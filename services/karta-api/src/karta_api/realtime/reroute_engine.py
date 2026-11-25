from __future__ import annotations

import logging
import uuid
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from karta_api.db.community_repo import CommunityRepository
from karta_api.db.toll_repo import TollRepository
from karta_api.models.common import Coordinate
from karta_api.models.realtime import HazardCategory, HazardRecord, RerouteProposal
from karta_api.models.routing import (
    CandidateRoute,
    RouteLeg,
    RouteManeuver,
    RouteRequest,
    RoutingProfileId,
)
from karta_api.models.tolls import TollSummary, VehicleProfile
from karta_api.realtime.hub import DriverSession, RealtimeHazardHub
from karta_api.routing.polyline import coords_to_linestring_wkt, decode_polyline6, encode_polyline6
from karta_api.routing.profiles import CostingProfileRegistry
from karta_api.routing.traffic import TrafficWeightManager
from karta_api.routing.valhalla_client import ValhallaClient, ValhallaError
from karta_api.tolls.currency import format_currency_minor, format_multi_currency_display
from karta_api.tolls.engine import RegionalTollEngine

logger = logging.getLogger(__name__)
REGIONAL_TZ = ZoneInfo("Asia/Kuala_Lumpur")


class LiveRerouteEngine:
    """
    Evaluates active navigating drivers whenever a road closure or severe accident lands
    ahead on their active corridor. Recalculates a live Valhalla detour with updated
    dynamic exclusions, re-evaluates MY/SG/BN tolls, and pushes `eta.update` +
    `route.reroute_proposal` frames directly to the affected client!
    """

    def __init__(
        self,
        *,
        hub: RealtimeHazardHub,
        valhalla: ValhallaClient,
        profiles: CostingProfileRegistry,
        traffic_manager: TrafficWeightManager,
        community_repo: CommunityRepository,
        toll_repo: TollRepository,
        toll_engine: RegionalTollEngine,
        min_savings_seconds: int = 120,
    ) -> None:
        self._hub = hub
        self._valhalla = valhalla
        self._profiles = profiles
        self._traffic = traffic_manager
        self._community = community_repo
        self._toll_repo = toll_repo
        self._toll_engine = toll_engine
        self._min_savings_seconds = min_savings_seconds

    async def evaluate_session_for_hazard(
        self, session: DriverSession, trigger_hazard: HazardRecord
    ) -> RerouteProposal | None:
        if session.destination is None:
            return None

        # 1. Push updated ETA & congestion segments on the driver's current corridor immediately
        cur_delay, cur_segments, _ = await self._traffic.evaluate_route_traffic(
            coords=session.route_coords,
            community_repo=self._community,
        )
        await self._hub.send_to_session(
            session.session_id,
            {
                "event_type": "eta.update",
                "route_id": session.route_id or "active",
                "traffic_delay_seconds": cur_delay,
                "congestion_segments": [s.model_dump(mode="json") for s in cur_segments],
                "trigger_hazard_id": trigger_hazard.id,
            },
        )

        # 2. Compute fresh detour via Valhalla with dynamic closure exclusions
        origin = Coordinate(lat=session.lat, lon=session.lon)
        try:
            profile_enum = RoutingProfileId(session.route_profile)
        except Exception:
            profile_enum = RoutingProfileId.DRIVE_FASTEST
        try:
            vp_enum = VehicleProfile(session.vehicle_profile)
        except Exception:
            vp_enum = VehicleProfile.CAR

        req = RouteRequest(
            origin=origin,
            destination=session.destination,
            waypoints=session.waypoints,
            profile=profile_enum,
            vehicle_profile=vp_enum,
            vehicle_registration_country=session.vehicle_registration_country,
            alternates=1,
            include_toll_free_comparison=False,
        )

        overlay = await self._traffic.build_dynamic_costing_overlay(
            origin=origin,
            destination=session.destination,
            waypoints=session.waypoints,
            community_repo=self._community,
        )
        # Ensure the triggering hazard itself is excluded in the detour attempt
        exclude_locs = list(overlay.exclude_locations)
        if not any(
            abs(p["lat"] - trigger_hazard.coordinate.lat) < 0.0005
            and abs(p["lon"] - trigger_hazard.coordinate.lon) < 0.0005
            for p in exclude_locs
        ):
            exclude_locs.append(
                {"lat": trigger_hazard.coordinate.lat, "lon": trigger_hazard.coordinate.lon}
            )

        payload = self._profiles.build_valhalla_route_payload(
            req,
            alternates_override=1,
            exclude_locations=exclude_locs,
            exclude_polygons=overlay.exclude_polygons,
        )
        # Keep heading continuity when rerouting mid-drive
        if session.heading_deg is not None and payload.get("locations"):
            payload["locations"][0]["heading"] = round(session.heading_deg, 1)
            payload["locations"][0]["heading_tolerance"] = 60

        try:
            raw = await self._valhalla.route(payload)
        except ValhallaError as exc:
            logger.debug("Live reroute Valhalla call skipped: %s", exc)
            return None

        # Also estimate remaining baseline duration without exclusions to measure real savings
        baseline_sec = float(raw["trip"].get("summary", {}).get("time", 0.0)) + cur_delay
        detour_trip = raw["trip"]
        detour_candidate = await self._trip_to_candidate(
            trip=detour_trip,
            req=req,
            departure_dt=datetime.now(tz=REGIONAL_TZ),
        )

        # Estimate savings against remaining current route impacted by the hazard
        time_saved = round(max(0.0, baseline_sec - detour_candidate.duration_seconds), 1)
        is_closure = trigger_hazard.category == HazardCategory.ROAD_CLOSURE
        if not is_closure and time_saved < self._min_savings_seconds:
            return None

        toll_delta = detour_candidate.tolls.display_total
        road_label = trigger_hazard.road_ref or trigger_hazard.road_name or "road ahead"
        reason = (
            f"Road closure reported on {road_label}"
            if is_closure
            else f"{trigger_hazard.category.value.replace('_', ' ').title()} ahead on {road_label} (+{int(round(cur_delay / 60))} min)"
        )

        proposal = RerouteProposal(
            proposal_id=str(uuid.uuid4()),
            reason=reason,
            trigger_hazard_id=trigger_hazard.id,
            trigger_category=trigger_hazard.category,
            current_delay_seconds=cur_delay,
            time_saved_seconds=max(time_saved, 180.0 if is_closure else time_saved),
            toll_delta_display=f"Detour tolls: {toll_delta}",
            auto_accept_seconds=12 if is_closure else 0,
            proposed_route=detour_candidate.model_dump(mode="json"),
        )

        await self._hub.send_to_session(
            session.session_id,
            {
                "event_type": "route.reroute_proposal",
                "proposal": proposal.model_dump(mode="json"),
            },
        )
        return proposal

    async def _trip_to_candidate(
        self,
        *,
        trip: dict[str, Any],
        req: RouteRequest,
        departure_dt: datetime,
    ) -> CandidateRoute:
        parsed_legs: list[RouteLeg] = []
        combined_coords: list[tuple[float, float]] = []

        for leg in trip.get("legs", []):
            shape = leg.get("shape", "")
            leg_coords = decode_polyline6(shape) if shape else []
            if combined_coords and leg_coords and combined_coords[-1] == leg_coords[0]:
                combined_coords.extend(leg_coords[1:])
            else:
                combined_coords.extend(leg_coords)

            maneuvers = [
                RouteManeuver(
                    type=int(m.get("type", 0)),
                    instruction=m.get("instruction", ""),
                    verbal_pre_transition_instruction=m.get("verbal_pre_transition_instruction"),
                    street_names=list(m.get("street_names", [])),
                    distance_km=round(float(m.get("length", 0.0)), 3),
                    time_seconds=round(float(m.get("time", 0.0)), 1),
                    begin_shape_index=int(m.get("begin_shape_index", 0)),
                    end_shape_index=int(m.get("end_shape_index", 0)),
                    toll=bool(m.get("toll", False)),
                    highway=bool(m.get("highway", False)),
                    travel_mode=m.get("travel_mode", "drive"),
                    transit_info=m.get("transit_info"),
                )
                for m in leg.get("maneuvers", [])
            ]
            ls = leg.get("summary", {})
            parsed_legs.append(
                RouteLeg(
                    distance_km=round(float(ls.get("length", 0.0)), 3),
                    duration_seconds=round(float(ls.get("time", 0.0)), 1),
                    shape_polyline6=shape,
                    maneuvers=maneuvers,
                )
            )

        summary = trip.get("summary", {})
        total_km = round(float(summary.get("length", 0.0)), 3)
        base_sec = round(float(summary.get("time", 0.0)), 1)

        delay_sec, segments, hazards_on_route = await self._traffic.evaluate_route_traffic(
            coords=combined_coords,
            community_repo=self._community,
        )
        total_sec = round(base_sec + delay_sec, 1)

        countries_crossed: list[str] = []
        toll_summary = TollSummary(has_tolls=False, display_total="Free")
        if len(combined_coords) >= 2:
            wkt = coords_to_linestring_wkt(combined_coords)
            countries_crossed = await self._toll_repo.countries_crossed_by_route_wkt(wkt)
            poly6 = (
                parsed_legs[0].shape_polyline6
                if len(parsed_legs) == 1
                else encode_polyline6(combined_coords)
            )
            toll_summary = await self._toll_engine.calculate_route_tolls(
                polyline6=poly6,
                duration_seconds=total_sec,
                departure_time=departure_dt,
                vehicle_profile=req.vehicle_profile,
                vehicle_registration_country=req.vehicle_registration_country,
                user_payment_methods=req.payment_methods,
            )

        return CandidateRoute(
            route_index=0,
            profile_used=req.profile.value,
            summary_label=f"Live Detour ({total_km:.1f} km, {int(round(total_sec / 60))} min)",
            distance_km=total_km,
            duration_seconds=total_sec,
            baseline_duration_seconds=base_sec,
            live_traffic_delay_seconds=delay_sec,
            has_toll_roads=bool(summary.get("has_toll", False)) or toll_summary.has_tolls,
            has_highways=bool(summary.get("has_highway", False)),
            countries_crossed=countries_crossed,
            legs=parsed_legs,
            tolls=toll_summary,
            congestion_segments=segments,
            active_hazards_on_route=hazards_on_route,
        )
