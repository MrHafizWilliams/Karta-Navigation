from fastapi import APIRouter

from karta_api.api.v1 import (
    auth,
    commuter,
    fuel,
    hazards,
    health,
    pois,
    realtime,
    regions,
    routes,
    spatial,
    tiles,
    tolls,
    voice,
)

v1_router = APIRouter(prefix="/v1")
v1_router.include_router(health.router)
v1_router.include_router(routes.router)
v1_router.include_router(pois.router)
v1_router.include_router(spatial.router)
v1_router.include_router(tiles.router)
v1_router.include_router(tolls.router)
v1_router.include_router(regions.router)
# Phase 3 Real-Time Crowdsourcing, Fuel, Smart Commuter & Hands-Free Voice
v1_router.include_router(realtime.router)
v1_router.include_router(hazards.router)
v1_router.include_router(fuel.router)
v1_router.include_router(commuter.router)
v1_router.include_router(voice.router)
v1_router.include_router(auth.router)
