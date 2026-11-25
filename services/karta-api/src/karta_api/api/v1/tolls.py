from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Query

from karta_api.deps import AppContainer, get_container
from karta_api.models.tolls import GantryInfo, TollEstimateRequest, TollSummary

router = APIRouter(prefix="/tolls", tags=["tolls"])
REGIONAL_TZ = ZoneInfo("Asia/Kuala_Lumpur")


@router.get("/gantries", response_model=list[GantryInfo])
async def list_toll_gantries(
    country_code: str | None = Query(None, pattern="^(MY|SG|BN)$"),
    corridor_id: str | None = Query(None),
    min_lon: float | None = Query(None, ge=-180.0, le=180.0),
    min_lat: float | None = Query(None, ge=-90.0, le=90.0),
    max_lon: float | None = Query(None, ge=-180.0, le=180.0),
    max_lat: float | None = Query(None, ge=-90.0, le=90.0),
    c: AppContainer = Depends(get_container),
) -> list[GantryInfo]:
    return await c.toll_repo.list_gantries(
        country_code=country_code,
        corridor_id=corridor_id,
        min_lon=min_lon,
        min_lat=min_lat,
        max_lon=max_lon,
        max_lat=max_lat,
    )


@router.post("/estimate", response_model=TollSummary)
async def estimate_polyline_tolls(
    req: TollEstimateRequest,
    c: AppContainer = Depends(get_container),
) -> TollSummary:
    departure_dt = req.departure_time or datetime.now(tz=REGIONAL_TZ)
    if departure_dt.tzinfo is None:
        departure_dt = departure_dt.replace(tzinfo=REGIONAL_TZ)

    return await c.toll_engine.calculate_route_tolls(
        polyline6=req.polyline6,
        duration_seconds=req.duration_seconds,
        departure_time=departure_dt,
        vehicle_profile=req.vehicle_profile,
        vehicle_registration_country=req.vehicle_registration_country,
        user_payment_methods=req.payment_methods,
    )
