#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Stage 02: Split MY-SG-BN .osm.pbf into 6 Downloadable Regional Extracts
# Uses `osmium extract --strategy=complete_ways` with 5km cross-border buffers.
# Usage: 02_split_regions.sh [--region all|sg|bn|my-peninsular-central|...]
# ==============================================================================

TARGET_REGION="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) TARGET_REGION="$2"; shift 2 ;;
    *) echo "[02_split_regions] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

OSM_FILENAME="${OSM_PBF_FILENAME:-malaysia-singapore-brunei-latest.osm.pbf}"
SRC_PBF="/data/raw/osm/${OSM_FILENAME}"
OUT_DIR="/data/raw/osm/regions"
POLY_DIR="/pipelines/regions"

if [[ ! -f "${SRC_PBF}" ]]; then
  echo "[02_split_regions] ERROR: Source PBF not found at ${SRC_PBF}. Run 01_fetch_osm.sh first." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

ALL_REGIONS=(
  "my-peninsular-central"
  "my-peninsular-north"
  "my-peninsular-south"
  "my-borneo"
  "sg"
  "bn"
)

if [[ "${TARGET_REGION}" == "all" ]]; then
  REGIONS_TO_BUILD=("${ALL_REGIONS[@]}")
else
  REGIONS_TO_BUILD=("${TARGET_REGION}")
fi

for REGION in "${REGIONS_TO_BUILD[@]}"; do
  POLY="${POLY_DIR}/${REGION}.geojson"
  OUT_PBF="${OUT_DIR}/${REGION}.osm.pbf"

  if [[ ! -f "${POLY}" ]]; then
    echo "[02_split_regions] ERROR: Region polygon not found: ${POLY}" >&2
    exit 1
  fi

  echo "[02_split_regions] Extracting region '${REGION}' -> ${OUT_PBF}"
  osmium extract \
    --polygon "${POLY}" \
    --strategy=complete_ways \
    --overwrite \
    -o "${OUT_PBF}" \
    "${SRC_PBF}"

  SIZE_BYTES=$(stat -c%s "${OUT_PBF}" 2>/dev/null || wc -c < "${OUT_PBF}")
  echo "[02_split_regions] Built ${OUT_PBF} (${SIZE_BYTES} bytes)"
done

echo "[02_split_regions] Regional extraction complete."
