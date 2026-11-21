-- Regression: one spot, one point. The classic source lists a city NPC on the
-- walled city's map and again on its parent zone's map, a few yards apart.
-- Nearest used to pick whichever copy was a yard closer; a zone-map copy made
-- Real routes say "Leave Darnassus" for a trainer inside Darnassus (1.5.0).
-- DB.Points drops the classic-derived zone-map copy when the same entry has a
-- city-map point within 150 yd and the copy lies inside the city map.
-- Uses the real client map rectangles (tools/fixtures/travel/UiMap*.csv).
-- Run from repo root: lua5.1 tests/run_city_points.lua
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

-- The walled city maps, read independently from the travel data's cities block.
local CITY = {}
for line in (ns.TravelData.cities or ''):gmatch('[^\n]+') do
    local m = tonumber(line:match('^(%d+)'))
    if m then CITY[m] = true end
end
check(CITY[1453] and CITY[1454] and CITY[1455] and CITY[1456] and CITY[1457] and CITY[1458], 'six walled city maps')

local function World(p)
    local g = geometry[p.m]
    if g then return g.cont, g.top - p.y * g.h, g.left - p.x * g.w end
end
local function Inside(p, city)
    local c, wx, wy = World(p)
    local g = geometry[city]
    if not c or c ~= g.cont then return false end
    local x, y = (g.left - wy) / g.w, (g.top - wx) / g.h
    return x >= 0 and x <= 1 and y >= 0 and y <= 1
end
local function Yards(a, b)
    local ac, ax, ay = World(a)
    local bc, bx, by = World(b)
    if not ac or ac ~= bc then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
-- A zone-map point inside a city rectangle within 150 yd of a city-map point
-- of the same entry: the twin WP-1 removes. Returns the nearest such point.
local function Twin(pts, p)
    if CITY[p.m] then return nil end
    local best, bestD
    for _, q in ipairs(pts) do
        if CITY[q.m] and Inside(p, q.m) then
            local d = Yards(p, q)
            if d <= 150 and (not bestD or d < bestD) then best, bestD = q, d end
        end
    end
    return best
end
-- Kept by rule: curated, corrected and observed (personal, imported or
-- shared-discovery) spots are never dropped; only classic-derived twins go.
local function Observed(e, p)
    if p.curated or p.fixed or p.c then return true end
    local lists = { not e.minedService and e.extra or nil }
    local base = (e.kind == 'object' and DB.objects or DB.units)[e.id]
    if base then lists[#lists + 1] = base.extra end
    for _, list in pairs(lists) do
        for _, q in ipairs(list) do if q == p then return true end end
    end
    return false
end

-- 1. Data invariant, both factions, every Nearest service and trainer service.
local SERVICES = { 'mailbox', 'innkeeper', 'flight', 'repair', 'vendor', 'banker', 'auctioneer',
    'stablemaster', 'spirithealer', 'battlemaster', 'meetingstone' }
local trainerServices = {}
for s in pairs(ns.Trainers.services) do trainerServices[#trainerServices + 1] = s end
for s in pairs(ns.Trainers.additionalServices or {}) do trainerServices[#trainerServices + 1] = s end
table.sort(trainerServices)
local entries, cityEntries, classicTwins, keptObserved = 0, 0, 0, 0
for _, side in ipairs({ 'Alliance', 'Horde' }) do
    faction = side
    local lists = {}
    for _, s in ipairs(SERVICES) do lists[#lists + 1] = { s, DB.ServiceEntries(s) } end
    for _, s in ipairs(trainerServices) do lists[#lists + 1] = { s, DB.TrainerEntries(s) } end
    for _, pair in ipairs(lists) do
        for _, e in ipairs(pair[2]) do
            entries = entries + 1
            local pts, onCity = DB.Points(e), false
            for _, p in ipairs(pts) do
                if CITY[p.m] then onCity = true end
                local q = Twin(pts, p)
                if q then
                    if Observed(e, p) then
                        keptObserved = keptObserved + 1
                    else
                        classicTwins = classicTwins + 1
                        if classicTwins <= 10 then
                            print(('  twin: %s %s %s (%s) %d:%.4f,%.4f, %.0f yd from %d:%.4f,%.4f'):format(side, pair[1],
                                tostring(e.name), tostring(e.id), p.m, p.x, p.y, Yards(p, q), q.m, q.x, q.y))
                        end
                    end
                end
            end
            if onCity then cityEntries = cityEntries + 1 end
        end
    end
end
faction = 'Alliance'
print(('Invariant: %d entries, %d with a city-map point, %d classic twins left, %d observed twins kept'):format(
    entries, cityEntries, classicTwins, keptObserved))
check(entries > 500 and cityEntries > 100, 'the invariant saw the service and trainer entries')
check(classicTwins == 0, 'no classic-derived zone-map twin of a city-map point is left (1.5.0 left 179 in this count)')

-- 2. The Darnassus twins named in the report: city point kept, Teldrassil copy gone.
local function Maps(e)
    local out = {}
    for _, p in ipairs(DB.Points(e)) do out[p.m] = (out[p.m] or 0) + 1 end
    return out
end
for _, id in ipairs({ 4160, 11041, 11042 }) do -- Ainethil, Milla Fairancora, Sylvanna Forestmoon
    local e = DB.units[id]
    local maps = e and Maps(e) or {}
    check(e and maps[1457] == 1 and not maps[1438], 'Darnassus trainer ' .. id .. ' has one point, on the Darnassus map')
end

-- 3. Controls that must survive: no city point of their own nearby.
for _, id in ipairs({ 1218, 1215 }) do -- Herbalist Pomeroy, Alchemist Mallory (Elwynn, outside Stormwind)
    local e = DB.units[id]
    check(e and Maps(e)[1429], 'Elwynn point kept: ' .. id)
end
for _, id in ipairs({ 14860, 6491 }) do -- Flik (Mulgore), a Mulgore spirit healer
    local e = DB.units[id]
    check(e and Maps(e)[1412], 'Mulgore point kept: ' .. id)
end

-- 4. The rules, on synthetic entries (the real Ainethil twin: 141 = Teldrassil,
-- 1657 = Darnassus; the city copy is 3 yd from the zone copy).
local function Pts(e) return DB.Points(e) end
local twin = Pts({ kind = 'npc', id = -1, coords = '141:286,519;1657:549,240' })
check(#twin == 1 and twin[1].m == 1457, 'classic twin collapses to the city point')
local cityOnly = Pts({ kind = 'npc', id = -2, coords = '1657:549,240' })
local zoneOnly = Pts({ kind = 'npc', id = -3, coords = '141:286,519' })
check(#cityOnly == 1 and #zoneOnly == 1 and zoneOnly[1].m == 1438, 'a lone zone-map point is never dropped')
-- far: inside the Darnassus rectangle, but more than 150 yd from the city point
local fx = 286
while Yards({ m = 1438, x = fx / 1000, y = 0.519 }, cityOnly[1]) <= 160 do fx = fx - 1 end
local far = { m = 1438, x = fx / 1000, y = 0.519 }
check(Inside(far, 1457) and Yards(far, cityOnly[1]) > 150, 'premise: far point inside Darnassus, > 150 yd')
local kept = Pts({ kind = 'npc', id = -4, coords = ('141:%d,519;1657:549,240'):format(fx) })
check(#kept == 2, 'a zone-map point more than 150 yd from the city point is kept')
-- near, but outside the city rectangle: never dropped (city guards at a gate)
local dg, tg = geometry[1457], geometry[1438]
local edge = { m = 1457, x = 0.98, y = 0.5, curated = true }
local wx, wy = dg.top - 0.5 * dg.h, dg.left - 1.03 * dg.w -- 3% past the east edge
local gx, gy = math.floor((tg.left - wy) / tg.w * 1000 + 0.5), math.floor((tg.top - wx) / tg.h * 1000 + 0.5)
local gate = { m = 1438, x = gx / 1000, y = gy / 1000 }
check(not Inside(gate, 1457) and Yards(gate, edge) <= 150, 'premise: zone point outside the Darnassus map, within 150 yd')
local outside = Pts({ kind = 'npc', id = -5, coords = ('141:%d,%d'):format(gx, gy), extra = { edge } })
check(#outside == 2, 'a zone-map point outside the city map is kept')
local curated = Pts({ kind = 'npc', id = -6, coords = '141:286,519',
    extra = { { m = 1438, x = 0.286, y = 0.519, curated = true }, { m = 1457, x = 0.556, y = 0.246, curated = true } } })
check(#curated == 2, 'a curated zone-map point is kept')
local seen = Pts({ kind = 'npc', id = -7, coords = '1657:549,240', extra = { { m = 1438, x = 0.286, y = 0.519 } } })
check(#seen == 2, 'a zone-map point the player saw is kept')
local fixed = Pts({ kind = 'npc', id = -8, coords = '1657:549,240', extra = { { m = 1438, x = 0.286, y = 0.519, fixed = true } } })
check(#fixed == 2, 'a corrected zone-map point is kept')
local curatedCity = Pts({ kind = 'npc', id = -9, coords = '141:286,519;1657:549,240',
    extra = { { m = 1457, x = 0.556, y = 0.246, curated = true } } })
check(#curatedCity == 1 and curatedCity[1].curated, 'a curated city point replaces the classic city copy and its zone twin')
-- the map API cannot place the zone point: keep it
local mapToWorld = Geo.MapToWorld
Geo.MapToWorld = function(m, x, y, p) if m == 1438 then return nil end return mapToWorld(m, x, y, p) end
local unplaced = Pts({ kind = 'npc', id = -10, coords = '141:287,518;1657:549,240' })
Geo.MapToWorld = mapToWorld
check(#unplaced == 2, 'a point the map API cannot place is kept')
-- the result is cached on the entry, as before
local cached = { kind = 'npc', id = -11, coords = '141:286,519;1657:549,240' }
check(DB.Points(cached) == DB.Points(cached) and cached.points, 'points stay cached on the entry')

-- 5. The reported case: Nearest Alchemy trainer from the Darnassus bank and
-- from three other spots in Darnassus (the choice used to depend on where you
-- stood). Each must give the Darnassus-map point, no detour, a two-stop plan.
local spots = { { 0.40, 0.42, 'by the bank' }, { 0.52, 0.18, 'north-west of the trainer' },
    { 0.60, 0.22, 'east of the trainer' }, { 0.45, 0.30, 'north-east of the bank' } }
for _, s in ipairs(spots) do
    WP.ClearAll(true)
    PlaceOnMap(1457, s[1], s[2])
    M.Tick(0.2)
    local wp = Find.GoToNearest('profession', 'alchemy')
    for _ = 1, 400 do if wp then break end; M.Tick(0.05); wp = WP.GetActive() end
    check(wp and wp.m == 1457, ('Nearest alchemy from %s is on the Darnassus map (got %s)'):format(s[3], tostring(wp and wp.m)))
    local title = wp and wp.title or ''
    check(title:find('Ainethil', 1, true) or title:find('Milla Fairancora', 1, true) or title:find('Sylvanna Forestmoon', 1, true),
        'Nearest alchemy from ' .. s[3] .. ' is a Darnassus trainer: ' .. title)
    if s[3] == 'by the bank' then check(title:find('Ainethil', 1, true), 'the reported case is Ainethil') end
    if wp then
        M.Tick(3)
        local steer = Travel.Steer(wp)
        local plan = Travel.Current()
        check(steer == nil, 'no detour from ' .. s[3] .. ': ' .. tostring(steer and steer.title))
        check(plan and plan.path and #plan.path == 2, 'a two-stop plan from ' .. s[3])
    end
end

print(('run_city_points: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
