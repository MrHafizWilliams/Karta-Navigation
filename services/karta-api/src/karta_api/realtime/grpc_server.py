from __future__ import annotations

import asyncio
import json
import logging
import uuid
from typing import Any

from karta_api.models.common import Coordinate
from karta_api.models.realtime import (
    HazardCategory,
    HazardReportRequest,
    HazardSeverity,
    HazardVoteType,
    TelemetryUpdate,
)
from karta_api.realtime.geo_filter import compute_dynamic_radius_meters
from karta_api.realtime.hub import RealtimeHazardHub

logger = logging.getLogger(__name__)

SERVICE_NAME = "karta.realtime.v1.RealtimeHazardService"


def _json_serialize(obj: dict[str, Any]) -> bytes:
    return json.dumps(obj, separators=(",", ":")).encode("utf-8")


def _json_deserialize(raw: bytes) -> dict[str, Any]:
    if not raw:
        return {}
    return json.loads(raw.decode("utf-8"))


class KartaRealtimeGrpcServer:
    """
    Async HTTP/2 gRPC Server exposing `karta.realtime.v1.RealtimeHazardService`
    (matching `contracts/proto/karta_realtime.proto`):
      - `StreamNavigationChannel` (bi-directional streaming)
      - `ReportHazard` (unary)
      - `QueryNearbyHazards` (unary)

    Backed directly by the shared `RealtimeHazardHub` (Redis Geo + Pub/Sub + PostGIS + Valhalla).
    """

    def __init__(self, hub: RealtimeHazardHub, listen_addr: str = "0.0.0.0:50051") -> None:
        self._hub = hub
        self._listen_addr = listen_addr
        self._server: Any = None
        self._started = False

    @property
    def is_running(self) -> bool:
        return self._started

    async def start(self) -> bool:
        try:
            import grpc
        except ImportError:
            logger.warning("grpcio not installed; gRPC realtime server disabled (WebSocket remains active).")
            return False

        async def handle_report_hazard(request: dict[str, Any], _context: Any) -> dict[str, Any]:
            coord = request.get("coordinate") or {}
            req = HazardReportRequest(
                category=HazardCategory(str(request.get("category", "accident")).lower()),
                subtype=request.get("subtype"),
                severity=HazardSeverity(str(request.get("severity", "medium")).lower()),
                coordinate=Coordinate(lat=float(coord["lat"]), lon=float(coord["lon"])),
                heading_deg=request.get("heading_deg"),
                affects_both_directions=bool(request.get("affects_both_directions", False)),
                lane_hint=request.get("lane_hint"),
                description=request.get("description"),
                source="grpc",
                reporter_session_id=request.get("session_id"),
            )
            hazard, merged = await self._hub.report_hazard(req)
            return {"merged": merged, "hazard": hazard.model_dump(mode="json")}

        async def handle_query_nearby(request: dict[str, Any], _context: Any) -> dict[str, Any]:
            coord = request.get("coordinate") or {}
            speed = float(request.get("speed_kmh", 0.0))
            heading = request.get("heading_deg")
            max_r = request.get("max_radius_meters")
            hazards = await self._hub.query_nearby_hazards(
                lat=float(coord["lat"]),
                lon=float(coord["lon"]),
                heading_deg=float(heading) if heading is not None else None,
                speed_kmh=speed,
                max_radius_m=float(max_r) if max_r else None,
            )
            return {
                "effective_radius_meters": compute_dynamic_radius_meters(speed, None, float(max_r) if max_r else None),
                "hazards": [h.model_dump(mode="json") for h in hazards],
            }

        async def handle_stream_channel(request_iterator: Any, _context: Any):
            session_id = f"grpc-{uuid.uuid4().hex[:12]}"
            out_queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=128)

            async def enqueue(frame: dict[str, Any]) -> None:
                try:
                    out_queue.put_nowait(frame)
                except asyncio.QueueFull:
                    pass

            await self._hub.register_session(
                session_id=session_id,
                transport="grpc",
                send=enqueue,
            )

            async def reader() -> None:
                try:
                    async for msg in request_iterator:
                        msg_type = msg.get("type") or msg.get("event_type")
                        if msg_type == "telemetry.update" or "telemetry" in msg:
                            t = msg.get("telemetry", msg)
                            coord = t.get("coordinate") or t
                            await self._hub.handle_telemetry(
                                TelemetryUpdate(
                                    session_id=session_id,
                                    coordinate=Coordinate(lat=float(coord["lat"]), lon=float(coord["lon"])),
                                    heading_deg=float(t.get("heading_deg", 0.0)),
                                    speed_kmh=float(t.get("speed_kmh", 0.0)),
                                    country_code=t.get("country_code"),
                                    route_id=t.get("route_id"),
                                    route_polyline6=t.get("route_polyline6"),
                                    destination=(
                                        Coordinate(**t["destination"]) if t.get("destination") else None
                                    ),
                                )
                            )
                        elif msg_type == "hazard.report" or "report_hazard" in msg:
                            r = msg.get("report_hazard", msg)
                            coord = r.get("coordinate") or r
                            await self._hub.report_hazard(
                                HazardReportRequest(
                                    category=HazardCategory(str(r.get("category", "accident")).lower()),
                                    subtype=r.get("subtype"),
                                    severity=HazardSeverity(str(r.get("severity", "medium")).lower()),
                                    coordinate=Coordinate(lat=float(coord["lat"]), lon=float(coord["lon"])),
                                    heading_deg=r.get("heading_deg"),
                                    affects_both_directions=bool(r.get("affects_both_directions", False)),
                                    lane_hint=r.get("lane_hint"),
                                    description=r.get("description"),
                                    source="grpc",
                                    reporter_session_id=session_id,
                                )
                            )
                        elif msg_type == "hazard.vote" or "vote_hazard" in msg:
                            v = msg.get("vote_hazard", msg)
                            await self._hub.vote_hazard(
                                hazard_id=str(v["hazard_id"]),
                                vote=HazardVoteType(str(v["vote"]).lower()),
                                voter_session_id=session_id,
                            )
                except asyncio.CancelledError:
                    pass
                except Exception as exc:
                    logger.debug("gRPC stream reader ended for %s: %s", session_id, exc)
                finally:
                    await out_queue.put({"event_type": "__eof__"})

            reader_task = asyncio.create_task(reader())
            try:
                while True:
                    frame = await out_queue.get()
                    if frame.get("event_type") == "__eof__":
                        break
                    yield frame
            finally:
                reader_task.cancel()
                await self._hub.unregister_session(session_id)

        method_handlers = {
            "ReportHazard": grpc.unary_unary_rpc_method_handler(
                handle_report_hazard,
                request_deserializer=_json_deserialize,
                response_serializer=_json_serialize,
            ),
            "QueryNearbyHazards": grpc.unary_unary_rpc_method_handler(
                handle_query_nearby,
                request_deserializer=_json_deserialize,
                response_serializer=_json_serialize,
            ),
            "StreamNavigationChannel": grpc.stream_stream_rpc_method_handler(
                handle_stream_channel,
                request_deserializer=_json_deserialize,
                response_serializer=_json_serialize,
            ),
        }
        generic_handler = grpc.method_handlers_generic_handler(SERVICE_NAME, method_handlers)
        self._server = grpc.aio.server()
        self._server.add_generic_rpc_handlers((generic_handler,))
        self._server.add_insecure_port(self._listen_addr)
        await self._server.start()
        self._started = True
        logger.info("Karta gRPC RealtimeHazardService listening on %s", self._listen_addr)
        return True

    async def stop(self) -> None:
        if self._server is not None and self._started:
            await self._server.stop(grace=2.0)
            self._started = False
            logger.info("Karta gRPC RealtimeHazardService stopped.")
