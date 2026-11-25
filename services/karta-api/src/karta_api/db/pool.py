from __future__ import annotations

import json
import logging
from pathlib import Path

import asyncpg

logger = logging.getLogger(__name__)


async def _init_connection(conn: asyncpg.Connection) -> None:
    await conn.set_type_codec(
        "jsonb",
        encoder=json.dumps,
        decoder=json.loads,
        schema="pg_catalog",
    )
    await conn.set_type_codec(
        "json",
        encoder=json.dumps,
        decoder=json.loads,
        schema="pg_catalog",
    )


class DatabasePool:
    def __init__(self, dsn: str, min_size: int = 2, max_size: int = 20) -> None:
        self._dsn = dsn
        self._min_size = min_size
        self._max_size = max_size
        self._pool: asyncpg.Pool | None = None

    async def connect(self) -> None:
        logger.info("Connecting to PostgreSQL/PostGIS pool...")
        self._pool = await asyncpg.create_pool(
            dsn=self._dsn,
            min_size=self._min_size,
            max_size=self._max_size,
            init=_init_connection,
        )

    async def ensure_phase3_schema(self, candidate_path: Path) -> bool:
        """Idempotently applies Phase 3 PostGIS DDL if upgrading an existing Phase 1 volume."""
        sql_path: Path | None = None
        if candidate_path.exists():
            sql_path = candidate_path
        else:
            for parent in Path(__file__).resolve().parents:
                fallback = parent / "infra" / "postgres" / "init" / "003_phase3_realtime_commuter.sql"
                if fallback.exists():
                    sql_path = fallback
                    break
        if sql_path is None:
            logger.warning("Phase 3 DDL SQL file not found at %s; skipping auto-migration.", candidate_path)
            return False

        ddl = sql_path.read_text(encoding="utf-8")
        async with self.pool.acquire() as conn:
            await conn.execute(ddl)
        logger.info("Verified Phase 3 PostGIS schemas (community, fuel, commuter, voice).")

        # Also idempotently apply 004_users_saved_places.sql (users.accounts, sessions, saved_places)
        users_sql = sql_path.parent / "004_users_saved_places.sql"
        if users_sql.exists():
            async with self.pool.acquire() as conn:
                await conn.execute(users_sql.read_text(encoding="utf-8"))
            logger.info("Verified Karta User Accounts & Saved Places PostGIS schema.")
        return True

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()
            self._pool = None

    @property
    def pool(self) -> asyncpg.Pool:
        if self._pool is None:
            raise RuntimeError("DatabasePool is not connected.")
        return self._pool

    async def healthcheck(self) -> dict[str, object]:
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT PostGIS_Version() AS postgis_version,
                       (SELECT COUNT(*) FROM spatial.pois) AS poi_count,
                       (SELECT COUNT(*) FROM spatial.road_segments) AS road_count,
                       (SELECT COUNT(*) FROM tolls.gantries WHERE is_active = TRUE) AS gantry_count,
                       (SELECT COUNT(*) FROM community.hazards WHERE status = 'active') AS active_hazards,
                       (SELECT COUNT(*) FROM fuel.station_prices) AS fuel_price_records
                """
            )
            return dict(row) if row else {}
