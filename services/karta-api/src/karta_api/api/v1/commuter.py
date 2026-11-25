from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Query

from karta_api.deps import AppContainer, get_container
from karta_api.models.commuter import (
    CalendarEventCreateRequest,
    CalendarEventItem,
    CalendarFeedRequest,
    CalendarIcsImportRequest,
    CarpoolMatchCandidate,
    CarpoolMatchRecord,
    CarpoolMatchRequestCreate,
    CarpoolMatchRespondRequest,
    CarpoolOfferCreateRequest,
    CarpoolOfferPublic,
    CarpoolSearchRequest,
    EvaluateDeparturesRequest,
    EvaluateDeparturesResponse,
)
from karta_api.routing.valhalla_client import ValhallaError

router = APIRouter(tags=["commuter"])


# ============================================================================
# SMART CALENDAR & EVENT SYNC (TIME-TO-LEAVE)
# ============================================================================
@router.post("/calendar/feeds")
async def register_calendar_feed(
    req: CalendarFeedRequest,
    c: AppContainer = Depends(get_container),
) -> dict[str, object]:
    if req.feed_url:
        try:
            feed, events = await c.calendar_service.sync_ics_feed_url(
                user_token=req.user_token,
                provider=req.provider,
                label=req.label,
                feed_url=req.feed_url,
            )
            return {
                "feed": feed,
                "synced_events": len(events),
                "events": [e.model_dump(mode="json") for e in events],
            }
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"Failed to sync ICS feed URL: {exc}") from exc

    feed = await c.community_repo.upsert_calendar_feed(
        user_token=req.user_token,
        provider=req.provider,
        label=req.label,
        feed_url=None,
    )
    return {"feed": feed, "synced_events": 0, "events": []}


@router.post("/calendar/import-ics", response_model=list[CalendarEventItem])
async def import_calendar_ics(
    req: CalendarIcsImportRequest,
    c: AppContainer = Depends(get_container),
) -> list[CalendarEventItem]:
    events = await c.calendar_service.import_ics_content(
        user_token=req.user_token,
        ics_content=req.ics_content,
        provider=req.provider,
    )
    if not events:
        raise HTTPException(status_code=422, detail="No valid VEVENT entries found in ICS payload.")
    return events


@router.post("/calendar/events", response_model=CalendarEventItem)
async def create_calendar_event(
    req: CalendarEventCreateRequest,
    c: AppContainer = Depends(get_container),
) -> CalendarEventItem:
    dest, cc = await c.calendar_service.geocode_location(
        req.location_text, fallback=req.destination
    )
    return await c.community_repo.upsert_calendar_event(
        user_token=req.user_token,
        title=req.title,
        provider=req.provider,
        location_text=req.location_text,
        destination=dest,
        country_code=cc,
        starts_at=req.starts_at,
        ends_at=req.ends_at,
        parking_buffer_sec=req.parking_buffer_sec,
    )


@router.get("/calendar/events", response_model=list[CalendarEventItem])
async def list_calendar_events(
    user_token: str = Query("karta-commuter-default"),
    horizon_hours: int = Query(24, ge=1, le=72),
    c: AppContainer = Depends(get_container),
) -> list[CalendarEventItem]:
    return await c.community_repo.list_upcoming_calendar_events(
        user_token=user_token, horizon_hours=horizon_hours
    )


@router.post("/calendar/evaluate-departures", response_model=EvaluateDeparturesResponse)
async def evaluate_time_to_leave(
    req: EvaluateDeparturesRequest,
    c: AppContainer = Depends(get_container),
) -> EvaluateDeparturesResponse:
    evaluations = await c.calendar_service.evaluate_upcoming_departures(
        user_token=req.user_token,
        origin=req.origin,
        horizon_hours=req.horizon_hours,
    )
    # Push urgent leave-now / running-late advisories over WebSocket too
    for ev in evaluations:
        if ev.urgency_level in ("leave_now", "running_late"):
            await c.realtime_hub.push_time_to_leave_alert(
                {
                    "event_id": ev.event.id,
                    "title": ev.event.title,
                    "recommended_departure_at": ev.recommended_departure_at.isoformat(),
                    "traffic_delay_seconds": ev.traffic_delay_seconds,
                    "urgency_level": ev.urgency_level,
                    "advisory_message": ev.advisory_message,
                }
            )
    return EvaluateDeparturesResponse(
        evaluated_at=datetime.now(tz=UTC),
        origin=req.origin,
        count=len(evaluations),
        evaluations=evaluations,
    )


# ============================================================================
# PRIVACY-FIRST CARPOOL / RIDE-SHARING CORRIDOR MATCHING
# ============================================================================
@router.post("/carpool/offers", response_model=CarpoolOfferPublic)
async def create_carpool_offer(
    req: CarpoolOfferCreateRequest,
    c: AppContainer = Depends(get_container),
) -> CarpoolOfferPublic:
    try:
        return await c.carpool_service.create_offer(req)
    except ValhallaError as exc:
        raise HTTPException(
            status_code=503 if exc.status_code >= 500 else 422,
            detail={"engine": "valhalla", "error": exc.message},
        ) from exc


@router.get("/carpool/offers", response_model=list[CarpoolOfferPublic])
async def list_carpool_offers(
    country_code: str | None = Query(None, pattern="^(MY|SG|BN)$"),
    c: AppContainer = Depends(get_container),
) -> list[CarpoolOfferPublic]:
    return await c.community_repo.list_active_carpool_offers(country_code=country_code)


@router.post("/carpool/matches/search", response_model=list[CarpoolMatchCandidate])
async def search_carpool_matches(
    req: CarpoolSearchRequest,
    c: AppContainer = Depends(get_container),
) -> list[CarpoolMatchCandidate]:
    return await c.carpool_service.search_matches(req)


@router.post("/carpool/offers/{offer_id}/request", response_model=CarpoolMatchRecord)
async def request_carpool_seat(
    offer_id: str,
    req: CarpoolMatchRequestCreate,
    c: AppContainer = Depends(get_container),
) -> CarpoolMatchRecord:
    try:
        rec = await c.carpool_service.request_match(offer_id, req)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid offer_id: {exc}") from exc
    if rec is None:
        raise HTTPException(status_code=404, detail="Carpool offer not found or no seats available.")
    return rec


@router.post("/carpool/matches/{match_id}/respond", response_model=CarpoolMatchRecord)
async def respond_carpool_request(
    match_id: str,
    req: CarpoolMatchRespondRequest,
    c: AppContainer = Depends(get_container),
) -> CarpoolMatchRecord:
    try:
        rec = await c.community_repo.respond_carpool_match(
            match_id=match_id,
            driver_token=req.driver_token,
            action=req.action,
            rendezvous_note=req.rendezvous_note,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid match_id: {exc}") from exc
    if rec is None:
        raise HTTPException(status_code=404, detail="Carpool match not found or unauthorized driver token.")
    return rec
