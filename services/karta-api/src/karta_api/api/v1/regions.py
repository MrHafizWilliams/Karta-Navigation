from __future__ import annotations

import re

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse

from karta_api.deps import AppContainer, get_container
from karta_api.models.regions import OfflineRegionListResponse

router = APIRouter(prefix="/regions", tags=["offline-regions"])

SAFE_SEGMENT_RE = re.compile(r"^[a-zA-Z0-9._-]+$")
ALLOWED_SUFFIXES = (".tar", ".sqlite", ".json")


@router.get("", response_model=OfflineRegionListResponse)
async def list_offline_regions(
    c: AppContainer = Depends(get_container),
) -> OfflineRegionListResponse:
    regions = await c.region_repo.list_offline_regions()
    return OfflineRegionListResponse(count=len(regions), regions=regions)


@router.get("/downloads/{region_id}/{filename}")
async def download_offline_pack_artifact(
    region_id: str,
    filename: str,
    c: AppContainer = Depends(get_container),
) -> FileResponse:
    if not SAFE_SEGMENT_RE.match(region_id) or not SAFE_SEGMENT_RE.match(filename):
        raise HTTPException(status_code=400, detail="Invalid artifact path segment.")
    if not filename.endswith(ALLOWED_SUFFIXES):
        raise HTTPException(status_code=403, detail="Artifact type not permitted.")

    base_dir = c.settings.offline_packs_dir.resolve()
    target = (base_dir / region_id / filename).resolve()
    if base_dir not in target.parents or not target.is_file():
        raise HTTPException(status_code=404, detail="Offline pack artifact not found.")

    return FileResponse(path=target, filename=filename, media_type="application/octet-stream")
