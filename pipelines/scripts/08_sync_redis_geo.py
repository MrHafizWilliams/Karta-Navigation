#!/usr/bin/env python3
"""
Stage 08: Atomically Hydrate Redis Geo Spatial Indexes from PostGIS

Populates:
  - karta:geo:pois:all & karta:geo:pois:{category}  (Redis GEO sets)
  - karta:poi:meta:{id}                             (Redis Hash compact metadata)
  - karta:geo:gantries & karta:gantry:meta:{id}     (Regional MY/SG/BN toll gantries)
  - karta:geo:speed_zones & karta:speed:meta:{id}   (AWAS / TP speed cameras & zones)

Uses temporary staging keys + atomic RENAME swaps so active viewport queries
experience zero downtime during map data refreshes.
"""

from __future__ import annotations

import json
import os
import time
from collections import defaultdict

import psycopg
import redis


def get_pg_dsn() -> str:
    return (
        f"host={os.environ.get('PGHOST', 'postgres')} "
        f"port={os.environ.get('PGPORT', '5432')} "
        f"dbname={os.environ.get('PGDATABASE', 'karta')} "
        f"user={os.environ.get('PGUSER', 'karta')} "
        f"password={os.environ.get('PGPASSWORD', 'karta_dev_change_me')}"
    )


def sync_pois(conn: psycopg.Connection, r: redis.Redis) -> int:
    stamp = str(int(time.time()))
    tmp_all = f"karta:geo:pois:all:tmp:{stamp}"
    cat_tmp_keys: dict[str, str] = {}
    batch_geo_all: list[object] = []
    batch_geo_cat: dict[str, list[object]] = defaultdict(list)

    total = 0
    pipe = r.pipeline(transaction=False)

    with conn.cursor(name="poi_stream_cursor") as cur:
        cur.itersize = 5000
        cur.execute(
            """
            SELECT id, name, category, COALESCE(subcategory, ''), COALESCE(brand, ''),
                   COALESCE(country_code, ''), ST_X(geom) AS lon, ST_Y(geom) AS lat,
                   ev_metadata
            FROM spatial.pois
            WHERE ST_X(geom) BETWEEN -180 AND 180
              AND ST_Y(geom) BETWEEN -85.0511 AND 85.0511
            """
        )

        for row in cur:
            pid, name, category, subcat, brand, cc, lon, lat, ev_meta = row
            member = str(pid)
            cat_key = f"karta:geo:pois:{category}:tmp:{stamp}"
            cat_tmp_keys[category] = cat_key

            batch_geo_all.extend([float(lon), float(lat), member])
            batch_geo_cat[cat_key].extend([float(lon), float(lat), member])

            meta = {
                "id": member,
                "name": name,
                "category": category,
                "subcategory": subcat,
                "brand": brand,
                "country_code": cc,
                "lon": f"{float(lon):.6f}",
                "lat": f"{float(lat):.6f}",
            }
            if ev_meta:
                meta["ev_metadata"] = json.dumps(ev_meta)
            pipe.hset(f"karta:poi:meta:{member}", mapping=meta)

            total += 1
            if total % 2000 == 0:
                if batch_geo_all:
                    pipe.execute_command("GEOADD", tmp_all, *batch_geo_all)
                    batch_geo_all.clear()
                for ck, items in batch_geo_cat.items():
                    if items:
                        pipe.execute_command("GEOADD", ck, *items)
                        items.clear()
                pipe.execute()

    if batch_geo_all:
        pipe.execute_command("GEOADD", tmp_all, *batch_geo_all)
    for ck, items in batch_geo_cat.items():
        if items:
            pipe.execute_command("GEOADD", ck, *items)
    pipe.execute()

    if total > 0:
        r.rename(tmp_all, "karta:geo:pois:all")
        for category, tmp_key in cat_tmp_keys.items():
            if r.exists(tmp_key):
                r.rename(tmp_key, f"karta:geo:pois:{category}")
        r.sadd("karta:geo:poi_categories", *cat_tmp_keys.keys())

    return total


def sync_gantries(conn: psycopg.Connection, r: redis.Redis) -> int:
    stamp = str(int(time.time()))
    tmp_key = f"karta:geo:gantries:tmp:{stamp}"
    geo_args: list[object] = []
    pipe = r.pipeline(transaction=False)

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT g.gantry_id, g.corridor_id, c.system_type::text, c.country_code,
                   g.name, g.role::text, g.direction_bearing,
                   array_to_json(g.accepted_payments)::text, g.lane_layout::text,
                   ST_X(g.geom) AS lon, ST_Y(g.geom) AS lat
            FROM tolls.gantries g
            JOIN tolls.corridors c ON c.corridor_id = g.corridor_id
            WHERE g.is_active = TRUE
            """
        )
        rows = cur.fetchall()

    for row in rows:
        gid, cid, stype, cc, name, role, bearing, payments_json, layout_json, lon, lat = row
        geo_args.extend([float(lon), float(lat), gid])
        pipe.hset(
            f"karta:gantry:meta:{gid}",
            mapping={
                "gantry_id": gid,
                "corridor_id": cid,
                "system_type": stype,
                "country_code": cc,
                "name": name,
                "role": role,
                "direction_bearing": "" if bearing is None else str(bearing),
                "accepted_payments": payments_json,
                "lane_layout": layout_json,
                "lon": f"{float(lon):.6f}",
                "lat": f"{float(lat):.6f}",
            },
        )

    if geo_args:
        pipe.execute_command("GEOADD", tmp_key, *geo_args)
    pipe.execute()

    if rows:
        r.rename(tmp_key, "karta:geo:gantries")
    return len(rows)


def sync_speed_zones(conn: psycopg.Connection, r: redis.Redis) -> int:
    stamp = str(int(time.time()))
    tmp_key = f"karta:geo:speed_zones:tmp:{stamp}"
    geo_args: list[object] = []
    pipe = r.pipeline(transaction=False)

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT id, zone_type, COALESCE(country_code, ''), COALESCE(road_name, ''),
                   limit_kmh, heading_deg, ST_X(geom), ST_Y(geom)
            FROM spatial.speed_zones
            """
        )
        rows = cur.fetchall()

    for row in rows:
        sid, ztype, cc, road, limit_kmh, heading, lon, lat = row
        member = str(sid)
        geo_args.extend([float(lon), float(lat), member])
        pipe.hset(
            f"karta:speed:meta:{member}",
            mapping={
                "id": member,
                "zone_type": ztype,
                "country_code": cc,
                "road_name": road,
                "limit_kmh": str(limit_kmh),
                "heading_deg": "" if heading is None else str(heading),
                "lon": f"{float(lon):.6f}",
                "lat": f"{float(lat):.6f}",
            },
        )

    if geo_args:
        pipe.execute_command("GEOADD", tmp_key, *geo_args)
    pipe.execute()

    if rows:
        r.rename(tmp_key, "karta:geo:speed_zones")
    return len(rows)


def main() -> int:
    r = redis.from_url(os.environ.get("REDIS_URL", "redis://redis:6379/0"), decode_responses=True)
    with psycopg.connect(get_pg_dsn()) as conn:
        pois_n = sync_pois(conn, r)
        gantries_n = sync_gantries(conn, r)
        speeds_n = sync_speed_zones(conn, r)

    r.set("karta:meta:last_geo_sync", str(int(time.time())))
    print(
        f"[08_sync_redis_geo] Atomic Redis Geo sync complete: "
        f"pois={pois_n}, gantries={gantries_n}, speed_zones={speeds_n}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
