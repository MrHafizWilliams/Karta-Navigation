FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY pyproject.toml alembic.ini /app/
COPY alembic /app/alembic
COPY src /app/src
COPY tests /app/tests

RUN pip install --upgrade pip && pip install ".[dev]"

EXPOSE 8000

CMD ["uvicorn", "karta_api.main:app", "--host", "0.0.0.0", "--port", "8000"]
