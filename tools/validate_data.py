#!/usr/bin/env python3
"""Run all required, offline data gates, reporting every failed validator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--lua", default=os.environ.get("LUA51") or shutil.which("lua5.1"))
    args = ap.parse_args()
    if not args.lua:
        ap.error("Lua 5.1 is required; pass --lua PATH or set LUA51")
    failed = []
    fixture_root = ROOT / "tools/fixtures"
    manifest = json.loads((fixture_root / "manifest.json").read_text())
    for name, info in manifest.items():
        p = fixture_root / name
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != info["sha256"]:
            print("FAIL audit fixture missing or changed: " + name, flush=True)
            failed.append("fixture " + name)
    commands = [
        [sys.executable, "tools/validate_taxi_transport.py"],
        [sys.executable, "tools/validate_terrain_geometry.py", "--lua", args.lua],
        [sys.executable, "tests/check_sanctum_area.py"],
        # Exercises validate_font_coverage's cmap/scanner without client assets.
        [sys.executable, "-B", "tests/check_font_coverage.py"],
        [sys.executable, "tools/validate_quest_data.py"],
        [args.lua, "tests/check_taxi_transport.lua"],
        [args.lua, "tests/check_quest_provenance.lua"],
        [args.lua, "tests/check_reference_data.lua"],
    ]
    for command in commands:
        print("Data gate: " + " ".join(command), flush=True)
        start = time.monotonic()
        try:
            result = subprocess.run(command, cwd=ROOT, timeout=60)
            if result.returncode:
                failed.append(command[1])
        except subprocess.TimeoutExpired:
            print("FAIL data validator exceeded 60 seconds: " + command[1], flush=True)
            failed.append(command[1])
        print("Data gate time: %.2fs" % (time.monotonic() - start), flush=True)
    print("Data audit: %d gates, %d failures%s" % (
        len(commands), len(failed), "; " + ", ".join(failed) if failed else ""), flush=True)
    return int(bool(failed))


if __name__ == "__main__":
    sys.exit(main())
