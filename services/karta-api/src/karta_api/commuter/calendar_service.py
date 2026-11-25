from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

import httpx

from karta_api.db.community_repo import CommunityRepository
from karta_api.db.spatial_repo import SpatialRepository
from karta_api.models.common import Coordinate
from karta_api.models.commuter import CalendarEventItem, TimeToLeaveEvaluation
from karta_api.models.routing import RouteRequest, RoutingProfileId
from karta_api.routing.polyline import decode_polyline6, encode_polyline6
from karta_api.routing.profiles import CostingProfileRegistry
from karta_api.routing.traffic import TrafficWeightManager
from karta_api.routing.valhalla_client import ValhallaClient, ValhallaError
from karta_api.tolls.engine import RegionalTollEngine

logger = logging.getLogger(__name__)
REGIONAL_TZ = ZoneInfo("Asia/Kuala_Lumpur")


@dataclass(frozen=True)
class ParsedIcsEvent:
    uid: str | None
    title: str
    location_text: str | None
    geo: Coordinate | None
    starts_at: datetime
    ends_at: datetime | None


def parse_ics_events(ics_text: str) -> list[ParsedIcsEvent]:
    """
    Lightweight, standards-compliant RFC 5545 iCalendar (.ics) parser supporting
    Google Calendar, Apple iCloud, Microsoft Outlook, and Facebook Events `.ics` exports.
    Handles line unfolding (`CRLF + space/tab`), `DTSTART;TZID=...`, UTC `Z`, `LOCATION`, and `GEO:lat;lon`.
    """
    unfolded = re.sub(r"\r?\n[ \t]", "", ics_text)
    events: list[ParsedIcsEvent] = []
    in_event = False
    fields: dict[str, tuple[str, str]] = {}

    for raw_line in unfolded.splitlines():
        line = raw_line.strip()
        if line == "BEGIN:VEVENT":
            in_event = True
            fields = {}
            continue
        if line == "END:VEVENT":
            in_event = False
            ev = _build_parsed_event(fields)
            if ev is not None:
                events.append(ev)
            continue
        if not in_event or ":" not in line:
            continue
        key_part, val = line.split(":", 1)
        prop_name = key_part.split(";", 1)[0].upper()
        fields[prop_name] = (key_part, val.strip())

    return events


def _parse_ics_datetime(key_part: str, val: str) -> datetime | None:
    tz = REGIONAL_TZ
    tz_match = re.search(r"TZID=([^;:]+)", key_part, re.IGNORECASE)
    if tz_match:
        try:
            tz = ZoneInfo(tz_match.group(1).strip())
        except Exception:
            tz = REGIONAL_TZ

    clean = val.strip()
    try:
        if clean.endswith("Z"):
            dt = datetime.strptime(clean, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
            return dt.astimezone(REGIONAL_TZ)
        if "T" in clean:
            dt = datetime.strptime(clean[:15], "%Y%m%dT%H%M%S")
            return dt.replace(tzinfo=tz)
        if len(clean) == 8:
            dt = datetime.strptime(clean, "%Y%m%d")
            return dt.replace(tzinfo=tz)
    except ValueError:
        return None
    return None


def _build_parsed_event(fields: dict[str, tuple[str, str]]) -> ParsedIcsEvent | None:
    if "DTSTART" not in fields or "SUMMARY" not in fields:
        return None
    starts_at = _parse_ics_datetime(*fields["DTSTART"])
    if starts_at is None:
        return None
    ends_at = _parse_ics_datetime(*fields["DTEND"]) if "DTEND" in fields else None
    title = fields["SUMMARY"][1].replace("\\,", ",").replace("\\n", " ").strip()
    loc = fields["LOCATION"][1].replace("\\,", ",").replace("\\n", ", ").strip() if "LOCATION" in fields else None
    uid = fields["UID"][1].strip() if "UID" in fields else None

    geo: Coordinate | None = None
    if "GEO" in fields:
        parts = re.split(r"[;,]", fields["GEO"][1])
        if len(parts) >= 2:
            try:
                geo = Coordinate(lat=float(parts[0]), lon=float(parts[1]))
            except ValueError:
                geo = None

    return ParsedIcsEvent(
        uid=uid,
        title=title,
        location_text=loc or None,
        geo=geo,
        starts_at=starts_at,
        ends_at=ends_at,
    )


class SmartCalendarService:
    """
    Syncs external Calendar / Facebook `.ics` feeds & manual commuter events, geocodes
    destination venues via PostGIS `spatial.pois`, and computes live traffic-aware
    Time-to-Leave advisories using real Valhalla dynamic costing + RegionalTollEngine.
    """

    def __init__(
        self,
        *,
        community_repo: CommunityRepository,
        spatial_repo: SpatialRepository,
        valhalla: ValhallaClient,
        profiles: CostingProfileRegistry,
        traffic_manager: TrafficWeightManager,
        toll_engine: RegionalTollEngine,
    ) -> None:
        self._community = community_repo
        self._spatial = spatial_repo
        self._valhalla = valhalla
        self._profiles = profiles
        self._traffic = traffic_manager
        self._toll_engine = toll_engine

    async def geocode_location(
        self, location_text: str | None, fallback: Coordinate | None = None
    ) -> tuple[Coordinate | None, str | None]:
        if fallback is not None:
            cc = await self._spatial.resolve_country_at_point(fallback.lat, fallback.lon)
            return fallback, (cc.iso_a2 if cc else "MY")
        if not location_text or len(location_text.strip()) < 2:
            return None, None
        # Query real PostGIS `spatial.pois` using the venue name / leading comma token
        token = location_text.split(",")[0].strip()
        hits = await self._spatial.search_pois(query=token, limit=1)
        if not hits and token != location_text.strip():
            hits = await self._spatial.search_pois(query=location_text.strip()[:80], limit=1)
        if hits:
            return hits[0].coordinate, (hits[0].country_code or "MY")
        return None, None

    async def import_ics_content(
        self,
        *,
        user_token: str,
        ics_content: str,
        provider: str = "ics_url",
        feed_id: str | None = None,
    ) -> list[CalendarEventItem]:
        parsed = parse_ics_events(ics_content)
        stored: list[CalendarEventItem] = []
        for ev in parsed:
            dest, cc = await self.geocode_location(ev.location_text, fallback=ev.geo)
            item = await self._community.upsert_calendar_event(
                user_token=user_token,
                title=ev.title,
                provider=provider,
                location_text=ev.location_text,
                destination=dest,
                country_code=cc,
                starts_at=ev.starts_at,
                ends_at=ev.ends_at,
                external_uid=ev.uid,
                feed_id=feed_id,
            )
            stored.append(item)
        return stored

    async def sync_ics_feed_url(
        self, *, user_token: str, provider: str, label: str, feed_url: str
    ) -> tuple[dict, list[CalendarEventItem]]:
        feed = await self._community.upsert_calendar_feed(
            user_token=user_token, provider=provider, label=label, feed_url=feed_url
        )
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            resp = await client.get(feed_url)
            resp.raise_for_status()
            events = await self.import_ics_content(
                user_token=user_token,
                ics_content=resp.text,
                provider=provider,
                feed_id=feed["id"],
            )
        return feed, events

    async def evaluate_upcoming_departures(
        self,
        *,
        user_token: str,
        origin: Coordinate,
        horizon_hours: int = 24,
    ) -> list[TimeToLeaveEvaluation]:
        events = await self._community.list_upcoming_calendar_events(
            user_token=user_token, horizon_hours=horizon_hours
        )
        now = datetime.now(tz=UTC)
        results: list[TimeToLeaveEvaluation] = []

        for ev in events:
            if ev.destination is None:
                continue

            req = RouteRequest(
                origin=origin,
                destination=ev.destination,
                profile=RoutingProfileId.DRIVE_FASTEST,
                alternates=0,
                include_toll_free_comparison=False,
            )
            overlay = await self._traffic.build_dynamic_costing_overlay(
                origin=origin,
                destination=ev.destination,
                community_repo=self._community,
            )
            payload = self._profiles.build_valhalla_route_payload(
                req,
                alternates_override=0,
                exclude_locations=overlay.exclude_locations,
                exclude_polygons=overlay.exclude_polygons,
            )

            try:
                raw = await self._valhalla.route(payload)
            except ValhallaError as exc:
                logger.debug("Valhalla TTL route skipped for event %s: %s", ev.id, exc)
                continue

            trip = raw["trip"]
            summary = trip.get("summary", {})
            dist_km = round(float(summary.get("length", 0.0)), 2)
            base_sec = round(float(summary.get("time", 0.0)), 1)

            coords: list[tuple[float, float]] = []
            for leg in trip.get("legs", []):
                if leg.get("shape"):
                    coords.extend(decode_polyline6(leg["shape"]))

            delay_sec, _, _ = await self._traffic.evaluate_route_traffic(
                coords=coords,
                community_repo=self._community,
            )
            live_sec = round(base_sec + delay_sec, 1)

            toll_display = "Free"
            if len(coords) >= 2:
                try:
                    toll = await self._toll_engine.calculate_route_tolls(
                        polyline6=encode_polyline6(coords),
                        duration_seconds=live_sec,
                        departure_time=now.astimezone(REGIONAL_TZ),
                    )
                    toll_display = toll.display_total
                except Exception:
                    toll_display = "Free"

            starts_utc = ev.starts_at.astimezone(UTC) if ev.starts_at.tzinfo else ev.starts_at.replace(tzinfo=UTC)
            rec_dep = starts_utc - timedelta(seconds=live_sec + ev.parking_buffer_sec)
            mins_until = int(round((rec_dep - now).total_seconds() / 60.0))

            if mins_until < 0:
                urgency = "running_late"
                advisory = f"Leave immediately — you are {abs(mins_until)} min behind schedule"
            elif mins_until <= 15:
                urgency = "leave_now"
                advisory = f"Time to leave in {mins_until} min ({int(round(live_sec / 60))} min drive)"
            elif mins_until <= 45:
                urgency = "prepare"
                advisory = f"Depart in {mins_until} min · {dist_km:.1f} km"
            else:
                urgency = "upcoming"
                advisory = f"Depart by {rec_dep.astimezone(REGIONAL_TZ).strftime('%H:%M')} · {dist_km:.1f} km"

            if delay_sec >= 120:
                advisory += f" (+{int(round(delay_sec / 60))} min live traffic)"

            results.append(
                TimeToLeaveEvaluation(
                    event=ev,
                    baseline_duration_seconds=base_sec,
                    live_traffic_duration_seconds=live_sec,
                    traffic_delay_seconds=delay_sec,
                    distance_km=dist_km,
                    estimated_toll_display=toll_display,
                    recommended_departure_at=rec_dep,
                    minutes_until_departure=mins_until,
                    urgency_level=urgency,
                    advisory_message=advisory,
                )
            )

        return results
