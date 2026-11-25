from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field

from karta_api.models.common import Coordinate


class HazardCategory(StrEnum):
    POLICE = "police"
    ACCIDENT = "accident"
    POTHOLE = "pothole"
    HIDDEN_VEHICLE = "hidden_vehicle"
    ROAD_DEBRIS = "road_debris"
    ROAD_CLOSURE = "road_closure"


class HazardSeverity(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class HazardStatus(StrEnum):
    ACTIVE = "active"
    RESOLVED = "resolved"
    EXPIRED = "expired"


class HazardVoteType(StrEnum):
    CONFIRM = "confirm"
    CLEARED = "cleared"


class CongestionLevel(StrEnum):
    FREE = "free"
    MODERATE = "moderate"
    HEAVY = "heavy"
    BLOCKED = "blocked"


class HazardReportRequest(BaseModel):
    category: HazardCategory
    subtype: str | None = Field(None, max_length=64)
    severity: HazardSeverity = HazardSeverity.MEDIUM
    coordinate: Coordinate
    heading_deg: float | None = Field(None, ge=0.0, lt=360.0)
    affects_both_directions: bool = False
    lane_hint: str | None = Field(None, max_length=64)
    description: str | None = Field(None, max_length=240)
    source: str = Field("radial", pattern="^(radial|voice|api|grpc)$")
    reporter_session_id: str | None = Field(None, max_length=96)


class HazardVoteRequest(BaseModel):
    vote: HazardVoteType
    coordinate: Coordinate | None = None
    voter_session_id: str | None = Field(None, max_length=96)


class HazardRecord(BaseModel):
    id: str
    category: HazardCategory
    subtype: str | None = None
    severity: HazardSeverity = HazardSeverity.MEDIUM
    status: HazardStatus = HazardStatus.ACTIVE
    coordinate: Coordinate
    road_heading_deg: float | None = None
    oneway: int = 0
    affects_both_directions: bool = False
    osm_way_id: int | None = None
    valhalla_edge_id: int | None = None
    road_name: str | None = None
    road_ref: str | None = None
    country_code: str | None = None
    lane_hint: str | None = None
    description: str | None = None
    source: str = "radial"
    confirmations: int = 1
    denials: int = 0
    confidence_score: float = 0.65
    distance_meters: float | None = None
    bearing_delta_deg: float | None = None
    on_active_route: bool = False
    created_at: datetime
    expires_at: datetime


class NearbyHazardsResponse(BaseModel):
    effective_radius_meters: float
    heading_deg: float | None = None
    speed_kmh: float = 0.0
    count: int
    hazards: list[HazardRecord] = Field(default_factory=list)


class CongestionSegment(BaseModel):
    start_fraction: float = Field(..., ge=0.0, le=1.0)
    end_fraction: float = Field(..., ge=0.0, le=1.0)
    severity: CongestionLevel
    speed_kmh: int
    delay_seconds: float = 0.0
    hazard_id: str | None = None
    label: str | None = None


class TelemetryUpdate(BaseModel):
    session_id: str
    coordinate: Coordinate
    heading_deg: float = Field(0.0, ge=0.0, lt=360.0)
    speed_kmh: float = Field(0.0, ge=0.0, le=260.0)
    country_code: str | None = None
    route_id: str | None = None
    route_polyline6: str | None = None
    route_profile: str = "drive_fastest"
    vehicle_profile: str = "car"
    vehicle_registration_country: str = "MY"
    destination: Coordinate | None = None
    waypoints: list[Coordinate] = Field(default_factory=list)


class RerouteProposal(BaseModel):
    proposal_id: str
    reason: str
    trigger_hazard_id: str | None = None
    trigger_category: HazardCategory | None = None
    current_delay_seconds: float = 0.0
    time_saved_seconds: float = 0.0
    toll_delta_display: str = "No toll change"
    auto_accept_seconds: int = 0
    proposed_route: dict[str, Any]


class VoiceIntentRequest(BaseModel):
    transcript: str = Field(..., min_length=1, max_length=320)
    locale: str = "en-MY"
    coordinate: Coordinate | None = None
    heading_deg: float | None = None


class VoiceIntentResponse(BaseModel):
    intent: str  # report_hazard | confirm_hazard | clear_hazard | accept_reroute | cancel | unknown
    confidence: float = Field(..., ge=0.0, le=1.0)
    hazard_category: HazardCategory | None = None
    subtype: str | None = None
    severity: HazardSeverity = HazardSeverity.MEDIUM
    direction: str = "ahead"  # ahead | opposite
    lane_hint: str | None = None
    road_hint: str | None = None
    confirmation_speech: str
    matched_terms: list[str] = Field(default_factory=list)
    normalized_transcript: str
