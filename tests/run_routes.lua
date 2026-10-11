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
local cats, maps = {}, {}
for _, r in ipairs(all) do
    cats[r.cat] = (cats[r.cat] or 0) + 1
    maps[r.zone or 0] = true
    check(Routes.ValidID(r.id), "ready-made route id is valid: " .. tostring(r.id))
end
local nmaps = 0
for _ in pairs(maps) do
    nmaps = nmaps + 1
end
check(#all > 20, "lots of ready-made routes (" .. #all .. ")")
check((cats.herbs or 0) > 0 and (cats.mining or 0) > 0, "herb and mining routes")
check((cats.treasure or 0) > 0, "treasure / rare routes")
check(nmaps > 5, "routes across many zones (" .. nmaps .. ")")
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
    "quests\tnearest\tQuest test\tA note\tP1411:10,10,One;P1411:20,20,Two;P1411:30,30,Three",
    "travel\torder\t(H) Horde only\t\tP1411:10,10,One;P1411:20,20,Two;P1411:30,30,Three",
    "other\torder\tToo short\t\tP1411:10,10,One",
}, "\n")
ns.DB.generation = ns.DB.generation + 1
all = Routes.Suggested()
local seed, horde, short
for _, r in ipairs(all) do
    if r.name == "Quest test" then
        seed = r
    elseif r.name:find("Horde only", 1, true) then
        horde = r
    elseif r.name == "Too short" then
        short = r
    end
end
check(seed and #seed.pts == 3 and seed.pts[2].t == "Two" and seed.note == "A note" and seed.mode == "nearest", "a hand-picked route is read")
check(seed and seed.id:find("^s%-"), "hand-picked routes get a stable id")
check(not short, "routes with fewer than 3 stops are left out")
local faction = UnitFactionGroup and UnitFactionGroup("player")
if faction == "Alliance" then
    check(not horde, "Horde-only routes are hidden from the Alliance")
else
    check(horde and horde.name == "Horde only", "faction routes show for that faction, without the tag")
end

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
