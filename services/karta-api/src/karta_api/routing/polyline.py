from __future__ import annotations

import math
from collections.abc import Sequence
from datetime import datetime, timedelta

EARTH_RADIUS_M = 6_371_008.8


def decode_polyline6(encoded: str, precision: int = 6) -> list[tuple[float, float]]:
    """
    Decodes a Valhalla precision-6 encoded polyline string into a list of (lat, lon) tuples.
    """
    factor = 10**precision
    coords: list[tuple[float, float]] = []
    index = 0
    lat = 0
    lon = 0
    length = len(encoded)

    while index < length:
        shift = 0
        result = 0
        while True:
            b = ord(encoded[index]) - 63
            index += 1
            result |= (b & 0x1F) << shift
            shift += 5
            if b < 0x20:
                break
        dlat = ~(result >> 1) if (result & 1) else (result >> 1)
        lat += dlat

        shift = 0
        result = 0
        while True:
            b = ord(encoded[index]) - 63
            index += 1
            result |= (b & 0x1F) << shift
            shift += 5
            if b < 0x20:
                break
        dlon = ~(result >> 1) if (result & 1) else (result >> 1)
        lon += dlon

        coords.append((lat / factor, lon / factor))

    return coords


def encode_polyline6(coords: Sequence[tuple[float, float]], precision: int = 6) -> str:
    """
    Encodes a sequence of (lat, lon) tuples into a Valhalla precision-6 polyline string.
    """
    factor = 10**precision
    output: list[str] = []
    prev_lat = 0
    prev_lon = 0

    def _encode_delta(val: int) -> None:
        v = ~(val << 1) if val < 0 else (val << 1)
        while v >= 0x20:
            output.append(chr((0x20 | (v & 0x1F)) + 63))
            v >>= 5
        output.append(chr(v + 63))

    for lat, lon in coords:
        ilat = int(round(lat * factor))
        ilon = int(round(lon * factor))
        _encode_delta(ilat - prev_lat)
        _encode_delta(ilon - prev_lon)
        prev_lat = ilat
        prev_lon = ilon

    return "".join(output)


def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2.0) ** 2
    return 2.0 * EARTH_RADIUS_M * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))


def initial_bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dlam = math.radians(lon2 - lon1)
    x = math.sin(dlam) * math.cos(phi2)
    y = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlam)
    return (math.degrees(math.atan2(x, y)) + 360.0) % 360.0


def angular_diff_deg(a: float, b: float) -> float:
    """Smallest angular difference between two headings in degrees [0, 180]."""
    diff = abs((a - b + 180.0) % 360.0 - 180.0)
    return diff


def coords_to_linestring_wkt(coords: Sequence[tuple[float, float]]) -> str:
    """Converts (lat, lon) coordinates to WGS 84 WKT LINESTRING(lon lat, ...)."""
    if len(coords) < 2:
        raise ValueError("A LineString requires at least 2 coordinate pairs.")
    pts = ", ".join(f"{lon:.6f} {lat:.6f}" for lat, lon in coords)
    return f"LINESTRING({pts})"


def estimate_crossing_timestamp(
    departure_time: datetime,
    total_duration_seconds: float,
    route_fraction: float,
) -> datetime:
    clamped = max(0.0, min(1.0, route_fraction))
    return departure_time + timedelta(seconds=total_duration_seconds * clamped)
