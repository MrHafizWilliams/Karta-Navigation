from karta_api.main import create_app


def test_openapi_schema_generates_all_phase1_and_phase3_routes() -> None:
    app = create_app()
    schema = app.openapi()
    paths = set(schema["paths"].keys())
    expected = {
        # Phase 1
        "/v1/routes",
        "/v1/pois/bbox",
        "/v1/pois/search",
        "/v1/pois/offline-index",
        "/v1/spatial/road-context",
        "/v1/tiles/prefetch-plan",
        "/v1/tolls/gantries",
        "/v1/tolls/estimate",
        "/v1/regions",
        "/v1/regions/downloads/{region_id}/{filename}",
        "/v1/health",
        "/v1/health/live",
        # Phase 3
        "/v1/hazards",
        "/v1/hazards/nearby",
        "/v1/hazards/{hazard_id}/vote",
        "/v1/hazards/traffic-probe",
        "/v1/fuel/along-route",
        "/v1/fuel/nearby",
        "/v1/fuel/stations/{poi_id}/prices",
        "/v1/calendar/feeds",
        "/v1/calendar/import-ics",
        "/v1/calendar/events",
        "/v1/calendar/evaluate-departures",
        "/v1/carpool/offers",
        "/v1/carpool/matches/search",
        "/v1/carpool/offers/{offer_id}/request",
        "/v1/carpool/matches/{match_id}/respond",
        "/v1/voice/parse-intent",
        "/v1/voice/packs",
        "/v1/voice/packs/{pack_id}/clips/{cue_key}",
    }
    assert expected.issubset(paths)
