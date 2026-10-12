# Offline data audit

`lua5.1 tests/run_tests.lua` runs the data gates on every invocation, alongside
the runtime gates. The existing CI `tests/run_*.lua` glob also discovers
`tests/run_data_audits.lua`. To inspect only data, run:

```sh
python3 tools/validate_data.py --lua lua5.1
lua5.1 tests/run_audit_planner.lua --details
```

Every gate exits nonzero on a confirmed failure. All inputs are local and
deterministic; each validator has a 60-second timeout. The terrain Lua helper
requires generated stdin and is invoked by its Python validator, rather than
as a standalone test. The optional InFlight timing comparison is excluded
from the required gate because that independent dataset is not bundled; the
ordinary client path, geometry, fare and runtime checks remain required.

## Pinned sources and generation

`tools/fixtures/manifest.json` records fixture checksums and source provenance.
Client tables use build **1.60.1.70338**, extracted from
[Wago's client tables](https://wago.tools/db2/UiMap?build=1.60.1.70338).
Item fixtures preserve the selected rows and necessary columns; the previous
build's complete ItemSparse ID set detects the 24 newly added items.
Travel extracts include the complete taxi path inventory. These are existing
cached extractions, not a fresh online fetch or a physical terrain survey.

Names and Classic spawn/quest provenance use
[pfQuest 104f35678ca39ab1fb78b655f815cc7016f5e0c8](https://github.com/shagu/pfQuest/tree/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db).
The compact fixtures retain independent source fields/names, without deriving
them from the addon output. pfQuest and the Mapzeroth travel source are MIT;
see `WaypointTracker_Data/THIRD-PARTY-LICENSES.txt`. ATT source relationships
and the original unsupported coordinates come from
[ec1aa307198d92d18c601ae2c9338a67b71e7d6b](https://github.com/ATTWoWAddon/AllTheThings/tree/ec1aa307198d92d18c601ae2c9338a67b71e7d6b/db/Camelot).

Rebuild the changed data from the repository root:

```sh
python3 tools/build_forever.py
python3 tools/filter_curated_maps.py
lua5.1 tools/build_reference_data.lua
python3 tools/build_travel.py tools/fixtures/travel
```

The client generator stages the whole output family before replacing files,
requires local inputs, and never downloads missing tables. The map filter is
an idempotent post-generation step for the ATT bundle: retain definitions and
relationships, remove positions whose map IDs the client does not support.
It does not substitute an instance entrance for an objective position.

`tools/build_sources.lua PFQUEST REPO` regenerates the item source family from
the pinned full pfQuest checkout. Missing translations use the same English
fallback as `Database.ParseSources`; all eight locale files retain ID parity.
The 175 newly explicit fallback records had no better localized name in the
bundled Names or Items layers. Their IDs remain listed in the integration
change log for translation verification.

## Reference coverage

`WaypointTracker_Data/ReferenceData.lua` appends 2,432 verified named definitions
to the curated layer, without positions, factions or guessed services. They
retain quest/item relationships and can display the existing no-location
result. Independent name fixtures and `tests/check_reference_data.lua` check
every supplied definition and verify that the seven quarantined coordinates
do not erase the three valid Classic fallbacks.

`tools/nonroutable_references.tsv` retains the four unresolved identity
relationships after the reviewed source-recovery overlay. The original
quest/item relationships and routing data are restored; unresolved placement
remains visible to the existing audit rather than being removed by a pruner.

## Restored data and public evidence

The standard play-through and data gates pass with the restored network.
Indoor Sanctum anchors retain their source-provided indoor area assignment;
they do not require an estimated room circle to pass the current runtime gate.
The terrain audit still reports 108 review groups, and the quest audit reports
232 placement suspects without confirmed errors. These are review leads.

The prune executor and its verified-policy gate have been removed. They
rejected the restored transport, walking, relationship and corpse-corridor
data. Client fixtures remain under `tools/fixtures`, with required terrain
inputs and source-recovery fixtures retained for offline checks. Scratch
captures, applied patches, logs and duplicate evidence dumps stay out of the
public worktree.

Private terrain diagnostics and snapshot metadata have been removed. The
consumer input checksum covers the redacted analysis; `snapshot_source_sha256`
retains the original shipped evidence identity so TravelData regenerates
byte-for-byte. Tests verify regeneration and unchanged terrain coordinates.
The ghost corridor's provenance is **observed player trace**; its neutral
fixture has no timestamps or private file hash. Identity tests use synthetic
character and realm values.

## In-game verification inventory

[data-walking-review.tsv](data-walking-review.tsv) classifies all **137** directed
walking legs over 2,000 yards from the planner sweep: 31 access approaches,
52 zone-crossing corridors, and 54 service approaches, across 19 maps. Two
same-map legs intersect another authored circular area. These are survey
leads, not collision evidence. Maximum length is 5,947.9 yards. No barriers,
road nodes, circle boundaries, danger costs or route retention were changed.

Prioritize Barrens/Great Lift approaches, Stonetalon/Charred Vale, Dun Algaz
and North Gate tunnels, Blackrock interiors, mesa/island/ramp boundaries,
Alterac/Ravenholdt, Timbermaw/Talondeep, and the Forever-specific zones.
`validate_terrain_geometry.py --details` lists 108 terrain review groups;
`validate_quest_data.py --show-all` lists the remaining 232 placement
suspects. Classic placement alone cannot establish Forever placement.
Q1067's U5588 reference names a pfQuest placeholder; verify that relationship.

Transport checks still require live evidence for Tidegear 3205, Horde
Powderfuse 3274, EPL tower ownership services, Nighthaven Horde timing,
estimated ship docks/waits/reverse cycles, flight timing differences and
class teleport cast times. Fare preservation is separate from affordability
filtering; the planner's cost/route behavior is unchanged by this integration.

## Approved verification application

`tools/fixtures/travel/verified-routing.json` freezes the field-level transport verdicts, literal walking verdicts, complete verified replacements and 15 local blocked crossing probes for client 1.60.1.70338. `build_travel.py` applies these before serialization; generated Lua is never hand-edited. Verified replacement points retain their full exported precision and both coordinate representations. Unusable terrain fragments and all uncertain candidate chains are removed. The broad estimated barrier extents are replaced by the finite verdict-backed crossing constraints.

The border follow-up corrects 65 anchors and verifies all 30 removed crossing/pass links, including the two that already had replacements. It also verifies eight necessary approaches, including the Stormwind and Ironforge gates, Elwynn–Westfall and the Dun Algaz passages, to preserve short existing routes when boats are enabled. `tools/fixtures/travel/border-evidence.json.gz` records anchor searches, client area IDs, A* attempts, exact world/native chord checks, supported WMO tunnel floors and continuous collision rays. Nearby snaps stay within 150 yards; wider searches use points in both client zone interiors and preserve routing-area boundaries. Incident geometry is freshly checked, with verified detours or the original verified fragment retained at a separate literal endpoint. Opaque per-instance MLMB metadata is retained and validated against MODF; the affected models' declared collision placements and every doodad set are checked conservatively, without inferring activation or LOD semantics. Other unknown chunks still fail closed. The fixed coverage roster and additional route-time checks guard both reachability and important nearby ground routes.

Unmeasured gates and walking passages are retained only when sequential planner removal tests lose a ground connection, or a required hard gate depends on them. Undercity's main entrance is required to preserve Tarren Mill → Undercity → zeppelin → Thrall. The two elevated tower approaches remain labelled unmeasured indoor approaches, rather than certified walking geometry. Generic teleport city locators remain unmeasured landings, and ship vehicle stops are not substituted as shore platforms. Tram animation timing and exterior routing cost are stored separately; the Skywatcher/Valanaar cycle is explicitly conditional on equal transit times.

Run `tools/filter_quest_locations.py` after data generation and reviewed curation. It removes the 232 explicitly unresolved suspected NPC/object positions in `quest-location-verdicts.tsv`, preserving definitions, names, other fields and confirmed positions. The immutable raw source database remains available for provenance; no raw quest/item relationship is deleted.

Permanent route gates include `run_thrall_travel.lua`, `check_taxi_transport.lua`, `run_quest557_ground.lua`, `run_ghost_travel.lua` and `run_route_coverage.lua`. Coverage uses 2,658 fixed restored profile/origin/destination cases. A lost route must name a BLOCKED walking link in its baseline path; unexplained losses fail. This is a sampled planner coverage gate, not an exhaustive all-node-pairs claim.

Quest 557 uses the complete verified control to Elemental Slave at Alterac 22.9, 59.5 as its curated Find target. The other genuine spawn coordinates remain in the immutable raw source database as references; they are not deleted. The permanent ground gate checks the actual Find selection as well as both planner preferences and coordinate representations.
