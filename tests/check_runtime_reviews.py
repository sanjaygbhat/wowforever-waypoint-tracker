"""Prove reviewed static findings cannot hide new, duplicate or changed sites."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

validator = Path(__file__).resolve().parents[1] / "tools/validate_runtime.py"
code = 'local level = UnitLevel("player")'
with tempfile.TemporaryDirectory(prefix="wt-runtime-reviews-") as directory:
    root = Path(directory)
    (root / "WaypointTracker").mkdir()
    path = root / "WaypointTracker/Review.lua"
    review = root / "reviews.json"
    review.write_text(json.dumps({"reviews": [{
        "file": "WaypointTracker/Review.lua", "api": "UnitLevel", "code": code,
        "reason": "Controlled unconfirmed policy finding for the gate test.",
        "source": "Synthetic fixture; no claim about live restrictions.",
    }]}))
    cases = [
        (code, True, True, "exact reviewed site"),
        ('-- line shifts are harmless\n' + code, True, True, "shifted reviewed site"),
        (code, False, False, "raw audit remains strict"),
        (code + '\nlocal other = UnitName("target")', True, False, "new site fails"),
        (code + "\n" + code, True, False, "duplicate site fails"),
        ('local level = tonumber(UnitLevel("player"))', True, False, "changed site fails"),
        ('local level = ns.Num(UnitLevel("player"))', True, False, "stale review fails"),
    ]
    for source, use_review, passes, label in cases:
        path.write_text(source)
        command = [sys.executable, "-B", str(validator), "secrets", "--root", str(root)]
        if use_review:
            command += ["--reviews", str(review)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        if (result.returncode == 0) != passes:
            raise AssertionError(label + "\n" + result.stdout + result.stderr)
    baseline = validator.with_name('validate_runtime_reviews.json')
    assert json.loads(baseline.read_text()) == {"reviews": []}, 'secret-review baseline must stay empty'
    for source, passes, label in [
        ('local level=ns.Num(UnitLevel("player"))\nlocal name=ns.Str(UnitName("target"))', True, 'empty baseline accepts guards'),
        (code, False, 'empty baseline rejects new numeric site'),
        ('local name=UnitName("target")', False, 'empty baseline rejects new string site'),
        ('local name=ns.Str(tostring(UnitName("target")))', False, 'empty baseline rejects late string guard'),
    ]:
        path.write_text(source)
        result = subprocess.run([sys.executable, '-B', str(validator), 'secrets', '--root', str(root),
                                 '--reviews', str(baseline)], capture_output=True, text=True, timeout=10)
        if (result.returncode == 0) != passes:
            raise AssertionError(label + '\n' + result.stdout + result.stderr)
print("Secret review gate: 11 passed, 0 failed")
