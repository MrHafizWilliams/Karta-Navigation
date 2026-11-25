from __future__ import annotations

import asyncpg

from karta_api.models.common import Coordinate, CountryContext
from karta_api.models.spatial import ApproachingGantry, ApproachingSpeedZone, PoiItem
from karta_api.models.tolls import PaymentMethod, TollLaneGuidance
from karta_api.routing.polyline import angular_diff_deg


class SpatialRepository:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    async def resolve_country_at_point(self, lat: float, lon: float) -> CountryContext | None:
        row = await self._pool.fetchrow(
            """
            SELECT iso_a2, name, currency_code, currency_symbol,
                   driving_side, speed_unit, timezone_iana
            FROM geo.countries
            WHERE ST_Contains(geom, ST_SetSRID(ST_MakePoint($1, $2), 4326))
            LIMIT 1
            """,
            lon,
            lat,
        )
        if not row:
            return None
        return CountryContext(
            iso_a2=row["iso_a2"].strip(),
            name=row["name"],
            currency_code=row["currency_code"].strip(),
            currency_symbol=row["currency_symbol"],
            driving_side=row["driving_side"],
            speed_unit=row["speed_unit"],
            timezone_iana=row["timezone_iana"],
        )

    async def pois_in_bbox(
        self,
        min_lon: float,
        min_lat: float,
        max_lon: float,
        max_lat: float,
        category: str | None = None,
        limit: int = 200,
    ) -> list[PoiItem]:
        rows = await self._pool.fetch(
            """
            SELECT id, name, category, subcategory, brand, country_code,
                   ST_Y(geom) AS lat, ST_X(geom) AS lon,
                   ev_metadata, opening_hours
            FROM spatial.pois
            WHERE geom && ST_MakeEnvelope($1, $2, $3, $4, 4326)
              AND ($5::text IS NULL OR category = $5)
            ORDER BY id ASC
            LIMIT $6
            """,
            min_lon,
            min_lat,
            max_lon,
            max_lat,
            category,
            limit,
        )
        return [
            PoiItem(
                id=r["id"],
                name=r["name"],
                category=r["category"],
                subcategory=r["subcategory"],
                brand=r["brand"],
                country_code=r["country_code"].strip() if r["country_code"] else None,
                coordinate=Coordinate(lat=r["lat"], lon=r["lon"]),
                ev_metadata=r["ev_metadata"],
                opening_hours=r["opening_hours"],
            )
            for r in rows
        ]

    async def search_pois(
        self,
        query: str,
        lat: float | None = None,
        lon: float | None = None,
        category: str | None = None,
        country_code: str | None = None,
        limit: int = 25,
    ) -> list[PoiItem]:
        if lat is not None and lon is not None:
            rows = await self._pool.fetch(
                """
                WITH pt AS (SELECT ST_SetSRID(ST_MakePoint($2, $3), 4326) AS g)
                SELECT p.id, p.name, p.category, p.subcategory, p.brand, p.country_code,
                       ST_Y(p.geom) AS lat, ST_X(p.geom) AS lon,
                       ST_Distance(p.geom::geography, pt.g::geography) AS dist_m,
                       p.ev_metadata, p.opening_hours,
                       GREATEST(
                           ts_rank(p.search_tsv, plainto_tsquery('simple', $1)),
                           similarity(p.name, $1)
                       ) AS score
                FROM spatial.pois p, pt
                WHERE (p.search_tsv @@ plainto_tsquery('simple', $1) OR p.name % $1)
                  AND ($4::text IS NULL OR p.category = $4)
                  AND ($5::char(2) IS NULL OR p.country_code = $5)
                ORDER BY score DESC, dist_m ASC
                LIMIT $6
                """,
                query,
                lon,
                lat,
                category,
                country_code,
                limit,
            )
        else:
            rows = await self._pool.fetch(
                """
                SELECT p.id, p.name, p.category, p.subcategory, p.brand, p.country_code,
                       ST_Y(p.geom) AS lat, ST_X(p.geom) AS lon,
                       NULL::float AS dist_m,
                       p.ev_metadata, p.opening_hours,
                       GREATEST(
                           ts_rank(p.search_tsv, plainto_tsquery('simple', $1)),
                           similarity(p.name, $1)
                       ) AS score
                FROM spatial.pois p
                WHERE (p.search_tsv @@ plainto_tsquery('simple', $1) OR p.name % $1)
                  AND ($2::text IS NULL OR p.category = $2)
                  AND ($3::char(2) IS NULL OR p.country_code = $3)
                ORDER BY score DESC
                LIMIT $4
                """,
                query,
                category,
                country_code,
                limit,
            )
        return [
            PoiItem(
                id=r["id"],
                name=r["name"],
                category=r["category"],
                subcategory=r["subcategory"],
                brand=r["brand"],
                country_code=r["country_code"].strip() if r["country_code"] else None,
                coordinate=Coordinate(lat=r["lat"], lon=r["lon"]),
                distance_meters=round(float(r["dist_m"]), 1) if r["dist_m"] is not None else None,
                ev_metadata=r["ev_metadata"],
                opening_hours=r["opening_hours"],
            )
            for r in rows
        ]

    async def export_offline_poi_index(
        self,
        country_code: str | None = None,
        min_lon: float | None = None,
        min_lat: float | None = None,
        max_lon: float | None = None,
        max_lat: float | None = None,
        limit: int = 3500,
    ) -> list[PoiItem]:
        """
        Exports high-utility regional MY/SG/BN POIs directly from PostGIS for
        instant (<50ms) client-side offline fuzzy search hydration.
        """
        has_bbox = None not in (min_lon, min_lat, max_lon, max_lat)
        rows = await self._pool.fetch(
            """
            SELECT id, name, category, subcategory, brand, country_code,
                   ST_Y(geom) AS lat, ST_X(geom) AS lon,
                   ev_metadata, opening_hours
            FROM spatial.pois
            WHERE ($1::char(2) IS NULL OR country_code = $1)
              AND (
                  $2::boolean = FALSE
                  OR geom && ST_MakeEnvelope($3, $4, $5, $6, 4326)
              )
            ORDER BY
                CASE category
                    WHEN 'airport' THEN 0
                    WHEN 'transit' THEN 1
                    WHEN 'rest_area' THEN 2
                    WHEN 'ev_charging' THEN 3
                    WHEN 'fuel' THEN 4
                    WHEN 'shopping' THEN 5
                    WHEN 'healthcare' THEN 6
                    WHEN 'tourism' THEN 7
                    WHEN 'parking' THEN 8
                    ELSE 9
                END ASC,
                (brand IS NOT NULL) DESC,
                id ASC
            LIMIT $7
            """,
            country_code,
            has_bbox,
            min_lon or 0.0,
            min_lat or 0.0,
            max_lon or 0.0,
            max_lat or 0.0,
            limit,
        )
        return [
            PoiItem(
                id=r["id"],
                name=r["name"],
                category=r["category"],
                subcategory=r["subcategory"],
                brand=r["brand"],
                country_code=r["country_code"].strip() if r["country_code"] else None,
                coordinate=Coordinate(lat=r["lat"], lon=r["lon"]),
                ev_metadata=r["ev_metadata"],
                opening_hours=r["opening_hours"],
            )
            for r in rows
        ]

    async def nearest_road_segment(
        self, lat: float, lon: float, heading_deg: float | None = None
    ) -> dict[str, object] | None:
        row = await self._pool.fetchrow(
            """
            WITH pt AS (SELECT ST_SetSRID(ST_MakePoint($1, $2), 4326) AS g)
            SELECT r.way_id, r.name, r.ref, r.highway_class, r.oneway,
                   r.maxspeed_fwd_kmh, r.maxspeed_bwd_kmh, r.maxspeed_source,
                   r.lanes_total, r.turn_lanes_fwd, r.turn_lanes_bwd,
                   r.is_toll, r.is_bridge, r.is_tunnel,
                   degrees(ST_Azimuth(
                       ST_LineInterpolatePoint(r.geom, GREATEST(0.0, ST_LineLocatePoint(r.geom, pt.g) - 0.05)),
                       ST_LineInterpolatePoint(r.geom, LEAST(1.0, ST_LineLocatePoint(r.geom, pt.g) + 0.05))
                   )) AS seg_azimuth
            FROM spatial.road_segments r, pt
            WHERE ST_DWithin(r.geom::geography, pt.g::geography, 45)
            ORDER BY r.geom <-> pt.g
            LIMIT 1
            """,
            lon,
            lat,
        )
        if not row:
            return None

        travel_reverse = False
        if heading_deg is not None and row["seg_azimuth"] is not None and row["oneway"] == 0:
            diff = angular_diff_deg(heading_deg, float(row["seg_azimuth"]))
            travel_reverse = diff > 90.0

        speed_limit = row["maxspeed_bwd_kmh"] if travel_reverse else row["maxspeed_fwd_kmh"]
        turn_lanes = (row["turn_lanes_bwd"] if travel_reverse else row["turn_lanes_fwd"]) or []

        return {
            "way_id": row["way_id"],
            "road_name": row["name"],
            "road_ref": row["ref"],
            "highway_class": row["highway_class"],
            "speed_limit_kmh": speed_limit,
            "speed_limit_source": row["maxspeed_source"],
            "lanes_total": row["lanes_total"],
            "turn_lanes": list(turn_lanes),
            "is_toll": bool(row["is_toll"]),
            "is_bridge": bool(row["is_bridge"]),
            "is_tunnel": bool(row["is_tunnel"]),
        }

    async def nearby_speed_zones(
        self, lat: float, lon: float, radius_m: float = 1000.0
    ) -> list[ApproachingSpeedZone]:
        rows = await self._pool.fetch(
            """
            WITH pt AS (SELECT ST_SetSRID(ST_MakePoint($1, $2), 4326) AS g)
            SELECT sz.id, sz.zone_type, sz.road_name, sz.limit_kmh,
                   ST_Y(sz.geom) AS lat, ST_X(sz.geom) AS lon,
                   ST_Distance(sz.geom::geography, pt.g::geography) AS dist_m
            FROM spatial.speed_zones sz, pt
            WHERE ST_DWithin(sz.geom::geography, pt.g::geography, $3)
            ORDER BY dist_m ASC
            LIMIT 10
            """,
            lon,
            lat,
            radius_m,
        )
        return [
            ApproachingSpeedZone(
                id=r["id"],
                zone_type=r["zone_type"],
                road_name=r["road_name"],
                limit_kmh=r["limit_kmh"],
                distance_meters=round(float(r["dist_m"]), 1),
                coordinate=Coordinate(lat=r["lat"], lon=r["lon"]),
            )
            for r in rows
        ]

    async def nearby_gantries(
        self, lat: float, lon: float, radius_m: float = 2000.0
    ) -> list[ApproachingGantry]:
        rows = await self._pool.fetch(
            """
            WITH pt AS (SELECT ST_SetSRID(ST_MakePoint($1, $2), 4326) AS g)
            SELECT g.gantry_id, g.name, g.corridor_id, c.system_type::text AS system_type,
                   g.accepted_payments::text[] AS accepted_payments, g.lane_layout,
                   ST_Y(g.geom) AS lat, ST_X(g.geom) AS lon,
                   ST_Distance(g.geom::geography, pt.g::geography) AS dist_m
            FROM tolls.gantries g
            JOIN tolls.corridors c ON c.corridor_id = g.corridor_id
            CROSS JOIN pt
            WHERE g.is_active = TRUE
              AND ST_DWithin(g.geom::geography, pt.g::geography, $3)
            ORDER BY dist_m ASC
            LIMIT 5
            """,
            lon,
            lat,
            radius_m,
        )
        return [
            ApproachingGantry(
                gantry_id=r["gantry_id"],
                name=r["name"],
                corridor_id=r["corridor_id"],
                system_type=r["system_type"],
                distance_meters=round(float(r["dist_m"]), 1),
                accepted_payments=[PaymentMethod(p) for p in r["accepted_payments"]],
                lane_layout=[TollLaneGuidance(**lane) for lane in (r["lane_layout"] or [])],
                coordinate=Coordinate(lat=r["lat"], lon=r["lon"]),
            )
            for r in rows
        ]
