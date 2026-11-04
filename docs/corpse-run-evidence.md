# Hillsbrad to Alterac ghost corridor

Provenance: observed player trace.

The shipped data retains a forward, ghost-only guidance corridor with 15
vertices. Its approximate path is 1,200 yards and its computed travel cost is
197 seconds at 7 yards per second with the existing walking factor. The
vertices do not certify arbitrary ground chords, reverse traversal, or
living-character access. No personal identifiers, timestamps, SavedVariables
excerpts, or private file hashes are published.

The neutral input is `tools/fixtures/travel/observed-corridors.json`; regression
coverage is in `tests/run_ghost_travel.lua`.

## Verified-data application

The sparse trace remains a reference in `tests/fixtures/corpse-replay.tsv`, rather than a shipped routing corridor. Searches within 40 yards of the observed chords verified replacements for gaps 9 and 10, but gap 1 had no densely verified endpoint connector down to a 0.78125-yard grid. The complete corridor was therefore dropped. The corpse regression now requires a complete general-planner route, rejects blocked ground legs, and exercises forward steering along that route under both preferences. Ghost-only mode, reverse-edge and distant-join restrictions remain covered by the isolated corridor fixtures.

Passive walked-leg learning remains enabled. The terrain recorder accepts continuous living ground movement; it deliberately excludes ghosts, flights, swimming, falling and vehicles. A player can learn a living traversal of this area at runtime; a ghost run does not silently become living ground evidence.
