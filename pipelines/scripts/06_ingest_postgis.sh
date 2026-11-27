#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Stage 06: Ingest OpenStreetMap Data into PostGIS (`osm2pgsql` Flex + Atomic Merge)
# Populates spatial.pois, spatial.road_segments (speed limits + turn:lanes),
# spatial.speed_zones, tolls.osm_toll_nodes, and upgrades geo.countries polygons.
# Usage: 06_ingest_postgis.sh [--region all|sg|bn|my-peninsular-central|...]
# ==============================================================================

TARGET_REGION="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) TARGET_REGION="$2"; shift 2 ;;
    *) echo "[06_ingest_postgis] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

OSM_FILENAME="${OSM_PBF_FILENAME:-malaysia-singapore-brunei-latest.osm.pbf}"
if [[ "${TARGET_REGION}" == "all" ]]; then
  PBF_PATH="/data/raw/osm/${OSM_FILENAME}"
else
  PBF_PATH="/data/raw/osm/regions/${TARGET_REGION}.osm.pbf"
fi

if [[ ! -f "${PBF_PATH}" ]]; then
  echo "[06_ingest_postgis] ERROR: OSM PBF not found at ${PBF_PATH}" >&2
  exit 1
fi

echo "[06_ingest_postgis] Preparing osm_stage schema..."
psql -v ON_ERROR_STOP=1 -c "CREATE SCHEMA IF NOT EXISTS osm_stage;"

echo "[06_ingest_postgis] Running osm2pgsql Flex ingestion from ${PBF_PATH}..."
osm2pgsql \
  --create \
  --slim \
  --drop \
  --output=flex \
  --style=/pipelines/osm2pgsql/karta_flex.lua \
  --cache=1024 \
  --number-processes=4 \
  "${PBF_PATH}"

echo "[06_ingest_postgis] Merging osm_stage into production PostGIS tables..."
psql -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

-- 1. Upgrade geo.countries with exact OSM admin_level=2 MultiPolygons if extracted
INSERT INTO geo.osm_admin_boundaries (osm_id, iso_a2, name, admin_level, geom)
SELECT osm_id, iso_a2, name, admin_level, ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))
FROM osm_stage.osm_admin_boundaries
WHERE iso_a2 IN ('MY', 'SG', 'BN', 'ID', 'PH', 'TH', 'LA', 'KH', 'VN', 'TL', 'MM')
ON CONFLICT (osm_id) DO UPDATE SET
    iso_a2 = EXCLUDED.iso_a2,
    name = EXCLUDED.name,
    geom = EXCLUDED.geom;

UPDATE geo.countries c
SET geom = sub.merged_geom
FROM (
    SELECT iso_a2, ST_Multi(ST_Union(geom)) AS merged_geom
    FROM geo.osm_admin_boundaries
    WHERE iso_a2 IN ('MY', 'SG', 'BN', 'ID', 'PH', 'TH', 'LA', 'KH', 'VN', 'TL', 'MM')
    GROUP BY iso_a2
) sub
WHERE c.iso_a2 = sub.iso_a2
  AND NOT ST_IsEmpty(sub.merged_geom);

-- 2. Merge POIs with country resolution
INSERT INTO spatial.pois (
    osm_type, osm_id, name, name_localized, category, subcategory,
    brand, country_code, address, opening_hours, ev_metadata, tags, geom, updated_at
)
SELECT
    s.osm_type,
    s.osm_id,
    s.name,
    COALESCE(s.name_localized, '{}'::jsonb),
    s.category,
    s.subcategory,
    s.brand,
    c.iso_a2,
    COALESCE(s.address, '{}'::jsonb),
    s.opening_hours,
    s.ev_metadata,
    COALESCE(s.tags, '{}'::jsonb),
    s.geom,
    NOW()
FROM osm_stage.pois s
LEFT JOIN geo.countries c ON ST_Contains(c.geom, s.geom)
WHERE s.name IS NOT NULL AND length(trim(s.name)) > 0
ON CONFLICT (osm_type, osm_id) DO UPDATE SET
    name = EXCLUDED.name,
    name_localized = EXCLUDED.name_localized,
    category = EXCLUDED.category,
    subcategory = EXCLUDED.subcategory,
    brand = EXCLUDED.brand,
    country_code = EXCLUDED.country_code,
    address = EXCLUDED.address,
    opening_hours = EXCLUDED.opening_hours,
    ev_metadata = EXCLUDED.ev_metadata,
    tags = EXCLUDED.tags,
    geom = EXCLUDED.geom,
    updated_at = NOW();

-- 3. Merge Road Segments (speed limits + turn:lanes parsed into TEXT[])
INSERT INTO spatial.road_segments (
    way_id, segment_seq, name, ref, highway_class, country_code,
    oneway, maxspeed_fwd_kmh, maxspeed_bwd_kmh, maxspeed_source,
    lanes_total, lanes_fwd, lanes_bwd, turn_lanes_fwd, turn_lanes_bwd,
    hgv_prohibited, is_toll, is_bridge, is_tunnel, surface, geom
)
SELECT
    r.way_id,
    0,
    r.name,
    r.ref,
    r.highway_class,
    c.iso_a2,
    COALESCE(r.oneway, 0),
    r.maxspeed_fwd_kmh,
    r.maxspeed_bwd_kmh,
    COALESCE(r.maxspeed_source, 'osm'),
    r.lanes_total,
    r.lanes_fwd,
    r.lanes_bwd,
    CASE WHEN r.turn_lanes_fwd IS NOT NULL AND r.turn_lanes_fwd <> ''
         THEN string_to_array(r.turn_lanes_fwd, '|') ELSE NULL END,
    CASE WHEN r.turn_lanes_bwd IS NOT NULL AND r.turn_lanes_bwd <> ''
         THEN string_to_array(r.turn_lanes_bwd, '|') ELSE NULL END,
    COALESCE(r.hgv_prohibited, FALSE),
    COALESCE(r.is_toll, FALSE),
    COALESCE(r.is_bridge, FALSE),
    COALESCE(r.is_tunnel, FALSE),
    r.surface,
    r.geom
FROM osm_stage.road_segments r
LEFT JOIN geo.countries c
  ON ST_Contains(c.geom, ST_LineInterpolatePoint(r.geom, 0.5))
WHERE ST_GeometryType(r.geom) = 'ST_LineString'
  AND ST_NPoints(r.geom) >= 2
ON CONFLICT (way_id, segment_seq) DO UPDATE SET
    name = EXCLUDED.name,
    ref = EXCLUDED.ref,
    highway_class = EXCLUDED.highway_class,
    country_code = EXCLUDED.country_code,
    oneway = EXCLUDED.oneway,
    maxspeed_fwd_kmh = EXCLUDED.maxspeed_fwd_kmh,
    maxspeed_bwd_kmh = EXCLUDED.maxspeed_bwd_kmh,
    maxspeed_source = EXCLUDED.maxspeed_source,
    lanes_total = EXCLUDED.lanes_total,
    lanes_fwd = EXCLUDED.lanes_fwd,
    lanes_bwd = EXCLUDED.lanes_bwd,
    turn_lanes_fwd = EXCLUDED.turn_lanes_fwd,
    turn_lanes_bwd = EXCLUDED.turn_lanes_bwd,
    hgv_prohibited = EXCLUDED.hgv_prohibited,
    is_toll = EXCLUDED.is_toll,
    is_bridge = EXCLUDED.is_bridge,
    is_tunnel = EXCLUDED.is_tunnel,
    surface = EXCLUDED.surface,
    geom = EXCLUDED.geom;

-- 4. Merge Speed Cameras / Speed Zones
INSERT INTO spatial.speed_zones (osm_id, zone_type, country_code, road_name, limit_kmh, heading_deg, geom)
SELECT
    sz.osm_id,
    CASE WHEN c.iso_a2 = 'SG' THEN 'tp_speed_camera' ELSE sz.zone_type END,
    c.iso_a2,
    sz.road_name,
    sz.limit_kmh,
    sz.heading_deg,
    sz.geom
FROM osm_stage.speed_zones sz
LEFT JOIN geo.countries c ON ST_Contains(c.geom, sz.geom)
ON CONFLICT (osm_id) DO UPDATE SET
    zone_type = EXCLUDED.zone_type,
    country_code = EXCLUDED.country_code,
    road_name = EXCLUDED.road_name,
    limit_kmh = EXCLUDED.limit_kmh,
    heading_deg = EXCLUDED.heading_deg,
    geom = EXCLUDED.geom;

-- 5. Merge Raw OSM Toll Nodes (for toll plaza cross-verification)
INSERT INTO tolls.osm_toll_nodes (osm_id, name, operator_name, highway_ref, barrier_type, tags, geom)
SELECT osm_id, name, operator_name, highway_ref, barrier_type, COALESCE(tags, '{}'::jsonb), geom
FROM osm_stage.osm_toll_nodes
ON CONFLICT (osm_id) DO UPDATE SET
    name = EXCLUDED.name,
    operator_name = EXCLUDED.operator_name,
    highway_ref = EXCLUDED.highway_ref,
    barrier_type = EXCLUDED.barrier_type,
    tags = EXCLUDED.tags,
    geom = EXCLUDED.geom;

-- Clean up staging schema
DROP SCHEMA IF EXISTS osm_stage CASCADE;

COMMIT;

ANALYZE spatial.pois;
ANALYZE spatial.road_segments;
ANALYZE spatial.speed_zones;
ANALYZE tolls.osm_toll_nodes;
ANALYZE geo.countries;
SQL

echo "[06_ingest_postgis] PostGIS ingestion complete. Summary:"
psql -c "
SELECT 'pois' AS table_name, COUNT(*) AS rows FROM spatial.pois
UNION ALL SELECT 'road_segments', COUNT(*) FROM spatial.road_segments
UNION ALL SELECT 'speed_zones', COUNT(*) FROM spatial.speed_zones
UNION ALL SELECT 'osm_toll_nodes', COUNT(*) FROM tolls.osm_toll_nodes;
"
