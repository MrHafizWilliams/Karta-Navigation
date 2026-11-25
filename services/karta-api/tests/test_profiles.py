from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from karta_api.models.common import Coordinate
from karta_api.models.routing import RouteRequest, RoutingProfileId
from karta_api.routing.profiles import CostingProfileRegistry


def _load_registry() -> CostingProfileRegistry:
    return CostingProfileRegistry(Path("/config/valhalla/costing_profiles.json"))


def test_all_seven_profiles_present() -> None:
    reg = _load_registry()
    profiles = set(reg.list_profiles())
    expected = {
        "drive_fastest",
        "drive_avoid_tolls",
        "drive_no_highways",
        "drive_motorcycle",
        "walk",
        "cycle",
        "transit",
    }
    assert expected.issubset(profiles)


def test_avoid_tolls_costing_payload() -> None:
    reg = _load_registry()
    req = RouteRequest(
        origin=Coordinate(lat=3.15785, lon=101.71186),
        destination=Coordinate(lat=1.4655, lon=103.7578),
        profile=RoutingProfileId.DRIVE_FASTEST,
        avoid_tolls=True,
    )
    payload = reg.build_valhalla_route_payload(req)
    assert payload["costing"] == "auto"
    assert payload["costing_options"]["auto"]["use_tolls"] == 0.0
    assert payload["costing_options"]["auto"]["toll_booth_penalty"] == 3600


def test_transit_multimodal_payload_sets_date_time() -> None:
    reg = _load_registry()
    dep = datetime(2026, 11, 23, 8, 30, tzinfo=ZoneInfo("Asia/Kuala_Lumpur"))
    req = RouteRequest(
        origin=Coordinate(lat=3.1343, lon=101.6861),  # KL Sentral
        destination=Coordinate(lat=3.15785, lon=101.71186),  # KLCC
        profile=RoutingProfileId.TRANSIT,
        departure_time=dep,
    )
    payload = reg.build_valhalla_route_payload(req)
    assert payload["costing"] == "multimodal"
    assert payload["date_time"] == {"type": 1, "value": "2026-11-23T08:30"}
    assert "transit" in payload["costing_options"]
    assert "pedestrian" in payload["costing_options"]


def test_multi_stop_waypoints_emit_break_legs() -> None:
    reg = _load_registry()
    req = RouteRequest(
        origin=Coordinate(lat=5.4145, lon=100.3298),
        waypoints=[Coordinate(lat=3.1579, lon=101.7116)],
        destination=Coordinate(lat=1.2834, lon=103.8607),
    )
    payload = reg.build_valhalla_route_payload(req)
    assert len(payload["locations"]) == 3
    assert [loc["type"] for loc in payload["locations"]] == ["break", "break", "break"]
