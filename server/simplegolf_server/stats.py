"""Career statistics worked out from saved scorecards.

Uses the same definitions as the game's local club (PlayerProfiles), so a
member's society stats read the same way as their local ones.
"""
from __future__ import annotations

import json
from typing import Iterable


def empty() -> dict:
    return {
        "rounds": 0, "holes": 0, "strokes": 0, "par": 0,
        "hole_in_ones": 0, "eagles": 0, "birdies": 0, "pars": 0, "bogeys": 0, "doubles": 0,
        "fairways": 0, "fairway_chances": 0, "greens": 0, "putts": 0,
        "drives": 0, "drive_total": 0.0, "longest_drive": 0.0,
        "best18": None, "best9": None, "scoring_average": None,
    }


def summarise(rounds: Iterable) -> dict:
    """rounds: rows with holes, total, par_total, played_at, course_name and the
    per-hole JSON arrays."""
    s = empty()
    for r in rounds:
        pars = json.loads(r["pars_json"])
        strokes = json.loads(r["strokes_json"])
        putts = json.loads(r["putts_json"])
        fairways = json.loads(r["fairways_json"])
        greens = json.loads(r["gir_json"])
        drives = json.loads(r["drives_json"])
        s["rounds"] += 1
        for par, score, putt, fairway, green, drive in zip(pars, strokes, putts, fairways, greens, drives):
            s["holes"] += 1
            s["strokes"] += score
            s["par"] += par
            s["putts"] += putt
            if score == 1:
                s["hole_in_ones"] += 1
            diff = score - par
            if diff <= -2:
                s["eagles"] += 1
            elif diff == -1:
                s["birdies"] += 1
            elif diff == 0:
                s["pars"] += 1
            elif diff == 1:
                s["bogeys"] += 1
            else:
                s["doubles"] += 1
            if fairway >= 0:
                s["fairway_chances"] += 1
                s["fairways"] += fairway
            if green:
                s["greens"] += 1
            if drive > 0:
                s["drives"] += 1
                s["drive_total"] += drive
                s["longest_drive"] = max(s["longest_drive"], drive)
        key = {18: "best18", 9: "best9"}.get(r["holes"])
        if key:
            best = s[key]
            to_par = r["total"] - r["par_total"]
            if best is None or to_par < best["strokes"] - best["par"]:
                s[key] = {"strokes": r["total"], "par": r["par_total"],
                          "course": r["course_name"], "date": r["played_at"][:10]}
    if s["holes"]:
        s["scoring_average"] = round((s["strokes"] - s["par"]) / s["holes"] * 18.0, 1)
    return s
