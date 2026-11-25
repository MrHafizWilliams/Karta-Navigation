from __future__ import annotations

from pydantic import BaseModel, Field


class Coordinate(BaseModel):
    lat: float = Field(..., ge=-90.0, le=90.0)
    lon: float = Field(..., ge=-180.0, le=180.0)


class BoundingBox(BaseModel):
    min_lon: float = Field(..., ge=-180.0, le=180.0)
    min_lat: float = Field(..., ge=-90.0, le=90.0)
    max_lon: float = Field(..., ge=-180.0, le=180.0)
    max_lat: float = Field(..., ge=-90.0, le=90.0)


class CurrencyAmount(BaseModel):
    currency_code: str = Field(..., description="ISO 4217 code: MYR, SGD, BND")
    amount_minor: int = Field(..., ge=0, description="Integer minor units (sen / cents)")
    formatted: str = Field(..., description="Localized formatted string, e.g. RM 14.80, $2.00, B$3.00")


class CountryContext(BaseModel):
    iso_a2: str = Field(..., description="ISO 3166-1 alpha-2: MY, SG, BN")
    name: str
    currency_code: str
    currency_symbol: str
    driving_side: str = "left"
    speed_unit: str = "kmh"
    timezone_iana: str
