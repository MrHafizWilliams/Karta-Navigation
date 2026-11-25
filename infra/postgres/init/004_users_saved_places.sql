-- ============================================================================
-- Karta Navigation — User Accounts, Sessions & Saved Places / Landmarks (PostGIS)
-- Idempotent migration applied automatically on karta-api startup.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS users;

CREATE TABLE IF NOT EXISTS users.accounts (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT NOT NULL,
    display_name  TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    password_salt TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_accounts_email_lower
    ON users.accounts (LOWER(email));

CREATE TABLE IF NOT EXISTS users.sessions (
    token_hash TEXT PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users.accounts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_sessions_user_id
    ON users.sessions (user_id);

CREATE TABLE IF NOT EXISTS users.saved_places (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES users.accounts(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    address_subtitle TEXT,
    category         TEXT NOT NULL DEFAULT 'favorite',
    notes            TEXT,
    country_code     CHAR(2),
    poi_id           BIGINT,
    geom             GEOMETRY(Point, 4326) NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_saved_places_user_id
    ON users.saved_places (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_users_saved_places_geom
    ON users.saved_places USING GIST (geom);
