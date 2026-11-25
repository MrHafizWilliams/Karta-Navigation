from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field

from karta_api.models.common import Coordinate


class FuelGrade(StrEnum):
    # Malaysia (MYR / RM)
    RON95 = "RON95"
    RON97 = "RON97"
    DIESEL_B10 = "DIESEL_B10"
    DIESEL_EURO5 = "DIESEL_EURO5"
    # Singapore (SGD / $)
    OCTANE_92 = "OCTANE_92"
    OCTANE_95 = "OCTANE_95"
    OCTANE_98 = "OCTANE_98"
    DIESEL_SG = "DIESEL_SG"
    # Brunei (BND / B$)
    RON97_BN = "RON97_BN"
    RON92_BN = "RON92_BN"
    DIESEL_BN = "DIESEL_BN"


class FuelGradeQuote(BaseModel):
    fuel_grade: FuelGrade
    price_minor: int
    currency_code: str
    formatted_price: str
    is_subsidized: bool = False
    source: str = "official_baseline"
    confirmations: int = 1
    reported_at: datetime


class FuelStationComparison(BaseModel):
    poi_id: int
    name: str
    brand: str | None = None
    country_code: str
    coordinate: Coordinate
    opening_hours: str | None = None
    distance_along_route_km: float | None = None
    detour_meters: float = 0.0
    detour_minutes: int = 0
    selected_grade: FuelGrade
    selected_price_minor: int
    selected_formatted_price: str
    currency_code: str
    is_cheapest: bool = False
    prices: list[FuelGradeQuote] = Field(default_factory=list)


class FuelAlongRouteRequest(BaseModel):
    polyline6: str = Field(..., min_length=4)
    fuel_grade: FuelGrade | None = None
    country_code: str | None = Field(None, pattern="^(MY|SG|BN)$")
    max_detour_meters: float = Field(1800.0, ge=100.0, le=8000.0)
    sort_by: str = Field("price", pattern="^(price|detour|distance)$")
    limit: int = Field(20, ge=1, le=50)


class FuelComparisonResponse(BaseModel):
    country_code: str
    fuel_grade: FuelGrade
    cheapest_poi_id: int | None = None
    cheapest_formatted_price: str | None = None
    count: int
    stations: list[FuelStationComparison] = Field(default_factory=list)


class FuelPriceUpdateRequest(BaseModel):
    fuel_grade: FuelGrade
    price_minor: int = Field(..., gt=10, lt=2000)
    reporter_session_id: str | None = None


# ============================================================================
# SMART CALENDAR & TIME-TO-LEAVE MODELS
# ============================================================================
class CalendarFeedRequest(BaseModel):
    user_token: str = Field("karta-commuter-default", min_length=3, max_length=96)
    provider: str = Field("ics_url", pattern="^(ics_url|facebook_ics|google_oauth|manual)$")
    label: str = Field(..., min_length=1, max_length=120)
    feed_url: str | None = None


class CalendarIcsImportRequest(BaseModel):
    user_token: str = Field("karta-commuter-default", min_length=3, max_length=96)
    provider: str = Field("ics_url", pattern="^(ics_url|facebook_ics|google_oauth|manual)$")
    ics_content: str = Field(..., min_length=20)


class CalendarEventCreateRequest(BaseModel):
    user_token: str = Field("karta-commuter-default", min_length=3, max_length=96)
    title: str = Field(..., min_length=1, max_length=160)
    provider: str = Field("manual", pattern="^(ics_url|facebook_ics|google_oauth|manual)$")
    location_text: str | None = Field(None, max_length=240)
    destination: Coordinate | None = None
    starts_at: datetime
    ends_at: datetime | None = None
    parking_buffer_sec: int = Field(600, ge=0, le=3600)


class CalendarEventItem(BaseModel):
    id: str
    title: str
    provider: str
    location_text: str | None = None
    destination: Coordinate | None = None
    country_code: str | None = None
    starts_at: datetime
    ends_at: datetime | None = None
    parking_buffer_sec: int = 600


class TimeToLeaveEvaluation(BaseModel):
    event: CalendarEventItem
    baseline_duration_seconds: float
    live_traffic_duration_seconds: float
    traffic_delay_seconds: float
    distance_km: float
    estimated_toll_display: str = "Free"
    recommended_departure_at: datetime
    minutes_until_departure: int
    urgency_level: str  # upcoming | prepare | leave_now | running_late
    advisory_message: str


class EvaluateDeparturesRequest(BaseModel):
    user_token: str = Field("karta-commuter-default", min_length=3, max_length=96)
    origin: Coordinate
    horizon_hours: int = Field(24, ge=1, le=72)


class EvaluateDeparturesResponse(BaseModel):
    evaluated_at: datetime
    origin: Coordinate
    count: int
    evaluations: list[TimeToLeaveEvaluation] = Field(default_factory=list)


# ============================================================================
# PRIVACY-FIRST CARPOOL / RIDE-SHARING MODELS
# ============================================================================
class CarpoolOfferCreateRequest(BaseModel):
    driver_token: str = Field(..., min_length=4, max_length=96)
    driver_alias: str = Field(..., min_length=2, max_length=64)
    verified_badge: str | None = Field(None, max_length=48)
    origin: Coordinate
    destination: Coordinate
    departure_at: datetime
    flexibility_minutes: int = Field(20, ge=5, le=90)
    seats_total: int = Field(3, ge=1, le=6)
    notes: str | None = Field(None, max_length=180)


class CarpoolOfferPublic(BaseModel):
    id: str
    driver_alias: str
    verified_badge: str | None = None
    country_code: str
    origin_zone_center: Coordinate
    origin_landmark_name: str
    dest_zone_center: Coordinate
    dest_landmark_name: str
    privacy_radius_m: int = 500
    route_polyline6: str
    route_distance_km: float
    departure_at: datetime
    flexibility_minutes: int
    seats_total: int
    seats_available: int
    estimated_split_minor: int
    estimated_split_formatted: str
    currency_code: str
    notes: str | None = None
    status: str = "active"


class CarpoolSearchRequest(BaseModel):
    rider_token: str = Field(..., min_length=4, max_length=96)
    pickup: Coordinate
    dropoff: Coordinate
    departure_at: datetime
    max_detour_meters: float = Field(2500.0, ge=300.0, le=8000.0)
    time_window_minutes: int = Field(30, ge=5, le=120)


class CarpoolMatchCandidate(BaseModel):
    offer: CarpoolOfferPublic
    pickup_zone_center: Coordinate
    pickup_landmark_name: str
    dropoff_zone_center: Coordinate
    dropoff_landmark_name: str
    overlap_pct: float
    detour_meters: float
    split_cost_minor: int
    split_cost_formatted: str
    currency_code: str


class CarpoolMatchRequestCreate(BaseModel):
    rider_token: str = Field(..., min_length=4, max_length=96)
    rider_alias: str = Field(..., min_length=2, max_length=64)
    pickup: Coordinate
    dropoff: Coordinate
    rendezvous_note: str | None = Field(None, max_length=160)


class CarpoolMatchRespondRequest(BaseModel):
    driver_token: str = Field(..., min_length=4, max_length=96)
    action: str = Field(..., pattern="^(accept|decline)$")
    rendezvous_note: str | None = Field(None, max_length=160)


class CarpoolMatchRecord(BaseModel):
    id: str
    offer_id: str
    driver_alias: str
    rider_alias: str
    pickup_zone_center: Coordinate
    pickup_landmark_name: str
    dropoff_zone_center: Coordinate
    dropoff_landmark_name: str
    overlap_pct: float
    detour_meters: float
    split_cost_minor: int
    split_cost_formatted: str
    currency_code: str
    status: str
    rendezvous_note: str | None = None
    privacy_shield_active: bool = True


# ============================================================================
# CUSTOM NAVIGATION VOICE PACKS
# ============================================================================
VOICE_CUE_SLOTS: tuple[str, ...] = (
    "turn_left",
    "turn_right",
    "keep_left",
    "keep_right",
    "straight",
    "roundabout",
    "arrived",
    "toll_ahead",
    "speed_camera",
    "hazard_police",
    "hazard_accident",
    "rerouting",
)


class CustomVoicePackCreateRequest(BaseModel):
    owner_token: str = Field("karta-driver-default", min_length=3, max_length=96)
    name: str = Field(..., min_length=1, max_length=80)
    locale: str = Field("en-MY", max_length=16)
    base_tts_voice: str = Field("karta_studio_en", max_length=48)


class CustomVoiceClipUploadRequest(BaseModel):
    mime_type: str = Field("audio/webm", max_length=48)
    duration_ms: int = Field(0, ge=0, le=15000)
    audio_base64: str = Field(..., min_length=8, max_length=400_000)


class CustomVoiceClipMeta(BaseModel):
    cue_key: str
    mime_type: str
    duration_ms: int
    audio_base64: str | None = None
    updated_at: datetime


class CustomVoicePackRecord(BaseModel):
    id: str
    owner_token: str
    name: str
    locale: str
    base_tts_voice: str
    recorded_cues: list[str] = Field(default_factory=list)
    total_cue_slots: int = len(VOICE_CUE_SLOTS)
    clips: dict[str, CustomVoiceClipMeta] = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime
