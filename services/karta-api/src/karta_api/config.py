from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    karta_env: str = "development"
    karta_log_level: str = "INFO"

    database_url: str = "postgresql://karta:karta_dev_change_me@localhost:5432/karta"
    db_pool_min_size: int = 2
    db_pool_max_size: int = 20

    redis_url: str = "redis://localhost:6379/0"
    route_cache_ttl_seconds: int = 120

    valhalla_url: str = "http://localhost:8002"
    valhalla_timeout_seconds: float = 20.0
    valhalla_traffic_tar_path: Path = Path("/data/valhalla/traffic.tar")

    pmtiles_public_url: str = "http://localhost:8081"
    pmtiles_internal_url: str = "http://localhost:8081"

    costing_profiles_path: Path = Path("/config/valhalla/costing_profiles.json")
    phase3_schema_sql_path: Path = Path("/config/postgres/init/003_phase3_realtime_commuter.sql")
    offline_packs_dir: Path = Path("/data/offline_packs")
    offline_packs_base_url: str = "http://localhost:8000/v1/regions/downloads"

    # Phase 3 Real-Time gRPC, Voice & Smart Commuter Settings
    grpc_enabled: bool = True
    grpc_listen_addr: str = "0.0.0.0:50051"
    hazard_expiry_sweep_seconds: int = 30
    reroute_min_savings_seconds: int = 120
    whisper_transcribe_url: str = ""
    google_calendar_client_id: str = ""
    facebook_app_id: str = ""


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
