from __future__ import annotations

from typing import Any

import httpx


class ValhallaError(RuntimeError):
    def __init__(self, status_code: int, message: str, error_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message
        self.error_code = error_code


class ValhallaClient:
    def __init__(self, base_url: str, timeout_seconds: float = 20.0) -> None:
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds
        self._client: httpx.AsyncClient | None = None

    async def connect(self) -> None:
        self._client = httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout,
            headers={"Content-Type": "application/json"},
        )

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    @property
    def client(self) -> httpx.AsyncClient:
        if self._client is None:
            raise RuntimeError("ValhallaClient is not connected.")
        return self._client

    async def route(self, payload: dict[str, Any]) -> dict[str, Any]:
        return await self._post("/route", payload)

    async def trace_attributes(self, payload: dict[str, Any]) -> dict[str, Any]:
        return await self._post("/trace_attributes", payload)

    async def locate(self, lat: float, lon: float, costing: str = "auto") -> list[dict[str, Any]]:
        data = await self._post(
            "/locate",
            {"locations": [{"lat": lat, "lon": lon}], "costing": costing, "verbose": True},
        )
        return data if isinstance(data, list) else []

    async def status(self) -> dict[str, Any]:
        try:
            resp = await self.client.get("/status")
            resp.raise_for_status()
            return resp.json()
        except Exception as exc:
            return {"reachable": False, "error": str(exc)}

    async def _post(self, path: str, payload: dict[str, Any]) -> Any:
        try:
            resp = await self.client.post(path, json=payload)
        except httpx.RequestError as exc:
            raise ValhallaError(503, f"Valhalla routing engine unreachable: {exc}") from exc

        if resp.status_code >= 400:
            try:
                err_body = resp.json()
                msg = err_body.get("error", resp.text)
                code = err_body.get("error_code")
            except Exception:
                msg = resp.text
                code = None
            raise ValhallaError(resp.status_code, msg, error_code=code)

        return resp.json()
