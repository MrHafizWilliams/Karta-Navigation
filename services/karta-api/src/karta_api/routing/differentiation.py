from __future__ import annotations

from collections import Counter

from karta_api.models.routing import CandidateRoute

# Valhalla maneuver types that represent start/destination/continuation (not active turns)
_NON_TURN_MANEUVER_TYPES = {0, 1, 2, 3, 4, 5, 6, 8}


def format_compact_duration(seconds: float) -> str:
    total_min = max(1, int(round(seconds / 60.0)))
    if total_min < 60:
        return f"{total_min} min"
    hrs, mins = divmod(total_min, 60)
    return f"{hrs}h {mins}m" if mins > 0 else f"{hrs}h"


def count_route_turns(route: CandidateRoute) -> int:
    turns = 0
    for leg in route.legs:
        for man in leg.maneuvers:
            if man.type not in _NON_TURN_MANEUVER_TYPES:
                turns += 1
    return turns


def extract_primary_corridor(route: CandidateRoute) -> str | None:
    """Identifies the longest-distance highway or arterial name along a route."""
    street_dist: Counter[str] = Counter()
    for leg in route.legs:
        for man in leg.maneuvers:
            if not man.street_names:
                continue
            primary_name = man.street_names[0].strip()
            if not primary_name:
                continue
            weight = int(round(max(0.1, man.distance_km) * 1000))
            if man.highway:
                weight = int(weight * 1.4)
            street_dist[primary_name] += weight
    if not street_dist:
        return None
    top_name, _ = street_dist.most_common(1)[0]
    return f"via {top_name}"


def differentiate_candidate_routes(candidates: list[CandidateRoute]) -> list[CandidateRoute]:
    """
    Tags every single-destination candidate route with scannable differentiation
    labels ('Fastest • 38 min', 'Fewer Turns', 'Avoids Highway', 'Shortest',
    'Alternative') plus maneuver counts and primary corridor names.
    """
    if not candidates:
        return candidates

    turn_counts = [count_route_turns(r) for r in candidates]
    corridors = [extract_primary_corridor(r) for r in candidates]

    fastest_idx = min(range(len(candidates)), key=lambda i: candidates[i].duration_seconds)
    fastest = candidates[fastest_idx]
    fastest_dur = fastest.duration_seconds
    fastest_turns = turn_counts[fastest_idx]

    fewest_turns_idx = min(
        range(len(candidates)), key=lambda i: (turn_counts[i], candidates[i].duration_seconds)
    )
    shortest_idx = min(
        range(len(candidates)),
        key=lambda i: (candidates[i].distance_km, candidates[i].duration_seconds),
    )

    used_kinds: set[str] = set()
    enriched: list[CandidateRoute] = []

    for idx, route in enumerate(candidates):
        turns = turn_counts[idx]
        corridor = corridors[idx]
        eta_delta = round(route.duration_seconds - fastest_dur, 1)
        dur_str = format_compact_duration(route.duration_seconds)
        highlights: list[str] = []

        if corridor:
            highlights.append(corridor)

        if idx == fastest_idx:
            badge_kind = "fastest"
            primary_tag = f"Fastest • {dur_str}"
            if route.live_traffic_delay_seconds >= 60:
                highlights.append(f"+{int(round(route.live_traffic_delay_seconds / 60))}m traffic")
        elif route.profile_used == "drive_no_highways" and "avoids_highway" not in used_kinds:
            badge_kind = "avoids_highway"
            primary_tag = "Avoids Highway"
        elif not route.has_highways and "avoids_highway" not in used_kinds:
            badge_kind = "avoids_highway"
            primary_tag = "Avoids Highway"
        elif (
            idx == fewest_turns_idx
            and turns < fastest_turns
            and "fewer_turns" not in used_kinds
        ):
            badge_kind = "fewer_turns"
            diff_turns = fastest_turns - turns
            primary_tag = "Fewer Turns"
            highlights.append(f"{diff_turns} fewer {'turn' if diff_turns == 1 else 'turns'}")
        elif (
            idx == shortest_idx
            and route.distance_km < fastest.distance_km - 0.4
            and "shortest" not in used_kinds
        ):
            badge_kind = "shortest"
            primary_tag = f"Shortest • {route.distance_km:.1f} km"
        elif not route.has_highways:
            badge_kind = "avoids_highway"
            primary_tag = "Avoids Highway"
        elif turns <= fastest_turns - 2:
            badge_kind = "fewer_turns"
            primary_tag = "Fewer Turns"
        else:
            badge_kind = "balanced"
            delta_min = max(1, int(round(eta_delta / 60.0)))
            primary_tag = f"Alternative • +{delta_min} min"

        used_kinds.add(badge_kind)

        if idx != fastest_idx and eta_delta >= 60:
            highlights.append(f"+{int(round(eta_delta / 60.0))} min vs fastest")

        enriched.append(
            route.model_copy(
                update={
                    "summary_label": primary_tag,
                    "ux_primary_tag": primary_tag,
                    "ux_badge_kind": badge_kind,
                    "ux_highlights": highlights[:3],
                    "turn_count": turns,
                    "primary_corridor_name": corridor,
                    "eta_delta_seconds": eta_delta,
                }
            )
        )

    return enriched
