# Waypoint Tracker — Routes tab, round 2 (names, map preview, world-map preview)

Branch: `ux-redesign` of `/Users/sanjaybhat/WoW Projects/waypoint-tracker-public-files`. Client: WoW Forever 1.60.1
(Interface 16001, FrameXML = `Gethe/wow-ui-source` branch `forever`, game type camelot). Companion to `DESIGN.md`
(§5.3 is superseded by this file where they differ); the parcel plan is §9 at the end.

Owner feedback this answers, verbatim: *"the names should be understandable, not have numbers, and on clicking it, I
should see a preview of the map on the right hand side with those points. If those points are in an area, show the
area map, if they are within a continent/side, show that, if they are all over the world, show the world map. On
clicking it, all the points should be visible in the normal map as a preview. And over there, you should have an option
to set it also."*

---

## 0. Decisions (the short version)

1. **Names say what you get or do, never the level, faction, category or an abbreviation.** Level range and faction
   become structured fields (`r.lv`, `r.faction`) shown in the detail pane and the row tooltip; the zone and category
   are a grey second line of every list row. The seed file gains two columns (`faction`, `levels`); all ~876 seed
   names are rewritten by rule (§2). Generated names drop the zone ("Copper Vein", "Treasure chests", "Rare spawns")
   because the zone is on every row anyway. No digits in the list except the vote score.
2. **Row click = select + a map preview in the detail pane** (new widget `RouteMap.lua`): the tightest map that shows
   every stop (zone → continent → world, §3.1), real map art drawn from `C_Map.GetMapArtLayerTextures` plus the
   explored overlays, numbered pins, start pin green, lines in route order (loop closes with a fainter return line),
   the player's position when on that map, a tooltip per stop. Fallback without art: the same box with a dark
   backdrop and the pins/lines.
3. **Preview click = the same route on Blizzard's world map** (new module `RoutePreview.lua`): our window hides, the
   world map opens on the chosen map (`OpenWorldMap(mapID)`, out of combat only), a data provider draws the stops
   as pins + lines, and a bar at the top of the map offers **Set This Route** (= Start, same replace-or-add
   question), **Back to Routes** and close. The preview ends when the map closes, another preview starts, the route
   is set, or the route disappears. Double-click on a row still starts the route (unchanged).
4. **Detail pane re-flow**: title · two meta lines (source/category/zone; levels/mode/stops/distance) · map preview
   · votes · note + numbered stop list (scrolls) · one action row **[Start Route] [Share…] [More ▾]**. Edit, Delete,
   Remove, Hide this author and Copy text move into **More ▾** (a `MenuUtil` menu). Running: **[Stop Route] [Skip
   This Point] [More ▾]**.
5. **List rows become two lines** (36 px): name in the category colour; grey "Zone · Category" below; votes at the
   right only when someone voted; green `>` marker for the running route. New sort **For my level**.
6. Everything else in the Routes tab (filters, pages, popups, recorder, sharing) is unchanged.

---

## 1. Diagnosis (what the tester saw)

- `RouteSeeds.lua`: 876 lines, 427 names contain digits ("Skinning 5-8: …", "Cloth 32-35: …", "SoD Mage 2-25:
  EK tour", "Library books: all 20"); 48 names use "EK", 25 "STV", 11 "EPL", 7 "WPL", plus BWL/UBRS/BFD/SoD/"W.
  Plaguelands"; 154 names start with "(A) "/"(H) "; quest notes start "Lv30-40;". The category word is repeated at
  the front of the name although the row is already coloured by category and the detail pane prints it.
- `Routes.lua:775-802`: generated names put the zone in the name ("Copper Vein - Elwynn Forest") and the row
  (`RoutesUI.lua:414`) prints the zone again in grey → "Copper Vein - Elwynn Forest  Elwynn Forest".
- `RoutesUI.lua:396-421`: one-line rows, name + zone + votes + stop count squeezed into 300 px; long names are cut.
- The detail pane (`RoutesUI.lua:156-293`) is text only; the player has to start a route to see where it goes.
  There is no way to see a route on the world map before starting it.
- Six action buttons in a 2×3 grid (`RoutesUI.lua:481-503`) take 84 px of a 352 px pane.

---

## 2. Naming

### 2.1 Where the information goes

| Fact | Today | New home |
|---|---|---|
| Level range | in the name ("5-8", "2-25", "14+") or the note ("Lv35;") | seed column `levels` → `r.lv = { min, max }`; detail meta line "Levels 5–8"; row tooltip; sort *For my level* |
| Faction | "(A) " / "(H) " prefix (also the filter key) | seed column `faction` ("A"/"H"/"") → `r.faction`; still filters at load; detail meta "Alliance only"; never in the name |
| Category | first word ("Skinning", "Cloth", "Quest:", "Chain:") | `r.cat` (already); row colour, row second line, detail meta |
| Zone | in the name for generated routes; abbreviations in seeds | row second line (`Geo.GetMapName(r.zone)`), detail meta; the name only names a *place inside* the zone or a region spanning zones |
| Abbreviations | EK, STV, EPL, WPL, BWL, UBRS, BFD, SoD, W. Plaguelands | written out in names **and** notes |

### 2.2 Seed file format (breaking change, one-shot conversion)

`WaypointTracker_Data/RouteSeeds.lua`, one route per line, **7 tab-separated columns**:

```
category <TAB> mode <TAB> faction <TAB> levels <TAB> name <TAB> note <TAB> stops
```

- `faction`: `""` (both), `A`, `H`. Replaces the `(A) `/`(H) ` name prefix. `Routes.lua` keeps the same filter
  (`MyFactionLetter()`), reading the column instead of the name.
- `levels`: `""`, `5-8`, `14+` or `35` (a single level). Parsed into `r.lv = { min = 5, max = 8 }`, `{ min = 14 }`,
  `{ min = 35, max = 35 }`. Quest notes lose their `Lv…;` prefix; the value moves here.
- `name`, `note`, `stops`: as today, with the rules below. The stop grammar (`U`, `O`, `N`, `Q`, `P`) is unchanged.
- Parser (`Routes.lua` `FromSeeds`): `line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")`.
  A 5-column line is **not** accepted any more (the data file and the tests are converted in the same wave).
- **Route id** becomes `"s-" .. Hash(cat .. "|" .. faction .. "|" .. spec)` — renaming a seed no longer changes its
  id, so votes survive future wording fixes. `tests/check_seeds.lua` asserts `(cat, faction, spec)` triples are
  unique. (Existing votes on the old `s-` ids are lost once; acceptable before release.)

### 2.3 Name rules (enforced by `tests/check_seeds.lua`; the renaming agent follows them line by line)

N1. **No digits.** `name:find("%d") == nil`, except names on the allowlist of real in-game titles
    (`ALLOWED_DIGIT_NAMES = { "Chasing A-Me 01" }` in the check script). Numbers as words are fine ("the first ten
    books", "all twenty books").
N2. **No level range, no faction tag, no category word.** A name must not start with `Quest:`, `Chain:`, `Quests:`,
    `Skinning`, `Cloth `, `Mats `, `Meat `, `Rep `, `Gold `, `Eggs `, `Clams `, `Silk `, `Water `, `Life `, `Earth `,
    `Fire `, `Air `, `Pet `, `Formula `, `Felcloth `, `Turn-ins `, `Trinket `, `Leather farming`, `Neutral town`,
    `Dungeon entrances:`, `Sightseeing:`, `SoD `, `(A) `, `(H) `. (Checked as a prefix list; "Sightseeing" and
    "Dungeon entrances" are reworded, see examples.)
N3. **No abbreviations.** Whole-word tokens forbidden in names and notes: `EK`, `STV`, `EPL`, `WPL`, `BWL`, `UBRS`,
    `LBRS`, `BRD`, `BFD`, `SoD`, `SM`, `DM`, `WC`, `ZF`, `ZG`, `MC`, `AQ`, `Lv`, `W.`, `E.`, `N.`, `S.`, `req`, `rep`
    (as a word; "reputation" is the word). Write "Eastern Kingdoms", "Stranglethorn Vale", "Eastern Plaguelands",
    "Western Plaguelands", "Blackwing Lair", "Upper Blackrock Spire", "Blackfathom Deeps", "Season of Discovery"
    (notes only; names say "runes" instead), "Scarlet Monastery", "Dire Maul", "Wailing Caverns", "Zul'Farrak",
    "Zul'Gurub", "Molten Core", "Ahn'Qiraj".
N4. **Say what you get or do; add where only inside the zone.** The row's second line already prints the zone, so the
    zone name appears in a route name only when (a) the route spans several zones (then name the region: "…of
    Eastern Kingdoms", "…tour of Kalimdor") or (b) two routes in the same zone would otherwise read the same and the
    place inside the zone is the difference ("Silk Cloth from Syndicate camps" vs "Silk Cloth from Syndicate elites
    in Stromgarde").
N5. **Patterns per category** (English; ≤ 36 characters — the row has ~240 px for the name):
    - skinning: `<Creatures> for <leather or scale tier>` — "Boars for Light Leather", "Cave yetis for Heavy Leather",
      "Flamescales for Black Dragonscale". The tier comes from the note ("Light Leather; …"). Two leather tiers: use
      the higher ("Medium/Heavy" → "Heavy Leather").
    - farming: `<Item or goal> from <source>` — "Silk Cloth from Syndicate camps", "Larval Acid from carrion worms",
      "Argent Dawn reputation at Corin's Crossing", "Small Eggs from swoops", "Gold from Karazhan cellar ghosts",
      "Gizzards and brains for Bloodmage quests".
    - quests: the quest title alone ("Red Linen Goods"); a chain: `<title> chain` ("Mor'Ladim chain"); a tour:
      `<Class> runes: <region> tour` ("Mage runes: Eastern Kingdoms tour"); library: "Library books: all twenty",
      "Library books: the first ten", "Library books of Kalimdor".
    - travel: `<City>: <service>` kept ("Stormwind: class trainers"); tours: `Flight paths of Eastern Kingdoms`,
      `Eastern Kingdoms profession trainers`; towns: `<Town> town services` ("Everlook town services"); sights:
      `<Sight>` ("The four Emerald Dream portals", "The sealed Gates of Uldum", "Ravenholdt Manor secret trail").
    - dungeons: `<Dungeon>: <approach>` kept when short ("Maraudon: orange approach", "Wailing Caverns from the
      Crossroads"); attunements/keys: `<Raid> attunement: <item>` with the raid written out ("Blackwing Lair
      attunement: Blackhand Command", "Upper Blackrock Spire key: Seal of Ascension"); entrances: "Dungeon entrances
      of Kalimdor".
    - treasure: `<Reward> at <place>` ("Tidal Charm at Faldir's Cove").
N6. **Unique per faction.** Two lines may share a name only if no player can see both (one is `A`, the other `H`).
    The check script fails on any pair of lines with the same name whose factions are `""`/anything or equal.
N7. **Notes**: keep the useful text; drop the `Lv…;` prefix (moved to `levels`); drop "EK tour;" fragments (the name
    says tour); expand abbreviations (N3); keep skill requirements and item names (digits are fine in notes); ≤ 140
    characters (`Routes.MAX_NOTE`).
N8. **Capitalisation**: sentence case, proper nouns and item names as the game spells them ("Light Leather",
    "Argent Dawn", "Syndicate").

### 2.4 Examples (before → after; `faction`, `levels`, `name`)

| # | Before (name; note prefix) | faction | levels | After (name) |
|---|---|---|---|---|
| 1 | `Skinning 5-8: Dun Morogh boars` | | 5-8 | `Boars for Light Leather` |
| 2 | `Skinning 12-15: Westfall young goretusks` | | 12-15 | `Young goretusks for Medium Leather` |
| 3 | `Skinning 30-32: Hillsbrad cave yetis` | | 30-32 | `Cave yetis for Heavy Leather` |
| 4 | `Skinning 37-38: STV shadowmaw panthers` | | 37-38 | `Shadowmaw panthers for Thick Leather` |
| 5 | `Skinning 51-54: W. Plaguelands bears & wolves` | | 51-54 | `Bears and wolves for Rugged Leather` |
| 6 | `Leather farming: Black Scales - Flamescales` | | | `Flamescales for Black Dragonscale` |
| 7 | `Leather farming: Rugged - EPL frenzied hounds` | | | `Frenzied hounds for Rugged Leather` |
| 8 | `Cloth 32-35: Alterac Syndicate (silk)` | | 32-35 | `Silk Cloth from Syndicate camps` |
| 9 | `Cloth 35-40: Alterac Syndicate (silk)` (elites in Stromgarde) | | 35-40 | `Silk Cloth from Stromgarde elites` |
| 10 | `Cloth 53-55: Blasted Dreadmaul (runecloth)` | | 53-55 | `Runecloth from Dreadmaul Post` |
| 11 | `Mats 54-57: EPL carrion worms` | | 54-57 | `Larval Acid from carrion worms` |
| 12 | `Meat 35-36: STV crocolisks` | | 35-36 | `Crocolisk Meat from the coast` |
| 13 | `Gold 58-60: Deadwind cellar ghosts` | | 58-60 | `Gold from Karazhan cellar ghosts` |
| 14 | `Rep 53-55: EPL Corin's Crossing` | | 53-55 | `Scourgestones at Corin's Crossing` (the 41-char "Argent Dawn reputation at Corin's Crossing" breaks N5; "rep" is forbidden by N3; the note keeps "Argent Dawn reputation") |
| 15 | `Turn-ins 46-52: Blasted gizzards & brains` | | 46-52 | `Gizzards and brains for Bloodmage buffs` |
| 16 | `Eggs 5-10: Mulgore swoops` | | 5-10 | `Small Eggs from swoops` |
| 17 | `Pet 54-56: EPL scar oozes` | | 54-56 | `Disgusting Oozeling from scar oozes` |
| 18 | `Formula 56-58: WPL Scarlet tower` | | 56-58 | `Crusader formula from Scarlet Spellbinders` |
| 19 | `Trinket 38-41: Arathi Faldir's Cove` (treasure) | | 38-41 | `Tidal Charm at Faldir's Cove` |
| 20 | `(A) Quest: Red Linen Goods`; note `Lv9; gather…` | A | 9 | `Red Linen Goods`; note `Gather…` |
| 21 | `(A) Chain: Mor'Ladim`; note `Lv35; investigate…` | A | 35 | `Mor'Ladim chain` |
| 22 | `Quest: The Green Hills of Stranglethorn`; note `Lv30-40; trade…` | | 30-40 | `The Green Hills of Stranglethorn` |
| 23 | `(H) Quest: Venom Bottles (EK tour)`; note `Lv43; EK tour; search…` | H | 43 | `Venom Bottles: Eastern Kingdoms tour`; note `Search…` |
| 24 | `(A) SoD Mage 2-25: EK tour` | A | 2-25 | `Mage runes: Eastern Kingdoms tour` |
| 25 | `(H) SoD Warrior 2-12: Tirisfal` | H | 2-12 | `Warrior runes in Tirisfal` (zone named: the route is a tour inside it and "Warrior runes" alone would collide with Durotar) |
| 26 | `(A) Library books: all 20` | A | | `Library books: all twenty` |
| 27 | `(H) Library books: first 10` | H | | `Library books: the first ten` |
| 28 | `(A) Cozy Sleeping Bag 14+: full tour` | A | 14+ | `Cozy Sleeping Bag quest chain` |
| 29 | `Chain: Chasing A-Me 01` | | | `Chasing A-Me 01 chain` (allowlisted title) |
| 30 | `(A) Flight paths: Eastern Kingdoms` | A | | `Flight paths of Eastern Kingdoms` |
| 31 | `(H) All profession trainers: Kalimdor` | H | | `Kalimdor profession trainers` |
| 32 | `(A) Stormwind: class trainers` | A | | `Stormwind: class trainers` (already fine) |
| 33 | `Neutral town: Everlook` | | | `Everlook town services` |
| 34 | `Sightseeing: four Emerald Dream portals` | | | `The four Emerald Dream portals` |
| 35 | `Dungeon entrances: Eastern Kingdoms` | | | `Dungeon entrances of Eastern Kingdoms` |
| 36 | `(H) Wailing Caverns: Crossroads approach` | H | | `Wailing Caverns from the Crossroads` |
| 37 | `(H) Blackrock Mountain: BWL orb approach` | H | | `Blackwing Lair: the orb approach` |
| 38 | `BWL attunement: Blackhand Command` | | | `Blackwing Lair attunement` (the full "…: Blackhand Command" is 44 chars; the quest name stays in the note) |
| 39 | `(A) UBRS key chain: Seal of Ascension` | A | | `Upper Blackrock Spire key chain` |
| 40 | `SoD Blood Moon: STV opt-out circuit` | | | `Blood Moon opt-out circuit` (zone Stranglethorn on the row) |

Generated routes (`Routes.lua`, locale strings): `"Copper Vein - Elwynn Forest"` → `"Copper Vein"` (the node name
from the database, already in the client's language); `"Treasure chests - Westfall"` → `L.ROUTE_SUGGESTED_CHESTS =
"Treasure chests"`; `"Rare spawns - Westfall"` → `L.ROUTE_SUGGESTED_RARES = "Rare spawns"`. Key
`ROUTE_SUGGESTED_NAME` is deleted from all nine locale files. Chat sharing is unaffected: `ROUTE_CHAT_LINE` already
appends the zone.

### 2.5 Localisation

- Seed names and notes stay English data (as today: `WaypointTracker_Data` ships English route text; node, NPC and
  quest *stop titles* come from the localised database). This does not change. A future `RouteSeedNames_<locale>`
  table keyed by the English name could translate them; out of scope now, but the English name is the stable key, so
  do not "fix" wording later without need.
- Generated names use `L.*` keys (above) and localised database names.
- New UI strings (§7) go into `enUS.lua` with English + `-- TODO translate` in the other eight files
  (`tests/check_locales.lua` must pass).

### 2.6 Where levels show (numbers are fine here, not in the list)

- Detail meta line 2: `Levels 5–8 · Loop · 14 stops · 412 yds away` (`L.ROUTE_LEVELS:format(5, 8)`, `L.ROUTE_LEVEL`
  for a single level, `L.ROUTE_LEVELS_UP` for "14+"). Faction-only seeds add `· Alliance only` to line 1.
- Row tooltip (hover 0.4 s, `GameTooltip` right): name (category colour), `Levels 5–8` grey, `Zone · Category ·
  14 stops`, then the note wrapped (max ~6 lines).
- Sort **For my level** (`state.sort == "level"`): routes whose `lv` contains `UnitLevel("player")` first, then by
  distance; then routes whose range is closest (|edge − level|); routes without `lv` last, by distance.
  `Routes.FitsLevel(r, level)` returns `true`/`false`, or `nil` when `r.lv` is nil.

---

## 3. Map preview in the detail pane (`RouteMap.lua`)

### 3.1 Which map (`Geo.CommonMap(pts)` → `mapID, shown`)

```
maps  = distinct p.m over the stops (Geo.SameMap folds phased copies)
if one map → that map (a zone, a city, a cave micro-map or a dungeon floor alike)
chains = Geo.ParentChain(m) for each: { m, parent, grandparent, …, root }  (C_Map.GetMapInfo().parentMapID, ≤ 12 hops)
cand  = first entry of chains[1] that is in every other chain          -- deepest common ancestor
repeat
    if every stop projects onto cand (Geo.ProjectToMap(p.m, p.x, p.y, cand) ~= nil) → return cand, #pts
    cand = parent(cand)
until cand == nil
world = Geo.WorldMapID()                                                 -- C_Map.GetFallbackWorldMapID() (947 on this client)
if ≥ 1 stop projects onto world → return world, count
return MainMap(pts) (the map most stops are on), count projecting there   -- e.g. one dungeon floor + an outdoor stop
```

- Zone → "area map" (also cities and caves). Same continent → the continent map (Kalimdor / Eastern Kingdoms, found
  through the parent chain, not hard-coded). Otherwise → the world map. Matches the owner's three cases exactly.
- `Geo.ProjectToMap(m, x, y, toMap)`: `Geo.TranslateToMap` for same-continent maps (existing, world-position based);
  for a **World**-type target (`mapType == Enum.UIMapType.World`, or `MapToWorld(toMap, .5, .5) == nil`) it translates
  the stop onto its continent map `C = Geo.ContinentID(m)` and then uses `C_Map.GetMapRectOnMap(C, toMap)` →
  `minX, maxX, minY, maxY` to place it: `x' = minX + cx * (maxX − minX)`, `y' = minY + cy * (maxY − minY)`. Returns nil
  when either step fails (dungeon floors have their own instance id and never project onto outdoor maps).
- Stops that do not project onto the chosen map are counted and reported under the preview:
  `L.ROUTE_PREVIEW_ELSEWHERE:format(n, Geo.GetMapName(theirMap))` ("3 stops are inside The Deadmines and aren't
  shown"). No pins for them.
- Result cached per route (`previewOf[r] = { map, shown }`, weak-keyed, like `worldOf`) — geometry never changes.

### 3.2 Drawing the map art (verified APIs, forever branch)

| Need | API (exists in `forever`) | Notes / fallback |
|---|---|---|
| Does the map have art | `C_Map.MapHasArt(mapID)` → bool; `C_Map.GetMapArtID(mapID)` → artID (phased maps have different art for the same id; use it in the texture cache key) | missing/false → fallback box (§3.4) |
| Tile grid | `C_Map.GetMapArtLayers(mapID)` → `{ { layerWidth, layerHeight, tileWidth, tileHeight, minScale, maxScale, additionalZoomSteps } }`; we use layer 1 only | `Blizzard_MapCanvasDetailLayer.lua`: `cols = ceil(layerWidth / tileWidth)`, `rows = ceil(layerHeight / tileHeight)` |
| Tile textures | `C_Map.GetMapArtLayerTextures(mapID, 1)` → array of fileDataIDs, **row-major**: `index = (row − 1) * cols + col`; `tex:SetTexture(fileID)` (Blizzard adds `nil, nil, "TRILINEAR"`) | tiles overhang the layer size on the last row/column; Blizzard relies on the canvas clipping → we `SetClipsChildren(true)` on the art frame |
| Explored overlays (without them the preview shows the unexplored/fogged base art) | `C_MapExplorationInfo.GetExploredMapTextures(mapID)` → `{ { textureWidth, textureHeight, offsetX, offsetY, fileDataIDs, isShownByMouseOver, isDrawOnTopLayer, hitRect } }` | `MapExplorationDataProvider.lua`: `wide = ceil(textureWidth / tileWidth)`, `tall = ceil(textureHeight / tileHeight)`; tile `(j, k)` has file `fileDataIDs[(j − 1) * wide + k]`, size = full tile except the last column/row = `textureWidth % tileWidth` (0 → full), anchored `TOPLEFT (offsetX + tileWidth * (k − 1), −(offsetY + tileHeight * (j − 1)))`; the file is padded to the next power of two (≥ 16) so `SetTexCoord(0, w / pow2(w), 0, h / pow2(h))`. Skip entries with `isShownByMouseOver`. Draw after the base tiles (`isDrawOnTopLayer` → one sublevel higher). If the API is nil → base tiles only |
| Scaling | all sizes/offsets × `s = min(boxW / layerWidth, boxH / layerHeight)`, centred (letterbox); pins at `(x * layerWidth * s, −y * layerHeight * s)` relative to the art's TOPLEFT | — |
| Lines | `frame:CreateLine()` (`Line` region, `SetStartPoint/SetEndPoint("TOPLEFT", art, px, −py)`, `SetThickness(2)`, `SetColorTexture`) | absent `CreateLine` → no lines, pins only |

`RouteMap.Art(mapID)` is a pure function returning `{ w, h, tiles = { { file, x, y, w, h, tcx, tcy, top } … } }` or nil
(unit-tested against the mock's fake layers). The widget pools `Texture` objects (base ~12, overlays up to ~60 per zone).
`Enum.UIMapType.World` falls back to `1` when `Enum` is nil (same style as `Geo.lua:18`).

### 3.3 The widget

```lua
local map = RouteMap.Create(parent, 290, 160)   -- Button; .art (clipped Frame), .pins {}, .lines {}, .player, .caption, .elsewhere
map:SetRoute(r)        -- nil clears; picks Geo.CommonMap, draws art + pins + lines; sets .mapID, .shown
map:Refresh()          -- player dot/arrow only (called from the tab's 0.5 s onUpdate)
map.onClick = function(route, mapID) … end     -- RoutesUI wires this to RoutePreview.Show
map:GetMapID()
```

Visuals (all sizes at UI scale 1, inside the 290×160 box):
- Backdrop `Widgets.BACKDROP_BOX`, fill `0,0,0,0.6` (letterbox bars are this colour). Art centred.
- **Lines** first (`OVERLAY`, sublevel 1): colour gold `1, 0.82, 0, 0.85`, thickness 2; drawn stop i → i+1 for modes
  `order` and `loop`; for `loop` the closing segment n → 1 is drawn at alpha 0.4 so the "back to start" leg reads as
  such; for mode `nearest` **no lines** (there is no order). Lines only between stops that both project.
- **Pins** (sublevel 2): 14 px circles — texture `Interface\COMMON\Indicator-Yellow` for stops, `Indicator-Green` for
  stop 1 (start), `Indicator-Gray` for a stop that is a hand-in (`t` starts with `L.ROUTE_STOP_END` prefix) — with a
  `NumberFontNormalSmall` label centred (`SetTextColor(0,0,0)` on yellow/green, white on grey). Numbers go 1…n; when
  n > 40 the labels are hidden (dots only) to avoid a smear; when two pins are < 10 px apart the later label is hidden.
  Each pin is a tiny `Button` with `OnEnter` tooltip: `"%d. %s"` title (or `L.ROUTE_UNNAMED`), then `Zone 54.2, 41.0`
  grey, then distance if on the player's continent; `OnClick` = same as clicking the box.
- **Player**: `Interface\Minimap\MinimapArrow` 16 px rotated by `Geo.GetFacing()` (`SetRotation`), shown only when
  `Geo.ProjectToMap(playerMap, px, py, map.mapID)` succeeds; updated by `Refresh()` every 0.5 s.
- **Caption** (bottom-right, `GameFontDisableSmall`): `Geo.GetMapName(mapID)` · `L.ROUTE_PREVIEW_OPEN` ("Open on world
  map ›"). Highlight texture on hover (`UI-QuestTitleHighlight`, ADD, 0.3). Tooltip on the box:
  `L.ROUTE_PREVIEW_TOOLTIP`.
- **Elsewhere line** (below the box, `GameFontDisableSmall`, shown only when `shown < #pts`): `ROUTE_PREVIEW_ELSEWHERE`.
- Zoom/fit: the whole chosen map is shown (no cropping): the map choice already is the tightest map containing all
  stops, and showing the full zone keeps landmarks recognisable. Padding = none; aspect = the art's (1002×668 ≈ 3:2 on
  Blizzard maps), letterboxed to 290×160 → art 240×160.

### 3.4 Fallback without art (`MapHasArt` false, `GetMapArtLayers` nil, or `CreateFrame` lacks `SetClipsChildren`)

Same box, no tiles: a 240×160 (3:2) dark panel `0.08, 0.08, 0.1, 1` with a faint 4×3 grid (`SetColorTexture(1,1,1,0.05)`
lines) and the map name centred in `GameFontDisableLarge`; pins and lines are drawn exactly as above on that 3:2
rectangle. Caption reads `L.ROUTE_PREVIEW_NO_ART:format(zoneName)` instead of the zone name. Click still opens the
world map preview.

### 3.5 Detail pane layout (right pane 310×352 at 640×540; numbers = UI units)

```
┌ detail (310 × 352) ─────────────────────────────────────────┐
│ Boars for Light Leather                                     │  y −10, GameFontNormalLarge, category colour, no wrap
│ Ready-made · Skinning · Dun Morogh · Alliance only          │  −30, GameFontHighlightSmall grey (line 1)
│ Levels 5–8 · Loop · 14 stops · 412 yds away                 │  −42 (line 2)
│ ┌───────────────────────────────────────────────────────┐  │  −58, RouteMap 290 × 160
│ │▒▒▒│        ①──②                               │▒▒▒│  │
│ │▒▒▒│       ╱     ╲                             │▒▒▒│  │  letterbox bars (dark) · map art · pins/lines
│ │▒▒▒│      ⑤       ③                            │▒▒▒│  │
│ │▒▒▒│       ╲  ▲  ╱     ▲ = you                  │▒▒▒│  │
│ │▒▒▒│        ④──┘                               │▒▒▒│  │
│ │▒▒▒│                Dun Morogh · Open on world map ›│  │  caption
│ └───────────────────────────────────────────────────────┘  │
│ 3 stops are inside Gnomeregan and aren't shown             │  −222, only when needed (else the next row moves up)
│ [▲ 14] [▼ 2]  You voted up                                  │  −236, 22 high
│ ┌ scroll ─────────────────────────────────────────────┬─┐  │  −264 … bottom 44: note, progress, stop list
│ │ Light Leather; Ruined Leather Scraps; open snowfields │▒│  │
│ │                                                       │ │  │
│ │ Stops                                                 │ │  │
│ │ 1. Crag Boar   2. Crag Boar   3. Large Crag Boar …    │ │  │
│ └───────────────────────────────────────────────────────┴─┘  │
│ [Start Route        ] [Share…            ] [More ▾]         │  bottom 10, 24 high: 120 · 110 · 60
└─────────────────────────────────────────────────────────────┘
```

- Body text = running progress line (green, as today) + note + blank line + `L.ROUTE_STOPS_HEADER` + numbered stop
  titles (`L.ROUTE_STOP_N:format(i, title)`), one per line, max 60 lines then "…". It scrolls (existing
  `UIPanelScrollFrameTemplate` body). The stop list is where the numbers live, by design.
- **Action row** (one row, 3 buttons): not running → `[Start Route] [Share…] [More ▾]`; running → `[Stop Route]
  [Skip This Point] [More ▾]`. **More ▾** = `Widgets.Menu(button, …)`: title = route name; mine: *Edit*, *Copy
  text*, divider, *Delete*; shared: *Copy text*, divider, *Remove*, *Hide This Author*; ready-made: *Copy text*.
  (Same actions as today; `Share…` keeps its own button because it is the most used after Start.) `More ▾` text is
  `L.ROUTE_MORE`; the fallback without `MenuUtil` runs the first button (Edit / Copy text) like every other menu.
- No route selected: help text / `ROUTES_PICK` in the scroll area as today; the preview and rows above are hidden.
- The `Widgets.Button` label clipping rule from REVIEW2 (font string LEFT 6 / RIGHT −6, no wrap) applies to all three.

### 3.6 List rows

```
┌ list 300 px ───────────────────────────────────┬─┐
│ > Boars for Light Leather               ▲ 14   │▒│   line 1: name (category colour), 36-px rows
│   Dun Morogh · Skinning                        │ │   line 2: GameFontDisableSmall
│   Red Linen Goods                              │ │
│   Elwynn Forest · Quests                       │ │
│   Flight paths of Eastern Kingdoms      ▲ 3    │ │
│   Eastern Kingdoms · Travel & sights           │ │   r.zone is the main map; a multi-zone route shows its common map name
│ …                                              │ │
└────────────────────────────────────────────────┴─┘
```
- `rowHeight = 36`; `row.text` (name) at `TOPLEFT 4,−3`, `row.sub` at `BOTTOMLEFT 4,3`; `row.right` (votes) at
  `TOPRIGHT −4,−4`: `"|cff40ff40▲ %d|r"` plus `" |cffff6060▼ %d|r"` only when `down > 0`; nothing when nobody voted.
  The stop count leaves the row (it is in the detail and tooltip). Running marker `|cff40ff40>|r ` as today.
- Line 2 = `Geo.GetMapName(r.previewMap or r.zone) .. " · " .. Routes.CategoryLabel(r.cat)`; for routes whose common map
  is a continent/world the first part is that map's name ("Eastern Kingdoms") — `RoutesUI` asks
  `ns.RouteMap and ns.RouteMap.MapFor(r)` (cached `Geo.CommonMap`) and falls back to `r.zone`.
- Row tooltip (§2.6). Selected row background as today; hover highlight as today.
- Sort dropdown gains `L.ROUTES_SORT_LEVEL` ("For my level") as the 4th radio.

### 3.7 Interaction summary

| Input | Result |
|---|---|
| Click a row | select; detail re-renders with the map preview (no world map) |
| Double-click a row | `Routes.Start(id)` (unchanged) |
| Click the preview box, a pin in it, or its caption | `RoutePreview.Show(id, previewMapID)` (§4) |
| Hover a pin | tooltip "3. Large Crag Boar · Dun Morogh 54.2, 41.0 · 412 yds" |
| Start / Stop / Skip / Share… / More ▾ | as today (More ▾ is a menu) |
| Tab `onUpdate` (0.5 s) | `RefreshList()` as today + `map:Refresh()` (player arrow) |

---

## 4. World-map preview (`RoutePreview.lua`)

### 4.1 Panel rules on this client (verified)

- `WorldMapFrame` is registered `RegisterUIPanel(self, { area = "left", pushable = 0, … allowOtherPanels … })`
  (`Blizzard_WorldMap.lua`, Mainline base used by camelot). Our window is `left, pushable = 5`. Per
  `UIParentPanelManager.lua`, opening a left panel while another left panel is up: *the old left frame with the higher
  pushable moves to center, the new frame takes left*. So if the player opens the map while our window is open,
  Blizzard slides our window to the centre slot — native, accepted. For **our** preview we do not want two panels
  fighting: `RoutePreview.Show` **hides our window first** (`Window.Hide()` → `HideUIPanel`), then opens the map.
- Maximised map (`miniWorldMap` CVar off) shows a blackout frame over everything; our bar lives inside the map's
  `ScrollContainer`, so it is visible in both windowed and maximised modes.
- `ShowUIPanel`/`HideUIPanel`/`OpenWorldMap` are protected in combat ("We no longer allow addons to show or hide UI
  panels in combat"). In combat `RoutePreview.Show` prints nothing to chat; it sets the window status line
  `L.IN_COMBAT_NO_PANELS` (red) and returns `false, "combat"`.
- `OpenWorldMap(mapID)` (global, `Blizzard_WorldMap.lua`) → `WorldMapFrame:HandleUserActionOpenSelf(mapID)`; `C_Map.
  OpenWorldMap` "has restrictions" (hardware event) — a click on our preview is one. Fallback when the global is nil:
  `pcall(ShowUIPanel, WorldMapFrame)` then `pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)` (**after** show,
  because `WorldMapMixin:OnShow` resets the map to the player's map). In both paths, after opening check
  `WorldMapFrame:GetMapID() ~= mapID → SetMapID(mapID)`; if the map did not open (`not WorldMapFrame:IsShown()`),
  return `false, "refused"` and re-show our window.

### 4.2 Module contract

```lua
RoutePreview.Show(id, mapID)  -> ok, reason      -- hides the window, opens the map on mapID, starts the preview
RoutePreview.End(reason)                          -- "set" | "back" | "close" | "mapClosed" | "replaced" | "gone"
RoutePreview.Current()        -> id | nil
RoutePreview.bar, RoutePreview.provider           -- for tests
ns.Fire("ROUTE_PREVIEW", id | nil)                -- after Show / End
```

- `Show`: `if ns.InCombat() → false,"combat"`; `if not WorldMapFrame → false,"nomap"`; `Window.Hide()`; `current = {
  id = id, map = mapID, returnTo = true }`; open the map (§4.1); `provider:RefreshAllData()`; bar refresh; fire.
- **Data provider** `RoutePreviewProvider = CreateFromMixins(MapCanvasDataProviderMixin)` added in the same `Setup`
  timing as `MapPins` (on `LOGIN`, or `EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap")`):
  - `RemoveAllData`: `map:RemoveAllPinsByTemplate("WaypointTrackerRoutePinTemplate")`; hide lines.
  - `RefreshAllData`: if no `current` → return. `mapID = map:GetMapID()`. For each stop `i`: `x, y =
    Geo.ProjectToMap(p.m, p.x, p.y, mapID)`; if ok → `map:AcquirePin(TEMPLATE, r, i, x, y)`. Lines on a layer frame
    parented to `map:GetCanvas()` (same technique as `TravelMap.lua:22-36, 93-108`): thickness `3 / scale`
    (`ScrollContainer:GetCanvasScale()`), gold `1, 0.82, 0, 0.9`, loop return leg alpha 0.45, none for `nearest`.
    Count `shown`; update the bar.
  - `OnCanvasScaleChanged`: re-thickness lines (pins scale via `SetScalingLimits(1, 1, 1.2)` like our waypoint pins).
  - `OnMapChanged` (default → `RefreshAllData`) handles the player navigating to another zone: stops that project
    are drawn, the bar says how many.
  - `OnHide`: `RoutePreview.End("mapClosed")`.
- **Pin template** `WaypointTrackerRoutePinTemplate` (`Templates.xml`, mixin `WaypointTrackerRoutePinMixin`,
  completed in `RoutePreview.lua` the way `MapPins.lua:12,268` does): 20×20 Frame, `Icon` texture
  `Interface\COMMON\Indicator-Yellow` (green for stop 1, grey for hand-in stops), `Number` FontString
  `NumberFontNormalSmall` centred (hidden when the route has > 60 stops), `Highlight` ADD. `OnLoad`: frame level
  `PIN_FRAME_LEVEL_WAYPOINT_LOCATION` (fallback `PIN_FRAME_LEVEL_AREA_POI`), `SetScalingLimits(1, 1.0, 1.2)`, the same
  `SetPassThroughButtons` guard as `MapPins.lua:18-28`. `OnAcquired(r, i, x, y)`: `SetPosition(x, y)`, colours,
  number. `OnMouseEnter`: tooltip `"%d. %s"`, zone + coords, distance. `OnClick` (left): nothing (the bar sets the
  route; a stray click must not start it). Right-click passes through (zoom out), as our other pins.
- The provider registers on LOGIN (or the world-map load continuation); the preview bar is created on first valid Show and reused. `RoutePreview.bar` is nil until then.
- **Bar** `WaypointTrackerRoutePreviewBar` (created on the first successful `Show` and reused; the provider itself
  registers on `LOGIN` or the `Blizzard_WorldMap` load continuation): `CreateFrame("Frame", name, WorldMapFrame:GetCanvasContainer())`,
  `BackdropTemplate` (`BACKDROP_BOX`, fill `0,0,0,0.75`), anchored `("TOP", container, "TOP", 0, -8)`, height 30,
  frame level `container:GetFrameLevel() + 510` (above pins, like `MapButton`). Contents left→right: `text`
  (`GameFontNormal`, `L.ROUTE_PREVIEW_BAR:format(name, shown)`), `[Set This Route]` (`UIPanelButtonTemplate`, 120),
  `[Back to Routes]` (120), `[x]` (`UIPanelCloseButton`, 24). Width = text width + 290. When `shown == 0` the text
  becomes `L.ROUTE_PREVIEW_OFFMAP:format(Geo.GetMapName(current.map))` and a `[Show Them]` button
  (`WorldMapFrame:SetMapID(current.map)`) replaces Set.
  ```
  ┌ world map canvas ───────────────────────────────────────────────────────────┐
  │        ┌──────────────────────────────────────────────────────────────┐    │
  │        │ Previewing Boars for Light Leather · 14 stops  [Set This Route] [Back to Routes] [x] │
  │        └──────────────────────────────────────────────────────────────┘    │
  │                     ①───②                                                  │
  │                    ╱     ╲         (gold lines, numbered pins; start = green)│
  │                   ⑤       ③                                                 │
  │                    ╲     ╱                                                  │
  │                     ④───┘  (loop: return leg fainter)                       │
  └─────────────────────────────────────────────────────────────────────────────┘
  ```
- **Set This Route** → `ns.Routes.Start(id)` (the replace-or-add `StaticPopup` appears over the map when needed; it is
  `DIALOG` strata) → `End("set")`. The map stays open; `MapPins` now draws the route's waypoints as normal pins, so the
  player sees the preview turn into the real thing.
- **Back to Routes** → `End("back")`: out of combat `pcall(HideUIPanel, WorldMapFrame)`, then `Window.Show("routes")`
  and `RoutesUI.Select(id)`; in combat only the preview ends (the map stays).
- **[x]** → `End("close")`: preview ends, map stays, window stays hidden.
- `End(reason)`: `current = nil`; `provider:RefreshAllData()` (removes pins/lines); bar hidden; `ns.Fire("ROUTE_PREVIEW",
  nil)`. `Show` while a preview runs → `End("replaced")` first. `ns.On("ROUTES_CHANGED")`: current route gone →
  `End("gone")`.
- Esc closes the map → `OnHide` → `End("mapClosed")`; the window does **not** reopen by itself (the player chose to
  close; Back is the explicit way home).
- A preview never outlives the map, so the window needs no "previewing" state of its own.
- `run_bare`: `WorldMapFrame`, `MapCanvasDataProviderMixin`, `CreateFromMixins`, `OpenWorldMap`, `MenuUtil` may all
  be nil → `Setup` returns early; `Show` returns `false, "nomap"` and RoutesUI shows `L.ROUTE_PREVIEW_UNAVAILABLE` in the
  status line.

### 4.3 Row click vs preview click — decided

- Row click → detail pane preview only (owner: "on clicking it, I should see a preview of the map on the right hand
  side"). It must stay cheap and must never move the player's panels.
- Preview click (box, pin or caption) → world map (owner: "On clicking it, all the points should be visible in the
  normal map as a preview … over there, you should have an option to set it also"). The preview box is the only
  world-map entry point in the pane; a fourth action button is not added (the row is full and the box is the obvious
  target). Double-click row = Start stays.

---

## 5. Also in this round (same spirit, small)

1. Two-line rows (§3.6) and the vote column without the stop count.
2. **More ▾** menu replaces the 2×3 button grid (§3.5).
3. Sort **For my level** (§2.6).
4. Stop list in the detail body (§3.5) — the numbered stops are what a quest route is about.
5. Row tooltip with levels and note (§2.6).
6. `L.ROUTES_POINTS` text becomes `"%d stops"` (the owner and the recorder say "stops"; key kept).
7. Search hay (`RoutesUI.lua:63`) adds `Routes.LevelText(r)` and the faction word, so "level 20" or "horde" finds
   routes.
Not touched: filters, pages (editor/import/copy/create/help), popups, recorder, sharing, settings, first-open help.

---

## 6. Behaviour details / edge cases

- **Routes with stops on several continents** → world map; pins are placed through `GetMapRectOnMap`; lines cross the
  sea (acceptable; it is a preview). If `GetMapRectOnMap` is nil (API missing) → `CommonMap` returns `MainMap` and the
  elsewhere line reports the rest.
- **Dungeon routes** ("Maraudon: orange approach" has outdoor stops only; dungeon floors appear only in player-made
  routes recorded inside): one floor → that floor's art (`GetMapArtLayers` works for dungeon maps); mixed → the
  outdoor common map + elsewhere line.
- **Loops are `unordered` until prepared** (`Routes.Prepare`, `Routes.lua:676`): the pane preview must call
  `Routes.Prepare(r)` before drawing lines (it is cheap for one route; the list never prepares all of them). Pins of an
  unprepared loop would otherwise be numbered in database order.
- **Phased map copies**: `Geo.SameMap` folds them for the "one map" test; `GetMapArtID` is in the texture cache key.
- **Player on another continent**: no player arrow; distance line omitted (as today).
- **200-stop routes**: pins pooled; labels hidden above 40 (pane) / 60 (world map); lines capped at 200 segments.
- **Combat**: pane preview works (no protected calls); world-map preview refuses with the status line; Set/Back inside
  an already-open preview: `Routes.Start` is fine, `HideUIPanel` is skipped.
- **Window closed while a pane preview exists**: nothing to do; `SetRoute(nil)` on tab hide releases textures.
- **Memory**: textures are pooled per widget; one widget exists (the detail pane). `RouteMap.Art` results are cached
  per `mapID .. ":" .. artID` (weak table) — at most a few dozen maps per session.
- **Taint**: no secure frames are touched; the bar and pins are our frames; `SetPassThroughButtons` keeps the existing
  out-of-combat guard.

---

## 7. Strings (English; add to `enUS.lua`, English + `-- TODO translate` in the other eight)

```lua
-- new
L.ROUTE_LEVELS = "Levels %d\226\128\147%d"            -- en dash; "Levels 5–8"
L.ROUTE_LEVEL = "Level %d"
L.ROUTE_LEVELS_UP = "Level %d and up"
L.ROUTE_FACTION_A = "Alliance only"
L.ROUTE_FACTION_H = "Horde only"
L.ROUTES_SORT_LEVEL = "For my level"
L.ROUTE_MORE = "More..."                                -- the third action button (a menu); no arrow glyph in the string
L.ROUTE_STOPS_HEADER = "Stops"
L.ROUTE_STOP_N = "%d. %s"
L.ROUTE_PREVIEW_OPEN = "Open on world map"
L.ROUTE_PREVIEW_TOOLTIP = "Click: show every stop on the world map, where you can set the route."
L.ROUTE_PREVIEW_NO_ART = "No map picture for %s"
L.ROUTE_PREVIEW_ELSEWHERE = "%d stops are inside %s and aren't shown."
L.ROUTE_PREVIEW_BAR = "Previewing %s \194\183 %d stops"   -- middle dot
L.ROUTE_PREVIEW_SET = "Set This Route"
L.ROUTE_PREVIEW_BACK = "Back to Routes"
L.ROUTE_PREVIEW_CLOSE = "Close the preview"
L.ROUTE_PREVIEW_OFFMAP = "The stops are on %s."
L.ROUTE_PREVIEW_SHOW = "Show Them"
L.ROUTE_PREVIEW_UNAVAILABLE = "The world map isn't available right now."
L.ROUTE_PREVIEW_START = "Start here"                    -- tooltip line for pin 1
L.ROUTE_SPANS = "Across %s"                             -- detail meta when the common map is a continent/world
-- changed text (same keys)
L.ROUTES_POINTS = "%d stops"
L.ROUTE_SUGGESTED_CHESTS = "Treasure chests"
L.ROUTE_SUGGESTED_RARES = "Rare spawns"
L.ROUTE_SUGGESTED_NOTE = "Every known spot in this zone, in one loop."
-- removed (all 9 files)
L.ROUTE_SUGGESTED_NAME
```

---

## 8. Module / API contract

```lua
-- Geo.lua (additions)
Geo.ParentChain(mapID) -> { mapID, parentID, ..., rootID }          -- ≤ 12 hops, cached
Geo.ContinentID(mapID) -> id | nil                                   -- nearest ancestor (or self) of type Continent
Geo.WorldMapID() -> id                                               -- C_Map.GetFallbackWorldMapID() or 947
Geo.IsWorldMap(mapID) -> bool                                        -- mapType == World or no world position
Geo.ProjectToMap(m, x, y, toMap) -> x, y | nil                       -- TranslateToMap, or continent rect on the world map
Geo.CommonMap(pts) -> mapID, shownCount                              -- §3.1

-- Routes.lua (additions)
r.faction = "A" | "H" | nil ; r.lv = { min = n, max = n | nil } | nil   -- seeds only; not serialised (WTR1 unchanged)
Routes.ParseLevels(text) -> lv | nil
Routes.LevelText(r) -> string | nil           -- L.ROUTE_LEVELS / ROUTE_LEVEL / ROUTE_LEVELS_UP
Routes.FitsLevel(r, level) -> true | false | nil
Routes.FactionText(r) -> string | nil
Routes.StopTitle(r, i) -> string              -- p.t or L.ROUTE_UNNAMED
Routes.SEED_COLUMNS = 7

-- RouteMap.lua (ns.RouteMap)
RouteMap.Art(mapID) -> { w, h, tiles = { { file, x, y, w, h, tcx, tcy, top } } } | nil     -- pure; cached
RouteMap.MapFor(r) -> mapID, shown            -- cached Geo.CommonMap(r.pts)
RouteMap.Create(parent, w, h) -> widget       -- :SetRoute(r|nil) :Refresh() :GetMapID() .onClick .pins .lines .art .caption .elsewhere .player

-- RoutePreview.lua (ns.RoutePreview)
RoutePreview.Show(id, mapID) -> ok, reason ; RoutePreview.End(reason) ; RoutePreview.Current() -> id|nil
RoutePreview.bar ; RoutePreview.provider ; global frame WaypointTrackerRoutePreviewBar ; XML template WaypointTrackerRoutePinTemplate
ns.Fire("ROUTE_PREVIEW", id|nil)

-- RoutesUI.lua (kept API) + widgets additions: widgets.map (RouteMap widget), widgets.more (button), rows have .sub
```

Nil-guards: RoutesUI calls `ns.RouteMap.Create` / `ns.RoutePreview.Show` only when present (stubs from the scaffold
parcel define empty tables); RouteMap calls `Geo.CommonMap` (lands in wave 1); every Blizzard API above through
`pcall`/`if`.

---

## 9. Parcel plan (disjoint file ownership; one coding agent per parcel)

Ground rules as in `PARCELS.md` (edit only owned files; requests go to `scratchpad/ux/requests/<id>.md`; strings only
from `enUS.lua`; `run_bare` must pass; Lua 5.1 at `$LUA`; `luac -p` clean). Test mock is `tests/wowmock.lua`, owned by
**exactly one parcel (R2)**.

```
Wave 1 (parallel, foundation)   R1 Strings   R2 Mock   R3 Geo   R4 Scaffold (toc + stubs)
        ↓ merge
Wave 2 (parallel, features)     R5 Seeds data   R6 Routes.lua   R7 RouteMap   R8 RoutePreview   R9 RoutesUI
        ↓ merge
Wave 3 (one agent)              R10 Integration, CI, docs
```

### R1 — Strings
**Owns**: `WaypointTracker/Locales/*.lua` (9 files).
**Work**: §7 additions (English + `-- TODO translate` in the 8 non-English files), changed texts, delete
`ROUTE_SUGGESTED_NAME` everywhere.
**Acceptance**: `$LUA tests/check_locales.lua` OK; `grep -c ROUTE_PREVIEW_SET Locales/*.lua` = 9; `grep ROUTE_SUGGESTED_NAME` = 0 hits in `WaypointTracker/`.

### R2 — Mock
**Owns**: `tests/wowmock.lua`, `tests/run_mock_selftest.lua`.
**Work** (additive; document each `M.*` in the header):
- Regions: `Frame:CreateLine()` → object kind `Line` with `SetStartPoint(point, rel, x, y)`, `SetEndPoint`,
  `SetThickness`, `GetThickness`, `SetColorTexture`, `Show/Hide` (record `_start`, `_end`); `Frame:SetClipsChildren(on)`
  (store), `Frame:SetDrawLayer(layer, sub)` (store), `Frame:SetRotation(rad)` (store), `Frame:SetColorTexture(r,g,b,a)`
  (store, if not already real), `Frame:SetHitRectInsets` no-op if missing.
- `C_Map.GetMapArtID(id)` → `id * 10` for known maps; `C_Map.MapHasArt(id)` → `M.maps[id] and not M.maps[id].noArt`;
  `C_Map.GetMapArtLayers(id)` → `{ { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256,
  minScale = 1, maxScale = 1, additionalZoomSteps = 0 } }` (nil for `noArt`); `C_Map.GetMapArtLayerTextures(id, 1)` →
  12 fake fileIDs `id*1000+1 … +12`; `C_Map.GetMapRectOnMap(child, top)`: for `top == 947` and `child` a continent
  (mapType 2) return `M.worldRects[child]` — seed `{ [13] = { 0.55, 0.95, 0.10, 0.90 }, [12] = { 0.05, 0.45, 0.10,
  0.90 } }`; otherwise nil. Add `mapType = 1` handling: `GetWorldPosFromMapPos(947, …)` returns nil (already, keep).
- `C_MapExplorationInfo = { GetExploredMapTextures = function(id) return M.explored[id] or {} end }`; seed
  `M.explored[37] = { { textureWidth = 300, textureHeight = 270, offsetX = 100, offsetY = 50, fileDataIDs = { 9001,
  9002, 9003, 9004 }, isShownByMouseOver = false, isDrawOnTopLayer = false } }`.
- Add `M.maps[1414] = Kalimdor` and `M.maps[1415] = Eastern Kingdoms`? **No** — keep retail ids (12/13); tests use them.
  Add a dungeon map that is a child of 52 but with its own `cont` (`[291] The Deadmines` already exists) and a Kalimdor
  zone (`[1]` Durotar exists) for the cross-continent test.
- `WorldMapFrame`: `SetMapID(id)` (sets `mapID`, calls `self:OnMapChanged()`); `OnMapChanged()` → every provider's
  `OnMapChanged` (default `RefreshAllData`); `GetCanvas()` → `ScrollContainer.Child` (Frame); `ScrollContainer:
  GetCanvasScale()` → 1; `Show()`/`Hide()` run `OnShow`/`OnHide` scripts **and** providers' `OnShow`/`OnHide`;
  `HideUIPanel(WorldMapFrame)`/`ShowUIPanel` already count calls; global `OpenWorldMap(id)` → `M.worldMapOpened =
  id`; `ShowUIPanel(WorldMapFrame)`; `WorldMapFrame:SetMapID(id)` (blocked in combat like ShowUIPanel); global
  `ToggleWorldMap()`. `AcquirePin(template, ...)` must honour the template name: `WaypointTrackerRoutePinTemplate` →
  `Mixin(pin, _G.WaypointTrackerRoutePinMixin)` with regions `Icon`, `Number` (FontString), `Highlight`;
  `RemoveAllPinsByTemplate(template)` removes only that template's pins (keep the current behaviour when `template` is nil).
- `PIN_FRAME_LEVEL_WAYPOINT_LOCATION` constant string if referenced; `UnitLevel` exists (keep); `Enum.UIMapType.World = 1`.
**Acceptance**: all existing suites pass unchanged; `run_mock_selftest.lua` exercises each addition once
(`CreateLine` returns an object with `SetStartPoint`; `SetMapID` triggers a provider's `RefreshAllData`;
`GetMapRectOnMap(13, 947)` returns 4 numbers; `OpenWorldMap(52)` shows the map on 52 and is blocked in combat).

### R3 — Geo
**Owns**: `WaypointTracker/Geo.lua`, `tests/run_geo.lua`.
**Work**: §8 Geo additions (`ParentChain`, `ContinentID`, `WorldMapID`, `IsWorldMap`, `ProjectToMap`, `CommonMap`),
pcall around `C_Map.GetMapRectOnMap`. No behaviour change to existing functions.
**Acceptance** (`tests/run_geo.lua`): stops all on 37 → `CommonMap` = 37; 37 + 52 (both EK) → 13; 37 + 1 (Durotar,
Kalimdor) → 947 with `shown == 2` and `ProjectToMap(37, .5, .5, 947)` inside `M.worldRects[13]`; 52 + 291 (Deadmines,
own instance) → 52 with `shown == 1`; micro map 5001 (Deathknell) + 18 → 18; `C_Map.GetMapRectOnMap = nil` → 37 + 1
returns `MainMap` and the count of stops on it; `run_bare` passes.

### R4 — Scaffold
**Owns**: `WaypointTracker/WaypointTracker.toc`, new stub files `WaypointTracker/RouteMap.lua` and
`WaypointTracker/RoutePreview.lua` (content: `local _, ns = ...` + `ns.RouteMap = {}` / `ns.RoutePreview = {}`).
**Work**: TOC load order `… Routes.lua, RoutesNet.lua, RouteMap.lua, RoutePreview.lua, RoutesUI.lua …`; `## Version:
1.2.0`. Nothing else.
**Acceptance**: `run_tests`, `run_routes`, `run_tab_routes`, `run_bare` pass unchanged; `ns.RouteMap` and
`ns.RoutePreview` exist after load.

### R5 — Seeds data
**Owns**: `WaypointTracker_Data/RouteSeeds.lua`, new `tests/check_seeds.lua`.
**Work**: convert every line to the 7-column format (§2.2) and rename per §2.3/§2.4; move `Lv…;` into `levels`; strip
`(A) `/`(H) ` into `faction`; expand abbreviations in names and notes; keep `stops` byte-for-byte. Write
`tests/check_seeds.lua` (loads the file with `WaypointTrackerData = {}` in a sandboxed env, then checks rules N1–N7:
columns, enums, levels grammar, digit ban + allowlist, forbidden prefixes, abbreviation tokens in name and note,
≤ 36-char names, unique `(cat, faction, spec)`, unique names per faction, non-empty stops matching the token grammar).
Print a summary (`876 seeds OK`). The agent may write a one-off conversion script in `scratchpad/` but the result is
reviewed line by line against the examples.
**Acceptance**: `$LUA tests/check_seeds.lua` OK; `awk -F'\t' 'NF!=7' RouteSeeds.lua` empty; sample spot checks: lines
for examples 1, 8, 9, 20, 23, 24, 26, 30, 38 read exactly as in §2.4.

### R6 — Routes.lua
**Owns**: `WaypointTracker/Routes.lua`, `tests/run_routes.lua`.
**Work**: 7-column parser; `faction`/`levels` fields; id `s-Hash(cat|faction|spec)`; `ParseLevels`, `LevelText`,
`FitsLevel`, `FactionText`, `StopTitle`; generated names without zone (`Make(out, …, g.name, …)`, `L.ROUTE_SUGGESTED_CHESTS`,
`L.ROUTE_SUGGESTED_RARES`); keep `Validate` dropping unknown fields for *shared* routes (`lv`/`faction` only ever come
from seeds: set them on `r` after `Validate` in `FromSeeds`, like `src`/`unordered`). Update the seed lines in
`tests/run_routes.lua:80-84` to 7 columns and add: levels parse (`"5-8"`, `"14+"`, `"35"`, `""`), `FitsLevel` for a level
inside/outside/nil, faction column hides Horde seeds from Alliance, generated names have no " - " zone suffix, ids are
stable when only the name changes.
**Acceptance**: `run_routes` passes; `run_tests` passes (it does not read seed names).

### R7 — RouteMap widget
**Owns**: `WaypointTracker/RouteMap.lua` (replaces the stub), `tests/run_routemap.lua`.
**Work**: §3.2–3.4, §8. Depends on Geo (wave 1) and on `Routes.Prepare` (exists). No dependency on RoutesUI.
**Acceptance** (`tests/run_routemap.lua`): `RouteMap.Art(37)` returns `w = 1002, h = 668`, 12 base tiles at
`(col*256, row*256)` row-major (file `37*1000 + (row-1)*4 + col`), plus 4 overlay tiles from `M.explored[37]` with the
last column 44 px wide and `tcx = 44/64`; `Art(id)` with `noArt` → nil; `Create` + `SetRoute(route on 37)` makes
`#pins == #pts`, pin 1 uses the green texture, `#lines == #pts − 1` for `order`, `== #pts` for `loop` with the last line
alpha < 0.5, `0` for `nearest`; a 37+1 route picks map 947 and the elsewhere line is hidden; a 52+291 route shows the
elsewhere text with `1` and `The Deadmines`; `Refresh()` shows the player arrow when `M.player` is on 37 and hides it
when on Durotar; clicking the box calls `onClick(route, 37)`; `SetRoute(nil)` hides everything; `run_bare` (no
`CreateLine`, no `C_MapExplorationInfo`, no `SetClipsChildren`) still builds the fallback box with pins.

### R8 — World-map preview
**Owns**: `WaypointTracker/RoutePreview.lua` (replaces the stub), `WaypointTracker/Templates.xml`,
`tests/run_routepreview.lua`.
**Work**: §4. The XML gains `WaypointTrackerRoutePinTemplate` next to the existing pin template. `Setup` on `LOGIN`
(+ `ContinueOnAddOnLoaded`), provider, pins, lines, bar, `End` rules, `ROUTE_PREVIEW` event, `ROUTES_CHANGED` hook.
Calls `ns.Window.Hide/Show` and `ns.RoutesUI.Select` nil-guarded.
**Acceptance** (`tests/run_routepreview.lua`): `Show(id, 37)` hides `WaypointTrackerFrame`, `M.worldMapOpened == 37`,
`WorldMapFrame:GetMapID() == 37`, `#WorldMapFrame.pins == #pts`, pin 1 green, bar text `ROUTE_PREVIEW_BAR:format(name,
#pts)`; `SetMapID(1)` (player browses to Durotar) → 0 pins and bar shows `ROUTE_PREVIEW_OFFMAP` + Show Them; Show Them
→ back on 37; **Set This Route** → `Routes.Run().id == id` (with `M.autoAltPopup` when waypoints exist), preview ended
(`Current() == nil`, pins removed), map still shown; `Show` again then **Back** → map hidden, window shown on
`routes`, `RoutesUI.widgets.detail.route.id == id`; `Show` then `WorldMapFrame:Hide()` → `Current() == nil`, window not
reopened; combat → `Show` returns `false, "combat"`, no `M.actionBlocked`, window unchanged; `WorldMapFrame = nil`
(bare) → `false, "nomap"`; `OpenWorldMap = nil` → fallback path still opens on 37; `Routes.Delete(id)` during a
preview ends it.

### R9 — RoutesUI integration
**Owns**: `WaypointTracker/RoutesUI.lua`, `tests/run_tab_routes.lua`.
**Work**: §3.5–3.7, §5: two-line rows (`rowHeight = 36`, `.sub`, votes only when voted, no stop count), row tooltip,
detail re-flow (`widgets.map = RouteMap.Create(detail, 290, 160)` when `ns.RouteMap.Create` exists, else the current
layout without a preview), meta lines with `Routes.LevelText/FactionText` (nil-guarded until R6 lands — code
`R().LevelText and R().LevelText(r)`), `ROUTE_SPANS` when `RouteMap.MapFor(r)` is not `r.zone`, stop list in the body,
`[Start/Stop] [Share…/Skip] [More ▾]` with the More menu, sort `level`, hay additions, `map.onClick = function(r, m)
local ok, why = ns.RoutePreview.Show(r.id, m); if not ok then Status(why == "combat" and L.IN_COMBAT_NO_PANELS or
L.ROUTE_PREVIEW_UNAVAILABLE) end end`, `onUpdate` → `widgets.map:Refresh()`. Keep every public function and the
`widgets` keys listed in DESIGN §10 (add `map`, `more`). Rewrite the parts of `run_tab_routes.lua` that assert the old
2×3 buttons/row text; keep every other assertion.
**Acceptance** (`tests/run_tab_routes.lua`): rows are 36 high with `.sub == "<zone> · <category>"`, `.right` empty when
unvoted and `"▲ 1"` after an upvote; row text has no digits for a ready-made gathering route; selecting a row shows
`widgets.map` with `#pins == #pts`; action row has exactly 3 visible buttons, the third `L.ROUTE_MORE`; More menu
(`M.lastMenu`) for a mine route lists Edit / Copy text / Delete, for a shared route Copy text / Remove / Hide This
Author; Delete via the menu still asks (`WAYPOINTTRACKER_ROUTE_DELETE`); sort menu has 4 entries and `level` puts a
`lv`-fitting route first (stub `UnitLevel`); clicking `widgets.map` calls `ns.RoutePreview.Show` (spy) with the route id
and 37; in combat the status line shows `IN_COMBAT_NO_PANELS`; body text contains `L.ROUTE_STOPS_HEADER` and `"1. "`;
everything that passed before still passes (pages, popups, recorder, share menu, fallbacks).

### R10 — Integration, CI, docs (wave 3, alone)
**Owns**: everything (sequential): `.github/workflows/tests.yml` (add `lua5.1 tests/check_seeds.lua`; new `run_*`
suites are picked up by the loop; add `run_routemap`/`run_routepreview` to the `--bare` loop), `README.md`,
`CHANGELOG.md`, `docs/`, `tests/run_tests.lua`, and any request file from R1–R9.
**Work**: run every suite (`for f in tests/run_*.lua; do $LUA $f; done`, `check_locales`, `check_api`, `check_seeds`,
`run_bare`, `WT_PLAIN_VECTORS=1` variants); apply `requests/*.md`; README Routes section: names, preview, world-map
preview, Set This Route; CHANGELOG 1.2.0; screenshots list in `docs/` if referenced.
**Acceptance**: CI green locally; `grep -rn "ROUTE_SUGGESTED_NAME" WaypointTracker tests` empty; a full manual
checklist for the owner written to `scratchpad/ux/ROUTES_CHECKLIST.md` (open Routes, click a skinning route → zone
art + pins; click a flight-path tour → continent; click a two-continent library tour → world map; click the preview →
map opens, bar shows; Set → replace/add question → pins become waypoints; Back → window returns).

### Mock additions summary (all in R2)
`CreateLine` + Line methods · `SetClipsChildren` · `SetDrawLayer` · `SetRotation` · `C_Map.GetMapArtID/MapHasArt/
GetMapArtLayers/GetMapArtLayerTextures/GetMapRectOnMap` · `M.worldRects` · `C_MapExplorationInfo.GetExploredMapTextures`
+ `M.explored` · `WorldMapFrame:SetMapID/OnMapChanged/GetCanvas`, `ScrollContainer:GetCanvasScale`, provider
`OnShow/OnHide` on map show/hide · `OpenWorldMap`, `ToggleWorldMap`, `M.worldMapOpened` · template-aware `AcquirePin`
/ `RemoveAllPinsByTemplate` with `WaypointTrackerRoutePinMixin` · `Enum.UIMapType.World`.
