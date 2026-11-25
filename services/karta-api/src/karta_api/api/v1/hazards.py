from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from karta_api.deps import AppContainer, get_container
from karta_api.models.realtime import (
    HazardRecord,
    HazardReportRequest,
    HazardVoteRequest,
    NearbyHazardsResponse,
)
from karta_api.realtime.geo_filter import compute_dynamic_radius_meters
from karta_api.routing.traffic import TrafficObservation

router = APIRouter(prefix="/hazards", tags=["hazards"])


@router.post("", response_model=HazardRecord)
async def create_hazard(
    req: HazardReportRequest,
    c: AppContainer = Depends(get_container),
) -> HazardRecord:
    hazard, _merged = await c.realtime_hub.report_hazard(req)
    return hazard


@router.get("/nearby", response_model=NearbyHazardsResponse)
async def get_nearby_hazards(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lon: float = Query(..., ge=-180.0, le=180.0),
    heading: float | None = Query(None, ge=0.0, lt=360.0),
    speed_kmh: float = Query(0.0, ge=0.0, le=260.0),
    max_radius_m: float | None = Query(None, ge=250.0, le=25000.0),
    c: AppContainer = Depends(get_container),
) -> NearbyHazardsResponse:
    hazards = await c.realtime_hub.query_nearby_hazards(
        lat=lat,
        lon=lon,
        heading_deg=heading,
        speed_kmh=speed_kmh,
        max_radius_m=max_radius_m,
    )
    eff_radius = compute_dynamic_radius_meters(speed_kmh, None, max_radius_m)
    return NearbyHazardsResponse(
        effective_radius_meters=eff_radius,
        heading_deg=heading,
        speed_kmh=speed_kmh,
        count=len(hazards),
        hazards=hazards,
    )


@router.post("/{hazard_id}/vote", response_model=HazardRecord)
async def vote_hazard(
    hazard_id: str,
    req: HazardVoteRequest,
    c: AppContainer = Depends(get_container),
) -> HazardRecord:
    try:
        updated = await c.realtime_hub.vote_hazard(
            hazard_id=hazard_id,
            vote=req.vote,
            voter_session_id=req.voter_session_id,
            coordinate=req.coordinate,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid hazard_id: {exc}") from exc
    if updated is None:
        raise HTTPException(status_code=404, detail="Hazard not found.")
    return updated


@router.post("/traffic-probe")
async def ingest_traffic_probe(
    osm_way_id: int = Query(..., gt=0),
    speed_kmh: int = Query(..., ge=0, le=160),
    valhalla_edge_id: int | None = Query(None),
    c: AppContainer = Depends(get_container),
) -> dict[str, object]:
    count = await c.traffic_manager.record_observations(
        [TrafficObservation(osm_way_id=osm_way_id, speed_kmh=speed_kmh, valhalla_edge_id=valhalla_edge_id)]
    )
    epoch = await c.traffic_manager.bump_traffic_epoch()
    return {"recorded": count, "traffic_epoch": epoch}
