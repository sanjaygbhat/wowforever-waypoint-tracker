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

## Initial trainer identity review (2026-11-13)

This section records the pre-expansion baseline; the following section describes
the current roster.

`tools/fixtures/trainers/trainers.tsv` pins per-NPC source URLs and evidence from
MIT All The Things commit `ec1aa307198d92d18c601ae2c9338a67b71e7d6b`
(`db/Camelot` and explicit editable NPC titles) and our packaged `Forever.lua`
observations at `b3f68f8da465dbd27b13e0b46a46f9a405a2f762`. The existing ATT
MIT notice applies; no additional third-party source was imported. The fixture
checksum is in `tools/fixtures/manifest.json`; `tools/build_trainers.py` produces
`WaypointTracker_Data/Trainers.lua` deterministically without network access.
`tests/check_trainers.py` gates evidence, vocabulary, class conflicts and stale
output, and runs both through the CI check glob and `tools/validate_data.py`.

Accept explicit trainer titles/headers or observed profession titles paired
with trainer service. Profession recipe groups qualify only when they explicitly
teach a profession rank; 18 recipe-only teachers were dropped. All 74 observed
rows were rechecked against Forever.lua, and all 196 ATT URL assertions against
the pinned raw files (including rank/header blocks): no source mismatches.
Identities assert no new positions. Unknown faction stays in the fixture and
is excluded from Nearest. Pet/demon/portal rows are retained but not exposed.

| Kind | Alliance | Horde | Both | Unknown | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| class | 67 | 74 | 0 | 7 | 148 |
| profession | 25 | 38 | 0 | 3 | 66 |
| weapon | 4 | 4 | 0 | 0 | 8 |
| riding | 4 | 4 | 0 | 0 | 8 |
| pet | 0 | 1 | 0 | 0 | 1 |
| demon | 6 | 7 | 0 | 0 | 13 |
| portal | 0 | 1 | 0 | 0 | 1 |

Profession trainers are incomplete: category presence does not establish world
or capital coverage. Nearest says "nearest known", explains the partial list,
and remembers identifiable profession trainers visited by the player. Missing
capital/profession combinations are gaps, not proof that no trainer exists.
Trainer learning compares exact game-localized skill-line names, only while a
tradeskill trainer is open. General trainer type cannot distinguish class,
weapon, riding or portal trainers, so new class assignments remain generic
without further trustworthy API evidence; explicit typed discoveries still
round-trip through WTL1. The runtime performs no extra background scans.

## Expanded observed trainer roster (2026-11-13)

Additional source: **EG Link output: World of Warcraft: Forever**, compiled by
**Efficient Games** (https://efficient.games),
https://github.com/JIVESCORP/eg-link-output-wowf/tree/164bd1e2d89579ada4ee5e2de7e5fd4db684a9f1,
pin `164bd1e2d89579ada4ee5e2de7e5fd4db684a9f1`.
Data from Efficient Games, licensed under **CC BY 4.0**
(https://creativecommons.org/licenses/by/4.0/). Attribution and the modification
notice are in `WaypointTracker_Data/THIRD-PARTY-LICENSES.txt`; the full upstream
licence and pin accompany `tools/fixtures/trainers/observed-164bd1e2/records.json`.
The reduced extract retains only fields used for classification, access and
fallback coordinates, with original file hashes and build metadata. It contains
444 NPC records, 26 corroborated ranked-title patterns and references 46 files;
the evidence folder is 195,378 bytes including the 18,659-byte upstream licence.

Independently read all 17 enUS creature-title snapshots, 25 trainer-window
snapshots and 25 NPC snapshots already provided. Also fetched all 25
`creatures.json` reaction snapshots at the same pin; all 96 inspected upstream
blobs (92 datasets plus documentation/licence/index) match their pinned Git blob
hashes. Newest numeric build per NPC/record wins, preferring live `wowf` over
`wow_classic_beta` for a build tie. A missing side field does not erase an older
explicit side. No older title is unioned over a newer changed/missing title.

“Observed in WoW Forever build X” means cache/server text or player-addon
observations collected on that build, **not** a complete roster, historical
Classic Era/1.12 verification, or assurance that a beta observation remains
unchanged on the live client. Retained evidence spans builds 1.60.1.70009 through
1.60.1.70888; beta-only observations remain identified by product/build. Positions
are where a player stood when an NPC window opened, not a certified NPC spawn.
The README reserves Blizzard's rights in game content.

Inclusion rules:

- Class: exact `<Class> Trainer`; weapon: `Weapon Master`; riding: explicit
  riding trainer/instructor title. Personal names, vendors and supplies titles
  never establish a classification. Pet/demon/portal identities remain
  fixture-only and are not offered by Nearest.
- Profession: explicit profession trainer title, or an exact ranked occupational
  title (Apprentice/Journeyman/Expert/Artisan/Master, including a specialization)
  corroborated by a trainer-window witness for that exact title pattern or an
  independently reviewed row in the original fixture. Unranked occupations need
  that NPC's trainer window or tradeskill interaction. Superior occupational
  titles and uncorroborated specialist titles are excluded. Title text remains
  literal evidence; `rank` continues to mean the prior explicitly taught rank,
  not the new source's title tier.
- Faction/access: explicit `npcs.side` Alliance/Horde first; otherwise positive
  creature reactions for each side (all recorded values for that side >=5,
  Friendly through Exalted), then packaged units. Neutral alone and mixed
  hostile/friendly readings do not establish access. Friendly evidence on both
  sides yields AH; none of the accepted records currently has AH. Unknown
  remains blank in the fixture and is excluded from generated Nearest lists
  and from typed learned candidates at runtime. No faction is inferred from
  class, race, city, personal name or the observer's faction.
- Compare every compatible identity against the previous fixture and retain
  both source/evidence chains. Kind/subkind disagreement quarantines both
  assertions; **zero conflicts** occurred. All 245 prior rows remain.

Independent extraction: **444** source rows, **207** supporting existing rows
and **237** new, for **482** total. Compared with the earlier 390-row research
TSV, 375 identities remain with identical roles, 15 fail the stricter inclusion
rules, and 69 Forever-only IDs are newly admitted (no Classic-ID allowlist).
197 shared rows have updated faction evidence and 119 differ in rank-column
semantics; original literal title tiers remain in the title evidence. The prior
research TSV is not an authority for the generated fixture.

| Kind | Alliance | Horde | Both | Unknown | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| class | 94 | 115 | 0 | 10 | 219 |
| profession | 79 | 121 | 0 | 12 | 212 |
| weapon | 4 | 4 | 0 | 0 | 8 |
| riding | 4 | 4 | 0 | 0 | 8 |
| pet | 11 | 7 | 0 | 0 | 18 |
| demon | 6 | 7 | 0 | 0 | 13 |
| portal | 1 | 3 | 0 | 0 | 4 |

The four exposed kinds contain **447** identities; 22 have unknown faction and
3 more have no available position (251978 enchanting, 267332 herbalism, 252388
mining), leaving **422** located known-faction candidates. Full class totals by
side are recorded in the per-subkind fixture; notably paladins are **8 Alliance,
5 Horde** and shamans **0 Alliance, 15 Horde, 3 unknown**. Alliance shaman access
is not established by these files; 257446, 258113 and 262558 stay unknown. Tests
use synthetic Alliance-shaman/AH records to prove access support without adding
unsupported production assertions.

Position extension: `positions` stores semicolon-separated `uiMap:x,y` triples
with 0–1 x right/y down; `name_enUS` is only a missing-name fallback. `has_position`
retains its old meaning: position present in raw Data.lua units. Existing raw,
Curated and Forever positions are resolved before adding fallbacks. **29**
fixture IDs receive observed positions; one is a fixture-only pet and one has
unknown faction, so **27** appear in runtime fallback text. Five shared NPCs
377/1383/3155/3345/4591 agree with existing runtime-resolved coordinates within
3.659/2.223/2.229/2.621/1.804 yards respectively, using the pinned client map
bounds (including classic-to-Forever transforms). Existing coordinates were
not replaced or rounded. Tests gate coordinates against pinned evidence and
reject any positioned ID that already has a packaged position.

The runtime resolves fallbacks only on a trainer request, after current learned
positions; later local observations and localized names always win. English
names are used only on enUS when no database name exists. Other locales use the
localized service label alone until a database/local observation provides a
name. Fallbacks do not modify DB.units or contaminate discovery exports.
Generation is deterministic/offline and fixtures/licences are checksummed.
Measured with actual Lua 5.1: expanded data chunk median 0.030 ms, p95 0.031 ms,
4.929 KiB retained; increase from the original roster is 0.009 ms/2.662 KiB.
No eager roster parsing, scans, timers or background work was added.

Capital counts below count known-faction roster NPCs whose existing resolved
positions (or eligible fallback) explicitly include that capital's uiMap. They
are category coverage, not completeness claims or new position certifications.

Class coverage:

| Capital | warrior | paladin | hunter | rogue | priest | shaman | mage | warlock | druid | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Stormwind | 3 | 3 | 3 | 2 | 4 | 0 | 2 | 3 | 1 | 21 |
| Ironforge | 3 | 1 | 3 | 3 | 4 | 0 | 2 | 1 | 0 | 17 |
| Darnassus | 3 | 0 | 3 | 1 | 4 | 0 | 0 | 0 | 2 | 13 |
| Orgrimmar | 3 | 0 | 3 | 3 | 2 | 4 | 4 | 3 | 0 | 22 |
| Thunder Bluff | 3 | 1 | 3 | 0 | 3 | 3 | 3 | 0 | 3 | 19 |
| Undercity | 3 | 1 | 0 | 3 | 3 | 0 | 3 | 3 | 0 | 16 |

- Stormwind: shaman.
- Ironforge: shaman, druid.
- Darnassus: paladin, shaman, mage, warlock.
- Orgrimmar: paladin, druid.
- Thunder Bluff: rogue, warlock.
- Undercity: hunter, shaman, druid.

Profession coverage:

| Capital | alchemy | blacksmithing | enchanting | engineering | herbalism | leatherworking | mining | skinning | tailoring | cooking | firstaid | fishing | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Stormwind | 2 | 2 | 2 | 2 | 1 | 2 | 1 | 1 | 3 | 1 | 1 | 1 | 19 |
| Ironforge | 2 | 3 | 2 | 3 | 1 | 2 | 1 | 1 | 2 | 1 | 1 | 1 | 20 |
| Darnassus | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 2 |
| Orgrimmar | 2 | 3 | 2 | 3 | 1 | 2 | 1 | 1 | 2 | 1 | 1 | 1 | 20 |
| Thunder Bluff | 2 | 2 | 2 | 0 | 1 | 3 | 1 | 1 | 2 | 1 | 1 | 1 | 17 |
| Undercity | 3 | 2 | 2 | 2 | 1 | 2 | 1 | 1 | 3 | 1 | 1 | 1 | 20 |

- Stormwind: no category zeros.
- Ironforge: no category zeros.
- Darnassus: blacksmithing, enchanting, engineering, herbalism, leatherworking, mining, skinning, tailoring, cooking, fishing.
- Orgrimmar: no category zeros.
- Thunder Bluff: engineering.
- Undercity: no category zeros.

Darnassus profession coverage remains particularly sparse: this pin supplies
neither a qualifying title nor interaction for most city profession NPCs. No
rows were inferred from familiar names to fill that gap. Both class and
profession data remain partial; no clean total-world denominator is known.

## Second trainer evidence and position review (2026-11-13)

The generator now uses one table of exact English source titles for all source
families, including `Hunter Trainer & Bowyer`. Every literal title/header/recipe
assertion must agree with the row's kind/subkind, including assertions in mixed
source rows. Faction assertions must agree with the row and the pinned evidence;
`faction=packaged units` explicitly identifies derivation from Data.lua. Single-row
wrong-class, wrong-profession, wrong-faction and kind/subkind mutations are run by
`tests/check_trainers.py`, across the applicable ATT, Forever, observed and mixed
source families. No contradictory production role was found and no row was dropped.

Ten rows lacked an explicit faction basis: **4160, 7948, 2390, 11097, 11052, 4732,
4753, 4772, 7954** now say `faction=packaged units` (the existing letters match
Data.lua); **257446** says `faction=unknown` and stays excluded. These are evidence
annotations, with no new faction inference or access change. Two further fixture
rows, **251991 and 257020**, record the position decisions below. Counts remain
482 fixture identities (199 A, 261 H, 0 AH, 22 unknown), 425 exposed known-access
identities and 422 positioned exposed identities. Generated Trainers.lua was
regenerated with `tools/build_trainers.py` and is byte-identical to the prior roster.

### Physical conflicts and decisions

The source pin remains `164bd1e2d89579ada4ee5e2de7e5fd4db684a9f1`.
`tools/fixtures/trainers/observed-164bd1e2/records.json` now also retains the latest
position records used in the two corrections, with original file hashes/build
metadata. `tools/corrections_trainers.tsv` is a compare-and-set source input for
`tools/stage_quest_corrections.py --corrections tools/corrections_trainers.tsv
--output <new-scratch-directory>`; copy only the staged Curated.lua after review.
Apply this after ATT generation/map filtering. The private ATT generator was not
run. No coordinates were invented or averaged; WTL1's existing 0.1% quantization
is retained (half-up rounding).

- **Taleen Shimmerthread, 251991:** Curated.lua previously shipped
  `2521:448,442,773,513`, **1,826.885 yards** apart in the pinned geometry.
  The ATT pin `ec1aa307198d92d18c601ae2c9338a67b71e7d6b` has a quest-giver
  coordinate at 44.8%,44.2% (db/Camelot/Categories/Zones.lua:19145), and an
  undated vendor/recipe node at 77.3%,51.3% (:19732–19735). Verified source Git
  blob: `8f5b44a0123674ab4a5831a19b013b5b63701cc2`.
  Positioned observations under the same NPC ID are beta 1.60.1.70205,
  2026-10-04, (0.448,0.4424); beta 1.60.1.70245, 2026-10-07,
  (0.4484,0.4426); and live wowf 1.60.1.70790, **2026-11-05**,
  **(0.4484,0.4424)**. Their paths are `data/<product>/<build>/npcs.json`.
  All use uiMap **2521**, instance **2991**. No supplied observation supports
  the distant vendor point, another NPC ID or a phase. Neither shipped point
  is outside the map's 0..1 bounds. Data.lua units and Forever.lua contain no
  position record for this ID. Prefer the newest positioned Forever observation:
  retain the existing nearby `2521:448,442` and remove `2521:773,513`.
  The live record has Gossip/QuestGiver interactions; its trainer role also has
  the separately pinned October 7 trainer-window evidence. This does not prove
  whether an unobserved historical spawn ever existed at the vendor coordinate.
- **Nasalanna Windsinger, 257020:** whole-roster cross-source comparison found
  the curated vendor point `2521:608,442` **979.078 yards** from the latest
  positioned observation. ATT Zones.lua:19718–19724 is the vendor/recipe node.
  Observations: beta 1.60.1.70205, 2026-10-04, (0.4324,0.4326), and beta
  1.60.1.70245, **2026-10-07**, **(0.4321,0.4325)**, both on uiMap 2521,
  instance 2991. Later live 1.60.1.70790 supplies the Enchanter title but no
  position. Prefer the newest positioned Forever observation, while retaining
  the explicit beta qualification: replace the undated curated point with
  `2521:432,433` at WTL1 precision. Data.lua units and Forever.lua have no
  position record. Both old and observed points are within map bounds.
- **Peria Lamenur, 2878 (fixture-only pet trainer): unresolved.** Data.lua units
  ships area 1 positions `467,540,710,380`, resolving to uiMap 1426 at
  (0.467,0.540) and (0.710,0.380), **1,306.999 yards** apart. Both are in bounds.
  The pin supplies a beta 1.60.1.70450 Pet Trainer title and beta 1.60.1.70338
  friendly Alliance reaction, but no positioned NPC record. Curated.lua and
  Forever.lua add no position. No chronology, alternate ID or phase can resolve
  the pair. **Keep both positions already shipped**, as required for unresolved
  conflicts; do not expose pet trainers through Nearest.

### Whole-roster spatial inventory

All **482** fixture IDs were checked, including unknown-access and fixture-only
pet/demon/portal rows. The scan combines real Lua 5.1 DB.Points (raw classic-to-
Forever conversion plus Curated/Forever precedence), all fixture fallback points,
and all positioned NPC records for these IDs in the 25 supplied snapshots at the
pin. Snapshot hashes match the supplied source MANIFEST; selected evidence hashes
also match records.json. Geometry is from pinned client 1.60.1.70862 UiMap and
UiMapAssignment. Compare world coordinates across map aliases; never compare
percentages on different rectangles. **470 IDs have position evidence, 12 have
none. No out-of-map point or cross-continent pair was found.** None of the 225 IDs
with historical positioned observations alone moves over 150 yards or changes
uiMap within those observation snapshots.

Before these corrections there were **93** IDs with either >150 yards separation
or multiple uiMaps across sources. **Three** are the physical conflicts above;
**90** are map aliases with maximum world separation <=150 yards. The following
is the complete pre-correction inventory, including close aliases rather than
silently omitting them. `Data` uses area IDs and 1/1000 coordinates; `Curated` and
`Forever` use uiMap IDs and 1/1000 coordinates. The final column gives the newest
positioned observation when present, not an inferred date for the undated data.

| ID / name | uiMaps | Max world separation (yards) | Shipped position evidence before correction | Newest positioned observation |
| --- | --- | ---: | --- | --- |
| 2390 Aranae Venomblood | 1416, 1424 | 26.960 | Data `36:604,812;267:617,195`; Forever `1424:616,197,612,205` | none |
| 2391 Serge Hinott | 1416, 1424 | 4.588 | Data `36:603,809;267:616,192`; Curated `1424:616,192`; Forever `1424:615,191` | wowf/1.60.1.70862 2026-11-09 1424:0.6158,0.1904 |
| 2399 Daryl Stack | 1416, 1424 | 6.933 | Data `36:627,827;267:637,208`; Curated `1424:636,208`; Forever `1424:635,208` | none |
| 2492 Lexington Mortaim | 1420, 1458 | 5.457 | Data `85:657,684;1497:842,156` | wowf/1.60.1.70790 2026-11-05 1458:0.8377,0.1544 |
| 2798 Pand Stonebinder | 1412, 1456 | 4.971 | Data `215:358,212;1638:297,212` | wowf/1.60.1.70862 2026-11-08 1456:0.2931,0.2161 |
| 2878 Peria Lamenur | 1426 | 1306.999 | Data `1:467,540,710,380` | none |
| 2998 Karn Stonehoof | 1412, 1456 | 12.698 | Data `215:378,280;1638:394,551`; Forever `1456:390,543,394,558,402,546` | wowf/1.60.1.70888 2026-11-11 1456:0.3927,0.556;1456:0.3968,0.5501 |
| 3001 Brek Stonehoof | 1412, 1456 | 4.575 | Data `215:368,286;1638:344,579` | wowf/1.60.1.70888 2026-11-10 1456:0.346,0.5748 |
| 3004 Tepa | 1412, 1456 | 2.922 | Data `215:389,261;1638:445,454` | none |
| 3007 Una | 1412, 1456 | 6.649 | Data `215:382,255;1638:415,426` | wowf/1.60.1.70888 2026-11-12 1456:0.4164,0.4271 |
| 3008 Mak | 1412, 1456 | 3.677 | Data `215:384,257;1638:421,435` | wowf/1.60.1.70862 2026-11-09 1456:0.4237,0.4342 |
| 3009 Bena Winterhoof | 1412, 1456 | 1.414 | Data `215:393,236;1638:466,332` | none |
| 3011 Teg Dawnstrider | 1412, 1456 | 1.788 | Data `215:389,245;1638:449,375` | none |
| 3013 Komin Winterhoof | 1412, 1456 | 7.366 | Data `215:400,251;1638:500,404` | wow_classic_beta/1.60.1.70170 2026-10-02 1456:0.499,0.3964 |
| 3026 Aska Mistrunner | 1412, 1456 | 4.205 | Data `215:401,276;1638:507,531` | wowf/1.60.1.70888 2026-11-11 1456:0.5101,0.5292 |
| 3028 Kah Mistrunner | 1412, 1456 | 9.499 | Data `215:412,263;1638:561,464`; Forever `1456:564,478` | wowf/1.60.1.70888 2026-11-10 1456:0.5607,0.4682 |
| 3030 Siln Skychaser | 1412, 1443, 1456 | 6.356 | Data `215:344,211;405:880,483;1638:228,211` | wowf/1.60.1.70888 2026-11-11 1456:0.2319,0.2062 |
| 3031 Tigor Skychaser | 1412, 1443, 1456 | 5.621 | Data `215:346,207;405:882,478;1638:236,188` | wowf/1.60.1.70862 2026-11-08 1456:0.2373,0.1935 |
| 3032 Beram Skychaser | 1412, 1443, 1456 | 2.748 | Data `215:343,207;405:878,478;1638:220,188` | wow_classic_beta/1.60.1.70170 2026-10-02 1456:0.22,0.1918 |
| 3033 Turak Runetotem | 1412, 1456 | 8.089 | Data `215:453,224;1638:765,272`; Curated `1456:764,276` | wowf/1.60.1.70862 2026-11-09 1456:0.7615,0.2767 |
| 3034 Sheal Runetotem | 1412, 1456 | 6.278 | Data `215:455,223;1638:771,270` | wowf/1.60.1.70790 2026-11-05 1456:0.772,0.2758 |
| 3036 Kym Wildmane | 1412, 1456 | 7.061 | Data `215:455,229;1638:771,298`; Forever `1456:775,296` | wow_classic_beta/1.60.1.70338 2026-10-10 1456:0.769,0.299;1456:0.7738,0.2986 |
| 3038 Kary Thunderhorn | 1412, 1456 | 2.921 | Data `215:417,348;1638:585,883`; Curated `1456:584,880` | none |
| 3039 Holt Thunderhorn | 1412, 1456 | 2.405 | Data `215:414,351;1638:573,898` | none |
| 3040 Urek Thunderhorn | 1412, 1456 | 1.053 | Data `215:418,345;1638:591,869` | wow_classic_beta/1.60.1.70338 2026-10-11 1456:0.59,0.8688 |
| 3041 Torm Ragetotem | 1412, 1456 | 1.364 | Data `215:414,346;1638:572,874` | none |
| 3042 Sark Ragetotem | 1412, 1456 | 1.328 | Data `215:414,350;1638:570,895` | none |
| 3043 Ker Ragetotem | 1412, 1456 | 3.290 | Data `215:415,342;1638:576,855` | wow_classic_beta/1.60.1.70338 2026-10-12 1456:0.5777,0.8576 |
| 3044 Miles Welsh | 1412, 1443, 1456 | 7.133 | Data `215:349,200;405:885,470;1638:253,153`; Forever `1456:257,159` | none |
| 3045 Malakai Cross | 1412, 1443, 1456 | 10.437 | Data `215:348,214;405:884,487;1638:246,226`; Forever `1456:248,226,240,217` | wowf/1.60.1.70862 2026-11-07 1456:0.2464,0.2223 |
| 3046 Father Cobb | 1412, 1443, 1456 | 16.945 | Data `215:350,211;405:886,482;1638:256,207`; Forever `1456:245,224` | wowf/1.60.1.70338 2026-10-12 1456:0.2528,0.2056 |
| 3047 Archmage Shymm | 1412, 1443, 1456 | 13.163 | Data `215:344,198;405:880,468;1638:228,145`; Forever `1456:224,162` | wowf/1.60.1.70862 2026-11-10 1456:0.2256,0.1513 |
| 3048 Ursyn Ghull | 1412, 1443, 1456 | 21.457 | Data `215:350,197;405:886,467;1638:257,142`; Forever `1456:255,156,266,167` | wow_classic_beta/1.60.1.70170 2026-10-02 1456:0.2572,0.1465 |
| 3049 Thurston Xane | 1412, 1443, 1456 | 27.519 | Data `215:349,211;405:885,483;1638:252,210`; Forever `1456:228,205` | wowf/1.60.1.70338 2026-10-12 1456:0.2539,0.2124;1456:0.252,0.205 |
| 3373 Arnok | 1411, 1454 | 5.037 | Data `14:416,92;1637:342,846`; Curated `1454:340,844` | wowf/1.60.1.70862 2026-11-09 1454:0.3399,0.8438 |
| 3698 Bolyun | 1440, 1442 | 0.630 | Data `331:180,600;406:529,169` | none |
| 4087 Arias'ta Bladesinger | 1438, 1457 | 0.543 | Data `141:294,542;1657:587,349` | none |
| 4089 Sildanair | 1438, 1457 | 2.804 | Data `141:300,557;1657:618,422` | none |
| 4090 Astarii Starseeker | 1438, 1457 | 1.665 | Data `141:252,638;1657:383,810` | none |
| 4091 Jandria | 1438, 1457 | 1.360 | Data `141:251,641;1657:379,827` | none |
| 4092 Lariia | 1438, 1457 | 10.526 | Data `141:256,654;1657:403,887`; Curated `1457:400,874` | wowf/1.60.1.70790 2026-11-05 1457:0.4043,0.884 |
| 4138 Jeen'ra Nightrunner | 1438, 1457 | 2.410 | Data `141:255,481;1657:397,54` | none |
| 4146 Jocaste | 1438, 1457 | 2.904 | Data `141:256,487;1657:404,85`; Curated `1457:402,88` | wowf/1.60.1.70790 2026-11-05 1457:0.4029,0.0858 |
| 4160 Ainethil | 1438, 1457 | 9.904 | Data `141:286,519;1657:549,240`; Curated `1457:556,246` | none |
| 4163 Syurna | 1438, 1457 | 0.294 | Data `141:249,515;1657:370,219`; Curated `1457:370,219` | none |
| 4205 Dorion | 1438, 1457 | 4.116 | Data `141:260,484;1657:422,73`; Curated `1457:422,76` | none |
| 4211 Dannelor | 1438, 1457 | 2.449 | Data `141:280,495;1657:517,122` | none |
| 4217 Mathrengyl Bearwalker | 1438, 1457 | 5.072 | Data `141:246,487;1657:354,84`; Curated `1457:352,80` | none |
| 4218 Denatharion | 1438, 1457 | 2.947 | Data `141:244,485;1657:348,74`; Curated `1457:348,78` | none |
| 4563 Kaal Soulreaper | 1420, 1458 | 2.039 | Data `85:661,684;1497:862,159`; Curated `1458:860,156` | none |
| 4564 Luther Pickman | 1420, 1458 | 2.372 | Data `85:662,683;1497:864,153` | none |
| 4565 Richard Kerwin | 1420, 1458 | 4.951 | Data `85:667,684;1497:889,159`; Forever `1458:885,156` | wow_classic_beta/1.60.1.70245 2026-10-07 1458:0.8868,0.1608 |
| 4566 Kaelystia Hatebringer | 1420, 1458 | 2.344 | Data `85:659,680;1497:850,140` | none |
| 4567 Pierce Shackleton | 1420, 1458 | 1.662 | Data `85:659,679;1497:854,135` | none |
| 4568 Anastasia Hartwell | 1420, 1458 | 5.243 | Data `85:659,672;1497:851,100`; Curated `1458:850,102` | wowf/1.60.1.70862 2026-11-10 1458:0.8479,0.105 |
| 4593 Christoph Walker | 1420, 1458 | 26.953 | Data `85:578,683;1497:469,152`; Forever `1458:468,165,476,149,474,191` | wowf/1.60.1.70888 2026-11-10 1458:0.471,0.1541 |
| 4594 Angela Curthas | 1420, 1458 | 23.720 | Data `85:581,684;1497:483,160`; Forever `1458:474,191` | none |
| 4595 Baltus Fowler | 1420, 1458 | 14.664 | Data `85:579,687;1497:474,173`; Forever `1458:476,149` | none |
| 4606 Aelthalyste | 1420, 1458 | 18.417 | Data `85:582,689;1497:490,183`; Forever `1458:492,181,489,181,474,191` | none |
| 4607 Father Lankester | 1420, 1458 | 51.221 | Data `85:583,684;1497:494,159`; Curated `1458:496,156`; Forever `1458:514,138,474,191` | wowf/1.60.1.70790 2026-11-05 1458:0.4962,0.1546 |
| 4608 Father Lazarus | 1420, 1458 | 4.829 | Data `85:579,691;1497:476,189`; Forever `1458:471,194` | none |
| 4609 Doctor Marsh | 1421, 1458 | 4.554 | Data `130:730,95;1497:509,746` | wowf/1.60.1.70790 2026-11-05 1458:0.5137,0.747 |
| 4611 Doctor Herbert Halsey | 1421, 1458 | 3.517 | Data `130:723,92;1497:478,733`; Curated `1458:476,730` | none |
| 4753 Jartsam | 1438, 1457 | 4.089 | Data `141:253,502;1657:387,158`; Curated `1457:386,160` | none |
| 5753 Martha Strain | 1420, 1458 | 0.952 | Data `85:660,685;1497:857,161` | none |
| 5784 Waldor | 1413, 1414 | 7.360 | Data `17:460,358` | wowf/1.60.1.70790 2026-11-06 1414:0.519,0.5546;1414:0.5192,0.5546 |
| 5882 Pephredo | 1411, 1454 | 1.102 | Data `14:427,95;1637:384,856` | none |
| 5883 Enyo | 1411, 1454 | 4.998 | Data `14:428,95;1637:388,857` | wowf/1.60.1.70862 2026-11-09 1454:0.3869,0.8551 |
| 5885 Deino | 1411, 1454 | 2.196 | Data `14:427,96;1637:384,861`; Curated `1454:386,860` | wowf/1.60.1.70862 2026-11-07 1454:0.3853,0.8579 |
| 5957 Birgitte Cranston | 1412, 1443, 1456 | 6.481 | Data `215:344,203;405:879,474;1638:225,169`; Forever `1456:223,165` | wowf/1.60.1.70862 2026-11-08 1456:0.2214,0.174 |
| 5958 Thuul | 1411, 1454 | 3.853 | Data `14:428,95;1637:387,854` | wowf/1.60.1.70790 2026-11-06 1454:0.386,0.8573 |
| 6014 X'yera | 1411, 1454 | 2.588 | Data `14:420,101;1637:360,877` | none |
| 6018 Ur'kyo | 1411, 1454 | 2.909 | Data `14:419,101;1637:356,878`; Curated `1454:356,876` | none |
| 7089 Mooranta | 1412, 1456 | 5.395 | Data `215:388,256;1638:444,432` | wowf/1.60.1.70862 2026-11-09 1456:0.4458,0.43 |
| 7311 Uthel'nay | 1411, 1454 | 0.463 | Data `14:429,97;1637:392,863`; Curated `1454:392,863` | none |
| 7315 Darnath Bladesinger | 1438, 1457 | 2.575 | Data `141:295,543;1657:589,353` | none |
| 7870 Caryssia Moonhunter | 1441, 1444 | 7.483 | Data `357:894,466;400:77,190`; Curated `1444:894,464` | none |
| 8308 Alenndaar Lapidaar | 1440, 1442 | 1.580 | Data `331:180,598;406:529,167` | none |
| 10086 Hesuwa Thunderhorn | 1412, 1456 | 0.540 | Data `215:408,339;1638:541,840` | none |
| 10089 Silvaria | 1438, 1457 | 2.770 | Data `141:260,488;1657:425,92` | none |
| 10278 Thrag Stonehoof | 1412, 1456 | 32.957 | Data `215:378,284;1638:394,567`; Forever `1456:397,556,391,560,422,569` | wow_classic_beta/1.60.1.70338 2026-10-11 1456:0.4003,0.5643 |
| 11044 Doctor Martin Felben | 1421, 1458 | 6.906 | Data `130:720,94;1497:466,741`; Forever `1458:468,747` | wowf/1.60.1.70888 2026-11-10 1458:0.467,0.7472 |
| 11047 Kray | 1412, 1456 | 1.348 | Data `215:393,238;1638:467,344` | none |
| 11051 Vhan | 1412, 1456 | 6.360 | Data `215:388,259;1638:443,443` | wowf/1.60.1.70862 2026-11-09 1456:0.4372,0.4458 |
| 11071 Mot Dawnstrider | 1412, 1456 | 1.992 | Data `215:389,247;1638:446,385` | none |
| 11084 Tarn | 1412, 1456 | 6.751 | Data `215:384,255;1638:423,426` | wowf/1.60.1.70862 2026-11-09 1456:0.4266,0.4296;1456:0.4203,0.4278 |
| 11097 Drakk Stonehand | 1424, 1425 | 1.983 | Data `47:134,435;267:987,23`; Curated `1425:134,434` | none |
| 11401 Priestess Alathea | 1438, 1457 | 4.462 | Data `141:254,638;1657:395,812`; Curated `1457:392,810,396,808` | none |
| 11866 Ilyenia Moonfire | 1438, 1457 | 2.259 | Data `141:292,567;1657:576,467`; Curated `1457:575,468` | none |
| 11869 Ansekhwa | 1412, 1456 | 14.408 | Data `215:381,296;1638:409,627`; Curated `1456:412,614`; Forever `1456:414,622,414,616,407,607` | wowf/1.60.1.70862 2026-11-08 1456:0.4102,0.6219 |
| 12776 Hraug | 1411, 1413 | 5.232 | Data `14:406,684;17:664,328`; Forever `1411:406,684` | wowf/1.60.1.70790 2026-11-04 1411:0.4063,0.6844 |
| 251991 Taleen Shimmerthread | 2521 | 1826.885 | Curated `2521:448,442,773,513` | wowf/1.60.1.70790 2026-11-05 2521:0.4484,0.4424 |
| 257020 Nasalanna Windsinger | 2521 | 979.078 | Curated `2521:608,442` | wow_classic_beta/1.60.1.70245 2026-10-07 2521:0.4321,0.4325 |

Unlocated IDs: 246797, 251379, 251972, 251977, 251978, 252084, 252388, 256658, 258113, 258785, 258930, 267332. No replacement was inferred for them.


## Complete Classic trainer fact census and Forever precedence (2026-11-13)

NPC role facts cross-checked against VMaNGOS core, CMaNGOS Classic-DB and
Questie. Only role/access/rank/spawn facts were extracted under the owner's
explicit sources override; no GPL implementation, SQL, Lua, names or prose is
copied into generated addon data. CMaNGOS's actual licence is GPL-3.0. Questie's
historical pin has no root licence; the retained later licence discussion
includes GPL-3 consent and the historical mixed/ARR caveat. Source-specific
extracts, pins, paths and checksums are under `tools/fixtures/trainers/`.

VMaNGOS uses the complete 2026-11-11 database snapshot at
`1fb4909858f3ac558e06613e223f6d7116a9a8fa`, final vanilla patch 10/build 5875,
selecting the newest template revision <=10, active spawn patch intervals, and
trainer spell build intervals. Core head `df69450dd7f953cd8e0bfa4d1e5dc4848362f9e8`
adds no database migration after the snapshot. Independent cross-checks are
CMaNGOS `c33f90b8eeb3f8bacb53d5cbfee45075c80b416c` full 1.12.1 snapshot with
reviewed updates and Questie `454b9d072965ee8f1a881429260fcf1fac8d60f7`
`Database/Classic/classicNpcDB.lua`, the last documented migration reference
before that database moved into QuestieDB. Newest ATT and EG Link repository
heads remain `1c4d146b518a3c2cda6d2488a27be6e2638d5360` and
`e0f8585914c134d9cb5d76756bd065b1e3e92ece`; both were rechecked during this run.

The numeric trainer flag alone is insufficient. Class trainer fields, taught
profession skill lines and explicit role titles establish roles; conflicting
emulator assertions require two-source agreement. Specialization/recipe teachers
are included only when actual trainer flags and skill spell facts establish the
profession. Trainer rank means the highest explicitly taught skill tier, derived
from numeric learn/skill effects, not the NPC's occupational title. Unspawned
world/test trainers are excluded. Forever role/access/position contradictions
win; neutral-only observations may be supplemented by explicit Classic access
facts, while hostile reactions still exclude that side. Unknown access remains
excluded. Personal positions, hostility and correction replacement/removal keep
their runtime precedence.

All nine classes are playable on both factions in Forever, including Dwarf
shamans and Undead paladins; see [Blizzard's race/class tables](https://worldofwarcraft.blizzard.com/en-us/news/24304075/).
ATT's literal Alliance-shaman quest-giver records establish Alliance access for
Teo Hammerstorm (257446), Eldrun Stormbreaker (258098), and Ingrid Dunwald
(258113). Eldrun has a single-NPC literal Ironforge coordinate (47.2%,12.2%);
Teo already has a shipped Dun Morogh point. Ingrid's two-NPC/two-coordinate
quest records do not bind each coordinate unambiguously to one NPC, so no
coordinate was invented for her. Alliance shaman access is no longer treated
as absent. Higher-priority unknown/hostile Forever-only NPCs stay fail closed.

The roster now contains 578 identities (482 at 1.4.0). Pet trainers are shipped
as the typed `trainer_pet_hunter` database roster; the existing Nearest menus
retain their requested class/profession/weapon/riding actions. No TOC file or
version change is needed. Exact per-source counts, every role/flag/rank/access/
spatial disagreement, per-town coverage and measured performance are recorded
in the accompanying mining report. Annora (11073) has a valid Uldaman instance
spawn, but the pinned Forever client has no corresponding uiMap; no surface
entrance is substituted for an NPC position. Three pre-existing Forever-only
profession trainers and Ingrid also lack an unambiguous positioned observation.

The capital gate prints all nine classes and twelve professions for each city.
Its explicit exceptions below are city-specific reviews, not claims that a
faction cannot play a class. Each is backed by zero active trainers in all three
independent pinned Classic role/spawn censuses, a hash-pinned review of that
city's current ATT definitions, and no positioned Forever contradiction.
Deleting a supported service still fails; an unknown-access positioned trainer
prevents an absence claim. These reviews should be revisited when new Forever
observations arrive. Literal review markers consumed by the gate:

```text
TRAINER_ABSENCE|Stormwind|A|class|shaman|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active shaman class trainer in Stormwind in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Ironforge|A|class|druid|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active druid class trainer in Ironforge in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Darnassus|A|class|paladin|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active paladin class trainer in Darnassus in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Darnassus|A|class|shaman|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active shaman class trainer in Darnassus in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Darnassus|A|class|mage|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active mage class trainer in Darnassus in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Darnassus|A|class|warlock|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active warlock class trainer in Darnassus in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Darnassus|A|profession|blacksmithing|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active blacksmithing profession trainer in Darnassus in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Darnassus|A|profession|engineering|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active engineering profession trainer in Darnassus in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Darnassus|A|profession|mining|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active mining profession trainer in Darnassus in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Orgrimmar|H|class|paladin|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active paladin class trainer in Orgrimmar in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Orgrimmar|H|class|druid|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active druid class trainer in Orgrimmar in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Undercity|H|class|hunter|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active hunter class trainer in Undercity in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Undercity|H|class|shaman|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active shaman class trainer in Undercity in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Undercity|H|class|druid|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active druid class trainer in Undercity in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Thunder Bluff|H|class|rogue|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active rogue class trainer in Thunder Bluff in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Thunder Bluff|H|class|warlock|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active warlock class trainer in Thunder Bluff in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
TRAINER_ABSENCE|Thunder Bluff|H|profession|engineering|https://github.com/vmangos/core/releases/download/db_latest/db-1fb4909.zip|69badaa90083eb6b29ca4a954619325ca6804b2c6b59dacc2d0a5dd95d6dbe39|Reviewed city-specific absence: no active engineering profession trainer in Thunder Bluff in any of the three pinned Classic role/spawn censuses; current ATT Camelot city definitions and all positioned Forever trainer observations supply no contrary identity. Both factions can play all nine classes in Forever; this review does not claim a faction-wide class absence.
```

Additional literal ATT access review: High Priestess Mims (258785) gives
Gnome-only priest quests with a single Ironforge coordinate (24.8%,9.4%);
Alfina Nightgaze (270459) gives a Skyborne Alliance-only druid quest. Their
Alliance access is now established, and Mims's missing position is filled.
Ten Forever-only identities still have unknown access. Six known-access rows
remain unlocated: Ingrid 258113 (ambiguous joint quest coordinates), pet trainer
Isaac Chan 258930 (title/access without a position), Annora 11073 (Uldaman has
no pinned Forever uiMap), and Vanessa Sellers 251978, Garan Sunstrider 267332,
and Halavuul Cragwind 252388 (no positioned observation). These are unresolved
data gaps, not reviewed absences. No coordinates or faction letters were guessed.

A further MIT player-observation extract from `salty-max/wow-data` at
`24c719a76202d2b047392972b5d6770e1fc98a11` resolves two of the preceding gaps.
Only original `data/players/forever/enUS.json` observation facts were used;
frozen website-derived tables in that repository were excluded. Eighteen
selected NPC coordinate/name records fill or supersede older coordinates,
keeping their full literal precision and build numbers; equally/newer built EG
positions retain priority. Ingrid now has a literal beta-build 70374 position
in Dun Morogh (47.2%,51.9%). Dorii Brightwhisper (251379) has a build 70790
position on Zephras Isle (41.7%,23.6%); the recorded ender of quest 92481, combined
with ATT's Alliance-only mage quest restriction, establishes Alliance access.
Reaction values without the observer's faction were not used for access.
Current remaining gaps: **nine unknown-access identities and five known-access
identities without a usable position** (258930, 11073, 251978, 267332, 252388).

The expanded roster supplies **528 positioned candidates to the existing
Nearest trainer actions** (422 in 1.4.0), plus 17 positioned pet trainers through
the typed database roster. The independent real-client resolver agrees with
Lua on all 578 raw identities and 561 faction-specific typed candidate records.
AreaTable's fifty referenced names were downloaded for build 1.60.1.70862 and
pinned as a reduced extract; all fifty match the shipped names. Client town
coverage uses the same AreaPOI icon family as Client.lua and a labelled 600-yard
nearest-marker index, independently of the limited wowmock catalogue.

The complete factual disagreement inventory is pinned in
`tools/fixtures/trainers/crosscheck.json`: 67 differences in supported role/
trainer-flag assertions (including unspawned test rows and unclassified titles),
nine differences in explicit numeric rank evidence, and all numeric flag,
faction-ID and spatial/quantization differences. No named positive class or
profession assignment conflicts between the two emulator sources. Bowen
Brisboise (3530) is omitted because only CMaNGOS asserts the trainer role;
VMaNGOS and Questie disagree. Doctor Gregory Victor/Doctor Gustaf VanHowzen
(12920/12939) retain their Forever first-aid evidence despite VMaNGOS's flags.
An empty supported-role set in Questie can also mean an unclassified occupation,
not a denial. Katoom (14740) has contradictory explicit fishing tiers, so no
highest tier is claimed; his trainer identity and position remain present.
Existing independently evidenced ATT ranks are retained. Spatial differences
between sources are below 150 yards; Peria Lamenur's shared multiple-spawn
ambiguity remains as documented above, without inventing a resolution.

Final source census counts (negative witnesses are retained separately):

| Source | Trainer-flag templates | Active trainer-flag rows | Active supported role identities |
| --- | ---: | ---: | ---: |
| VMaNGOS | 547 | 485 | 484 |
| CMaNGOS | 539 | 493 | 487 |
| Questie | 499 | 493 | 475 |

All 484 active supported VMaNGOS identities are represented. All eligible
CMaNGOS/Questie roles are represented; 3530 is the explicitly disputed exclusion.
No supported role is inferred from a trainer flag alone. The individual
negative/unclassified/unspawned assertions and rank differences are all retained
in the pinned cross-check ledger.

Final validation: all **133 workflow invocations passed**, including ten locale
play-throughs, all Lua scenarios/variants, all Lua/Python gates, full data and
runtime audits with empty reviews; final syntax check covers **182 Lua files**.
The trainer gate has **33 tests** and prints capital and town matrices. The
initial full run overlapped a rank-fixture update and failed one locale's nested
gate; the second complete run passed all invocations. The two full runs total
**41.0 minutes**. Post-review index/nearest/loader/precedence checks and final
syntax/data/runtime checks passed again. The cache also recovers temporarily
unavailable map information without reparsing text or requiring a data merge.

Real Lua 5.1 performance: both 68-case before/after matrices cover every Nearest
action and both factions; the second uses real pinned maps with Real routes on.
Final measured warm maximum is **1.957 ms**; isolated first trainer parse/index
maximum is **1.467 ms** (100 samples, 1,367 table allocations in the limited-map
mock). Ten thousand cached index requests allocate **zero tables**. Full cold
clicks include the existing common lazy database load; exact per-action cold/
warm milliseconds, allocation counts and KiB are retained in the mining report.
No TOC addition, login parse, background scan or runtime-review exemption.

## Base Nearest service coverage (2026-11-13)

The 11 base services use shipped data as well as discoveries. The old mock map
catalogue could not measure their world coverage. `tools/audit_services.py`
runs the actual Database/Geo resolver against build **1.60.1.70862** UiMap,
UiMapAssignment and AreaTable fixtures, including Classic bounds conversion,
curated/community precedence, factions and world distances. The mock's synthetic
maps are replaced only inside this offline probe. No client gameplay is claimed.

Additional evidence is pinned under `tools/fixtures/services/`:

- Efficient Games' [EG Link output](https://github.com/JIVESCORP/eg-link-output-wowf/tree/e0f8585914c134d9cb5d76756bd065b1e3e92ece),
  commit `e0f8585914c134d9cb5d76756bd065b1e3e92ece`, CC BY 4.0. The reduced
  evidence keeps literal records, build/product metadata and full-file hashes.
  Interaction positions describe where players stood; they are not a census of
  certified NPC spawn points. Newest numeric build wins, live product breaks a
  build tie. Exact duplicate coordinates collapse; nearby literals keep their
  complete precision. Older titles do not override newer title records.
- [ATT Camelot](https://github.com/ATTWoWAddon/AllTheThings/tree/1c4d146b518a3c2cda6d2488a27be6e2638d5360/db/Camelot),
  commit `1c4d146b518a3c2cda6d2488a27be6e2638d5360`, MIT. Explicit NPC coordinate
  literals supplement independently evidenced services without EG positions.
  Quest-giver, item, recipe and containing-zone coordinates do not qualify.
- The complete [pfQuest service metadata](https://github.com/shagu/pfQuest/blob/104f35678ca39ab1fb78b655f815cc7016f5e0c8/db/meta.lua),
  MIT, at the existing pin. The full source roster comparison confirms every
  mailbox/meeting-stone spawn is already retained by the coordinate fixtures:
  **60 mailbox and 22 meeting-stone spawns**. Five mailbox and three stone IDs
  have no coordinates in that source.
- The client's [AreaTable](https://wago.tools/db2/AreaTable/csv?build=1.60.1.70862)
  provides area names and faction masks. Client taxi service bits exclude
  transport/quest helper endpoints from Nearest flight master; flight positions
  now preserve the literal full precision of TaxiNodes.

Only explicit service titles, interaction types or repair-window flags classify
new services. Explicit NPC side, existing pfQuest access or friendly reactions
establish faction access. Neutral reactions alone do not establish access.
Mailbox access uses existing metadata or the client's explicit area mask;
contested/unrestricted areas retain both factions. Unknown access remains in the
rejection inventory. No title alone implies repair or a trainer role.

`tools/build_services.py` deterministically writes a marked precise supplement
inside the existing `Forever.lua`. Its `SN`/`SO` records are separate from WTL1,
which encodes integer thousandths and would lose source precision. The WTL1
community block and discovery merger remain unchanged. Supplemental candidates
are labelled community, keep personal observation/correction precedence, and
are indexed on the first service request. No TOC addition or login scan occurs.
A normal reload can discover existing-file changes; no new file enumeration is
required. Trainer generators, rosters and runtime parsing are unchanged.

`tests/check_services.py`, also a required `validate_data.py` gate, verifies
literal evidence, pins, regeneration, coordinate/world agreement, client taxi
precision and minimum coverage using real client geometry. Six capital centres
and twenty literal AreaPOI town positions exercise **286** Nearest selections;
all have measured distances. Every capital has the eight required local services,
with Darnassus's flight service correctly outside the city at Rut'theran. The
probe also checks personal precedence, object-service indexing and warm clicks.
The general location audit validates the precise block byte-for-byte against
its generator rather than misreading it as WTL1 or skipping unknown data.

Reproduce offline from the repository root:

```sh
python3 -B tools/build_services.py --check
python3 -B tests/check_services.py
python3 -B tools/audit_services.py --output /tmp/waypoint-services.json
```

No source provides a complete world denominator. Requests for WorldSafeLocs,
WorldSafeLoc and graveyard tables at this build returned HTTP 400/403, including
“Table not found”; no graveyard coordinates or healer services were inferred.
Spirit-healer coverage remains the existing roster plus literal observations.

The audit starts a fresh Lua state for each faction: legacy discoveries without
explicit access use the viewer's faction while merging, so switching faction
after loading is insufficient. Coverage applies both service access and the
general entry-faction filter; the original Alliance lists included two Horde-only
NPCs (3683/3684) that Find correctly filtered out. The updated lists have no such
mismatch. Native continent-map observations remain literal; their mailbox access
uses the client mask of the smallest containing zone. No coordinate is rounded
or replaced to derive that access.

The final host sweep measured every base action from both faction load contexts
and the 26 survey origins: maximum warm click **2.510 ms**. The entire cold
service-query stage peaked at **20.437 ms** and the entire supplemented data-file
compile/execute at **2.089 ms**; even this conservative **22.526 ms** total is
below the 30 ms added-work allowance. Complete cold clicks retain the existing
roughly half-second database load. Timings are Lua 5.1 mock measurements, not
in-game frame-time or availability claims.
