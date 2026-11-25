from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from karta_api.api.v1.router import v1_router
from karta_api.cache.redis_geo import RedisGeoCache
from karta_api.commuter.calendar_service import SmartCalendarService
from karta_api.commuter.carpool_service import PrivacyCarpoolService
from karta_api.config import get_settings
from karta_api.db.community_repo import CommunityRepository
from karta_api.db.pool import DatabasePool
from karta_api.db.region_repo import RegionRepository
from karta_api.db.spatial_repo import SpatialRepository
from karta_api.db.toll_repo import TollRepository
from karta_api.db.user_repo import UserRepository
from karta_api.deps import AppContainer
from karta_api.realtime.grpc_server import KartaRealtimeGrpcServer
from karta_api.realtime.hub import RealtimeHazardHub
from karta_api.realtime.reroute_engine import LiveRerouteEngine
from karta_api.routing.profiles import CostingProfileRegistry
from karta_api.routing.traffic import TrafficWeightManager
from karta_api.routing.valhalla_client import ValhallaClient
from karta_api.tolls.engine import RegionalTollEngine


def create_app() -> FastAPI:
    settings = get_settings()
    logging.basicConfig(
        level=getattr(logging, settings.karta_log_level.upper(), logging.INFO),
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    )

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        db_pool = DatabasePool(
            dsn=settings.database_url,
            min_size=settings.db_pool_min_size,
            max_size=settings.db_pool_max_size,
        )
        redis_cache = RedisGeoCache(settings.redis_url)
        valhalla = ValhallaClient(
            base_url=settings.valhalla_url,
            timeout_seconds=settings.valhalla_timeout_seconds,
        )
        profiles = CostingProfileRegistry(settings.costing_profiles_path)

        await db_pool.connect()
        await db_pool.ensure_phase3_schema(settings.phase3_schema_sql_path)
        await redis_cache.connect()
        await valhalla.connect()

        spatial_repo = SpatialRepository(db_pool.pool)
        toll_repo = TollRepository(db_pool.pool)
        region_repo = RegionRepository(db_pool.pool)
        community_repo = CommunityRepository(db_pool.pool)
        user_repo = UserRepository(db_pool.pool)
        toll_engine = RegionalTollEngine(toll_repo)
        traffic_manager = TrafficWeightManager(
            redis_cache,
            traffic_tar_path=settings.valhalla_traffic_tar_path,
        )

        realtime_hub = RealtimeHazardHub(
            redis_cache=redis_cache,
            community_repo=community_repo,
            spatial_repo=spatial_repo,
            valhalla=valhalla,
            traffic_manager=traffic_manager,
            expiry_sweep_seconds=settings.hazard_expiry_sweep_seconds,
        )
        reroute_engine = LiveRerouteEngine(
            hub=realtime_hub,
            valhalla=valhalla,
            profiles=profiles,
            traffic_manager=traffic_manager,
            community_repo=community_repo,
            toll_repo=toll_repo,
            toll_engine=toll_engine,
            min_savings_seconds=settings.reroute_min_savings_seconds,
        )
        realtime_hub.set_reroute_hook(reroute_engine.evaluate_session_for_hazard)
        await realtime_hub.start()

        grpc_server = KartaRealtimeGrpcServer(
            hub=realtime_hub,
            listen_addr=settings.grpc_listen_addr,
        )
        if settings.grpc_enabled:
            try:
                await grpc_server.start()
            except Exception as exc:
                logging.getLogger(__name__).warning("gRPC server start warning: %s", exc)

        calendar_service = SmartCalendarService(
            community_repo=community_repo,
            spatial_repo=spatial_repo,
            valhalla=valhalla,
            profiles=profiles,
            traffic_manager=traffic_manager,
            toll_engine=toll_engine,
        )
        carpool_service = PrivacyCarpoolService(
            community_repo=community_repo,
            spatial_repo=spatial_repo,
            valhalla=valhalla,
            profiles=profiles,
            toll_engine=toll_engine,
        )

        app.state.container = AppContainer(
            settings=settings,
            db_pool=db_pool,
            redis_cache=redis_cache,
            valhalla=valhalla,
            profiles=profiles,
            spatial_repo=spatial_repo,
            toll_repo=toll_repo,
            region_repo=region_repo,
            community_repo=community_repo,
            user_repo=user_repo,
            toll_engine=toll_engine,
            traffic_manager=traffic_manager,
            realtime_hub=realtime_hub,
            reroute_engine=reroute_engine,
            grpc_server=grpc_server,
            calendar_service=calendar_service,
            carpool_service=carpool_service,
        )
        try:
            yield
        finally:
            await grpc_server.stop()
            await realtime_hub.stop()
            await valhalla.close()
            await redis_cache.close()
            await db_pool.close()

    app = FastAPI(
        title="Karta Core Spatial, Routing, Real-Time Crowdsourcing & Commuter API",
        version="0.3.0",
        description=(
            "Phase 1-3 backend for Karta Navigation Platform (Malaysia, Singapore, Brunei): "
            "Valhalla multi-modal & dynamic-costing routing, PostGIS spatial search, Redis Geo + "
            "Pub/Sub real-time hazard broadcasting (WebSocket + gRPC), MY/SG/BN toll engine, "
            "hands-free EN/BM/Manglish/Singlish voice intent, community fuel prices, smart "
            "calendar Time-to-Leave, privacy-first carpool matching, and custom voice packs."
        ),
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(v1_router)
    return app


app = create_app()
