#!/usr/bin/env python3
"""Filter generated ATT spots against the pinned target client's UiMap IDs.

Run after build_att.lua; this is an idempotent, offline generation step.
Unsupported spots are quarantined, without inventing substitute coordinates.
Names and relationships survive; Data.lua supplies any existing valid fallback.
"""
import argparse
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", type=Path, default=ROOT / "WaypointTracker_Data/Curated.lua")
    ap.add_argument("--output", type=Path, default=ROOT / "WaypointTracker_Data/Curated.lua")
    ap.add_argument("--maps", type=Path, default=ROOT / "tools/fixtures/travel/UiMap.csv")
    args = ap.parse_args()
    with args.maps.open(encoding="utf-8-sig", newline="") as f:
        maps = {r["ID"] for r in csv.DictReader(f)}
    lines = args.input.read_text().splitlines()
    for i, line in enumerate(lines):
        f = line.split("\t")
        if f[0] not in ("N", "O"):
            continue
        ix = 6 if f[0] == "N" else 3
        keep = []
        for spot in f[ix].split(";"):
            if not spot:
                continue
            if spot.split(":", 1)[0] in maps:
                keep.append(spot)
            else:
                print("QUARANTINE %s%s %s: map absent from build 1.60.1.70338 UiMap" % (f[0], f[1], spot))
        f[ix] = ";".join(keep)
        lines[i] = "\t".join(f)
    args.output.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
