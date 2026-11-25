from __future__ import annotations

from datetime import date, datetime, time
from typing import Any
from zoneinfo import ZoneInfo

import pytest

from karta_api.db.toll_repo import MatchedGantryCrossing
from karta_api.models.tolls import PaymentMethod, VehicleProfile
from karta_api.routing.polyline import encode_polyline6
from karta_api.tolls.engine import RegionalTollEngine


class DeterministicTollStore:
    """In-memory deterministic test fixture backing the TollDataStore Protocol."""

    def __init__(self, crossings: list[MatchedGantryCrossing], holidays: set[tuple[str, date]] | None = None) -> None:
        self._crossings = crossings
        self._holidays = holidays or set()

    async def find_gantries_along_route_wkt(self, route_wkt: str) -> list[MatchedGantryCrossing]:
        return list(self._crossings)

    async def resolve_vehicle_class(self, country_code: str, canonical_profile: str) -> str | None:
        mapping = {
            ("MY", "car"): "MY_C1",
            ("MY", "motorcycle"): "MY_MC",
            ("SG", "car"): "SG_PC",
            ("SG", "motorcycle"): "SG_MC",
            ("BN", "car"): "BN_C1",
            ("BN", "motorcycle"): "BN_MC",
        }
        return mapping.get((country_code, canonical_profile))

    async def get_open_rates(
        self,
        gantry_id: str,
        country_code: str,
        vehicle_class: str,
        as_of_date: date,
        include_foreign_only: bool,
    ) -> list[dict[str, Any]]:
        table: dict[tuple[str, str], list[dict[str, Any]]] = {
            ("MY-LDP-PENCHALA", "MY_C1"): [
                {"amount_minor": 210, "currency_code": "MYR", "foreign_vehicle_only": False}
            ],
            ("MY-CIQ-BSI-INBOUND", "MY_C1"): [
                {"amount_minor": 0, "currency_code": "MYR", "foreign_vehicle_only": False},
                {"amount_minor": 2000, "currency_code": "MYR", "foreign_vehicle_only": True},
            ],
            ("BN-RASAU-BRIDGE", "BN_C1"): [
                {"amount_minor": 300, "currency_code": "BND", "foreign_vehicle_only": False}
            ],
            ("BN-RASAU-BRIDGE", "BN_MC"): [
                {"amount_minor": 100, "currency_code": "BND", "foreign_vehicle_only": False}
            ],
        }
        rows = table.get((gantry_id, vehicle_class), [])
        return [r for r in rows if (not r["foreign_vehicle_only"]) or include_foreign_only]

    async def get_closed_matrix_rate(
        self,
        corridor_id: str,
        entry_gantry_id: str,
        exit_gantry_id: str,
        vehicle_class: str,
        as_of_date: date,
    ) -> dict[str, Any] | None:
        if (corridor_id, entry_gantry_id, exit_gantry_id, vehicle_class) == (
            "MY-PLUS-MAIN",
            "MY-PLUS-SG_BESI",
            "MY-PLUS-SKUDAI",
            "MY_C1",
        ):
            return {"amount_minor": 3444, "currency_code": "MYR", "distance_km": 297.4}
        if (corridor_id, entry_gantry_id, exit_gantry_id, vehicle_class) == (
            "MY-PLUS-MAIN",
            "MY-PLUS-SG_BESI",
            "MY-PLUS-SKUDAI",
            "MY_MC",
        ):
            return {"amount_minor": 0, "currency_code": "MYR", "distance_km": 297.4}
        return None

    async def get_erp_rate(
        self,
        gantry_id: str,
        vehicle_class: str,
        day_type: str,
        local_time: time,
        as_of_date: date,
    ) -> dict[str, Any] | None:
        if gantry_id == "SG-ERP-31-CTE-BRADDELL" and day_type == "WEEKDAY":
            if time(8, 30) <= local_time < time(9, 0):
                amt = 300 if vehicle_class == "SG_PC" else 150
                return {"amount_minor": amt, "currency_code": "SGD"}
        return None

    async def get_public_holiday_override(self, country_code: str, target_date: date) -> str | None:
        return "SUNDAY_PH" if (country_code, target_date) in self._holidays else None


SAMPLE_POLY6 = encode_polyline6([(3.15, 101.71), (1.30, 103.85)])


@pytest.mark.asyncio
async def test_plus_closed_system_pairing_and_motorcycle_exemption() -> None:
    crossings = [
        MatchedGantryCrossing(
            gantry_id="MY-PLUS-SG_BESI",
            corridor_id="MY-PLUS-MAIN",
            corridor_name="North-South Expressway",
            system_type="closed_matrix",
            country_code="MY",
            gantry_name="Plaza Tol Sungai Besi",
            role="entry_exit",
            direction_bearing=None,
            bearing_tolerance=55,
            accepted_payments=["RFID", "SMARTTAG", "TNG_CARD"],
            lane_layout=[{"lane": 1, "methods": ["RFID"]}],
            lat=3.04684,
            lon=101.70623,
            route_fraction=0.10,
            route_heading_deg=150.0,
        ),
        MatchedGantryCrossing(
            gantry_id="MY-PLUS-SKUDAI",
            corridor_id="MY-PLUS-MAIN",
            corridor_name="North-South Expressway",
            system_type="closed_matrix",
            country_code="MY",
            gantry_name="Plaza Tol Skudai",
            role="entry_exit",
            direction_bearing=None,
            bearing_tolerance=55,
            accepted_payments=["RFID", "SMARTTAG", "TNG_CARD"],
            lane_layout=[{"lane": 1, "methods": ["RFID"]}],
            lat=1.60852,
            lon=103.65125,
            route_fraction=0.90,
            route_heading_deg=155.0,
        ),
    ]
    engine = RegionalTollEngine(DeterministicTollStore(crossings))
    dep = datetime(2026, 11, 23, 9, 0, tzinfo=ZoneInfo("Asia/Kuala_Lumpur"))

    car_res = await engine.calculate_route_tolls(
        SAMPLE_POLY6, 12600, dep, VehicleProfile.CAR, "MY", [PaymentMethod.RFID]
    )
    assert car_res.has_tolls is True
    assert car_res.display_total == "RM 34.44"
    assert len(car_res.items) == 1
    assert car_res.items[0].entry_gantry_id == "MY-PLUS-SG_BESI"
    assert car_res.items[0].gantry_id == "MY-PLUS-SKUDAI"

    mc_res = await engine.calculate_route_tolls(
        SAMPLE_POLY6, 12600, dep, VehicleProfile.MOTORCYCLE, "MY", [PaymentMethod.RFID]
    )
    assert mc_res.has_tolls is False
    assert mc_res.display_total == "Free"


@pytest.mark.asyncio
async def test_singapore_erp_peak_offpeak_heading_and_holiday() -> None:
    # Southbound gantry (195 deg)
    erp_sb = MatchedGantryCrossing(
        gantry_id="SG-ERP-31-CTE-BRADDELL",
        corridor_id="SG-ERP-CTE",
        corridor_name="CTE ERP",
        system_type="time_varying_erp",
        country_code="SG",
        gantry_name="CTE Southbound before Braddell",
        role="erp_gantry",
        direction_bearing=195,
        bearing_tolerance=50,
        accepted_payments=["ERP_IU", "ERP2_OBU"],
        lane_layout=[{"lane": 1, "methods": ["ERP_IU", "ERP2_OBU"]}],
        lat=1.34692,
        lon=103.85823,
        route_fraction=0.5,
        route_heading_deg=190.0,
    )
    sg_tz = ZoneInfo("Asia/Singapore")

    # 1. Weekday morning peak: depart 08:25, 20-min trip -> crosses at 08:35 -> $3.00
    engine = RegionalTollEngine(DeterministicTollStore([erp_sb]))
    peak = await engine.calculate_route_tolls(
        SAMPLE_POLY6, 1200, datetime(2026, 11, 23, 8, 25, tzinfo=sg_tz),
        VehicleProfile.CAR, "SG", [PaymentMethod.ERP2_OBU],
    )
    assert peak.has_tolls is True
    assert peak.display_total == "$3.00"

    # 2. Weekday off-peak (14:00) -> Free
    offpeak = await engine.calculate_route_tolls(
        SAMPLE_POLY6, 1200, datetime(2026, 11, 23, 14, 0, tzinfo=sg_tz),
        VehicleProfile.CAR, "SG", [PaymentMethod.ERP2_OBU],
    )
    assert offpeak.has_tolls is False
    assert offpeak.display_total == "Free"

    # 3. Public Holiday on a weekday (2026-12-25 Christmas Friday at 08:35) -> Free
    ph_engine = RegionalTollEngine(
        DeterministicTollStore([erp_sb], holidays={("SG", date(2026, 12, 25))})
    )
    ph_res = await ph_engine.calculate_route_tolls(
        SAMPLE_POLY6, 1200, datetime(2026, 12, 25, 8, 25, tzinfo=sg_tz),
        VehicleProfile.CAR, "SG", [PaymentMethod.ERP2_OBU],
    )
    assert ph_res.has_tolls is False
    assert ph_res.display_total == "Free"

    # 4. Opposite direction (northbound heading 15 deg vs gantry 195 deg) -> Ignored!
    erp_wrong_dir = MatchedGantryCrossing(**{**erp_sb.__dict__, "route_heading_deg": 15.0})
    opp_engine = RegionalTollEngine(DeterministicTollStore([erp_wrong_dir]))
    opp_res = await opp_engine.calculate_route_tolls(
        SAMPLE_POLY6, 1200, datetime(2026, 11, 23, 8, 25, tzinfo=sg_tz),
        VehicleProfile.CAR, "SG", [PaymentMethod.ERP2_OBU],
    )
    assert opp_res.has_tolls is False
    assert opp_res.items == []


@pytest.mark.asyncio
async def test_cross_border_sg_to_my_multicurrency_and_foreign_road_charge() -> None:
    crossings = [
        MatchedGantryCrossing(
            gantry_id="SG-ERP-31-CTE-BRADDELL",
            corridor_id="SG-ERP-CTE",
            corridor_name="CTE ERP",
            system_type="time_varying_erp",
            country_code="SG",
            gantry_name="CTE ERP",
            role="erp_gantry",
            direction_bearing=195,
            bearing_tolerance=50,
            accepted_payments=["ERP_IU", "ERP2_OBU"],
            lane_layout=[],
            lat=1.34692,
            lon=103.85823,
            route_fraction=0.1,
            route_heading_deg=195.0,
        ),
        MatchedGantryCrossing(
            gantry_id="MY-CIQ-BSI-INBOUND",
            corridor_id="MY-BORDER-SG",
            corridor_name="Johor Causeway",
            system_type="border_checkpoint",
            country_code="MY",
            gantry_name="BSI CIQ Inbound",
            role="border_crossing",
            direction_bearing=345,
            bearing_tolerance=65,
            accepted_payments=["TNG_CARD", "RFID"],
            lane_layout=[],
            lat=1.46148,
            lon=103.76792,
            route_fraction=0.5,
            route_heading_deg=350.0,
        ),
        MatchedGantryCrossing(
            gantry_id="MY-LDP-PENCHALA",
            corridor_id="MY-LDP",
            corridor_name="LDP",
            system_type="open_barrier",
            country_code="MY",
            gantry_name="Plaza Tol Penchala",
            role="open_plaza",
            direction_bearing=None,
            bearing_tolerance=55,
            accepted_payments=["RFID", "SMARTTAG", "TNG_CARD"],
            lane_layout=[],
            lat=3.16422,
            lon=101.61349,
            route_fraction=0.9,
            route_heading_deg=0.0,
        ),
    ]
    engine = RegionalTollEngine(DeterministicTollStore(crossings))
    sg_tz = ZoneInfo("Asia/Singapore")
    # SG-registered car entering Malaysia incurs RM 20.00 Road Charge + RM 2.10 LDP + $3.00 ERP
    res = await engine.calculate_route_tolls(
        SAMPLE_POLY6,
        3600,
        datetime(2026, 11, 23, 8, 30, tzinfo=sg_tz),
        VehicleProfile.CAR,
        vehicle_registration_country="SG",
        user_payment_methods=[PaymentMethod.ERP2_OBU, PaymentMethod.TNG_CARD],
    )
    assert res.display_total == "RM 22.10 + $3.00"
    assert any("Road Charge" in w for item in res.items for w in item.warnings)


@pytest.mark.asyncio
async def test_brunei_rasau_bridge_bnd_formatting() -> None:
    rasau = MatchedGantryCrossing(
        gantry_id="BN-RASAU-BRIDGE",
        corridor_id="BN-RASAU",
        corridor_name="Rasau Toll Bridge",
        system_type="open_barrier",
        country_code="BN",
        gantry_name="Rasau Toll Bridge",
        role="open_plaza",
        direction_bearing=None,
        bearing_tolerance=55,
        accepted_payments=["CASH", "BRUNEI_TOLL_CARD"],
        lane_layout=[{"lane": 1, "methods": ["BRUNEI_TOLL_CARD"]}],
        lat=4.57845,
        lon=114.17835,
        route_fraction=0.5,
        route_heading_deg=270.0,
    )
    engine = RegionalTollEngine(DeterministicTollStore([rasau]))
    bn_tz = ZoneInfo("Asia/Brunei")
    res = await engine.calculate_route_tolls(
        SAMPLE_POLY6,
        1800,
        datetime(2026, 11, 23, 10, 0, tzinfo=bn_tz),
        VehicleProfile.CAR,
        vehicle_registration_country="BN",
        user_payment_methods=[PaymentMethod.CASH],
    )
    assert res.has_tolls is True
    assert res.display_total == "B$3.00"
    assert res.items[0].payment_compatible is True
