from karta_api.tolls.currency import (
    aggregate_totals,
    format_currency_minor,
    format_multi_currency_display,
)


def test_regional_currency_formatting() -> None:
    assert format_currency_minor("MYR", 3444).formatted == "RM 34.44"
    assert format_currency_minor("SGD", 200).formatted == "$2.00"
    assert format_currency_minor("BND", 300).formatted == "B$3.00"
    assert format_currency_minor("MYR", 0).formatted == "RM 0.00"


def test_multi_currency_aggregation_and_display() -> None:
    charges = [
        format_currency_minor("SGD", 200),
        format_currency_minor("MYR", 2000),
        format_currency_minor("MYR", 3444),
        format_currency_minor("BND", 300),
    ]
    totals = aggregate_totals(charges)
    assert [(t.currency_code, t.amount_minor, t.formatted) for t in totals] == [
        ("MYR", 5444, "RM 54.44"),
        ("SGD", 200, "$2.00"),
        ("BND", 300, "B$3.00"),
    ]
    assert format_multi_currency_display(totals) == "RM 54.44 + $2.00 + B$3.00"
    assert format_multi_currency_display([]) == "Free"
