from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

from karta_api.cache.redis_geo import RedisGeoCache
from karta_api.db.community_repo import CommunityRepository
from karta_api.db.spatial_repo import SpatialRepository
from karta_api.models.common import Coordinate
from karta_api.models.realtime import (
    HazardCategory,
    HazardRecord,
    HazardReportRequest,
    HazardStatus,
    HazardVoteType,
    TelemetryUpdate,
)
from karta_api.realtime.geo_filter import (
    build_closure_exclusion_ring,
    compute_dynamic_radius_meters,
    encode_geohash,
    evaluate_hazard_for_driver,
    geohash_cell_and_neighbors,
)
from karta_api.routing.polyline import decode_polyline6
from karta_api.routing.traffic import TrafficObservation, TrafficWeightManager
from karta_api.routing.valhalla_client import ValhallaClient

logger = logging.getLogger(__name__)

SendCallback = Callable[[dict[str, Any]], Awaitable[None]]
RerouteHook = Callable[["DriverSession", HazardRecord], Awaitable[None]]


@dataclass
class DriverSession:
    session_id: str
    transport: str  # "ws" | "grpc"
    send: SendCallback
    lat: float = 3.1579
    lon: float = 101.7116
    heading_deg: float | None = None
    speed_kmh: float = 0.0
    country_code: str = "MY"
    route_id: str | None = None
    route_polyline6: str | None = None
    route_coords: list[tuple[float, float]] = field(default_factory=list)
    route_profile: str = "drive_fastest"
    vehicle_profile: str = "car"
    vehicle_registration_country: str = "MY"
    destination: Coordinate | None = None
    waypoints: list[Coordinate] = field(default_factory=list)
    subscribed_cells: set[str] = field(default_factory=set)
    seen_hazard_ids: set[str] = field(default_factory=set)
    last_telemetry_at: datetime = field(default_factory=lambda: datetime.now(tz=UTC))


class RealtimeHazardHub:
    """
    Low-latency Geospatial Pub/Sub Hub backed by Redis Geo, Redis Pub/Sub (geohash5
    cell channels), PostGIS `community.hazards`, and Valhalla `/locate` edge snapping.
    Serves BOTH the FastAPI WebSocket Gateway and the gRPC Bi-Directional Server.
    """

    def __init__(
        self,
        *,
        redis_cache: RedisGeoCache,
        community_repo: CommunityRepository,
        spatial_repo: SpatialRepository,
        valhalla: ValhallaClient,
        traffic_manager: TrafficWeightManager,
        expiry_sweep_seconds: int = 30,
    ) -> None:
        self._redis = redis_cache
        self._community = community_repo
        self._spatial = spatial_repo
        self._valhalla = valhalla
        self._traffic = traffic_manager
        self._expiry_sweep_seconds = expiry_sweep_seconds

        self._sessions: dict[str, DriverSession] = {}
        self._cell_index: dict[str, set[str]] = {}  # geohash5 -> set(session_id)
        self._reroute_hook: RerouteHook | None = None

        self._pubsub_task: asyncio.Task[None] | None = None
        self._sweeper_task: asyncio.Task[None] | None = None
        self._running = False

    def set_reroute_hook(self, hook: RerouteHook) -> None:
        self._reroute_hook = hook

    @property
    def active_session_count(self) -> int:
        return len(self._sessions)

    async def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._pubsub_task = asyncio.create_task(self._redis_pubsub_loop(), name="karta-pubsub-loop")
        self._sweeper_task = asyncio.create_task(self._expiry_sweeper_loop(), name="karta-hazard-sweeper")
        logger.info("RealtimeHazardHub started (Redis Geo + Pub/Sub geohash5 fan-out).")

    async def stop(self) -> None:
        self._running = False
        for task in (self._pubsub_task, self._sweeper_task):
            if task is not None:
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
        self._pubsub_task = None
        self._sweeper_task = None

    async def register_session(
        self,
        *,
        session_id: str,
        transport: str,
        send: SendCallback,
        lat: float = 3.1579,
        lon: float = 101.7116,
        country_code: str = "MY",
    ) -> DriverSession:
        session = DriverSession(
            session_id=session_id,
            transport=transport,
            send=send,
            lat=lat,
            lon=lon,
            country_code=country_code,
        )
        self._sessions[session_id] = session
        self._update_cell_subscriptions(session, lat, lon)

        # Send immediate bootstrap ack with nearby active hazards
        nearby = await self.query_nearby_hazards(
            lat=lat, lon=lon, heading_deg=None, speed_kmh=0.0, max_radius_m=8000.0
        )
        epoch = await self._traffic.get_traffic_epoch()
        for h in nearby:
            session.seen_hazard_ids.add(h.id)

        await self._safe_send(
            session,
            {
                "event_type": "session.ack",
                "session_id": session_id,
                "traffic_epoch": epoch,
                "active_drivers": len(self._sessions),
                "initial_hazards": [h.model_dump(mode="json") for h in nearby],
            },
        )
        return session

    async def unregister_session(self, session_id: str) -> None:
        session = self._sessions.pop(session_id, None)
        if session is None:
            return
        for cell in session.subscribed_cells:
            bucket = self._cell_index.get(cell)
            if bucket is not None:
                bucket.discard(session_id)
                if not bucket:
                    self._cell_index.pop(cell, None)
        try:
            await self._redis.client.zrem("karta:geo:drivers", session_id)
        except Exception:
            pass

    async def handle_telemetry(self, update: TelemetryUpdate) -> list[HazardRecord]:
        session = self._sessions.get(update.session_id)
        if session is None:
            return []

        session.lat = update.coordinate.lat
        session.lon = update.coordinate.lon
        session.heading_deg = update.heading_deg
        session.speed_kmh = update.speed_kmh
        session.last_telemetry_at = datetime.now(tz=UTC)
        if update.country_code:
            session.country_code = update.country_code
        if update.route_id is not None:
            session.route_id = update.route_id
        if update.route_profile:
            session.route_profile = update.route_profile
        if update.vehicle_profile:
            session.vehicle_profile = update.vehicle_profile
        if update.vehicle_registration_country:
            session.vehicle_registration_country = update.vehicle_registration_country
        if update.destination is not None:
            session.destination = update.destination
        if update.waypoints:
            session.waypoints = update.waypoints
        if update.route_polyline6 and update.route_polyline6 != session.route_polyline6:
            session.route_polyline6 = update.route_polyline6
            try:
                session.route_coords = decode_polyline6(update.route_polyline6)
            except Exception:
                session.route_coords = []

        self._update_cell_subscriptions(session, session.lat, session.lon)

        # Update Redis Geo active driver index & optionally feed live speed probe into traffic table
        try:
            await self._redis.client.geoadd(
                "karta:geo:drivers",
                (session.lon, session.lat, session.session_id),
            )
        except Exception:
            pass

        # Feed moving vehicle GPS probe speed into Redis traffic table when moving slowly on a road
        if 3.0 <= session.speed_kmh <= 150.0:
            asyncio.create_task(self._record_probe_speed_async(session))

        # Push any newly approaching hazards within the driver's dynamic heading-aware cone
        relevant = await self.query_nearby_hazards(
            lat=session.lat,
            lon=session.lon,
            heading_deg=session.heading_deg,
            speed_kmh=session.speed_kmh,
            route_coords=session.route_coords,
        )
        fresh: list[HazardRecord] = []
        for haz in relevant:
            if haz.id not in session.seen_hazard_ids:
                session.seen_hazard_ids.add(haz.id)
                fresh.append(haz)
                await self._safe_send(
                    session,
                    {
                        "event_type": "hazard.alert",
                        "hazard": haz.model_dump(mode="json"),
                    },
                )
        return fresh

    async def report_hazard(self, req: HazardReportRequest) -> tuple[HazardRecord, bool]:
        """
        Persists a crowdsourced hazard in PostGIS, snaps it to PostGIS `road_segments` and
        Valhalla `/locate` directed edges, indexes it in Redis Geo, updates Valhalla dynamic
        costing weights, and publishes it to Redis Pub/Sub geohash5 cell channels!
        """
        # 1. Snap to nearest PostGIS road segment & active country
        road = await self._spatial.nearest_road_segment(
            req.coordinate.lat, req.coordinate.lon, heading_deg=req.heading_deg
        )
        country = await self._spatial.resolve_country_at_point(
            req.coordinate.lat, req.coordinate.lon
        )

        # 2. Snap to Valhalla directed edge (non-blocking graceful fallback if offline)
        valhalla_edge_id: int | None = None
        osm_way_id: int | None = None
        try:
            located = await self._valhalla.locate(req.coordinate.lat, req.coordinate.lon)
            if located and isinstance(located[0], dict):
                edges = located[0].get("edges") or []
                if edges:
                    edge0 = edges[0]
                    valhalla_edge_id = edge0.get("edge_id", {}).get("value") if isinstance(edge0.get("edge_id"), dict) else None
                    edge_info = edge0.get("edge_info") or {}
                    if edge_info.get("way_id") is not None:
                        osm_way_id = int(edge_info["way_id"])
        except Exception as exc:
            logger.debug("Valhalla /locate snap skipped: %s", exc)

        # Build small exclusion polygon WKT for road closures
        exclusion_wkt: str | None = None
        if req.category == HazardCategory.ROAD_CLOSURE:
            ring = build_closure_exclusion_ring(req.coordinate.lat, req.coordinate.lon)
            ring_txt = ", ".join(f"{pt[0]} {pt[1]}" for pt in ring)
            exclusion_wkt = f"POLYGON(({ring_txt}))"

        oneway = 0
        if road:
            hw = str(road.get("highway_class") or "")
            if hw in ("motorway", "motorway_link", "trunk_link"):
                oneway = 1

        hazard, merged = await self._community.create_or_merge_hazard(
            req,
            road_heading_deg=req.heading_deg,
            oneway=oneway,
            osm_way_id=osm_way_id,
            valhalla_edge_id=valhalla_edge_id,
            road_name=str(road["road_name"]) if road and road.get("road_name") else None,
            road_ref=str(road["road_ref"]) if road and road.get("road_ref") else None,
            country_code=country.iso_a2 if country else None,
            exclusion_wkt=exclusion_wkt,
        )

        # 3. Index in Redis Geo + Metadata Hash
        await self._index_hazard_in_redis(hazard)

        # 4. Feed dynamic costing weight into Valhalla TrafficWeightManager
        await self._traffic.apply_hazard_weight(hazard)

        # 5. Fan-out to geohash5 cell via Redis Pub/Sub (and local sessions immediately)
        cell = encode_geohash(hazard.coordinate.lat, hazard.coordinate.lon, precision=5)
        payload = {
            "event_type": "hazard.updated" if merged else "hazard.alert",
            "cell": cell,
            "hazard": hazard.model_dump(mode="json"),
        }
        await self._publish_cell_event(cell, payload)
        return hazard, merged

    async def vote_hazard(
        self,
        *,
        hazard_id: str,
        vote: HazardVoteType,
        voter_session_id: str | None,
        coordinate: Coordinate | None = None,
    ) -> HazardRecord | None:
        updated = await self._community.vote_hazard(
            hazard_id=hazard_id,
            vote=vote,
            voter_session_id=voter_session_id,
            coordinate=coordinate,
        )
        if updated is None:
            return None

        cell = encode_geohash(updated.coordinate.lat, updated.coordinate.lon, precision=5)
        if updated.status != HazardStatus.ACTIVE:
            await self._remove_hazard_from_redis(updated.id)
            await self._traffic.clear_hazard_weight(updated.id, osm_way_id=updated.osm_way_id)
            await self._publish_cell_event(
                cell,
                {
                    "event_type": "hazard.removed",
                    "cell": cell,
                    "hazard_id": updated.id,
                    "reason": "community_cleared",
                },
            )
        else:
            await self._index_hazard_in_redis(updated)
            await self._publish_cell_event(
                cell,
                {
                    "event_type": "hazard.updated",
                    "cell": cell,
                    "hazard": updated.model_dump(mode="json"),
                },
            )
        return updated

    async def broadcast_fuel_price_update(self, payload: dict[str, Any]) -> None:
        try:
            await self._redis.client.publish("karta:pubsub:fuel", json.dumps(payload))
        except Exception:
            pass
        for session in list(self._sessions.values()):
            await self._safe_send(session, {"event_type": "fuel.price_updated", **payload})

    async def push_time_to_leave_alert(self, payload: dict[str, Any]) -> None:
        try:
            await self._redis.client.publish("karta:pubsub:commuter", json.dumps(payload))
        except Exception:
            pass
        for session in list(self._sessions.values()):
            await self._safe_send(session, {"event_type": "commuter.time_to_leave", **payload})

    async def query_nearby_hazards(
        self,
        *,
        lat: float,
        lon: float,
        heading_deg: float | None,
        speed_kmh: float,
        route_coords: list[tuple[float, float]] | None = None,
        max_radius_m: float | None = None,
    ) -> list[HazardRecord]:
        """
        Queries active hazards via sub-5ms Redis Geo (`karta:geo:hazards`) with automatic
        PostGIS fallback, then applies Karta's 4-stage dynamic heading-aware cone filter.
        """
        search_radius = max(
            compute_dynamic_radius_meters(speed_kmh, HazardCategory.ROAD_CLOSURE, max_radius_m),
            2000.0,
        )
        candidates = await self._geosearch_hazards_redis(lat, lon, search_radius)
        if candidates is None:
            candidates = await self._community.list_active_hazards_nearby(
                lat=lat, lon=lon, radius_m=search_radius
            )

        filtered: list[HazardRecord] = []
        now = datetime.now(tz=UTC)
        for haz in candidates:
            if haz.status != HazardStatus.ACTIVE or haz.expires_at <= now:
                continue
            decision = evaluate_hazard_for_driver(
                driver_lat=lat,
                driver_lon=lon,
                driver_heading_deg=heading_deg,
                driver_speed_kmh=speed_kmh,
                hazard=haz,
                active_route_coords=route_coords,
                max_radius_override_m=max_radius_m,
            )
            if decision.relevant:
                filtered.append(
                    haz.model_copy(
                        update={
                            "distance_meters": decision.distance_meters,
                            "bearing_delta_deg": decision.bearing_delta_deg,
                            "on_active_route": decision.on_active_route,
                        }
                    )
                )

        filtered.sort(key=lambda h: (not h.on_active_route, h.distance_meters or 999999.0))
        return filtered

    async def send_to_session(self, session_id: str, frame: dict[str, Any]) -> None:
        session = self._sessions.get(session_id)
        if session is not None:
            await self._safe_send(session, frame)

    def _update_cell_subscriptions(self, session: DriverSession, lat: float, lon: float) -> None:
        next_cells = geohash_cell_and_neighbors(lat, lon, precision=5)
        if next_cells == session.subscribed_cells:
            return
        for old_cell in session.subscribed_cells - next_cells:
            bucket = self._cell_index.get(old_cell)
            if bucket is not None:
                bucket.discard(session.session_id)
                if not bucket:
                    self._cell_index.pop(old_cell, None)
        for new_cell in next_cells - session.subscribed_cells:
            self._cell_index.setdefault(new_cell, set()).add(session.session_id)
        session.subscribed_cells = next_cells

    async def _index_hazard_in_redis(self, hazard: HazardRecord) -> None:
        try:
            ttl_s = max(60, int((hazard.expires_at - datetime.now(tz=UTC)).total_seconds()))
            pipe = self._redis.client.pipeline(transaction=False)
            pipe.geoadd(
                "karta:geo:hazards",
                (hazard.coordinate.lon, hazard.coordinate.lat, hazard.id),
            )
            pipe.set(f"karta:hazard:meta:{hazard.id}", hazard.model_dump_json(), ex=ttl_s)
            await pipe.execute()
        except Exception as exc:
            logger.debug("Redis hazard index write skipped: %s", exc)

    async def _remove_hazard_from_redis(self, hazard_id: str) -> None:
        try:
            pipe = self._redis.client.pipeline(transaction=False)
            pipe.zrem("karta:geo:hazards", hazard_id)
            pipe.delete(f"karta:hazard:meta:{hazard_id}")
            await pipe.execute()
        except Exception:
            pass

    async def _geosearch_hazards_redis(
        self, lat: float, lon: float, radius_m: float
    ) -> list[HazardRecord] | None:
        try:
            if not await self._redis.client.exists("karta:geo:hazards"):
                return None
            raw = await self._redis.client.geosearch(
                name="karta:geo:hazards",
                longitude=lon,
                latitude=lat,
                radius=radius_m,
                unit="m",
                sort="ASC",
                count=120,
            )
            if not raw:
                return []
            pipe = self._redis.client.pipeline(transaction=False)
            for member_id in raw:
                pipe.get(f"karta:hazard:meta:{member_id}")
            metas = await pipe.execute()
            out: list[HazardRecord] = []
            for m in metas:
                if m:
                    out.append(HazardRecord.model_validate_json(m))
            return out
        except Exception:
            return None

    async def _publish_cell_event(self, cell: str, payload: dict[str, Any]) -> None:
        published_via_redis = False
        try:
            await self._redis.client.publish(f"karta:pubsub:cell:{cell}", json.dumps(payload))
            published_via_redis = True
        except Exception as exc:
            logger.debug("Redis publish fallback to local dispatch: %s", exc)

        # If Pub/Sub background loop isn't active (e.g. unit tests), dispatch locally immediately
        if not published_via_redis or self._pubsub_task is None or self._pubsub_task.done():
            await self._dispatch_cell_event_locally(cell, payload)

    async def _dispatch_cell_event_locally(self, cell: str, payload: dict[str, Any]) -> None:
        session_ids = list(self._cell_index.get(cell, ()))
        if not session_ids:
            return

        event_type = payload.get("event_type")
        if event_type == "hazard.removed":
            hid = str(payload.get("hazard_id", ""))
            for sid in session_ids:
                sess = self._sessions.get(sid)
                if sess is not None:
                    sess.seen_hazard_ids.discard(hid)
                    await self._safe_send(sess, payload)
            return

        raw_haz = payload.get("hazard")
        if not raw_haz:
            return
        hazard = HazardRecord.model_validate(raw_haz)

        for sid in session_ids:
            sess = self._sessions.get(sid)
            if sess is None:
                continue
            decision = evaluate_hazard_for_driver(
                driver_lat=sess.lat,
                driver_lon=sess.lon,
                driver_heading_deg=sess.heading_deg,
                driver_speed_kmh=sess.speed_kmh,
                hazard=hazard,
                active_route_coords=sess.route_coords,
            )
            if not decision.relevant:
                continue

            enriched = hazard.model_copy(
                update={
                    "distance_meters": decision.distance_meters,
                    "bearing_delta_deg": decision.bearing_delta_deg,
                    "on_active_route": decision.on_active_route,
                }
            )
            sess.seen_hazard_ids.add(enriched.id)
            await self._safe_send(
                sess,
                {
                    "event_type": event_type,
                    "hazard": enriched.model_dump(mode="json"),
                },
            )

            # Trigger real-time Valhalla reroute check if a blocking/severe hazard hits active route
            if (
                decision.on_active_route
                and self._reroute_hook is not None
                and sess.destination is not None
                and (
                    hazard.category in (HazardCategory.ROAD_CLOSURE, HazardCategory.ACCIDENT)
                )
            ):
                asyncio.create_task(self._reroute_hook(sess, enriched))

    async def _redis_pubsub_loop(self) -> None:
        while self._running:
            try:
                pubsub = self._redis.client.pubsub(ignore_subscribe_messages=True)
                await pubsub.psubscribe("karta:pubsub:cell:*")
                async for msg in pubsub.listen():
                    if not self._running:
                        break
                    if msg.get("type") != "pmessage":
                        continue
                    channel = str(msg.get("channel", ""))
                    cell = channel.rsplit(":", 1)[-1]
                    try:
                        payload = json.loads(msg["data"])
                    except Exception:
                        continue
                    await self._dispatch_cell_event_locally(cell, payload)
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.warning("Redis Pub/Sub loop reconnecting after error: %s", exc)
                await asyncio.sleep(2.0)

    async def _expiry_sweeper_loop(self) -> None:
        while self._running:
            try:
                await asyncio.sleep(self._expiry_sweep_seconds)
                expired_ids = await self._community.expire_stale_hazards()
                if expired_ids:
                    for hid in expired_ids:
                        await self._remove_hazard_from_redis(hid)
                        await self._traffic.clear_hazard_weight(hid)
                    logger.info("Expired %d stale community hazards.", len(expired_ids))
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.debug("Hazard sweeper tick error: %s", exc)

    async def _record_probe_speed_async(self, session: DriverSession) -> None:
        try:
            road = await self._spatial.nearest_road_segment(
                session.lat, session.lon, heading_deg=session.heading_deg
            )
            if road and road.get("way_id"):
                await self._traffic.record_observations(
                    [TrafficObservation(osm_way_id=int(road["way_id"]), speed_kmh=int(round(session.speed_kmh)))]
                )
        except Exception:
            pass

    @staticmethod
    async def _safe_send(session: DriverSession, frame: dict[str, Any]) -> None:
        try:
            await session.send(frame)
        except Exception:
            pass
