from __future__ import annotations

import json
import logging
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from karta_api.cache.redis_geo import RedisGeoCache
from karta_api.db.community_repo import CommunityRepository
from karta_api.models.common import Coordinate
from karta_api.models.realtime import (
    CongestionLevel,
    CongestionSegment,
    HazardCategory,
    HazardRecord,
    HazardSeverity,
)
from karta_api.realtime.geo_filter import build_closure_exclusion_ring
from karta_api.routing.polyline import coords_to_linestring_wkt

logger = logging.getLogger(__name__)

# Speed cap (km/h) and base delay penalty (seconds) per hazard category & severity
HAZARD_TRAFFIC_IMPACT: dict[tuple[HazardCategory, HazardSeverity], tuple[int, float, CongestionLevel]] = {
    (HazardCategory.ROAD_CLOSURE, HazardSeverity.HIGH): (0, 1200.0, CongestionLevel.BLOCKED),
    (HazardCategory.ROAD_CLOSURE, HazardSeverity.MEDIUM): (0, 900.0, CongestionLevel.BLOCKED),
    (HazardCategory.ROAD_CLOSURE, HazardSeverity.LOW): (5, 480.0, CongestionLevel.BLOCKED),
    (HazardCategory.ACCIDENT, HazardSeverity.HIGH): (10, 480.0, CongestionLevel.HEAVY),
    (HazardCategory.ACCIDENT, HazardSeverity.MEDIUM): (24, 210.0, CongestionLevel.HEAVY),
    (HazardCategory.ACCIDENT, HazardSeverity.LOW): (40, 90.0, CongestionLevel.MODERATE),
    (HazardCategory.POLICE, HazardSeverity.HIGH): (30, 120.0, CongestionLevel.MODERATE),
    (HazardCategory.POLICE, HazardSeverity.MEDIUM): (50, 45.0, CongestionLevel.MODERATE),
    (HazardCategory.POLICE, HazardSeverity.LOW): (70, 15.0, CongestionLevel.MODERATE),
    (HazardCategory.ROAD_DEBRIS, HazardSeverity.HIGH): (25, 150.0, CongestionLevel.HEAVY),
    (HazardCategory.ROAD_DEBRIS, HazardSeverity.MEDIUM): (45, 60.0, CongestionLevel.MODERATE),
    (HazardCategory.ROAD_DEBRIS, HazardSeverity.LOW): (65, 25.0, CongestionLevel.MODERATE),
    (HazardCategory.HIDDEN_VEHICLE, HazardSeverity.HIGH): (35, 90.0, CongestionLevel.MODERATE),
    (HazardCategory.HIDDEN_VEHICLE, HazardSeverity.MEDIUM): (55, 45.0, CongestionLevel.MODERATE),
    (HazardCategory.HIDDEN_VEHICLE, HazardSeverity.LOW): (70, 20.0, CongestionLevel.MODERATE),
    (HazardCategory.POTHOLE, HazardSeverity.HIGH): (45, 30.0, CongestionLevel.MODERATE),
    (HazardCategory.POTHOLE, HazardSeverity.MEDIUM): (65, 15.0, CongestionLevel.MODERATE),
    (HazardCategory.POTHOLE, HazardSeverity.LOW): (80, 5.0, CongestionLevel.FREE),
}


@dataclass(frozen=True)
class TrafficObservation:
    osm_way_id: int
    speed_kmh: int
    valhalla_edge_id: int | None = None


@dataclass(frozen=True)
class DynamicCostingOverlay:
    exclude_locations: list[dict[str, float]]
    exclude_polygons: list[list[list[float]]]
    traffic_epoch: int
    active_closure_ids: list[str]


class TrafficWeightManager:
    """
    Two-Tier Real Valhalla Dynamic Costing & Live Congestion Manager:
      - Tier 1 (Always active): Stages live hazards & closures in Redis (`karta:traffic:closures`,
        `karta:traffic:speeds`, `karta:traffic:epoch`), injects active closures/blockages into
        Valhalla `/route` via native `exclude_locations` + `exclude_polygons`, invalidates stale
        route cache buckets via `traffic_epoch`, and computes per-route corridor delays and
        color-coded `congestion_segments` via PostGIS `ST_DWithin`.
      - Tier 2 (Optional mmap): When `/data/valhalla/traffic.tar` is initialized by stage 09,
        records directed edge speeds (`karta:traffic:edge_speeds`) for memory-mapped Valhalla
        `speed_types: ["current", ...]`.
    """

    def __init__(
        self,
        cache: RedisGeoCache,
        traffic_tar_path: Path | None = None,
    ) -> None:
        self._cache = cache
        self._traffic_tar_path = traffic_tar_path

    @property
    def traffic_tar_available(self) -> bool:
        return bool(self._traffic_tar_path and self._traffic_tar_path.exists())

    async def get_traffic_epoch(self) -> int:
        try:
            raw = await self._cache.client.get("karta:traffic:epoch")
            return int(raw) if raw else 0
        except Exception:
            return 0

    async def bump_traffic_epoch(self) -> int:
        try:
            return int(await self._cache.client.incr("karta:traffic:epoch"))
        except Exception:
            return 0

    async def record_observations(self, observations: list[TrafficObservation]) -> int:
        count = 0
        for obs in observations:
            await self._cache.record_traffic_probe_speed(obs.osm_way_id, obs.speed_kmh)
            if obs.valhalla_edge_id is not None:
                await self._cache.client.hset(
                    "karta:traffic:edge_speeds",
                    str(obs.valhalla_edge_id),
                    str(max(0, min(obs.speed_kmh, 140))),
                )
            count += 1
        return count

    async def get_all_observed_speeds(self) -> dict[int, int]:
        raw = await self._cache.client.hgetall("karta:traffic:speeds")
        return {int(k): int(v) for k, v in raw.items()}

    async def apply_hazard_weight(self, hazard: HazardRecord) -> int:
        """
        Feeds a newly reported/updated hazard into Redis traffic tables so subsequent
        Valhalla routes immediately reflect closures and congestion spikes.
        """
        speed_cap, delay_sec, level = HAZARD_TRAFFIC_IMPACT.get(
            (hazard.category, hazard.severity),
            (45, 45.0, CongestionLevel.MODERATE),
        )
        pipe = self._cache.client.pipeline(transaction=False)

        if hazard.osm_way_id is not None:
            pipe.hset("karta:traffic:speeds", str(hazard.osm_way_id), str(max(0, speed_cap)))
        if hazard.valhalla_edge_id is not None:
            pipe.hset("karta:traffic:edge_speeds", str(hazard.valhalla_edge_id), str(max(0, speed_cap)))

        # Closures and major accidents create Valhalla routing exclusions
        is_blocking = hazard.category == HazardCategory.ROAD_CLOSURE or (
            hazard.category == HazardCategory.ACCIDENT and hazard.severity == HazardSeverity.HIGH
        )
        if is_blocking:
            ring = build_closure_exclusion_ring(
                hazard.coordinate.lat,
                hazard.coordinate.lon,
                half_size_meters=24.0 if hazard.category == HazardCategory.ROAD_CLOSURE else 16.0,
            )
            pipe.hset(
                "karta:traffic:closures",
                hazard.id,
                json.dumps(
                    {
                        "id": hazard.id,
                        "category": hazard.category.value,
                        "severity": hazard.severity.value,
                        "lat": hazard.coordinate.lat,
                        "lon": hazard.coordinate.lon,
                        "ring": ring,
                        "delay_seconds": delay_sec,
                        "level": level.value,
                    }
                ),
            )
            pipe.geoadd(
                "karta:geo:closures",
                (hazard.coordinate.lon, hazard.coordinate.lat, hazard.id),
            )

        pipe.incr("karta:traffic:epoch")
        results = await pipe.execute()
        new_epoch = int(results[-1]) if results else 0
        logger.debug(
            "Applied Valhalla traffic weight for hazard=%s (%s/%s) blocking=%s epoch=%s",
            hazard.id,
            hazard.category.value,
            hazard.severity.value,
            is_blocking,
            new_epoch,
        )
        return new_epoch

    async def clear_hazard_weight(self, hazard_id: str, osm_way_id: int | None = None) -> int:
        pipe = self._cache.client.pipeline(transaction=False)
        pipe.hdel("karta:traffic:closures", hazard_id)
        pipe.zrem("karta:geo:closures", hazard_id)
        if osm_way_id is not None:
            pipe.hdel("karta:traffic:speeds", str(osm_way_id))
        pipe.incr("karta:traffic:epoch")
        results = await pipe.execute()
        return int(results[-1]) if results else 0

    async def build_dynamic_costing_overlay(
        self,
        *,
        origin: Coordinate,
        destination: Coordinate,
        waypoints: list[Coordinate] | None = None,
        community_repo: CommunityRepository | None = None,
        max_exclusions: int = 40,
    ) -> DynamicCostingOverlay:
        """
        Collects active road closures & severe blocking accidents inside the trip's
        bounding corridor (expanded by ~0.12 deg / ~13 km) to inject directly into
        Valhalla's `/route` request (`exclude_locations` + `exclude_polygons`).
        """
        pts = [origin, destination, *(waypoints or [])]
        min_lat = min(p.lat for p in pts) - 0.12
        max_lat = max(p.lat for p in pts) + 0.12
        min_lon = min(p.lon for p in pts) - 0.12
        max_lon = max(p.lon for p in pts) + 0.12

        epoch = await self.get_traffic_epoch()
        exclude_locs: list[dict[str, float]] = []
        exclude_polys: list[list[list[float]]] = []
        closure_ids: list[str] = []

        # Avoid excluding the exact origin or destination coordinate itself (Valhalla rejects unroutable endpoints)
        def _too_close_to_endpoint(lat: float, lon: float) -> bool:
            for ep in pts:
                if abs(ep.lat - lat) < 0.0012 and abs(ep.lon - lon) < 0.0012:
                    return True
            return False

        # 1. Fast Redis closures hash check
        raw_closures: dict[str, str] = {}
        try:
            raw_closures = await self._cache.client.hgetall("karta:traffic:closures")
        except Exception:
            raw_closures = {}

        for cid, raw in raw_closures.items():
            try:
                item = json.loads(raw)
                lat = float(item["lat"])
                lon = float(item["lon"])
            except Exception:
                continue
            if not (min_lat <= lat <= max_lat and min_lon <= lon <= max_lon):
                continue
            if _too_close_to_endpoint(lat, lon):
                continue
            closure_ids.append(cid)
            exclude_locs.append({"lat": lat, "lon": lon})
            if item.get("category") == HazardCategory.ROAD_CLOSURE.value and item.get("ring"):
                exclude_polys.append(item["ring"])
            if len(exclude_locs) >= max_exclusions:
                break

        # 2. If Redis closures were cold (e.g., after Redis restart), fallback cleanly to PostGIS
        if not closure_ids and community_repo is not None:
            try:
                pg_hazards = await community_repo.list_active_hazards_in_bbox(
                    min_lon=min_lon,
                    min_lat=min_lat,
                    max_lon=max_lon,
                    max_lat=max_lat,
                    categories=[HazardCategory.ROAD_CLOSURE, HazardCategory.ACCIDENT],
                    limit=max_exclusions,
                )
                for h in pg_hazards:
                    is_blocking = h.category == HazardCategory.ROAD_CLOSURE or (
                        h.category == HazardCategory.ACCIDENT and h.severity == HazardSeverity.HIGH
                    )
                    if not is_blocking or _too_close_to_endpoint(h.coordinate.lat, h.coordinate.lon):
                        continue
                    closure_ids.append(h.id)
                    exclude_locs.append({"lat": h.coordinate.lat, "lon": h.coordinate.lon})
                    if h.category == HazardCategory.ROAD_CLOSURE:
                        exclude_polys.append(
                            build_closure_exclusion_ring(h.coordinate.lat, h.coordinate.lon)
                        )
            except Exception as exc:
                logger.warning("PostGIS closure fallback failed: %s", exc)

        return DynamicCostingOverlay(
            exclude_locations=exclude_locs[:max_exclusions],
            exclude_polygons=exclude_polys[:15],
            traffic_epoch=epoch,
            active_closure_ids=closure_ids,
        )

    async def evaluate_route_traffic(
        self,
        *,
        coords: list[tuple[float, float]],
        community_repo: CommunityRepository | None,
    ) -> tuple[float, list[CongestionSegment], list[HazardRecord]]:
        """
        Intersects a decoded route polyline with active PostGIS community hazards to produce
        live traffic delay seconds, colored congestion segments for MapLibre, and hazards on route.
        """
        if len(coords) < 2 or community_repo is None:
            return (0.0, [], [])

        route_wkt = coords_to_linestring_wkt(coords)
        try:
            hits = await community_repo.list_active_hazards_along_route_wkt(route_wkt, buffer_m=65.0)
        except Exception as exc:
            logger.warning("Route hazard evaluation failed: %s", exc)
            return (0.0, [], [])

        if not hits:
            return (
                0.0,
                [
                    CongestionSegment(
                        start_fraction=0.0,
                        end_fraction=1.0,
                        severity=CongestionLevel.FREE,
                        speed_kmh=90,
                        delay_seconds=0.0,
                        label="Clear flow",
                    )
                ],
                [],
            )

        total_delay = 0.0
        segments: list[CongestionSegment] = []
        hazards_on_route: list[HazardRecord] = []

        for haz, frac, _cross_m in hits:
            speed_cap, base_delay, level = HAZARD_TRAFFIC_IMPACT.get(
                (haz.category, haz.severity),
                (50, 45.0, CongestionLevel.MODERATE),
            )
            # Weight delay slightly by community confidence score
            conf_mult = 0.8 + 0.4 * max(0.0, min(1.0, haz.confidence_score))
            delay_s = round(base_delay * conf_mult, 1)
            total_delay += delay_s

            # Highlight a visible congestion tail upstream of the hazard (~2-4% of route)
            tail = 0.035 if level in (CongestionLevel.HEAVY, CongestionLevel.BLOCKED) else 0.018
            s_frac = max(0.0, round(frac - tail, 4))
            e_frac = min(1.0, round(frac + 0.008, 4))
            if e_frac <= s_frac:
                e_frac = min(1.0, round(s_frac + 0.01, 4))

            segments.append(
                CongestionSegment(
                    start_fraction=s_frac,
                    end_fraction=e_frac,
                    severity=level,
                    speed_kmh=speed_cap,
                    delay_seconds=delay_s,
                    hazard_id=haz.id,
                    label=f"{haz.category.value.replace('_', ' ').title()}{' · ' + haz.road_ref if haz.road_ref else ''}",
                )
            )
            hazards_on_route.append(haz.model_copy(update={"on_active_route": True}))

        return (round(total_delay, 1), segments, hazards_on_route)

    @staticmethod
    def estimate_eta_impact_for_hazard(hazard: HazardRecord) -> tuple[int, float, CongestionLevel]:
        return HAZARD_TRAFFIC_IMPACT.get(
            (hazard.category, hazard.severity),
            (50, 45.0, CongestionLevel.MODERATE),
        )
