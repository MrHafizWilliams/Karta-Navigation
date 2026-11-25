#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Karta Master Data Pipeline Orchestrator (runs inside `pipeline` container)
# Executes:
#   01_fetch_osm.sh      -> Verify local MY-SG-BN .osm.pbf (or refresh)
#   02_split_regions.sh  -> Split into downloadable regional PBFs
#   04_fetch_gtfs.py     -> Pull Malaysia Prasarana/KTMB + Singapore open GTFS
#   06_ingest_postgis.sh -> Load POIs, speed limits, turn:lanes, speed zones, borders
#   07_load_tolls.py     -> Load MY/SG/BN toll tariffs + export offline SQLite packs
#   08_sync_redis_geo.py -> Atomically hydrate Redis Geo bounding-box indexes
#
# Note: Planetiler (PMTiles) and Valhalla tile builds run in their dedicated
# containers (`planetiler` and `valhalla-builder`) via Make / scripts/karta.ps1.
# ==============================================================================

REGION="all"
REFRESH_OSM=false
SKIP_GTFS=false
SKIP_PMTILES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2 ;;
    --refresh-osm) REFRESH_OSM=true; shift ;;
    --skip-gtfs) SKIP_GTFS=true; shift ;;
    --skip-pmtiles) SKIP_PMTILES=true; shift ;;
    *) echo "[run_all] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

echo "[run_all] Starting Karta spatial pipeline (region=${REGION})"

if [[ "${REFRESH_OSM}" == "true" ]]; then
  bash /pipelines/scripts/01_fetch_osm.sh --refresh
else
  bash /pipelines/scripts/01_fetch_osm.sh
fi

bash /pipelines/scripts/02_split_regions.sh --region "${REGION}"

if [[ "${SKIP_GTFS}" == "false" ]]; then
  python3 /pipelines/scripts/04_fetch_gtfs.py
else
  echo "[run_all] Skipping GTFS download (--skip-gtfs)"
fi

bash /pipelines/scripts/06_ingest_postgis.sh --region "${REGION}"
python3 /pipelines/scripts/07_load_tolls.py
python3 /pipelines/scripts/08_sync_redis_geo.py

echo "[run_all] Spatial database, tolls, and Redis Geo pipeline complete!"
if [[ "${SKIP_PMTILES}" == "false" ]]; then
  echo "[run_all] Next: build vector tiles and routing graph via:"
  echo "          .\\scripts\\karta.ps1 pmtiles -Region ${REGION}"
  echo "          .\\scripts\\karta.ps1 valhalla-build -Region ${REGION}"
fi
