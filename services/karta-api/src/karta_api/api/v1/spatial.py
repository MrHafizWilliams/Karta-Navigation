from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from karta_api.deps import AppContainer, get_container
from karta_api.models.common import Coordinate
from karta_api.models.spatial import RoadContextResponse

router = APIRouter(prefix="/spatial", tags=["spatial"])


@router.get("/road-context", response_model=RoadContextResponse)
async def get_road_context(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lon: float = Query(..., ge=-180.0, le=180.0),
    heading: float | None = Query(None, ge=0.0, lt=360.0),
    lookahead_m: float = Query(1500.0, ge=100.0, le=5000.0),
    c: AppContainer = Depends(get_container),
) -> RoadContextResponse:
    country = await c.spatial_repo.resolve_country_at_point(lat, lon)
    road = await c.spatial_repo.nearest_road_segment(lat, lon, heading_deg=heading)

    # Sub-5ms Redis Geo lookahead with automatic PostGIS fallback
    speeds = await c.redis_cache.geosearch_nearby_speed_zones(lat, lon, radius_m=min(lookahead_m, 2000.0))
    if speeds is None:
        speeds = await c.spatial_repo.nearby_speed_zones(lat, lon, radius_m=min(lookahead_m, 2000.0))

    return RoadContextResponse(
        coordinate=Coordinate(lat=lat, lon=lon),
        country=country,
        road_name=road["road_name"] if road else None,
        road_ref=road["road_ref"] if road else None,
        highway_class=road["highway_class"] if road else None,
        speed_limit_kmh=road["speed_limit_kmh"] if road else None,
        speed_limit_source=road["speed_limit_source"] if road else None,
        lanes_total=road["lanes_total"] if road else None,
        turn_lanes=road["turn_lanes"] if road else [],
        is_toll=False,
        is_bridge=bool(road["is_bridge"]) if road else False,
        is_tunnel=bool(road["is_tunnel"]) if road else False,
        approaching_speed_zones=speeds,
        approaching_gantries=[],
    )
