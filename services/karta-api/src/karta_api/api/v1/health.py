from __future__ import annotations

import httpx
from fastapi import APIRouter, Depends

from karta_api.deps import AppContainer, get_container

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live")
async def liveness() -> dict[str, str]:
    return {"status": "alive", "service": "karta-api"}


@router.get("")
async def readiness(c: AppContainer = Depends(get_container)) -> dict[str, object]:
    pg_info = await c.db_pool.healthcheck()
    redis_info = await c.redis_cache.healthcheck()
    valhalla_info = await c.valhalla.status()

    pmtiles_ok = False
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(c.settings.pmtiles_internal_url)
            pmtiles_ok = resp.status_code < 500
    except Exception:
        pmtiles_ok = False

    valhalla_ok = "version" in valhalla_info
    overall = "ok" if (pg_info and redis_info.get("ping") and valhalla_ok) else "degraded"

    return {
        "status": overall,
        "service": "karta-api",
        "dependencies": {
            "postgis": pg_info,
            "redis_geo": redis_info,
            "valhalla": {
                "reachable": valhalla_ok,
                "version": valhalla_info.get("version"),
                "tileset_last_modified": valhalla_info.get("tileset_last_modified"),
            },
            "pmtiles": {
                "reachable": pmtiles_ok,
                "public_url": c.settings.pmtiles_public_url,
            },
            "realtime": {
                "ws_endpoint": "/v1/realtime/ws",
                "grpc_running": c.grpc_server.is_running,
                "grpc_addr": c.settings.grpc_listen_addr,
                "active_sessions": c.realtime_hub.active_session_count,
                "traffic_epoch": await c.traffic_manager.get_traffic_epoch(),
                "valhalla_traffic_tar_ready": c.traffic_manager.traffic_tar_available,
            },
        },
        "routing_profiles": c.profiles.list_profiles(),
    }
