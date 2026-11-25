from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field

from karta_api.models.common import Coordinate, CurrencyAmount


class PaymentMethod(StrEnum):
    TNG_CARD = "TNG_CARD"
    SMARTTAG = "SMARTTAG"
    RFID = "RFID"
    OPEN_PAYMENT_CARD = "OPEN_PAYMENT_CARD"
    ANPR_JUSTGO = "ANPR_JUSTGO"
    ERP_IU = "ERP_IU"
    ERP2_OBU = "ERP2_OBU"
    CASH = "CASH"
    BRUNEI_TOLL_CARD = "BRUNEI_TOLL_CARD"


class VehicleProfile(StrEnum):
    CAR = "car"
    MOTORCYCLE = "motorcycle"
    TAXI = "taxi"
    VAN_2AXLE = "van_2axle"
    TRUCK_3AXLE = "truck_3axle"
    BUS = "bus"


class TollLaneGuidance(BaseModel):
    lane: int = Field(..., ge=1)
    methods: list[PaymentMethod]


class TollBadge(BaseModel):
    """Compact, driver-scannable gantry & payment badge for route comparison cards."""

    badge_id: str
    label: str = Field(..., description="e.g. 'PLUS Highway', 'Penang Bridge', 'Singapore ERP'")
    payment_label: str = Field(..., description="e.g. 'Touch \\'n Go RFID', 'Singapore ERP 2.0'")
    badge_kind: str = Field(
        ...,
        description="Semantic kind: plus_highway, bridge, urban_expressway, sg_erp, border_ciq, brunei_bridge",
    )
    country_code: str
    gantry_name: str
    entry_gantry_name: str | None = None
    charge: CurrencyAmount
    accepted_payments: list[PaymentMethod] = Field(default_factory=list)
    crossing_time_local: str | None = Field(
        None, description="Local crossing clock e.g. '08:35 SGT' or '09:15 MYT'"
    )


class TollChargeItem(BaseModel):
    gantry_id: str
    corridor_id: str
    corridor_name: str
    system_type: str
    country_code: str
    gantry_name: str
    entry_gantry_id: str | None = None
    entry_gantry_name: str | None = None
    estimated_crossing_time: datetime
    coordinate: Coordinate
    charge: CurrencyAmount
    accepted_payments: list[PaymentMethod]
    lane_layout: list[TollLaneGuidance] = Field(default_factory=list)
    payment_compatible: bool = True
    warnings: list[str] = Field(default_factory=list)
    is_estimated: bool = False
    badge: TollBadge | None = None


class TollSummary(BaseModel):
    has_tolls: bool
    items: list[TollChargeItem] = Field(default_factory=list)
    gantry_badges: list[TollBadge] = Field(
        default_factory=list,
        description="Ordered scannable toll badges (PLUS Highway, Penang Bridge, Touch 'n Go RFID, SG ERP, etc.)",
    )
    totals_by_currency: list[CurrencyAmount] = Field(default_factory=list)
    display_total: str = Field(..., description="Human-readable combined display, e.g. 'RM 34.44 + $2.00' or 'Free'")
    warnings: list[str] = Field(default_factory=list)


class GantryInfo(BaseModel):
    gantry_id: str
    corridor_id: str
    corridor_name: str
    operator_name: str
    system_type: str
    country_code: str
    external_code: str | None = None
    name: str
    role: str
    direction_code: str | None = None
    direction_bearing: int | None = None
    accepted_payments: list[PaymentMethod]
    lane_layout: list[TollLaneGuidance] = Field(default_factory=list)
    coordinate: Coordinate


class TollEstimateRequest(BaseModel):
    polyline6: str = Field(..., min_length=2, description="Valhalla precision-6 encoded route geometry")
    duration_seconds: float = Field(..., gt=0)
    departure_time: datetime | None = None
    vehicle_profile: VehicleProfile = VehicleProfile.CAR
    vehicle_registration_country: str = Field("MY", pattern="^(MY|SG|BN|[A-Z]{2})$")
    payment_methods: list[PaymentMethod] = Field(
        default_factory=lambda: [
            PaymentMethod.RFID,
            PaymentMethod.TNG_CARD,
            PaymentMethod.ERP2_OBU,
        ]
    )
