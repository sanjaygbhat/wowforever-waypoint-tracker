#!/usr/bin/env python3
"""Preserve terrain verdicts when caching immutable chord geometry."""
import math
from pathlib import Path
import random
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from validate_terrain_geometry import compile_blocked_chords, terrain_blocked


def original_oracle(p, q, chords):
    # The pre-optimization audited predicate, retained as an independent oracle.
    for a, b in chords:
        if p[0] != a[0] or q[0] != a[0]:
            continue
        dx, dy = b[1]-a[1], b[2]-a[2]
        length2 = dx*dx+dy*dy
        if not length2:
            continue
        if not all(min(a[k], b[k])-3 <= point[k] <= max(a[k], b[k])+3
                   for point in (p, q) for k in (1, 2)):
            continue
        projected = []
        for point in (p, q):
            t = max(0, min(1, ((point[1]-a[1])*dx+(point[2]-a[2])*dy)/length2))
            projected.append((t, (point[1]-a[1]-t*dx)**2+(point[2]-a[2]-t*dy)**2))
        (tp, dp), (tq, dq) = projected
        if dp <= 9 and dq <= 9 and abs(tp-tq)*math.sqrt(length2) > 30:
            return True
    return False


class TerrainGeometry(unittest.TestCase):
    def test_distance_overlap_and_continent_boundaries(self):
        compiled = compile_blocked_chords([((0, 0, 0), (0, 100, 0))])
        for p, q, expected in [
            ((0, 10, 3), (0, 90, 3), True),
            ((0, 10, 3.000001), (0, 90, 3.000001), False),
            ((0, 0, 0), (0, 30, 0), False),
            ((0, 0, 0), (0, 30.000001, 0), True),
            ((0, -3, 0), (0, 31, 0), True),
            ((0, -3.000001, 0), (0, 31, 0), False),
            ((0, 50, 0), (0, 50, 0), False),
            ((0, 10, 0), (1, 90, 0), False),
            ((1, 10, 0), (1, 90, 0), False),
        ]:
            self.assertEqual(terrain_blocked(p, q, compiled), expected, (p, q))
            self.assertEqual(terrain_blocked(q, p, compiled), expected, (q, p))

    def test_cached_predicate_matches_original_oracle(self):
        rng = random.Random(16001)
        chords = [((0, 5, 5), (0, 5, 5))]  # Degenerate evidence stays inert.
        for _ in range(40):
            cont = rng.randrange(2)
            a = (cont, rng.uniform(-500, 500), rng.uniform(-500, 500))
            b = (cont, a[1]+rng.uniform(-100, 100), a[2]+rng.uniform(-100, 100))
            chords.extend([(a, b), (b, a)])
        compiled = compile_blocked_chords(chords)
        for _ in range(2000):
            a, b = rng.choice(chords)
            points = []
            for _ in range(2):
                t = rng.uniform(-.05, 1.05)
                points.append((a[0], a[1]+t*(b[1]-a[1])+rng.uniform(-4, 4),
                               a[2]+t*(b[2]-a[2])+rng.uniform(-4, 4)))
            p, q = points
            self.assertEqual(terrain_blocked(p, q, compiled), original_oracle(p, q, chords), (p, q))


if __name__ == "__main__":
    unittest.main()
