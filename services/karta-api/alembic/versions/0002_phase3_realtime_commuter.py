"""Phase 3 schemas: real-time community hazards, fuel prices, smart commuter & custom voice packs

Revision ID: 0002_phase3_realtime_commuter
Revises: 0001_initial_schema
Create Date: 2026-11-22
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "0002_phase3_realtime_commuter"
down_revision: Union[str, None] = "0001_initial_schema"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    for parent in Path(__file__).resolve().parents:
        sql_path = parent / "infra" / "postgres" / "init" / "003_phase3_realtime_commuter.sql"
        if sql_path.exists():
            op.execute(sql_path.read_text(encoding="utf-8"))
            return
    raise FileNotFoundError("Could not locate 003_phase3_realtime_commuter.sql")


def downgrade() -> None:
    op.execute("DROP SCHEMA IF EXISTS voice CASCADE;")
    op.execute("DROP SCHEMA IF EXISTS commuter CASCADE;")
    op.execute("DROP SCHEMA IF EXISTS fuel CASCADE;")
    op.execute("DROP SCHEMA IF EXISTS community CASCADE;")
