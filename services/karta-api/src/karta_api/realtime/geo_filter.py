from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

from karta_api.models.realtime import HazardCategory, HazardRecord
from karta_api.routing.polyline import angular_diff_deg, haversine_meters, initial_bearing_deg

_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
_BASE32_MAP = {ch: idx for idx, ch in enumerate(_BASE32)}

CATEGORY_RADIUS_MULTIPLIER: dict[HazardCategory, float] = {
    HazardCategory.ROAD_CLOSURE: 1.60,
    HazardCategory.ACCIDENT: 1.40,
    HazardCategory.POLICE: 1.10,
    HazardCategory.HIDDEN_VEHICLE: 0.85,
    HazardCategory.ROAD_DEBRIS: 0.85,
    HazardCategory.POTHOLE: 0.65,
}

CATEGORY_DEFAULT_TTL_MINUTES: dict[HazardCategory, int] = {
    HazardCategory.POLICE: 45,
    HazardCategory.ACCIDENT: 60,
    HazardCategory.POTHOLE: 1440,
    HazardCategory.HIDDEN_VEHICLE: 30,
    HazardCategory.ROAD_DEBRIS: 45,
    HazardCategory.ROAD_CLOSURE: 180,
}

# Immediate proximity ring where hazards are always relevant regardless of bearing (junctions/urban turns)
IMMEDIATE_PROXIMITY_RING_M = 250.0
FORWARD_CONE_HALF_ANGLE_DEG = 65.0
CARRIAGEWAY_OPPOSITE_THRESHOLD_DEG = 90.0


def encode_geohash(lat: float, lon: float, precision: int = 5) -> str:
    """Encodes WGS 84 (lat, lon) into a standard base32 geohash string."""
    lat_interval = [-90.0, 90.0]
    lon_interval = [-180.0, 180.0]
    geohash: list[str] = []
    bits = [16, 8, 4, 2, 1]
    bit = 0
    ch = 0
    even = True

    while len(geohash) < precision:
        if even:
            mid = (lon_interval[0] + lon_interval[1]) / 2.0
            if lon >= mid:
                ch |= bits[bit]
                lon_interval[0] = mid
            else:
                lon_interval[1] = mid
        else:
            mid = (lat_interval[0] + lat_interval[1]) / 2.0
            if lat >= mid:
                ch |= bits[bit]
                lat_interval[0] = mid
            else:
                lat_interval[1] = mid
        even = not even
        if bit < 4:
            bit += 1
        else:
            geohash.append(_BASE32[ch])
            bit = 0
            ch = 0
    return "".join(geohash)


def decode_geohash_bbox(gh: str) -> tuple[float, float, float, float]:
    """Returns (min_lat, max_lat, min_lon, max_lon) for a geohash cell."""
    lat_interval = [-90.0, 90.0]
    lon_interval = [-180.0, 180.0]
    even = True
    for c in gh:
        cd = _BASE32_MAP[c]
        for mask in (16, 8, 4, 2, 1):
            if even:
                mid = (lon_interval[0] + lon_interval[1]) / 2.0
                if cd & mask:
                    lon_interval[0] = mid
                else:
                    lon_interval[1] = mid
            else:
                mid = (lat_interval[0] + lat_interval[1]) / 2.0
                if cd & mask:
                    lat_interval[0] = mid
                else:
                    lat_interval[1] = mid
            even = not even
    return (lat_interval[0], lat_interval[1], lon_interval[0], lon_interval[1])


def geohash_cell_and_neighbors(lat: float, lon: float, precision: int = 5) -> set[str]:
    """Returns the target geohash cell plus its 8 surrounding neighbor cells."""
    center = encode_geohash(lat, lon, precision=precision)
    min_lat, max_lat, min_lon, max_lon = decode_geohash_bbox(center)
    dlat = max_lat - min_lat
    dlon = max_lon - min_lon
    clat = (min_lat + max_lat) / 2.0
    clon = (min_lon + max_lon) / 2.0

    cells: set[str] = {center}
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            nlat = max(-89.999, min(89.999, clat + dy * dlat))
            nlon = ((clon + dx * dlon + 180.0) % 360.0) - 180.0
            cells.add(encode_geohash(nlat, nlon, precision=precision))
    return cells


def compute_dynamic_radius_meters(
    speed_kmh: float,
    category: HazardCategory | None = None,
    max_cap_meters: float | None = None,
) -> float:
    """
    Computes a speed- and hazard-category-aware alert lookahead radius:
    - Urban (<50 km/h): ~1.2 - 3.1 km
    - Highway (110 km/h on PLUS E1/E2): ~5.4 km base, up to ~8.6 km for road closures
      so drivers can exit BEFORE reaching the blockage.
    """
    clamped_speed = max(0.0, min(speed_kmh, 200.0))
    base_m = max(1000.0, min(6000.0, 1200.0 + 38.0 * clamped_speed))
    mult = CATEGORY_RADIUS_MULTIPLIER.get(category, 1.0) if category is not None else 1.0
    radius = min(10_000.0, max(700.0, base_m * mult))
    if max_cap_meters is not None and max_cap_meters > 0:
        radius = min(radius, max_cap_meters)
    return round(radius, 1)


@dataclass(frozen=True)
class RouteSnapResult:
    cross_track_meters: float
    along_route_meters: float
    route_fraction: float
    total_route_meters: float


def snap_point_to_polyline(
    lat: float,
    lon: float,
    polyline_coords: Sequence[tuple[float, float]],
) -> RouteSnapResult | None:
    """Projects a point onto a decoded (lat, lon) polyline returning cross-track & along-route distance."""
    if len(polyline_coords) < 2:
        return None

    cos_lat = max(0.05, math.cos(math.radians(lat)))
    meters_per_lat = 111_132.92
    meters_per_lon = 111_320.0 * cos_lat

    best_dist = float("inf")
    best_along = 0.0
    cum_m = 0.0

    for idx in range(len(polyline_coords) - 1):
        lat1, lon1 = polyline_coords[idx]
        lat2, lon2 = polyline_coords[idx + 1]
        seg_len = haversine_meters(lat1, lon1, lat2, lon2)
        if seg_len < 1e-3:
            continue

        # Local tangent-plane projection for fast, accurate segment clamping
        ax = (lon1 - lon) * meters_per_lon
        ay = (lat1 - lat) * meters_per_lat
        bx = (lon2 - lon) * meters_per_lon
        by = (lat2 - lat) * meters_per_lat

        dx = bx - ax
        dy = by - ay
        denom = dx * dx + dy * dy
        t = 0.0 if denom <= 1e-9 else max(0.0, min(1.0, -(ax * dx + ay * dy) / denom))

        px = ax + t * dx
        py = ay + t * dy
        dist = math.hypot(px, py)
        if dist < best_dist:
            best_dist = dist
            best_along = cum_m + t * seg_len

        cum_m += seg_len

    total_m = max(1.0, cum_m)
    return RouteSnapResult(
        cross_track_meters=round(best_dist, 1),
        along_route_meters=round(best_along, 1),
        route_fraction=round(max(0.0, min(1.0, best_along / total_m)), 5),
        total_route_meters=round(total_m, 1),
    )


@dataclass(frozen=True)
class HeadingFilterDecision:
    relevant: bool
    distance_meters: float
    bearing_delta_deg: float
    effective_radius_meters: float
    on_active_route: bool = False
    reason: str = "accepted"


def evaluate_hazard_for_driver(
    *,
    driver_lat: float,
    driver_lon: float,
    driver_heading_deg: float | None,
    driver_speed_kmh: float,
    hazard: HazardRecord,
    active_route_coords: Sequence[tuple[float, float]] | None = None,
    max_radius_override_m: float | None = None,
) -> HeadingFilterDecision:
    """
    4-Stage Dynamic, Heading-Aware Geospatial Relevance Filter:
      1. Speed + category dynamic radius check.
      2. Forward 130° heading cone check (±65°) or 250 m immediate safety ring.
      3. Divided carriageway / one-way opposite-bound suppression.
      4. Active route corridor boost (marks `on_active_route=True` if ahead on route within 65 m).
    """
    eff_radius = compute_dynamic_radius_meters(
        speed_kmh=driver_speed_kmh,
        category=hazard.category,
        max_cap_meters=max_radius_override_m,
    )
    dist_m = haversine_meters(driver_lat, driver_lon, hazard.coordinate.lat, hazard.coordinate.lon)
    bearing_to_hazard = initial_bearing_deg(
        driver_lat, driver_lon, hazard.coordinate.lat, hazard.coordinate.lon
    )
    bearing_delta = (
        angular_diff_deg(driver_heading_deg, bearing_to_hazard)
        if driver_heading_deg is not None
        else 0.0
    )

    # Check active route relevance early (a closure 9 km ahead along the active route may still matter)
    on_active_route = False
    if active_route_coords and len(active_route_coords) >= 2:
        drv_snap = snap_point_to_polyline(driver_lat, driver_lon, active_route_coords)
        haz_snap = snap_point_to_polyline(
            hazard.coordinate.lat, hazard.coordinate.lon, active_route_coords
        )
        if (
            drv_snap is not None
            and haz_snap is not None
            and haz_snap.cross_track_meters <= 65.0
            and haz_snap.along_route_meters >= drv_snap.along_route_meters - 40.0
        ):
            on_active_route = True

    # Stage 1: Distance vs dynamic radius
    if dist_m > eff_radius and not (on_active_route and dist_m <= eff_radius * 1.35):
        return HeadingFilterDecision(
            relevant=False,
            distance_meters=round(dist_m, 1),
            bearing_delta_deg=round(bearing_delta, 1),
            effective_radius_meters=eff_radius,
            on_active_route=on_active_route,
            reason="outside_dynamic_radius",
        )

    # Stage 2: Forward heading cone check (when heading is known and moving or navigating)
    if driver_heading_deg is not None and dist_m > IMMEDIATE_PROXIMITY_RING_M:
        if bearing_delta > FORWARD_CONE_HALF_ANGLE_DEG and not on_active_route:
            return HeadingFilterDecision(
                relevant=False,
                distance_meters=round(dist_m, 1),
                bearing_delta_deg=round(bearing_delta, 1),
                effective_radius_meters=eff_radius,
                on_active_route=False,
                reason="behind_driver_heading_cone",
            )

    # Stage 3: Divided carriageway / one-way opposite direction suppression
    if (
        driver_heading_deg is not None
        and hazard.road_heading_deg is not None
        and hazard.oneway != 0
        and not hazard.affects_both_directions
    ):
        road_diff = angular_diff_deg(driver_heading_deg, hazard.road_heading_deg)
        if road_diff > CARRIAGEWAY_OPPOSITE_THRESHOLD_DEG:
            return HeadingFilterDecision(
                relevant=False,
                distance_meters=round(dist_m, 1),
                bearing_delta_deg=round(bearing_delta, 1),
                effective_radius_meters=eff_radius,
                on_active_route=False,
                reason="opposite_carriageway_suppressed",
            )

    return HeadingFilterDecision(
        relevant=True,
        distance_meters=round(dist_m, 1),
        bearing_delta_deg=round(bearing_delta, 1),
        effective_radius_meters=eff_radius,
        on_active_route=on_active_route,
        reason="accepted",
    )


def build_closure_exclusion_ring(
    lat: float,
    lon: float,
    half_size_meters: float = 22.0,
) -> list[list[float]]:
    """
    Constructs a small closed WGS 84 polygon ring `[[lon, lat], ...]` for Valhalla
    `exclude_polygons` around a reported road closure or flash flood.
    """
    dlat = half_size_meters / 111_132.92
    dlon = half_size_meters / max(10_000.0, 111_320.0 * math.cos(math.radians(lat)))
    return [
        [round(lon - dlon, 6), round(lat - dlat, 6)],
        [round(lon + dlon, 6), round(lat - dlat, 6)],
        [round(lon + dlon, 6), round(lat + dlat, 6)],
        [round(lon - dlon, 6), round(lat + dlat, 6)],
        [round(lon - dlon, 6), round(lat - dlat, 6)],
    ]
