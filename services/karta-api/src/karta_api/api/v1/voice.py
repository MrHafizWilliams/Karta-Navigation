from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from karta_api.deps import AppContainer, get_container
from karta_api.models.commuter import (
    VOICE_CUE_SLOTS,
    CustomVoiceClipMeta,
    CustomVoiceClipUploadRequest,
    CustomVoicePackCreateRequest,
    CustomVoicePackRecord,
)
from karta_api.models.realtime import VoiceIntentRequest, VoiceIntentResponse
from karta_api.voice.intent_parser import parse_voice_intent

router = APIRouter(prefix="/voice", tags=["voice"])


@router.post("/parse-intent", response_model=VoiceIntentResponse)
async def parse_hands_free_voice_intent(req: VoiceIntentRequest) -> VoiceIntentResponse:
    """Low-latency EN / Bahasa Melayu / Manglish / Singlish speech-to-intent endpoint."""
    return parse_voice_intent(req.transcript, locale=req.locale)


@router.get("/packs", response_model=list[CustomVoicePackRecord])
async def list_custom_voice_packs(
    owner_token: str = Query("karta-driver-default"),
    include_audio: bool = Query(False),
    c: AppContainer = Depends(get_container),
) -> list[CustomVoicePackRecord]:
    return await c.community_repo.list_voice_packs(
        owner_token=owner_token, include_audio=include_audio
    )


@router.post("/packs", response_model=CustomVoicePackRecord)
async def create_custom_voice_pack(
    req: CustomVoicePackCreateRequest,
    c: AppContainer = Depends(get_container),
) -> CustomVoicePackRecord:
    return await c.community_repo.create_voice_pack(
        owner_token=req.owner_token,
        name=req.name,
        locale=req.locale,
        base_tts_voice=req.base_tts_voice,
    )


@router.put("/packs/{pack_id}/clips/{cue_key}", response_model=CustomVoiceClipMeta)
async def upload_custom_voice_clip(
    pack_id: str,
    cue_key: str,
    req: CustomVoiceClipUploadRequest,
    c: AppContainer = Depends(get_container),
) -> CustomVoiceClipMeta:
    if cue_key not in VOICE_CUE_SLOTS:
        raise HTTPException(
            status_code=422,
            detail=f"Unknown cue_key '{cue_key}'. Valid cues: {', '.join(VOICE_CUE_SLOTS)}",
        )
    try:
        return await c.community_repo.upsert_voice_clip(
            pack_id=pack_id,
            cue_key=cue_key,
            mime_type=req.mime_type,
            duration_ms=req.duration_ms,
            audio_base64=req.audio_base64,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid pack_id: {exc}") from exc


@router.delete("/packs/{pack_id}/clips/{cue_key}")
async def delete_custom_voice_clip(
    pack_id: str,
    cue_key: str,
    c: AppContainer = Depends(get_container),
) -> dict[str, object]:
    try:
        deleted = await c.community_repo.delete_voice_clip(pack_id, cue_key)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid pack_id: {exc}") from exc
    return {"deleted": deleted, "pack_id": pack_id, "cue_key": cue_key}
