from __future__ import annotations

import hashlib
import json

from fastapi import APIRouter, Depends, Response

from karta_api.deps import AppContainer, get_container
from karta_api.models.routing import TilePrefetchRequest, TilePrefetchResponse
from karta_api.routing.tile_prefetch import build_predictive_tile_plan

router = APIRouter(prefix="/tiles", tags=["predictive-caching"])


def _tile_plan_cache_key(req: TilePrefetchRequest) -> str:
    pos = (
        [round(req.current_position.lat, 3), round(req.current_position.lon, 3)]
        if req.current_position
        else None
    )
    speed_bucket = int(req.current_speed_kmh // 15) * 15
    raw = json.dumps(
        {
            "p": hashlib.sha256(req.polyline6.encode("utf-8")).hexdigest()[:16],
            "pos": pos,
            "sb": speed_bucket,
            "z": req.zoom_levels,
            "m": len(req.maneuver_coordinates),
            "arch": req.region_archive,
            "max": req.max_tiles,
        },
        sort_keys=True,
    )
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:20]
    return f"karta:cache:tiles:{digest}"


@router.post("/prefetch-plan", response_model=TilePrefetchResponse)
async def compute_predictive_tile_plan(
    req: TilePrefetchRequest,
    response: Response,
    c: AppContainer = Depends(get_container),
) -> TilePrefetchResponse:
    """
    Generates a speed-adaptive Web Mercator (z/x/y) predictive vector tile prefetch
    plan along the active route corridor and probable next turns (±60° exit fan-out).
    """
    response.headers["Cache-Control"] = "public, max-age=180, stale-while-revalidate=600"
    ckey = _tile_plan_cache_key(req)
    cached = await c.redis_cache.get_cached_json(ckey)
    if cached is not None:
        cached["cached"] = True
        return TilePrefetchResponse.model_validate(cached)

    plan = build_predictive_tile_plan(req, pmtiles_public_url=c.settings.pmtiles_public_url)
    await c.redis_cache.set_cached_json(ckey, plan.model_dump(mode="json"), ttl_seconds=300)
    return plan
