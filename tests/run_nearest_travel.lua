-- Regression: Nearest ranks by the way there, not as the crow flies. A spawn
-- a few yards closer but behind a city wall or across a measured barrier
-- loses to one you can walk to; Real routes off, or a plan that fails,
-- leaves straight-line ranking. Uses the real client map rectangles
-- (tools/fixtures/travel/UiMap*.csv) and the shipped travel data.
-- Run from repo root: lua5.1 tests/run_nearest_travel.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')

local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. message) end
end

local function csv(line)
    local t, field, quoted, i = {}, '', false, 1
    while i <= #line do
        local c = line:sub(i, i)
        if c == '"' then
            if quoted and line:sub(i + 1, i + 1) == '"' then field = field .. '"'; i = i + 1
            else quoted = not quoted end
        elseif c == ',' and not quoted then t[#t + 1] = field; field = ''
        else field = field .. c end
        i = i + 1
    end
    t[#t + 1] = field:gsub('\r$', '')
    return t
end
local function readCSV(path)
    local f = assert(io.open(path))
    local header, out = csv(f:read('*l')), {}
    for line in f:lines() do
        local values, row = csv(line), {}
        for i, h in ipairs(header) do row[h] = values[i] end
        out[#out + 1] = row
    end
    f:close(); return out
end

-- Real client rectangles replace the mock's made-up ones (which have no city maps).
local info, geometry = {}, {}
for _, r in ipairs(readCSV('tools/fixtures/travel/UiMap.csv')) do info[tonumber(r.ID)] = r end
for id in pairs(M.maps) do M.maps[id] = nil end
M.maps[947] = { mapID = 947, name = 'Azeroth', mapType = 1, parentMapID = 0 }
for _, r in ipairs(readCSV('tools/fixtures/travel/UiMapAssignment.csv')) do
    local id = tonumber(r.UiMapID)
    if id ~= 947 and not geometry[id] and tonumber(r.UiMin_0) == 0 and tonumber(r.UiMin_1) == 0
        and tonumber(r.UiMax_0) == 1 and tonumber(r.UiMax_1) == 1 and info[id] then
        local g = { mapID = id, name = info[id].Name_lang, cont = tonumber(r.MapID),
            top = tonumber(r.Region_3), left = tonumber(r.Region_4),
            h = tonumber(r.Region_3) - tonumber(r.Region_0), w = tonumber(r.Region_4) - tonumber(r.Region_1),
            mapType = tonumber(info[id].Type), parentMapID = tonumber(info[id].ParentUiMapID) }
        if g.w > 0 and g.h > 0 then geometry[id] = g; M.maps[id] = g end
    end
end
M.worldRects = { [1415] = { 0.55, 0.95, 0.10, 0.90 }, [1414] = { 0.05, 0.45, 0.10, 0.90 } }
-- The mock only knows seven made-up maps here: the player stands on the map
-- the test names.
function C_Map.GetBestMapForUnit()
    if M.player.noPosition then return nil end
    return M.player.map or (M.player.inst == 0 and 1415 or 1414)
end
function C_Map.GetMapInfoAtPosition(id) return C_Map.GetMapInfo(id) end

local faction = 'Alliance'
local unitFaction, unitLevel = UnitFactionGroup, UnitLevel
function UnitFactionGroup(unit) if unit == nil or unit == 'player' then return faction end return unitFaction(unit) end
function UnitLevel(unit) if unit == 'player' then return 60 end return unitLevel(unit) end
function UnitClass() return 'DRUID', 'DRUID' end
function UnitRace() return 'NightElf', 'NightElf' end
function GetUnitSpeed() return 0, 7, 7, 4.7 end
function IsMounted() return false end
function GetServerTime() return math.floor(M.now) + 1700000000 end
function GetBindLocation() return 'Dolanaar' end
function GetItemCount() return 0 end

local function PlaceOnMap(m, x, y)
    local g = assert(geometry[m], 'no geometry for map ' .. tostring(m))
    M.player.inst = g.cont
    M.player.wx, M.player.wy = g.top - y * g.h, g.left - x * g.w
    M.player.map = m
end

WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN'); M.FireEvent('PLAYER_ENTERING_WORLD')
M.noDataAddon = false
local DB, Geo, Find, WP, Travel = ns.DB, ns.Geo, ns.Find, ns.WP, ns.Travel
PlaceOnMap(1457, 0.40, 0.42) -- Darnassus, by the bank
M.Tick(0.2)
check(DB.Load(), 'database loads')


-- Counts what Nearest plans (Travel.Choices: the arrow's own planning).
local plans = 0
local choices = Travel.Choices
Travel.Choices = function(...) plans = plans + 1; return choices(...) end
local function Clicked(fn)
    plans = 0
    local start = os.clock()
    local a, b, c = fn()
    return (os.clock() - start) * 1000, plans, a, b, c
end
local function Settle(wp)
    for _ = 1, 400 do if wp then break end; M.Tick(0.05); wp = WP.GetActive() end
    return wp
end
local function Alchemy()
    local list = {}
    faction = 'Alliance'
    for _, e in ipairs(DB.TrainerEntries('trainer_profession_alchemy')) do list[#list + 1] = e end
    return list
end
local function Clear(entries) for _, e in ipairs(entries) do e.points = nil end end

-- 1. The Darnassus bank case with WP-1's collapse switched off: the trainer's
-- Teldrassil-map copy is the closest in a straight line, behind the city
-- wall for the planner. Nearest must still pick the Darnassus-side point.
DB._KeepCityTwins(true)
Clear(Alchemy())
local spots = { { 0.40, 0.42, 'by the bank' }, { 0.45, 0.30, 'north-east of the bank' } }
for _, s in ipairs(spots) do
    WP.ClearAll(true)
    PlaceOnMap(1457, s[1], s[2])
    M.Tick(0.2)
    local _, straight = DB.NearestOf(Alchemy(), { faction = true })
    check(straight and straight.m == 1438, 'premise, ' .. s[3] .. ': the closest copy in a straight line is on the Teldrassil map')
    local ms, n, wp = Clicked(function() return Find.GoToNearest('profession', 'alchemy') end)
    wp = Settle(wp)
    print(('  Nearest alchemy %s, twins kept: %.1f ms, %d planned'):format(s[3], ms, n))
    check(wp and wp.m == 1457, 'twins kept, ' .. s[3] .. ': Nearest gives the Darnassus-map point (got ' .. tostring(wp and wp.m) .. ')')
    check(wp and (wp.title or ''):find('Ainethil', 1, true), 'twins kept, ' .. s[3] .. ': Ainethil')
    check(n == 2, 'twins kept, ' .. s[3] .. ': two planned, the closer copy and the walkable one')
    if wp then
        M.Tick(3)
        check(Travel.Steer(wp) == nil, 'twins kept, ' .. s[3] .. ': no detour')
        local plan = Travel.Current()
        check(plan and plan.path and #plan.path == 2, 'twins kept, ' .. s[3] .. ': a two-stop plan')
    end
end
-- Real routes off: straight-line ranking, nothing planned
ns.Set('realRoutes', false)
WP.ClearAll(true)
PlaceOnMap(1457, 0.40, 0.42)
M.Tick(0.2)
local _, offPlans, offWp = Clicked(function() return Find.GoToNearest('profession', 'alchemy') end)
offWp = Settle(offWp)
check(offWp and offWp.m == 1438 and offPlans == 0, 'Real routes off: straight-line ranking (the Teldrassil copy), nothing planned')
ns.Set('realRoutes', true)
DB._KeepCityTwins(nil)
Clear(Alchemy())

-- 2. Closer in a straight line but across a wall or a river: loses to a
-- slightly farther one you can walk to.
local function Entries(a, b)
    return { { kind = 'npc', id = 990001, name = 'Across', fac = 'AH', extra = { { m = a[1], x = a[2], y = a[3], curated = true } } },
        { kind = 'npc', id = 990002, name = 'Walkable', fac = 'AH', extra = { { m = b[1], x = b[2], y = b[3], curated = true } } } }
end
local dg, tg = geometry[1457], geometry[1438]
local ewx, ewy = dg.top - 0.5 * dg.h, dg.left - 1.03 * dg.w -- 3% past Darnassus' east edge
local cases = {
    -- Darnassus' east side: outside the city map (Teldrassil) vs inside it
    { 'city wall', { 1457, 0.96, 0.50 }, { 1438, (tg.left - ewy) / tg.w, (tg.top - ewx) / tg.h }, { 1457, 0.88, 0.50 } },
    -- a measured barrier in Alterac Mountains (TravelData barriers, map 1416 y = 55.6)
    { 'barrier', { 1416, 0.30, 0.565 }, { 1416, 0.30, 0.553 }, { 1416, 0.30, 0.58 } },
}
for _, case in ipairs(cases) do
    PlaceOnMap(case[2][1], case[2][2], case[2][3])
    M.Tick(0.2)
    local list = Entries(case[3], case[4])
    local straight, _, sd = DB.NearestOf(list)
    local _, across = choices({ m = case[3][1], x = case[3][2], y = case[3][3] })
    local _, walk = choices({ m = case[4][1], x = case[4][2], y = case[4][3] })
    check(straight and straight.name == 'Across' and walk and #walk.path == 2 and across and #across.path > 2,
        'premise, ' .. case[1] .. ': the closer one needs a detour, the other is a direct walk')
    local ms, n, e, _, d = Clicked(function() return Find._Quickest(list) end)
    local ranked = DB.NearestCandidates(list, nil, 2)
    print(('  %s: %.0f vs %.0f yd straight; %.0f vs %.0f s planned; %.1f ms, %d planned'):format(case[1], sd,
        ranked[2] and ranked[2].d or -1, across and across.total or -1, walk and walk.total or -1, ms, n))
    check(e and e.name == 'Walkable' and n == 2, case[1] .. ': the walkable one wins, two planned')
    ns.Set('realRoutes', false)
    local offMs, offN, offE = Clicked(function() return Find._Quickest(list) end)
    check(offE and offE.name == 'Across' and offN == 0, case[1] .. ', Real routes off: straight-line ranking')
    ns.Set('realRoutes', true)
    -- the closest can't be planned: straight-line ranking
    Travel.Choices = function() plans = plans + 1; return {} end
    local _, failN, failE = Clicked(function() return Find._Quickest(list) end)
    check(failE and failE.name == 'Across' and failN == 1, case[1] .. ', planning fails: straight-line ranking')
    Travel.Choices = function(...) plans = plans + 1; return choices(...) end
end

-- 3. Budget: the closest is walkable, so nothing is planned (the usual click).
WP.ClearAll(true)
PlaceOnMap(1457, 0.40, 0.42)
M.Tick(0.2)
local services = { 'mailbox', 'innkeeper', 'flight', 'repair', 'vendor', 'banker', 'auctioneer' }
local total, planned = 0, 0
for _, s in ipairs(services) do
    local entries = DB.ServiceEntries(s)
    local ms, n = Clicked(function() return Find._Quickest(entries, { faction = true }) end)
    total, planned = total + ms, planned + n
end
local ms, n, wp = Clicked(function() return Find.GoToNearest('profession', 'alchemy') end)
wp = Settle(wp)
print(('  Darnassus bank, seven services and alchemy: %.1f ms, %d planned'):format(total + ms, planned + n))
check(planned == 0 and n == 0 and wp and wp.m == 1457, 'the usual click plans nothing')
check(#M.errors == 0, table.concat(M.errors, '\n'))

print(('run_nearest_travel: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
