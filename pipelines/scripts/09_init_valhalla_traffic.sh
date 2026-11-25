#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Stage 09: Initialize Valhalla Memory-Mapped Live Traffic Archive (traffic.tar)
# Runs inside the `valhalla-builder` container (`ghcr.io/valhalla/valhalla-scripted`).
# Creates an aligned blank `traffic.tar` matching `/data/valhalla/valhalla_tiles.tar`
# so Karta's Phase 3 ValhallaTrafficTarWriter can update edge speeds live in-place
# for `speed_types: ["current", "predicted", "constrained", "freeflow"]`.
# ==============================================================================

VALHALLA_CFG="/data/valhalla/valhalla.json"
TRAFFIC_TAR="/data/valhalla/traffic.tar"

if [[ ! -f "${VALHALLA_CFG}" ]]; then
  echo "[09_init_valhalla_traffic] ERROR: ${VALHALLA_CFG} not found. Run stage 05 first." >&2
  exit 1
fi

if command -v valhalla_traffic_demo_utils >/dev/null 2>&1; then
  echo "[09_init_valhalla_traffic] Initializing ${TRAFFIC_TAR} via valhalla_traffic_demo_utils..."
  valhalla_traffic_demo_utils --config "${VALHALLA_CFG}" --generate-live-traffic
elif command -v valhalla_build_extract >/dev/null 2>&1; then
  echo "[09_init_valhalla_traffic] Creating empty traffic extract alignment at ${TRAFFIC_TAR}..."
  valhalla_build_extract -c "${VALHALLA_CFG}" -t "${TRAFFIC_TAR}" -v || true
else
  echo "[09_init_valhalla_traffic] WARNING: Traffic builder utility unavailable; Tier-1 dynamic costing remains active."
fi

if [[ -f "${TRAFFIC_TAR}" ]]; then
  echo "[09_init_valhalla_traffic] Ready: $(ls -lh "${TRAFFIC_TAR}")"
fi
