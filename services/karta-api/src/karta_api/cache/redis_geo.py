from __future__ import annotations

import json
import math
from typing import Any

import redis.asyncio as aioredis

from karta_api.models.common import Coordinate
from karta_api.models.spatial import ApproachingGantry, ApproachingSpeedZone, PoiItem
from karta_api.models.tolls import PaymentMethod, TollLaneGuidance


class RedisGeoCache:
    def __init__(self, redis_url: str) -> None:
        self._url = redis_url
        self._client: aioredis.Redis | None = None

    async def connect(self) -> None:
        self._client = aioredis.from_url(self._url, decode_responses=True)

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    @property
    def client(self) -> aioredis.Redis:
        if self._client is None:
            raise RuntimeError("RedisGeoCache is not connected.")
        return self._client

    async def healthcheck(self) -> dict[str, object]:
        pong = await self.client.ping()
        pois_count = await self.client.zcard("karta:geo:pois:all")
        gantries_count = await self.client.zcard("karta:geo:gantries")
        speeds_count = await self.client.zcard("karta:geo:speed_zones")
        hazards_count = await self.client.zcard("karta:geo:hazards")
        closures_count = await self.client.hlen("karta:traffic:closures")
        return {
            "ping": bool(pong),
            "geo_pois_indexed": int(pois_count),
            "geo_gantries_indexed": int(gantries_count),
            "geo_speed_zones_indexed": int(speeds_count),
            "geo_hazards_indexed": int(hazards_count),
            "traffic_closures_active": int(closures_count),
        }

    async def geosearch_pois_bbox(
        self,
        min_lon: float,
        min_lat: float,
        max_lon: float,
        max_lat: float,
        category: str | None = None,
        limit: int = 200,
    ) -> list[PoiItem] | None:
        """
        Sub-second bounding-box POI query using Redis 7 `GEOSEARCH ... BYBOX`.
        Returns None if the Redis Geo set has not been hydrated yet (signaling
        caller to fall back cleanly to PostGIS).
        """
        geo_key = f"karta:geo:pois:{category}" if category else "karta:geo:pois:all"
        if not await self.client.exists(geo_key):
            return None

        center_lon = (min_lon + max_lon) / 2.0
        center_lat = (min_lat + max_lat) / 2.0
        cos_lat = max(0.01, math.cos(math.radians(center_lat)))
        width_km = max(0.05, abs(max_lon - min_lon) * 111.320 * cos_lat)
        height_km = max(0.05, abs(max_lat - min_lat) * 110.574)

        raw = await self.client.geosearch(
            name=geo_key,
            longitude=center_lon,
            latitude=center_lat,
            width=width_km,
            height=height_km,
            unit="km",
            withcoord=True,
            withdist=True,
            sort="ASC",
            count=limit,
        )
        if not raw:
            return []

        pipe = self.client.pipeline(transaction=False)
        for entry in raw:
            member_id = entry[0]
            pipe.hgetall(f"karta:poi:meta:{member_id}")
        metas: list[dict[str, str]] = await pipe.execute()

        items: list[PoiItem] = []
        for entry, meta in zip(raw, metas, strict=False):
            member_id, dist_km, (lon, lat) = entry
            if not meta:
                continue
            ev_meta = json.loads(meta["ev_metadata"]) if meta.get("ev_metadata") else None
            items.append(
                PoiItem(
                    id=int(member_id),
                    name=meta.get("name", ""),
                    category=meta.get("category", category or "other"),
                    subcategory=meta.get("subcategory") or None,
                    brand=meta.get("brand") or None,
                    country_code=meta.get("country_code") or None,
                    coordinate=Coordinate(lat=float(lat), lon=float(lon)),
                    distance_meters=round(float(dist_km) * 1000.0, 1),
                    ev_metadata=ev_meta,
                )
            )
        return items

    async def geosearch_nearby_speed_zones(
        self, lat: float, lon: float, radius_m: float = 1000.0
    ) -> list[ApproachingSpeedZone] | None:
        if not await self.client.exists("karta:geo:speed_zones"):
            return None
        raw = await self.client.geosearch(
            name="karta:geo:speed_zones",
            longitude=lon,
            latitude=lat,
            radius=radius_m,
            unit="m",
            withcoord=True,
            withdist=True,
            sort="ASC",
            count=10,
        )
        if not raw:
            return []
        pipe = self.client.pipeline(transaction=False)
        for entry in raw:
            pipe.hgetall(f"karta:speed:meta:{entry[0]}")
        metas = await pipe.execute()

        results: list[ApproachingSpeedZone] = []
        for entry, meta in zip(raw, metas, strict=False):
            sid, dist_m, (g_lon, g_lat) = entry
            if not meta:
                continue
            results.append(
                ApproachingSpeedZone(
                    id=int(sid),
                    zone_type=meta.get("zone_type", "awas_camera"),
                    road_name=meta.get("road_name") or None,
                    limit_kmh=int(meta.get("limit_kmh", 80)),
                    distance_meters=round(float(dist_m), 1),
                    coordinate=Coordinate(lat=float(g_lat), lon=float(g_lon)),
                )
            )
        return results

    async def geosearch_nearby_gantries(
        self, lat: float, lon: float, radius_m: float = 2000.0
    ) -> list[ApproachingGantry] | None:
        if not await self.client.exists("karta:geo:gantries"):
            return None
        raw = await self.client.geosearch(
            name="karta:geo:gantries",
            longitude=lon,
            latitude=lat,
            radius=radius_m,
            unit="m",
            withcoord=True,
            withdist=True,
            sort="ASC",
            count=5,
        )
        if not raw:
            return []
        pipe = self.client.pipeline(transaction=False)
        for entry in raw:
            pipe.hgetall(f"karta:gantry:meta:{entry[0]}")
        metas = await pipe.execute()

        results: list[ApproachingGantry] = []
        for entry, meta in zip(raw, metas, strict=False):
            gid, dist_m, (g_lon, g_lat) = entry
            if not meta:
                continue
            payments = [PaymentMethod(p) for p in json.loads(meta.get("accepted_payments", "[]"))]
            lanes = [TollLaneGuidance(**lane) for lane in json.loads(meta.get("lane_layout", "[]"))]
            results.append(
                ApproachingGantry(
                    gantry_id=gid,
                    name=meta.get("name", gid),
                    corridor_id=meta.get("corridor_id", ""),
                    system_type=meta.get("system_type", "open_barrier"),
                    distance_meters=round(float(dist_m), 1),
                    accepted_payments=payments,
                    lane_layout=lanes,
                    coordinate=Coordinate(lat=float(g_lat), lon=float(g_lon)),
                )
            )
        return results

    async def get_cached_json(self, key: str) -> dict[str, Any] | None:
        raw = await self.client.get(key)
        return json.loads(raw) if raw else None

    async def set_cached_json(self, key: str, value: dict[str, Any], ttl_seconds: int) -> None:
        await self.client.set(key, json.dumps(value), ex=ttl_seconds)

    async def record_traffic_probe_speed(self, osm_way_id: int, speed_kmh: int) -> None:
        await self.client.hset("karta:traffic:speeds", str(osm_way_id), str(max(5, min(speed_kmh, 140))))
