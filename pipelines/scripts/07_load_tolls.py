#!/usr/bin/env python3
"""
Stage 07: Load Regional MY/SG/BN Toll Operators, Corridors, Gantries, Tariff Matrices,
Singapore ERP Schedules, and Public Holidays into PostGIS, AND export regional
offline SQLite toll databases + register offline pack metadata in `geo.offline_regions`.

Key spatial engineering detail:
- Computes meter-accurate perpendicular virtual tripwires (`detection_line`) for
  every toll gantry using PostGIS `ST_Project` on geography so route matching checks
  `ST_Intersects(route_linestring, detection_line)` rather than noisy point buffers.
- For bidirectional plazas without a fixed heading, infers the carriageway bearing
  from the nearest intersecting motorway/trunk segment in `spatial.road_segments`
  if available, falling back to an explicit cross-carriageway bearing.
"""

from __future__ import annotations

import csv
import datetime as dt
import hashlib
import json
import os
import sqlite3
from pathlib import Path
from typing import Any

import psycopg
import yaml

SEED_DIR = Path("/pipelines/seed_data/tolls")
REGIONS_CATALOG = Path("/pipelines/regions/regions_catalog.yaml")
OFFLINE_PACKS_DIR = Path("/data/offline_packs")
PMTILES_DIR = Path("/data/pmtiles")

EFFECTIVE_FROM = dt.date(2026, 1, 1)

# Singapore LTA ERP class multipliers relative to Passenger Car (SG_PC)
SG_ERP_MULTIPLIERS: list[tuple[str, float]] = [
    ("SG_PC", 1.0),
    ("SG_TAXI", 1.0),
    ("SG_MC", 0.5),
    ("SG_HGV", 1.5),
    ("SG_VHGV", 2.0),
    ("SG_BUS", 2.0),
]


def get_dsn() -> str:
    return (
        f"host={os.environ.get('PGHOST', 'postgres')} "
        f"port={os.environ.get('PGPORT', '5432')} "
        f"dbname={os.environ.get('PGDATABASE', 'karta')} "
        f"user={os.environ.get('PGUSER', 'karta')} "
        f"password={os.environ.get('PGPASSWORD', 'karta_dev_change_me')}"
    )


def infer_road_bearing(cur: psycopg.Cursor, lon: float, lat: float) -> float:
    """
    Infers the azimuth (degrees 0..360) of the nearest major road within 60m
    so bidirectional Malaysian toll plazas get a tripwire strictly perpendicular
    to the actual highway geometry.
    """
    cur.execute(
        """
        WITH pt AS (SELECT ST_SetSRID(ST_MakePoint(%s, %s), 4326) AS g),
        nearest AS (
            SELECT geom
            FROM spatial.road_segments, pt
            WHERE highway_class IN ('motorway', 'motorway_link', 'trunk', 'trunk_link', 'primary')
              AND ST_DWithin(geom::geography, pt.g::geography, 80)
            ORDER BY geom <-> pt.g
            LIMIT 1
        )
        SELECT degrees(ST_Azimuth(
            ST_LineInterpolatePoint(geom, GREATEST(0.0, ST_LineLocatePoint(geom, (SELECT g FROM pt)) - 0.05)),
            ST_LineInterpolatePoint(geom, LEAST(1.0, ST_LineLocatePoint(geom, (SELECT g FROM pt)) + 0.05))
        ))
        FROM nearest
        """,
        (lon, lat),
    )
    row = cur.fetchone()
    if row and row[0] is not None:
        return float(row[0]) % 360.0
    return 0.0


def upsert_gantry(cur: psycopg.Cursor, g: dict[str, Any]) -> None:
    lat = float(g["lat"])
    lon = float(g["lon"])
    bearing = g.get("direction_bearing")
    half_width_m = float(g.get("tripwire_half_width_m", 45))
    bearing_tol = int(g.get("bearing_tolerance", 55))

    ref_bearing = float(bearing) if bearing is not None else infer_road_bearing(cur, lon, lat)
    perp_left = (ref_bearing + 270.0) % 360.0
    perp_right = (ref_bearing + 90.0) % 360.0

    # Snap optional osm_node_id if a matching barrier=toll_booth exists within 100m
    cur.execute(
        """
        SELECT osm_id
        FROM tolls.osm_toll_nodes
        WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, 100)
        ORDER BY geom <-> ST_SetSRID(ST_MakePoint(%s, %s), 4326)
        LIMIT 1
        """,
        (lon, lat, lon, lat),
    )
    snap = cur.fetchone()
    osm_node_id = snap[0] if snap else g.get("osm_node_id")

    cur.execute(
        """
        INSERT INTO tolls.gantries (
            gantry_id, corridor_id, external_code, osm_node_id, name, role,
            direction_code, direction_bearing, bearing_tolerance,
            accepted_payments, lane_layout, geom, detection_line, is_active, updated_at
        )
        VALUES (
            %s, %s, %s, %s, %s, %s::tolls.gantry_role,
            %s, %s, %s,
            %s::tolls.payment_method[], %s::jsonb,
            ST_SetSRID(ST_MakePoint(%s, %s), 4326),
            ST_MakeLine(
                ST_Project(ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, %s, radians(%s))::geometry,
                ST_Project(ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, %s, radians(%s))::geometry
            ),
            TRUE, NOW()
        )
        ON CONFLICT (gantry_id) DO UPDATE SET
            corridor_id = EXCLUDED.corridor_id,
            external_code = EXCLUDED.external_code,
            osm_node_id = EXCLUDED.osm_node_id,
            name = EXCLUDED.name,
            role = EXCLUDED.role,
            direction_code = EXCLUDED.direction_code,
            direction_bearing = EXCLUDED.direction_bearing,
            bearing_tolerance = EXCLUDED.bearing_tolerance,
            accepted_payments = EXCLUDED.accepted_payments,
            lane_layout = EXCLUDED.lane_layout,
            geom = EXCLUDED.geom,
            detection_line = EXCLUDED.detection_line,
            is_active = TRUE,
            updated_at = NOW()
        """,
        (
            g["gantry_id"],
            g["corridor_id"],
            g.get("external_code"),
            osm_node_id,
            g["name"],
            g["role"],
            g.get("direction_code"),
            bearing,
            bearing_tol,
            g["accepted_payments"],
            json.dumps(g.get("lane_layout", [])),
            lon,
            lat,
            lon,
            lat,
            half_width_m,
            perp_left,
            lon,
            lat,
            half_width_m,
            perp_right,
        ),
    )


def load_all_tolls(conn: psycopg.Connection) -> None:
    ops_data = yaml.safe_load((SEED_DIR / "operators_corridors.yaml").read_text(encoding="utf-8"))
    my_data = yaml.safe_load((SEED_DIR / "my_gantries_and_open_rates.yaml").read_text(encoding="utf-8"))
    sg_data = yaml.safe_load((SEED_DIR / "sg_erp_gantries_and_schedules.yaml").read_text(encoding="utf-8"))
    bn_data = yaml.safe_load((SEED_DIR / "bn_tolls_and_holidays.yaml").read_text(encoding="utf-8"))

    with conn.cursor() as cur:
        # 1. Operators
        for op in ops_data["operators"]:
            cur.execute(
                """
                INSERT INTO tolls.operators (operator_code, name, country_code, currency_code, website_url)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (operator_code) DO UPDATE SET
                    name = EXCLUDED.name,
                    country_code = EXCLUDED.country_code,
                    currency_code = EXCLUDED.currency_code,
                    website_url = EXCLUDED.website_url
                """,
                (op["operator_code"], op["name"], op["country_code"], op["currency_code"], op.get("website_url")),
            )

        # 2. Corridors
        for cor in ops_data["corridors"]:
            cur.execute(
                """
                INSERT INTO tolls.corridors (corridor_id, operator_code, highway_ref, name, system_type, country_code, notes)
                VALUES (%s, %s, %s, %s, %s::tolls.system_type, %s, %s)
                ON CONFLICT (corridor_id) DO UPDATE SET
                    operator_code = EXCLUDED.operator_code,
                    highway_ref = EXCLUDED.highway_ref,
                    name = EXCLUDED.name,
                    system_type = EXCLUDED.system_type,
                    country_code = EXCLUDED.country_code,
                    notes = EXCLUDED.notes
                """,
                (
                    cor["corridor_id"],
                    cor["operator_code"],
                    cor.get("highway_ref"),
                    cor["name"],
                    cor["system_type"],
                    cor["country_code"],
                    cor.get("notes"),
                ),
            )

        # 3. Gantries (MY, SG, BN)
        all_gantries = my_data["gantries"] + sg_data["gantries"] + bn_data["gantries"]
        for g in all_gantries:
            upsert_gantry(cur, g)

        # 4. Open & Border Rates (idempotent replace per effective date)
        cur.execute("DELETE FROM tolls.open_rates WHERE effective_from = %s", (EFFECTIVE_FROM,))
        for r in my_data["open_rates"] + bn_data["open_rates"]:
            cur.execute(
                """
                INSERT INTO tolls.open_rates (
                    gantry_id, country_code, vehicle_class, payment_method,
                    foreign_vehicle_only, amount_minor, currency_code, effective_from
                )
                VALUES (%s, %s, %s, %s::tolls.payment_method, %s, %s, %s, %s)
                """,
                (
                    r["gantry_id"],
                    r["country_code"],
                    r["vehicle_class"],
                    r.get("payment_method"),
                    bool(r.get("foreign_vehicle_only", False)),
                    int(r["amount_minor"]),
                    r["currency_code"],
                    EFFECTIVE_FROM,
                ),
            )

        # 5. Closed-System Matrix Rates (PLUS E1/E2)
        matrix_path = SEED_DIR / "my_closed_plus_matrix.csv"
        matrix_count = 0
        with matrix_path.open("r", encoding="utf-8", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                pairs = [(row["entry_gantry_id"], row["exit_gantry_id"])]
                if row.get("symmetric", "false").lower() == "true":
                    pairs.append((row["exit_gantry_id"], row["entry_gantry_id"]))

                for entry_id, exit_id in pairs:
                    cur.execute(
                        """
                        INSERT INTO tolls.closed_matrix_rates (
                            corridor_id, entry_gantry_id, exit_gantry_id,
                            country_code, vehicle_class, distance_km,
                            amount_minor, currency_code, effective_from
                        )
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT (corridor_id, entry_gantry_id, exit_gantry_id, vehicle_class, effective_from)
                        DO UPDATE SET
                            distance_km = EXCLUDED.distance_km,
                            amount_minor = EXCLUDED.amount_minor,
                            currency_code = EXCLUDED.currency_code
                        """,
                        (
                            row["corridor_id"],
                            entry_id,
                            exit_id,
                            row["country_code"],
                            row["vehicle_class"],
                            float(row["distance_km"]),
                            int(row["amount_minor"]),
                            row["currency_code"],
                            EFFECTIVE_FROM,
                        ),
                    )
                    matrix_count += 1

        # 6. Singapore ERP Schedules (expanded across official LTA vehicle class multipliers)
        cur.execute("DELETE FROM tolls.erp_schedules WHERE effective_from = %s", (EFFECTIVE_FROM,))
        erp_count = 0
        for s in sg_data["schedules"]:
            base_cents = int(s["sg_pc_cents"])
            for vclass, mult in SG_ERP_MULTIPLIERS:
                amt = int(round(base_cents * mult))
                cur.execute(
                    """
                    INSERT INTO tolls.erp_schedules (
                        gantry_id, country_code, vehicle_class, day_type,
                        start_time, end_time, amount_minor, currency_code, effective_from, source_etag
                    )
                    VALUES (%s, 'SG', %s, %s, %s::time, %s::time, %s, 'SGD', %s, 'curated-phase1')
                    """,
                    (
                        s["gantry_id"],
                        vclass,
                        s["day_type"],
                        s["start_time"],
                        s["end_time"],
                        amt,
                        EFFECTIVE_FROM,
                    ),
                )
                erp_count += 1

        # 7. Public Holidays
        for ph in bn_data["public_holidays"]:
            cur.execute(
                """
                INSERT INTO tolls.public_holidays (country_code, holiday_date, name, toll_override_rule)
                VALUES (%s, %s::date, %s, %s)
                ON CONFLICT (country_code, holiday_date) DO UPDATE SET
                    name = EXCLUDED.name,
                    toll_override_rule = EXCLUDED.toll_override_rule
                """,
                (ph["country_code"], ph["holiday_date"], ph["name"], ph["toll_override_rule"]),
            )

    conn.commit()
    print(
        f"[07_load_tolls] Loaded {len(all_gantries)} gantries, "
        f"{matrix_count} closed-matrix entries, and {erp_count} SG ERP schedule windows."
    )


def file_sha256_and_size(path: Path) -> tuple[str, int]:
    if not path.exists():
        return ("0" * 64, 0)
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return (h.hexdigest(), path.stat().st_size)


def export_offline_sqlite_and_register_regions(conn: psycopg.Connection) -> None:
    """
    Exports a lightweight regional SQLite toll database per offline pack so
    Phase 2 mobile devices can compute offline pre-route tolls identically to the server,
    and updates `geo.offline_regions` with live SHA-256 & byte manifests.
    """
    catalog = yaml.safe_load(REGIONS_CATALOG.read_text(encoding="utf-8"))
    pmtiles_base = os.environ.get("PMTILES_PUBLIC_URL", "http://localhost:8081").rstrip("/")
    packs_base = os.environ.get("OFFLINE_PACKS_BASE_URL", "http://localhost:8000/v1/regions/downloads").rstrip("/")
    data_version = dt.date.today().isoformat()

    for reg in catalog["regions"]:
        rid = reg["region_id"]
        min_lon, min_lat, max_lon, max_lat = reg["bbox"]
        pack_dir = OFFLINE_PACKS_DIR / rid
        pack_dir.mkdir(parents=True, exist_ok=True)
        sqlite_path = pack_dir / f"tolls_{rid}.sqlite"
        if sqlite_path.exists():
            sqlite_path.unlink()

        with sqlite3.connect(sqlite_path) as sconn, conn.cursor() as cur:
            sconn.executescript(
                """
                CREATE TABLE gantries (
                    gantry_id TEXT PRIMARY KEY,
                    corridor_id TEXT NOT NULL,
                    system_type TEXT NOT NULL,
                    country_code TEXT NOT NULL,
                    name TEXT NOT NULL,
                    role TEXT NOT NULL,
                    direction_bearing INTEGER,
                    bearing_tolerance INTEGER NOT NULL,
                    accepted_payments_json TEXT NOT NULL,
                    lane_layout_json TEXT NOT NULL,
                    lat REAL NOT NULL,
                    lon REAL NOT NULL,
                    tripwire_wkt TEXT NOT NULL
                );
                CREATE TABLE open_rates (
                    gantry_id TEXT NOT NULL,
                    vehicle_class TEXT NOT NULL,
                    foreign_vehicle_only INTEGER NOT NULL,
                    amount_minor INTEGER NOT NULL,
                    currency_code TEXT NOT NULL
                );
                CREATE TABLE closed_matrix_rates (
                    corridor_id TEXT NOT NULL,
                    entry_gantry_id TEXT NOT NULL,
                    exit_gantry_id TEXT NOT NULL,
                    vehicle_class TEXT NOT NULL,
                    amount_minor INTEGER NOT NULL,
                    currency_code TEXT NOT NULL
                );
                CREATE TABLE erp_schedules (
                    gantry_id TEXT NOT NULL,
                    vehicle_class TEXT NOT NULL,
                    day_type TEXT NOT NULL,
                    start_time TEXT NOT NULL,
                    end_time TEXT NOT NULL,
                    amount_minor INTEGER NOT NULL,
                    currency_code TEXT NOT NULL
                );
                CREATE TABLE public_holidays (
                    country_code TEXT NOT NULL,
                    holiday_date TEXT NOT NULL,
                    toll_override_rule TEXT NOT NULL
                );
                """
            )

            cur.execute(
                """
                SELECT g.gantry_id, g.corridor_id, c.system_type::text, c.country_code,
                       g.name, g.role::text, g.direction_bearing, g.bearing_tolerance,
                       array_to_json(g.accepted_payments)::text, g.lane_layout::text,
                       ST_Y(g.geom), ST_X(g.geom), ST_AsText(g.detection_line)
                FROM tolls.gantries g
                JOIN tolls.corridors c ON c.corridor_id = g.corridor_id
                WHERE g.is_active = TRUE
                  AND ST_Intersects(g.geom, ST_MakeEnvelope(%s, %s, %s, %s, 4326))
                """,
                (min_lon, min_lat, max_lon, max_lat),
            )
            g_rows = cur.fetchall()
            g_ids = [r[0] for r in g_rows]
            sconn.executemany(
                "INSERT INTO gantries VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                g_rows,
            )

            if g_ids:
                cur.execute(
                    """
                    SELECT gantry_id, vehicle_class, foreign_vehicle_only::int, amount_minor, currency_code
                    FROM tolls.open_rates
                    WHERE gantry_id = ANY(%s) AND (effective_to IS NULL OR effective_to >= CURRENT_DATE)
                    """,
                    (g_ids,),
                )
                sconn.executemany("INSERT INTO open_rates VALUES (?,?,?,?,?)", cur.fetchall())

                cur.execute(
                    """
                    SELECT corridor_id, entry_gantry_id, exit_gantry_id, vehicle_class, amount_minor, currency_code
                    FROM tolls.closed_matrix_rates
                    WHERE (entry_gantry_id = ANY(%s) OR exit_gantry_id = ANY(%s))
                      AND (effective_to IS NULL OR effective_to >= CURRENT_DATE)
                    """,
                    (g_ids, g_ids),
                )
                sconn.executemany("INSERT INTO closed_matrix_rates VALUES (?,?,?,?,?,?)", cur.fetchall())

                cur.execute(
                    """
                    SELECT gantry_id, vehicle_class, day_type, to_char(start_time, 'HH24:MI'),
                           to_char(end_time, 'HH24:MI'), amount_minor, currency_code
                    FROM tolls.erp_schedules
                    WHERE gantry_id = ANY(%s) AND (effective_to IS NULL OR effective_to >= CURRENT_DATE)
                    """,
                    (g_ids,),
                )
                sconn.executemany("INSERT INTO erp_schedules VALUES (?,?,?,?,?,?,?)", cur.fetchall())

            cur.execute(
                "SELECT country_code, to_char(holiday_date, 'YYYY-MM-DD'), toll_override_rule FROM tolls.public_holidays"
            )
            sconn.executemany("INSERT INTO public_holidays VALUES (?,?,?)", cur.fetchall())
            sconn.commit()

        pm_sha, pm_bytes = file_sha256_and_size(PMTILES_DIR / f"{rid}.pmtiles")
        val_sha, val_bytes = file_sha256_and_size(pack_dir / "valhalla_tiles.tar")
        sq_sha, sq_bytes = file_sha256_and_size(sqlite_path)

        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO geo.offline_regions (
                    region_id, display_name, country_codes, bbox_geom, data_version,
                    pmtiles_url, pmtiles_sha256, pmtiles_bytes,
                    valhalla_tar_url, valhalla_tar_sha256, valhalla_tar_bytes,
                    tolls_sqlite_url, tolls_sqlite_sha256, tolls_sqlite_bytes, updated_at
                )
                VALUES (
                    %s, %s, %s::char(2)[], ST_MakeEnvelope(%s, %s, %s, %s, 4326), %s,
                    %s, %s, %s,
                    %s, %s, %s,
                    %s, %s, %s, NOW()
                )
                ON CONFLICT (region_id) DO UPDATE SET
                    display_name = EXCLUDED.display_name,
                    country_codes = EXCLUDED.country_codes,
                    bbox_geom = EXCLUDED.bbox_geom,
                    data_version = EXCLUDED.data_version,
                    pmtiles_url = EXCLUDED.pmtiles_url,
                    pmtiles_sha256 = EXCLUDED.pmtiles_sha256,
                    pmtiles_bytes = EXCLUDED.pmtiles_bytes,
                    valhalla_tar_url = EXCLUDED.valhalla_tar_url,
                    valhalla_tar_sha256 = EXCLUDED.valhalla_tar_sha256,
                    valhalla_tar_bytes = EXCLUDED.valhalla_tar_bytes,
                    tolls_sqlite_url = EXCLUDED.tolls_sqlite_url,
                    tolls_sqlite_sha256 = EXCLUDED.tolls_sqlite_sha256,
                    tolls_sqlite_bytes = EXCLUDED.tolls_sqlite_bytes,
                    updated_at = NOW()
                """,
                (
                    rid,
                    reg["display_name"],
                    reg["country_codes"],
                    min_lon,
                    min_lat,
                    max_lon,
                    max_lat,
                    data_version,
                    f"{pmtiles_base}/{rid}.pmtiles",
                    pm_sha,
                    pm_bytes,
                    f"{packs_base}/{rid}/valhalla_tiles.tar",
                    val_sha,
                    val_bytes,
                    f"{packs_base}/{rid}/tolls_{rid}.sqlite",
                    sq_sha,
                    sq_bytes,
                ),
            )
    conn.commit()
    print("[07_load_tolls] Exported offline SQLite toll packs and updated geo.offline_regions.")


def main() -> int:
    with psycopg.connect(get_dsn()) as conn:
        load_all_tolls(conn)
        export_offline_sqlite_and_register_regions(conn)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
