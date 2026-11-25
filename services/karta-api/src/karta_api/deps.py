from __future__ import annotations

from dataclasses import dataclass

from fastapi import Request

from karta_api.cache.redis_geo import RedisGeoCache
from karta_api.commuter.calendar_service import SmartCalendarService
from karta_api.commuter.carpool_service import PrivacyCarpoolService
from karta_api.config import Settings
from karta_api.db.community_repo import CommunityRepository
from karta_api.db.pool import DatabasePool
from karta_api.db.region_repo import RegionRepository
from karta_api.db.spatial_repo import SpatialRepository
from karta_api.db.toll_repo import TollRepository
from karta_api.db.user_repo import UserRepository
from karta_api.realtime.grpc_server import KartaRealtimeGrpcServer
from karta_api.realtime.hub import RealtimeHazardHub
from karta_api.realtime.reroute_engine import LiveRerouteEngine
from karta_api.routing.profiles import CostingProfileRegistry
from karta_api.routing.traffic import TrafficWeightManager
from karta_api.routing.valhalla_client import ValhallaClient
from karta_api.tolls.engine import RegionalTollEngine


@dataclass
class AppContainer:
    settings: Settings
    db_pool: DatabasePool
    redis_cache: RedisGeoCache
    valhalla: ValhallaClient
    profiles: CostingProfileRegistry
    spatial_repo: SpatialRepository
    toll_repo: TollRepository
    region_repo: RegionRepository
    community_repo: CommunityRepository
    user_repo: UserRepository
    toll_engine: RegionalTollEngine
    traffic_manager: TrafficWeightManager
    realtime_hub: RealtimeHazardHub
    reroute_engine: LiveRerouteEngine
    grpc_server: KartaRealtimeGrpcServer
    calendar_service: SmartCalendarService
    carpool_service: PrivacyCarpoolService


def get_container(request: Request) -> AppContainer:
    return request.app.state.container
