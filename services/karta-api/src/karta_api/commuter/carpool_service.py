from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from karta_api.db.community_repo import CommunityRepository
from karta_api.db.spatial_repo import SpatialRepository
from karta_api.models.commuter import (
    CarpoolMatchCandidate,
    CarpoolMatchRecord,
    CarpoolMatchRequestCreate,
    CarpoolOfferCreateRequest,
    CarpoolOfferPublic,
    CarpoolSearchRequest,
)
from karta_api.models.routing import RouteRequest, RoutingProfileId
from karta_api.routing.polyline import coords_to_linestring_wkt, decode_polyline6, encode_polyline6
from karta_api.routing.profiles import CostingProfileRegistry
from karta_api.routing.valhalla_client import ValhallaClient
from karta_api.tolls.engine import RegionalTollEngine

REGIONAL_TZ = ZoneInfo("Asia/Kuala_Lumpur")

# Regional fuel cost per km in minor currency units (for fair commuter cost-sharing estimate)
FUEL_COST_MINOR_PER_KM: dict[str, tuple[int, str]] = {
    "MY": (18, "MYR"),  # ~RM 0.18/km at RON95 RM 2.05/L
    "SG": (24, "SGD"),  # ~$0.24/km at Octane 95 $2.85/L
    "BN": (6, "BND"),   # ~B$0.06/km at RON97 B$0.53/L
}


class PrivacyCarpoolService:
    """
    Privacy-first commuter carpool matching engine:
      - Snaps all origins/destinations to 500m public privacy zones + public POI landmarks.
      - Computes real Valhalla corridor geometry for directional PostGIS overlap matching.
      - Splits estimated regional fuel + PostGIS toll costs fairly in MYR / SGD / BND.
    """

    def __init__(
        self,
        *,
        community_repo: CommunityRepository,
        spatial_repo: SpatialRepository,
        valhalla: ValhallaClient,
        profiles: CostingProfileRegistry,
        toll_engine: RegionalTollEngine,
    ) -> None:
        self._community = community_repo
        self._spatial = spatial_repo
        self._valhalla = valhalla
        self._profiles = profiles
        self._toll_engine = toll_engine

    async def create_offer(self, req: CarpoolOfferCreateRequest) -> CarpoolOfferPublic:
        # 1. Privacy fuzzing: never persist raw home/work endpoints
        origin_zone, origin_landmark = await self._community.snap_to_public_privacy_zone(
            req.origin.lat, req.origin.lon
        )
        dest_zone, dest_landmark = await self._community.snap_to_public_privacy_zone(
            req.destination.lat, req.destination.lon
        )

        # 2. Compute real Valhalla route between the fuzzed public meeting zones
        route_req = RouteRequest(
            origin=origin_zone,
            destination=dest_zone,
            profile=RoutingProfileId.DRIVE_FASTEST,
            alternates=0,
            include_toll_free_comparison=False,
            departure_time=req.departure_at,
        )
        val_payload = self._profiles.build_valhalla_route_payload(route_req, alternates_override=0)
        raw = await self._valhalla.route(val_payload)
        trip = raw["trip"]
        summary = trip.get("summary", {})
        dist_km = round(float(summary.get("length", 0.0)), 2)
        dur_sec = float(summary.get("time", 0.0))

        coords: list[tuple[float, float]] = []
        for leg in trip.get("legs", []):
            if leg.get("shape"):
                coords.extend(decode_polyline6(leg["shape"]))

        poly6 = encode_polyline6(coords) if coords else trip["legs"][0]["shape"]
        route_wkt = coords_to_linestring_wkt(coords)

        cc_ctx = await self._spatial.resolve_country_at_point(origin_zone.lat, origin_zone.lon)
        cc = cc_ctx.iso_a2 if cc_ctx else "MY"
        per_km_minor, cur_code = FUEL_COST_MINOR_PER_KM.get(cc, (18, "MYR"))

        # 3. Compute real pre-route toll cost and split across seats + driver
        toll_minor = 0
        try:
            dep = req.departure_at if req.departure_at.tzinfo else req.departure_at.replace(tzinfo=REGIONAL_TZ)
            toll = await self._toll_engine.calculate_route_tolls(
                polyline6=poly6,
                duration_seconds=dur_sec,
                departure_time=dep,
            )
            for t in toll.totals_by_currency:
                if t.currency_code == cur_code:
                    toll_minor += t.amount_minor
        except Exception:
            pass

        total_trip_minor = int(round(dist_km * per_km_minor)) + toll_minor
        # Cost-share per rider (non-profit split across 2+ occupants)
        split_minor = max(100, int(round(total_trip_minor / max(2, min(req.seats_total + 1, 4)))))

        return await self._community.create_carpool_offer(
            driver_token=req.driver_token,
            driver_alias=req.driver_alias,
            verified_badge=req.verified_badge,
            country_code=cc,
            origin_zone=origin_zone,
            origin_landmark=origin_landmark,
            dest_zone=dest_zone,
            dest_landmark=dest_landmark,
            route_wkt=route_wkt,
            route_polyline6=poly6,
            route_distance_km=dist_km,
            departure_at=req.departure_at,
            flexibility_minutes=req.flexibility_minutes,
            seats_total=req.seats_total,
            estimated_split_minor=split_minor,
            currency_code=cur_code,
            notes=req.notes,
        )

    async def search_matches(self, req: CarpoolSearchRequest) -> list[CarpoolMatchCandidate]:
        pickup_zone, pickup_landmark = await self._community.snap_to_public_privacy_zone(
            req.pickup.lat, req.pickup.lon
        )
        dropoff_zone, dropoff_landmark = await self._community.snap_to_public_privacy_zone(
            req.dropoff.lat, req.dropoff.lon
        )
        return await self._community.search_matching_carpool_offers(
            rider_token=req.rider_token,
            pickup_zone=pickup_zone,
            pickup_landmark=pickup_landmark,
            dropoff_zone=dropoff_zone,
            dropoff_landmark=dropoff_landmark,
            departure_at=req.departure_at,
            max_detour_meters=req.max_detour_meters,
            time_window_minutes=req.time_window_minutes,
        )

    async def request_match(
        self, offer_id: str, req: CarpoolMatchRequestCreate
    ) -> CarpoolMatchRecord | None:
        pickup_zone, pickup_landmark = await self._community.snap_to_public_privacy_zone(
            req.pickup.lat, req.pickup.lon
        )
        dropoff_zone, dropoff_landmark = await self._community.snap_to_public_privacy_zone(
            req.dropoff.lat, req.dropoff.lon
        )
        return await self._community.request_carpool_match(
            offer_id=offer_id,
            rider_token=req.rider_token,
            rider_alias=req.rider_alias,
            pickup_zone=pickup_zone,
            pickup_landmark=pickup_landmark,
            dropoff_zone=dropoff_zone,
            dropoff_landmark=dropoff_landmark,
            rendezvous_note=req.rendezvous_note,
        )
