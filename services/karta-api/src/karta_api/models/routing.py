from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field

from karta_api.models.common import Coordinate, CountryContext, CurrencyAmount
from karta_api.models.realtime import CongestionSegment, HazardRecord
from karta_api.models.tolls import PaymentMethod, TollSummary, VehicleProfile


class RoutingProfileId(StrEnum):
    DRIVE_FASTEST = "drive_fastest"
    DRIVE_AVOID_TOLLS = "drive_avoid_tolls"
    DRIVE_NO_HIGHWAYS = "drive_no_highways"
    DRIVE_MOTORCYCLE = "drive_motorcycle"
    WALK = "walk"
    CYCLE = "cycle"
    TRANSIT = "transit"


class RouteRequest(BaseModel):
    origin: Coordinate
    destination: Coordinate
    waypoints: list[Coordinate] = Field(default_factory=list, max_length=15)
    profile: RoutingProfileId = RoutingProfileId.DRIVE_FASTEST
    vehicle_profile: VehicleProfile = VehicleProfile.CAR
    vehicle_registration_country: str = Field("MY", pattern="^[A-Z]{2}$")
    payment_methods: list[PaymentMethod] = Field(
        default_factory=lambda: [
            PaymentMethod.RFID,
            PaymentMethod.TNG_CARD,
            PaymentMethod.SMARTTAG,
            PaymentMethod.OPEN_PAYMENT_CARD,
            PaymentMethod.ERP_IU,
            PaymentMethod.ERP2_OBU,
        ]
    )
    avoid_tolls: bool = False
    avoid_highways: bool = False
    avoid_ferries: bool = False
    alternates: int = Field(2, ge=0, le=3)
    include_toll_free_comparison: bool = True
    departure_time: datetime | None = None
    arrive_by: datetime | None = None
    language: str = Field("en-US", description="Valhalla maneuver instruction language tag")


class RouteManeuver(BaseModel):
    type: int
    instruction: str
    verbal_pre_transition_instruction: str | None = None
    street_names: list[str] = Field(default_factory=list)
    distance_km: float
    time_seconds: float
    begin_shape_index: int
    end_shape_index: int
    toll: bool = False
    highway: bool = False
    travel_mode: str = "drive"
    transit_info: dict | None = None


class RouteLeg(BaseModel):
    distance_km: float
    duration_seconds: float
    shape_polyline6: str
    maneuvers: list[RouteManeuver]


class CandidateRoute(BaseModel):
    route_index: int
    profile_used: str
    summary_label: str
    # Human-friendly UX differentiation metadata
    ux_primary_tag: str = Field("", description="Scannable tag e.g. 'Fastest • 38 min', 'Cheapest Toll • Save RM 4.20'")
    ux_badge_kind: str = Field(
        "balanced",
        description="Semantic badge token: fastest, cheapest_toll, toll_free, fewer_turns, avoids_highway, shortest, balanced",
    )
    ux_highlights: list[str] = Field(default_factory=list)
    turn_count: int = Field(0, ge=0)
    primary_corridor_name: str | None = None
    eta_delta_seconds: float = 0.0
    distance_km: float
    duration_seconds: float
    baseline_duration_seconds: float | None = None
    live_traffic_delay_seconds: float = 0.0
    has_toll_roads: bool
    has_highways: bool
    countries_crossed: list[str] = Field(default_factory=list)
    legs: list[RouteLeg]
    tolls: TollSummary
    congestion_segments: list[CongestionSegment] = Field(default_factory=list)
    active_hazards_on_route: list[HazardRecord] = Field(default_factory=list)


class PrefetchTileCoord(BaseModel):
    z: int = Field(..., ge=0, le=18)
    x: int = Field(..., ge=0)
    y: int = Field(..., ge=0)
    priority: int = Field(1, ge=0, le=3, description="0=next turn/horizon, 1=corridor, 2=alternate turn fan-out")
    reason: str = Field("corridor", description="corridor | next_turn | alternate_turn | horizon_buffer")
    tile_url: str | None = None


class TilePrefetchRequest(BaseModel):
    polyline6: str = Field(..., min_length=2)
    current_position: Coordinate | None = None
    current_speed_kmh: float = Field(80.0, ge=0.0, le=260.0)
    maneuver_coordinates: list[Coordinate] = Field(default_factory=list, max_length=20)
    zoom_levels: list[int] | None = None
    max_tiles: int = Field(96, ge=8, le=256)
    region_archive: str = Field("my-sg-bn-full", description="PMTiles archive basename served by go-pmtiles")


class TilePrefetchResponse(BaseModel):
    lookahead_km: float
    zoom_levels: list[int]
    tile_count: int
    tiles: list[PrefetchTileCoord]
    cached: bool = False
    planning_ms: float = 0.0


class TollSavingsComparison(BaseModel):
    toll_free_route_index: int
    extra_duration_seconds: float
    extra_distance_km: float
    savings_by_currency: list[CurrencyAmount]
    summary_text: str


class RouteResponse(BaseModel):
    origin_country: CountryContext | None = None
    destination_country: CountryContext | None = None
    departure_time: datetime
    routes: list[CandidateRoute]
    toll_free_comparison: TollSavingsComparison | None = None
    cached: bool = False
    traffic_epoch: int = 0
    exclusions_applied: int = 0
