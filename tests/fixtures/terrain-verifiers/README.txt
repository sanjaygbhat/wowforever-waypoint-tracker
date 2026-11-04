Historical terrain verifier source snapshots

Byte-for-byte copies from commit 40865c62b7d029e0167acf588094340c05f7660c
(the parent of the live-client CLI migration in a9a5341). These sources
match read_input_sha256 in docs/terrain-calibrated-final.json and preserve
the executable source behind that pinned-build evidence. Do not edit these
snapshots when maintaining tools/*.py or rewrite historical evidence hashes.

tests/check_terrain_artifacts.py hashes these files. Current verifier behavior
is tested separately by tests/check_terrain_offline.py (binary reader, terrain
classification, client selection) and tests/check_terrain_calibration.py
(strict cliff controls, precision and adaptive routing). Run those suites
alongside the artifact integrity check after changing current verifiers.
The archived CLI paths/defaults refer to the historical beta installation;
use tools/verify_legs_*.py for current offline verification.
