from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from karta_api.models.common import Coordinate
from karta_api.models.routing import (
    CandidateRoute,
    RouteLeg,
    RouteManeuver,
    TilePrefetchRequest,
)
from karta_api.models.tolls import PaymentMethod, TollChargeItem, TollSummary
from karta_api.routing.differentiation import differentiate_candidate_routes
from karta_api.routing.polyline import encode_polyline6
from karta_api.routing.tile_prefetch import build_predictive_tile_plan
from karta_api.tolls.currency import format_currency_minor
from karta_api.tolls.engine import build_toll_badge


def _make_route(
    idx: int,
    duration_min: float,
    distance_km: float,
    toll_myr_sen: int,
    turns: int,
    has_highways: bool,
    corridor_street: str,
    profile_used: str = "drive_fastest",
) -> CandidateRoute:
    maneuvers = [
        RouteManeuver(
            type=1,
            instruction="Start",
            street_names=[corridor_street],
            distance_km=distance_km * 0.6,
            time_seconds=duration_min * 36,
            begin_shape_index=0,
            end_shape_index=1,
            highway=has_highways,
        )
    ]
    for t in range(turns):
        maneuvers.append(
            RouteManeuver(
                type=10 if t % 2 == 0 else 15,
                instruction=f"Turn {t + 1}",
                street_names=[f"Jalan {t + 1}"],
                distance_km=0.5,
                time_seconds=30.0,
                begin_shape_index=1,
                end_shape_index=2,
                highway=False,
            )
        )
    totals = [format_currency_minor("MYR", toll_myr_sen)] if toll_myr_sen > 0 else []
    tolls = TollSummary(
        has_tolls=toll_myr_sen > 0,
        totals_by_currency=totals,
        display_total=totals[0].formatted if totals else "Free",
    )
    return CandidateRoute(
        route_index=idx,
        profile_used=profile_used,
        summary_label=profile_used,
        distance_km=distance_km,
        duration_seconds=duration_min * 60.0,
        has_toll_roads=toll_myr_sen > 0,
        has_highways=has_highways,
        countries_crossed=["MY"],
        legs=[
            RouteLeg(
                distance_km=distance_km,
                duration_seconds=duration_min * 60.0,
                shape_polyline6=encode_polyline6([(3.1579, 101.7116), (3.0468, 101.7062)]),
                maneuvers=maneuvers,
            )
        ],
        tolls=tolls,
    )


def test_route_differentiation_assigns_scannable_ux_labels() -> None:
    routes = [
        _make_route(0, duration_min=38, distance_km=42.0, toll_myr_sen=840, turns=12, has_highways=True, corridor_street="PLUS E2"),
        _make_route(1, duration_min=44, distance_km=45.0, toll_myr_sen=420, turns=14, has_highways=True, corridor_street="LDP E11"),
        _make_route(2, duration_min=46, distance_km=43.5, toll_myr_sen=840, turns=7, has_highways=True, corridor_street="MEX E20"),
        _make_route(3, duration_min=51, distance_km=41.0, toll_myr_sen=0, turns=18, has_highways=False, corridor_street="Jalan Persekutuan 1", profile_used="drive_no_highways"),
    ]
    out = differentiate_candidate_routes(routes)

    assert out[0].ux_primary_tag == "Fastest • 38 min"
    assert out[0].ux_badge_kind == "fastest"
    assert out[0].primary_corridor_name == "via PLUS E2"

    assert out[1].ux_primary_tag == "Cheapest Toll • Save RM 4.20"
    assert out[1].ux_badge_kind == "cheapest_toll"

    assert out[2].ux_primary_tag == "Fewer Turns"
    assert out[2].ux_badge_kind == "fewer_turns"
    assert out[2].turn_count == 7

    assert out[3].ux_primary_tag == "Avoids Highway"
    assert out[3].ux_badge_kind == "avoids_highway"


def test_itemized_gantry_badges_for_my_sg_bn() -> None:
    my_tz = ZoneInfo("Asia/Kuala_Lumpur")
    sg_tz = ZoneInfo("Asia/Singapore")
    bn_tz = ZoneInfo("Asia/Brunei")

    plus_item = TollChargeItem(
        gantry_id="MY-PLUS-SKUDAI",
        corridor_id="MY-PLUS-MAIN",
        corridor_name="North-South Expressway",
        system_type="closed_matrix",
        country_code="MY",
        gantry_name="Plaza Tol Skudai",
        entry_gantry_id="MY-PLUS-SG_BESI",
        entry_gantry_name="Plaza Tol Sungai Besi",
        estimated_crossing_time=datetime(2026, 11, 23, 10, 15, tzinfo=my_tz),
        coordinate=Coordinate(lat=1.60852, lon=103.65125),
        charge=format_currency_minor("MYR", 3444),
        accepted_payments=[PaymentMethod.RFID, PaymentMethod.SMARTTAG, PaymentMethod.TNG_CARD],
    )
    penang_item = TollChargeItem(
        gantry_id="MY-PENANG-PERAI",
        corridor_id="MY-PENANG-BRIDGE",
        corridor_name="Penang Bridge",
        system_type="open_barrier",
        country_code="MY",
        gantry_name="Plaza Tol Jambatan Pulau Pinang",
        estimated_crossing_time=datetime(2026, 11, 23, 8, 5, tzinfo=my_tz),
        coordinate=Coordinate(lat=5.36766, lon=100.39134),
        charge=format_currency_minor("MYR", 574),
        accepted_payments=[PaymentMethod.RFID, PaymentMethod.TNG_CARD],
    )
    erp_item = TollChargeItem(
        gantry_id="SG-ERP-31-CTE-BRADDELL",
        corridor_id="SG-ERP-CTE",
        corridor_name="CTE ERP",
        system_type="time_varying_erp",
        country_code="SG",
        gantry_name="CTE Southbound before Braddell",
        estimated_crossing_time=datetime(2026, 11, 23, 8, 35, tzinfo=sg_tz),
        coordinate=Coordinate(lat=1.34692, lon=103.85823),
        charge=format_currency_minor("SGD", 300),
        accepted_payments=[PaymentMethod.ERP_IU, PaymentMethod.ERP2_OBU],
    )
    bn_item = TollChargeItem(
        gantry_id="BN-RASAU-BRIDGE",
        corridor_id="BN-RASAU",
        corridor_name="Rasau Toll Bridge",
        system_type="open_barrier",
        country_code="BN",
        gantry_name="Rasau Toll Bridge",
        estimated_crossing_time=datetime(2026, 11, 23, 11, 0, tzinfo=bn_tz),
        coordinate=Coordinate(lat=4.57845, lon=114.17835),
        charge=format_currency_minor("BND", 300),
        accepted_payments=[PaymentMethod.BRUNEI_TOLL_CARD, PaymentMethod.CASH],
    )

    b_plus = build_toll_badge(plus_item)
    b_penang = build_toll_badge(penang_item)
    b_erp = build_toll_badge(erp_item)
    b_bn = build_toll_badge(bn_item)

    assert b_plus.label == "PLUS Highway"
    assert b_plus.payment_label == "Touch 'n Go RFID"
    assert b_plus.charge.formatted == "RM 34.44"

    assert b_penang.label == "Penang Bridge"
    assert b_penang.badge_kind == "bridge"

    assert b_erp.label == "Singapore ERP"
    assert b_erp.payment_label == "Singapore ERP 2.0"
    assert b_erp.crossing_time_local == "08:35 SGT"

    assert b_bn.label == "Rasau Bridge"
    assert b_bn.charge.formatted == "B$3.00"


def test_predictive_tile_plan_highway_lookahead_and_next_turn_fanout() -> None:
    # KLCC -> Sungai Besi -> Seremban corridor with a sharp interchange bend
    corridor = [
        (3.1579, 101.7116),
        (3.1200, 101.7090),
        (3.0468, 101.7062),
        (3.0300, 101.7500),  # Sharp eastbound exit bend (> 40 deg)
        (2.9600, 101.7900),
        (2.8500, 101.8400),
    ]
    req = TilePrefetchRequest(
        polyline6=encode_polyline6(corridor),
        current_position=Coordinate(lat=3.1579, lon=101.7116),
        current_speed_kmh=110.0,
        maneuver_coordinates=[Coordinate(lat=3.0468, lon=101.7062)],
        max_tiles=128,
    )
    plan = build_predictive_tile_plan(req, pmtiles_public_url="http://localhost:8081")

    assert plan.lookahead_km == 14.0
    assert plan.zoom_levels == [12, 13, 14]
    assert plan.tile_count > 10
    assert plan.planning_ms < 25.0  # Must plan well under 25ms
    reasons = {t.reason for t in plan.tiles}
    assert "corridor" in reasons
    assert "next_turn" in reasons
    assert "alternate_turn" in reasons
    assert "horizon_buffer" in reasons
    # Ensure strict priority ordering (next_turn/immediate corridor first)
    priorities = [t.priority for t in plan.tiles]
    assert priorities == sorted(priorities)
