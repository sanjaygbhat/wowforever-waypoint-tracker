-- Routes, item sources and the newer window behaviour, against the fake
-- WoW API. Run from the repository root:
--     lua5.1 tests/run_routes.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end

WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local WP, Routes, L = ns.WP, ns.Routes, ns.L

-- Seed metadata: ranges, a minimum level, a single level, or no restriction.
check(Routes.SEED_COLUMNS == 7, "seed format has seven columns")
local range = Routes.ParseLevels("5-8")
local up = Routes.ParseLevels("14+")
local single = Routes.ParseLevels("35")
check(range and range.min == 5 and range.max == 8, "level range parses")
check(up and up.min == 14 and up.max == nil, "minimum level parses")
check(single and single.min == 35 and single.max == 35, "single level parses")
check(Routes.ParseLevels("") == nil and Routes.ParseLevels(nil) == nil, "unspecified levels have no range")
for _, text in ipairs({ "8-5", "5-0", "0", "0+", "5-2147483648", "5.5", "5--8", "5-", "levels 5-8" }) do
    check(Routes.ParseLevels(text) == nil, "invalid levels are ignored: " .. text)
end
check(Routes.FitsLevel({ lv = range }, 5) == true and Routes.FitsLevel({ lv = range }, 8) == true,
    "range includes both edges")
check(Routes.FitsLevel({ lv = range }, 6) == true, "level inside range fits")
check(Routes.FitsLevel({ lv = range }, 4) == false and Routes.FitsLevel({ lv = range }, 9) == false,
    "levels outside range do not fit")
check(Routes.FitsLevel({ lv = up }, 14) == true and Routes.FitsLevel({ lv = up }, 60) == true
    and Routes.FitsLevel({ lv = up }, 13) == false, "minimum level has no upper limit")
check(Routes.FitsLevel({ lv = single }, 35) == true and Routes.FitsLevel({ lv = single }, 34) == false,
    "single level fits only that level")
check(Routes.FitsLevel({}, 20) == nil and Routes.FitsLevel(nil, 20) == nil
    and Routes.FitsLevel({ lv = range }, nil) == nil, "missing range or player level has no match")
check(Routes.LevelText({ lv = range }) == (rawget(L, "ROUTE_LEVELS") or "Levels %d\226\128\147%d"):format(5, 8),
    "range text uses the level range string")
check(Routes.LevelText({ lv = up }) == (rawget(L, "ROUTE_LEVELS_UP") or "Level %d and up"):format(14),
    "minimum level text uses the level and up string")
check(Routes.LevelText({ lv = single }) == (rawget(L, "ROUTE_LEVEL") or "Level %d"):format(35),
    "single level text uses the single level string")
check(Routes.LevelText({}) == nil and Routes.LevelText(nil) == nil, "unspecified levels have no text")
check(Routes.FactionText({ faction = "A" }) == (rawget(L, "ROUTE_FACTION_A") or "Alliance only")
    and Routes.FactionText({ faction = "H" }) == (rawget(L, "ROUTE_FACTION_H") or "Horde only"),
    "faction text uses the faction strings")
check(Routes.FactionText({}) == nil and Routes.FactionText(nil) == nil, "unrestricted routes have no faction text")
check(Routes.StopTitle({ pts = { { t = "Copper Vein" } } }, 1) == "Copper Vein", "stop title uses the point title")
check(Routes.StopTitle({ pts = { {}, { t = "" } } }, 1) == L.ROUTE_UNNAMED
    and Routes.StopTitle({ pts = { {}, { t = "" } } }, 2) == L.ROUTE_UNNAMED
    and Routes.StopTitle({ pts = {} }, 1) == L.ROUTE_UNNAMED
    and Routes.StopTitle(nil, 1) == L.ROUTE_UNNAMED, "untitled or absent stops use the unnamed fallback")

-- /wp toggles the single window on its last tab.
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "")
check(WaypointTrackerFrame and WaypointTrackerFrame:IsShown(), "/wp opens the waypoint window")
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "")
check(not WaypointTrackerFrame:IsShown(), "/wp again closes the window")
check(_G.WaypointTrackerArrowFind == nil, "no Find button by the arrow")

-- every item with a seller can be found, with all its sellers
local t0 = os.clock()
check(ns.DB.Load(), "database loads")
local loadTime = os.clock() - t0
local dye = ns.DB.items[2605]
check(dye and dye.name == "Green Dye", "Green Dye is in the database")
local sellers = {}
for _, id in ipairs(dye and dye.soldBy or {}) do
    sellers[id] = true
end
check(sellers[3366] and sellers[3367] and sellers[3364] and sellers[4775], "Green Dye's Orgrimmar and Undercity sellers are all known")
local thread = ns.DB.items[2321]
check(thread and #thread.soldBy > 10, "Fine Thread is sold by many vendors")

-- ready-made routes for every zone, of every kind
t0 = os.clock()
local all = Routes.Suggested()
local genTime = os.clock() - t0
local cats, maps, generated = {}, {}, {}
for _, r in ipairs(all) do
    cats[r.cat] = (cats[r.cat] or 0) + 1
    maps[r.zone or 0] = true
    check(Routes.ValidID(r.id), "ready-made route id is valid: " .. tostring(r.id))
    if not r.id:find("^s%-") then
        check(not r.name:find(" - ", 1, true), "generated name has no zone suffix: " .. r.name)
        if r.id:find("^g%d") or r.id:find("^f%d") then
            check(r.name == r.pts[1].t, "gathering name is the database node title")
            generated[r.cat] = true
        elseif r.id:find("^c%-") then
            check(r.name == (L.ROUTE_SUGGESTED_CHESTS:gsub(" %- %%s$", "")), "chest name uses the short locale string")
            generated.chests = true
        elseif r.id:find("^r%-") then
            check(r.name == (L.ROUTE_SUGGESTED_RARES:gsub(" %- %%s$", "")), "rare name uses the short locale string")
            generated.rares = true
        end
    end
end
local nmaps = 0
for _ in pairs(maps) do
    nmaps = nmaps + 1
end
check(#all > 20, "lots of ready-made routes (" .. #all .. ")")
check((cats.herbs or 0) > 0 and (cats.mining or 0) > 0, "herb and mining routes")
check((cats.treasure or 0) > 0, "treasure / rare routes")
check(nmaps > 5, "routes across many zones (" .. nmaps .. ")")
check(generated.mining and generated.herbs and generated.fishing and generated.chests and generated.rares,
    "short names are checked for every generated route kind")
check(Routes.Suggested() == all, "ready-made routes are worked out once")
local loop
for _, r in ipairs(all) do
    if r.unordered and #r.pts > 5 then
        loop = r
        break
    end
end
check(loop ~= nil, "a loop waits to be put in order")
if loop then
    Routes.Prepare(loop)
    check(not loop.unordered, "preparing puts it in order")
end
local listed = Routes.All()
check(#listed >= #all, "browsing lists the ready-made routes")

-- hand-picked routes from the data file
WaypointTrackerData.routeSeeds = table.concat({
    "quests\tnearest\tA\t5-8\tQuest test\tA note\tP1411:10,10,One;P1411:20,20,Two;P1411:30,30,Three",
    "travel\torder\tH\t14+\tHorde only\t\tP1411:10,10,One;P1411:20,20,Two;P1411:30,30,Three",
    "other\torder\t\t\tToo short\t\tP1411:10,10,One",
    "other\torder\t\t35\tSingle level\t\tP1411:10,10,One;P1411:20,20,Two;P1411:30,30,Three",
    "travel\torder\t\t\tUnrestricted\t\tP1411:10,10,One;P1411:20,20,Two;P1411:30,30,Three",
    "travel\torder\tX\t\tInvalid faction\t\tP1411:10,10,One;P1411:20,20,Two;P1411:30,30,Three",
    "quests\tnearest\tOld format\tA note\tP1411:10,10,One;P1411:20,20,Two;P1411:30,30,Three",
}, "\n")
local seedText = WaypointTrackerData.routeSeeds
local nativeFaction = UnitFactionGroup
UnitFactionGroup = function() return "Alliance" end
ns.DB.generation = ns.DB.generation + 1
all = Routes.Suggested()
local seed, horde, short, singleSeed, unrestricted, invalid, oldFormat
for _, r in ipairs(all) do
    if r.name == "Quest test" then
        seed = r
    elseif r.name:find("Horde only", 1, true) then
        horde = r
    elseif r.name == "Too short" then
        short = r
    elseif r.name == "Single level" then
        singleSeed = r
    elseif r.name == "Unrestricted" then
        unrestricted = r
    elseif r.name == "Invalid faction" then
        invalid = r
    elseif r.name == "Old format" then
        oldFormat = r
    end
end
check(seed and #seed.pts == 3 and seed.pts[2].t == "Two" and seed.note == "A note" and seed.mode == "nearest", "a hand-picked route is read")
check(seed and seed.id:find("^s%-"), "hand-picked routes get a stable id")
check(seed and seed.faction == "A" and seed.lv and seed.lv.min == 5 and seed.lv.max == 8,
    "seed columns supply faction and levels after validation")
check(singleSeed and singleSeed.lv and singleSeed.lv.min == 35 and singleSeed.lv.max == 35,
    "single-level seed retains its level")
check(unrestricted and unrestricted.faction == nil and unrestricted.lv == nil, "empty seed metadata stays nil")
check(not short, "routes with fewer than 3 stops are left out")
check(not invalid and not oldFormat, "invalid faction and old five-column seeds are skipped safely")
check(not horde, "faction column hides Horde-only routes from the Alliance")
local validated = seed and Routes.Validate(seed)
check(validated and validated.lv == nil and validated.faction == nil, "validation drops seed-only fields")
local parsed = seed and Routes.Parse(Routes.Serialize(seed))
check(parsed and parsed.lv == nil and parsed.faction == nil, "sharing does not serialize seed-only metadata")

UnitFactionGroup = function() return "Horde" end
ns.DB.generation = ns.DB.generation + 1
local alliance
for _, r in ipairs(Routes.Suggested()) do
    if r.name == "Horde only" then horde = r end
    if r.name == "Quest test" then alliance = r end
end
check(not alliance and horde and horde.faction == "H" and horde.lv and horde.lv.min == 14 and horde.lv.max == nil,
    "Horde sees its seed and levels, without a faction tag in the name")
check(horde and unrestricted and horde.id ~= unrestricted.id, "faction changes the id for otherwise identical seeds")

UnitFactionGroup = function() return "Alliance" end
WaypointTrackerData.routeSeeds = seedText:gsub("Quest test", "Renamed quest")
ns.DB.generation = ns.DB.generation + 1
local renamed
for _, r in ipairs(Routes.Suggested()) do
    if r.name == "Renamed quest" then renamed = r end
end
check(seed and renamed and renamed.id == seed.id, "seed id is stable when only its name changes")
check(singleSeed and unrestricted and singleSeed.id ~= unrestricted.id, "category changes the id for the same faction and stops")
UnitFactionGroup = nativeFaction

-- starting a ready-made route keeps it and sets its stops
WP.ClearAll(true)
check(Routes.Apply(seed.id, "replace"), "a ready-made route starts")
check(WP.Count() == 3 and Routes.Run() and Routes.Run().id == seed.id, "its stops are your waypoints")
Routes.Stop(true)

-- recording a route as you go
Routes.RecordStart()
check(Routes.Recording() ~= nil, "recording starts")
check(Routes.RecordAdd("A"), "a stop is added by hand")
M.player.wx = M.player.wx + 100
M.Tick(0.2)
check(Routes.RecordAdd("B"), "a second stop")
M.player.wx = M.player.wx + 100
M.Tick(0.2)
Routes.RecordAdd("C")
local draft = Routes.RecordFinish()
check(draft and #draft.pts == 3 and draft.mode == "order", "finishing gives a draft in order")
check(not Routes.Recording(), "recording stopped")
local saved = Routes.SaveMine(draft)
check(saved and saved.public and Routes.IsMine(saved), "a saved route is yours and shared")

-- Routes uses the shared window, pages and context menus
ns.RoutesUI.Show()
M.Tick(0.1)
check(ns.RoutesUI.IsShown(), "Routes tab opens")
local f = ns.RoutesUI.Frames()
check(ns.RoutesUI.widgets.detail.body:GetText() == L.ROUTES_HELP_TEXT
    and not ns.Window.CurrentPage("routes"), "first-open help is inline in the detail pane")
ns.RoutesUI.ShowCreate()
ns.RoutesUI.ShowShare(saved, true)
f = ns.RoutesUI.Frames()
check(f.create and f.create:IsVisible()
    and ns.Window.CurrentPage("routes").title == L.ROUTE_CREATE_TITLE, "Create opens a Routes page")
check(M.lastMenu and M.lastMenu.items[1].text == L.ROUTE_SHARE_SAVED_TITLE, "Share opens a context menu")
Routes.RecordStart()
f = ns.RoutesUI.Frames()
check(f.recorder and f.recorder:IsShown(), "the recorder bar shows while recording")
Routes.RecordCancel()
check(not f.recorder:IsShown(), "and goes away when cancelled")

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("database load %.2fs, ready-made routes %.2fs (%d)"):format(loadTime, genTime, #all))
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
