from __future__ import annotations

import hashlib
import json
import time

from fastapi import APIRouter, Depends, HTTPException, Query, Response

from karta_api.deps import AppContainer, get_container
from karta_api.models.spatial import PoiBBoxResponse

router = APIRouter(prefix="/pois", tags=["pois"])


def _search_cache_key(
    q: str,
    lat: float | None,
    lon: float | None,
    category: str | None,
    country_code: str | None,
    limit: int,
) -> str:
    raw = json.dumps(
        {
            "q": q.strip().lower(),
            "lat": round(lat, 2) if lat is not None else None,
            "lon": round(lon, 2) if lon is not None else None,
            "cat": category,
            "cc": country_code,
            "lim": limit,
        },
        sort_keys=True,
    )
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:20]
    return f"karta:cache:poi_search:{digest}"


@router.get("/bbox", response_model=PoiBBoxResponse)
async def get_pois_in_bbox(
    min_lon: float = Query(..., ge=-180.0, le=180.0),
    min_lat: float = Query(..., ge=-90.0, le=90.0),
    max_lon: float = Query(..., ge=-180.0, le=180.0),
    max_lat: float = Query(..., ge=-90.0, le=90.0),
    category: str | None = Query(None, description="e.g. fuel, ev_charging, rest_area, parking, food, transit"),
    limit: int = Query(150, ge=1, le=500),
    c: AppContainer = Depends(get_container),
) -> PoiBBoxResponse:
    if min_lon >= max_lon or min_lat >= max_lat:
        raise HTTPException(status_code=400, detail="Invalid bounding box: min must be less than max.")

    t0 = time.perf_counter()
    items = await c.redis_cache.geosearch_pois_bbox(
        min_lon=min_lon,
        min_lat=min_lat,
        max_lon=max_lon,
        max_lat=max_lat,
        category=category,
        limit=limit,
    )
    source = "redis_geo"

    if items is None:
        items = await c.spatial_repo.pois_in_bbox(
            min_lon=min_lon,
            min_lat=min_lat,
            max_lon=max_lon,
            max_lat=max_lat,
            category=category,
            limit=limit,
        )
        source = "postgis"

    elapsed_ms = round((time.perf_counter() - t0) * 1000.0, 2)
    return PoiBBoxResponse(
        source=source,
        query_ms=elapsed_ms,
        count=len(items),
        items=items,
    )


@router.get("/search", response_model=PoiBBoxResponse)
async def search_pois(
    response: Response,
    q: str = Query(..., min_length=2, max_length=120),
    lat: float | None = Query(None, ge=-90.0, le=90.0),
    lon: float | None = Query(None, ge=-180.0, le=180.0),
    category: str | None = Query(None),
    country_code: str | None = Query(None, pattern="^(MY|SG|BN)$"),
    limit: int = Query(25, ge=1, le=100),
    c: AppContainer = Depends(get_container),
) -> PoiBBoxResponse:
    t0 = time.perf_counter()
    response.headers["Cache-Control"] = "public, max-age=120"
    ckey = _search_cache_key(q, lat, lon, category, country_code, limit)
    cached = await c.redis_cache.get_cached_json(ckey)
    if cached is not None:
        cached["source"] = "redis_cache"
        cached["query_ms"] = round((time.perf_counter() - t0) * 1000.0, 2)
        return PoiBBoxResponse.model_validate(cached)

    items = await c.spatial_repo.search_pois(
        query=q,
        lat=lat,
        lon=lon,
        category=category,
        country_code=country_code,
        limit=limit,
    )
    elapsed_ms = round((time.perf_counter() - t0) * 1000.0, 2)
    payload = PoiBBoxResponse(
        source="postgis",
        query_ms=elapsed_ms,
        count=len(items),
        items=items,
    )
    await c.redis_cache.set_cached_json(ckey, payload.model_dump(mode="json"), ttl_seconds=120)
    return payload


@router.get("/offline-index", response_model=PoiBBoxResponse)
async def get_offline_poi_index(
    response: Response,
    country_code: str | None = Query(None, pattern="^(MY|SG|BN)$"),
    min_lon: float | None = Query(None, ge=-180.0, le=180.0),
    min_lat: float | None = Query(None, ge=-90.0, le=90.0),
    max_lon: float | None = Query(None, ge=-180.0, le=180.0),
    max_lat: float | None = Query(None, ge=-90.0, le=90.0),
    limit: int = Query(2500, ge=50, le=6000),
    c: AppContainer = Depends(get_container),
) -> PoiBBoxResponse:
    """
    Exports a compact PostGIS POI bundle for client-side offline fuzzy search
    hydration (<50ms keystroke latency across Malaysia, Singapore, and Brunei).
    """
    t0 = time.perf_counter()
    response.headers["Cache-Control"] = "public, max-age=3600, stale-while-revalidate=86400"
    ckey_raw = json.dumps(
        {
            "cc": country_code,
            "bbox": [min_lon, min_lat, max_lon, max_lat],
            "lim": limit,
        },
        sort_keys=True,
    )
    ckey = f"karta:cache:poi_pack:{hashlib.sha256(ckey_raw.encode('utf-8')).hexdigest()[:16]}"
    cached = await c.redis_cache.get_cached_json(ckey)
    if cached is not None:
        cached["source"] = "redis_cache"
        cached["query_ms"] = round((time.perf_counter() - t0) * 1000.0, 2)
        return PoiBBoxResponse.model_validate(cached)

    items = await c.spatial_repo.export_offline_poi_index(
        country_code=country_code,
        min_lon=min_lon,
        min_lat=min_lat,
        max_lon=max_lon,
        max_lat=max_lat,
        limit=limit,
    )
    elapsed_ms = round((time.perf_counter() - t0) * 1000.0, 2)
    payload = PoiBBoxResponse(
        source="postgis_offline_pack",
        query_ms=elapsed_ms,
        count=len(items),
        items=items,
    )
    await c.redis_cache.set_cached_json(ckey, payload.model_dump(mode="json"), ttl_seconds=600)
    return payload
