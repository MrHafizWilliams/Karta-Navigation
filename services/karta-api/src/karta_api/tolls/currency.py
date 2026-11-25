from __future__ import annotations

from collections import defaultdict
from collections.abc import Iterable

from karta_api.models.common import CurrencyAmount

# Canonical regional formatting rules derived from GEMINI.md:
#   MYR -> "RM 14.80"
#   SGD -> "$2.00"
#   BND -> "B$3.00"
CURRENCY_SPEC: dict[str, tuple[str, bool, int]] = {
    "MYR": ("RM", True, 2),
    "SGD": ("$", False, 2),
    "BND": ("B$", False, 2),
}

CANONICAL_ORDER = ("MYR", "SGD", "BND")


def format_currency_minor(currency_code: str, amount_minor: int) -> CurrencyAmount:
    code = currency_code.upper().strip()
    symbol, prefix_space, decimals = CURRENCY_SPEC.get(code, (f"{code}", True, 2))
    major = amount_minor / (10**decimals)
    spacer = " " if prefix_space else ""
    formatted = f"{symbol}{spacer}{major:,.{decimals}f}"
    return CurrencyAmount(
        currency_code=code,
        amount_minor=amount_minor,
        formatted=formatted,
    )


def aggregate_totals(charges: Iterable[CurrencyAmount]) -> list[CurrencyAmount]:
    buckets: dict[str, int] = defaultdict(int)
    for c in charges:
        buckets[c.currency_code.upper()] += c.amount_minor

    ordered_codes = [c for c in CANONICAL_ORDER if c in buckets]
    ordered_codes.extend(sorted(c for c in buckets if c not in CANONICAL_ORDER))
    return [format_currency_minor(code, buckets[code]) for code in ordered_codes if buckets[code] > 0]


def format_multi_currency_display(totals: list[CurrencyAmount]) -> str:
    if not totals:
        return "Free"
    return " + ".join(t.formatted for t in totals)
