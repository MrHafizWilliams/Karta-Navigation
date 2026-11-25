from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, status

from karta_api.deps import AppContainer, get_container
from karta_api.models.users import (
    AuthSessionResponse,
    LoginRequest,
    RegisterRequest,
    SavedPlaceCreateRequest,
    SavedPlaceItem,
    SavedPlacesListResponse,
    UserProfile,
)

router = APIRouter(tags=["users & saved places"])


def _extract_bearer(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sign in required.",
        )
    parts = authorization.strip().split(" ", 1)
    if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1].strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header.",
        )
    return parts[1].strip()


async def _require_user(
    authorization: str | None = Header(default=None),
    c: AppContainer = Depends(get_container),
) -> tuple[UserProfile, str]:
    token = _extract_bearer(authorization)
    user = await c.user_repo.get_user_by_token(token)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired or invalid. Please sign in again.",
        )
    return user, token


@router.post("/auth/register", response_model=AuthSessionResponse, status_code=status.HTTP_201_CREATED)
async def register(
    req: RegisterRequest,
    c: AppContainer = Depends(get_container),
) -> AuthSessionResponse:
    try:
        return await c.user_repo.register_user(
            email=req.email,
            display_name=req.display_name,
            password=req.password,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc


@router.post("/auth/login", response_model=AuthSessionResponse)
async def login(
    req: LoginRequest,
    c: AppContainer = Depends(get_container),
) -> AuthSessionResponse:
    session = await c.user_repo.authenticate_user(
        email=req.email,
        password=req.password,
    )
    if session is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password.",
        )
    return session


@router.post("/auth/logout")
async def logout(
    auth: tuple[UserProfile, str] = Depends(_require_user),
    c: AppContainer = Depends(get_container),
) -> dict[str, bool]:
    _, token = auth
    await c.user_repo.revoke_session(token)
    return {"ok": True}


@router.get("/auth/me", response_model=UserProfile)
async def me(
    auth: tuple[UserProfile, str] = Depends(_require_user),
) -> UserProfile:
    user, _ = auth
    return user


@router.get("/saved-places", response_model=SavedPlacesListResponse)
async def list_saved_places(
    auth: tuple[UserProfile, str] = Depends(_require_user),
    c: AppContainer = Depends(get_container),
) -> SavedPlacesListResponse:
    user, _ = auth
    items = await c.user_repo.list_saved_places(user.id)
    return SavedPlacesListResponse(count=len(items), items=items)


@router.post("/saved-places", response_model=SavedPlaceItem, status_code=status.HTTP_201_CREATED)
async def create_saved_place(
    req: SavedPlaceCreateRequest,
    auth: tuple[UserProfile, str] = Depends(_require_user),
    c: AppContainer = Depends(get_container),
) -> SavedPlaceItem:
    user, _ = auth
    return await c.user_repo.create_saved_place(user_id=user.id, req=req)


@router.delete("/saved-places/{place_id}")
async def delete_saved_place(
    place_id: str,
    auth: tuple[UserProfile, str] = Depends(_require_user),
    c: AppContainer = Depends(get_container),
) -> dict[str, bool]:
    user, _ = auth
    deleted = await c.user_repo.delete_saved_place(user_id=user.id, place_id=place_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Saved place not found.")
    return {"deleted": True}
