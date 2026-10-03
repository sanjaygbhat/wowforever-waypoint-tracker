# Waypoint Tracker: notes for working on this repository

A World of Warcraft addon for **World of Warcraft: Forever** (WoW Forever; client 1.60.1, `## Interface: 16001`, install folder `_classic_beta_` during the beta, launch November 4, 2026). Version **1.0.0** is the first public release.

## Layout

- `WaypointTracker/`: the addon. Load order is the `.toc`. Plain Lua, no libraries.
  - `Core.lua`: namespace, events (`ns.On`/`ns.Fire`, `ns.RegisterEvent` is safe for unknown events), settings with defaults and migrations, `ns.XY` (WoW Forever returns positions as plain `{x, y}` tables, so never call `:GetXY()` directly; `tests/check_api.lua` enforces this).
  - `Arrow.lua`, `Waypoints.lua`, `Follow.lua` (the game's map pin and pin links), `Share.lua`, `Slash.lua`, `UI.lua`, `Find.lua` (includes the correction box), `Database.lua`, `Learn.lua` (discoveries: NPCs around you via nameplates/target/mouse-over with `CheckInteractDistance` out of combat, vendor stock, quests, loot; corrections; sharing; the quest-name scan), `AddonBridge.lua` (the shared waypoint API other addons call; formerly `TomTomCompat.lua`).
  - Discoveries are local only (addons have no network access). `Learn.Compact` drops anything the database already has (`DB.AddsSomething`, against a snapshot of the shipped entry), a few seconds after it's written once Find's database is loaded, and fully after each merge. Corrections (`st.fixes`) are never compacted. What a player imports is marked `shared`: it fills gaps but never renames database entries, and isn't exported again.
- `WaypointTracker_Data/`: load-on-demand database for Find (`Data.lua` + `Names_*.lua` classic world, `Client.lua` + `Items*.lua` from the Forever client, `Curated.lua` curated Forever data, `Forever.lua` players' shared discoveries, `THIRD-PARTY-LICENSES.txt`).
- `tests/`: Lua 5.1 mock of the game API and play-through tests. `tools/`: data builders, art renderers, `build_site.sh`. `docs/`: checklist, CurseForge and Wago text (`CURSEFORGE.md`, `WAGO.md`: the same text, but Wago's has the Wago install line and no Sponsors link; keep them in step), launch pack and follow-up runbook (`docs/release/`), wiki page sources (`docs/wiki/`, pasted into the GitHub wiki by hand), screenshots, images.
- `site/`: the GitHub Pages website (https://sanjaygbhat.github.io/wowforever-waypoint-tracker/), with `robots.txt`, `sitemap.xml` and `llms.txt`. `tools/build_site.sh` fills in `@VERSION@`/`@DATE@` and copies the images; `.github/workflows/pages.yml` deploys it from `main` (Settings → Pages → Source: GitHub Actions). Search engines don't index the wiki (GitHub only allows that from 500 stars), so what people should find goes in the README and the site. Keep the site's FAQ text and its JSON-LD `FAQPage` identical.

## Data: sources, priority and rebuilding

Priority in game (highest first): what you see in the game → players' shared discoveries (`Forever.lua`) → the curated database (`Curated.lua`) → the classic database. The game's own quest names (asked in the background) beat any shipped title.

| Source | Licence | Builder | Gives |
|---|---|---|---|
| pfQuest (github.com/shagu/pfQuest) | MIT | `tools/build_db.lua` | Classic world: NPCs, objects, quests, quest items, names in 9 languages |
| wago.tools DB2 tables of the Forever client (product `wow_classic_beta`, build 1.60.1.70170) | game data | `tools/build_forever.py` | Forever-only quest IDs (for the name scan), quest map markers, flight paths, towns, every item with names in 9 languages |
| All The Things (github.com/ATTWoWAddon/AllTheThings), `db/Camelot` (Forever) and `db/VanillaSOD` | MIT | `tools/build_att.lua` | Forever quest givers, NPCs, objects, flight masters, item sources (drops, vendors, mounts, pets, recipes). Season of Discovery data only fills Forever-client quests the Forever data lacks, and those quests get no shipped title, so they appear only after the game confirms them. Names come from ATT's source comments and its `ObjectNames` table. |
| Players' discoveries (GitHub issues: shared text, or the saved file `WTF/Account/<account>/SavedVariables/WaypointTracker.lua`) | players | `tools/merge_discoveries.py` | New NPCs with titles and spots (the addon records NPCs around the player), vendors' stock, drops, quest givers, corrections. The tool parses saved files as data only and keeps only what adds to the shipped database. |

Rebuild in this order (clone the sources to a scratch folder first):

```sh
lua5.1 tools/build_db.lua <pfQuest>
python3 tools/build_forever.py --classic <pfQuest> [--build <newest wow_classic_beta build>]
lua5.1 tools/build_att.lua <AllTheThings>
python3 tools/build_forever.py --classic <pfQuest>   # again: adds curated quest IDs to the name scan
```

Before a release, check for newer sources: `git log -1` of pfQuest and ATT, and `https://wago.tools/api/builds` for the newest `wow_classic_beta` build. After rebuilding, check that no curated NPC or object is left without a name (a nameless one can't be searched; it's kept only for its spots).

Known limits of the sources (as of 2026-10-02): ATT has only placeholder files for Mount Hyjal and Shen'dralas (Riverglades is being filled in), and documents about 136 of the ~1,440 placed new Forever NPCs (measured against Wowhead's list, for counting only), so new NPCs come mostly from players' discoveries; NPC names aren't in the client files (only servers have them). Never use Wowhead data (not redistributable; comparing counts is fine). Questie supports Forever with the same Era data but is GPL, so it isn't bundled.

Shared text format (`WTL1`, tab-separated, one entry per line): `N id name hostile level services spots fac title`, `O id name spots`, `Q id title level giver ender area text objectives needs fac`, `I id name drops sold`, `M spots`, `C N|O id wrong right` (a player's correction: `map:x,y` each, either may be empty). Spots are `map:x,y,x,y;map:...` in 0..1000. New fields go at the end so older versions keep importing. Text fields must never contain tabs, newlines or `]==]` (the shipped files keep this text in Lua long strings).

## Rules for this project

- Public text (README, CurseForge description, release notes) never mentions anything negative: no limitations, bugs, "not supported", "not known yet" or failing badges. Say what works.
- Don't mention TomTom or compare with other addons anywhere, except the README's "For addon authors" section and code identifiers (the `TomTom` global API is what other addons call).
- No donation or "support me" links inside the addon (Blizzard policy); GitHub Sponsors only in the README and CurseForge page.
- Screenshots are real in-game shots, cropped only. No illustrations in their place.
- Never paste API tokens into files. No model identifiers in commits or files.
- When renaming a saved setting, add the old name to the migration table in `Core.lua` (`tomtomCompat` → `addonWaypoints`, `tomtomNoticeShown` → `wayNoticeShown` so far).

## Release and listings

- CurseForge project 1722148 (game flavour Forever, 88568), Wago project ZKxOb36k. Both IDs are in the `.toc` (`X-Curse-Project-ID`, `X-Wago-ID`) and the repository variables. Wago's API key for Forever is `supported_forever_patches`.
- `.github/workflows/release.yml` sends upload metadata with `--form-string` (with `-F`, a `;` in the changelog cuts the JSON short), and attaches `release.json` (flavor `forever`) so addon managers pick the Forever zip.
- A tag `vX.Y.Z` needs a `## X.Y.Z` section in `CHANGELOG.md`.

## Git

- Work on the branch the session names; don't push elsewhere without permission.
- Since the 1.0.0 release (tag `v1.0.0` on `39fa4b6`, public), history is kept: add normal commits on top of `main`, and never rewrite `main` or tags. The owner merges the session branch into `main`.
- Commit as `git -c user.name="sanjaygbhat" -c user.email="sanjaygbhat@gmail.com"`.

## Checks before every push

```sh
lua5.1 tests/check_locales.lua
lua5.1 tests/check_api.lua
for l in enUS deDE frFR esES ptBR ruRU koKR zhCN zhTW; do WT_LOCALE=$l lua5.1 tests/run_tests.lua | tail -1; done
python3 tests/test_merge_discoveries.py
WT_PLAIN_VECTORS=1 lua5.1 tests/run_tests.lua | tail -1
lua5.1 tests/run_bare.lua && WT_PLAIN_VECTORS=1 lua5.1 tests/run_bare.lua
```

Build the zip like `.github/workflows/release.yml` does: copy `LICENSE` to `WaypointTracker/LICENSE.txt`, zip both folders, remove the copy.
