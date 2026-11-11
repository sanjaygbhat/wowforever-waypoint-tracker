-- Regression: every key binding and the arrival rules, checked by what the
-- player sees change (an adversarial review showed bindings, /cway and the
-- arrival settings could be broken without any test failing).
-- Run from repo root: lua5.1 tests/run_entry_points.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. message) end
end

WaypointTrackerDB = nil
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN'); M.FireEvent('PLAYER_ENTERING_WORLD')
M.Tick(0.1)
local WP, Window, Routes, Geo, L = ns.WP, ns.Window, ns.Routes, ns.Geo, ns.L
M.player.wx, M.player.wy, M.player.inst = -1000, -1500, 0 -- Elwynn

-- ---------------------------------------------------------------------------
-- 1. Bindings.xml: each binding names a real global, has a label, and runs.
-- ---------------------------------------------------------------------------
local xml = assert(io.open('WaypointTracker/Bindings.xml')):read('*a')
local bindings = {}
for name, body in xml:gmatch('<Binding name="([%w_]+)"[^>]*>(.-)</Binding>') do
    bindings[#bindings + 1] = { name = name, body = body:gsub('^%s+', ''):gsub('%s+$', '') }
end
check(#bindings >= 12, 'Bindings.xml lists the key bindings (got ' .. #bindings .. ')')
local run = {}
for _, b in ipairs(bindings) do
    local fn = b.body:match('^([%w_]+)%(%)$')
    check(fn ~= nil, b.name .. ' calls one function')
    check(fn and type(_G[fn]) == 'function', b.name .. ' calls an existing function: ' .. tostring(fn))
    check(type(_G['BINDING_NAME_' .. b.name]) == 'string' and _G['BINDING_NAME_' .. b.name] ~= '', b.name .. ' has a label in Key Bindings')
    run[b.name] = function() return _G[fn]() end
end
check(type(BINDING_HEADER_WAYPOINTTRACKER) == 'string', 'Key Bindings has a Waypoint Tracker header')

local function Press(name)
    local f = run[name]
    if not f then check(false, 'binding missing: ' .. name); return end
    local ok, err = pcall(f)
    check(ok, name .. ' runs without error: ' .. tostring(err))
end

-- Window and tabs
Window.Hide()
Press('WAYPOINTTRACKER_TOGGLE')
check(Window.IsShown(), 'Toggle window opens the window')
Press('WAYPOINTTRACKER_TOGGLE')
check(not Window.IsShown(), 'Toggle window closes it again')
Press('WAYPOINTTRACKER_FIND')
check(Window.IsShown() and Window.GetTab() == 'find', 'Find binding opens the Find tab')
Window.Hide()
Press('WAYPOINTTRACKER_ROUTES')
check(Window.IsShown() and Window.GetTab() == 'routes', 'Routes binding opens the Routes tab')
Window.Hide()

-- Waypoints
WP.ClearAll(true)
Press('WAYPOINTTRACKER_HERE')
local here = WP.GetActive()
local m, x, y = Geo.GetPlayerMapPosition()
check(WP.Count() == 1 and here and here.m == m and math.abs(here.x - x) < 0.001 and math.abs(here.y - y) < 0.001,
    'Add here puts a waypoint where you stand')
M.chatOpen, M.chatText = false, nil
Press('WAYPOINTTRACKER_SHARE')
check(M.chatText and M.chatText ~= '', 'Share opens chat with your spot (got ' .. tostring(M.chatText) .. ')')
check(WP.Count() == 1, 'Share does not add a waypoint')
Press('WAYPOINTTRACKER_CLEAR')
check(WP.Count() == 0 and WP.GetActive() == nil, 'Clear removes the active waypoint')

-- Closest: the farther one is active, the binding picks the nearer one.
local nearWp = WP.Add(m, x + 0.01, y, { title = 'Near', setActive = false })
local farWp = WP.Add(m, x + 0.2, y, { title = 'Far', setActive = true })
check(WP.GetActive() == farWp, 'setup: the far waypoint is active')
Press('WAYPOINTTRACKER_CLOSEST')
check(WP.GetActive() == nearWp, 'Closest binding makes the nearest waypoint active')

-- /cway does the same.
WP.SetActive(farWp, true)
M.TypeSlash(SlashCmdList.WAYPOINTTRACKERCWAY, '')
check(WP.GetActive() == nearWp, '/cway makes the nearest waypoint active')
WP.ClearAll(true)

-- Toggles
local function Flips(name, key)
    local before = ns.Get(key)
    Press(name)
    check(ns.Get(key) == not before, name .. ' flips ' .. key)
    Press(name)
    check(ns.Get(key) == before, name .. ' flips ' .. key .. ' back')
end
Flips('WAYPOINTTRACKER_ARROW', 'arrowShown')
Flips('WAYPOINTTRACKER_TREASURE', 'treasureHunt')
Flips('WAYPOINTTRACKER_TRAVEL', 'realRoutes')

-- Routes: record a stop by key, then step to the next stop by key.
Routes.RecordStart()
Press('WAYPOINTTRACKER_ROUTE_RECORD_ADD')
check(#Routes.Recording().pts == 1, 'Record stop binding adds a stop while recording')
M.player.wx = M.player.wx + 120; M.Tick(0.2)
Press('WAYPOINTTRACKER_ROUTE_RECORD_ADD')
M.player.wx = M.player.wx + 120; M.Tick(0.2)
Press('WAYPOINTTRACKER_ROUTE_RECORD_ADD')
local draft = Routes.RecordFinish()
check(draft and #draft.pts == 3, 'three stops recorded by key')
M.player.wx = -1000; M.Tick(0.2)
local saved = draft and Routes.SaveMine(draft)
check(saved and Routes.Apply(saved.id, 'replace'), 'the recorded route starts')
local first = WP.GetActive()
local count = WP.Count()
Press('WAYPOINTTRACKER_ROUTE_NEXT')
local second = WP.GetActive()
check(first and second and second ~= first and second.routeID == first.routeID and WP.Count() == count - 1,
    'Next stop binding moves the arrow to the next stop')
Routes.Stop(true)
WP.ClearAll(true)

-- ---------------------------------------------------------------------------
-- 2. Arriving at a waypoint, under each setting.
-- ---------------------------------------------------------------------------
-- The target is where the player starts; the others lie further along.
local HOME_X, HOME_Y = -1000, -1500
local function Setup()
    M.Tick(4) -- past the previous "You have arrived!" moment
    WP.ClearAll(true)
    M.player.wx, M.player.wy = HOME_X, HOME_Y
    M.Tick(0.2)
    local pm, px, py = Geo.GetPlayerMapPosition()
    M.player.wx = HOME_X + 300 -- walk away before the target exists
    M.Tick(0.2)
    local a = WP.Add(pm, px, py, { title = 'Target', setActive = true })
    local b = WP.Add(pm, px + 0.05, py + 0.05, { title = 'Second', setActive = false })
    local c = WP.Add(pm, px + 0.15, py + 0.15, { title = 'Third', setActive = false })
    WP.SetActive(a, true)
    M.Tick(0.2)
    return a, b, c
end
local function ArriveAt()
    M.player.wx, M.player.wy = HOME_X + 2, HOME_Y + 2
    M.Tick(0.6)
end

ns.Set('autoClear', true); ns.Set('autoNext', true)
local a, b = Setup()
ArriveAt()
check(not WP.IsValid(a), 'arriving removes the waypoint (autoClear on)')
check(WP.GetActive() == b, 'arriving moves the arrow to the closest remaining waypoint (autoNext on)')

ns.Set('autoNext', false)
a = Setup()
ArriveAt()
check(not WP.IsValid(a) and WP.GetActive() == nil and WP.Count() == 2,
    'with autoNext off nothing else becomes active and the others stay')

ns.Set('autoClear', false); ns.Set('autoNext', true)
a = Setup()
ArriveAt()
check(WP.IsValid(a) and WP.Count() == 3, 'with autoClear off the reached waypoint stays')
ns.Set('autoClear', true)
WP.ClearAll(true)

-- ---------------------------------------------------------------------------
-- Taint (1.2.4: "attempt to perform boolean test on field 'outOfRange' (a
-- secret boolean value, while execution tainted by 'WaypointTracker')" in
-- CompactUnitFrame). Every way to open Edit Mode must go through the secure
-- panel manager; none may call Blizzard's Edit Mode or Settings code directly.
-- ---------------------------------------------------------------------------
local function Leave() if EditModeManagerFrame:IsShown() then HideUIPanel(EditModeManagerFrame) end end
M.taintedCalls = {}
local entered = M.editModeEntered
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, 'editmode')
check(M.editModeEntered == entered + 1 and EditModeManagerFrame:IsEditModeActive(), '/wp editmode enters Edit Mode')
Leave()
local menu = M.OpenMenu(WaypointTrackerMinimapButton, 'RightButton')
local item = menu and M.FindMenuItem(menu, L.OPEN_EDIT_MODE)
check(item ~= nil, 'the quick menu has Edit Mode')
if item then M.PickMenuItem(menu, L.OPEN_EDIT_MODE) end
check(M.editModeEntered == entered + 2 and EditModeManagerFrame:IsEditModeActive(), 'the quick menu Edit Mode entry enters Edit Mode')
-- Selecting our arrow inside Edit Mode, then leaving it.
if ns.EditMode.Select then ns.EditMode.Select('arrow') end
Leave()
check(not EditModeManagerFrame:IsEditModeActive(), 'leaving Edit Mode works')
for _, b in ipairs(bindings) do
    local fn = b.body:match('^([%w_]+)%(%)$')
    if fn and type(_G[fn]) == 'function' then pcall(_G[fn]) end
end
Leave()
check(#M.taintedCalls == 0, 'no entry point runs Blizzard Edit Mode or Settings code tainted: ' .. table.concat(M.taintedCalls, ', '))

check(#M.errors == 0, 'entry points have no reported Lua errors')
for _, e in ipairs(M.errors) do print(e) end
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and #M.errors == 0 and 0 or 1)
