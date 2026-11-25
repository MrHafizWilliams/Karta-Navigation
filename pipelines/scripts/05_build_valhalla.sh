#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Stage 05: Build Valhalla Routing Tiles, GTFS Transit Graph & Offline Tar Extracts
# Runs inside the `valhalla-builder` container (`ghcr.io/valhalla/valhalla-scripted`).
# Produces:
#   - Online server tiles + extract at /data/valhalla/
#   - Downloadable regional extracts + manifest.json at /data/offline_packs/<region>/
# Usage: 05_build_valhalla.sh [--region all|sg|bn|my-peninsular-central|...]
# ==============================================================================

TARGET_REGION="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) TARGET_REGION="$2"; shift 2 ;;
    *) echo "[05_build_valhalla] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

THREADS="${VALHALLA_THREADS:-4}"
BUILD_TRANSIT="${VALHALLA_BUILD_TRANSIT:-True}"
TEMPLATE="/config/valhalla/valhalla.json.template"
GTFS_DIR="/data/raw/gtfs"
DATA_VERSION="$(date -u +%Y-%m-%d)"

render_config() {
  local work_dir="$1"
  local cfg_out="${work_dir}/valhalla.json"
  python3 - "$TEMPLATE" "$cfg_out" "$work_dir" "$GTFS_DIR" "$THREADS" <<'PYEOF'
import json, sys
tpl_path, out_path, work_dir, gtfs_dir, threads = sys.argv[1:6]
with open(tpl_path, "r", encoding="utf-8") as f:
    cfg = json.load(f)
cfg["mjolnir"]["tile_dir"] = f"{work_dir}/valhalla_tiles"
cfg["mjolnir"]["tile_extract"] = f"{work_dir}/valhalla_tiles.tar"
cfg["mjolnir"]["traffic_extract"] = f"{work_dir}/traffic.tar"
cfg["mjolnir"]["admin"] = f"{work_dir}/admins.sqlite"
cfg["mjolnir"]["timezone"] = f"{work_dir}/timezones.sqlite"
cfg["mjolnir"]["transit_dir"] = f"{work_dir}/transit_tiles"
cfg["mjolnir"]["transit_feeds_dir"] = gtfs_dir
cfg["mjolnir"]["concurrency"] = int(threads)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
PYEOF
}

build_target() {
  local name="$1"
  local pbf_path="$2"
  local work_dir="$3"
  local include_transit="$4"

  if [[ ! -f "${pbf_path}" ]]; then
    echo "[05_build_valhalla] ERROR: PBF not found: ${pbf_path}" >&2
    return 1
  fi

  echo "[05_build_valhalla] === Building Valhalla graph for '${name}' from ${pbf_path} ==="
  mkdir -p "${work_dir}/valhalla_tiles" "${work_dir}/transit_tiles"
  render_config "${work_dir}"
  local cfg="${work_dir}/valhalla.json"

  echo "[05_build_valhalla] Building admins.sqlite..."
  valhalla_build_admins -c "${cfg}" "${pbf_path}"

  echo "[05_build_valhalla] Building timezones.sqlite..."
  valhalla_build_timezones > "${work_dir}/timezones.sqlite"

  # Ingest GTFS if enabled and feed folders exist
  if [[ "${include_transit}" == "True" && -d "${GTFS_DIR}" ]] && [[ -n "$(find "${GTFS_DIR}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]]; then
    echo "[05_build_valhalla] Ingesting GTFS transit feeds from ${GTFS_DIR}..."
    if valhalla_ingest_transit -c "${cfg}"; then
      echo "[05_build_valhalla] Converting GTFS transit tiles..."
      valhalla_convert_transit -c "${cfg}" || echo "[05_build_valhalla] WARNING: transit conversion had partial errors; continuing road graph."
    else
      echo "[05_build_valhalla] WARNING: valhalla_ingest_transit failed; continuing with road/pedestrian/cycle graph."
    fi
  else
    echo "[05_build_valhalla] Skipping GTFS transit step (no feeds present or disabled)."
  fi

  echo "[05_build_valhalla] Building hierarchical routing tiles (threads=${THREADS})..."
  valhalla_build_tiles -c "${cfg}" "${pbf_path}"

  echo "[05_build_valhalla] Packaging single-file valhalla_tiles.tar extract..."
  valhalla_build_extract -c "${cfg}" -v

  local tar_path="${work_dir}/valhalla_tiles.tar"
  local sha
  sha=$(sha256sum "${tar_path}" | awk '{print $1}')
  local size_bytes
  size_bytes=$(stat -c%s "${tar_path}")

  cat > "${work_dir}/manifest.json" <<EOF
{
  "region_id": "${name}",
  "data_version": "${DATA_VERSION}",
  "valhalla_tar": "valhalla_tiles.tar",
  "valhalla_tar_sha256": "${sha}",
  "valhalla_tar_bytes": ${size_bytes},
  "includes_transit": $( [[ "${include_transit}" == "True" ]] && echo "true" || echo "false" )
}
EOF

  echo "[05_build_valhalla] Completed '${name}': ${tar_path} (${size_bytes} bytes, sha256=${sha:0:12}...)"
}

if [[ "${TARGET_REGION}" == "all" ]]; then
  FULL_PBF="/data/raw/osm/${OSM_PBF_FILENAME:-malaysia-singapore-brunei-latest.osm.pbf}"
  build_target "my-sg-bn-full" "${FULL_PBF}" "/data/valhalla" "${BUILD_TRANSIT}"

  # Build regional offline packs for any split regional PBFs that exist
  for REGION in my-peninsular-central my-peninsular-north my-peninsular-south my-borneo sg bn; do
    REG_PBF="/data/raw/osm/regions/${REGION}.osm.pbf"
    if [[ -f "${REG_PBF}" ]]; then
      build_target "${REGION}" "${REG_PBF}" "/data/offline_packs/${REGION}" "False"
    fi
  done
else
  REG_PBF="/data/raw/osm/regions/${TARGET_REGION}.osm.pbf"
  build_target "${TARGET_REGION}" "${REG_PBF}" "/data/offline_packs/${TARGET_REGION}" "${BUILD_TRANSIT}"
  # Also point online server /data/valhalla to this smoke-test extract if no full extract exists yet
  if [[ ! -f "/data/valhalla/valhalla_tiles.tar" ]]; then
    echo "[05_build_valhalla] Populating /data/valhalla/ from '${TARGET_REGION}' for immediate API testing..."
    mkdir -p /data/valhalla
    cp "/data/offline_packs/${TARGET_REGION}/valhalla_tiles.tar" /data/valhalla/valhalla_tiles.tar
    cp "/data/offline_packs/${TARGET_REGION}/admins.sqlite" /data/valhalla/admins.sqlite
    cp "/data/offline_packs/${TARGET_REGION}/timezones.sqlite" /data/valhalla/timezones.sqlite
    render_config "/data/valhalla"
  fi
fi

echo "[05_build_valhalla] All requested Valhalla builds complete."
