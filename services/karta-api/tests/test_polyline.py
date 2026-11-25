from datetime import datetime, timezone

from karta_api.routing.polyline import (
    angular_diff_deg,
    coords_to_linestring_wkt,
    decode_polyline6,
    encode_polyline6,
    estimate_crossing_timestamp,
    haversine_meters,
    initial_bearing_deg,
)


def test_polyline6_roundtrip() -> None:
    pts = [
        (3.157850, 101.711860),  # KLCC
        (3.046840, 101.706230),  # Sungai Besi Toll
        (1.608520, 103.651250),  # Skudai Toll
        (1.283400, 103.860700),  # Marina Bay SG
    ]
    encoded = encode_polyline6(pts)
    decoded = decode_polyline6(encoded)
    assert len(decoded) == len(pts)
    for (lat_a, lon_a), (lat_b, lon_b) in zip(pts, decoded, strict=True):
        assert abs(lat_a - lat_b) < 1e-6
        assert abs(lon_a - lon_b) < 1e-6


def test_wkt_uses_lon_lat_order() -> None:
    wkt = coords_to_linestring_wkt([(3.15785, 101.71186), (1.2834, 103.8607)])
    assert wkt == "LINESTRING(101.711860 3.157850, 103.860700 1.283400)"


def test_angular_diff_and_bearing() -> None:
    assert angular_diff_deg(355.0, 5.0) == 10.0
    assert angular_diff_deg(10.0, 190.0) == 180.0
    assert angular_diff_deg(195.0, 200.0) == 5.0

    # KLCC -> Singapore is roughly SSE (~131 deg)
    brg = initial_bearing_deg(3.15785, 101.71186, 1.2834, 103.8607)
    assert 125.0 < brg < 140.0


def test_haversine_and_timestamp_interpolation() -> None:
    dist_m = haversine_meters(3.15785, 101.71186, 1.2834, 103.8607)
    assert 310_000 < dist_m < 325_000

    dep = datetime(2026, 11, 23, 8, 0, tzinfo=timezone.utc)
    crossing = estimate_crossing_timestamp(dep, total_duration_seconds=3600.0, route_fraction=0.25)
    assert crossing == datetime(2026, 11, 23, 8, 15, tzinfo=timezone.utc)
