from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from karta_api.models.common import Coordinate

SavedPlaceCategory = Literal["home", "work", "favorite", "landmark", "poi"]


class RegisterRequest(BaseModel):
    email: str = Field(..., min_length=4, max_length=254)
    display_name: str = Field(..., min_length=2, max_length=80)
    password: str = Field(..., min_length=6, max_length=128)

    @field_validator("email")
    @classmethod
    def _clean_email(cls, value: str) -> str:
        cleaned = value.strip().lower()
        if "@" not in cleaned or "." not in cleaned.split("@")[-1]:
            raise ValueError("Please enter a valid email address.")
        return cleaned

    @field_validator("display_name")
    @classmethod
    def _clean_name(cls, value: str) -> str:
        cleaned = value.strip()
        if len(cleaned) < 2:
            raise ValueError("Display name must be at least 2 characters.")
        return cleaned


class LoginRequest(BaseModel):
    email: str = Field(..., min_length=4, max_length=254)
    password: str = Field(..., min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def _clean_email(cls, value: str) -> str:
        return value.strip().lower()


class UserProfile(BaseModel):
    id: str
    email: str
    display_name: str
    saved_places_count: int = 0
    created_at: datetime


class AuthSessionResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_at: datetime
    user: UserProfile


class SavedPlaceCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=140)
    coordinate: Coordinate
    category: SavedPlaceCategory = "favorite"
    address_subtitle: str | None = Field(default=None, max_length=240)
    notes: str | None = Field(default=None, max_length=320)
    country_code: str | None = Field(default=None, max_length=2)
    poi_id: int | None = None

    @field_validator("name")
    @classmethod
    def _clean_name(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Place name cannot be empty.")
        return cleaned


class SavedPlaceItem(BaseModel):
    id: str
    name: str
    category: SavedPlaceCategory
    coordinate: Coordinate
    address_subtitle: str | None = None
    notes: str | None = None
    country_code: str | None = None
    poi_id: int | None = None
    created_at: datetime


class SavedPlacesListResponse(BaseModel):
    count: int
    items: list[SavedPlaceItem]
