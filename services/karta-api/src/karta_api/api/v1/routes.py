from __future__ import annotations

import hashlib
import json
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException

from karta_api.deps import AppContainer, get_container
from karta_api.models.routing import (
    CandidateRoute,
    RouteLeg,
    RouteManeuver,
    RouteRequest,
    RouteResponse,
    RoutingProfileId,
    TollSavingsComparison,
)
from karta_api.models.tolls import TollSummary
from karta_api.routing.differentiation import differentiate_candidate_routes
from karta_api.routing.polyline import coords_to_linestring_wkt, decode_polyline6, encode_polyline6
from karta_api.routing.valhalla_client import ValhallaError
from karta_api.tolls.currency import format_currency_minor, format_multi_currency_display

router = APIRouter(prefix="/routes", tags=["routing"])
REGIONAL_TZ = ZoneInfo("Asia/Kuala_Lumpur")


def _cache_key(req: RouteRequest, departure_dt: datetime, traffic_epoch: int = 0) -> str:
    # Quantize departure time into 5-minute buckets so ERP schedules stay exact while caching hot routes
    bucket_min = (departure_dt.minute // 5) * 5
    bucket_ts = departure_dt.replace(minute=bucket_min, second=0, microsecond=0).isoformat()
    raw = json.dumps(
        {
            "o": [round(req.origin.lat, 5), round(req.origin.lon, 5)],
            "d": [round(req.destination.lat, 5), round(req.destination.lon, 5)],
            "w": [[round(w.lat, 5), round(w.lon, 5)] for w in req.waypoints],
            "p": req.profile.value,
            "vp": req.vehicle_profile.value,
            "rc": req.vehicle_registration_country,
            "pm": sorted(m.value for m in req.payment_methods),
            "at": req.avoid_tolls,
            "ah": req.avoid_highways,
            "af": req.avoid_ferries,
            "alt": req.alternates,
            "cmp": req.include_toll_free_comparison,
            "ts": bucket_ts,
            "lang": req.language,
            "te": traffic_epoch,
        },
        sort_keys=True,
    )
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]
    return f"karta:cache:route:{digest}"


async def _parse_trip_to_candidate(
    trip: dict[str, Any],
    route_index: int,
    profile_used: str,
    supports_tolls: bool,
    req: RouteRequest,
    departure_dt: datetime,
    c: AppContainer,
) -> CandidateRoute:
    raw_legs = trip.get("legs", [])
    parsed_legs: list[RouteLeg] = []
    combined_coords: list[tuple[float, float]] = []

    for leg in raw_legs:
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
                toll=False,
                highway=bool(m.get("highway", False)),
                travel_mode=m.get("travel_mode", "drive"),
                transit_info=m.get("transit_info"),
            )
            for m in leg.get("maneuvers", [])
        ]
        leg_summary = leg.get("summary", {})
        parsed_legs.append(
            RouteLeg(
                distance_km=round(float(leg_summary.get("length", 0.0)), 3),
                duration_seconds=round(float(leg_summary.get("time", 0.0)), 1),
                shape_polyline6=shape,
                maneuvers=maneuvers,
            )
        )

    summary = trip.get("summary", {})
    total_km = round(float(summary.get("length", 0.0)), 3)
    base_sec = round(float(summary.get("time", 0.0)), 1)

    delay_sec, congestion_segments, hazards_on_route = await c.traffic_manager.evaluate_route_traffic(
        coords=combined_coords,
        community_repo=c.community_repo,
    )
    total_sec = round(base_sec + delay_sec, 1)

    countries_crossed: list[str] = []
    toll_summary = TollSummary(has_tolls=False, display_total="")

    if len(combined_coords) >= 2:
        route_wkt = coords_to_linestring_wkt(combined_coords)
        countries_crossed = await c.toll_repo.countries_crossed_by_route_wkt(route_wkt)

    has_tolls_flag = False
    has_highways_flag = bool(summary.get("has_highway", False))
    label = f"{profile_used} ({total_km:.1f} km, {int(round(total_sec / 60))} min)"

    return CandidateRoute(
        route_index=route_index,
        profile_used=profile_used,
        summary_label=label,
        distance_km=total_km,
        duration_seconds=total_sec,
        baseline_duration_seconds=base_sec,
        live_traffic_delay_seconds=delay_sec,
        has_toll_roads=has_tolls_flag,
        has_highways=has_highways_flag,
        countries_crossed=countries_crossed,
        legs=parsed_legs,
        tolls=toll_summary,
        congestion_segments=congestion_segments,
        active_hazards_on_route=hazards_on_route,
    )


@router.post("", response_model=RouteResponse)
async def compute_route(
    req: RouteRequest,
    c: AppContainer = Depends(get_container),
) -> RouteResponse:
    departure_dt = req.departure_time or datetime.now(tz=REGIONAL_TZ)
    if departure_dt.tzinfo is None:
        departure_dt = departure_dt.replace(tzinfo=REGIONAL_TZ)

    # Enforce single-destination navigation (start -> destination only, zero intermediate stops)
    # and disable toll fee computation/comparison.
    if req.waypoints or req.include_toll_free_comparison or req.avoid_tolls or req.profile == RoutingProfileId.DRIVE_AVOID_TOLLS:
        req = req.model_copy(
            update={
                "waypoints": [],
                "include_toll_free_comparison": False,
                "avoid_tolls": False,
                "profile": (
                    RoutingProfileId.DRIVE_FASTEST
                    if req.profile == RoutingProfileId.DRIVE_AVOID_TOLLS
                    else req.profile
                ),
            }
        )

    # Query active crowdsourced closures & current traffic epoch before checking route cache
    overlay = await c.traffic_manager.build_dynamic_costing_overlay(
        origin=req.origin,
        destination=req.destination,
        waypoints=[],
        community_repo=c.community_repo,
    )
    ckey = _cache_key(req, departure_dt, traffic_epoch=overlay.traffic_epoch)
    cached_payload = await c.redis_cache.get_cached_json(ckey)
    if cached_payload is not None:
        cached_payload["cached"] = True
        return RouteResponse.model_validate(cached_payload)

    origin_country = await c.spatial_repo.resolve_country_at_point(req.origin.lat, req.origin.lon)
    dest_country = await c.spatial_repo.resolve_country_at_point(
        req.destination.lat, req.destination.lon
    )

    profile_meta = c.profiles.get_profile(req.profile)
    supports_tolls = bool(profile_meta.get("supports_tolls", False))
    valhalla_payload = c.profiles.build_valhalla_route_payload(
        req,
        exclude_locations=overlay.exclude_locations,
        exclude_polygons=overlay.exclude_polygons,
    )

    try:
        raw_resp = await c.valhalla.route(valhalla_payload)
    except ValhallaError as exc:
        # If tight exclusion polygon made an endpoint unreachable, retry cleanly without exclusions
        if overlay.exclude_locations or overlay.exclude_polygons:
            try:
                fallback_payload = c.profiles.build_valhalla_route_payload(req)
                raw_resp = await c.valhalla.route(fallback_payload)
            except ValhallaError as exc2:
                raise HTTPException(
                    status_code=503 if exc2.status_code >= 500 else 422,
                    detail={"engine": "valhalla", "error": exc2.message, "error_code": exc2.error_code},
                ) from exc2
        else:
            raise HTTPException(
                status_code=503 if exc.status_code >= 500 else 422,
                detail={"engine": "valhalla", "error": exc.message, "error_code": exc.error_code},
            ) from exc

    trips: list[tuple[dict[str, Any], str]] = [(raw_resp["trip"], req.profile.value)]
    for alt in raw_resp.get("alternates", []):
        if "trip" in alt:
            trips.append((alt["trip"], req.profile.value))

    candidates: list[CandidateRoute] = []
    for idx, (trip_obj, prof_name) in enumerate(trips):
        cand = await _parse_trip_to_candidate(
            trip=trip_obj,
            route_index=idx,
            profile_used=prof_name,
            supports_tolls=supports_tolls,
            req=req,
            departure_dt=departure_dt,
            c=c,
        )
        candidates.append(cand)

    # Automatic toll-free comparison when driving with tolls enabled
    comparison: TollSavingsComparison | None = None
    if (
        supports_tolls
        and req.include_toll_free_comparison
        and not req.avoid_tolls
        and req.profile != RoutingProfileId.DRIVE_AVOID_TOLLS
        and candidates
        and candidates[0].tolls.has_tolls
    ):
        tf_payload = c.profiles.build_valhalla_route_payload(
            req,
            override_profile=RoutingProfileId.DRIVE_AVOID_TOLLS,
            alternates_override=0,
            exclude_locations=overlay.exclude_locations,
            exclude_polygons=overlay.exclude_polygons,
        )
        try:
            tf_raw = await c.valhalla.route(tf_payload)
            tf_cand = await _parse_trip_to_candidate(
                trip=tf_raw["trip"],
                route_index=len(candidates),
                profile_used=RoutingProfileId.DRIVE_AVOID_TOLLS.value,
                supports_tolls=True,
                req=req,
                departure_dt=departure_dt,
                c=c,
            )
            primary = candidates[0]
            tf_totals = {t.currency_code: t.amount_minor for t in tf_cand.tolls.totals_by_currency}
            savings = []
            for pt in primary.tolls.totals_by_currency:
                diff_minor = pt.amount_minor - tf_totals.get(pt.currency_code, 0)
                if diff_minor > 0:
                    savings.append(format_currency_minor(pt.currency_code, diff_minor))

            if savings:
                candidates.append(tf_cand)
                extra_sec = round(tf_cand.duration_seconds - primary.duration_seconds, 1)
                extra_km = round(tf_cand.distance_km - primary.distance_km, 2)
                extra_min = int(round(extra_sec / 60.0))
                sign = "+" if extra_min >= 0 else ""
                savings_str = format_multi_currency_display(savings)
                comparison = TollSavingsComparison(
                    toll_free_route_index=tf_cand.route_index,
                    extra_duration_seconds=extra_sec,
                    extra_distance_km=extra_km,
                    savings_by_currency=savings,
                    summary_text=f"Save {savings_str} ({sign}{extra_min} min)",
                )
        except ValhallaError:
            pass

    # Apply human-friendly route differentiation tags ('Fastest • 38 min', 'Cheapest Toll • Save RM 4.20', etc.)
    differentiated = differentiate_candidate_routes(candidates)

    response = RouteResponse(
        origin_country=origin_country,
        destination_country=dest_country,
        departure_time=departure_dt,
        routes=differentiated,
        toll_free_comparison=comparison,
        cached=False,
        traffic_epoch=overlay.traffic_epoch,
        exclusions_applied=len(overlay.active_closure_ids),
    )
    await c.redis_cache.set_cached_json(
        ckey,
        response.model_dump(mode="json"),
        ttl_seconds=c.settings.route_cache_ttl_seconds,
    )
    return response
