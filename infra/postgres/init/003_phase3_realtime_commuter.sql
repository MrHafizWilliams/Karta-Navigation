-- ============================================================================
-- Karta Navigation Platform — Phase 3 Real-Time Crowdsourcing, Fuel Prices,
-- Smart Commuter (Calendar TTL & Privacy-First Carpool), and Custom Voice Packs
-- Target: PostgreSQL 16 + PostGIS 3.4 (EPSG:4326 / WGS 84)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS community;
CREATE SCHEMA IF NOT EXISTS fuel;
CREATE SCHEMA IF NOT EXISTS commuter;
CREATE SCHEMA IF NOT EXISTS voice;

-- ============================================================================
-- 1. COMMUNITY SCHEMA: Live Crowdsourced Hazards & Community Verification
-- ============================================================================
CREATE TABLE IF NOT EXISTS community.hazards (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category                TEXT NOT NULL CHECK (category IN (
                                'police',
                                'accident',
                                'pothole',
                                'hidden_vehicle',
                                'road_debris',
                                'road_closure'
                            )),
    subtype                 TEXT,
    severity                TEXT NOT NULL DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high')),
    status                  TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'resolved', 'expired')),
    geom                    GEOMETRY(Point, 4326) NOT NULL,
    exclusion_geom          GEOMETRY(Polygon, 4326),
    road_heading_deg        DOUBLE PRECISION,
    oneway                  SMALLINT NOT NULL DEFAULT 0,
    affects_both_directions BOOLEAN NOT NULL DEFAULT FALSE,
    osm_way_id              BIGINT,
    valhalla_edge_id        BIGINT,
    road_name               TEXT,
    road_ref                TEXT,
    country_code            CHAR(2) REFERENCES geo.countries(iso_a2),
    lane_hint               TEXT,
    description             TEXT,
    source                  TEXT NOT NULL DEFAULT 'radial' CHECK (source IN ('radial', 'voice', 'api', 'grpc')),
    reporter_hash           TEXT NOT NULL,
    confirmations           INT NOT NULL DEFAULT 1,
    denials                 INT NOT NULL DEFAULT 0,
    confidence_score        DOUBLE PRECISION NOT NULL DEFAULT 0.65,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at              TIMESTAMPTZ NOT NULL,
    resolved_at             TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_community_hazards_geom
    ON community.hazards USING GIST (geom);

CREATE INDEX IF NOT EXISTS idx_community_hazards_active_geom
    ON community.hazards USING GIST (geom)
    WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_community_hazards_active_expiry
    ON community.hazards (expires_at)
    WHERE status = 'active';

CREATE TABLE IF NOT EXISTS community.hazard_votes (
    hazard_id               UUID NOT NULL REFERENCES community.hazards(id) ON DELETE CASCADE,
    voter_hash              TEXT NOT NULL,
    vote                    TEXT NOT NULL CHECK (vote IN ('confirm', 'cleared')),
    voter_geom              GEOMETRY(Point, 4326),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (hazard_id, voter_hash)
);

-- ============================================================================
-- 2. FUEL SCHEMA: Community-Updated Petrol & Diesel Prices on Real OSM POIs
-- ============================================================================
CREATE TABLE IF NOT EXISTS fuel.station_prices (
    id                      BIGSERIAL PRIMARY KEY,
    poi_id                  BIGINT NOT NULL REFERENCES spatial.pois(id) ON DELETE CASCADE,
    country_code            CHAR(2) NOT NULL REFERENCES geo.countries(iso_a2),
    fuel_grade              TEXT NOT NULL CHECK (fuel_grade IN (
                                'RON95', 'RON97', 'DIESEL_B10', 'DIESEL_EURO5',
                                'OCTANE_92', 'OCTANE_95', 'OCTANE_98', 'DIESEL_SG',
                                'RON97_BN', 'RON92_BN', 'DIESEL_BN'
                            )),
    price_minor             INT NOT NULL CHECK (price_minor > 0),
    currency_code           CHAR(3) NOT NULL,
    is_subsidized           BOOLEAN NOT NULL DEFAULT FALSE,
    source                  TEXT NOT NULL DEFAULT 'official_baseline'
                                CHECK (source IN ('official_baseline', 'community_verified')),
    confirmations           INT NOT NULL DEFAULT 1,
    reported_by_hash        TEXT,
    reported_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (poi_id, fuel_grade)
);

CREATE INDEX IF NOT EXISTS idx_fuel_prices_poi
    ON fuel.station_prices (poi_id);

CREATE INDEX IF NOT EXISTS idx_fuel_prices_country_grade
    ON fuel.station_prices (country_code, fuel_grade, price_minor);

CREATE TABLE IF NOT EXISTS fuel.price_history (
    id                      BIGSERIAL PRIMARY KEY,
    poi_id                  BIGINT NOT NULL REFERENCES spatial.pois(id) ON DELETE CASCADE,
    country_code            CHAR(2) NOT NULL,
    fuel_grade              TEXT NOT NULL,
    price_minor             INT NOT NULL,
    currency_code           CHAR(3) NOT NULL,
    reported_by_hash        TEXT NOT NULL,
    reported_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 3. COMMUTER SCHEMA: Smart Calendar Sync (ICS/Facebook/Google) & Privacy Carpool
-- ============================================================================
CREATE TABLE IF NOT EXISTS commuter.calendar_feeds (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_token              TEXT NOT NULL,
    provider                TEXT NOT NULL CHECK (provider IN ('ics_url', 'facebook_ics', 'google_oauth', 'manual')),
    label                   TEXT NOT NULL,
    feed_url                TEXT,
    last_synced_at          TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_commuter_feeds_user
    ON commuter.calendar_feeds (user_token);

CREATE TABLE IF NOT EXISTS commuter.calendar_events (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_token              TEXT NOT NULL,
    feed_id                 UUID REFERENCES commuter.calendar_feeds(id) ON DELETE CASCADE,
    external_uid            TEXT,
    title                   TEXT NOT NULL,
    provider                TEXT NOT NULL DEFAULT 'manual',
    location_text           TEXT,
    dest_geom               GEOMETRY(Point, 4326),
    country_code            CHAR(2),
    starts_at               TIMESTAMPTZ NOT NULL,
    ends_at                 TIMESTAMPTZ,
    parking_buffer_sec      INT NOT NULL DEFAULT 600,
    last_ttl_eval_json      JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_token, external_uid)
);

CREATE INDEX IF NOT EXISTS idx_commuter_events_user_start
    ON commuter.calendar_events (user_token, starts_at);

-- Privacy-first carpool offers: stores ONLY 500m-fuzzed pickup/dropoff zones & public meeting landmarks
CREATE TABLE IF NOT EXISTS commuter.carpool_offers (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_token            TEXT NOT NULL,
    driver_alias            TEXT NOT NULL,
    verified_badge          TEXT,
    country_code            CHAR(2) NOT NULL DEFAULT 'MY',
    origin_zone_geom        GEOMETRY(Point, 4326) NOT NULL,
    origin_landmark_name    TEXT NOT NULL,
    dest_zone_geom          GEOMETRY(Point, 4326) NOT NULL,
    dest_landmark_name      TEXT NOT NULL,
    privacy_radius_m        INT NOT NULL DEFAULT 500,
    route_geom              GEOMETRY(LineString, 4326) NOT NULL,
    route_polyline6         TEXT NOT NULL,
    route_distance_km       DOUBLE PRECISION NOT NULL DEFAULT 0,
    departure_at            TIMESTAMPTZ NOT NULL,
    flexibility_minutes     INT NOT NULL DEFAULT 20,
    seats_total             SMALLINT NOT NULL CHECK (seats_total BETWEEN 1 AND 6),
    seats_available         SMALLINT NOT NULL CHECK (seats_available >= 0),
    estimated_split_minor   INT NOT NULL DEFAULT 0,
    currency_code           CHAR(3) NOT NULL DEFAULT 'MYR',
    notes                   TEXT,
    status                  TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'full', 'cancelled', 'expired')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at              TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_carpool_offers_route_geom
    ON commuter.carpool_offers USING GIST (route_geom)
    WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_carpool_offers_departure
    ON commuter.carpool_offers (departure_at)
    WHERE status = 'active';

CREATE TABLE IF NOT EXISTS commuter.carpool_matches (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id                UUID NOT NULL REFERENCES commuter.carpool_offers(id) ON DELETE CASCADE,
    rider_token             TEXT NOT NULL,
    rider_alias             TEXT NOT NULL,
    pickup_zone_geom        GEOMETRY(Point, 4326) NOT NULL,
    pickup_landmark_name    TEXT NOT NULL,
    dropoff_zone_geom       GEOMETRY(Point, 4326) NOT NULL,
    dropoff_landmark_name   TEXT NOT NULL,
    overlap_pct             DOUBLE PRECISION NOT NULL DEFAULT 0,
    detour_meters           DOUBLE PRECISION NOT NULL DEFAULT 0,
    split_cost_minor        INT NOT NULL DEFAULT 0,
    currency_code           CHAR(3) NOT NULL DEFAULT 'MYR',
    status                  TEXT NOT NULL DEFAULT 'requested'
                                CHECK (status IN ('requested', 'accepted', 'declined', 'cancelled')),
    rendezvous_note         TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (offer_id, rider_token)
);

-- ============================================================================
-- 4. VOICE SCHEMA: Custom User Navigation Voice Packs & Recorded Audio Clips
-- ============================================================================
CREATE TABLE IF NOT EXISTS voice.custom_packs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_token             TEXT NOT NULL,
    name                    TEXT NOT NULL,
    locale                  TEXT NOT NULL DEFAULT 'en-MY',
    base_tts_voice          TEXT NOT NULL DEFAULT 'karta_studio_en',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_voice_custom_packs_owner
    ON voice.custom_packs (owner_token);

CREATE TABLE IF NOT EXISTS voice.custom_clips (
    pack_id                 UUID NOT NULL REFERENCES voice.custom_packs(id) ON DELETE CASCADE,
    cue_key                 TEXT NOT NULL CHECK (cue_key IN (
                                'turn_left', 'turn_right', 'keep_left', 'keep_right',
                                'straight', 'roundabout', 'arrived', 'toll_ahead',
                                'speed_camera', 'hazard_police', 'hazard_accident', 'rerouting'
                            )),
    mime_type               TEXT NOT NULL DEFAULT 'audio/webm',
    duration_ms             INT NOT NULL DEFAULT 0,
    audio_base64            TEXT NOT NULL,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (pack_id, cue_key)
);
