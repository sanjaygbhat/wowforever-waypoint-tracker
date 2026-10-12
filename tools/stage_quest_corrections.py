#!/usr/bin/env python3
"""Stage reviewed WTL1 corrections in a NEW directory; never edit inputs.

Run after ATT generation and filter_curated_maps.py. The TSV is an explicit
compare-and-set curation input, using the existing WTL1 field encoding.
No network, game, git commands, cache writes, or third-party dependencies.
"""
import argparse
import csv
import difflib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FIELDS = {"N": {"spots": 6, "fac": 7}, "O": {"spots": 3},
          "Q": {"giver": 4, "ender": 5, "area": 6}}


def corrected(source, corrections):
    match = re.search(r"WaypointTrackerData\.curated\s*=\s*\[==\[(.*?)\]==\]", source, re.S)
    if not match:
        raise ValueError("Expected one curated WTL1 long-string block")
    lines = match[1].splitlines()
    records = {}
    for ix, line in enumerate(lines):
        fields = line.split("\t")
        if fields[0] in FIELDS and len(fields) > 1:
            key = fields[0] + fields[1]
            if key in records:
                raise ValueError("Duplicate input record " + key)
            records[key] = ix
    additions = set()
    for c in corrections:
        if c["file"] != "Curated.lua" or c["verdict"] != "CONFIRMED":
            raise ValueError("Unsupported correction: " + str(c))
        key = c["record"]
        if c["field"] == "record":
            value = json.loads(c["value"])
            if key in records or c["expected"] != "ABSENT":
                raise ValueError("New definition already exists: " + key)
            if value[0] != "O" or len(value) != 4 or value[0] + value[1] != key or value[3]:
                raise ValueError("Only reviewed object identities without spots may be added")
            if any("\t" in x or "\n" in x or "\r" in x for x in value):
                raise ValueError("Invalid WTL1 field")
            records[key] = len(lines)
            lines.append("\t".join(value))
            additions.add(key)
            continue
        if key not in records:
            raise ValueError("Record missing: " + key)
        fields = lines[records[key]].split("\t")
        ix = FIELDS[key[0]][c["field"]]
        if fields[ix] != c["expected"]:
            raise ValueError("Stale expected value for %s.%s: %r != %r" %
                             (key, c["field"], fields[ix], c["expected"]))
        fields[ix] = c["value"]
        lines[records[key]] = "\t".join(fields)
    body = "\n".join(lines) + "\n"
    return source[:match.start(1)] + body + source[match.end(1):], additions


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", type=Path, default=ROOT)
    ap.add_argument("--corrections", type=Path, default=ROOT / "tools/corrections_quests.tsv")
    ap.add_argument("--output", required=True, type=Path,
                    help="must not exist; staged files and patch are created here")
    args = ap.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    if output.exists() or output == repo or repo in output.parents:
        raise ValueError("Use an absent staging directory outside the source repository")
    with args.corrections.open(encoding="utf-8", newline="") as handle:
        corrections = list(csv.DictReader(handle, delimiter="\t"))
    old = (repo / "WaypointTracker_Data/Curated.lua").read_text()
    new, additions = corrected(old, corrections)
    old_ex = (repo / "tools/nonroutable_references.tsv").read_text()
    kept, removed = [], []
    for line in old_ex.splitlines():
        fields = line.split("\t")
        if not line.startswith("#") and len(fields) >= 4 and fields[3] in additions:
            removed.append(line)
        else:
            kept.append(line)
    new_ex = "\n".join(kept) + "\n"
    # Inputs fully checked before creating output; all writes use exclusive mode.
    output.mkdir(parents=True, exist_ok=False)
    patch = []
    for rel, before, after in (("WaypointTracker_Data/Curated.lua", old, new),
                               ("tools/nonroutable_references.tsv", old_ex, new_ex)):
        dest = output / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        with dest.open("x") as handle:
            handle.write(after)
        patch.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                         fromfile="a/" + rel, tofile="b/" + rel))
    with (output / "corrections.patch").open("x") as handle:
        handle.writelines(patch)
    with (output / "resolved-reference-exceptions.tsv").open("x") as handle:
        handle.write("\n".join(removed) + "\n")
    print("Staged %d corrections, %d named objects, %d resolved reference exceptions in %s" %
          (len(corrections), len(additions), len(removed), output))


if __name__ == "__main__":
    main()
