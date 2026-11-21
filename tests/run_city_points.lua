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
-- One spawn listed twice, the twin WP-1 removes from service and trainer
-- entries: a zone-map point inside a city rectangle and a city-map point of
-- the same entry that are each other's nearest, within 12 yd.
local LIMIT = 12
-- (`classic`: the entry's classic-derived points; only those are compared)
local function Twin(pts, p, classic)
    if CITY[p.m] or not classic[p] then return nil end
    local best, bestD
    for _, q in ipairs(pts) do
        if CITY[q.m] and Inside(p, q.m) then
            local d = Yards(p, q)
            if not bestD or d < bestD then best, bestD = q, d end
        end
    end
    if not best or bestD > LIMIT then return nil end
    for _, o in ipairs(pts) do
        if o ~= p and classic[o] and not CITY[o.m] and Inside(o, best.m) then
            local d = Yards(o, best)
            if d < bestD or (d == bestD and o.x < p.x) then return nil end
        end
    end
    return best, bestD
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
local entries, cityEntries, dropped, wrong, seenBase = 0, 0, 0, 0, {}
-- Exactly the classic zone-map twins of `e` go when the rule covers it, and
-- nothing at all goes when it doesn't.
local function Compare(e, covered, label)
    if seenBase[e] or not e.coords then return end
    seenBase[e] = true
    e.points = nil; DB._KeepCityTwins(true)
    local all = DB.Points(e)
    e.points = nil; DB._KeepCityTwins(nil)
    -- (points from world positions are new tables each time: match by spot)
    local kept, keptSet, classic = DB.Points(e), {}, {}
    local function Key(p) return p.m .. ':' .. p.x .. ':' .. p.y end
    for _, p in ipairs(kept) do keptSet[Key(p)] = (keptSet[Key(p)] or 0) + 1 end
    for _, p in ipairs(all) do if not Observed(e, p) then classic[p] = true end end
    for _, p in ipairs(all) do
        local q, d
        if covered then q, d = Twin(all, p, classic) end
        if q then dropped = dropped + 1 end
        local left = (keptSet[Key(p)] or 0) > 0
        if left then keptSet[Key(p)] = keptSet[Key(p)] - 1 end
        if (q ~= nil) == left then
            wrong = wrong + 1
            if wrong <= 10 then
                print(('  %s: %s %s (%s) %d:%.4f,%.4f%s'):format(q and 'twin kept' or 'dropped, not a twin', label,
                    tostring(e.name), tostring(e.id), p.m, p.x, p.y, q and (', %.0f yd from %d:%.4f,%.4f'):format(d, q.m, q.x, q.y) or ''))
            end
        end
    end
end
for _, side in ipairs({ 'Alliance', 'Horde' }) do
    faction = side
    local lists = {}
    for _, s in ipairs(SERVICES) do lists[#lists + 1] = { s, DB.ServiceEntries(s) } end
    for _, s in ipairs(trainerServices) do lists[#lists + 1] = { s, DB.TrainerEntries(s) } end
    for _, pair in ipairs(lists) do
        for _, listed in ipairs(pair[2]) do
            entries = entries + 1
            -- the database entry whose points the collapse works on
            local e = (listed.kind == 'object' and DB.objects or DB.units)[listed.id] or listed
            for _, p in ipairs(DB.Points(listed)) do if CITY[p.m] then cityEntries = cityEntries + 1; break end end
            Compare(e, true, pair[1])
        end
    end
end
faction = 'Alliance'
-- every other NPC: covered unless it is an enemy; other objects: never
local npcs = 0
for _, e in pairs(DB.units) do
    if not seenBase[e] then npcs = npcs + 1 end
    Compare(e, not DB.IsEnemy(e), 'npc')
end
for _, e in pairs(DB.objects) do Compare(e, false, 'object') end
print(('Invariant: %d service/trainer entries (%d with a city-map point), %d other NPCs, %d twins dropped, %d points wrong'):format(
    entries, cityEntries, npcs, dropped, wrong))
check(entries > 500 and cityEntries > 100 and npcs > 5000 and dropped > 400, 'the invariant saw every entry and the twins')
check(wrong == 0, 'exactly the classic zone-map twins within 12 yd go (each other\'s nearest), and nothing else')

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

-- 3b. Enemies keep every spawn: one inside a city map's rectangle is out
-- beyond the walls (1.5.1 review: Lake Frenzy, Worg, Prairie Wolf Alpha's
-- nearest went from 12 yd to 188 yd, Cursed Darkhound).
local function Unchanged(e)
    e.points = nil
    DB._KeepCityTwins(true)
    local all = #DB.Points(e)
    e.points = nil
    DB._KeepCityTwins(nil)
    return all, #DB.Points(e)
end
for _, c in ipairs({ { 6033, 'Lake Frenzy' }, { 1765, 'Worg' }, { 2960, 'Prairie Wolf Alpha' },
    { 1548, 'Cursed Darkhound' } }) do
    local e = DB.units[c[1]]
    local all, kept = Unchanged(e or {})
    check(e and all > 0 and kept == all, ('%s keeps every spawn (%d of %d)'):format(c[2], kept, all))
end
PlaceOnMap(1412, 0.395, 0.283) -- Mulgore, by Thunder Bluff
M.Tick(0.2)
local _, _, wolf = DB.NearestOf({ DB.units[2960] })
check(wolf and wolf < 20, ('Prairie Wolf Alpha is still %s yd away'):format(wolf and ('%.0f'):format(wolf) or '?'))
PlaceOnMap(1457, 0.40, 0.42)
M.Tick(0.2)
-- a city guard: only its zone-map twins go (each within 12 yd of its city spot)
do
    local all, kept = Unchanged(DB.units[3296])
    check(kept < all and all - kept <= 3, ('Orgrimmar Grunt loses only its twins (%d of %d kept)'):format(kept, all))
end
-- and the service and trainer collapse is unchanged for these
for _, id in ipairs({ 4160, 11041, 11042 }) do
    local all, kept = Unchanged(DB.units[id])
    check(kept == all - 1, 'Darnassus trainer ' .. id .. ': exactly its one zone-map twin goes')
end

-- 4. The rules, on synthetic service entries (the real Ainethil twin: 141 =
-- Teldrassil, 1657 = Darnassus; the city copy is 3 yd from the zone copy).
local function Pts(e)
    if e.svc == nil then e.svc = { vendor = true } end
    if e.svc == false then e.svc = nil end
    return DB.Points(e)
end
local twin = Pts({ kind = 'npc', id = -1, coords = '141:286,519;1657:549,240' })
check(#twin == 1 and twin[1].m == 1457, 'classic twin collapses to the city point')
local creature = Pts({ kind = 'npc', id = -12, svc = false, coords = '141:286,519;1657:549,240' })
check(#creature == 2, 'an enemy (no faction): the twin is kept')
local resident = Pts({ kind = 'npc', id = -14, svc = false, fac = 'A', coords = '141:286,519;1657:549,240' })
check(#resident == 1 and resident[1].m == 1457, 'a friendly NPC with no service: the twin goes too')
local object = Pts({ kind = 'object', id = -15, svc = false, coords = '141:286,519;1657:549,240' })
check(#object == 2, 'an object with no service: the twin is kept')
local two = Pts({ kind = 'npc', id = -13, coords = '141:286,519,287,518;1657:549,240' })
check(#two == 2, 'two zone-map copies by one city point: only the nearer one goes')
local cityOnly = Pts({ kind = 'npc', id = -2, coords = '1657:549,240' })
local zoneOnly = Pts({ kind = 'npc', id = -3, coords = '141:286,519' })
check(#cityOnly == 1 and #zoneOnly == 1 and zoneOnly[1].m == 1438, 'a lone zone-map point is never dropped')
-- far: inside the Darnassus rectangle, but more than 12 yd from the city point
local fx = 286
while Yards({ m = 1438, x = fx / 1000, y = 0.519 }, cityOnly[1]) <= 14 do fx = fx - 1 end
local far = { m = 1438, x = fx / 1000, y = 0.519 }
check(Inside(far, 1457) and Yards(far, cityOnly[1]) > 12, 'premise: far point inside Darnassus, > 12 yd')
local kept = Pts({ kind = 'npc', id = -4, coords = ('141:%d,519;1657:549,240'):format(fx) })
check(#kept == 2, 'a zone-map point more than 12 yd from the city point is kept')
-- near, but outside the city rectangle: never dropped
local dg, tg = geometry[1457], geometry[1438]
local edge = { m = 1457, x = 0.998, y = 0.5, curated = true }
local wx, wy = dg.top - 0.5 * dg.h, dg.left - 1.004 * dg.w -- just past the east edge
local gx, gy = math.floor((tg.left - wy) / tg.w * 1000 + 0.5), math.floor((tg.top - wx) / tg.h * 1000 + 0.5)
local gate = { m = 1438, x = gx / 1000, y = gy / 1000 }
check(not Inside(gate, 1457) and Yards(gate, edge) <= 12, ('premise: zone point outside the Darnassus map, %.0f yd away'):format(Yards(gate, edge)))
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
local cached = { kind = 'npc', id = -11, svc = { vendor = true }, coords = '141:286,519;1657:549,240' }
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

-- 6. Thunder Bluff and Undercity have no usable terrain footprint: there a
-- zone-map copy of a city NPC sent you out of the gate to someone standing
-- beside you (1.5.1 review: Cairne Bloodhoof's Mulgore copy 8 yd from his
-- Thunder Bluff spot, Bethor Iceshard's Tirisfal copy 2 yd away). Find
-- must give a walk inside the city, with no "Leave".
faction = 'Horde'
local unitRace = UnitRace
for _, c in ipairs({ { 3057, 'Cairne Bloodhoof', 1456, 'Tauren' }, { 1498, 'Bethor Iceshard', 1458, 'Scourge' } }) do
    function UnitRace() return c[4], c[4] end
    local e = DB.units[c[1]]
    local pts, city, zone = e and DB.Points(e) or {}, nil, 0
    for _, p in ipairs(pts) do
        if p.m == c[3] then city = p elseif Inside(p, c[3]) then zone = zone + 1 end
    end
    check(city and zone == 0, c[2] .. ': one point inside the city, on its map')
    if city then
        WP.ClearAll(true)
        PlaceOnMap(c[3], city.x + 0.01, city.y) -- a few yards away, inside
        M.Tick(0.2)
        Find.Activate(e)
        local wp = WP.GetActive()
        check(wp and wp.m == c[3], c[2] .. ': Find sets the city-map point (got ' .. tostring(wp and wp.m) .. ')')
        if wp then
            M.Tick(3)
            local steer = Travel.Steer(wp)
            local plan = Travel.Current()
            local goal = plan and plan.path and plan.path[#plan.path].node
            local here = Travel._PlayerPlace()
            check(steer == nil, c[2] .. ': no detour (' .. tostring(steer and steer.title) .. ')')
            check(plan and #plan.path == 2 and goal and here and goal.area == here.area and goal.city == here.city,
                c[2] .. ': a walk inside the city (same area and city)')
            local leave = false
            for _, line in ipairs(Travel.Describe()) do if line:find('Leave', 1, true) then leave = true end end
            check(not leave, c[2] .. ': no "Leave" step')
        end
    end
end
UnitRace = unitRace
faction = 'Alliance'
WP.ClearAll(true)

print(('run_city_points: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
