from __future__ import annotations

import logging
import uuid
from typing import Any

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from karta_api.deps import AppContainer
from karta_api.models.common import Coordinate
from karta_api.models.realtime import (
    HazardCategory,
    HazardReportRequest,
    HazardSeverity,
    HazardVoteType,
    TelemetryUpdate,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/realtime", tags=["realtime"])


@router.websocket("/ws")
async def realtime_navigation_ws(
    websocket: WebSocket,
    session_id: str | None = Query(None),
    lat: float = Query(3.1579, ge=-90.0, le=90.0),
    lon: float = Query(101.7116, ge=-180.0, le=180.0),
    country: str = Query("MY", pattern="^(MY|SG|BN)$"),
) -> None:
    """
    Low-latency bi-directional WebSocket channel backed by Redis Geo, Redis Pub/Sub
    (geohash5 cell fan-out), PostGIS, and Valhalla dynamic costing.
    """
    await websocket.accept()
    container: AppContainer = websocket.app.state.container
    hub = container.realtime_hub
    sid = session_id or f"ws-{uuid.uuid4().hex[:12]}"

    async def send_frame(frame: dict[str, Any]) -> None:
        await websocket.send_json(frame)

    await hub.register_session(
        session_id=sid,
        transport="ws",
        send=send_frame,
        lat=lat,
        lon=lon,
        country_code=country,
    )

    try:
        while True:
            raw = await websocket.receive_json()
            msg_type = str(raw.get("type") or raw.get("event_type") or "")

            if msg_type == "ping":
                await websocket.send_json({"event_type": "pong", "session_id": sid})

            elif msg_type == "telemetry.update":
                coord_raw = raw.get("coordinate") or raw
                update = TelemetryUpdate(
                    session_id=sid,
                    coordinate=Coordinate(lat=float(coord_raw["lat"]), lon=float(coord_raw["lon"])),
                    heading_deg=float(raw.get("heading_deg", 0.0)) % 360.0,
                    speed_kmh=float(raw.get("speed_kmh", 0.0)),
                    country_code=raw.get("country_code"),
                    route_id=raw.get("route_id"),
                    route_polyline6=raw.get("route_polyline6"),
                    route_profile=str(raw.get("route_profile") or "drive_fastest"),
                    vehicle_profile=str(raw.get("vehicle_profile") or "car"),
                    vehicle_registration_country=str(raw.get("vehicle_registration_country") or "MY"),
                    destination=Coordinate(**raw["destination"]) if raw.get("destination") else None,
                    waypoints=[Coordinate(**w) for w in raw.get("waypoints", [])],
                )
                await hub.handle_telemetry(update)

            elif msg_type == "hazard.report":
                coord_raw = raw.get("coordinate") or raw
                req = HazardReportRequest(
                    category=HazardCategory(str(raw["category"]).lower()),
                    subtype=raw.get("subtype"),
                    severity=HazardSeverity(str(raw.get("severity", "medium")).lower()),
                    coordinate=Coordinate(lat=float(coord_raw["lat"]), lon=float(coord_raw["lon"])),
                    heading_deg=(
                        float(raw["heading_deg"]) % 360.0
                        if raw.get("heading_deg") is not None
                        else None
                    ),
                    affects_both_directions=bool(raw.get("affects_both_directions", False)),
                    lane_hint=raw.get("lane_hint"),
                    description=raw.get("description"),
                    source=str(raw.get("source") or "radial"),
                    reporter_session_id=sid,
                )
                hazard, merged = await hub.report_hazard(req)
                await websocket.send_json(
                    {
                        "event_type": "hazard.ack",
                        "merged": merged,
                        "hazard": hazard.model_dump(mode="json"),
                    }
                )

            elif msg_type == "hazard.vote":
                coord = Coordinate(**raw["coordinate"]) if raw.get("coordinate") else None
                updated = await hub.vote_hazard(
                    hazard_id=str(raw["hazard_id"]),
                    vote=HazardVoteType(str(raw["vote"]).lower()),
                    voter_session_id=sid,
                    coordinate=coord,
                )
                if updated is not None:
                    await websocket.send_json(
                        {
                            "event_type": "hazard.vote_ack",
                            "hazard": updated.model_dump(mode="json"),
                        }
                    )

            elif msg_type == "route.reroute_decision":
                await websocket.send_json(
                    {
                        "event_type": "route.reroute_ack",
                        "proposal_id": raw.get("proposal_id"),
                        "action": raw.get("action"),
                    }
                )

    except WebSocketDisconnect:
        logger.debug("WebSocket session disconnected: %s", sid)
    except Exception as exc:
        logger.debug("WebSocket session closed with error (%s): %s", sid, exc)
    finally:
        await hub.unregister_session(sid)
