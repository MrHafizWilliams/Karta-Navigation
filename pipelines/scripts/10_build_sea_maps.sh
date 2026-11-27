#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Stage 10: Merge All 8 Southeast Asian OSM Extracts (`Karta/maps/*.osm.pbf` +
# `malaysia-singapore-brunei-latest.osm.pbf`) into unified `/data/raw/osm/sea-full.osm.pbf`
# and stage per-country extracts for PMTiles, Valhalla & PostGIS.
# Runs inside the `pipeline` container (has `osmium-tool`).
# ==============================================================================

RAW_DIR="/data/raw/osm"
REGIONS_DIR="${RAW_DIR}/regions"
MAPS_DIR="/data/maps"
mkdir -p "${RAW_DIR}" "${REGIONS_DIR}"

INPUTS=()

BASE_PBF="${RAW_DIR}/malaysia-singapore-brunei-latest.osm.pbf"
if [[ -f "${BASE_PBF}" ]]; then
  INPUTS+=("${BASE_PBF}")
fi

declare -A COUNTRY_MAP=(
  ["id"]="indonesia-latest.osm.pbf"
  ["th"]="thailand-latest.osm.pbf"
  ["ph"]="philippines-latest.osm.pbf"
  ["vn"]="vietnam-latest.osm.pbf"
  ["mm"]="myanmar-latest.osm.pbf"
  ["la"]="laos-latest.osm.pbf"
  ["kh"]="cambodia-latest.osm.pbf"
  ["tl"]="east-timor-latest.osm.pbf"
)

for CODE in id th ph vn mm la kh tl; do
  SRC="${MAPS_DIR}/${COUNTRY_MAP[$CODE]}"
  if [[ -f "${SRC}" ]]; then
    echo "[10_build_sea_maps] Found ${CODE^^} extract: ${SRC}"
    ln -sf "${SRC}" "${REGIONS_DIR}/${CODE}.osm.pbf"
    INPUTS+=("${SRC}")
  else
    echo "[10_build_sea_maps] WARNING: Missing ${SRC}; skipping ${CODE^^}."
  fi
done

if [[ "${#INPUTS[@]}" -eq 0 ]]; then
  echo "[10_build_sea_maps] ERROR: No OSM PBF files found to merge." >&2
  exit 1
fi

MERGED_PBF="${RAW_DIR}/sea-full.osm.pbf"
echo "[10_build_sea_maps] Merging ${#INPUTS[@]} Southeast Asia extracts into ${MERGED_PBF}..."
osmium merge "${INPUTS[@]}" -o "${MERGED_PBF}" --overwrite

ls -lh "${MERGED_PBF}"
echo "[10_build_sea_maps] Unified 8-country SEA extract ready at ${MERGED_PBF}."
