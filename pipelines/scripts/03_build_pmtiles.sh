#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Stage 03: Convert Regional & Full .osm.pbf Files into Vector PMTiles v3
# Designed to run via Docker Compose (`planetiler` service) or host Docker CLI.
# Usage: 03_build_pmtiles.sh [--region all|sg|bn|my-peninsular-central|...]
# ==============================================================================

TARGET_REGION="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) TARGET_REGION="$2"; shift 2 ;;
    *) echo "[03_build_pmtiles] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/infra/docker/docker-compose.yml"
ENV_FILE="${REPO_ROOT}/.env"

build_one() {
  local pbf_rel="$1"
  local out_name="$2"
  echo "[03_build_pmtiles] Building /data/pmtiles/${out_name} from /data/raw/osm/${pbf_rel}"
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" \
    --profile pipeline run --rm planetiler \
    --download \
    --osm-path="/data/raw/osm/${pbf_rel}" \
    --output="/data/pmtiles/${out_name}" \
    --force
}

if [[ "${TARGET_REGION}" == "all" ]]; then
  build_one "${OSM_PBF_FILENAME:-malaysia-singapore-brunei-latest.osm.pbf}" "my-sg-bn-full.pmtiles"
  for REGION in my-peninsular-central my-peninsular-north my-peninsular-south my-borneo sg bn; do
    if [[ -f "${REPO_ROOT}/data/raw/osm/regions/${REGION}.osm.pbf" ]]; then
      build_one "regions/${REGION}.osm.pbf" "${REGION}.pmtiles"
    else
      echo "[03_build_pmtiles] Skipping ${REGION} (regional PBF not split yet)."
    fi
  done
else
  build_one "regions/${TARGET_REGION}.osm.pbf" "${TARGET_REGION}.pmtiles"
fi

echo "[03_build_pmtiles] PMTiles generation complete."
