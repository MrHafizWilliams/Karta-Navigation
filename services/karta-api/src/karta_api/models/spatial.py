from __future__ import annotations

from pydantic import BaseModel, Field

from karta_api.models.common import Coordinate, CountryContext
from karta_api.models.tolls import PaymentMethod, TollLaneGuidance


class PoiItem(BaseModel):
    id: int
    name: str
    category: str
    subcategory: str | None = None
    brand: str | None = None
    country_code: str | None = None
    coordinate: Coordinate
    distance_meters: float | None = None
    ev_metadata: dict | None = None
    opening_hours: str | None = None


class PoiBBoxResponse(BaseModel):
    source: str = Field(..., description="'redis_geo' or 'postgis'")
    query_ms: float
    count: int
    items: list[PoiItem]


class ApproachingSpeedZone(BaseModel):
    id: int
    zone_type: str
    road_name: str | None = None
    limit_kmh: int
    distance_meters: float
    coordinate: Coordinate


class ApproachingGantry(BaseModel):
    gantry_id: str
    name: str
    corridor_id: str
    system_type: str
    distance_meters: float
    accepted_payments: list[PaymentMethod]
    lane_layout: list[TollLaneGuidance] = Field(default_factory=list)
    coordinate: Coordinate


class RoadContextResponse(BaseModel):
    coordinate: Coordinate
    country: CountryContext | None = None
    road_name: str | None = None
    road_ref: str | None = None
    highway_class: str | None = None
    speed_limit_kmh: int | None = None
    speed_limit_source: str | None = None
    lanes_total: int | None = None
    turn_lanes: list[str] = Field(default_factory=list)
    is_toll: bool = False
    is_bridge: bool = False
    is_tunnel: bool = False
    approaching_speed_zones: list[ApproachingSpeedZone] = Field(default_factory=list)
    approaching_gantries: list[ApproachingGantry] = Field(default_factory=list)
