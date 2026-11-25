from __future__ import annotations

import asyncpg

from karta_api.models.common import BoundingBox
from karta_api.models.regions import OfflineRegionPack


class RegionRepository:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    async def list_offline_regions(self) -> list[OfflineRegionPack]:
        rows = await self._pool.fetch(
            """
            SELECT region_id, display_name, country_codes,
                   ST_XMin(bbox_geom) AS min_lon, ST_YMin(bbox_geom) AS min_lat,
                   ST_XMax(bbox_geom) AS max_lon, ST_YMax(bbox_geom) AS max_lat,
                   data_version, pmtiles_url, pmtiles_sha256, pmtiles_bytes,
                   valhalla_tar_url, valhalla_tar_sha256, valhalla_tar_bytes,
                   tolls_sqlite_url, tolls_sqlite_sha256, tolls_sqlite_bytes,
                   updated_at
            FROM geo.offline_regions
            ORDER BY region_id ASC
            """
        )
        return [
            OfflineRegionPack(
                region_id=r["region_id"],
                display_name=r["display_name"],
                country_codes=[c.strip() for c in r["country_codes"]],
                bbox=BoundingBox(
                    min_lon=float(r["min_lon"]),
                    min_lat=float(r["min_lat"]),
                    max_lon=float(r["max_lon"]),
                    max_lat=float(r["max_lat"]),
                ),
                data_version=r["data_version"],
                pmtiles_url=r["pmtiles_url"],
                pmtiles_sha256=r["pmtiles_sha256"].strip(),
                pmtiles_bytes=int(r["pmtiles_bytes"]),
                valhalla_tar_url=r["valhalla_tar_url"],
                valhalla_tar_sha256=r["valhalla_tar_sha256"].strip(),
                valhalla_tar_bytes=int(r["valhalla_tar_bytes"]),
                tolls_sqlite_url=r["tolls_sqlite_url"],
                tolls_sqlite_sha256=r["tolls_sqlite_sha256"].strip()
                if r["tolls_sqlite_sha256"]
                else None,
                tolls_sqlite_bytes=int(r["tolls_sqlite_bytes"] or 0),
                updated_at=r["updated_at"],
            )
            for r in rows
        ]
