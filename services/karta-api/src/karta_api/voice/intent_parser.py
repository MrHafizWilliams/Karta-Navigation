from __future__ import annotations

import re

from karta_api.models.realtime import HazardCategory, HazardSeverity, VoiceIntentResponse

_WAKE_PREFIX_RE = re.compile(
    r"^(?:hey\s+karta|ok\s+karta|hi\s+karta|karta\s+report|lapor\s+karta|karta)[,\s:]+",
    re.IGNORECASE,
)

# Ranked keyword patterns per hazard category (English + Bahasa Melayu + Manglish + Singlish)
_HAZARD_LEXICON: list[tuple[HazardCategory, str | None, float, list[str]]] = [
    (
        HazardCategory.ROAD_CLOSURE,
        "flash_flood",
        0.96,
        ["banjir kilat", "flash flood", "banjir", "flooded", "flooding", "air naik", "water ponding"],
    ),
    (
        HazardCategory.ROAD_CLOSURE,
        "closure",
        0.95,
        [
            "road closed",
            "road closure",
            "jalan tutup",
            "jalan ditutup",
            "lane closed",
            "lorong tutup",
            "tanah runtuh",
            "landslide",
            "sinkhole",
            "kerja jalan",
            "roadworks",
            "road work",
            "construction blocking",
            "blocked road",
        ],
    ),
    (
        HazardCategory.ACCIDENT,
        "collision",
        0.95,
        [
            "accident",
            "eksiden",
            "kemalangan",
            "car crash",
            "crash",
            "pileup",
            "pile up",
            "collision",
            "langgar",
            "terbalik",
            "overturned",
            "lorry overturn",
            "bang",
        ],
    ),
    (
        HazardCategory.POLICE,
        "roadblock",
        0.95,
        ["roadblock", "road block", "sekatan jalan", "operasi", "ops", "jpj"],
    ),
    (
        HazardCategory.POLICE,
        "speed_trap",
        0.94,
        [
            "speed trap",
            "perangkap laju",
            "traffic police",
            "tp ahead",
            "tp ",
            "police",
            "polis",
            "abang polis",
            "mata-mata",
            "mata mata",
            "awas camera",
            "hidden police",
            "speed camera",
        ],
    ),
    (
        HazardCategory.HIDDEN_VEHICLE,
        "stalled_vehicle",
        0.92,
        [
            "hidden vehicle",
            "stalled car",
            "stalled vehicle",
            "broken down",
            "breakdown",
            "kereta rosak",
            "lori rosak",
            "stopped car",
            "vehicle on shoulder",
            "car on shoulder",
            "stopped vehicle",
            "motor rosak",
        ],
    ),
    (
        HazardCategory.ROAD_DEBRIS,
        "debris",
        0.92,
        [
            "road debris",
            "debris",
            "object on road",
            "objek atas jalan",
            "pokok tumbang",
            "fallen tree",
            "tree branch",
            "tayar pecah",
            "tire on road",
            "tyre on road",
            "oil spill",
            "minyak tumpah",
            "obstruction",
            "barang jatuh",
        ],
    ),
    (
        HazardCategory.POTHOLE,
        "pothole",
        0.93,
        [
            "pothole",
            "pot hole",
            "lubang jalan",
            "jalan berlubang",
            "lubang besar",
            "lubang",
            "road hole",
            "deep hole",
            "uneven road",
        ],
    ),
]

_CANCEL_TERMS = ("cancel", "batal", "batalkan", "nevermind", "never mind", "stop report", "tak jadi")
_CONFIRM_TERMS = ("still there", "masih ada", "yes still", "confirm hazard", "confirm", "ada lagi")
_CLEAR_TERMS = ("cleared", "already cleared", "dah clear", "gone", "no longer there", "tak ada", "tiada", "all clear")
_REROUTE_TERMS = ("accept reroute", "take faster route", "reroute now", "tukar laluan", "ikut jalan baru", "yes reroute")

_OPPOSITE_TERMS = (
    "opposite side",
    "opposite direction",
    "other side",
    "arah bertentangan",
    "sebelah sana",
    "bertentangan",
)
_HIGH_SEVERITY_TERMS = ("major", "teruk", "bad", "heavy", "severe", "huge", "besar", "jam teruk", "massive", "pileup")
_LOW_SEVERITY_TERMS = ("minor", "small", "sikit", "kecil", "light")

_LANE_PATTERNS: list[tuple[str, tuple[str, ...]]] = [
    ("right_lane", ("fast lane", "right lane", "lorong kanan", "lorong laju")),
    ("left_lane", ("left lane", "slow lane", "lorong kiri", "lorong perlahan")),
    ("middle_lane", ("middle lane", "center lane", "lorong tengah")),
    ("emergency_lane", ("emergency lane", "shoulder", "lorong kecemasan", "bahu jalan")),
]

_HIGHWAY_REF_RE = re.compile(
    r"\b(PLUS|NKVE|LDP|DUKE|AKLEH|KESAS|SPRINT|ELITE|MEX|SUKE|SPE|LPT|NPE|BESRAYA|LEKAS|SKVE|WCE|PIE|AYE|CTE|ECP|BKE|SLE|TPE|KPE|MCE|NSC|E\d{1,2})\b",
    re.IGNORECASE,
)

_CONFIRMATION_LABELS: dict[HazardCategory, tuple[str, str]] = {
    HazardCategory.POLICE: ("Police presence", "Kehadiran polis"),
    HazardCategory.ACCIDENT: ("Accident", "Kemalangan"),
    HazardCategory.POTHOLE: ("Pothole", "Lubang jalan"),
    HazardCategory.HIDDEN_VEHICLE: ("Stopped vehicle", "Kenderaan rosak"),
    HazardCategory.ROAD_DEBRIS: ("Road debris", "Objek di atas jalan"),
    HazardCategory.ROAD_CLOSURE: ("Road closure", "Penutupan jalan"),
}


def parse_voice_intent(transcript: str, locale: str = "en-MY") -> VoiceIntentResponse:
    """
    Deterministic, sub-5ms speech-to-intent parser tuned for Malaysian, Singaporean,
    and Bruneian English + Bahasa Melayu + Manglish/Singlish road terminology.
    """
    raw = transcript.strip()
    cleaned = _WAKE_PREFIX_RE.sub("", raw).strip()
    low = f" {re.sub(r'[^a-z0-9\\s-]', ' ', cleaned.lower())} "
    low = re.sub(r"\s+", " ", low)

    is_bm = locale.lower().startswith("ms") or any(
        w in low for w in (" ada ", " jalan ", " lorong ", " kereta ", " polis ", " kemalangan ", " banjir ", " lubang ", " batal ", " dah ")
    )

    # 1. Check quick control/cancellation commands first
    for term in _CANCEL_TERMS:
        if f" {term} " in low:
            return VoiceIntentResponse(
                intent="cancel",
                confidence=0.96,
                confirmation_speech="Laporan dibatalkan." if is_bm else "Report cancelled.",
                matched_terms=[term],
                normalized_transcript=cleaned,
            )

    for term in _REROUTE_TERMS:
        if f" {term} " in low:
            return VoiceIntentResponse(
                intent="accept_reroute",
                confidence=0.95,
                confirmation_speech="Menukar ke laluan lebih pantas." if is_bm else "Switching to the faster route now.",
                matched_terms=[term],
                normalized_transcript=cleaned,
            )

    # 2. Check hazard report categories
    matched_category: HazardCategory | None = None
    matched_subtype: str | None = None
    best_conf = 0.0
    matched_terms: list[str] = []

    for cat, subtype, base_conf, keywords in _HAZARD_LEXICON:
        for kw in keywords:
            needle = f" {kw.strip()} "
            if needle in low:
                matched_category = cat
                matched_subtype = subtype
                best_conf = base_conf
                matched_terms.append(kw.strip())
                break
        if matched_category is not None:
            break

    if matched_category is not None:
        direction = "opposite" if any(t in low for t in _OPPOSITE_TERMS) else "ahead"
        severity = HazardSeverity.MEDIUM
        if matched_category == HazardCategory.ROAD_CLOSURE or any(t in low for t in _HIGH_SEVERITY_TERMS):
            severity = HazardSeverity.HIGH
        elif any(t in low for t in _LOW_SEVERITY_TERMS):
            severity = HazardSeverity.LOW

        lane_hint: str | None = None
        for lane_id, patterns in _LANE_PATTERNS:
            if any(p in low for p in patterns):
                lane_hint = lane_id
                break

        road_match = _HIGHWAY_REF_RE.search(cleaned)
        road_hint = road_match.group(1).upper() if road_match else None

        en_label, bm_label = _CONFIRMATION_LABELS[matched_category]
        dir_phrase_en = "on the opposite side" if direction == "opposite" else "ahead"
        dir_phrase_bm = "di arah bertentangan" if direction == "opposite" else "di hadapan"
        lane_en = f" in the {lane_hint.replace('_', ' ')}" if lane_hint else ""
        road_suffix = f" on {road_hint}" if road_hint else ""

        if is_bm:
            speech = f"{bm_label} dilaporkan {dir_phrase_bm}. Terima kasih!"
        else:
            sev_prefix = "Major " if severity == HazardSeverity.HIGH and matched_category == HazardCategory.ACCIDENT else ""
            speech = f"{sev_prefix}{en_label} reported {dir_phrase_en}{lane_en}{road_suffix}. Thank you."

        return VoiceIntentResponse(
            intent="report_hazard",
            confidence=best_conf,
            hazard_category=matched_category,
            subtype=matched_subtype,
            severity=severity,
            direction=direction,
            lane_hint=lane_hint,
            road_hint=road_hint,
            confirmation_speech=speech,
            matched_terms=matched_terms,
            normalized_transcript=cleaned,
        )

    # 3. Check hazard confirmation / cleared responses
    for term in _CONFIRM_TERMS:
        if f" {term} " in low:
            return VoiceIntentResponse(
                intent="confirm_hazard",
                confidence=0.92,
                confirmation_speech="Disahkan masih ada." if is_bm else "Confirmed hazard is still there.",
                matched_terms=[term],
                normalized_transcript=cleaned,
            )

    for term in _CLEAR_TERMS:
        if f" {term} " in low:
            return VoiceIntentResponse(
                intent="clear_hazard",
                confidence=0.92,
                confirmation_speech="Terima kasih, tanda bahaya dikemas kini." if is_bm else "Marked hazard as cleared. Thanks!",
                matched_terms=[term],
                normalized_transcript=cleaned,
            )

    return VoiceIntentResponse(
        intent="unknown",
        confidence=0.0,
        confirmation_speech=(
            "Maaf, tidak jelas. Cuba sebut 'kemalangan', 'polis', 'lubang jalan', atau 'jalan tutup'."
            if is_bm
            else "Didn't catch that hazard. Try saying police, accident, pothole, debris, stalled car, or road closed."
        ),
        matched_terms=[],
        normalized_transcript=cleaned,
    )
