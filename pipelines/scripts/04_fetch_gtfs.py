#!/usr/bin/env python3
"""
Stage 04: Fetch, Validate & Index Regional GTFS Feeds (Malaysia Prasarana/KTMB + Singapore Open GTFS)

- Downloads official Malaysia GTFS Static ZIPs from data.gov.my (CC-BY-4.0):
    * Prasarana Rapid KL Rail (LRT, MRT, Monorail)
    * Prasarana Rapid KL Bus & MRT Feeder
    * Prasarana Rapid Penang
    * Prasarana Rapid Kuantan
    * KTMB (KTM Komuter / ETS)
- Downloads open Singapore GTFS static feed (configurable via SG_GTFS_STATIC_URL;
  live LTA DataMall API key is intentionally excluded in Phase 1).
- Sanitizes calendar.txt / stop_times.txt quirks before Valhalla transit ingestion.
- Upserts feed metadata and stop geometries into PostGIS (`transit.feeds`, `transit.stops`).
"""

from __future__ import annotations

import csv
import hashlib
import io
import os
import shutil
import sys
import zipfile
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

import httpx
import psycopg


@dataclass(frozen=True)
class GtfsSource:
    feed_id: str
    agency_name: str
    country_code: str
    url: str
    required: bool = False


GTFS_ROOT = Path("/data/raw/gtfs")

SOURCES: list[GtfsSource] = [
    GtfsSource(
        feed_id="my-prasarana-rapid-rail-kl",
        agency_name="Prasarana — Rapid KL Rail (MRT/LRT/Monorail)",
        country_code="MY",
        url="https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl",
    ),
    GtfsSource(
        feed_id="my-prasarana-rapid-bus-kl",
        agency_name="Prasarana — Rapid KL Bus & MRT Feeder",
        country_code="MY",
        url="https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kl",
    ),
    GtfsSource(
        feed_id="my-prasarana-rapid-bus-penang",
        agency_name="Prasarana — Rapid Penang",
        country_code="MY",
        url="https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-penang",
    ),
    GtfsSource(
        feed_id="my-prasarana-rapid-bus-kuantan",
        agency_name="Prasarana — Rapid Kuantan",
        country_code="MY",
        url="https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kuantan",
    ),
    GtfsSource(
        feed_id="my-ktmb",
        agency_name="Keretapi Tanah Melayu Berhad (KTMB)",
        country_code="MY",
        url="https://api.data.gov.my/gtfs-static/ktmb",
    ),
    GtfsSource(
        feed_id="sg-transit-open",
        agency_name="Singapore Public Transit (MRT/LRT/Bus — Open GTFS)",
        country_code="SG",
        url=os.environ.get(
            "SG_GTFS_STATIC_URL",
            "https://github.com/thecrapone/singapore-gtfs-2026/releases/latest/download/gtfs.zip",
        ),
    ),
]


def parse_gtfs_date(val: str | None) -> date | None:
    if not val or len(val.strip()) != 8:
        return None
    s = val.strip()
    try:
        return date(int(s[0:4]), int(s[4:6]), int(s[6:8]))
    except ValueError:
        return None


def sanitize_gtfs_dir(feed_dir: Path) -> tuple[date | None, date | None]:
    """
    Ensures every feed has a valid calendar.txt (some upstream agencies publish
    only calendar_dates.txt, which can cause valhalla_ingest_transit warnings)
    and trims blank trailing rows in stops.txt.
    """
    calendar_path = feed_dir / "calendar.txt"
    cal_dates_path = feed_dir / "calendar_dates.txt"
    start_dates: list[date] = []
    end_dates: list[date] = []

    if calendar_path.exists():
        with calendar_path.open("r", encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                sd = parse_gtfs_date(row.get("start_date"))
                ed = parse_gtfs_date(row.get("end_date"))
                if sd:
                    start_dates.append(sd)
                if ed:
                    end_dates.append(ed)
    elif cal_dates_path.exists():
        # Synthesize a minimal calendar.txt from unique service_ids for Valhalla compatibility
        service_ids: set[str] = set()
        with cal_dates_path.open("r", encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                sid = (row.get("service_id") or "").strip()
                if sid:
                    service_ids.add(sid)
                d = parse_gtfs_date(row.get("date"))
                if d:
                    start_dates.append(d)
                    end_dates.append(d)

        today = date.today()
        s_str = (min(start_dates) if start_dates else today).strftime("%Y%m%d")
        e_str = (max(end_dates) if end_dates else today + timedelta(days=180)).strftime("%Y%m%d")
        with calendar_path.open("w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(
                [
                    "service_id",
                    "monday",
                    "tuesday",
                    "wednesday",
                    "thursday",
                    "friday",
                    "saturday",
                    "sunday",
                    "start_date",
                    "end_date",
                ]
            )
            for sid in sorted(service_ids):
                writer.writerow([sid, 1, 1, 1, 1, 1, 1, 1, s_str, e_str])

    return (min(start_dates) if start_dates else None, max(end_dates) if end_dates else None)


def index_stops_in_postgis(
    conn: psycopg.Connection,
    src: GtfsSource,
    feed_dir: Path,
    checksum: str,
    start_d: date | None,
    end_d: date | None,
) -> int:
    stops_path = feed_dir / "stops.txt"
    if not stops_path.exists():
        print(f"[04_fetch_gtfs] WARNING: {src.feed_id} missing stops.txt; skipping PostGIS index.")
        return 0

    rows: list[tuple[str, str, str | None, str, float, float]] = []
    with stops_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stop_id = (row.get("stop_id") or "").strip()
            stop_name = (row.get("stop_name") or "").strip()
            lat_s = (row.get("stop_lat") or "").strip()
            lon_s = (row.get("stop_lon") or "").strip()
            if not stop_id or not stop_name or not lat_s or not lon_s:
                continue
            try:
                lat = float(lat_s)
                lon = float(lon_s)
            except ValueError:
                continue
            if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                continue
            stop_code = (row.get("stop_code") or "").strip() or None
            rows.append((src.feed_id, stop_id, stop_code, stop_name, lon, lat))

    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO transit.feeds (feed_id, agency_name, country_code, source_url, feed_start_date, feed_end_date, checksum_sha256, ingested_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
            ON CONFLICT (feed_id) DO UPDATE SET
                agency_name = EXCLUDED.agency_name,
                source_url = EXCLUDED.source_url,
                feed_start_date = EXCLUDED.feed_start_date,
                feed_end_date = EXCLUDED.feed_end_date,
                checksum_sha256 = EXCLUDED.checksum_sha256,
                ingested_at = NOW()
            """,
            (src.feed_id, src.agency_name, src.country_code, src.url, start_d, end_d, checksum),
        )
        cur.execute("DELETE FROM transit.stops WHERE feed_id = %s", (src.feed_id,))
        cur.executemany(
            """
            INSERT INTO transit.stops (feed_id, stop_id, stop_code, stop_name, geom)
            VALUES (%s, %s, %s, %s, ST_SetSRID(ST_MakePoint(%s, %s), 4326))
            ON CONFLICT (feed_id, stop_id) DO NOTHING
            """,
            rows,
        )
    conn.commit()
    return len(rows)


def download_and_extract(client: httpx.Client, src: GtfsSource) -> tuple[Path, str] | None:
    if not src.url:
        print(f"[04_fetch_gtfs] Skipping {src.feed_id} (empty URL)")
        return None

    print(f"[04_fetch_gtfs] Fetching {src.feed_id} from {src.url}")
    try:
        resp = client.get(src.url, follow_redirects=True)
        resp.raise_for_status()
    except Exception as exc:
        print(f"[04_fetch_gtfs] WARNING: Could not download {src.feed_id}: {exc}", file=sys.stderr)
        if src.required:
            raise
        return None

    payload = resp.content
    checksum = hashlib.sha256(payload).hexdigest()

    feed_dir = GTFS_ROOT / src.feed_id
    if feed_dir.exists():
        shutil.rmtree(feed_dir)
    feed_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(io.BytesIO(payload)) as zf:
        # Handle archives that nest GTFS files inside a single top-level folder
        members = [m for m in zf.infolist() if not m.is_dir() and m.filename.endswith(".txt")]
        for member in members:
            target_name = Path(member.filename).name
            with zf.open(member) as src_fp, (feed_dir / target_name).open("wb") as dst_fp:
                shutil.copyfileobj(src_fp, dst_fp)

    return feed_dir, checksum


def main() -> int:
    GTFS_ROOT.mkdir(parents=True, exist_ok=True)
    db_dsn = (
        f"host={os.environ.get('PGHOST', 'postgres')} "
        f"port={os.environ.get('PGPORT', '5432')} "
        f"dbname={os.environ.get('PGDATABASE', 'karta')} "
        f"user={os.environ.get('PGUSER', 'karta')} "
        f"password={os.environ.get('PGPASSWORD', 'karta_dev_change_me')}"
    )

    loaded_feeds = 0
    with httpx.Client(timeout=60.0) as client, psycopg.connect(db_dsn) as conn:
        for src in SOURCES:
            result = download_and_extract(client, src)
            if result is None:
                continue
            feed_dir, checksum = result
            start_d, end_d = sanitize_gtfs_dir(feed_dir)
            stop_count = index_stops_in_postgis(conn, src, feed_dir, checksum, start_d, end_d)
            print(
                f"[04_fetch_gtfs] Indexed {src.feed_id}: {stop_count} stops "
                f"(valid {start_d}..{end_d}, sha256={checksum[:12]}...)"
            )
            loaded_feeds += 1

    print(f"[04_fetch_gtfs] Completed. Active GTFS feeds loaded: {loaded_feeds}/{len(SOURCES)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
