#!/usr/bin/env python3
"""Preflight: lay every sheet's rows and columns over each other.

Errors (block the build):
  - a row missing a declared column, or a cell left empty
  - a reference between sheets that does not resolve
  - duplicate row keys
Open checkboxes (do not block, but the row is unfinished):
  - any row whose 'verified' cell is not a final state for that sheet

Exit code 0 = clean (build may run), 1 = errors.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHEETS = ROOT / "sheets"

# Which 'verified' values count as done, per sheet.
FINAL = {
    "ats_channels": {"game"},
    "ats_events": {"game"},
    "crash_rules": {"tuned"},
    "obstacles": {"game"},
    "rigs": {"game"},
    "protocol": {"game"},
    "beamng_hooks": {"game"},
    "world": {"game"},
    "install": {"installed"},
}


def load():
    sheets = {}
    for path in sorted(SHEETS.glob("*.json")):
        data = json.loads(path.read_text())
        sheets[data["sheet"]] = data
    return sheets


def key_of(row):
    return row.get("id") or f'{row.get("msg")}.{row.get("field")}'


def empty(v):
    return v is None or (isinstance(v, str) and v.strip() == "")


def main():
    sheets = load()
    errors, open_boxes = [], []

    for name, sheet in sheets.items():
        cols = list(sheet["columns"].keys())
        seen = set()
        for row in sheet["rows"]:
            k = key_of(row)
            if k in seen:
                errors.append(f"{name}: duplicate row '{k}'")
            seen.add(k)
            for c in cols:
                if c not in row or empty(row[c]):
                    errors.append(f"{name}.{k}: cell '{c}' is unfilled")
            extra = set(row) - set(cols)
            if extra:
                errors.append(f"{name}.{k}: columns not declared in sheet: {sorted(extra)}")
            if row.get("verified") not in FINAL.get(name, set()):
                open_boxes.append(f"{name}.{k}: verified={row.get('verified')}")

    ids = lambda s: {key_of(r) for r in sheets[s]["rows"]}
    channel_ids, event_ids = ids("ats_channels"), ids("ats_events")

    # protocol.source -> ats_channels / ats_events / computed:*
    computed_ok = {"paused", "impact_kmh", "peak_g", "damage_delta", "trigger", "wear_total"}
    for r in sheets["protocol"]["rows"]:
        src = r["source"]
        if src.startswith("computed:"):
            if src.split(":", 1)[1] not in computed_ok:
                errors.append(f"protocol.{key_of(r)}: unknown computed source '{src}'")
        elif src not in channel_ids | event_ids:
            errors.append(f"protocol.{key_of(r)}: source '{src}' not in ats_channels/ats_events")

    # rigs.needs -> ats_channels / ats_events / none
    for r in sheets["rigs"]["rows"]:
        if r["needs"] != "none" and r["needs"] not in channel_ids | event_ids:
            errors.append(f"rigs.{r['id']}: needs '{r['needs']}' does not resolve")

    # obstacles must tile 0..999 km/h without gaps or overlaps
    tiers = sorted(sheets["obstacles"]["rows"], key=lambda r: r["min_kmh"])
    edge = 0
    for t in tiers:
        if t["min_kmh"] != edge:
            errors.append(f"obstacles.{t['id']}: starts at {t['min_kmh']} km/h, expected {edge}")
        edge = t["max_kmh"]
    if edge != 999:
        errors.append(f"obstacles: last tier ends at {edge}, expected 999")

    # every channel/event is used by the protocol or a crash rule
    used = {r["source"] for r in sheets["protocol"]["rows"]} | {"accel", "wear_cabin", "wear_chassis",
            "wear_engine", "trailer_wear_body", "fine_offence"}
    for cid in channel_ids | event_ids:
        if cid not in used:
            errors.append(f"ats_channels/ats_events.{cid}: read but never used")

    # install refs and component <-> mapping pairing
    install_ids = ids("install")
    comps = {r["value"]["id"] for r in sheets["install"]["rows"] if r["kind"] == "component"}
    for r in sheets["install"]["rows"]:
        if r["refs"] != "none" and r["refs"] not in install_ids:
            errors.append(f"install.{r['id']}: refs '{r['refs']}' does not resolve")
        if r["kind"] == "mapping" and r["value"]["component"] not in comps:
            errors.append(f"install.{r['id']}: maps unknown component '{r['value']['component']}'")
    mapped = {r["value"]["component"] for r in sheets["install"]["rows"] if r["kind"] == "mapping"}
    for c in comps - mapped:
        errors.append(f"install: component '{c}' has no mapping (its files would not be installed)")

    # crash_rules constants the code needs
    needed = {"window_s", "min_speed_drop_kmh", "min_peak_g", "min_damage_delta", "cooldown_s",
              "repair_drop", "send_rate_hz", "udp_port"}
    missing = needed - ids("crash_rules")
    for m in sorted(missing):
        errors.append(f"crash_rules: constant '{m}' missing")
    world_needed = {"level_path", "obstacle_life_s", "stale_tick_s"}
    for m in sorted(world_needed - ids("world")):
        errors.append(f"world: setting '{m}' missing")

    print(f"Preflight over {len(sheets)} sheets, "
          f"{sum(len(s['rows']) for s in sheets.values())} rows")
    for e in errors:
        print("  ERROR", e)
    print(f"{len(errors)} error(s)")
    print(f"{len(open_boxes)} open checkbox(es) (rows not yet verified in the running game):")
    for o in open_boxes:
        print("  [ ]", o)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
