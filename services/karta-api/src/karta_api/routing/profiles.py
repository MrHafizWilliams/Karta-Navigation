from __future__ import annotations

import copy
import json
from datetime import datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from karta_api.models.routing import RouteRequest, RoutingProfileId

KL_TZ = ZoneInfo("Asia/Kuala_Lumpur")


class CostingProfileRegistry:
    def __init__(self, profiles_path: Path) -> None:
        resolved = self._resolve_path(profiles_path)
        data = json.loads(resolved.read_text(encoding="utf-8"))
        self._profiles: dict[str, dict[str, Any]] = data["profiles"]

    @staticmethod
    def _resolve_path(candidate: Path) -> Path:
        if candidate.exists():
            return candidate
        for parent in Path(__file__).resolve().parents:
            fallback = parent / "infra" / "valhalla" / "costing_profiles.json"
            if fallback.exists():
                return fallback
        raise FileNotFoundError(
            f"Valhalla costing profiles not found at '{candidate}' or in ancestor infra/valhalla/."
        )

    def get_profile(self, profile_id: RoutingProfileId | str) -> dict[str, Any]:
        key = str(profile_id)
        if key not in self._profiles:
            raise KeyError(f"Unknown routing profile: {key}")
        return copy.deepcopy(self._profiles[key])

    def list_profiles(self) -> list[str]:
        return list(self._profiles.keys())

    def build_valhalla_route_payload(
        self,
        req: RouteRequest,
        override_profile: RoutingProfileId | None = None,
        alternates_override: int | None = None,
        exclude_locations: list[dict[str, float]] | None = None,
        exclude_polygons: list[list[list[float]]] | None = None,
    ) -> dict[str, Any]:
        """
        Builds a real Valhalla `/route` JSON request from Karta's RouteRequest and
        custom regional costing profile presets, optionally injecting live Phase 3
        crowdsourced road closures & severe hazard exclusions into Valhalla's dynamic costing.
        """
        effective_profile = override_profile or req.profile
        if override_profile is None and req.profile == RoutingProfileId.DRIVE_FASTEST:
            if req.avoid_highways:
                effective_profile = RoutingProfileId.DRIVE_NO_HIGHWAYS
            elif req.avoid_tolls:
                effective_profile = RoutingProfileId.DRIVE_AVOID_TOLLS

        preset = self.get_profile(effective_profile)
        valhalla_costing: str = preset["valhalla_costing"]
        costing_options: dict[str, Any] = preset.get("costing_options", {})

        # Apply granular user preference overrides on top of preset
        if valhalla_costing in ("auto", "motorcycle"):
            opts = costing_options.setdefault(valhalla_costing, {})
            opts["ignore_closures"] = False
            if req.avoid_tolls and override_profile != RoutingProfileId.DRIVE_FASTEST:
                opts["use_tolls"] = 0.0
                if valhalla_costing == "auto":
                    opts["toll_booth_cost"] = 300
                    opts["toll_booth_penalty"] = 3600
            if req.avoid_highways:
                opts["use_highways"] = 0.0
            if req.avoid_ferries:
                opts["use_ferry"] = 0.0

        locations = [{"lat": req.origin.lat, "lon": req.origin.lon, "type": "break"}]
        for wp in req.waypoints:
            locations.append({"lat": wp.lat, "lon": wp.lon, "type": "break"})
        locations.append({"lat": req.destination.lat, "lon": req.destination.lon, "type": "break"})

        alternates = alternates_override if alternates_override is not None else req.alternates

        payload: dict[str, Any] = {
            "locations": locations,
            "costing": valhalla_costing,
            "costing_options": costing_options,
            "units": "kilometers",
            "language": req.language,
            "alternates": alternates,
            "directions_options": {
                "units": "kilometers",
                "language": req.language,
                "narrative": True,
            },
        }

        if exclude_locations:
            payload["exclude_locations"] = exclude_locations[:50]
        if exclude_polygons:
            payload["exclude_polygons"] = exclude_polygons[:15]

        # Time-dependent routing (essential for GTFS transit + traffic predictions)
        if req.arrive_by is not None:
            local_dt = self._to_regional_local(req.arrive_by)
            payload["date_time"] = {"type": 2, "value": local_dt.strftime("%Y-%m-%dT%H:%M")}
        elif req.departure_time is not None or valhalla_costing == "multimodal":
            dt_val = req.departure_time or datetime.now(tz=KL_TZ)
            local_dt = self._to_regional_local(dt_val)
            payload["date_time"] = {"type": 1, "value": local_dt.strftime("%Y-%m-%dT%H:%M")}

        return payload

    @staticmethod
    def _to_regional_local(dt_val: datetime) -> datetime:
        if dt_val.tzinfo is None:
            return dt_val.replace(tzinfo=KL_TZ)
        return dt_val.astimezone(KL_TZ)
