-- ============================================================================
-- Karta Navigation Platform — Phase 1 Spatial & Regional Toll Database Schema
-- Target: PostgreSQL 16 + PostGIS 3.4 (EPSG:4326 / WGS 84)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA IF NOT EXISTS geo;
CREATE SCHEMA IF NOT EXISTS spatial;
CREATE SCHEMA IF NOT EXISTS tolls;
CREATE SCHEMA IF NOT EXISTS transit;

-- ============================================================================
-- 1. GEO SCHEMA: Countries, Currency Rules & Downloadable Offline Regions
-- ============================================================================
CREATE TABLE IF NOT EXISTS geo.countries (
    iso_a2              CHAR(2) PRIMARY KEY,            -- 'MY', 'SG', 'BN'
    iso_a3              CHAR(3) NOT NULL UNIQUE,        -- 'MYS', 'SGP', 'BRN'
    name                TEXT NOT NULL,
    currency_code       CHAR(3) NOT NULL,               -- 'MYR', 'SGD', 'BND'
    currency_symbol     TEXT NOT NULL,                  -- 'RM', '$', 'B$'
    symbol_prefix_space BOOLEAN NOT NULL DEFAULT FALSE, -- TRUE -> 'RM 12.50', FALSE -> '$2.00', 'B$3.00'
    decimal_places      SMALLINT NOT NULL DEFAULT 2,
    driving_side        TEXT NOT NULL CHECK (driving_side IN ('left', 'right')),
    speed_unit          TEXT NOT NULL DEFAULT 'kmh' CHECK (speed_unit IN ('kmh', 'mph')),
    timezone_iana       TEXT NOT NULL,                  -- 'Asia/Kuala_Lumpur', 'Asia/Singapore', 'Asia/Brunei'
    geom                GEOMETRY(MultiPolygon, 4326) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_geo_countries_geom
    ON geo.countries USING GIST (geom);

-- Raw OSM admin_level=2 staging polygons extracted by osm2pgsql
CREATE TABLE IF NOT EXISTS geo.osm_admin_boundaries (
    osm_id              BIGINT PRIMARY KEY,
    iso_a2              CHAR(2),
    name                TEXT,
    admin_level         SMALLINT,
    geom                GEOMETRY(MultiPolygon, 4326) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_geo_osm_admin_geom
    ON geo.osm_admin_boundaries USING GIST (geom);

CREATE TABLE IF NOT EXISTS geo.offline_regions (
    region_id           TEXT PRIMARY KEY,               -- e.g. 'my-peninsular-central', 'sg', 'bn'
    display_name        TEXT NOT NULL,
    country_codes       CHAR(2)[] NOT NULL,
    bbox_geom           GEOMETRY(Polygon, 4326) NOT NULL,
    data_version        TEXT NOT NULL,                  -- e.g. '2026-11-21'
    pmtiles_url         TEXT NOT NULL,
    pmtiles_sha256      CHAR(64) NOT NULL,
    pmtiles_bytes       BIGINT NOT NULL DEFAULT 0,
    valhalla_tar_url    TEXT NOT NULL,
    valhalla_tar_sha256 CHAR(64) NOT NULL,
    valhalla_tar_bytes  BIGINT NOT NULL DEFAULT 0,
    tolls_sqlite_url    TEXT,
    tolls_sqlite_sha256 CHAR(64),
    tolls_sqlite_bytes  BIGINT DEFAULT 0,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_geo_offline_regions_bbox
    ON geo.offline_regions USING GIST (bbox_geom);

-- ============================================================================
-- 2. SPATIAL SCHEMA: POIs, Road Speed Limits, Lane Guidance & Speed Zones
-- ============================================================================
CREATE TABLE IF NOT EXISTS spatial.pois (
    id                  BIGSERIAL PRIMARY KEY,
    osm_type            CHAR(1) NOT NULL CHECK (osm_type IN ('N', 'W', 'R')),
    osm_id              BIGINT NOT NULL,
    name                TEXT NOT NULL,
    name_localized      JSONB NOT NULL DEFAULT '{}'::JSONB, -- {"ms": "...", "en": "...", "zh": "..."}
    category            TEXT NOT NULL,                      -- 'fuel', 'ev_charging', 'rest_area', 'parking', 'food', 'hospital', 'transit', 'mosque', 'bank', 'shopping'
    subcategory         TEXT,
    brand               TEXT,                               -- 'Petronas', 'Shell', 'Gentari', 'ChargEV', 'SP Mobility'
    country_code        CHAR(2) REFERENCES geo.countries(iso_a2),
    address             JSONB NOT NULL DEFAULT '{}'::JSONB,
    opening_hours       TEXT,
    ev_metadata         JSONB,                              -- connector types, max_kw, socket counts
    tags                JSONB NOT NULL DEFAULT '{}'::JSONB,
    geom                GEOMETRY(Point, 4326) NOT NULL,
    search_tsv          TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('simple', coalesce(name, '') || ' ' || coalesce(brand, '') || ' ' || coalesce(category, '') || ' ' || coalesce(subcategory, ''))
    ) STORED,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (osm_type, osm_id)
);

CREATE INDEX IF NOT EXISTS idx_spatial_pois_geom
    ON spatial.pois USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_spatial_pois_tsv
    ON spatial.pois USING GIN (search_tsv);
CREATE INDEX IF NOT EXISTS idx_spatial_pois_name_trgm
    ON spatial.pois USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_spatial_pois_cat_cc
    ON spatial.pois (country_code, category);

CREATE TABLE IF NOT EXISTS spatial.road_segments (
    way_id              BIGINT NOT NULL,
    segment_seq         INT NOT NULL DEFAULT 0,
    name                TEXT,
    ref                 TEXT,                               -- 'E1', 'E11', 'CTE', 'AH2'
    highway_class       TEXT NOT NULL,
    country_code        CHAR(2) REFERENCES geo.countries(iso_a2),
    oneway              SMALLINT NOT NULL DEFAULT 0,        -- 1=forward, -1=reverse, 0=bidirectional
    maxspeed_fwd_kmh    SMALLINT,
    maxspeed_bwd_kmh    SMALLINT,
    maxspeed_source     TEXT NOT NULL DEFAULT 'osm',        -- 'osm', 'default_class', 'variable'
    lanes_total         SMALLINT,
    lanes_fwd           SMALLINT,
    lanes_bwd           SMALLINT,
    turn_lanes_fwd      TEXT[],                             -- ARRAY['left','through','through;right']
    turn_lanes_bwd      TEXT[],
    hgv_prohibited      BOOLEAN NOT NULL DEFAULT FALSE,
    is_toll             BOOLEAN NOT NULL DEFAULT FALSE,
    is_bridge           BOOLEAN NOT NULL DEFAULT FALSE,
    is_tunnel           BOOLEAN NOT NULL DEFAULT FALSE,
    surface             TEXT,
    geom                GEOMETRY(LineString, 4326) NOT NULL,
    PRIMARY KEY (way_id, segment_seq)
);

CREATE INDEX IF NOT EXISTS idx_road_segments_geom
    ON spatial.road_segments USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_road_segments_ref
    ON spatial.road_segments (ref) WHERE ref IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_road_segments_toll
    ON spatial.road_segments USING GIST (geom) WHERE is_toll = TRUE;

CREATE TABLE IF NOT EXISTS spatial.speed_zones (
    id                  BIGSERIAL PRIMARY KEY,
    osm_id              BIGINT UNIQUE,
    zone_type           TEXT NOT NULL CHECK (zone_type IN ('awas_camera', 'tp_speed_camera', 'red_light_camera', 'school_zone', 'variable_limit')),
    country_code        CHAR(2) REFERENCES geo.countries(iso_a2),
    road_name           TEXT,
    limit_kmh           SMALLINT NOT NULL,
    heading_deg         SMALLINT CHECK (heading_deg BETWEEN 0 AND 359),
    heading_tolerance   SMALLINT NOT NULL DEFAULT 45,
    active_schedule     JSONB,
    geom                GEOMETRY(Point, 4326) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_speed_zones_geom
    ON spatial.speed_zones USING GIST (geom);

-- ============================================================================
-- 3. TOLLS SCHEMA: MY (PLUS / Open / RFID / SmartTAG / ANPR), SG (ERP), BN
-- ============================================================================
DO $$ BEGIN
    CREATE TYPE tolls.system_type AS ENUM (
        'closed_matrix',      -- Distance-based entry->exit pair (PLUS E1/E2, ELITE E6, LPT E8, WCE E32)
        'open_barrier',       -- Flat fee per plaza (LDP E11, SPRINT E23, DUKE E33, KESAS E5, SUKE, SPE, Penang Bridge)
        'time_varying_erp',   -- Singapore ERP gantries (time-of-day + day-of-week dynamic tariff)
        'border_checkpoint'   -- MY-SG Causeway / Second Link CIQ + VEP Road Charge, MY-BN borders
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE tolls.gantry_role AS ENUM (
        'entry_exit',
        'entry_only',
        'exit_only',
        'open_plaza',
        'erp_gantry',
        'border_crossing'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE tolls.payment_method AS ENUM (
        'TNG_CARD',
        'SMARTTAG',
        'RFID',
        'OPEN_PAYMENT_CARD',
        'ANPR_JUSTGO',
        'ERP_IU',
        'ERP2_OBU',
        'CASH',
        'BRUNEI_TOLL_CARD'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Staging table for raw OSM barrier=toll_booth & highway=toll_gantry nodes
CREATE TABLE IF NOT EXISTS tolls.osm_toll_nodes (
    osm_id              BIGINT PRIMARY KEY,
    name                TEXT,
    operator_name       TEXT,
    highway_ref         TEXT,
    barrier_type        TEXT,
    tags                JSONB NOT NULL DEFAULT '{}'::JSONB,
    geom                GEOMETRY(Point, 4326) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_tolls_osm_nodes_geom
    ON tolls.osm_toll_nodes USING GIST (geom);

CREATE TABLE IF NOT EXISTS tolls.operators (
    operator_code       TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    country_code        CHAR(2) NOT NULL REFERENCES geo.countries(iso_a2),
    currency_code       CHAR(3) NOT NULL,
    website_url         TEXT
);

CREATE TABLE IF NOT EXISTS tolls.corridors (
    corridor_id         TEXT PRIMARY KEY,
    operator_code       TEXT NOT NULL REFERENCES tolls.operators(operator_code),
    highway_ref         TEXT,
    name                TEXT NOT NULL,
    system_type         tolls.system_type NOT NULL,
    country_code        CHAR(2) NOT NULL REFERENCES geo.countries(iso_a2),
    notes               TEXT
);

CREATE TABLE IF NOT EXISTS tolls.vehicle_classes (
    country_code        CHAR(2) NOT NULL REFERENCES geo.countries(iso_a2),
    class_code          TEXT NOT NULL,
    canonical_profile   TEXT NOT NULL CHECK (canonical_profile IN ('car', 'motorcycle', 'taxi', 'van_2axle', 'truck_3axle', 'bus')),
    label               TEXT NOT NULL,
    description         TEXT,
    PRIMARY KEY (country_code, class_code)
);

CREATE TABLE IF NOT EXISTS tolls.gantries (
    gantry_id           TEXT PRIMARY KEY,
    corridor_id         TEXT NOT NULL REFERENCES tolls.corridors(corridor_id),
    external_code       TEXT,
    osm_node_id         BIGINT,
    name                TEXT NOT NULL,
    role                tolls.gantry_role NOT NULL,
    direction_code      TEXT,                               -- 'NB','SB','EB','WB','INBOUND','OUTBOUND','BOTH'
    direction_bearing   SMALLINT CHECK (direction_bearing BETWEEN 0 AND 359),
    bearing_tolerance   SMALLINT NOT NULL DEFAULT 55,
    accepted_payments   tolls.payment_method[] NOT NULL,
    lane_layout         JSONB NOT NULL DEFAULT '[]'::JSONB,
    geom                GEOMETRY(Point, 4326) NOT NULL,
    detection_line      GEOMETRY(LineString, 4326) NOT NULL,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tolls_gantries_geom
    ON tolls.gantries USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_tolls_gantries_tripwire
    ON tolls.gantries USING GIST (detection_line) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_tolls_gantries_corridor
    ON tolls.gantries (corridor_id);

CREATE TABLE IF NOT EXISTS tolls.open_rates (
    id                    BIGSERIAL PRIMARY KEY,
    gantry_id             TEXT NOT NULL REFERENCES tolls.gantries(gantry_id) ON DELETE CASCADE,
    country_code          CHAR(2) NOT NULL,
    vehicle_class         TEXT NOT NULL,
    payment_method        tolls.payment_method,
    foreign_vehicle_only  BOOLEAN NOT NULL DEFAULT FALSE,
    amount_minor          INT NOT NULL CHECK (amount_minor >= 0),
    currency_code         CHAR(3) NOT NULL,
    effective_from        DATE NOT NULL,
    effective_to          DATE,
    FOREIGN KEY (country_code, vehicle_class) REFERENCES tolls.vehicle_classes(country_code, class_code)
);

CREATE INDEX IF NOT EXISTS idx_tolls_open_lookup
    ON tolls.open_rates (gantry_id, vehicle_class, effective_from);

CREATE TABLE IF NOT EXISTS tolls.closed_matrix_rates (
    id                    BIGSERIAL PRIMARY KEY,
    corridor_id           TEXT NOT NULL REFERENCES tolls.corridors(corridor_id) ON DELETE CASCADE,
    entry_gantry_id       TEXT NOT NULL REFERENCES tolls.gantries(gantry_id) ON DELETE CASCADE,
    exit_gantry_id        TEXT NOT NULL REFERENCES tolls.gantries(gantry_id) ON DELETE CASCADE,
    country_code          CHAR(2) NOT NULL,
    vehicle_class         TEXT NOT NULL,
    distance_km           NUMERIC(6,2),
    amount_minor          INT NOT NULL CHECK (amount_minor >= 0),
    currency_code         CHAR(3) NOT NULL,
    effective_from        DATE NOT NULL,
    effective_to          DATE,
    FOREIGN KEY (country_code, vehicle_class) REFERENCES tolls.vehicle_classes(country_code, class_code),
    UNIQUE (corridor_id, entry_gantry_id, exit_gantry_id, vehicle_class, effective_from)
);

CREATE INDEX IF NOT EXISTS idx_tolls_closed_lookup
    ON tolls.closed_matrix_rates (corridor_id, entry_gantry_id, exit_gantry_id, vehicle_class);

CREATE TABLE IF NOT EXISTS tolls.erp_schedules (
    id                    BIGSERIAL PRIMARY KEY,
    gantry_id             TEXT NOT NULL REFERENCES tolls.gantries(gantry_id) ON DELETE CASCADE,
    country_code          CHAR(2) NOT NULL,
    vehicle_class         TEXT NOT NULL,
    day_type              TEXT NOT NULL CHECK (day_type IN ('WEEKDAY', 'SATURDAY', 'SUNDAY_PH')),
    start_time            TIME NOT NULL,
    end_time              TIME NOT NULL,
    amount_minor          INT NOT NULL CHECK (amount_minor >= 0),
    currency_code         CHAR(3) NOT NULL DEFAULT 'SGD',
    effective_from        DATE NOT NULL,
    effective_to          DATE,
    source_etag           TEXT,
    FOREIGN KEY (country_code, vehicle_class) REFERENCES tolls.vehicle_classes(country_code, class_code),
    CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_tolls_erp_lookup
    ON tolls.erp_schedules (gantry_id, vehicle_class, day_type, start_time, end_time);

CREATE TABLE IF NOT EXISTS tolls.public_holidays (
    country_code          CHAR(2) NOT NULL REFERENCES geo.countries(iso_a2),
    holiday_date          DATE NOT NULL,
    name                  TEXT NOT NULL,
    toll_override_rule    TEXT NOT NULL DEFAULT 'SUNDAY_PH', -- 'SUNDAY_PH', 'FREE_TOLL', 'DISCOUNT_50'
    PRIMARY KEY (country_code, holiday_date)
);

-- ============================================================================
-- 4. TRANSIT SCHEMA: GTFS Feed Registry & Fast Stop Discovery
-- ============================================================================
CREATE TABLE IF NOT EXISTS transit.feeds (
    feed_id               TEXT PRIMARY KEY,
    agency_name           TEXT NOT NULL,
    country_code          CHAR(2) NOT NULL REFERENCES geo.countries(iso_a2),
    source_url            TEXT NOT NULL,
    feed_start_date       DATE,
    feed_end_date         DATE,
    checksum_sha256       CHAR(64),
    ingested_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transit.stops (
    feed_id               TEXT NOT NULL REFERENCES transit.feeds(feed_id) ON DELETE CASCADE,
    stop_id               TEXT NOT NULL,
    stop_code             TEXT,
    stop_name             TEXT NOT NULL,
    route_types           SMALLINT[] NOT NULL DEFAULT '{}',
    geom                  GEOMETRY(Point, 4326) NOT NULL,
    PRIMARY KEY (feed_id, stop_id)
);

CREATE INDEX IF NOT EXISTS idx_transit_stops_geom
    ON transit.stops USING GIST (geom);
