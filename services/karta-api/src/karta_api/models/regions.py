from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel

from karta_api.models.common import BoundingBox


class OfflineRegionPack(BaseModel):
    region_id: str
    display_name: str
    country_codes: list[str]
    bbox: BoundingBox
    data_version: str
    pmtiles_url: str
    pmtiles_sha256: str
    pmtiles_bytes: int
    valhalla_tar_url: str
    valhalla_tar_sha256: str
    valhalla_tar_bytes: int
    tolls_sqlite_url: str | None = None
    tolls_sqlite_sha256: str | None = None
    tolls_sqlite_bytes: int = 0
    updated_at: datetime


class OfflineRegionListResponse(BaseModel):
    count: int
    regions: list[OfflineRegionPack]
