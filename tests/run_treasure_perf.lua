-- Real database, warm scans and picks. Optional monotonic wall clock supplied
-- as a Lua 5.1 module via WT_PERF_CLOCK; os.clock is the portable CI fallback.
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
ns.DB.Load()
local baseline = os.getenv('WT_TREASURE_BASELINE')
if baseline then
    local f = assert(io.open(baseline)); local source = f:read('*a'); f:close()
    assert(loadstring(source .. '\nTreasure.PickKnown = KnownSpots\n'))('WaypointTracker', ns)
end
local T = ns.Treasure
ns.settings.treasureHunt, ns.settings.treasurePing = true, false
ns.settings.treasureFocus, ns.settings.realRoutes = false, false
local clock, clockName = os.clock, 'CPU clock (portable fallback)'
if os.getenv('WT_PERF_CLOCK') then
    clock = assert(package.loadlib(os.getenv('WT_PERF_CLOCK'), 'luaopen_treasure_clock'))()
    clockName = 'monotonic wall clock'
end
print('Treasure performance: ' .. (baseline and 'BEFORE' or 'AFTER') .. ', ' .. clockName)
-- Ceilings are tuned for an idle developer machine and get 2x headroom for
-- background load. Shared CI runners are slower and noisier, so there (CI
-- is set) the headroom is 5x; set
-- WT_PERF_SLACK to choose the factor yourself. The work counters and
-- allocation checks below are exact everywhere.
local slack = tonumber(os.getenv('WT_PERF_SLACK')) or (os.getenv('CI') and 5 or 2)
local function measure(name, fn, ceiling, count, prepare)
    ceiling = ceiling * slack
    -- Independent fixtures must not inherit garbage from a previous fixture's
    -- cold planner/database setup. GC stays enabled throughout every sample.
    collectgarbage('collect')
    fn() -- warm caches/rows
    local samples, worst = {}, 0
    for i = 1, count or 250 do
        if prepare then prepare() end
        local start = clock(); fn(); local ms = (clock() - start) * 1000
        samples[i], worst = ms, math.max(worst, ms)
    end
    table.sort(samples)
    print(('%s: median %.4f ms; worst %.4f ms'):format(name, samples[math.ceil(#samples / 2)], worst))
    if not baseline then assert(worst < ceiling, name .. ' exceeds ' .. ceiling .. ' ms') end
end
for _, n in ipairs({0, 5, 40}) do
    T.Clear(); ns.WP.ClearAll(true); M.units, M.vignettes = {}, {}
    for i = 1, n do
        local guid = 'Creature-0-1-0-0-999001-' .. i
        M.units['nameplate' .. i] = {guid = guid, name = 'Perf Rare', class = 'rare', reaction = 2, level = 30}
        M.vignettes['perf' .. i] = {objectGUID = guid, name = 'Perf Rare', onMinimap = true, atlasName = 'VignetteKill', pos = {0.5, 0.5}}
    end
    measure('Scan ' .. n .. ' units + ' .. n .. ' vignettes', T.Scan, 2)
    measure('First detections ' .. n, T.Scan, 4, 30, T.Clear)
    -- Preserve the original scan-only burst gate. The full triggered
    -- planning work is timed and proved separately below.
    if n == 40 then
        ns.settings.treasureFocus, ns.settings.realRoutes = true, true
        measure('First detections 40 (focus + Real routes on)', T.Scan, 4, 30, T.Clear)
        ns.settings.treasureFocus, ns.settings.realRoutes = false, false
    end
    -- Exclude mock-owned API allocations to detect addon-owned steady-state
    -- tables. The production APIs supply these objects, rather than Lua code.
    local api, bestMap = C_VignetteInfo, C_Map.GetBestMapForUnit
    local currentMap = bestMap("player")
    C_Map.GetBestMapForUnit = function() return currentMap end
    local guids, infos, positions = api.GetVignettes(), {}, {}
    for _, guid in ipairs(guids) do infos[guid] = api.GetVignetteInfo(guid); positions[guid] = api.GetVignettePosition(guid) end
    C_VignetteInfo = { GetVignettes = function() return guids end,
        GetVignetteInfo = function(guid) return infos[guid] end,
        GetVignettePosition = function(guid) return positions[guid] end }
    for i = 1, 10 do T.Scan() end
    collectgarbage('collect'); collectgarbage('stop')
    local before = collectgarbage('count')
    for i = 1, 1000 do T.Scan() end
    local growth = collectgarbage('count') - before
    collectgarbage('restart')
    print(('Unchanged %d: %.3f KiB allocated / 1000 scans (API objects reused)'):format(n, growth))
    if not baseline then assert(growth < 1, 'unchanged scan allocated tables') end
    C_VignetteInfo, C_Map.GetBestMapForUnit = api, bestMap
end
-- Full triggered planning frames, separate from scan-only timings. Pump the
-- actual deferred waypoint callbacks and sliced steering against shipped travel
-- data, using real map geometry for the Horde Hillsbrad/Alterac fixture.
local routeBest = C_Map.GetBestMapForUnit
for _, f in ipairs({
    {1416, 1500, 783.33331298828, 2799.99993896488, 1866.66665649414},
    {1424, 400, 1066.6666259766, 3199.9998779297, 2133.3332519531},
    {1420, 3837.4997558594, 3033.33325195313, 4518.7498779297, 3012.49981689456},
    {1458, 1877.9453125, 873.19262695313, 959.37503051758, 640.1041259766},
}) do
    M.maps[f[1]] = {mapID = f[1], name = 'Travel perf zone', cont = 0, top = f[2], left = f[3], w = f[4], h = f[5], mapType = 3, parentMapID = 13}
end
local R, WP = ns.Travel, ns.WP
C_Map.GetBestMapForUnit = function() return 1416 end
M.player.inst, M.player.wx, M.player.wy = ns.Geo.MapToWorld(1416, .4, .5)
ns.settings.treasureFocus, ns.settings.realRoutes = true, true
ns.settings.travelTrails, ns.settings.travelHearth = false, false
R._SetSliced(true)
local searches, moves = 0, 0
local refresh, move = ns.Terrain.Refresh, WP.Move
ns.Terrain.Refresh = function(...) searches = searches + 1; return refresh(...) end
WP.Move = function(...) moves = moves + 1; return move(...) end
for _, moving in ipairs({false, true}) do
    T.Clear(); WP.ClearAll(true); R._Reset(); M.units, M.vignettes = {}, {}
    M.vignettes.planning = {objectGUID = 'Creature-0-1-0-0-999201-1', name = 'Planning rare', onMinimap = true, atlasName = 'VignetteKill', pos = {.6, .5}}
    local firstSearch, firstMove = searches, moves
    local total, worst, times = 0, 0, {}
    T.Scan()
    for sec = 1, 12 do
        if moving then M.vignettes.planning.pos[1] = .6 + sec * .005 end
        local start = clock(); T.Scan(); local elapsed = (clock() - start) * 1000
        for frame = 1, 60 do
            local begin = clock()
            M.now = M.now + 1 / 60
            local timers = M.timers; M.timers = {}
            for _, timer in ipairs(timers) do
                if timer.at <= M.now then timer.fn() else M.timers[#M.timers + 1] = timer end
            end
            R.Steer(WP.GetActive())
            local ms = (clock() - begin) * 1000
            times[#times + 1], worst, elapsed = ms, math.max(worst, ms), elapsed + ms
        end
        total = total + elapsed
    end
    table.sort(times)
    print(('Real routes %s: searches %d; moves %d; median frame %.4f ms; worst frame %.4f ms; mean per second %.4f ms'):format(moving and 'moving' or 'stationary', searches - firstSearch, moves - firstMove, times[math.ceil(#times / 2)], worst, total / 12))
    assert(searches > firstSearch, 'Real routes benchmark must execute actual planning searches')
    assert((moving and moves > firstMove) or (not moving and moves == firstMove), 'moving/stationary fixture must exercise expected waypoint updates')
    assert(worst < 100 * slack and total / 12 < 150 * slack, 'full planning frame/second exceeds honest cold-inclusive budget')
end
ns.Terrain.Refresh, WP.Move = refresh, move
T.Clear(); WP.ClearAll(true); R._Reset()
ns.settings.treasureFocus, ns.settings.realRoutes = false, false
C_Map.GetBestMapForUnit = routeBest
T.Clear(); ns.WP.ClearAll(true); M.units, M.vignettes = {}, {}
local counts, map, most = {}, nil, 0
for _, e in pairs(ns.DB.objects) do
    if e.chest then
        for _, p in ipairs(ns.DB.Points(e)) do counts[p.m] = (counts[p.m] or 0) + 1 end
    end
end
for m, n in pairs(counts) do if n > most then map, most = m, n end end
-- Use the map with the most chest points even where wowmock lacks its art.
local oldMap, oldVector = C_Map.GetBestMapForUnit, ns.Geo.GetVector
C_Map.GetBestMapForUnit = function() return map end
-- Preserve the real Geo path, supplying a map geometry for this fixture.
M.maps[map] = M.maps[map] or {mapID = map, name = 'Perf zone', mapType = 3, parentMapID = 0, cont = 0, top = 0, left = 0, w = 4000, h = 4000}
M.player.wx, M.player.wy, M.player.inst = -2000, -2000, 0
ns.settings.treasureKnownSpots, ns.settings.treasureKnownRares = true, true
local start = clock()
if T.ZoneSpots then T.ZoneSpots(map) else T.PickKnown() end
print(('Index build / first pick: %.4f ms; busiest chest zone %d (%d points)'):format((clock() - start) * 1000, map, most))
measure('Known spot pick (warm index)', function() T.Clear(); T.PickKnown() end, 2)
if not baseline and ns.TabTreasure then
    T.Clear(); ns.WP.ClearAll(true)
    -- Exactly 50 recent records, 200 known zone points and 40 live rows.
    ns.charDB.treasureLog = {}
    for i = 1, 50 do ns.charDB.treasureLog[i] = {at = 1000, kind = 'rare', name = 'Recent ' .. i, id = 100000 + i} end
    T.LoadLog()
    local realDB = ns.DB
    ns.DB = {ready = true, generation = realDB.generation + 1000, objects = {}, units = {},
        Points = function(e) return e.points end, IsEnemy = function() return true end}
    for i = 1, 200 do
        ns.DB.objects[i] = {name = 'Zone chest ' .. i, chest = true, points = {{m = map, x = .1 + (i % 19) * .04, y = .1 + math.floor(i / 19) * .05}}}
    end
    for i = 1, 40 do
        local guid = 'GameObject-0-1-0-0-2843-tab' .. i
        M.vignettes[guid] = {objectGUID = guid, name = 'Tab chest ' .. i, onMinimap = true, atlasName = 'VignetteLoot', pos = {0.5, 0.5}}
    end
    T.Scan()
    -- Restore exactly fifty recent fixture rows after detection logging.
    for i = 1, 50 do ns.charDB.treasureLog[i] = {at = 1000, kind = 'rare', name = 'Recent ' .. i, id = 100000 + i} end
    T.LoadLog()
    ns.Window.Show('treasure')
    local ui = ns.TabTreasure.widgets
    assert(#T.Recent() == 50 and #ui.zone.items == 200 and #ui.nearby.items == 40, 'tab fixture must have 50 log, 200 zone, 40 nearby rows')
    print('Tab fixture: 50 recent + 200 zone + 40 nearby')
    measure('Tab refresh (50 recent + 200 zone + 40 nearby)', ns.TabTreasure.Refresh, 2)
    ns.DB = realDB
    ns.Window.Hide()
    measure('Hidden tab refresh', ns.TabTreasure.Refresh, 0.2)
else
    print('Tab refresh: not present before')
end
C_Map.GetBestMapForUnit, ns.Geo.GetVector = oldMap, oldVector
assert(#M.errors == 0, 'performance harness captured addon errors: ' .. tostring(M.errors[1]))
print('Treasure performance: PASS')
