#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Stage 01: Verify / Fetch Geofabrik MY-SG-BN OpenStreetMap Extract (.osm.pbf)
# Reuses pre-placed /data/raw/osm/malaysia-singapore-brunei-latest.osm.pbf by default.
# Pass --refresh to download a fresh copy from Geofabrik with MD5 verification.
# ==============================================================================

REFRESH=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh) REFRESH=true; shift ;;
    *) echo "[01_fetch_osm] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

OSM_DIR="/data/raw/osm"
OSM_FILENAME="${OSM_PBF_FILENAME:-malaysia-singapore-brunei-latest.osm.pbf}"
OSM_PATH="${OSM_DIR}/${OSM_FILENAME}"
OSM_URL="${OSM_SOURCE_URL:-https://download.geofabrik.de/asia/malaysia-singapore-brunei-latest.osm.pbf}"
MD5_URL="${OSM_URL}.md5"

mkdir -p "${OSM_DIR}"

if [[ -f "${OSM_PATH}" && "${REFRESH}" == "false" ]]; then
  SIZE_BYTES=$(stat -c%s "${OSM_PATH}" 2>/dev/null || wc -c < "${OSM_PATH}")
  if [[ "${SIZE_BYTES}" -gt 10000000 ]]; then
    echo "[01_fetch_osm] Reusing local OSM extract: ${OSM_PATH} (${SIZE_BYTES} bytes)"
    if command -v osmium >/dev/null 2>&1; then
      osmium fileinfo "${OSM_PATH}" | head -n 12 || true
    fi
    exit 0
  else
    echo "[01_fetch_osm] Local file looks truncated (${SIZE_BYTES} bytes); re-downloading..."
  fi
fi

echo "[01_fetch_osm] Downloading ${OSM_URL} -> ${OSM_PATH}"
curl -fL --retry 3 --retry-delay 5 -o "${OSM_PATH}.tmp" "${OSM_URL}"

echo "[01_fetch_osm] Verifying MD5 checksum from ${MD5_URL}"
if curl -fsSL "${MD5_URL}" -o "${OSM_PATH}.md5"; then
  EXPECTED_MD5=$(awk '{print $1}' "${OSM_PATH}.md5")
  ACTUAL_MD5=$(md5sum "${OSM_PATH}.tmp" | awk '{print $1}')
  if [[ "${EXPECTED_MD5}" != "${ACTUAL_MD5}" ]]; then
    echo "[01_fetch_osm] ERROR: MD5 mismatch! expected=${EXPECTED_MD5} actual=${ACTUAL_MD5}" >&2
    rm -f "${OSM_PATH}.tmp"
    exit 1
  fi
  echo "[01_fetch_osm] MD5 verified: ${ACTUAL_MD5}"
else
  echo "[01_fetch_osm] WARNING: Could not fetch .md5 checksum; continuing with downloaded file."
fi

mv "${OSM_PATH}.tmp" "${OSM_PATH}"
echo "[01_fetch_osm] Done: ${OSM_PATH}"
