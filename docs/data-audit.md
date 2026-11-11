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

The terrain validator caches invariant blocked-chord geometry and excludes
terrain-only nodes before enumerating ordinary graph pairs. Probe coverage,
order, verdicts and the 60-second gate limit remain unchanged.
`tests/check_terrain_geometry.py` checks boundary cases and compares the cached
predicate against the original audited oracle.

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

`WaypointTracker_Data/ReferenceData.lua` appends 2,428 verified named definitions
to the curated layer, without positions, factions or guessed services. They
retain quest/item relationships and can display the existing no-location
result. Independent name fixtures and `tests/check_reference_data.lua` check
every supplied definition and verify that the seven quarantined coordinates
do not erase the three valid Classic fallbacks.

Deepmoss Matriarch (4264) and Grenka Bloodscreech (4490) now have player-observed
positions in `Forever.lua`. They are no longer reference-only targets in
`tools/reference_ids.tsv`; regenerating the supplement preserves those
discoveries without treating their positions as invented reference locations.

Issue #10's WTL1 export adds player-observed locations for Shadowy Assassin
(2434), Cyclonian (6239), Summoned Incubus (185335) and Ornery Galestrider
(251707). All four are retired from `tools/reference_ids.tsv`; the first two
also leave `ReferenceData.lua` (the latter two lacked verified names in its
pinned source). The strict no-location assertion still applies to every
remaining supplement definition, with separate regressions for observed IDs.

The `data-refresh` integration also introduced 43 references with no target
definition or verified name in any bundled layer: 28 objectives, two quest
givers and 13 item sources. `tools/corrections_quests.tsv` retains every
original field and records the exact omitted IDs and reason. Only these
unresolved edges are omitted from the active curated Find fields; existing
defined targets, quest areas, owner discoveries, the immutable Classic data
and the reviewed source-recovery overlay remain intact. This is an internal
completeness repair, not evidence that the IDs do not exist in Forever.
Restore an edge when its identity can be sourced; never invent a display
name, coordinate or substitute target to satisfy the validator. The four
previously audited unresolved relationships below retain their exact ledger.

`tools/nonroutable_references.tsv` retains the four unresolved identity
relationships after the reviewed source-recovery overlay. The original
quest/item relationships and routing data are restored; unresolved placement
remains visible to the existing audit rather than being removed by a pruner.

## Merging player discoveries

The original public issue #10 export (2026-10-18, WTL1 enUS 1.1.1) is retained
at `tools/fixtures/discoveries/issue-10.wtl`, with its checksum and source in the
fixture manifest. Replay it without changing files:

```sh
python3 tools/merge_discoveries.py tools/fixtures/discoveries/issue-10.wtl --check
python3 tests/check_merge_discoveries.py
```

Omit `--check` to apply an export; `--report PATH` records JSON counts and each
rejected row's line, ID and reason. The tool writes only `Forever.lua`, keeping
the curated, client and immutable Classic layers intact. Existing nonempty
fields win; services and typed relationships are combined. Existing positions
remain intact, including older close pairs. New observations use Learn.lua's
one-per-1%-cell deduplication, 30 positions per map and 20 maps per entry.
Quest area positions are copied only from explicit player observations; no
quest location is inferred from a giver, objective or another data layer.
Malformed rows, unknown UiMaps, out-of-range coordinates and invalid entry IDs
are rejected whole. Creature IDs use the same 1..2147483647 sanity range as
`Learn.ParseGUID`/`Core.Int`; unsupported service names are ignored as in game.

The initial issue #10 merge accepted all 959 records: 315 NPCs, 156 quests,
21 objects, 466 items and one mailbox record. It added 234 NPC, 117 quest,
21 object and 260 item entries to the community layer, plus 1,068 positions
(907 NPC, 95 object, 63 quest-area, three mailbox). Of these, 357 positions
extend existing entries; 210 observations deduplicate and 129 exceed existing
storage limits. No records were rejected. Counts describe additions to the community layer.

After a merge, compare positioned NPC/object IDs against
`tools/reference_ids.tsv`. Remove newly observed IDs from that list and run
`lua5.1 tools/build_reference_data.lua`, following the `f342f28` reconciliation.
Add observed-position assertions to `tests/check_reference_data.lua`; never
weaken the no-location check for the remaining supplement. Replaying the
export must be byte-identical and add no entries or positions.

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

## Teleport items and reagents (1.3.1)

Evidence is the Forever client's own tables for build **1.60.1.70862**
(`https://wago.tools/db2/<Table>/csv?build=1.60.1.70862&locale=enUS`), pinned as
`tools/fixtures/travel/<Table>-1.60.1.70862-enUS.csv` by
`tools/pin_travel_client.py` with both the full-table and the pinned-file
SHA-256 in the manifest. The same rows were extracted from build 1.60.1.70888
and are byte-identical. API availability comes from Gethe/wow-ui-source
`forever` at 4cd0ab752a77164f654ccbca9d0c1fe8dafceebe (version 1.60.1.70888),
`ItemDocumentation.lua`: `C_Item.IsEquippedItem`, `C_Item.IsUsableItem`, and
`C_Item.GetItemCount`'s `includeUses` argument.

**Reagents.** SpellReagents rows 19589, 19622, 19623, 19676, 19679 and 19680
give Teleport: Stormwind (3561), Ironforge (3562), Undercity (3563),
Darnassus (3565), Thunder Bluff (3566) and Orgrimmar (3567) one Rune of
Teleportation (17031) each. Teleport: Moonglade (18960), Astral Recall (556)
and the Hearthstone (8690) have no SpellReagents row. `build_travel.py` writes
the reagent into the `teleports` block; the planner offers a city teleport only
when the bags hold the reagent (a missing, failing or secret count is none).
The generator refuses a hearth spell that gains a reagent, and a spell with more
than one reagent, instead of dropping the requirement. All of these spells cast
in 10 seconds (SpellMisc casting index 7 = 10,000 ms).

**Teleport items.** Every client item whose on-use spell teleports
(SpellEffect 5/252) or whose spell text describes teleporting or transporting
was reviewed. The client has no destination for these spells: Everlook
Transporter (23442) is a type-252 effect with a server-side target, and
Gnomish Transporter (23453), Mount Hyjal Transporter (1269339) and Crumbling
Hearthstone (1312670) are scripted (type 3) effects. A row ships only when the
client's spell text names a town that is already a network node, and
`build_travel.py` refuses rows whose landing word is missing from that text.
Landings are the town's inn (or the capital's city node) and are **estimated**,
like the class teleports' `cast-verified,landing-unmeasured` landings. Cast
time, cooldown, charges, slot, required skill/rank, specialization and level
are read from ItemEffect/ItemSparse, never from `tools/travel_items.tsv`.

| Item | Client facts | Landing | Shipped |
| --- | --- | --- | --- |
| 18984 Dimensional Ripper - Everlook | Engineering (202) 260, Goblin Engineer (20222), 4 h cooldown, text: "transports you to Everlook… technical problems that sometimes occur" | Everlook inn `INN_11118` | yes, "can misfire" |
| 18986 Ultrasafe Transporter: Gadgetzan | Engineering 260, Gnomish Engineer (20219), 4 h, text: "transport yourself to Gadgetzan… nothing bad could ever happen" | Gadgetzan inn `INN_7733` | yes, "can misfire" |
| 260820 SAF-T Emergency Ripper: Everlook | trinket (InventoryType 12), level 55, 3 charges, 4 h, spell 23442 | `INN_11118` | yes, worn only, "can misfire" |
| 260819 EZ-Thro Field Transporter: Gadgetzan | trinket, level 55, 3 charges, 4 h, spell 23453 | `INN_7733` | yes, worn only, "can misfire" |
| 282006 Crumbling Hearthstone | level 1, single use, text "$?pc923[Orgrimmar][Stormwind]"; PlayerCondition 923 is a Horde race mask | `CITY_ORGRIMMAR` (Horde), `CITY_STORMWIND` (Alliance) | yes |
| 260821, 260823 (Mount Hyjal transporters) | "Kaylaena's Workshop on Mount Hyjal… high chance" of problems | no network node | no |
| 17690–17691, 17900–17909, 18149–18150 | "sanctuary of Dun Baldar / Frostwolf Keep" | Alterac Valley only | no |
| 191267, 191288 | inside Naxxramas | dungeon | no |
| 241128 Pile of Portiporters | "Teleport Somewhere", New Avalon only | random | no |
| 213548 Scroll of Liminal Passage | to a party member | not fixed | no |
| 22589/22630–22632, 12585, 17191 | group portals (Karazhan, Stormwind, inner Maraudon) | portal object | no |
| 21711 Lunar Festival Invitation | from within Moonglade's event area | event only | no |
| 260830 SAF-T Teleport | Tinker: Teleport, "Teleport forward $M2 yds" | short blink | no |

Misfires: the Everlook spell's own text says technical problems occur, and the
Gnomish spell is a server script whose text is ironic about safety; neither
outcome is described by client data. Rather than excluding the engineers'
devices, the step says "Use … (it can misfire)" and the landing stays an
estimate. The skill-gated devices are offered only when
`C_Item.IsUsableItem` confirms the item is usable and the specialization spell
is known; with no answer (missing API, error, secret value) they are skipped.
Trinkets are offered only while worn (`C_Item.IsEquippedItem`), with a charge
left (`GetItemCount(item, false, true)`) and off cooldown; their level is
checked with `UnitLevel` only when `IsUsableItem` cannot answer.

Not needed for Forever on this evidence: equipping an item before use is not
planned (a trinket must already be worn), toys and flight costs remain out of
scope, and mage portals (10059, 11416–11420, reagent Rune of Portals 17032) are
never better than the mage's own teleport to the same city.

## Upstream network review for 1.3.1

Upstream (Mapzeroth `rebuild` 1976d4f35e0460fdc587dd8361612a1b98095364, still
the branch head on 2026-11-11) was dumped with `tools/mapzeroth_dump.lua` and
built against our fixtures without changing any gate. The checked-in `mz_*.tsv`
fixtures stay at the earlier extraction; only the timing below is imported.

- **Steamwheedle and Powderfuse docks moved** (1446:68.36,23.02 and
  2548:80.31,54.39). The build stops with "terrain endpoint changed:
  DOCK_STEAMWHEEDLE" (and DOCK_POWDERFUSE when only that one is pinned): both are
  surveyed terrain endpoints. The new positions lie 15 and 16 yards from the
  client-spline `*_CLIENT_STOP` anchors the ship already uses, so upstream now
  agrees with the client evidence we route through. Kept ours, no import.
- **Redridge crossings.** Upstream moves the Riverglades–Redridge crossing
  (2548:16.01,68.62 / 1433:45.36,7.92; ours 13.8,78.4, 334 yards away, with our
  own north-road crossing 151 yards from upstream's Redridge side) and adds
  Redridge–Riverglades (2), Redridge–Burning Steppes and Redridge–Swamp of
  Sorrows crossings. Moving the Riverglades anchor fails "terrain endpoint
  changed: BORDER_RIVERGLADES_TO_REDRIDGE_MOUNTAINS" (it starts terrain chain
  956CFEACC0D3). The new crossings fail "missing walking verdict" in
  `verified_travel.py`: the build-1.60.1.70338 terrain verification has no
  verdict for them, and a verdict from a different client build would mix
  evidence identities. Kept ours; they need a terrain verification pass first.
- **Steamwheedle–Powderfuse ship time.** Upstream reports a live measurement
  of 69 s aboard and 60 s at the dock, 2T + D = 198 s, the same both ways. The
  client path 11391 (TaxiPathNode nodes 5 and 23) waits 60 s at each stop,
  matching the reported wait; its spline is 1,561 and 1,588 yards per crossing,
  about 53–54 s at the speed implied by the Booty Bay–Ratchet ship's reported
  95 s over 2,787 yards, so 198 s is consistent with client geometry while the
  old 90 s placeholder was not. Imported as `retime` in `tools/travel_extra.tsv`
  (198 s, 69 aboard). The link stays `unmeasured-traversal`; no terrain,
  endpoint or coverage gate changed.
- Not part of the three conflicts but in the same dump: Undercity elevator and
  entrance nodes (would add an area and touch the Thrall/Undercity hard gate),
  six TAXI_3276 flight rows (the client's own flights already decide these) and
  non-travel points of interest. Not imported.
