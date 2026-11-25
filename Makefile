SHELL := /bin/bash
COMPOSE := docker compose -f infra/docker/docker-compose.yml --env-file .env

.PHONY: help env up down logs ps db-shell pipeline pipeline-sg pipeline-central pipeline-full pmtiles valhalla-build postgis-load tolls-load redis-sync test-api

help:
	@echo "Karta Navigation Platform — Phase 1 Targets"
	@echo "  make env              Copy .env.example to .env if missing"
	@echo "  make up               Start PostGIS, Redis Geo, Valhalla, PMTiles, and Karta API"
	@echo "  make down             Stop all containers"
	@echo "  make pipeline-sg      Fast smoke pipeline for Singapore sub-region"
	@echo "  make pipeline-central Fast pipeline for Klang Valley / Central Peninsular MY"
	@echo "  make pipeline-full    Full MY + SG + BN pipeline (OSM split, PMTiles, GTFS, Valhalla, PostGIS, Tolls, Redis)"
	@echo "  make postgis-load     Ingest OSM PBF into PostGIS + load tolls + hydrate Redis Geo"
	@echo "  make tolls-load       Reload regional MY/SG/BN toll tariffs into PostGIS + SQLite + Redis"
	@echo "  make redis-sync       Atomically sync PostGIS POIs, gantries, and speed zones into Redis Geo"
	@echo "  make test-api         Run Karta Core API pytest suite inside container"

env:
	@test -f .env || cp .env.example .env

up: env
	$(COMPOSE) up -d postgres redis pmtiles valhalla karta-api

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100

ps:
	$(COMPOSE) ps

db-shell:
	$(COMPOSE) exec postgres psql -U $${POSTGRES_USER:-karta} -d $${POSTGRES_DB:-karta}

pipeline-sg: env
	$(COMPOSE) --profile pipeline run --rm pipeline bash /pipelines/scripts/run_all.sh --region sg

pipeline-central: env
	$(COMPOSE) --profile pipeline run --rm pipeline bash /pipelines/scripts/run_all.sh --region my-peninsular-central

pipeline-full: env
	$(COMPOSE) --profile pipeline run --rm pipeline bash /pipelines/scripts/run_all.sh --region all

pmtiles: env
	$(COMPOSE) --profile pipeline run --rm planetiler --download --osm-path=/data/raw/osm/malaysia-singapore-brunei-latest.osm.pbf --output=/data/pmtiles/my-sg-bn-full.pmtiles

postgis-load: env
	$(COMPOSE) up -d postgres redis
	$(COMPOSE) --profile pipeline run --rm pipeline bash /pipelines/scripts/06_ingest_postgis.sh
	$(COMPOSE) --profile pipeline run --rm pipeline python3 /pipelines/scripts/07_load_tolls.py
	$(COMPOSE) --profile pipeline run --rm pipeline python3 /pipelines/scripts/08_sync_redis_geo.py

tolls-load: env
	$(COMPOSE) --profile pipeline run --rm pipeline python3 /pipelines/scripts/07_load_tolls.py
	$(COMPOSE) --profile pipeline run --rm pipeline python3 /pipelines/scripts/08_sync_redis_geo.py

redis-sync: env
	$(COMPOSE) --profile pipeline run --rm pipeline python3 /pipelines/scripts/08_sync_redis_geo.py

test-api: env
	$(COMPOSE) run --rm --no-deps karta-api pytest -v
