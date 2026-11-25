from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID

import asyncpg

from karta_api.models.common import Coordinate
from karta_api.models.users import (
    AuthSessionResponse,
    SavedPlaceCreateRequest,
    SavedPlaceItem,
    UserProfile,
)

_PBKDF2_ITERATIONS = 260_000
_SESSION_TTL_DAYS = 30


def _hash_password(password: str, salt_hex: str) -> str:
    dk = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        bytes.fromhex(salt_hex),
        _PBKDF2_ITERATIONS,
    )
    return dk.hex()


def _hash_token(raw_token: str) -> str:
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


class UserRepository:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool

    async def register_user(
        self,
        *,
        email: str,
        display_name: str,
        password: str,
    ) -> AuthSessionResponse:
        norm_email = email.strip().lower()
        salt_hex = secrets.token_hex(16)
        pw_hash = _hash_password(password, salt_hex)

        async with self._pool.acquire() as conn:
            existing = await conn.fetchrow(
                "SELECT id FROM users.accounts WHERE LOWER(email) = $1",
                norm_email,
            )
            if existing is not None:
                raise ValueError("An account with this email already exists.")

            row = await conn.fetchrow(
                """
                INSERT INTO users.accounts (email, display_name, password_hash, password_salt, last_login_at)
                VALUES ($1, $2, $3, $4, NOW())
                RETURNING id::text AS id, email, display_name, created_at
                """,
                norm_email,
                display_name.strip(),
                pw_hash,
                salt_hex,
            )
            assert row is not None
            raw_token, expires_at = await self._create_session(conn, row["id"])

        return AuthSessionResponse(
            access_token=raw_token,
            expires_at=expires_at,
            user=UserProfile(
                id=row["id"],
                email=row["email"],
                display_name=row["display_name"],
                saved_places_count=0,
                created_at=row["created_at"],
            ),
        )

    async def authenticate_user(
        self,
        *,
        email: str,
        password: str,
    ) -> AuthSessionResponse | None:
        norm_email = email.strip().lower()
        async with self._pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT id::text AS id, email, display_name, password_hash, password_salt, created_at,
                       (SELECT COUNT(*) FROM users.saved_places sp WHERE sp.user_id = users.accounts.id) AS saved_count
                FROM users.accounts
                WHERE LOWER(email) = $1
                """,
                norm_email,
            )
            if row is None:
                return None

            candidate_hash = _hash_password(password, row["password_salt"])
            if not hmac.compare_digest(candidate_hash, row["password_hash"]):
                return None

            await conn.execute(
                "UPDATE users.accounts SET last_login_at = NOW() WHERE id = $1::uuid",
                row["id"],
            )
            raw_token, expires_at = await self._create_session(conn, row["id"])

        return AuthSessionResponse(
            access_token=raw_token,
            expires_at=expires_at,
            user=UserProfile(
                id=row["id"],
                email=row["email"],
                display_name=row["display_name"],
                saved_places_count=int(row["saved_count"] or 0),
                created_at=row["created_at"],
            ),
        )

    async def get_user_by_token(self, raw_token: str) -> UserProfile | None:
        token_hash = _hash_token(raw_token)
        async with self._pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT a.id::text AS id, a.email, a.display_name, a.created_at,
                       (SELECT COUNT(*) FROM users.saved_places sp WHERE sp.user_id = a.id) AS saved_count
                FROM users.sessions s
                JOIN users.accounts a ON a.id = s.user_id
                WHERE s.token_hash = $1 AND s.expires_at > NOW()
                """,
                token_hash,
            )
            if row is None:
                return None
            return UserProfile(
                id=row["id"],
                email=row["email"],
                display_name=row["display_name"],
                saved_places_count=int(row["saved_count"] or 0),
                created_at=row["created_at"],
            )

    async def revoke_session(self, raw_token: str) -> None:
        token_hash = _hash_token(raw_token)
        async with self._pool.acquire() as conn:
            await conn.execute(
                "DELETE FROM users.sessions WHERE token_hash = $1",
                token_hash,
            )

    async def list_saved_places(self, user_id: str) -> list[SavedPlaceItem]:
        async with self._pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT id::text AS id,
                       name,
                       category,
                       address_subtitle,
                       notes,
                       TRIM(country_code) AS country_code,
                       poi_id,
                       ST_Y(geom) AS lat,
                       ST_X(geom) AS lon,
                       created_at
                FROM users.saved_places
                WHERE user_id = $1::uuid
                ORDER BY
                    CASE category
                        WHEN 'home' THEN 0
                        WHEN 'work' THEN 1
                        WHEN 'landmark' THEN 2
                        WHEN 'favorite' THEN 3
                        ELSE 4
                    END,
                    created_at DESC
                """,
                user_id,
            )
        return [
            SavedPlaceItem(
                id=r["id"],
                name=r["name"],
                category=r["category"],
                address_subtitle=r["address_subtitle"],
                notes=r["notes"],
                country_code=r["country_code"] or None,
                poi_id=r["poi_id"],
                coordinate=Coordinate(lat=float(r["lat"]), lon=float(r["lon"])),
                created_at=r["created_at"],
            )
            for r in rows
        ]

    async def create_saved_place(
        self,
        *,
        user_id: str,
        req: SavedPlaceCreateRequest,
    ) -> SavedPlaceItem:
        async with self._pool.acquire() as conn:
            # Home & Work behave as single pinned slots (upsert by replacing prior Home/Work)
            if req.category in ("home", "work"):
                await conn.execute(
                    "DELETE FROM users.saved_places WHERE user_id = $1::uuid AND category = $2",
                    user_id,
                    req.category,
                )

            row = await conn.fetchrow(
                """
                INSERT INTO users.saved_places (
                    user_id, name, category, address_subtitle, notes, country_code, poi_id, geom
                )
                VALUES (
                    $1::uuid, $2, $3, $4, $5, $6, $7,
                    ST_SetSRID(ST_MakePoint($8, $9), 4326)
                )
                RETURNING id::text AS id,
                          name,
                          category,
                          address_subtitle,
                          notes,
                          TRIM(country_code) AS country_code,
                          poi_id,
                          ST_Y(geom) AS lat,
                          ST_X(geom) AS lon,
                          created_at
                """,
                user_id,
                req.name.strip(),
                req.category,
                req.address_subtitle,
                req.notes,
                req.country_code.upper() if req.country_code else None,
                req.poi_id,
                req.coordinate.lon,
                req.coordinate.lat,
            )
            assert row is not None
        return SavedPlaceItem(
            id=row["id"],
            name=row["name"],
            category=row["category"],
            address_subtitle=row["address_subtitle"],
            notes=row["notes"],
            country_code=row["country_code"] or None,
            poi_id=row["poi_id"],
            coordinate=Coordinate(lat=float(row["lat"]), lon=float(row["lon"])),
            created_at=row["created_at"],
        )

    async def delete_saved_place(self, *, user_id: str, place_id: str) -> bool:
        try:
            UUID(place_id)
        except ValueError:
            return False
        async with self._pool.acquire() as conn:
            status = await conn.execute(
                "DELETE FROM users.saved_places WHERE id = $1::uuid AND user_id = $2::uuid",
                place_id,
                user_id,
            )
        return status.endswith("1")

    async def _create_session(
        self,
        conn: asyncpg.Connection,
        user_id: str,
    ) -> tuple[str, datetime]:
        raw_token = f"krt_{secrets.token_urlsafe(32)}"
        token_hash = _hash_token(raw_token)
        expires_at = datetime.now(tz=timezone.utc) + timedelta(days=_SESSION_TTL_DAYS)
        await conn.execute(
            """
            INSERT INTO users.sessions (token_hash, user_id, expires_at)
            VALUES ($1, $2::uuid, $3)
            """,
            token_hash,
            user_id,
            expires_at,
        )
        return raw_token, expires_at
