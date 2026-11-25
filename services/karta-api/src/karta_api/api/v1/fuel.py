from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from karta_api.deps import AppContainer, get_container
from karta_api.models.commuter import (
    FuelAlongRouteRequest,
    FuelComparisonResponse,
    FuelGrade,
    FuelGradeQuote,
    FuelPriceUpdateRequest,
)

router = APIRouter(prefix="/fuel", tags=["fuel"])


@router.post("/along-route", response_model=FuelComparisonResponse)
async def fuel_stations_along_route(
    req: FuelAlongRouteRequest,
    c: AppContainer = Depends(get_container),
) -> FuelComparisonResponse:
    cc, grade, stations = await c.community_repo.fuel_stations_along_route(
        polyline6=req.polyline6,
        fuel_grade=req.fuel_grade,
        country_code=req.country_code,
        max_detour_meters=req.max_detour_meters,
        sort_by=req.sort_by,
        limit=req.limit,
    )
    cheapest = next((s for s in stations if s.is_cheapest), None)
    return FuelComparisonResponse(
        country_code=cc,
        fuel_grade=grade,
        cheapest_poi_id=cheapest.poi_id if cheapest else None,
        cheapest_formatted_price=cheapest.selected_formatted_price if cheapest else None,
        count=len(stations),
        stations=stations,
    )


@router.get("/nearby", response_model=FuelComparisonResponse)
async def fuel_stations_nearby(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lon: float = Query(..., ge=-180.0, le=180.0),
    radius_m: float = Query(5000.0, ge=300.0, le=25000.0),
    fuel_grade: FuelGrade | None = Query(None),
    limit: int = Query(20, ge=1, le=50),
    c: AppContainer = Depends(get_container),
) -> FuelComparisonResponse:
    cc, grade, stations = await c.community_repo.fuel_stations_nearby(
        lat=lat,
        lon=lon,
        radius_m=radius_m,
        fuel_grade=fuel_grade,
        limit=limit,
    )
    cheapest = next((s for s in stations if s.is_cheapest), None)
    return FuelComparisonResponse(
        country_code=cc,
        fuel_grade=grade,
        cheapest_poi_id=cheapest.poi_id if cheapest else None,
        cheapest_formatted_price=cheapest.selected_formatted_price if cheapest else None,
        count=len(stations),
        stations=stations,
    )


@router.post("/stations/{poi_id}/prices", response_model=FuelGradeQuote)
async def update_station_fuel_price(
    poi_id: int,
    req: FuelPriceUpdateRequest,
    c: AppContainer = Depends(get_container),
) -> FuelGradeQuote:
    try:
        result = await c.community_repo.upsert_fuel_price(
            poi_id=poi_id,
            fuel_grade=req.fuel_grade,
            price_minor=req.price_minor,
            reporter_session_id=req.reporter_session_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    if result is None:
        raise HTTPException(status_code=404, detail="Fuel station POI not found.")

    quote, cc, coord = result
    await c.realtime_hub.broadcast_fuel_price_update(
        {
            "poi_id": poi_id,
            "country_code": cc,
            "fuel_grade": quote.fuel_grade.value,
            "price_minor": quote.price_minor,
            "formatted_price": quote.formatted_price,
            "coordinate": coord.model_dump(),
        }
    )
    return quote
