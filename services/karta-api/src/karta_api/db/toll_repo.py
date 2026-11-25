from __future__ import annotations

from dataclasses import dataclass
from datetime import date, time
from typing import Any

import asyncpg

from karta_api.models.common import Coordinate
from karta_api.models.tolls import GantryInfo, PaymentMethod, TollLaneGuidance


@dataclass(frozen=True)
class MatchedGantryCrossing:
    gantry_id: str
    corridor_id: str
    corridor_name: str
    system_type: str
    country_code: str
    gantry_name: str
    role: str
    direction_bearing: int | None
    bearing_tolerance: int
    accepted_payments: list[str]
    lane_layout: list[dict[str, Any]]
    lat: float
    lon: float
    route_fraction: float
    route_heading_deg: float | None


class TollRepository:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    async def find_gantries_along_route_wkt(self, route_wkt: str) -> list[MatchedGantryCrossing]:
        """
        Real PostGIS spatial intersection against perpendicular carriageway virtual
        tripwires (`tolls.gantries.detection_line`), ordered strictly along the
        route progression (`ST_LineLocatePoint`) with local tangent route heading.
        """
        rows = await self._pool.fetch(
            """
            WITH route AS (
                SELECT ST_GeomFromText($1, 4326) AS geom
            ),
            hits AS (
                SELECT
                    g.gantry_id,
                    g.corridor_id,
                    c.name AS corridor_name,
                    c.system_type::text AS system_type,
                    c.country_code,
                    g.name AS gantry_name,
                    g.role::text AS role,
                    g.direction_bearing,
                    g.bearing_tolerance,
                    g.accepted_payments::text[] AS accepted_payments,
                    g.lane_layout,
                    ST_Y(g.geom) AS lat,
                    ST_X(g.geom) AS lon,
                    ST_LineLocatePoint(
                        route.geom,
                        ST_Centroid(ST_Intersection(route.geom, g.detection_line))
                    ) AS route_fraction,
                    route.geom AS route_geom
                FROM tolls.gantries g
                JOIN tolls.corridors c ON c.corridor_id = g.corridor_id
                CROSS JOIN route
                WHERE g.is_active = TRUE
                  AND ST_Intersects(route.geom, g.detection_line)
            )
            SELECT
                gantry_id, corridor_id, corridor_name, system_type, country_code,
                gantry_name, role, direction_bearing, bearing_tolerance,
                accepted_payments, lane_layout, lat, lon, route_fraction,
                degrees(ST_Azimuth(
                    ST_LineInterpolatePoint(route_geom, GREATEST(0.0, route_fraction - 0.002)),
                    ST_LineInterpolatePoint(route_geom, LEAST(1.0, route_fraction + 0.002))
                )) AS route_heading_deg
            FROM hits
            ORDER BY route_fraction ASC
            """,
            route_wkt,
        )
        return [
            MatchedGantryCrossing(
                gantry_id=r["gantry_id"],
                corridor_id=r["corridor_id"],
                corridor_name=r["corridor_name"],
                system_type=r["system_type"],
                country_code=r["country_code"].strip(),
                gantry_name=r["gantry_name"],
                role=r["role"],
                direction_bearing=r["direction_bearing"],
                bearing_tolerance=r["bearing_tolerance"],
                accepted_payments=list(r["accepted_payments"]),
                lane_layout=list(r["lane_layout"] or []),
                lat=float(r["lat"]),
                lon=float(r["lon"]),
                route_fraction=float(r["route_fraction"]),
                route_heading_deg=float(r["route_heading_deg"])
                if r["route_heading_deg"] is not None
                else None,
            )
            for r in rows
        ]

    async def countries_crossed_by_route_wkt(self, route_wkt: str) -> list[str]:
        rows = await self._pool.fetch(
            """
            WITH route AS (SELECT ST_GeomFromText($1, 4326) AS geom)
            SELECT c.iso_a2,
                   MIN(ST_LineLocatePoint(route.geom, ST_Centroid(ST_Intersection(route.geom, c.geom)))) AS first_frac
            FROM geo.countries c
            CROSS JOIN route
            WHERE ST_Intersects(route.geom, c.geom)
            GROUP BY c.iso_a2
            ORDER BY first_frac ASC
            """,
            route_wkt,
        )
        return [r["iso_a2"].strip() for r in rows]

    async def resolve_vehicle_class(self, country_code: str, canonical_profile: str) -> str | None:
        row = await self._pool.fetchrow(
            """
            SELECT class_code
            FROM tolls.vehicle_classes
            WHERE country_code = $1 AND canonical_profile = $2
            LIMIT 1
            """,
            country_code,
            canonical_profile,
        )
        return row["class_code"] if row else None

    async def get_open_rates(
        self,
        gantry_id: str,
        country_code: str,
        vehicle_class: str,
        as_of_date: date,
        include_foreign_only: bool,
    ) -> list[dict[str, Any]]:
        rows = await self._pool.fetch(
            """
            SELECT amount_minor, currency_code, foreign_vehicle_only, payment_method::text
            FROM tolls.open_rates
            WHERE gantry_id = $1
              AND country_code = $2
              AND vehicle_class = $3
              AND effective_from <= $4
              AND (effective_to IS NULL OR effective_to >= $4)
              AND (foreign_vehicle_only = FALSE OR $5 = TRUE)
            ORDER BY foreign_vehicle_only ASC, effective_from DESC
            """,
            gantry_id,
            country_code,
            vehicle_class,
            as_of_date,
            include_foreign_only,
        )
        return [dict(r) for r in rows]

    async def get_closed_matrix_rate(
        self,
        corridor_id: str,
        entry_gantry_id: str,
        exit_gantry_id: str,
        vehicle_class: str,
        as_of_date: date,
    ) -> dict[str, Any] | None:
        row = await self._pool.fetchrow(
            """
            SELECT amount_minor, currency_code, distance_km
            FROM tolls.closed_matrix_rates
            WHERE corridor_id = $1
              AND entry_gantry_id = $2
              AND exit_gantry_id = $3
              AND vehicle_class = $4
              AND effective_from <= $5
              AND (effective_to IS NULL OR effective_to >= $5)
            ORDER BY effective_from DESC
            LIMIT 1
            """,
            corridor_id,
            entry_gantry_id,
            exit_gantry_id,
            vehicle_class,
            as_of_date,
        )
        return dict(row) if row else None

    async def get_erp_rate(
        self,
        gantry_id: str,
        vehicle_class: str,
        day_type: str,
        local_time: time,
        as_of_date: date,
    ) -> dict[str, Any] | None:
        row = await self._pool.fetchrow(
            """
            SELECT amount_minor, currency_code
            FROM tolls.erp_schedules
            WHERE gantry_id = $1
              AND vehicle_class = $2
              AND day_type = $3
              AND start_time <= $4
              AND end_time > $4
              AND effective_from <= $5
              AND (effective_to IS NULL OR effective_to >= $5)
            ORDER BY effective_from DESC
            LIMIT 1
            """,
            gantry_id,
            vehicle_class,
            day_type,
            local_time,
            as_of_date,
        )
        return dict(row) if row else None

    async def get_public_holiday_override(
        self, country_code: str, target_date: date
    ) -> str | None:
        row = await self._pool.fetchrow(
            """
            SELECT toll_override_rule
            FROM tolls.public_holidays
            WHERE country_code = $1 AND holiday_date = $2
            LIMIT 1
            """,
            country_code,
            target_date,
        )
        return row["toll_override_rule"] if row else None

    async def list_gantries(
        self,
        country_code: str | None = None,
        corridor_id: str | None = None,
        min_lon: float | None = None,
        min_lat: float | None = None,
        max_lon: float | None = None,
        max_lat: float | None = None,
    ) -> list[GantryInfo]:
        has_bbox = None not in (min_lon, min_lat, max_lon, max_lat)
        rows = await self._pool.fetch(
            """
            SELECT g.gantry_id, g.corridor_id, c.name AS corridor_name,
                   o.name AS operator_name, c.system_type::text AS system_type,
                   c.country_code, g.external_code, g.name, g.role::text AS role,
                   g.direction_code, g.direction_bearing,
                   g.accepted_payments::text[] AS accepted_payments,
                   g.lane_layout,
                   ST_Y(g.geom) AS lat, ST_X(g.geom) AS lon
            FROM tolls.gantries g
            JOIN tolls.corridors c ON c.corridor_id = g.corridor_id
            JOIN tolls.operators o ON o.operator_code = c.operator_code
            WHERE g.is_active = TRUE
              AND ($1::char(2) IS NULL OR c.country_code = $1)
              AND ($2::text IS NULL OR g.corridor_id = $2)
              AND (
                  $3::boolean = FALSE
                  OR g.geom && ST_MakeEnvelope($4, $5, $6, $7, 4326)
              )
            ORDER BY c.country_code, g.corridor_id, g.gantry_id
            """,
            country_code,
            corridor_id,
            has_bbox,
            min_lon or 0.0,
            min_lat or 0.0,
            max_lon or 0.0,
            max_lat or 0.0,
        )
        return [
            GantryInfo(
                gantry_id=r["gantry_id"],
                corridor_id=r["corridor_id"],
                corridor_name=r["corridor_name"],
                operator_name=r["operator_name"],
                system_type=r["system_type"],
                country_code=r["country_code"].strip(),
                external_code=r["external_code"],
                name=r["name"],
                role=r["role"],
                direction_code=r["direction_code"],
                direction_bearing=r["direction_bearing"],
                accepted_payments=[PaymentMethod(p) for p in r["accepted_payments"]],
                lane_layout=[TollLaneGuidance(**lane) for lane in (r["lane_layout"] or [])],
                coordinate=Coordinate(lat=float(r["lat"]), lon=float(r["lon"])),
            )
            for r in rows
        ]
