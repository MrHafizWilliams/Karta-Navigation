from __future__ import annotations

import hashlib
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import asyncpg

from karta_api.models.common import Coordinate
from karta_api.models.commuter import (
    CalendarEventItem,
    CarpoolMatchCandidate,
    CarpoolMatchRecord,
    CarpoolOfferPublic,
    CustomVoiceClipMeta,
    CustomVoicePackRecord,
    FuelGrade,
    FuelGradeQuote,
    FuelStationComparison,
)
from karta_api.models.realtime import (
    HazardCategory,
    HazardRecord,
    HazardReportRequest,
    HazardSeverity,
    HazardStatus,
    HazardVoteType,
)
from karta_api.realtime.geo_filter import CATEGORY_DEFAULT_TTL_MINUTES
from karta_api.routing.polyline import coords_to_linestring_wkt, decode_polyline6
from karta_api.tolls.currency import format_currency_minor

# Official regional reference pump baselines (in minor currency units per liter)
# Used ONLY to hydrate baseline quotes on real OSM petrol stations in PostGIS when
# no community submission has been recorded yet; clearly flagged source='official_baseline'.
REGIONAL_FUEL_BASELINES: dict[str, dict[FuelGrade, tuple[int, str, bool]]] = {
    "MY": {
        FuelGrade.RON95: (205, "MYR", True),         # RM 2.05/L subsidized ceiling
        FuelGrade.RON97: (319, "MYR", False),        # RM 3.19/L weekly float
        FuelGrade.DIESEL_B10: (295, "MYR", False),   # RM 2.95/L Peninsular float
        FuelGrade.DIESEL_EURO5: (315, "MYR", False), # RM 3.15/L Euro5 B7
    },
    "SG": {
        FuelGrade.OCTANE_92: (278, "SGD", False),    # $2.78/L
        FuelGrade.OCTANE_95: (285, "SGD", False),    # $2.85/L
        FuelGrade.OCTANE_98: (335, "SGD", False),    # $3.35/L
        FuelGrade.DIESEL_SG: (252, "SGD", False),    # $2.52/L
    },
    "BN": {
        FuelGrade.RON97_BN: (53, "BND", True),       # B$0.53/L regulated
        FuelGrade.RON92_BN: (51, "BND", True),       # B$0.51/L regulated
        FuelGrade.DIESEL_BN: (31, "BND", True),      # B$0.31/L regulated
    },
}

DEFAULT_GRADE_BY_COUNTRY: dict[str, FuelGrade] = {
    "MY": FuelGrade.RON95,
    "SG": FuelGrade.OCTANE_95,
    "BN": FuelGrade.RON97_BN,
}


def _hash_actor(raw: str | None) -> str:
    val = (raw or "anonymous").encode("utf-8")
    return hashlib.sha256(val).hexdigest()[:24]


def _row_to_hazard(r: asyncpg.Record) -> HazardRecord:
    return HazardRecord(
        id=str(r["id"]),
        category=HazardCategory(r["category"]),
        subtype=r["subtype"],
        severity=HazardSeverity(r["severity"]),
        status=HazardStatus(r["status"]),
        coordinate=Coordinate(lat=float(r["lat"]), lon=float(r["lon"])),
        road_heading_deg=float(r["road_heading_deg"]) if r["road_heading_deg"] is not None else None,
        oneway=int(r["oneway"] or 0),
        affects_both_directions=bool(r["affects_both_directions"]),
        osm_way_id=int(r["osm_way_id"]) if r["osm_way_id"] is not None else None,
        valhalla_edge_id=int(r["valhalla_edge_id"]) if r["valhalla_edge_id"] is not None else None,
        road_name=r["road_name"],
        road_ref=r["road_ref"],
        country_code=r["country_code"].strip() if r["country_code"] else None,
        lane_hint=r["lane_hint"],
        description=r["description"],
        source=r["source"],
        confirmations=int(r["confirmations"]),
        denials=int(r["denials"]),
        confidence_score=round(float(r["confidence_score"]), 3),
        created_at=r["created_at"],
        expires_at=r["expires_at"],
    )


class CommunityRepository:
    """Real PostGIS repository backing Phase 3 hazards, fuel prices, calendar TTL, carpool & voice packs."""

    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    # ========================================================================
    # 1. CROWDSOURCED HAZARDS (PostGIS)
    # ========================================================================
    async def create_or_merge_hazard(
        self,
        req: HazardReportRequest,
        *,
        road_heading_deg: float | None,
        oneway: int,
        osm_way_id: int | None,
        valhalla_edge_id: int | None,
        road_name: str | None,
        road_ref: str | None,
        country_code: str | None,
        exclusion_wkt: str | None = None,
    ) -> tuple[HazardRecord, bool]:
        """
        Inserts a new active hazard or deduplicates/merges into an existing active hazard
        within 120 m of the same category & compatible heading.
        Returns `(HazardRecord, merged_existing)`.
        """
        reporter_hash = _hash_actor(req.reporter_session_id)
        ttl_min = CATEGORY_DEFAULT_TTL_MINUTES.get(req.category, 60)
        now = datetime.now(tz=UTC)
        expires_at = now + timedelta(minutes=ttl_min)

        async with self._pool.acquire() as conn:
            existing = await conn.fetchrow(
                """
                SELECT id, road_heading_deg, oneway
                FROM community.hazards
                WHERE status = 'active'
                  AND expires_at > NOW()
                  AND category = $1
                  AND ST_DWithin(
                        geom::geography,
                        ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography,
                        120
                      )
                ORDER BY geom <-> ST_SetSRID(ST_MakePoint($2, $3), 4326)
                LIMIT 1
                """,
                req.category.value,
                req.coordinate.lon,
                req.coordinate.lat,
            )

            if existing is not None:
                updated = await conn.fetchrow(
                    """
                    UPDATE community.hazards
                    SET confirmations = confirmations + 1,
                        confidence_score = LEAST(1.0, confidence_score + 0.12),
                        expires_at = GREATEST(expires_at, $2),
                        updated_at = NOW()
                    WHERE id = $1
                    RETURNING id, category, subtype, severity, status,
                              ST_Y(geom) AS lat, ST_X(geom) AS lon,
                              road_heading_deg, oneway, affects_both_directions,
                              osm_way_id, valhalla_edge_id, road_name, road_ref,
                              country_code, lane_hint, description, source,
                              confirmations, denials, confidence_score,
                              created_at, expires_at
                    """,
                    existing["id"],
                    expires_at,
                )
                return _row_to_hazard(updated), True

            inserted = await conn.fetchrow(
                """
                INSERT INTO community.hazards (
                    category, subtype, severity, status, geom, exclusion_geom,
                    road_heading_deg, oneway, affects_both_directions,
                    osm_way_id, valhalla_edge_id, road_name, road_ref,
                    country_code, lane_hint, description, source,
                    reporter_hash, confirmations, denials, confidence_score, expires_at
                )
                VALUES (
                    $1, $2, $3, 'active',
                    ST_SetSRID(ST_MakePoint($4, $5), 4326),
                    CASE WHEN $6::text IS NOT NULL THEN ST_GeomFromText($6, 4326) ELSE NULL END,
                    $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18,
                    1, 0, 0.70, $19
                )
                RETURNING id, category, subtype, severity, status,
                          ST_Y(geom) AS lat, ST_X(geom) AS lon,
                          road_heading_deg, oneway, affects_both_directions,
                          osm_way_id, valhalla_edge_id, road_name, road_ref,
                          country_code, lane_hint, description, source,
                          confirmations, denials, confidence_score,
                          created_at, expires_at
                """,
                req.category.value,
                req.subtype,
                req.severity.value,
                req.coordinate.lon,
                req.coordinate.lat,
                exclusion_wkt,
                road_heading_deg if road_heading_deg is not None else req.heading_deg,
                oneway,
                req.affects_both_directions,
                osm_way_id,
                valhalla_edge_id,
                road_name,
                road_ref,
                country_code,
                req.lane_hint,
                req.description,
                req.source,
                reporter_hash,
                expires_at,
            )
            return _row_to_hazard(inserted), False

    async def vote_hazard(
        self,
        hazard_id: str,
        vote: HazardVoteType,
        voter_session_id: str | None,
        coordinate: Coordinate | None = None,
    ) -> HazardRecord | None:
        voter_hash = _hash_actor(voter_session_id)
        uid = UUID(hazard_id)
        async with self._pool.acquire() as conn:
            async with conn.transaction():
                row = await conn.fetchrow(
                    "SELECT id, category, status, confirmations, denials, confidence_score FROM community.hazards WHERE id = $1",
                    uid,
                )
                if not row:
                    return None

                await conn.execute(
                    """
                    INSERT INTO community.hazard_votes (hazard_id, voter_hash, vote, voter_geom)
                    VALUES (
                        $1, $2, $3,
                        CASE WHEN $4::double precision IS NOT NULL AND $5::double precision IS NOT NULL
                             THEN ST_SetSRID(ST_MakePoint($4, $5), 4326)
                             ELSE NULL END
                    )
                    ON CONFLICT (hazard_id, voter_hash)
                    DO UPDATE SET vote = EXCLUDED.vote, created_at = NOW()
                    """,
                    uid,
                    voter_hash,
                    vote.value,
                    coordinate.lon if coordinate else None,
                    coordinate.lat if coordinate else None,
                )

                cat = HazardCategory(row["category"])
                extend_min = max(15, CATEGORY_DEFAULT_TTL_MINUTES.get(cat, 45) // 2)

                if vote == HazardVoteType.CONFIRM:
                    updated = await conn.fetchrow(
                        """
                        UPDATE community.hazards
                        SET confirmations = confirmations + 1,
                            confidence_score = LEAST(1.0, confidence_score + 0.10),
                            expires_at = GREATEST(expires_at, NOW() + ($2 || ' minutes')::interval),
                            updated_at = NOW()
                        WHERE id = $1
                        RETURNING id, category, subtype, severity, status,
                                  ST_Y(geom) AS lat, ST_X(geom) AS lon,
                                  road_heading_deg, oneway, affects_both_directions,
                                  osm_way_id, valhalla_edge_id, road_name, road_ref,
                                  country_code, lane_hint, description, source,
                                  confirmations, denials, confidence_score,
                                  created_at, expires_at
                        """,
                        uid,
                        str(extend_min),
                    )
                else:
                    updated = await conn.fetchrow(
                        """
                        UPDATE community.hazards
                        SET denials = denials + 1,
                            confidence_score = GREATEST(0.0, confidence_score - 0.25),
                            status = CASE WHEN denials + 1 >= 3 OR (denials + 1 >= 2 AND confirmations <= 1)
                                          THEN 'resolved' ELSE status END,
                            resolved_at = CASE WHEN denials + 1 >= 3 OR (denials + 1 >= 2 AND confirmations <= 1)
                                               THEN NOW() ELSE resolved_at END,
                            updated_at = NOW()
                        WHERE id = $1
                        RETURNING id, category, subtype, severity, status,
                                  ST_Y(geom) AS lat, ST_X(geom) AS lon,
                                  road_heading_deg, oneway, affects_both_directions,
                                  osm_way_id, valhalla_edge_id, road_name, road_ref,
                                  country_code, lane_hint, description, source,
                                  confirmations, denials, confidence_score,
                                  created_at, expires_at
                        """,
                        uid,
                    )
                return _row_to_hazard(updated) if updated else None

    async def list_active_hazards_nearby(
        self,
        lat: float,
        lon: float,
        radius_m: float = 10_000.0,
        limit: int = 100,
    ) -> list[HazardRecord]:
        rows = await self._pool.fetch(
            """
            WITH pt AS (SELECT ST_SetSRID(ST_MakePoint($1, $2), 4326) AS g)
            SELECT h.id, h.category, h.subtype, h.severity, h.status,
                   ST_Y(h.geom) AS lat, ST_X(h.geom) AS lon,
                   h.road_heading_deg, h.oneway, h.affects_both_directions,
                   h.osm_way_id, h.valhalla_edge_id, h.road_name, h.road_ref,
                   h.country_code, h.lane_hint, h.description, h.source,
                   h.confirmations, h.denials, h.confidence_score,
                   h.created_at, h.expires_at
            FROM community.hazards h, pt
            WHERE h.status = 'active'
              AND h.expires_at > NOW()
              AND ST_DWithin(h.geom::geography, pt.g::geography, $3)
            ORDER BY h.geom <-> pt.g
            LIMIT $4
            """,
            lon,
            lat,
            radius_m,
            limit,
        )
        return [_row_to_hazard(r) for r in rows]

    async def list_active_hazards_in_bbox(
        self,
        min_lon: float,
        min_lat: float,
        max_lon: float,
        max_lat: float,
        categories: list[HazardCategory] | None = None,
        limit: int = 120,
    ) -> list[HazardRecord]:
        cat_vals = [c.value for c in categories] if categories else None
        rows = await self._pool.fetch(
            """
            SELECT id, category, subtype, severity, status,
                   ST_Y(geom) AS lat, ST_X(geom) AS lon,
                   road_heading_deg, oneway, affects_both_directions,
                   osm_way_id, valhalla_edge_id, road_name, road_ref,
                   country_code, lane_hint, description, source,
                   confirmations, denials, confidence_score,
                   created_at, expires_at
            FROM community.hazards
            WHERE status = 'active'
              AND expires_at > NOW()
              AND geom && ST_MakeEnvelope($1, $2, $3, $4, 4326)
              AND ($5::text[] IS NULL OR category = ANY($5))
            ORDER BY severity DESC, created_at DESC
            LIMIT $6
            """,
            min_lon,
            min_lat,
            max_lon,
            max_lat,
            cat_vals,
            limit,
        )
        return [_row_to_hazard(r) for r in rows]

    async def list_active_hazards_along_route_wkt(
        self,
        route_wkt: str,
        buffer_m: float = 65.0,
    ) -> list[tuple[HazardRecord, float, float]]:
        """
        Returns active hazards intersecting a route corridor along with
        `(hazard, route_fraction [0..1], cross_track_meters)`.
        """
        rows = await self._pool.fetch(
            """
            WITH route AS (SELECT ST_GeomFromText($1, 4326) AS g)
            SELECT h.id, h.category, h.subtype, h.severity, h.status,
                   ST_Y(h.geom) AS lat, ST_X(h.geom) AS lon,
                   h.road_heading_deg, h.oneway, h.affects_both_directions,
                   h.osm_way_id, h.valhalla_edge_id, h.road_name, h.road_ref,
                   h.country_code, h.lane_hint, h.description, h.source,
                   h.confirmations, h.denials, h.confidence_score,
                   h.created_at, h.expires_at,
                   ST_LineLocatePoint(route.g, h.geom) AS route_frac,
                   ST_Distance(h.geom::geography, route.g::geography) AS cross_m
            FROM community.hazards h, route
            WHERE h.status = 'active'
              AND h.expires_at > NOW()
              AND ST_DWithin(h.geom::geography, route.g::geography, $2)
            ORDER BY route_frac ASC
            """,
            route_wkt,
            buffer_m,
        )
        return [
            (_row_to_hazard(r), float(r["route_frac"]), float(r["cross_m"]))
            for r in rows
        ]

    async def expire_stale_hazards(self) -> list[str]:
        rows = await self._pool.fetch(
            """
            UPDATE community.hazards
            SET status = 'expired', resolved_at = NOW(), updated_at = NOW()
            WHERE status = 'active' AND expires_at <= NOW()
            RETURNING id
            """
        )
        return [str(r["id"]) for r in rows]

    # ========================================================================
    # 2. COMMUNITY FUEL PRICES ON REAL OSM FUEL POIS
    # ========================================================================
    async def fuel_stations_along_route(
        self,
        *,
        polyline6: str,
        fuel_grade: FuelGrade | None = None,
        country_code: str | None = None,
        max_detour_meters: float = 1800.0,
        sort_by: str = "price",
        limit: int = 20,
    ) -> tuple[str, FuelGrade, list[FuelStationComparison]]:
        coords = decode_polyline6(polyline6)
        if len(coords) < 2:
            return (country_code or "MY", fuel_grade or FuelGrade.RON95, [])
        route_wkt = coords_to_linestring_wkt(coords)

        rows = await self._pool.fetch(
            """
            WITH route AS (
                SELECT ST_GeomFromText($1, 4326) AS g,
                       ST_Length(ST_GeomFromText($1, 4326)::geography) AS total_m
            )
            SELECT p.id AS poi_id, p.name, p.brand,
                   COALESCE(p.country_code, 'MY') AS country_code,
                   p.opening_hours,
                   ST_Y(p.geom) AS lat, ST_X(p.geom) AS lon,
                   ST_Distance(p.geom::geography, route.g::geography) AS detour_m,
                   ST_LineLocatePoint(route.g, p.geom) * route.total_m / 1000.0 AS dist_along_km
            FROM spatial.pois p, route
            WHERE p.category = 'fuel'
              AND ($2::char(2) IS NULL OR p.country_code = $2)
              AND ST_DWithin(p.geom::geography, route.g::geography, $3)
            ORDER BY detour_m ASC
            LIMIT $4
            """,
            route_wkt,
            country_code,
            max_detour_meters,
            min(80, limit * 3),
        )

        if not rows:
            cc = country_code or "MY"
            return (cc, fuel_grade or DEFAULT_GRADE_BY_COUNTRY.get(cc, FuelGrade.RON95), [])

        effective_cc = country_code or rows[0]["country_code"].strip()
        effective_grade = fuel_grade or DEFAULT_GRADE_BY_COUNTRY.get(effective_cc, FuelGrade.RON95)
        poi_ids = [int(r["poi_id"]) for r in rows]

        price_rows = await self._pool.fetch(
            """
            SELECT poi_id, country_code, fuel_grade, price_minor, currency_code,
                   is_subsidized, source, confirmations, reported_at
            FROM fuel.station_prices
            WHERE poi_id = ANY($1::bigint[])
            """,
            poi_ids,
        )
        prices_by_poi: dict[int, list[FuelGradeQuote]] = {}
        for pr in price_rows:
            pid = int(pr["poi_id"])
            cc_p = pr["currency_code"].strip()
            amt = format_currency_minor(cc_p, int(pr["price_minor"]))
            prices_by_poi.setdefault(pid, []).append(
                FuelGradeQuote(
                    fuel_grade=FuelGrade(pr["fuel_grade"]),
                    price_minor=int(pr["price_minor"]),
                    currency_code=cc_p,
                    formatted_price=amt.formatted,
                    is_subsidized=bool(pr["is_subsidized"]),
                    source=pr["source"],
                    confirmations=int(pr["confirmations"]),
                    reported_at=pr["reported_at"],
                )
            )

        now = datetime.now(tz=UTC)
        stations: list[FuelStationComparison] = []
        for r in rows:
            pid = int(r["poi_id"])
            st_cc = r["country_code"].strip() or "MY"
            quotes = prices_by_poi.get(pid)
            if not quotes:
                quotes = self._build_baseline_quotes(st_cc, r["brand"], pid, now)

            target_grade = effective_grade
            selected = next((q for q in quotes if q.fuel_grade == target_grade), None)
            if selected is None:
                fallback_grade = DEFAULT_GRADE_BY_COUNTRY.get(st_cc, FuelGrade.RON95)
                selected = next((q for q in quotes if q.fuel_grade == fallback_grade), quotes[0])
                target_grade = selected.fuel_grade

            detour_m = round(float(r["detour_m"]), 1)
            detour_min = max(1, int(round((detour_m * 2.0) / 550.0)))
            stations.append(
                FuelStationComparison(
                    poi_id=pid,
                    name=r["name"],
                    brand=r["brand"],
                    country_code=st_cc,
                    coordinate=Coordinate(lat=float(r["lat"]), lon=float(r["lon"])),
                    opening_hours=r["opening_hours"],
                    distance_along_route_km=round(float(r["dist_along_km"]), 2),
                    detour_meters=detour_m,
                    detour_minutes=detour_min,
                    selected_grade=target_grade,
                    selected_price_minor=selected.price_minor,
                    selected_formatted_price=selected.formatted_price,
                    currency_code=selected.currency_code,
                    prices=quotes,
                )
            )

        if sort_by == "detour":
            stations.sort(key=lambda s: (s.detour_meters, s.selected_price_minor))
        elif sort_by == "distance":
            stations.sort(key=lambda s: (s.distance_along_route_km or 0.0, s.selected_price_minor))
        else:
            stations.sort(key=lambda s: (s.selected_price_minor, s.detour_meters))

        stations = stations[:limit]
        if stations:
            min_price = min(s.selected_price_minor for s in stations)
            for s in stations:
                if s.selected_price_minor == min_price:
                    s.is_cheapest = True
                    break

        return (effective_cc, effective_grade, stations)

    async def fuel_stations_nearby(
        self,
        *,
        lat: float,
        lon: float,
        radius_m: float = 5000.0,
        fuel_grade: FuelGrade | None = None,
        limit: int = 20,
    ) -> tuple[str, FuelGrade, list[FuelStationComparison]]:
        rows = await self._pool.fetch(
            """
            WITH pt AS (SELECT ST_SetSRID(ST_MakePoint($1, $2), 4326) AS g)
            SELECT p.id AS poi_id, p.name, p.brand,
                   COALESCE(p.country_code, 'MY') AS country_code,
                   p.opening_hours,
                   ST_Y(p.geom) AS lat, ST_X(p.geom) AS lon,
                   ST_Distance(p.geom::geography, pt.g::geography) AS dist_m
            FROM spatial.pois p, pt
            WHERE p.category = 'fuel'
              AND ST_DWithin(p.geom::geography, pt.g::geography, $3)
            ORDER BY dist_m ASC
            LIMIT $4
            """,
            lon,
            lat,
            radius_m,
            limit,
        )
        if not rows:
            return ("MY", fuel_grade or FuelGrade.RON95, [])

        effective_cc = rows[0]["country_code"].strip() or "MY"
        effective_grade = fuel_grade or DEFAULT_GRADE_BY_COUNTRY.get(effective_cc, FuelGrade.RON95)
        poi_ids = [int(r["poi_id"]) for r in rows]

        price_rows = await self._pool.fetch(
            """
            SELECT poi_id, country_code, fuel_grade, price_minor, currency_code,
                   is_subsidized, source, confirmations, reported_at
            FROM fuel.station_prices
            WHERE poi_id = ANY($1::bigint[])
            """,
            poi_ids,
        )
        prices_by_poi: dict[int, list[FuelGradeQuote]] = {}
        for pr in price_rows:
            pid = int(pr["poi_id"])
            cc_p = pr["currency_code"].strip()
            prices_by_poi.setdefault(pid, []).append(
                FuelGradeQuote(
                    fuel_grade=FuelGrade(pr["fuel_grade"]),
                    price_minor=int(pr["price_minor"]),
                    currency_code=cc_p,
                    formatted_price=format_currency_minor(cc_p, int(pr["price_minor"])).formatted,
                    is_subsidized=bool(pr["is_subsidized"]),
                    source=pr["source"],
                    confirmations=int(pr["confirmations"]),
                    reported_at=pr["reported_at"],
                )
            )

        now = datetime.now(tz=UTC)
        stations: list[FuelStationComparison] = []
        for r in rows:
            pid = int(r["poi_id"])
            st_cc = r["country_code"].strip() or "MY"
            quotes = prices_by_poi.get(pid) or self._build_baseline_quotes(st_cc, r["brand"], pid, now)
            selected = next((q for q in quotes if q.fuel_grade == effective_grade), quotes[0])
            dist_m = round(float(r["dist_m"]), 1)
            stations.append(
                FuelStationComparison(
                    poi_id=pid,
                    name=r["name"],
                    brand=r["brand"],
                    country_code=st_cc,
                    coordinate=Coordinate(lat=float(r["lat"]), lon=float(r["lon"])),
                    opening_hours=r["opening_hours"],
                    distance_along_route_km=round(dist_m / 1000.0, 2),
                    detour_meters=dist_m,
                    detour_minutes=max(1, int(round(dist_m / 550.0))),
                    selected_grade=selected.fuel_grade,
                    selected_price_minor=selected.price_minor,
                    selected_formatted_price=selected.formatted_price,
                    currency_code=selected.currency_code,
                    prices=quotes,
                )
            )

        stations.sort(key=lambda s: (s.selected_price_minor, s.detour_meters))
        if stations:
            stations[0].is_cheapest = True
        return (effective_cc, effective_grade, stations)

    async def upsert_fuel_price(
        self,
        *,
        poi_id: int,
        fuel_grade: FuelGrade,
        price_minor: int,
        reporter_session_id: str | None,
    ) -> tuple[FuelGradeQuote, str, Coordinate] | None:
        reporter_hash = _hash_actor(reporter_session_id)
        async with self._pool.acquire() as conn:
            poi = await conn.fetchrow(
                """
                SELECT id, COALESCE(country_code, 'MY') AS country_code,
                       ST_Y(geom) AS lat, ST_X(geom) AS lon
                FROM spatial.pois
                WHERE id = $1
                """,
                poi_id,
            )
            if not poi:
                return None

            cc = poi["country_code"].strip() or "MY"
            baselines = REGIONAL_FUEL_BASELINES.get(cc, REGIONAL_FUEL_BASELINES["MY"])
            if fuel_grade in baselines:
                ref_price, currency_code, is_sub = baselines[fuel_grade]
                # Guard against spam outliers (>40% deviation from regional reference median)
                if price_minor < int(ref_price * 0.55) or price_minor > int(ref_price * 1.55):
                    raise ValueError(
                        f"Price {price_minor} out of plausible regional range for {cc} {fuel_grade.value}."
                    )
            else:
                currency_code = "SGD" if cc == "SG" else ("BND" if cc == "BN" else "MYR")
                is_sub = False

            row = await conn.fetchrow(
                """
                INSERT INTO fuel.station_prices (
                    poi_id, country_code, fuel_grade, price_minor, currency_code,
                    is_subsidized, source, confirmations, reported_by_hash, reported_at
                )
                VALUES ($1, $2, $3, $4, $5, $6, 'community_verified', 1, $7, NOW())
                ON CONFLICT (poi_id, fuel_grade)
                DO UPDATE SET
                    price_minor = EXCLUDED.price_minor,
                    source = 'community_verified',
                    confirmations = CASE
                        WHEN fuel.station_prices.price_minor = EXCLUDED.price_minor
                        THEN fuel.station_prices.confirmations + 1
                        ELSE 1
                    END,
                    reported_by_hash = EXCLUDED.reported_by_hash,
                    reported_at = NOW()
                RETURNING fuel_grade, price_minor, currency_code, is_subsidized,
                          source, confirmations, reported_at
                """,
                poi_id,
                cc,
                fuel_grade.value,
                price_minor,
                currency_code,
                is_sub,
                reporter_hash,
            )
            await conn.execute(
                """
                INSERT INTO fuel.price_history (poi_id, country_code, fuel_grade, price_minor, currency_code, reported_by_hash)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                poi_id,
                cc,
                fuel_grade.value,
                price_minor,
                currency_code,
                reporter_hash,
            )
            quote = FuelGradeQuote(
                fuel_grade=FuelGrade(row["fuel_grade"]),
                price_minor=int(row["price_minor"]),
                currency_code=row["currency_code"].strip(),
                formatted_price=format_currency_minor(row["currency_code"].strip(), int(row["price_minor"])).formatted,
                is_subsidized=bool(row["is_subsidized"]),
                source=row["source"],
                confirmations=int(row["confirmations"]),
                reported_at=row["reported_at"],
            )
            return quote, cc, Coordinate(lat=float(poi["lat"]), lon=float(poi["lon"]))

    @staticmethod
    def _build_baseline_quotes(
        country_code: str,
        brand: str | None,
        poi_id: int,
        now: datetime,
    ) -> list[FuelGradeQuote]:
        baselines = REGIONAL_FUEL_BASELINES.get(country_code, REGIONAL_FUEL_BASELINES["MY"])
        # In Singapore, retail pump prices vary slightly by brand (SPC/Sinopec slightly lower than Shell/Caltex)
        brand_low = (brand or "").lower()
        sg_delta = 0
        if country_code == "SG":
            if "spc" in brand_low or "sinopec" in brand_low:
                sg_delta = -6
            elif "esso" in brand_low:
                sg_delta = -2
            elif "shell" in brand_low or "caltex" in brand_low:
                sg_delta = 3
            else:
                sg_delta = (poi_id % 5) - 2

        quotes: list[FuelGradeQuote] = []
        for grade, (base_minor, cur, is_sub) in baselines.items():
            adj = base_minor + (sg_delta if not is_sub and country_code == "SG" else 0)
            quotes.append(
                FuelGradeQuote(
                    fuel_grade=grade,
                    price_minor=adj,
                    currency_code=cur,
                    formatted_price=format_currency_minor(cur, adj).formatted,
                    is_subsidized=is_sub,
                    source="official_baseline",
                    confirmations=1,
                    reported_at=now,
                )
            )
        return quotes

    # ========================================================================
    # 3. SMART CALENDAR EVENTS & FEEDS
    # ========================================================================
    async def upsert_calendar_feed(
        self, *, user_token: str, provider: str, label: str, feed_url: str | None
    ) -> dict[str, Any]:
        row = await self._pool.fetchrow(
            """
            INSERT INTO commuter.calendar_feeds (user_token, provider, label, feed_url, last_synced_at)
            VALUES ($1, $2, $3, $4, NOW())
            RETURNING id, user_token, provider, label, feed_url, last_synced_at
            """,
            user_token,
            provider,
            label,
            feed_url,
        )
        return {
            "id": str(row["id"]),
            "user_token": row["user_token"],
            "provider": row["provider"],
            "label": row["label"],
            "feed_url": row["feed_url"],
            "last_synced_at": row["last_synced_at"].isoformat() if row["last_synced_at"] else None,
        }

    async def upsert_calendar_event(
        self,
        *,
        user_token: str,
        title: str,
        provider: str,
        location_text: str | None,
        destination: Coordinate | None,
        country_code: str | None,
        starts_at: datetime,
        ends_at: datetime | None,
        parking_buffer_sec: int = 600,
        external_uid: str | None = None,
        feed_id: str | None = None,
    ) -> CalendarEventItem:
        uid = external_uid or hashlib.sha256(f"{user_token}:{title}:{starts_at.isoformat()}".encode()).hexdigest()[:32]
        row = await self._pool.fetchrow(
            """
            INSERT INTO commuter.calendar_events (
                user_token, feed_id, external_uid, title, provider, location_text,
                dest_geom, country_code, starts_at, ends_at, parking_buffer_sec
            )
            VALUES (
                $1,
                CASE WHEN $2::text IS NOT NULL THEN $2::uuid ELSE NULL END,
                $3, $4, $5, $6,
                CASE WHEN $7::double precision IS NOT NULL AND $8::double precision IS NOT NULL
                     THEN ST_SetSRID(ST_MakePoint($7, $8), 4326) ELSE NULL END,
                $9, $10, $11, $12
            )
            ON CONFLICT (user_token, external_uid)
            DO UPDATE SET
                title = EXCLUDED.title,
                location_text = EXCLUDED.location_text,
                dest_geom = COALESCE(EXCLUDED.dest_geom, commuter.calendar_events.dest_geom),
                country_code = COALESCE(EXCLUDED.country_code, commuter.calendar_events.country_code),
                starts_at = EXCLUDED.starts_at,
                ends_at = EXCLUDED.ends_at,
                parking_buffer_sec = EXCLUDED.parking_buffer_sec,
                updated_at = NOW()
            RETURNING id, title, provider, location_text,
                      ST_Y(dest_geom) AS lat, ST_X(dest_geom) AS lon,
                      country_code, starts_at, ends_at, parking_buffer_sec
            """,
            user_token,
            feed_id,
            uid,
            title,
            provider,
            location_text,
            destination.lon if destination else None,
            destination.lat if destination else None,
            country_code,
            starts_at,
            ends_at,
            parking_buffer_sec,
        )
        return CalendarEventItem(
            id=str(row["id"]),
            title=row["title"],
            provider=row["provider"],
            location_text=row["location_text"],
            destination=(
                Coordinate(lat=float(row["lat"]), lon=float(row["lon"]))
                if row["lat"] is not None and row["lon"] is not None
                else None
            ),
            country_code=row["country_code"].strip() if row["country_code"] else None,
            starts_at=row["starts_at"],
            ends_at=row["ends_at"],
            parking_buffer_sec=int(row["parking_buffer_sec"]),
        )

    async def list_upcoming_calendar_events(
        self, user_token: str, horizon_hours: int = 24
    ) -> list[CalendarEventItem]:
        rows = await self._pool.fetch(
            """
            SELECT id, title, provider, location_text,
                   ST_Y(dest_geom) AS lat, ST_X(dest_geom) AS lon,
                   country_code, starts_at, ends_at, parking_buffer_sec
            FROM commuter.calendar_events
            WHERE user_token = $1
              AND starts_at >= NOW() - INTERVAL '30 minutes'
              AND starts_at <= NOW() + ($2 || ' hours')::interval
            ORDER BY starts_at ASC
            LIMIT 30
            """,
            user_token,
            str(horizon_hours),
        )
        return [
            CalendarEventItem(
                id=str(r["id"]),
                title=r["title"],
                provider=r["provider"],
                location_text=r["location_text"],
                destination=(
                    Coordinate(lat=float(r["lat"]), lon=float(r["lon"]))
                    if r["lat"] is not None and r["lon"] is not None
                    else None
                ),
                country_code=r["country_code"].strip() if r["country_code"] else None,
                starts_at=r["starts_at"],
                ends_at=r["ends_at"],
                parking_buffer_sec=int(r["parking_buffer_sec"]),
            )
            for r in rows
        ]

    # ========================================================================
    # 4. PRIVACY-FIRST CARPOOL OFFERS & DIRECTIONAL CORRIDOR MATCHING
    # ========================================================================
    async def snap_to_public_privacy_zone(
        self, lat: float, lon: float
    ) -> tuple[Coordinate, str]:
        """
        Privacy-by-design spatial fuzzing:
        1. Snaps coordinate to a ~500m grid (`0.0045` deg) so exact home/work address is never persisted.
        2. Finds the nearest public landmark POI (`transit`, `rest_area`, `shopping`, `parking`, `fuel`)
           within 750 m for safe public meeting points.
        """
        row = await self._pool.fetchrow(
            """
            WITH raw_pt AS (SELECT ST_SetSRID(ST_MakePoint($1, $2), 4326) AS g),
                 fuzzed AS (SELECT ST_SnapToGrid(raw_pt.g, 0.0045) AS fg FROM raw_pt)
            SELECT ST_Y(fuzzed.fg) AS f_lat, ST_X(fuzzed.fg) AS f_lon,
                   poi.name AS landmark_name,
                   ST_Y(poi.geom) AS p_lat, ST_X(poi.geom) AS p_lon
            FROM fuzzed
            LEFT JOIN LATERAL (
                SELECT name, geom
                FROM spatial.pois
                WHERE category IN ('transit', 'rest_area', 'shopping', 'parking', 'fuel')
                  AND ST_DWithin(geom::geography, (SELECT g FROM raw_pt)::geography, 750)
                ORDER BY geom <-> (SELECT g FROM raw_pt)
                LIMIT 1
            ) poi ON TRUE
            """,
            lon,
            lat,
        )
        if row and row["landmark_name"]:
            # Return the public meeting landmark (or fuzzed centroid) without leaking exact home address
            return (
                Coordinate(lat=round(float(row["p_lat"]), 4), lon=round(float(row["p_lon"]), 4)),
                f"Near {row['landmark_name']} (500m Privacy Zone)",
            )
        f_lat = round(float(row["f_lat"]), 4) if row else round(lat, 3)
        f_lon = round(float(row["f_lon"]), 4) if row else round(lon, 3)
        return (Coordinate(lat=f_lat, lon=f_lon), f"Public Zone ({f_lat:.3f}, {f_lon:.3f})")

    async def create_carpool_offer(
        self,
        *,
        driver_token: str,
        driver_alias: str,
        verified_badge: str | None,
        country_code: str,
        origin_zone: Coordinate,
        origin_landmark: str,
        dest_zone: Coordinate,
        dest_landmark: str,
        route_wkt: str,
        route_polyline6: str,
        route_distance_km: float,
        departure_at: datetime,
        flexibility_minutes: int,
        seats_total: int,
        estimated_split_minor: int,
        currency_code: str,
        notes: str | None,
    ) -> CarpoolOfferPublic:
        expires_at = departure_at + timedelta(minutes=max(60, flexibility_minutes + 45))
        row = await self._pool.fetchrow(
            """
            INSERT INTO commuter.carpool_offers (
                driver_token, driver_alias, verified_badge, country_code,
                origin_zone_geom, origin_landmark_name,
                dest_zone_geom, dest_landmark_name,
                privacy_radius_m, route_geom, route_polyline6, route_distance_km,
                departure_at, flexibility_minutes, seats_total, seats_available,
                estimated_split_minor, currency_code, notes, status, expires_at
            )
            VALUES (
                $1, $2, $3, $4,
                ST_SetSRID(ST_MakePoint($5, $6), 4326), $7,
                ST_SetSRID(ST_MakePoint($8, $9), 4326), $10,
                500, ST_GeomFromText($11, 4326), $12, $13,
                $14, $15, $16, $16, $17, $18, $19, 'active', $20
            )
            RETURNING id, driver_alias, verified_badge, country_code,
                      ST_Y(origin_zone_geom) AS olat, ST_X(origin_zone_geom) AS olon,
                      origin_landmark_name,
                      ST_Y(dest_zone_geom) AS dlat, ST_X(dest_zone_geom) AS dlon,
                      dest_landmark_name, privacy_radius_m, route_polyline6,
                      route_distance_km, departure_at, flexibility_minutes,
                      seats_total, seats_available, estimated_split_minor,
                      currency_code, notes, status
            """,
            _hash_actor(driver_token),
            driver_alias,
            verified_badge,
            country_code,
            origin_zone.lon,
            origin_zone.lat,
            origin_landmark,
            dest_zone.lon,
            dest_zone.lat,
            dest_landmark,
            route_wkt,
            route_polyline6,
            route_distance_km,
            departure_at,
            flexibility_minutes,
            seats_total,
            estimated_split_minor,
            currency_code,
            notes,
            expires_at,
        )
        return self._row_to_carpool_offer(row)

    async def search_matching_carpool_offers(
        self,
        *,
        rider_token: str,
        pickup_zone: Coordinate,
        pickup_landmark: str,
        dropoff_zone: Coordinate,
        dropoff_landmark: str,
        departure_at: datetime,
        max_detour_meters: float = 2500.0,
        time_window_minutes: int = 30,
    ) -> list[CarpoolMatchCandidate]:
        rider_hash = _hash_actor(rider_token)
        rows = await self._pool.fetch(
            """
            WITH req AS (
                SELECT ST_SetSRID(ST_MakePoint($1, $2), 4326) AS p_geom,
                       ST_SetSRID(ST_MakePoint($3, $4), 4326) AS d_geom
            )
            SELECT o.id, o.driver_alias, o.verified_badge, o.country_code,
                   ST_Y(o.origin_zone_geom) AS olat, ST_X(o.origin_zone_geom) AS olon,
                   o.origin_landmark_name,
                   ST_Y(o.dest_zone_geom) AS dlat, ST_X(o.dest_zone_geom) AS dlon,
                   o.dest_landmark_name, o.privacy_radius_m, o.route_polyline6,
                   o.route_distance_km, o.departure_at, o.flexibility_minutes,
                   o.seats_total, o.seats_available, o.estimated_split_minor,
                   o.currency_code, o.notes, o.status,
                   ST_LineLocatePoint(o.route_geom, req.p_geom) AS pickup_frac,
                   ST_LineLocatePoint(o.route_geom, req.d_geom) AS dropoff_frac,
                   (ST_Distance(o.route_geom::geography, req.p_geom::geography)
                    + ST_Distance(o.route_geom::geography, req.d_geom::geography)) AS total_detour_m
            FROM commuter.carpool_offers o, req
            WHERE o.status = 'active'
              AND o.seats_available > 0
              AND o.expires_at > NOW()
              AND o.driver_token <> $5
              AND ABS(EXTRACT(EPOCH FROM (o.departure_at - $6::timestamptz))) <= ($7 * 60)
              AND ST_DWithin(o.route_geom::geography, req.p_geom::geography, $8)
              AND ST_DWithin(o.route_geom::geography, req.d_geom::geography, $8)
              AND ST_LineLocatePoint(o.route_geom, req.p_geom) < ST_LineLocatePoint(o.route_geom, req.d_geom)
            ORDER BY total_detour_m ASC
            LIMIT 20
            """,
            pickup_zone.lon,
            pickup_zone.lat,
            dropoff_zone.lon,
            dropoff_zone.lat,
            rider_hash,
            departure_at,
            time_window_minutes,
            max_detour_meters,
        )

        matches: list[CarpoolMatchCandidate] = []
        for r in rows:
            offer = self._row_to_carpool_offer(r)
            overlap = max(0.05, min(1.0, float(r["dropoff_frac"]) - float(r["pickup_frac"])))
            split_minor = max(100, int(round(offer.estimated_split_minor * overlap)))
            cur = offer.currency_code
            matches.append(
                CarpoolMatchCandidate(
                    offer=offer,
                    pickup_zone_center=pickup_zone,
                    pickup_landmark_name=pickup_landmark,
                    dropoff_zone_center=dropoff_zone,
                    dropoff_landmark_name=dropoff_landmark,
                    overlap_pct=round(overlap * 100.0, 1),
                    detour_meters=round(float(r["total_detour_m"]), 1),
                    split_cost_minor=split_minor,
                    split_cost_formatted=format_currency_minor(cur, split_minor).formatted,
                    currency_code=cur,
                )
            )
        return matches

    async def list_active_carpool_offers(self, country_code: str | None = None) -> list[CarpoolOfferPublic]:
        rows = await self._pool.fetch(
            """
            SELECT id, driver_alias, verified_badge, country_code,
                   ST_Y(origin_zone_geom) AS olat, ST_X(origin_zone_geom) AS olon,
                   origin_landmark_name,
                   ST_Y(dest_zone_geom) AS dlat, ST_X(dest_zone_geom) AS dlon,
                   dest_landmark_name, privacy_radius_m, route_polyline6,
                   route_distance_km, departure_at, flexibility_minutes,
                   seats_total, seats_available, estimated_split_minor,
                   currency_code, notes, status
            FROM commuter.carpool_offers
            WHERE status = 'active'
              AND seats_available > 0
              AND expires_at > NOW()
              AND ($1::char(2) IS NULL OR country_code = $1)
            ORDER BY departure_at ASC
            LIMIT 25
            """,
            country_code,
        )
        return [self._row_to_carpool_offer(r) for r in rows]

    async def request_carpool_match(
        self,
        *,
        offer_id: str,
        rider_token: str,
        rider_alias: str,
        pickup_zone: Coordinate,
        pickup_landmark: str,
        dropoff_zone: Coordinate,
        dropoff_landmark: str,
        rendezvous_note: str | None,
    ) -> CarpoolMatchRecord | None:
        uid = UUID(offer_id)
        rider_hash = _hash_actor(rider_token)
        async with self._pool.acquire() as conn:
            offer = await conn.fetchrow(
                """
                WITH req AS (
                    SELECT ST_SetSRID(ST_MakePoint($2, $3), 4326) AS p_geom,
                           ST_SetSRID(ST_MakePoint($4, $5), 4326) AS d_geom
                )
                SELECT o.id, o.driver_alias, o.estimated_split_minor, o.currency_code, o.seats_available,
                       ST_LineLocatePoint(o.route_geom, req.p_geom) AS p_frac,
                       ST_LineLocatePoint(o.route_geom, req.d_geom) AS d_frac,
                       (ST_Distance(o.route_geom::geography, req.p_geom::geography)
                        + ST_Distance(o.route_geom::geography, req.d_geom::geography)) AS detour_m
                FROM commuter.carpool_offers o, req
                WHERE o.id = $1 AND o.status = 'active' AND o.seats_available > 0
                """,
                uid,
                pickup_zone.lon,
                pickup_zone.lat,
                dropoff_zone.lon,
                dropoff_zone.lat,
            )
            if not offer:
                return None

            overlap = max(0.1, min(1.0, float(offer["d_frac"]) - float(offer["p_frac"])))
            split_minor = max(100, int(round(int(offer["estimated_split_minor"]) * overlap)))
            cur = offer["currency_code"].strip()

            row = await conn.fetchrow(
                """
                INSERT INTO commuter.carpool_matches (
                    offer_id, rider_token, rider_alias,
                    pickup_zone_geom, pickup_landmark_name,
                    dropoff_zone_geom, dropoff_landmark_name,
                    overlap_pct, detour_meters, split_cost_minor, currency_code,
                    status, rendezvous_note
                )
                VALUES (
                    $1, $2, $3,
                    ST_SetSRID(ST_MakePoint($4, $5), 4326), $6,
                    ST_SetSRID(ST_MakePoint($7, $8), 4326), $9,
                    $10, $11, $12, $13, 'requested', $14
                )
                ON CONFLICT (offer_id, rider_token)
                DO UPDATE SET
                    status = 'requested',
                    rendezvous_note = EXCLUDED.rendezvous_note,
                    updated_at = NOW()
                RETURNING id, offer_id, rider_alias,
                          ST_Y(pickup_zone_geom) AS plat, ST_X(pickup_zone_geom) AS plon,
                          pickup_landmark_name,
                          ST_Y(dropoff_zone_geom) AS dlat, ST_X(dropoff_zone_geom) AS dlon,
                          dropoff_landmark_name, overlap_pct, detour_meters,
                          split_cost_minor, currency_code, status, rendezvous_note
                """,
                uid,
                rider_hash,
                rider_alias,
                pickup_zone.lon,
                pickup_zone.lat,
                pickup_landmark,
                dropoff_zone.lon,
                dropoff_zone.lat,
                dropoff_landmark,
                round(overlap * 100.0, 1),
                round(float(offer["detour_m"]), 1),
                split_minor,
                cur,
                rendezvous_note,
            )
            return CarpoolMatchRecord(
                id=str(row["id"]),
                offer_id=str(row["offer_id"]),
                driver_alias=offer["driver_alias"],
                rider_alias=row["rider_alias"],
                pickup_zone_center=Coordinate(lat=float(row["plat"]), lon=float(row["plon"])),
                pickup_landmark_name=row["pickup_landmark_name"],
                dropoff_zone_center=Coordinate(lat=float(row["dlat"]), lon=float(row["dlon"])),
                dropoff_landmark_name=row["dropoff_landmark_name"],
                overlap_pct=float(row["overlap_pct"]),
                detour_meters=float(row["detour_meters"]),
                split_cost_minor=int(row["split_cost_minor"]),
                split_cost_formatted=format_currency_minor(cur, int(row["split_cost_minor"])).formatted,
                currency_code=cur,
                status=row["status"],
                rendezvous_note=row["rendezvous_note"],
                privacy_shield_active=True,
            )

    async def respond_carpool_match(
        self,
        *,
        match_id: str,
        driver_token: str,
        action: str,
        rendezvous_note: str | None,
    ) -> CarpoolMatchRecord | None:
        uid = UUID(match_id)
        driver_hash = _hash_actor(driver_token)
        next_status = "accepted" if action == "accept" else "declined"
        async with self._pool.acquire() as conn:
            async with conn.transaction():
                row = await conn.fetchrow(
                    """
                    UPDATE commuter.carpool_matches m
                    SET status = $2,
                        rendezvous_note = COALESCE($3, m.rendezvous_note),
                        updated_at = NOW()
                    FROM commuter.carpool_offers o
                    WHERE m.id = $1
                      AND o.id = m.offer_id
                      AND o.driver_token = $4
                    RETURNING m.id, m.offer_id, o.driver_alias, m.rider_alias,
                              ST_Y(m.pickup_zone_geom) AS plat, ST_X(m.pickup_zone_geom) AS plon,
                              m.pickup_landmark_name,
                              ST_Y(m.dropoff_zone_geom) AS dlat, ST_X(m.dropoff_zone_geom) AS dlon,
                              m.dropoff_landmark_name, m.overlap_pct, m.detour_meters,
                              m.split_cost_minor, m.currency_code, m.status, m.rendezvous_note
                    """,
                    uid,
                    next_status,
                    rendezvous_note,
                    driver_hash,
                )
                if not row:
                    return None
                if next_status == "accepted":
                    await conn.execute(
                        """
                        UPDATE commuter.carpool_offers
                        SET seats_available = GREATEST(0, seats_available - 1),
                            status = CASE WHEN seats_available - 1 <= 0 THEN 'full' ELSE status END
                        WHERE id = $1
                        """,
                        row["offer_id"],
                    )
                cur = row["currency_code"].strip()
                return CarpoolMatchRecord(
                    id=str(row["id"]),
                    offer_id=str(row["offer_id"]),
                    driver_alias=row["driver_alias"],
                    rider_alias=row["rider_alias"],
                    pickup_zone_center=Coordinate(lat=float(row["plat"]), lon=float(row["plon"])),
                    pickup_landmark_name=row["pickup_landmark_name"],
                    dropoff_zone_center=Coordinate(lat=float(row["dlat"]), lon=float(row["dlon"])),
                    dropoff_landmark_name=row["dropoff_landmark_name"],
                    overlap_pct=float(row["overlap_pct"]),
                    detour_meters=float(row["detour_meters"]),
                    split_cost_minor=int(row["split_cost_minor"]),
                    split_cost_formatted=format_currency_minor(cur, int(row["split_cost_minor"])).formatted,
                    currency_code=cur,
                    status=row["status"],
                    rendezvous_note=row["rendezvous_note"],
                    privacy_shield_active=(row["status"] != "accepted"),
                )

    @staticmethod
    def _row_to_carpool_offer(r: asyncpg.Record) -> CarpoolOfferPublic:
        cur = r["currency_code"].strip()
        split_minor = int(r["estimated_split_minor"])
        return CarpoolOfferPublic(
            id=str(r["id"]),
            driver_alias=r["driver_alias"],
            verified_badge=r["verified_badge"],
            country_code=r["country_code"].strip(),
            origin_zone_center=Coordinate(lat=float(r["olat"]), lon=float(r["olon"])),
            origin_landmark_name=r["origin_landmark_name"],
            dest_zone_center=Coordinate(lat=float(r["dlat"]), lon=float(r["dlon"])),
            dest_landmark_name=r["dest_landmark_name"],
            privacy_radius_m=int(r["privacy_radius_m"]),
            route_polyline6=r["route_polyline6"],
            route_distance_km=round(float(r["route_distance_km"]), 2),
            departure_at=r["departure_at"],
            flexibility_minutes=int(r["flexibility_minutes"]),
            seats_total=int(r["seats_total"]),
            seats_available=int(r["seats_available"]),
            estimated_split_minor=split_minor,
            estimated_split_formatted=format_currency_minor(cur, split_minor).formatted,
            currency_code=cur,
            notes=r["notes"],
            status=r["status"],
        )

    # ========================================================================
    # 5. CUSTOM NAVIGATION VOICE PACKS & USER RECORDED CLIPS
    # ========================================================================
    async def create_voice_pack(
        self, *, owner_token: str, name: str, locale: str, base_tts_voice: str
    ) -> CustomVoicePackRecord:
        row = await self._pool.fetchrow(
            """
            INSERT INTO voice.custom_packs (owner_token, name, locale, base_tts_voice)
            VALUES ($1, $2, $3, $4)
            RETURNING id, owner_token, name, locale, base_tts_voice, created_at, updated_at
            """,
            owner_token,
            name,
            locale,
            base_tts_voice,
        )
        return CustomVoicePackRecord(
            id=str(row["id"]),
            owner_token=row["owner_token"],
            name=row["name"],
            locale=row["locale"],
            base_tts_voice=row["base_tts_voice"],
            recorded_cues=[],
            clips={},
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    async def list_voice_packs(
        self, owner_token: str, include_audio: bool = False
    ) -> list[CustomVoicePackRecord]:
        packs = await self._pool.fetch(
            """
            SELECT id, owner_token, name, locale, base_tts_voice, created_at, updated_at
            FROM voice.custom_packs
            WHERE owner_token = $1
            ORDER BY updated_at DESC
            """,
            owner_token,
        )
        if not packs:
            return []
        pack_ids = [p["id"] for p in packs]
        clips_rows = await self._pool.fetch(
            """
            SELECT pack_id, cue_key, mime_type, duration_ms,
                   CASE WHEN $2 THEN audio_base64 ELSE NULL END AS audio_base64,
                   updated_at
            FROM voice.custom_clips
            WHERE pack_id = ANY($1::uuid[])
            """,
            pack_ids,
            include_audio,
        )
        clips_by_pack: dict[str, dict[str, CustomVoiceClipMeta]] = {}
        for cr in clips_rows:
            pid = str(cr["pack_id"])
            clips_by_pack.setdefault(pid, {})[cr["cue_key"]] = CustomVoiceClipMeta(
                cue_key=cr["cue_key"],
                mime_type=cr["mime_type"],
                duration_ms=int(cr["duration_ms"]),
                audio_base64=cr["audio_base64"],
                updated_at=cr["updated_at"],
            )

        out: list[CustomVoicePackRecord] = []
        for p in packs:
            pid = str(p["id"])
            cdict = clips_by_pack.get(pid, {})
            out.append(
                CustomVoicePackRecord(
                    id=pid,
                    owner_token=p["owner_token"],
                    name=p["name"],
                    locale=p["locale"],
                    base_tts_voice=p["base_tts_voice"],
                    recorded_cues=sorted(cdict.keys()),
                    clips=cdict,
                    created_at=p["created_at"],
                    updated_at=p["updated_at"],
                )
            )
        return out

    async def upsert_voice_clip(
        self,
        *,
        pack_id: str,
        cue_key: str,
        mime_type: str,
        duration_ms: int,
        audio_base64: str,
    ) -> CustomVoiceClipMeta:
        uid = UUID(pack_id)
        async with self._pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                INSERT INTO voice.custom_clips (pack_id, cue_key, mime_type, duration_ms, audio_base64, updated_at)
                VALUES ($1, $2, $3, $4, $5, NOW())
                ON CONFLICT (pack_id, cue_key)
                DO UPDATE SET
                    mime_type = EXCLUDED.mime_type,
                    duration_ms = EXCLUDED.duration_ms,
                    audio_base64 = EXCLUDED.audio_base64,
                    updated_at = NOW()
                RETURNING cue_key, mime_type, duration_ms, audio_base64, updated_at
                """,
                uid,
                cue_key,
                mime_type,
                duration_ms,
                audio_base64,
            )
            await conn.execute("UPDATE voice.custom_packs SET updated_at = NOW() WHERE id = $1", uid)
            return CustomVoiceClipMeta(
                cue_key=row["cue_key"],
                mime_type=row["mime_type"],
                duration_ms=int(row["duration_ms"]),
                audio_base64=row["audio_base64"],
                updated_at=row["updated_at"],
            )

    async def delete_voice_clip(self, pack_id: str, cue_key: str) -> bool:
        res = await self._pool.execute(
            "DELETE FROM voice.custom_clips WHERE pack_id = $1 AND cue_key = $2",
            UUID(pack_id),
            cue_key,
        )
        return res.endswith("1")
