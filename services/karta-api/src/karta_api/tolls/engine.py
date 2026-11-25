from __future__ import annotations

from datetime import date, datetime, time
from typing import Any, Protocol
from zoneinfo import ZoneInfo

from karta_api.db.toll_repo import MatchedGantryCrossing
from karta_api.models.common import Coordinate
from karta_api.models.tolls import (
    PaymentMethod,
    TollBadge,
    TollChargeItem,
    TollLaneGuidance,
    TollSummary,
    VehicleProfile,
)
from karta_api.routing.polyline import (
    angular_diff_deg,
    coords_to_linestring_wkt,
    decode_polyline6,
    estimate_crossing_timestamp,
)
from karta_api.tolls.currency import (
    aggregate_totals,
    format_currency_minor,
    format_multi_currency_display,
)

COUNTRY_TIMEZONES: dict[str, ZoneInfo] = {
    "MY": ZoneInfo("Asia/Kuala_Lumpur"),
    "SG": ZoneInfo("Asia/Singapore"),
    "BN": ZoneInfo("Asia/Brunei"),
}

COUNTRY_DEFAULT_CURRENCY: dict[str, str] = {
    "MY": "MYR",
    "SG": "SGD",
    "BN": "BND",
}

COUNTRY_TZ_ABBR: dict[str, str] = {
    "MY": "MYT",
    "SG": "SGT",
    "BN": "BNT",
}

_PAYMENT_DISPLAY_LABEL: dict[PaymentMethod, str] = {
    PaymentMethod.RFID: "Touch 'n Go RFID",
    PaymentMethod.ANPR_JUSTGO: "ANPR JustGO",
    PaymentMethod.SMARTTAG: "SmartTAG",
    PaymentMethod.TNG_CARD: "Touch 'n Go",
    PaymentMethod.OPEN_PAYMENT_CARD: "Open Payment",
    PaymentMethod.ERP2_OBU: "Singapore ERP 2.0",
    PaymentMethod.ERP_IU: "Singapore ERP",
    PaymentMethod.BRUNEI_TOLL_CARD: "Brunei Toll Card",
    PaymentMethod.CASH: "Cash",
}


def build_toll_badge(item: TollChargeItem) -> TollBadge:
    """
    Produces a scannable, human-friendly gantry & payment badge for route cards
    (e.g. 'PLUS Highway', 'Penang Bridge', 'Touch \'n Go RFID', 'Singapore ERP').
    """
    cid = item.corridor_id.upper()
    gid = item.gantry_id.upper()
    cc = item.country_code.upper()

    if item.system_type == "time_varying_erp" or cc == "SG":
        label = "Singapore ERP"
        kind = "sg_erp"
    elif "PENANG" in cid or "PENANG" in gid:
        label = "Penang Bridge"
        kind = "bridge"
    elif "PLUS" in cid:
        label = "PLUS Highway"
        kind = "plus_highway"
    elif "CIQ" in gid or "BSI" in gid or item.system_type == "border_checkpoint":
        label = "Second Link" if "LINKEDUA" in gid else "Johor Causeway CIQ"
        kind = "border_ciq"
    elif "RASAU" in cid or cc == "BN":
        label = "Rasau Bridge"
        kind = "brunei_bridge"
    elif "LDP" in cid:
        label = "LDP Highway"
        kind = "urban_expressway"
    elif "SPRINT" in cid:
        label = "SPRINT Highway"
        kind = "urban_expressway"
    elif "DUKE" in cid:
        label = "DUKE Highway"
        kind = "urban_expressway"
    elif "KESAS" in cid:
        label = "KESAS Highway"
        kind = "urban_expressway"
    elif "AKLEH" in cid:
        label = "AKLEH"
        kind = "urban_expressway"
    elif "SUKE" in cid:
        label = "SUKE Highway"
        kind = "urban_expressway"
    else:
        label = item.corridor_name
        kind = "urban_expressway"

    # Prefer RFID / ERP2 / Open Payment as the headline driver-facing payment chip
    preferred_order = (
        PaymentMethod.ERP2_OBU,
        PaymentMethod.ERP_IU,
        PaymentMethod.RFID,
        PaymentMethod.SMARTTAG,
        PaymentMethod.TNG_CARD,
        PaymentMethod.OPEN_PAYMENT_CARD,
        PaymentMethod.ANPR_JUSTGO,
        PaymentMethod.BRUNEI_TOLL_CARD,
        PaymentMethod.CASH,
    )
    primary_method = item.accepted_payments[0] if item.accepted_payments else PaymentMethod.TNG_CARD
    for pm in preferred_order:
        if pm in item.accepted_payments:
            primary_method = pm
            break

    tz_abbr = COUNTRY_TZ_ABBR.get(cc, "MYT")
    local_clock = f"{item.estimated_crossing_time.strftime('%H:%M')} {tz_abbr}"

    return TollBadge(
        badge_id=f"{item.gantry_id}:{item.estimated_crossing_time.strftime('%H%M')}",
        label=label,
        payment_label=_PAYMENT_DISPLAY_LABEL.get(primary_method, primary_method.value),
        badge_kind=kind,
        country_code=cc,
        gantry_name=item.gantry_name,
        entry_gantry_name=item.entry_gantry_name,
        charge=item.charge,
        accepted_payments=item.accepted_payments,
        crossing_time_local=local_clock,
    )


class TollDataStore(Protocol):
    async def find_gantries_along_route_wkt(self, route_wkt: str) -> list[MatchedGantryCrossing]: ...
    async def resolve_vehicle_class(self, country_code: str, canonical_profile: str) -> str | None: ...
    async def get_open_rates(
        self,
        gantry_id: str,
        country_code: str,
        vehicle_class: str,
        as_of_date: date,
        include_foreign_only: bool,
    ) -> list[dict[str, Any]]: ...
    async def get_closed_matrix_rate(
        self,
        corridor_id: str,
        entry_gantry_id: str,
        exit_gantry_id: str,
        vehicle_class: str,
        as_of_date: date,
    ) -> dict[str, Any] | None: ...
    async def get_erp_rate(
        self,
        gantry_id: str,
        vehicle_class: str,
        day_type: str,
        local_time: time,
        as_of_date: date,
    ) -> dict[str, Any] | None: ...
    async def get_public_holiday_override(self, country_code: str, target_date: date) -> str | None: ...


class RegionalTollEngine:
    """
    Stateful pre-route toll calculation engine supporting Malaysia (PLUS closed
    entry-exit matrices, open urban expressways, RFID/SmartTAG/TnG/ANPR lane
    guidance, MY-SG border Road Charge), Singapore (time-of-day ERP schedules +
    public holiday overrides), and Brunei Darussalam (BND).
    """

    def __init__(self, store: TollDataStore) -> None:
        self._store = store

    async def calculate_route_tolls(
        self,
        polyline6: str,
        duration_seconds: float,
        departure_time: datetime,
        vehicle_profile: VehicleProfile = VehicleProfile.CAR,
        vehicle_registration_country: str = "MY",
        user_payment_methods: list[PaymentMethod] | None = None,
    ) -> TollSummary:
        coords = decode_polyline6(polyline6)
        if len(coords) < 2:
            return TollSummary(has_tolls=False, display_total="Free")

        route_wkt = coords_to_linestring_wkt(coords)
        raw_crossings = await self._store.find_gantries_along_route_wkt(route_wkt)
        if not raw_crossings:
            return TollSummary(has_tolls=False, display_total="Free")

        # 1. Directional bearing verification (eliminates opposite-carriageway & flyover false hits)
        valid_crossings: list[MatchedGantryCrossing] = []
        seen_recent: list[tuple[str, float]] = []
        for hit in raw_crossings:
            if hit.direction_bearing is not None and hit.route_heading_deg is not None:
                if angular_diff_deg(hit.route_heading_deg, float(hit.direction_bearing)) > hit.bearing_tolerance:
                    continue
            # Deduplicate jitter if geometry grazes the same tripwire twice within 1% of route
            if any(gid == hit.gantry_id and abs(frac - hit.route_fraction) < 0.01 for gid, frac in seen_recent):
                continue
            seen_recent.append((hit.gantry_id, hit.route_fraction))
            valid_crossings.append(hit)

        if not valid_crossings:
            return TollSummary(has_tolls=False, display_total="Free")

        user_methods = set(user_payment_methods or [])
        vclass_cache: dict[str, str | None] = {}
        closed_entries: dict[str, MatchedGantryCrossing] = {}
        charge_items: list[TollChargeItem] = []
        global_warnings: list[str] = []

        async def _vehicle_class(cc: str) -> str | None:
            if cc not in vclass_cache:
                vclass_cache[cc] = await self._store.resolve_vehicle_class(cc, vehicle_profile.value)
            return vclass_cache[cc]

        for hit in valid_crossings:
            crossing_dt = estimate_crossing_timestamp(departure_time, duration_seconds, hit.route_fraction)
            tz = COUNTRY_TIMEZONES.get(hit.country_code, COUNTRY_TIMEZONES["MY"])
            local_dt = crossing_dt.astimezone(tz) if crossing_dt.tzinfo else crossing_dt.replace(tzinfo=tz)
            vclass = await _vehicle_class(hit.country_code)

            accepted = [PaymentMethod(m) for m in hit.accepted_payments]
            lanes = [TollLaneGuidance(**lane) for lane in hit.lane_layout]
            payment_ok = (not user_methods) or bool(user_methods.intersection(accepted))
            item_warnings: list[str] = []
            if not payment_ok:
                accepted_str = ", ".join(m.value for m in accepted)
                item_warnings.append(
                    f"Payment method mismatch at {hit.gantry_name}; accepted: {accepted_str}."
                )

            # ------------------------------------------------------------------
            # A. Closed-System Distance Matrix (e.g., PLUS E1/E2/ELITE/LPT)
            # ------------------------------------------------------------------
            if hit.system_type == "closed_matrix":
                if hit.corridor_id not in closed_entries:
                    if hit.role in ("entry_exit", "entry_only"):
                        closed_entries[hit.corridor_id] = hit
                    continue

                entry = closed_entries.pop(hit.corridor_id)
                if entry.gantry_id == hit.gantry_id:
                    continue

                rate = (
                    await self._store.get_closed_matrix_rate(
                        hit.corridor_id,
                        entry.gantry_id,
                        hit.gantry_id,
                        vclass,
                        local_dt.date(),
                    )
                    if vclass
                    else None
                )

                if rate is not None:
                    charge = format_currency_minor(rate["currency_code"], int(rate["amount_minor"]))
                    is_est = False
                else:
                    ccy = COUNTRY_DEFAULT_CURRENCY.get(hit.country_code, "MYR")
                    charge = format_currency_minor(ccy, 0)
                    is_est = True
                    msg = (
                        f"Closed-system matrix tariff not found for {entry.gantry_name} -> "
                        f"{hit.gantry_name} ({vclass or vehicle_profile.value})."
                    )
                    item_warnings.append(msg)
                    global_warnings.append(msg)

                charge_items.append(
                    TollChargeItem(
                        gantry_id=hit.gantry_id,
                        corridor_id=hit.corridor_id,
                        corridor_name=hit.corridor_name,
                        system_type=hit.system_type,
                        country_code=hit.country_code,
                        gantry_name=hit.gantry_name,
                        entry_gantry_id=entry.gantry_id,
                        entry_gantry_name=entry.gantry_name,
                        estimated_crossing_time=local_dt,
                        coordinate=Coordinate(lat=hit.lat, lon=hit.lon),
                        charge=charge,
                        accepted_payments=accepted,
                        lane_layout=lanes,
                        payment_compatible=payment_ok,
                        warnings=item_warnings,
                        is_estimated=is_est,
                    )
                )

            # ------------------------------------------------------------------
            # B. Singapore Time-Varying ERP (Schedule + Public Holiday Override)
            # ------------------------------------------------------------------
            elif hit.system_type == "time_varying_erp":
                holiday_rule = await self._store.get_public_holiday_override(
                    hit.country_code, local_dt.date()
                )
                if holiday_rule == "SUNDAY_PH" or local_dt.weekday() == 6:
                    day_type = "SUNDAY_PH"
                elif local_dt.weekday() == 5:
                    day_type = "SATURDAY"
                else:
                    day_type = "WEEKDAY"

                rate = (
                    await self._store.get_erp_rate(
                        hit.gantry_id,
                        vclass,
                        day_type,
                        local_dt.time().replace(second=0, microsecond=0),
                        local_dt.date(),
                    )
                    if vclass and day_type != "SUNDAY_PH"
                    else None
                )
                amt_minor = int(rate["amount_minor"]) if rate else 0
                ccy = rate["currency_code"] if rate else COUNTRY_DEFAULT_CURRENCY.get(hit.country_code, "SGD")

                charge_items.append(
                    TollChargeItem(
                        gantry_id=hit.gantry_id,
                        corridor_id=hit.corridor_id,
                        corridor_name=hit.corridor_name,
                        system_type=hit.system_type,
                        country_code=hit.country_code,
                        gantry_name=hit.gantry_name,
                        estimated_crossing_time=local_dt,
                        coordinate=Coordinate(lat=hit.lat, lon=hit.lon),
                        charge=format_currency_minor(ccy, amt_minor),
                        accepted_payments=accepted,
                        lane_layout=lanes,
                        payment_compatible=payment_ok,
                        warnings=item_warnings,
                    )
                )

            # ------------------------------------------------------------------
            # C. Open Barrier Plazas & Border Checkpoints (MY / BN / CIQ VEP)
            # ------------------------------------------------------------------
            else:
                is_foreign = vehicle_registration_country.upper() != hit.country_code.upper()
                rates = (
                    await self._store.get_open_rates(
                        hit.gantry_id,
                        hit.country_code,
                        vclass,
                        local_dt.date(),
                        include_foreign_only=is_foreign,
                    )
                    if vclass
                    else []
                )
                total_minor = sum(int(r["amount_minor"]) for r in rates)
                ccy = (
                    rates[0]["currency_code"]
                    if rates
                    else COUNTRY_DEFAULT_CURRENCY.get(hit.country_code, "MYR")
                )
                if is_foreign and any(r.get("foreign_vehicle_only") for r in rates):
                    item_warnings.append(
                        f"Includes foreign-registered vehicle Road Charge / border levy ({hit.country_code})."
                    )

                charge_items.append(
                    TollChargeItem(
                        gantry_id=hit.gantry_id,
                        corridor_id=hit.corridor_id,
                        corridor_name=hit.corridor_name,
                        system_type=hit.system_type,
                        country_code=hit.country_code,
                        gantry_name=hit.gantry_name,
                        estimated_crossing_time=local_dt,
                        coordinate=Coordinate(lat=hit.lat, lon=hit.lon),
                        charge=format_currency_minor(ccy, total_minor),
                        accepted_payments=accepted,
                        lane_layout=lanes,
                        payment_compatible=payment_ok,
                        warnings=item_warnings,
                    )
                )

        # Warn if a closed-system entry never exited (e.g., route ends mid-highway)
        for corridor_id, unmatched_entry in closed_entries.items():
            global_warnings.append(
                f"Entered closed toll corridor {corridor_id} at {unmatched_entry.gantry_name} "
                "without an exit plaza on this route segment."
            )

        enriched_items: list[TollChargeItem] = []
        gantry_badges: list[TollBadge] = []
        for item in charge_items:
            badge = build_toll_badge(item)
            enriched_items.append(item.model_copy(update={"badge": badge}))
            if item.charge.amount_minor > 0 or item.system_type == "closed_matrix":
                gantry_badges.append(badge)

        totals = aggregate_totals(item.charge for item in enriched_items)
        has_tolls = any(t.amount_minor > 0 for t in totals)
        return TollSummary(
            has_tolls=has_tolls,
            items=enriched_items,
            gantry_badges=gantry_badges,
            totals_by_currency=totals,
            display_total=format_multi_currency_display(totals),
            warnings=global_warnings,
        )
