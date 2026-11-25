"""Baseline Phase 1 PostGIS schema marker (applied via infra/postgres/init/001_schema.sql)

Revision ID: 0001_initial_schema
Revises:
Create Date: 2026-11-21
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "0001_initial_schema"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Idempotently ensures baseline PostGIS schemas exist when migrating an empty DB outside Docker init.
    for parent in Path(__file__).resolve().parents:
        init_sql = parent / "infra" / "postgres" / "init" / "001_schema.sql"
        seed_sql = parent / "infra" / "postgres" / "init" / "002_seed_countries.sql"
        if init_sql.exists():
            op.execute(init_sql.read_text(encoding="utf-8"))
            if seed_sql.exists():
                op.execute(seed_sql.read_text(encoding="utf-8"))
            return


def downgrade() -> None:
    op.execute("DROP SCHEMA IF EXISTS transit CASCADE;")
    op.execute("DROP SCHEMA IF EXISTS tolls CASCADE;")
    op.execute("DROP SCHEMA IF EXISTS spatial CASCADE;")
    op.execute("DROP SCHEMA IF EXISTS geo CASCADE;")
