from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from karta_api.api.v1.routes import _cache_key
from karta_api.commuter.calendar_service import parse_ics_events
from karta_api.models.common import Coordinate
from karta_api.models.realtime import HazardCategory, HazardRecord, HazardSeverity, HazardStatus
from karta_api.models.routing import RouteRequest
from karta_api.realtime.geo_filter import (
    build_closure_exclusion_ring,
    compute_dynamic_radius_meters,
    encode_geohash,
    evaluate_hazard_for_driver,
    geohash_cell_and_neighbors,
)
from karta_api.routing.profiles import CostingProfileRegistry
from karta_api.voice.intent_parser import parse_voice_intent


def _make_hazard(
    *,
    lat: float,
    lon: float,
    category: HazardCategory = HazardCategory.ACCIDENT,
    severity: HazardSeverity = HazardSeverity.HIGH,
    road_heading_deg: float | None = 0.0,
    oneway: int = 1,
    affects_both: bool = False,
) -> HazardRecord:
    now = datetime.now(tz=UTC)
    return HazardRecord(
        id="haz-test-1",
        category=category,
        severity=severity,
        status=HazardStatus.ACTIVE,
        coordinate=Coordinate(lat=lat, lon=lon),
        road_heading_deg=road_heading_deg,
        oneway=oneway,
        affects_both_directions=affects_both,
        created_at=now,
        expires_at=now + timedelta(hours=1),
    )


def test_dynamic_radius_scales_by_speed_and_category() -> None:
    urban_pothole = compute_dynamic_radius_meters(30.0, HazardCategory.POTHOLE)
    highway_closure = compute_dynamic_radius_meters(110.0, HazardCategory.ROAD_CLOSURE)
    highway_police = compute_dynamic_radius_meters(110.0, HazardCategory.POLICE)

    assert 1000.0 <= urban_pothole <= 2000.0
    assert highway_closure > highway_police > urban_pothole
    assert highway_closure <= 10000.0


def test_heading_aware_filter_accepts_ahead_and_rejects_behind() -> None:
    # Driver at KLCC heading North (0 deg) at 90 km/h
    driver_lat, driver_lon = 3.1579, 101.7116

    # Hazard ~1.1 km due North (ahead)
    ahead_haz = _make_hazard(lat=3.1679, lon=101.7116, road_heading_deg=0.0, oneway=1)
    dec_ahead = evaluate_hazard_for_driver(
        driver_lat=driver_lat,
        driver_lon=driver_lon,
        driver_heading_deg=0.0,
        driver_speed_kmh=90.0,
        hazard=ahead_haz,
    )
    assert dec_ahead.relevant is True
    assert dec_ahead.bearing_delta_deg < 10.0

    # Hazard ~1.1 km due South (behind driver) -> rejected!
    behind_haz = _make_hazard(lat=3.1479, lon=101.7116, road_heading_deg=0.0, oneway=1)
    dec_behind = evaluate_hazard_for_driver(
        driver_lat=driver_lat,
        driver_lon=driver_lon,
        driver_heading_deg=0.0,
        driver_speed_kmh=90.0,
        hazard=behind_haz,
    )
    assert dec_behind.relevant is False
    assert dec_behind.reason == "behind_driver_heading_cone"

    # Opposite carriageway on one-way expressway (ahead geographically, but Southbound heading 180 deg) -> suppressed!
    opp_haz = _make_hazard(lat=3.1679, lon=101.7116, road_heading_deg=180.0, oneway=1, affects_both=False)
    dec_opp = evaluate_hazard_for_driver(
        driver_lat=driver_lat,
        driver_lon=driver_lon,
        driver_heading_deg=0.0,
        driver_speed_kmh=90.0,
        hazard=opp_haz,
    )
    assert dec_opp.relevant is False
    assert dec_opp.reason == "opposite_carriageway_suppressed"


def test_geohash_neighbors_returns_nine_cells() -> None:
    center = encode_geohash(3.1579, 101.7116, precision=5)
    cells = geohash_cell_and_neighbors(3.1579, 101.7116, precision=5)
    assert center in cells
    assert len(cells) == 9


@pytest.mark.parametrize(
    ("transcript", "expected_intent", "expected_cat", "expected_dir", "expected_lane"),
    [
        ("Hey Karta, ada kemalangan teruk lorong kanan on PLUS", "report_hazard", HazardCategory.ACCIDENT, "ahead", "right_lane"),
        ("Karta report police speed trap ahead on LDP", "report_hazard", HazardCategory.POLICE, "ahead", None),
        ("Lapor Karta, sekatan jalan JPJ arah bertentangan", "report_hazard", HazardCategory.POLICE, "opposite", None),
        ("Big pothole left lane near KLCC", "report_hazard", HazardCategory.POTHOLE, "ahead", "left_lane"),
        ("Kereta rosak di lorong kecemasan", "report_hazard", HazardCategory.HIDDEN_VEHICLE, "ahead", "emergency_lane"),
        ("Pokok tumbang road debris on CTE", "report_hazard", HazardCategory.ROAD_DEBRIS, "ahead", None),
        ("Banjir kilat jalan tutup ahead", "report_hazard", HazardCategory.ROAD_CLOSURE, "ahead", None),
        ("Still there", "confirm_hazard", None, "ahead", None),
        ("Dah clear already", "clear_hazard", None, "ahead", None),
        ("Accept reroute", "accept_reroute", None, "ahead", None),
        ("Cancel report", "cancel", None, "ahead", None),
    ],
)
def test_voice_intent_parser_regional_en_bm_manglish_singlish(
    transcript: str,
    expected_intent: str,
    expected_cat: HazardCategory | None,
    expected_dir: str,
    expected_lane: str | None,
) -> None:
    res = parse_voice_intent(transcript, locale="en-MY")
    assert res.intent == expected_intent
    assert res.hazard_category == expected_cat
    if expected_cat is not None:
        assert res.direction == expected_dir
        assert res.lane_hint == expected_lane
        assert res.confidence >= 0.9


def test_ics_parser_handles_facebook_and_google_events() -> None:
    sample_ics = (
        "BEGIN:VCALENDAR\r\n"
        "VERSION:2.0\r\n"
        "BEGIN:VEVENT\r\n"
        "UID:fb-event-9981@facebook.com\r\n"
        "DTSTART;TZID=Asia/Kuala_Lumpur:20261123T193000\r\n"
        "DTEND;TZID=Asia/Kuala_Lumpur:20261123T213000\r\n"
        "SUMMARY:KLCC Evening Tech Meetup\r\n"
        "LOCATION:Petronas Twin Towers\\, Kuala Lumpur\r\n"
        "GEO:3.1579;101.7116\r\n"
        "END:VEVENT\r\n"
        "END:VCALENDAR\r\n"
    )
    events = parse_ics_events(sample_ics)
    assert len(events) == 1
    ev = events[0]
    assert ev.uid == "fb-event-9981@facebook.com"
    assert ev.title == "KLCC Evening Tech Meetup"
    assert ev.location_text == "Petronas Twin Towers, Kuala Lumpur"
    assert ev.geo is not None
    assert abs(ev.geo.lat - 3.1579) < 1e-4


def test_valhalla_dynamic_costing_exclusions_and_cache_epoch() -> None:
    profiles = CostingProfileRegistry(Path("/config/valhalla/costing_profiles.json"))
    req = RouteRequest(
        origin=Coordinate(lat=3.1579, lon=101.7116),
        destination=Coordinate(lat=1.2834, lon=103.8607),
    )
    ring = build_closure_exclusion_ring(3.101, 101.720)
    payload = profiles.build_valhalla_route_payload(
        req,
        exclude_locations=[{"lat": 3.101, "lon": 101.720}],
        exclude_polygons=[ring],
    )
    assert payload["exclude_locations"] == [{"lat": 3.101, "lon": 101.720}]
    assert len(payload["exclude_polygons"]) == 1
    assert payload["costing_options"]["auto"]["ignore_closures"] is False

    now = datetime(2026, 11, 23, 8, 12, tzinfo=UTC)
    k0 = _cache_key(req, now, traffic_epoch=0)
    k1 = _cache_key(req, now, traffic_epoch=1)
    assert k0 != k1
