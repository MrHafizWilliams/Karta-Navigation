from __future__ import annotations

import math
import time
from collections.abc import Sequence

from karta_api.models.common import Coordinate
from karta_api.models.routing import PrefetchTileCoord, TilePrefetchRequest, TilePrefetchResponse
from karta_api.routing.polyline import decode_polyline6, haversine_meters, initial_bearing_deg

_EARTH_RADIUS_M = 6_371_008.8


def lat_lon_to_tile_xy(lat: float, lon: float, zoom: int) -> tuple[int, int]:
    """Converts WGS 84 (lat, lon) into Slippy-Map Web Mercator (x, y) tile coordinates."""
    clamped_lat = max(-85.05112878, min(85.05112878, lat))
    lat_rad = math.radians(clamped_lat)
    n = 1 << zoom
    x = int((lon + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return (max(0, min(n - 1, x)), max(0, min(n - 1, y)))


def project_point_meters(lat: float, lon: float, bearing_deg: float, distance_m: float) -> tuple[float, float]:
    """Great-circle forward projection in meters."""
    ang = distance_m / _EARTH_RADIUS_M
    brg = math.radians(bearing_deg)
    lat1 = math.radians(lat)
    lon1 = math.radians(lon)

    lat2 = math.asin(
        math.sin(lat1) * math.cos(ang) + math.cos(lat1) * math.sin(ang) * math.cos(brg)
    )
    lon2 = lon1 + math.atan2(
        math.sin(brg) * math.sin(ang) * math.cos(lat1),
        math.cos(ang) - math.sin(lat1) * math.sin(lat2),
    )
    return (math.degrees(lat2), ((math.degrees(lon2) + 540.0) % 360.0) - 180.0)


def adaptive_lookahead_and_zooms(speed_kmh: float) -> tuple[float, list[int]]:
    """
    Returns (lookahead_km, zoom_levels) calibrated for highway vs urban speeds
    so pitched 3D MapLibre cameras never encounter late tile pop-in.
    """
    if speed_kmh >= 90.0:
        return (14.0, [12, 13, 14])
    if speed_kmh >= 55.0:
        return (7.0, [13, 14, 15])
    return (3.0, [14, 15])


def _nearest_vertex_index(coords: Sequence[tuple[float, float]], target: Coordinate) -> int:
    best_i = 0
    best_d = float("inf")
    for i, (lat, lon) in enumerate(coords):
        d = haversine_meters(lat, lon, target.lat, target.lon)
        if d < best_d:
            best_d = d
            best_i = i
    return best_i


def build_predictive_tile_plan(
    req: TilePrefetchRequest,
    pmtiles_public_url: str,
) -> TilePrefetchResponse:
    """
    Computes an ordered, deduplicated list of vector tiles `(z, x, y)` covering:
      - Priority 0: Immediate upcoming maneuvers + 1-tile radial next-turn neighborhood
      - Priority 1: Speed-adaptive active route corridor lookahead + lateral horizon buffer
      - Priority 2: Probable alternate-turn / missed-exit recovery fan-out (±60° from turns)
    """
    t0 = time.perf_counter()
    coords = decode_polyline6(req.polyline6)
    lookahead_km, default_zooms = adaptive_lookahead_and_zooms(req.current_speed_kmh)
    zooms = sorted({z for z in (req.zoom_levels or default_zooms) if 8 <= z <= 16})
    if not zooms:
        zooms = default_zooms

    if len(coords) < 2:
        return TilePrefetchResponse(
            lookahead_km=lookahead_km,
            zoom_levels=zooms,
            tile_count=0,
            tiles=[],
            planning_ms=round((time.perf_counter() - t0) * 1000.0, 2),
        )

    start_idx = _nearest_vertex_index(coords, req.current_position) if req.current_position else 0
    max_lookahead_m = lookahead_km * 1000.0
    base_url = pmtiles_public_url.rstrip("/")
    archive = req.region_archive.strip("/")

    selected: dict[tuple[int, int, int], PrefetchTileCoord] = {}

    def _add_tile(z: int, x: int, y: int, priority: int, reason: str) -> None:
        n = 1 << z
        if x < 0 or y < 0 or x >= n or y >= n:
            return
        key = (z, x, y)
        existing = selected.get(key)
        if existing is None or priority < existing.priority:
            selected[key] = PrefetchTileCoord(
                z=z,
                x=x,
                y=y,
                priority=priority,
                reason=reason,
                tile_url=f"{base_url}/{archive}/{z}/{x}/{y}.mvt",
            )

    # 1. Priority 0 & 2: Upcoming maneuver clusters + probable alternate-turn fan-out
    detail_zoom = min(15, max(zooms))
    for m_coord in req.maneuver_coordinates[:4]:
        cx, cy = lat_lon_to_tile_xy(m_coord.lat, m_coord.lon, detail_zoom)
        _add_tile(detail_zoom, cx, cy, 0, "next_turn")
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx != 0 or dy != 0:
                    _add_tile(detail_zoom, cx + dx, cy + dy, 2, "alternate_turn")

    # 2. Priority 1: Active corridor progression + lateral horizon buffer for 3D pitch
    accum_m = 0.0
    sample_step_m = 450.0 if req.current_speed_kmh >= 85.0 else 250.0
    next_sample_m = 0.0

    for i in range(start_idx, len(coords) - 1):
        lat1, lon1 = coords[i]
        lat2, lon2 = coords[i + 1]
        seg_m = haversine_meters(lat1, lon1, lat2, lon2)
        if seg_m < 1.0:
            continue

        brg = initial_bearing_deg(lat1, lon1, lat2, lon2)
        while next_sample_m <= accum_m + seg_m and next_sample_m <= max_lookahead_m:
            frac = (next_sample_m - accum_m) / seg_m
            s_lat = lat1 + (lat2 - lat1) * frac
            s_lon = lon1 + (lon2 - lon1) * frac
            prio = 0 if next_sample_m <= 2500.0 else 1

            for z in zooms:
                tx, ty = lat_lon_to_tile_xy(s_lat, s_lon, z)
                _add_tile(z, tx, ty, prio, "corridor")

            # Lateral horizon tiles (~900m left/right) for pitched 3D camera frustum
            lat_z = zooms[-1]
            for side_offset in (-90.0, 90.0):
                b_lat, b_lon = project_point_meters(s_lat, s_lon, (brg + side_offset) % 360.0, 900.0)
                bx, by = lat_lon_to_tile_xy(b_lat, b_lon, lat_z)
                _add_tile(lat_z, bx, by, 1, "horizon_buffer")

            next_sample_m += sample_step_m

        # Detect sharp bearing change (upcoming junction / highway ramp) for alternate-turn fan-out
        if i + 2 < len(coords) and accum_m <= 6000.0:
            next_brg = initial_bearing_deg(lat2, lon2, coords[i + 2][0], coords[i + 2][1])
            turn_delta = abs((next_brg - brg + 180.0) % 360.0 - 180.0)
            if turn_delta >= 28.0:
                tx, ty = lat_lon_to_tile_xy(lat2, lon2, detail_zoom)
                _add_tile(detail_zoom, tx, ty, 0, "next_turn")
                for fan_offset in (-60.0, 60.0):
                    f_lat, f_lon = project_point_meters(lat2, lon2, (brg + fan_offset) % 360.0, 1200.0)
                    fx, fy = lat_lon_to_tile_xy(f_lat, f_lon, detail_zoom)
                    _add_tile(detail_zoom, fx, fy, 2, "alternate_turn")

        accum_m += seg_m
        if accum_m > max_lookahead_m:
            break

    ordered = sorted(selected.values(), key=lambda t: (t.priority, t.z, t.x, t.y))[: req.max_tiles]
    elapsed_ms = round((time.perf_counter() - t0) * 1000.0, 2)
    return TilePrefetchResponse(
        lookahead_km=lookahead_km,
        zoom_levels=zooms,
        tile_count=len(ordered),
        tiles=ordered,
        cached=False,
        planning_ms=elapsed_ms,
    )
