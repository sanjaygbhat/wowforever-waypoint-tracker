-- Real routes planning while steering: the preferred search only, spread
-- over frames (a coroutine pumped once a frame by Travel.Steer), with the
-- same answers as planning all at once. Run from the repository root:
--     lua5.1 tests/run_travel_sliced.lua
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')

-- A counting frame clock: STEP milliseconds per node expansion (a heap pop,
-- counted below), so a time budget is a budget of node expansions however
-- often the clock is read (Search also reads it inside a long expansion,
-- and the arrow's trail search reads it too).
local STEP, pops = 0.05, 0
function debugprofilestop()
    return pops * STEP
end

local MAPS = {
    {1416, 0, 1500, 783.33331298828, 2799.99993896488, 1866.66665649414},
    {1424, 0, 400, 1066.6666259766, 3199.9998779297, 2133.3332519531},
    {1420, 0, 3837.4997558594, 3033.3332519531, 4518.7498779297, 3012.49981689456},
    {1458, 0, 1877.9453125, 873.19262695313, 959.37503051758, 640.1041259766},
    {1411, 1, 1808.3332519531, -1962.4998779297, 5287.4996337891, 3524.9998779297},
    {1454, 1, 2273.8771972656, -3680.6010742188, 1402.6044921874, 935.4166259765},
}
local shippedMaps = {}
for _, f in ipairs(MAPS) do
    shippedMaps[f[1]] = { mapID = f[1], name = tostring(f[1]), cont = f[2], top = f[3], left = f[4], w = f[5], h = f[6],
        mapType = 3, parentMapID = f[2] == 0 and 13 or 12 }
end
function UnitFactionGroup() return 'Horde' end
function UnitLevel() return 30 end
function GetUnitSpeed() return 7, 7 end
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN')
local T, G, WP, L = ns.Travel, ns.Geo, ns.WP, ns.L
local shipped = ns.TravelData
local mockBestMap = C_Map.GetBestMapForUnit

local passed, failed = 0, 0
local function check(v, why)
    if v then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. why) end
end

local function upvalue(fn, name)
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if not n then return nil end
        if n == name then return v, i end
    end
end

-- Node expansions: every turn of Search's main loop pops its heap once.
do
    local pop, i = upvalue(T.Search, 'Pop')
    assert(pop, 'Search pops its heap')
    debug.setupvalue(T.Search, i, function(h) pops = pops + 1; return pop(h) end)
end
-- Every search (also a retry over uncertain terrain) starts with
-- Terrain.Refresh, and records Travel.lastExpanded when it ends.
local starts, startedInCall = 0, false
do
    local refresh = ns.Terrain.Refresh
    ns.Terrain.Refresh = function(...)
        starts, startedInCall = starts + 1, true
        T.lastExpanded = nil
        return refresh(...)
    end
end
local planned = 0
ns.On('TRAVEL_PLANNED', function() planned = planned + 1 end)

-- One frame of steering, measured: node expansions, and whether a whole
-- search (start to end) happened inside it; `pumped`: the job it resumed.
local frame = { pops = 0, whole = false, starts = 0, pumped = nil }
-- the last re-anchor held the route (a surveyed-terrain leg ahead), and no
-- job has answered since (set by the counters below)
local holding = false
-- jobStarted[job]: when a job was first resumed; finishes: every job that
-- answered (Finish), with when it started and answered
local jobStarted, finishes = setmetatable({}, { __mode = 'k' }), {}
do
    local pump, i = upvalue(T.Steer, 'Pump')
    assert(pump, 'Steer resumes jobs through Pump')
    debug.setupvalue(T.Steer, i, function(...)
        local j = upvalue(T.Steer, 'job')
        frame.pumped = j
        if j and not jobStarted[j] then jobStarted[j] = M.now end
        return pump(...)
    end)
    local finish, k = upvalue(pump, 'Finish')
    assert(finish, 'Pump answers through Finish')
    debug.setupvalue(pump, k, function(j, ...)
        finishes[#finishes + 1] = { j = j, at = M.now, started = jobStarted[j] }
        holding = false
        return finish(j, ...)
    end)
end
local function Steer(wp, dt)
    M.now = M.now + (dt or 1 / 60)
    local p0, s0 = pops, starts
    startedInCall, T.lastExpanded, frame.pumped = false, nil, nil
    local s = T.Steer(wp)
    frame.pops, frame.starts = pops - p0, starts - s0
    frame.whole = startedInCall and T.lastExpanded ~= nil
    return s
end

-- the shipped network on the six real maps above
local function UseShipped()
    for id, m in pairs(shippedMaps) do M.maps[id] = m end
    C_Map.GetBestMapForUnit = function()
        if M.player.noPosition then return nil end
        local best, size
        for id, m in pairs(shippedMaps) do
            if m.cont == M.player.inst then
                local x, y = (m.left - M.player.wy) / m.w, (m.top - M.player.wx) / m.h
                if x >= 0 and x <= 1 and y >= 0 and y <= 1 and (not size or m.w * m.h < size) then
                    best, size = id, m.w * m.h
                end
            end
        end
        return best
    end
    ns.TravelData = shipped
    T._Reset()
    local d = T.Data()
    for id in pairs(d.byTaxi) do T.Know().flights[id] = true end
    return d
end
local function Stand(m, x, y)
    local cont, wx, wy = G.MapToWorld(m, x, y)
    M.player.inst, M.player.wx, M.player.wy = cont, wx, wy
end
local function Toward(cont, wx, wy, yards)
    if cont ~= M.player.inst then return end
    local dx, dy = wx - M.player.wx, wy - M.player.wy
    local dd = math.sqrt(dx * dx + dy * dy)
    if dd < 1e-6 then return end
    local k = math.min(1, yards / dd)
    M.player.wx, M.player.wy = M.player.wx + dx * k, M.player.wy + dy * k
end
-- walk where the route says (no rides: these are planning tests)
local function Walk(yards)
    local p = T.Current()
    local e = p and p.target
    if not e then return end
    local how = e.via
    if type(how) == 'table' and (how.kind or (how.method ~= 'walk' and how.method ~= 'gate' and how.method ~= 'lift')) then
        return
    end
    local tc, tx, ty = T.Pos(e.node)
    Toward(tc, tx, ty, yards)
end

-- ---------------------------------------------------------------------------
-- Auto-detection: a client clock means sliced planning
-- ---------------------------------------------------------------------------
local d = UseShipped()
ns.Set('realRoutes', true); ns.Set('travelHearth', false); ns.Set('travelTrails', false)
ns.Set('travelFlights', true); ns.Set('travelBoats', true); ns.Set('travelPreference', 'safer')
T._SetSliced(nil)
WP.ClearAll(true)
Stand(1424, .5552, .2685)
local wp = WP.Add(1454, .32, .378, { title = 'Thrall' })
local first = Steer(wp)
check(first == nil and T.Current() == nil, 'auto: the first frame of a new waypoint has no plan yet (plain arrow)')
check(not frame.whole and frame.pops <= 4 / STEP + 2, 'auto: the first frame searches within the first-plan budget')
local frames = 1
while not T.Current() and frames < 600 do Steer(wp); frames = frames + 1 end
check(T.Current() and frames > 2, 'auto: the plan arrives after a few frames (' .. frames .. ')')

-- ---------------------------------------------------------------------------
-- (a) Budget: no frame expands more nodes than its budget, and no frame
-- holds a whole search, walking with re-plans on the shipped network
-- ---------------------------------------------------------------------------
local scenarios = {
    { name = 'same-zone walk', from = { 1424, .62, .25 }, to = { 1424, .45, .40 }, flights = true },
    { name = 'cross-zone walk', from = { 1424, .615, .209 }, to = { 1416, .231, .604 }, flights = false },
    { name = 'cross-continent trip', from = { 1424, .5552, .2685 }, to = { 1454, .32, .378 }, flights = true },
}
for _, sc in ipairs(scenarios) do
    for _, sliced in ipairs({ true, false }) do
        -- false: no clock reading (deterministic expansions-per-frame budget)
        UseShipped()
        ns.Set('travelFlights', sc.flights); ns.Set('travelBoats', sc.flights)
        T._SetSliced(true)
        local clockFn = debugprofilestop
        if not sliced then debugprofilestop = function() return nil end end
        WP.ClearAll(true)
        Stand(sc.from[1], sc.from[2], sc.from[3])
        wp = WP.Add(sc.to[1], sc.to[2], sc.to[3], { title = sc.name })
        local label = sc.name .. (sliced and ' (clock)' or ' (expansion count)')
        local worst, whole, searches, plans, n = 0, 0, 0, 0, 0
        local over = false
        for f = 1, 60 * 25 do
            Steer(wp)
            -- an urgent job's slice is 4 ms (80 expansions), a background one's 1 ms (20)
            local urgent = frame.pumped and frame.pumped.urgent
            local limit = sliced and ((urgent and 4 or 1) / STEP + 2) or ((urgent and 80 or 20) + 2)
            worst = math.max(worst, frame.pops)
            if frame.pops > limit then over = true end
            if frame.whole then whole = whole + 1 end
            searches = searches + frame.starts
            if T.Current() then plans = plans + 1 end
            Walk(7 / 60)
            n = f
        end
        check(not over, label .. ': no frame over its expansion budget (worst ' .. worst .. ')')
        check(whole == 0, label .. ': no frame holds a whole search')
        check(searches >= 5 and plans > n / 2, label .. ': it re-plans while walking (' .. searches .. ' searches) and steers')
        check(#M.errors == 0, label .. ': no errors ' .. tostring(M.errors[1]))
        debugprofilestop = clockFn
    end
end

-- ---------------------------------------------------------------------------
-- (b) Equivalence on the shipped network: the sliced search, paused at every
-- checkpoint and pumped to the end, gives Travel.Routes' answer exactly
-- ---------------------------------------------------------------------------
local mapToWorld = G.MapToWorld
G.MapToWorld = function() return nil end -- the shipped positions, as tests/run_route_coverage.lua
d = UseShipped()
local function Fields(line)
    local out = {}; for v in (line .. '\t'):gmatch('(.-)\t') do out[#out + 1] = v end; return out
end
local function Position(id)
    local n = d.nodes[id]
    return n and { m = n.m, x = n.x, y = n.y, cont = n.cont0, wx = n.wx0, wy = n.wy0, area = n.area, city = n.city }
end
local function Same(a, b)
    if (a == nil) ~= (b == nil) then return false, 'one has no route' end
    if not a then return true end
    local function near(x, y) return x == y or (x and y and math.abs(x - y) <= 1e-9) end
    if not (near(a.total, b.total) and near(a.risk, b.risk) and near(a.terrainPenalty or 0, b.terrainPenalty or 0)) then
        return false, ('totals %s/%s risk %s/%s'):format(tostring(a.total), tostring(b.total), tostring(a.risk), tostring(b.risk))
    end
    if #a.path ~= #b.path then return false, 'lengths ' .. #a.path .. '/' .. #b.path end
    for i = 1, #a.path do
        local x, y = a.path[i], b.path[i]
        local function id(n) return n.id or (n.player and 'player') or (n.goal and 'goal') or ('@' .. tostring(n.wx) .. ',' .. tostring(n.wy)) end
        local function via(v) return type(v) == 'table' and tostring(v.method or v.kind) .. ':' .. tostring(v.key) or tostring(v) end
        if id(x.node) ~= id(y.node) or via(x.via) ~= via(y.via) or not near(x.at, y.at) or not near(x.risk, y.risk) then
            return false, 'stop ' .. i .. ' ' .. id(x.node) .. '/' .. id(y.node) .. ' ' .. via(x.via) .. '/' .. via(y.via)
        end
    end
    return true
end
-- pump a sliced search to the end, pausing at every checkpoint
local function Pumped(start, goal, c, preference, both)
    local out, resumes = nil, 0
    local co = coroutine.create(function()
        out = { T._Preferred(start, goal, c, preference, function() coroutine.yield() end, both) }
    end)
    repeat
        local ok, err = coroutine.resume(co); resumes = resumes + 1
        assert(ok, err)
    until coroutine.status(co) == 'dead'
    return out[1], out[2], out[3], resumes
end
local cases, mismatches, ghosts = 0, 0, 0
local f = assert(io.open('tests/fixtures/route-coverage-baseline.tsv')); f:read('*l')
local lineNo = 0
for line in f:lines() do
    lineNo = lineNo + 1
    if lineNo % 64 == 1 then
        local r = Fields(line)
        local faction, profile, a, b = r[1]:match('^(%w+)/([%w%-]+) ([^>]+)>(.+)$')
        local known = T.Know().flights; wipe(known)
        for _, n in pairs(d.nodes) do
            if n.taxi then
                if profile == 'all' or profile == 'fast-flights' or profile == 'ground-only' or profile == 'least-actual-time'
                    or profile == 'alternating' and n.taxi % 2 == 0 or profile == 'sparse' and n.taxi % 7 == 0 then known[n.taxi] = true
                elseif profile == 'explicit-false' then known[n.taxi] = false end
            end
        end
        local ghost = lineNo % 192 == 1
        local c = { faction = faction, class = 'WARRIOR', race = 'Human', level = 60, run = 7, ground = 14, flightFactor = 1,
            flights = profile ~= 'ground-only' and not ghost, boats = profile ~= 'ground-only' and not ghost, jumps = {},
            dead = ghost or nil, ghost = ghost or nil }
        if ghost then c.ground = 7; ghosts = ghosts + 1 end
        if Position(a) and Position(b) then
            for _, pref in ipairs({ 'fastest', 'safer' }) do
                cases = cases + 1
                local list, want = T.Routes(Position(a), Position(b), c, pref)
                local got, _, _, resumes = Pumped(Position(a), Position(b), c, pref, false)
                local ok, why = Same(got, want)
                if not ok or (want and resumes < 2) then
                    mismatches = mismatches + 1
                    print('  mismatch ' .. r[1] .. ' ' .. pref .. ': ' .. tostring(why) .. ' resumes=' .. resumes)
                end
                -- the trip's first job also brings both candidates for the offer
                local best, fast, safe = Pumped(Position(a), Position(b), c, pref, true)
                local ok2 = Same(best, want) and Same(fast, list[1])
                    and (pref == 'fastest' or Same(safe, list[2]))
                if not ok2 then
                    mismatches = mismatches + 1
                    print('  mismatch (both) ' .. r[1] .. ' ' .. pref)
                end
            end
        end
    end
end
f:close()
check(cases >= 60 and ghosts >= 3, 'equivalence matrix covers ' .. cases .. ' pair/policy cases (' .. ghosts .. ' ghost pairs)')
check(mismatches == 0, 'sliced search equals Travel.Routes exactly on every pair (' .. mismatches .. ' mismatches)')
G.MapToWorld = mapToWorld

-- ---------------------------------------------------------------------------
-- A small made-up network for counting searches (no terrain evidence, so a
-- search that finds a way never retries)
-- ---------------------------------------------------------------------------
local function UseSmall(links)
    C_Map.GetBestMapForUnit = function() return 37 end
    local function node(id, area, map, x)
        local cont, wx, wy = mapToWorld(map, x, .5)
        return table.concat({ id, 'pass', area, cont, wx, wy, map, x * 100, 50 }, '\t')
    end
    ns.TravelData = { areas = { 'start', 'risk', 'safe', 'goal' }, indoor = {},
        nodes = table.concat({ node('A', 1, 37, .1), node('R', 2, 52, .3), node('S', 3, 37, .3), node('G', 4, 37, .8) }, '\n'),
        links = links or 'A\tR\twalk\t50\t\t\t1\nR\tG\twalk\t50\t\t\t1\nA\tS\twalk\t72.5\t\t\t1\nS\tG\twalk\t72.5\t\t\t1',
        maps = '37\t1', regions = '37\t4\t80\t50\t2', levels = '52\t60\t63', towns = '', cities = '', factors = '' }
    T._Reset()
    return T.Data()
end
local function SmallPlace(x, area)
    local cont, wx, wy = mapToWorld(37, x, .5)
    return { m = 37, x = x, y = .5, area = area, cont = cont, wx = wx, wy = wy }
end
local function Has(path, id)
    for _, e in ipairs(path or {}) do if e.node.id == id then return true end end
end
local function Settle(w, limit)
    for _ = 1, limit or 600 do
        Steer(w)
        local j = upvalue(T.Steer, 'job')
        if not j then return end
    end
end

-- ---------------------------------------------------------------------------
-- (c) A re-plan is one search (the preferred one); two only when the safer
-- search finds nothing and the fastest is tried. Same answer as Travel.Routes.
-- ---------------------------------------------------------------------------
for _, sliced in ipairs({ false, true }) do
    for _, pref in ipairs({ 'fastest', 'safer' }) do
        UseSmall()
        ns.Set('travelFlights', false); ns.Set('travelBoats', false); ns.Set('travelPreference', pref)
        T._SetSliced(sliced)
        WP.ClearAll(true)
        local start = SmallPlace(.1, 1)
        M.player.inst, M.player.wx, M.player.wy = start.cont, start.wx, start.wy
        wp = WP.Add(37, .8, .5, { title = 'Single search' })
        Steer(wp); Settle(wp)
        local label = pref .. (sliced and ' sliced' or ' at once')
        local s0 = starts
        -- the periodic re-plan (sliced: the background refresh, SLICE_REFRESH)
        Steer(wp, sliced and 5.1 or 2.1)
        Settle(wp)
        check(starts - s0 == 1, label .. ': one re-plan is exactly one search (' .. (starts - s0) .. ')')
        local from = SmallPlace(.1, 1); from.player = true
        local to = SmallPlace(.8, 4); to.goal = true
        local _, want = T.Routes(from, to, T._Context(), pref)
        local ok, why = Same(T.Current(), want)
        check(ok and Has(T.Current().path, pref == 'fastest' and 'R' or 'S'), label .. ': the plan is Travel.Routes\' choice ' .. tostring(why))
        -- no way at all: the safer search, then the fastest (each retried
        -- over uncertain ground: two searches, four passes); sliced, the
        -- check again after a "no route" searches the fastest way first and
        -- stops there (two passes)
        UseSmall('A\tS\twalk\t72.5\t\t\t1')
        T._SetSliced(sliced)
        WP.ClearAll(true)
        wp = WP.Add(37, .8, .5, { title = 'No way' })
        Steer(wp); Settle(wp)
        s0 = starts
        Steer(wp, sliced and 5.1 or 2.1); Settle(wp)
        check(starts - s0 == ((pref == 'fastest' or sliced) and 2 or 4), label .. ': no route costs ' .. ((pref == 'fastest' or sliced) and 'one search' or 'the safer and the fastest search') .. ' (' .. (starts - s0) .. ' passes)')
    end
end

-- ---------------------------------------------------------------------------
-- (d) An unreachable waypoint (both ends placed): searches at the re-plan
-- pace, not every frame, and the no-route answer never flickers to nil
-- ---------------------------------------------------------------------------
for _, sliced in ipairs({ false, true }) do
    UseSmall('A\tS\twalk\t72.5\t\t\t1')
    ns.Set('travelFlights', false); ns.Set('travelBoats', false); ns.Set('travelPreference', 'safer')
    T._SetSliced(sliced)
    WP.ClearAll(true)
    local start = SmallPlace(.1, 1)
    M.player.inst, M.player.wx, M.player.wy = start.cont, start.wx, start.wy
    wp = WP.Add(37, .8, .5, { title = 'Unreachable' })
    local s0, answered, flicker, noPlan = starts, false, 0, 0
    for _ = 1, 600 do
        local s = Steer(wp)
        local isNoPlan = s and s.title == L.TRAVEL_NO_PLAN and s.pin
        if isNoPlan then answered, noPlan = true, noPlan + 1 elseif answered then flicker = flicker + 1 end
    end
    local label = sliced and 'sliced' or 'at once'
    -- 10 s: the first plan and one every 2 s; each is 4 passes (see above),
    -- plus the trip's offer once (at once: Travel.Choices, 2 passes)
    check(starts - s0 <= 6 * 4 + 2, label .. ': unreachable waypoint searches at the re-plan pace (' .. (starts - s0) .. ' passes in 600 frames)')
    check(answered and flicker == 0, label .. ': the no-route answer stays, no flicker (' .. noPlan .. ' frames)')
    check(T.Current() == nil, label .. ': no plan is held')
end

-- ---------------------------------------------------------------------------
-- (e) A waypoint or player the network can't place: no plan, the plain arrow
-- ---------------------------------------------------------------------------
C_Map.GetBestMapForUnit = mockBestMap
ns.TravelData = {
    areas = { 'ek.elwynn', 'ek.westfall', 'ek.tirisfal', 'kal.durotar' }, indoor = {},
    nodes = table.concat({
        'B_EW\tborder\t1\t0\t-2000\t-600\t37\t20\t100\t\t\t\t',
        'B_WE\tborder\t2\t0\t-2000\t-600\t52\t44\t0\t\t\t\t',
        'G_OUT\tentrance\t1\t0\t0\t-300\t37\t10\t0\t\t\t\t',
        'G_IN\tentrance\t1\t0\t100\t-300\t84\t75\t100\t84\t\t\t',
    }, '\n'),
    links = 'B_EW\tB_WE\twalk\t0\t\t\t\t\t\t\t\nG_IN\tG_OUT\tgate\t0\t\t\t\t\t\t\t',
    maps = '37\t1\n52\t2\n18\t3\n1\t4\n84\t1', regions = '', cities = '84\tAlliance', towns = '', teleports = '',
    factors = '', levels = '',
}
for _, sliced in ipairs({ false, true }) do
    T._Reset(); T.Data()
    ns.Set('realRoutes', true)
    T._SetSliced(sliced)
    local label = sliced and 'sliced' or 'at once'
    local function Run(w)
        local s
        for _ = 1, 5 do s = Steer(w, 0.7) end
        return s
    end
    WP.ClearAll(true)
    M.player.noPosition = nil
    M.player.inst, M.player.wx, M.player.wy = 0, -1000, -2400 -- Elwynn (37)
    local cont, wx, wy = G.MapToWorld(37, 0.3, 0.3)
    local cx, cy = G.WorldToMap(cont, wx, wy, 13)
    local onCont = WP.Add(13, cx, cy, { title = 'Continent pin' })
    check(Run(onCont) == nil and T.Current() == nil, label .. ': a waypoint on a continent map gets the plain arrow')
    WP.ClearAll(true)
    local c2, w2x, w2y = G.MapToWorld(1411, 0.5, 0.5)
    M.player.inst, M.player.wx, M.player.wy = 1, w2x + 50, w2y + 50
    local unmapped = WP.Add(1411, 0.5, 0.5, { title = 'Unmapped zone spot' })
    check(c2 == 1 and Run(unmapped) == nil and T.Current() == nil, label .. ': a map the network does not cover gets the plain arrow')
    WP.ClearAll(true)
    M.player.inst, M.player.wx, M.player.wy = 0, -1000, -2400
    local westfall = WP.Add(52, 0.9, 0.5, { title = 'Moonbrook' })
    local routed = Run(westfall)
    check(T.Current() ~= nil and (routed == nil or routed.title ~= L.TRAVEL_NO_PLAN), label .. ': (control) a placed waypoint is planned')
    M.player.noPosition = true
    check(Run(westfall) == nil and T.Current() == nil, label .. ': no player position gets the plain arrow and holds no plan')
    M.player.noPosition = nil
end

-- ---------------------------------------------------------------------------
-- (f) Cooldown/spell events never force a re-plan; a zone change still does
-- ---------------------------------------------------------------------------
for _, sliced in ipairs({ false, true }) do
    UseSmall()
    ns.Set('travelFlights', false); ns.Set('travelBoats', false); ns.Set('travelPreference', 'fastest')
    T._SetSliced(sliced)
    WP.ClearAll(true)
    local start = SmallPlace(.1, 1)
    M.player.inst, M.player.wx, M.player.wy = start.cont, start.wx, start.wy
    wp = WP.Add(37, .8, .5, { title = 'Soft events' })
    Steer(wp); Settle(wp)
    local s0 = starts
    for _ = 1, 300 do
        M.FireEvent('BAG_UPDATE_COOLDOWN'); M.FireEvent('SPELLS_CHANGED')
        Steer(wp)
    end
    local label = sliced and 'sliced' or 'at once'
    check(starts - s0 <= 3, label .. ': 5 s of BAG_UPDATE_COOLDOWN/SPELLS_CHANGED every frame re-plan at the 2 s pace (' .. (starts - s0) .. ')')
    Settle(wp)
    s0 = starts
    M.FireEvent('ZONE_CHANGED_NEW_AREA')
    Steer(wp); Settle(wp)
    check(starts - s0 == 1, label .. ': ZONE_CHANGED_NEW_AREA still re-plans at once')
end

-- ---------------------------------------------------------------------------
-- (g) The planning job's life: it starts again whenever what it plans for
-- changes, an error is reported once, and an answer from a few frames ago
-- steers from where the player is now
-- ---------------------------------------------------------------------------
local function Job() return (upvalue(T.Steer, 'job')) end
local function Begin(sc, prefer)
    d = UseShipped()
    ns.Set('travelFlights', sc.flights ~= false); ns.Set('travelBoats', sc.flights ~= false)
    ns.Set('travelPreference', prefer or 'safer')
    T._SetSliced(true)
    WP.ClearAll(true)
    Stand(sc.from[1], sc.from[2], sc.from[3])
    local w = WP.Add(sc.to[1], sc.to[2], sc.to[3], { title = 'Lifecycle' })
    Steer(w); Steer(w)
    return w
end
STEP = 1 -- 4 node expansions a frame for a first plan: jobs last many frames
local thrall = { from = { 1424, .5552, .2685 }, to = { 1454, .32, .378 } }
local ground = { from = { 1424, .615, .209 }, to = { 1416, .231, .604 }, flights = false }

-- waypoint changed mid-job
local w1 = Begin(thrall)
check(Job() and Job().wp == w1 and T.Current() == nil, 'lifecycle: a first job runs over several frames')
local w2 = WP.Add(1424, .45, .40, { title = 'Changed mind' })
local wrong = false
for _ = 1, 600 do
    Steer(w2)
    if T.Current() and T.Current().wp ~= w2 then wrong = true end
    if T.Current() and not Job() then break end
end
check(not wrong and T.Current() and T.Current().wp == w2, 'lifecycle: changing waypoint mid-job never adopts the old waypoint\'s route')

-- goal moved mid-job (same waypoint object)
w1 = Begin(thrall)
local oldJob = Job()
w1.x = .40
Steer(w1)
check(Job() == oldJob and upvalue(T.Steer, 'replanQueued'), 'lifecycle: moving the goal mid-job lets the (urgent) job finish and queues the search to the moved goal')
Settle(w1)
local last = T.Current() and T.Current().path[#T.Current().path].node
check(last and last.x == .40, 'lifecycle: the plan goes to the moved goal')

-- Travel.Invalidate() and a learned crossing mid-job
for _, change in ipairs({ 'invalidate', 'crossing' }) do
    w1 = Begin(thrall)
    oldJob = Job()
    local s0 = starts
    if change == 'invalidate' then T.Invalidate() else T.AddCrossing('SLICEDTEST', 9001, 9002, 1424, .5, .5) end
    Steer(w1)
    if change == 'invalidate' then
        check(Job() == oldJob and upvalue(T.Steer, 'replanQueued'), 'lifecycle: invalidate mid-job lets the (urgent) job finish and queues another search')
    else
        check(Job() ~= oldJob and starts > s0, 'lifecycle: ' .. change .. ' mid-job discards the job and searches again')
    end
    Settle(w1)
    check(T.Current() ~= nil, 'lifecycle: after ' .. change .. ' the plan still arrives')
end

-- an error inside Search mid-job
w1 = Begin(thrall)
local decide, broken, throws = ns.Terrain.Decide, true, 0
ns.Terrain.Decide = function(...)
    if broken then throws = throws + 1; error('sliced test failure') end
    return decide(...)
end
local errors0 = #M.errors
for _ = 1, 30 do Steer(w1); if #M.errors > errors0 then break end end
check(#M.errors == errors0 + 1 and tostring(M.errors[#M.errors]):find('sliced test failure', 1, true), 'lifecycle: an error in the job is reported once')
check(Job() == nil and T.Current() == nil, 'lifecycle: the failed job is gone (never resumed)')
local t0, s0 = throws, starts
for _ = 1, 100 do Steer(w1) end -- 1.67 s, standing still
check(throws == t0 and starts == s0, 'lifecycle: no retry before the normal re-plan pace')
broken = false
for _ = 1, 60 do Steer(w1) end
Settle(w1)
check(T.Current() ~= nil and #M.errors == errors0 + 1, 'lifecycle: the planner recovers at the next re-plan')
ns.Terrain.Decide = decide

-- walking during a job: the answer steers from where the player is now.
-- tests/run_travel_reroute.lua's network: an optional pass P on the way to
-- the flight master FM; at .315 the player is past P (more than 15 yd).
STEP = 4 -- one node expansion a frame
C_Map.GetBestMapForUnit = function() return 37 end
do
    local function at(x, y, area)
        local cont, wx, wy = mapToWorld(37, x, y)
        return { m = 37, x = x, y = y, cont = cont, wx = wx, wy = wy, area = area or 1, player = true }
    end
    local function row(id, kind, x, y, area, taxi)
        local q = at(x, y, area)
        return table.concat({ id, kind, area or 1, q.cont, q.wx, q.wy, 37, x * 100, y * 100, '', '', taxi or '', taxi and 'Horde' or '' }, '\t')
    end
    ns.TravelData = { areas = { 'approach', 'landing' }, indoor = {}, maps = '37\t1', regions = '37\t2\t80\t50\t2',
        nodes = table.concat({ row('P', 'pass', .3, .5), row('Q', 'pass', .3, .502), row('FM', 'taxi', .4, .5, 1, 1), row('LAND', 'taxi', .8, .5, 2, 2) }, '\n'),
        links = 'P\tFM\twalk\t47\t\t\t1\nQ\tFM\twalk\t47\t\t\t1\nFM\tLAND\ttaxi\t900\tHorde\t\t1', cities = '', towns = '', levels = '', factors = '' }
    T._Reset(); T.Data()
    T.Know().flights[1], T.Know().flights[2] = true, true
    ns.Set('travelFlights', true); ns.Set('travelPreference', 'fastest')
    T._SetSliced(true)
    WP.ClearAll(true)
    local from, past = at(.2, .5), at(.315, .5)
    M.player.inst, M.player.wx, M.player.wy = from.cont, from.wx, from.wy
    local w = WP.Add(37, .8, .5, { title = 'Walk during the job' })
    Steer(w)
    check(Job() ~= nil and T.Current() == nil, 'lifecycle: the first job is running')
    M.player.wx, M.player.wy = past.wx, past.wy
    local walked = math.sqrt((past.wx - from.wx) ^ 2 + (past.wy - from.wy) ^ 2)
    local s
    for _ = 1, 600 do
        s = Steer(w)
        if T.Current() then break end
    end
    local p = T.Current()
    local fm = p and p.target and p.target.node
    check(p and walked >= 20 and p.path[1].node.wx == from.wx, 'lifecycle: the plan was searched from where the player was (' .. math.floor(walked) .. ' yd ago)')
    local _, fx, fy = T.Pos(T.Data().nodes.FM)
    check(fm and fm.id == 'FM' and s and math.abs(s.dist - math.sqrt((fx - past.wx) ^ 2 + (fy - past.wy) ^ 2)) < 1e-6,
        'lifecycle: on the frame it arrives it steers from where the player is now, past P to FM')
    T._SetSliced(false); T.Invalidate(); Steer(w, 0)
    check(T.Current().target.node.id == 'FM', 'lifecycle: planning all at once from here aims at the same stop')
end
STEP = 0.05

-- ---------------------------------------------------------------------------
-- The trip's offer, sliced: its first job searches both ways (two searches,
-- none of them inside one frame), then offers
-- ---------------------------------------------------------------------------
UseSmall()
ns.Set('travelFlights', false); ns.Set('travelBoats', false); ns.Set('travelPreference', 'safer')
T._SetSliced(true)
WP.ClearAll(true)
do
    local start = SmallPlace(.1, 1)
    M.player.inst, M.player.wx, M.player.wy = start.cont, start.wx, start.wy
end
wp = WP.Add(37, .8, .5, { title = 'Offer trip' })
local s0, whole = starts, 0
for _ = 1, 30 do Steer(wp); if frame.whole then whole = whole + 1 end end
check(starts - s0 == 2 and whole == 0, 'offer: a trip starts with two sliced searches (' .. (starts - s0) .. ')')
check(T.offerButton and T.offerButton:IsShown() and Has(T.Current().path, 'S'), 'offer: the faster riskier way is offered; the safe route is followed')
s0 = starts
for _ = 1, 600 do Steer(wp) end
check(starts - s0 <= 6, 'offer: the offer is made once a trip (' .. (starts - s0) .. ' searches in 10 s)')

-- ---------------------------------------------------------------------------
-- Counters for the sections below: re-plans (Replan), re-anchors
-- (Remaining), planning contexts (Context) and background jobs (StartJob),
-- counted in every closure of Travel's that holds them
-- ---------------------------------------------------------------------------
local counts = { replan = 0, remaining = 0, context = 0, jobs = 0, anchored = 0, unanchored = 0, held = 0 }
do
    local replan = assert(upvalue(T.Steer, 'Replan'), 'Steer re-plans through Replan')
    local remaining = assert(upvalue(replan, 'Remaining'), 'Replan re-anchors through Remaining')
    local startJob = assert(upvalue(replan, 'StartJob'), 'Replan starts jobs through StartJob')
    local context = assert(T._Context, 'Travel._Context')
    local swap = {
        [replan] = function(...) counts.replan = counts.replan + 1; return replan(...) end,
        [remaining] = function(...)
            counts.remaining = counts.remaining + 1
            local r, why = remaining(...)
            if r then counts.anchored = counts.anchored + 1 else counts.unanchored = counts.unanchored + 1 end
            if why == 'terrain' then counts.held = counts.held + 1 end
            holding = why == 'terrain'
            return r, why
        end,
        [startJob] = function(...) counts.jobs = counts.jobs + 1; return startJob(...) end,
        [context] = function(...) counts.context = counts.context + 1; return context(...) end,
    }
    -- (an upvalue is shared by every closure of the file that names it, so
    -- one swap reaches them all; the counters themselves are never walked)
    local seen, wrapped = {}, 0
    for _, w in pairs(swap) do seen[w] = true end
    local function walk(fn)
        if seen[fn] then return end
        seen[fn] = true
        for i = 1, 255 do
            local n, v = debug.getupvalue(fn, i)
            if not n then break end
            if type(v) == 'function' then
                if swap[v] then
                    debug.setupvalue(fn, i, swap[v]); wrapped = wrapped + 1
                elseif not seen[v] then
                    walk(v)
                end
            end
        end
    end
    for _, v in pairs(T) do if type(v) == 'function' then walk(v) end end
    for original in pairs(swap) do walk(original) end -- StartJob is Replan's alone
    check(wrapped >= 4, 'counters installed (' .. wrapped .. ' upvalues)')
end
local function Snap() return counts.replan, counts.remaining, counts.context, counts.jobs end

-- ---------------------------------------------------------------------------
-- (j) Following a long route: a re-anchor and a planning context at most
-- once per re-plan (never every frame); and while the route holds where you
-- are (re-anchored), a background search at most every 5 s (SLICE_REFRESH)
-- ---------------------------------------------------------------------------
-- walk the route for 60 s at `speed`, counting per frame
local function Follow(w, speed)
    local r0, m0, c0, j0 = Snap()
    local a0, u0 = counts.anchored, counts.unanchored
    local st = { perFrame = 0, idleWork = 0, searchFrames = 0, yards = 0 }
    for _ = 1, 60 * 60 do
        local r1, m1, c1 = Snap()
        local x0, y0 = M.player.wx, M.player.wy
        Steer(w)
        local r, m, c = counts.replan - r1, counts.remaining - m1, counts.context - c1
        if r > 1 or m > r or c > r then st.perFrame = st.perFrame + 1 end
        if r == 0 and (m > 0 or c > 0) then st.idleWork = st.idleWork + 1 end
        if frame.pops > 0 then st.searchFrames = st.searchFrames + 1 end
        Walk(speed / 60)
        st.yards = st.yards + math.sqrt((M.player.wx - x0) ^ 2 + (M.player.wy - y0) ^ 2)
    end
    st.replans, st.jobs = counts.replan - r0, counts.jobs - j0
    st.remaining, st.contexts = counts.remaining - m0, counts.context - c0
    st.anchored, st.unanchored = counts.anchored - a0, counts.unanchored - u0
    return st
end
local function PerTrigger(st, label)
    check(st.perFrame == 0, label .. ': at most one re-plan a frame, and per re-plan at most one re-anchor and one context (' .. st.perFrame .. ' frames over)')
    check(st.idleWork == 0, label .. ': no re-anchor or context on a frame without a re-plan (' .. st.idleWork .. ' frames)')
    check(st.remaining == st.replans and st.contexts == st.replans, label .. ': every re-plan re-anchors once with one context')
    check(st.replans <= math.ceil(st.yards / 10) + 30 + st.jobs + 1,
        label .. ': re-plans only at the 10 yd / 2 s triggers (' .. st.replans .. ' in 60 s, ' .. math.floor(st.yards) .. ' yd)')
    print(('  %s: walked %d yd, %d re-plans, %d/%d re-anchored, %d jobs, %d frames with search work'):format(label,
        st.yards, st.replans, st.anchored, st.anchored + st.unanchored, st.jobs, st.searchFrames))
end
-- the shipped network: long multi-stop routes (their re-anchor often fails:
-- a route with a surveyed-terrain leg ahead is searched again, as before)
local walks = {
    { name = 'cross-zone walk', from = { 1424, .615, .209 }, to = { 1416, .231, .604 }, flights = false },
    { name = 'cross-continent trip', from = { 1424, .5552, .2685 }, to = { 1454, .32, .378 }, flights = true },
}
for _, sc in ipairs(walks) do
    for _, speed in ipairs({ 7, 14 }) do
        UseShipped()
        ns.Set('travelFlights', sc.flights); ns.Set('travelBoats', sc.flights); ns.Set('travelPreference', 'safer')
        T._SetSliced(true)
        WP.ClearAll(true)
        Stand(sc.from[1], sc.from[2], sc.from[3])
        wp = WP.Add(sc.to[1], sc.to[2], sc.to[3], { title = sc.name })
        local n = 0
        while not T.Current() and n < 600 do Steer(wp); n = n + 1 end
        Settle(wp)
        local label = ('%s at %d yd/s'):format(sc.name, speed)
        local st = Follow(wp, speed)
        PerTrigger(st, label)
        check(st.yards >= speed * 60 * 0.5 and T.Current() and T.Current().wp == wp, label .. ': still following the route')
        check(#M.errors == 1, label .. ': no errors ' .. tostring(M.errors[2]))
    end
end
-- a long walk whose route always re-anchors (no surveyed-terrain leg): to a
-- flight master 1350 yd away, then a flight
local function LongWalk()
    C_Map.GetBestMapForUnit = function() return 37 end
    local function at(x, y, area)
        local cont, wx, wy = mapToWorld(37, x, y)
        return { m = 37, x = x, y = y, cont = cont, wx = wx, wy = wy, area = area or 1, player = true }
    end
    local function row(id, kind, x, y, area, taxi)
        local q = at(x, y, area)
        return table.concat({ id, kind, area or 1, q.cont, q.wx, q.wy, 37, x * 100, y * 100, '', '', taxi or '', taxi and 'Horde' or '' }, '\t')
    end
    ns.TravelData = { areas = { 'approach', 'landing' }, indoor = {}, maps = '37\t1', regions = '37\t2\t95\t50\t3',
        nodes = table.concat({ row('P', 'pass', .3, .5), row('FM', 'taxi', .65, .5, 1, 1), row('LAND', 'taxi', .95, .5, 2, 2) }, '\n'),
        links = 'P\tFM\twalk\t0\t\t\t1\nFM\tLAND\ttaxi\t60\tHorde\t\t1', cities = '', towns = '', levels = '', factors = '' }
    T._Reset(); T.Data()
    T.Know().flights[1], T.Know().flights[2] = true, true
    ns.Set('travelFlights', true)
    return at
end
for _, speed in ipairs({ 7, 14 }) do
    for _, preference in ipairs({ 'fastest', 'safer' }) do
        local at = LongWalk()
        ns.Set('travelPreference', preference)
        T._SetSliced(true)
        WP.ClearAll(true)
        do local p = at(.2, .5); M.player.inst, M.player.wx, M.player.wy = p.cont, p.wx, p.wy end
        wp = WP.Add(37, .96, .5, { title = 'Long walk' })
        local n = 0
        while not T.Current() and n < 600 do Steer(wp); n = n + 1 end
        Settle(wp)
        local label = ('long walk at %d yd/s (%s)'):format(speed, preference)
        local st = Follow(wp, speed)
        PerTrigger(st, label)
        check(st.yards >= speed * 60 * 0.9 and st.anchored >= st.yards / 10 - 2 and st.unanchored == 0,
            label .. ': the route held and was re-anchored at every re-plan (' .. st.anchored .. '/' .. (st.anchored + st.unanchored) .. ')')
        check(st.jobs <= 13, label .. ': at most a background search every 5 s while the route holds (' .. st.jobs .. ' in 60 s)')
        check(st.searchFrames <= 60 * 60 / 4, label .. ': background search runs in a minority of frames (' .. st.searchFrames .. ' of 3600)')
        check(T.Current() and T.Current().target.node.id == 'FM', label .. ': the arrow still leads to the flight master')
        check(#M.errors == 1, label .. ': no errors ' .. tostring(M.errors[2]))
    end
end

-- ---------------------------------------------------------------------------
-- (k) What can't wait still searches within half a second, sliced: leaving
-- the route, Travel.Invalidate(), a moved goal, a new area. tests/
-- run_travel_reroute.lua's network, with a third area on the approach.
-- ---------------------------------------------------------------------------
local function RerouteNetwork(extraRegion)
    C_Map.GetBestMapForUnit = function() return 37 end
    local function at(x, y, area)
        local cont, wx, wy = mapToWorld(37, x, y)
        return { m = 37, x = x, y = y, cont = cont, wx = wx, wy = wy, area = area or 1, player = true }
    end
    local function row(id, kind, x, y, area, taxi)
        local q = at(x, y, area)
        return table.concat({ id, kind, area or 1, q.cont, q.wx, q.wy, 37, x * 100, y * 100, '', '', taxi or '', taxi and 'Horde' or '' }, '\t')
    end
    ns.TravelData = { areas = { 'approach', 'landing', 'side' }, indoor = {}, maps = '37\t1',
        regions = '37\t2\t80\t50\t2' .. (extraRegion or ''),
        nodes = table.concat({ row('P', 'pass', .3, .5), row('Q', 'pass', .3, .502), row('FM', 'taxi', .4, .5, 1, 1), row('LAND', 'taxi', .8, .5, 2, 2) }, '\n'),
        links = 'P\tFM\twalk\t47\t\t\t1\nQ\tFM\twalk\t47\t\t\t1\nFM\tLAND\ttaxi\t900\tHorde\t\t1', cities = '', towns = '', levels = '', factors = '' }
    T._Reset(); T.Data()
    T.Know().flights[1], T.Know().flights[2] = true, true
    ns.Set('travelFlights', true)
    return at
end
local function Go(p) M.player.inst, M.player.wx, M.player.wy = p.cont, p.wx, p.wy end
-- frames (at 60 fps, up to `limit`) until a background job starts
local function UntilJob(w, limit)
    local j0 = counts.jobs
    for f = 1, limit or 60 do
        Steer(w)
        if counts.jobs > j0 then return f end
    end
end
do
    local at = RerouteNetwork('\n37\t3\t22\t50\t.5') -- 'side': 15 yd around (.22, .5), on the approach
    ns.Set('travelPreference', 'fastest')
    T._SetSliced(true)
    WP.ClearAll(true)
    Go(at(.2, .5))
    local w = WP.Add(37, .8, .5, { title = 'Urgent re-plans' })
    Steer(w); Settle(w)
    check(T.Current() and T.Current().target.node.id == 'P', 'urgent: the first plan aims at the approach P')
    -- control: walking 15 yd along the route re-anchors there, and waits
    Go(at(.205, .5))
    local r0, _, _, j0 = Snap()
    for _ = 1, 36 do Steer(w) end
    check(counts.replan > r0 and counts.jobs == j0 and T.Current().path[1].node.wx == M.player.wx,
        'urgent (control): moving along the route re-anchors at once and searches later')
    -- leaving the route (60 yd off it)
    Go(at(.21, .47))
    local f = UntilJob(w, 30)
    check(f ~= nil, 'urgent: leaving the route searches within 0.5 s (' .. tostring(f) .. ' frames)')
    Settle(w)
    -- Travel.Invalidate()
    T.Invalidate()
    f = UntilJob(w, 30)
    check(f == 1, 'urgent: Travel.Invalidate() searches on the next frame (' .. tostring(f) .. ')')
    Settle(w)
    -- the goal moved (same waypoint object)
    w.x = .79
    f = UntilJob(w, 30)
    check(f ~= nil, 'urgent: a moved goal searches within 0.5 s (' .. tostring(f) .. ' frames)')
    Settle(w)
    local last = T.Current() and T.Current().path[#T.Current().path].node
    check(last and last.x == .79, 'urgent: the plan goes to the moved goal')
    -- a new area
    Go(at(.22, .5))
    f = UntilJob(w, 30)
    check(f ~= nil, 'urgent: a new area searches within 0.5 s (' .. tostring(f) .. ' frames)')
    Settle(w)
    -- after SLICE_REFRESH, moving along searches again
    Go(at(.2, .5)); Steer(w, 0.6); Settle(w)
    Go(at(.205, .5))
    f = UntilJob(w, 60 * 6)
    check(f ~= nil and f > 60 * 3, 'urgent (control): on the route the next search waits for the 5 s refresh (' .. tostring(f) .. ' frames)')
    check(#M.errors == 1, 'urgent: no errors ' .. tostring(M.errors[2]))
end

-- ---------------------------------------------------------------------------
-- (l) Between background searches the re-anchored route steers exactly as
-- planning all at once does (tests/run_travel_reroute.lua, sliced)
-- ---------------------------------------------------------------------------
for _, preference in ipairs({ 'fastest', 'safer' }) do
    local at = RerouteNetwork()
    ns.Set('travelPreference', preference)
    T._SetSliced(true)
    local function choose()
        WP.ClearAll(true)
        Go(at(.2, .5))
        local w = WP.Add(37, .8, .5, { title = 'Reroute destination' })
        Steer(w); Settle(w)
        return w
    end
    local label = preference .. ' sliced'
    local w = choose()
    check(T.Current() and T.Current().target.node.id == 'P', label .. ' begins with optional approach')
    local j0 = counts.jobs
    Go(at(.3005, .51)); Steer(w, 2.1)
    check(counts.jobs == j0, label .. ': (the refresh waits; the re-anchor steers)')
    check(T.Current().target.node.id == 'FM', label .. ' lateral parallel movement bypasses P outside 15 yards')
    check(T.Current().path[1].node.wx == M.player.wx, label .. ' route is anchored at current position')
    w = choose()
    j0 = counts.jobs
    Go(at(.315, .5)); Steer(w, 2.1)
    check(counts.jobs == j0 and T.Current().target.node.id == 'FM', label .. ' passed P is skipped outside arrival radius')
end
check(#M.errors == 1, 'reroute sliced: no errors ' .. tostring(M.errors[2]))

-- ---------------------------------------------------------------------------
-- (h) Travel.Refresh plans again at once, and leaves no global behind
-- ---------------------------------------------------------------------------
T._SetSliced(false)
WP.ClearAll(true)
wp = WP.Add(37, .8, .5, { title = 'Refresh' })
Steer(wp)
local before = planned
M.now = M.now + 0.1
T.Refresh()
check(planned == before + 1, 'Travel.Refresh re-plans at once')
check(rawget(_G, 'lastPlanTime') == nil, 'Travel.Refresh writes no global')

-- ---------------------------------------------------------------------------
-- (i) The player's place is one table while they stand still
-- ---------------------------------------------------------------------------
local a1, a2 = T._PlayerPlace(), T._PlayerPlace()
M.player.wx = M.player.wx + 3
local a3 = T._PlayerPlace()
check(a1 and a1 == a2, 'an unmoved player is the same place table (no allocation)')
check(a3 and a3 ~= a1 and a3.wx ~= a1.wx, 'a moved player is a new place')


-- ===========================================================================
-- When jobs run (sliced): urgent and background jobs, progress while what a
-- job plans for keeps changing, terrain holds, one slice a frame, idle jobs
-- ===========================================================================
local function Queued() return upvalue(T.Steer, 'replanQueued') == true end
local function Urgent(j) return j ~= nil and j.urgent == true end
local function Here(j) return j and j.here and math.abs(j.here.wx - M.player.wx) < 1e-6 and math.abs(j.here.wy - M.player.wy) < 1e-6 end
-- the longest time a job took (first slice to answer) among finishes[from..]
local function Longest(from)
    local t = 0
    for k = from, #finishes do
        local f = finishes[k]
        if f.started then t = math.max(t, f.at - f.started) end
    end
    return t
end

-- ---------------------------------------------------------------------------
-- (m) A goal that keeps moving (Treasure.lua moves a wandering rare's
-- waypoint about once a second) never starves the planner: a job runs to
-- its answer, the search for where the goal is now follows it at once, and
-- the plan's goal is never older than 2T + 1 s (T: the longest job)
-- ---------------------------------------------------------------------------
STEP = 1 -- 4 node expansions a frame for an urgent job: jobs last seconds
do
    local w = Begin(thrall)
    local n = 0
    while not (T.Current() and not Job()) and n < 6000 do Steer(w); n = n + 1 end
    check(T.Current() ~= nil, 'moving goal: (control) the first plan')
    local f0 = #finishes
    local history = { { x = w.x, at = M.now } } -- each goal position, and when it was set
    local worst, sampled, adopted = 0, 0, 0
    local lastPlan = T.Current()
    for _ = 1, 60 do
        WP.Move(w, w.m, w.x + 0.0012, w.y)
        history[#history + 1] = { x = w.x, at = M.now }
        for _ = 1, 60 do
            Steer(w)
            local p = T.Current()
            if p ~= lastPlan and p and p.path[1].node.player and finishes[#finishes] and p.path == finishes[#finishes].j.best.path then
                adopted = adopted + 1
            end
            lastPlan = p
        end
        -- how long ago the position the plan leads to stopped being the goal's
        local p = T.Current()
        local endX = p and p.path[#p.path].node.x
        local age = math.huge
        for k = #history, 1, -1 do
            if history[k].x == endX then age = (k == #history) and 0 or (M.now - history[k + 1].at); break end
        end
        worst, sampled = math.max(worst, age), sampled + 1
    end
    local done, longest = #finishes - f0, Longest(f0 + 1)
    print(('  moving goal: %d jobs answered in 60 s (longest %.2f s), %d adopted, plan goal at most %.2f s old'):format(done, longest, adopted, worst))
    check(longest > 1, 'moving goal: (control) a job outlasts a goal move (' .. longest .. ' s)')
    check(done >= 10 and adopted >= 10, 'moving goal: jobs keep answering and their routes are taken (' .. done .. ' answered, ' .. adopted .. ' taken)')
    check(worst <= 2 * longest + 1, ('moving goal: the plan\'s goal is never older than 2T + 1 s (%.2f s, T = %.2f s)'):format(worst, longest))
    -- once the goal stops, the plan is for the goal within two job lengths
    local stopped = M.now
    local at
    for _ = 1, 60 * 30 do
        Steer(w)
        local p = T.Current()
        if p and p.path[#p.path].node.x == w.x then at = M.now; break end
    end
    check(at and at - stopped <= 2 * longest + 1 / 30, ('moving goal: after it stops the plan reaches it within two job lengths (%s s)'):format(tostring(at and at - stopped)))
end

-- ---------------------------------------------------------------------------
-- (n) The generation changing faster than a job lasts (zone-border
-- flapping, Terrain.Save bursts): jobs still answer and the plan is renewed
-- ---------------------------------------------------------------------------
do
    local w = Begin(thrall)
    local n = 0
    while not (T.Current() and not Job()) and n < 6000 do Steer(w); n = n + 1 end
    local f0, renewed, before = #finishes, 0, T.Current()
    for f = 1, 60 * 30 do
        if f % 18 == 0 then T.Invalidate() end -- every 0.3 s
        Steer(w)
        local p, last = T.Current(), finishes[#finishes]
        if p ~= before and last and p and p.path == last.j.best.path then renewed = renewed + 1 end
        before = p
    end
    local done = #finishes - f0
    print(('  generation every 0.3 s: %d jobs answered in 30 s (longest %.2f s), plan renewed %d times'):format(done, Longest(f0 + 1), renewed))
    check(Longest(f0 + 1) > 0.3, 'generation flapping: (control) a job outlasts a generation change')
    check(done >= 5 and renewed >= 5, 'generation flapping: jobs still answer and renew the plan (' .. done .. ' answered, ' .. renewed .. ' renewed)')
end

-- ---------------------------------------------------------------------------
-- (o) An urgent re-plan never waits behind a background job: leaving the
-- route one frame after a background job started searches from the new
-- position at once, at the urgent budget; leaving it again while that
-- urgent job runs queues a search after it (no restart)
-- ---------------------------------------------------------------------------
do
    local w = Begin(thrall)
    local n = 0
    while not (T.Current() and not Job()) and n < 6000 do Steer(w); n = n + 1 end
    Steer(w, 6) -- the periodic re-plan, 5 s after the last job: a background search
    local j0 = Job()
    check(j0 ~= nil and j0.urgent == false, 'urgent: (control) a background job is running')
    M.player.wx, M.player.wy = M.player.wx + 80, M.player.wy + 80
    Steer(w)
    local j1 = Job()
    check(j1 ~= nil and j1 ~= j0 and Urgent(j1) and Here(j1),
        'urgent: leaving the route during a background job starts a search from the new position in the same frame')
    Steer(w)
    check(frame.pumped == j1 and frame.pops > 1 / STEP + 2 and frame.pops <= 4 / STEP + 2,
        'urgent: its slices get the urgent budget (' .. frame.pops .. ' expansions)')
    M.player.wx, M.player.wy = M.player.wx - 160, M.player.wy
    for _ = 1, 40 do Steer(w) end
    check(Job() == j1 and Queued(), 'urgent: leaving the route again while the urgent job runs queues a search after it')
    Settle(w, 6000)
    check(T.Current() and Here({ here = T.Current().path[1].node }), 'urgent: the queued search, from the latest position, answers')
end
STEP = 0.05

-- ---------------------------------------------------------------------------
-- (p) An unreachable waypoint (no boats or flights to the other continent):
-- the check again searches the fastest way first and stops there, as
-- Travel.Routes does; checks come 5 s after the last one ended
-- ---------------------------------------------------------------------------
local function NoWay()
    UseShipped()
    ns.Set('travelFlights', false); ns.Set('travelBoats', false); ns.Set('travelPreference', 'safer')
    T._SetSliced(true)
    WP.ClearAll(true)
    Stand(1424, .5552, .2685)
    local w = WP.Add(1454, .32, .378, { title = 'No way without boats' })
    local s
    for _ = 1, 6000 do
        s = Steer(w)
        if s and s.title == L.TRAVEL_NO_PLAN and not Job() then break end
    end
    return w, s
end
do
    local w, s = NoWay()
    check(s and s.pin and T.Current() == nil, 'no way: (control) both ends placed, no route')
    local j0 = counts.jobs
    for _ = 1, 60 * 6 do Steer(w); if counts.jobs > j0 then break end end
    local p0 = pops
    Settle(w, 6000)
    local recheck = pops - p0
    local here = T._PlayerPlace()
    local start = { area = here.area, city = here.city, cont = here.cont, wx = here.wx, wy = here.wy, m = here.m, x = here.x, y = here.y, player = true }
    local cont, wx, wy = G.MapToWorld(w.m, w.x, w.y)
    local area, city = T.AreaAt(w.m, w.x, w.y)
    local goal = { area = area, city = city, cont = cont, wx = wx, wy = wy, m = w.m, x = w.x, y = w.y, goal = true }
    p0 = pops
    local _, want = T.Routes(start, goal, T._Context(), 'safer')
    local routes = pops - p0
    print(('  no way: a check again expands %d nodes, Travel.Routes %d'):format(recheck, routes))
    check(counts.jobs == j0 + 1 and want == nil and T.Current() == nil, 'no way: (control) one check, still no route')
    check(recheck > 0 and recheck <= routes * 1.2, 'no way: a check again costs what Travel.Routes does (' .. recheck .. ' / ' .. routes .. ' expansions)')
    -- standing still for 120 s
    local framesWith, n, gap, jobsSeen = 0, 0, math.huge, 0
    local current, lastSlice
    for _ = 1, 60 * 120 do
        Steer(w)
        n = n + 1
        if frame.pumped then
            framesWith = framesWith + 1
            if frame.pumped ~= current then
                if lastSlice then gap = math.min(gap, M.now - lastSlice) end
                current, jobsSeen = frame.pumped, jobsSeen + 1
            end
            lastSlice = M.now
        end
    end
    print(('  no way, standing 120 s: %d jobs, a slice in %d of %d frames (%.1f%%), shortest gap between jobs %.2f s'):format(jobsSeen, framesWith, n, 100 * framesWith / n, gap))
    -- (the tree before this change: a slice in 31.3% of frames, gaps from 4.1 s)
    check(framesWith / n < 0.156, ('no way: standing still, a slice in under half the frames it took before (%.1f%%)'):format(100 * framesWith / n))
    check(jobsSeen >= 5 and gap >= 5 - 1e-6, ('no way: at least 5 s without planning between checks (%.2f s)'):format(gap))
end

-- ---------------------------------------------------------------------------
-- (q) A setting that makes the route possible (boats and flights on) while
-- the answer is "no route": an urgent job (4 ms), the no-route pin until it
-- answers, and the route found by that one job; also when it comes during
-- a background check
-- ---------------------------------------------------------------------------
for _, during in ipairs({ false, true }) do
    local w = NoWay()
    local label = during and 'during a background check' or 'between checks'
    if during then
        for _ = 1, 60 * 7 do Steer(w); if Job() then break end end
        check(Job() ~= nil and Job().urgent == false, 'setting: (control) a background check is running')
    end
    local j0 = counts.jobs
    ns.Set('travelBoats', true); ns.Set('travelFlights', true)
    local pin, slow, fast, frames = 0, 0, 0, 0
    local first
    for _ = 1, 6000 do
        local s = Steer(w)
        frames = frames + 1
        if frame.pumped then
            first = first or frame.pumped
            if not Urgent(frame.pumped) then slow = slow + 1 end
            if frame.pops > 1 / STEP + 2 then fast = fast + 1 end
        end
        if T.Current() then break end
        if s and s.title == L.TRAVEL_NO_PLAN and s.pin then pin = pin + 1 end
    end
    check(T.Current() ~= nil and counts.jobs - j0 == 1, 'setting ' .. label .. ': the route is found by one job (' .. (counts.jobs - j0) .. ')')
    check(slow == 0 and fast > 0, 'setting ' .. label .. ': it is urgent: every slice at 4 ms (' .. slow .. ' background slices)')
    check(pin == frames - 1, 'setting ' .. label .. ': the no-route pin stays until it answers (' .. pin .. '/' .. (frames - 1) .. ')')
end

-- ---------------------------------------------------------------------------
-- (r) A route with a surveyed-terrain leg ahead can't be re-anchored
-- (Reprice rebuilds that evidence only by searching). Standing still (and
-- for every route), a search at most every 5 s after the last one ended;
-- moving, a background search at every re-plan as before (planning all at
-- once searches then too); what can't wait still searches within 0.5 s
-- ---------------------------------------------------------------------------
local crossZone = { from = { 1424, .615, .209 }, to = { 1416, .231, .604 } }
local function Held(sliced)
    UseShipped()
    ns.Set('travelFlights', false); ns.Set('travelBoats', false); ns.Set('travelPreference', 'safer')
    T._SetSliced(sliced)
    WP.ClearAll(true)
    Stand(crossZone.from[1], crossZone.from[2], crossZone.from[3])
    return WP.Add(crossZone.to[1], crossZone.to[2], crossZone.to[3], { title = 'Over the hills' })
end
do
    local w = Held(true)
    Steer(w); Settle(w, 6000)
    -- walk on until a surveyed-terrain leg is ahead, then stand there for 60 s
    local function TerrainAhead()
        local p = T.Current()
        for i = p and p.index or math.huge, p and #p.path or 0 do
            if type(p.path[i].via) == 'table' and p.path[i].via.terrain then return true end
        end
        return false
    end
    for _ = 1, 60 * 30 do
        Steer(w)
        if TerrainAhead() then break end
        Walk(7 / 60)
    end
    check(TerrainAhead(), 'held: (control) walking on, a surveyed-terrain leg is ahead')
    local j0, h0 = counts.jobs, counts.held
    for _ = 1, 3600 do Steer(w) end
    local standing = counts.jobs - j0
    check(counts.held - h0 > 10, 'held: (control) standing, the route could not be re-anchored (' .. (counts.held - h0) .. ' times)')
    -- what can't wait, standing on it: each an urgent job within 0.5 s
    local function Urgently(label, change)
        Settle(w, 6000)
        for _ = 1, 600 do Steer(w); if holding and not Job() then break end end
        check(holding and not Job(), 'held: (control) not re-anchored before ' .. label)
        change()
        local f = UntilJob(w, 30)
        check(f ~= nil and Urgent(Job()), 'held: ' .. label .. ' searches at once (' .. tostring(f) .. ' frames)')
        Settle(w, 6000)
    end
    local back = { M.player.inst, M.player.wx, M.player.wy }
    Urgently('leaving the route', function() M.player.wx = M.player.wx + 60 end)
    M.player.inst, M.player.wx, M.player.wy = back[1], back[2], back[3]
    Urgently('Travel.Invalidate()', function() T.Invalidate() end)
    Urgently('a moved goal', function() w.x = w.x + 0.002 end)
    -- moving along the route for 60 s, over the border into another area
    w = Held(true)
    Steer(w); Settle(w, 6000)
    j0, h0 = counts.jobs, counts.held
    local area0, f, urgentJob, background = T._PlayerPlace().area, nil, nil, 0
    local seen = {}
    local function Count()
        local j = Job()
        if j and not seen[j] then seen[j] = true; if j.urgent == false then background = background + 1 end end
    end
    for _ = 1, 3600 do
        Steer(w); Count(); Walk(7 / 60)
        if not f and T._PlayerPlace().area ~= area0 then
            -- a new area: an urgent search within 0.5 s
            local k0 = counts.jobs
            for k = 1, 30 do
                Steer(w); Count(); Walk(7 / 60)
                if counts.jobs > k0 then f, urgentJob = k, Job(); break end
            end
            f = f or false
        end
    end
    local moving = counts.jobs - j0
    check(counts.held - h0 > 10, 'held: (control) moving, the route could not be re-anchored (' .. (counts.held - h0) .. ' times)')
    check(f and Urgent(urgentJob), 'held: a new area searches at once (' .. tostring(f) .. ' frames)')
    print(('  held route: %d jobs in 60 s moving (%d background), %d standing'):format(moving, background, moving > 0 and standing or 0))
    -- the tree before this change: 24 jobs over this walk (at 1 ms a frame)
    check(math.abs(moving - 24) <= 1 and background >= moving - 3, 'held: moving along it, a background search at each re-plan, as before (' .. moving .. ' jobs, ' .. background .. ' background)')
    check(standing <= 13, 'held: standing still, at most a search every 5 s (' .. standing .. ' in 60 s; 30 before)')
end
-- standing still on the long trip (every route: re-anchored or not)
do
    local w = Begin(thrall)
    Settle(w, 6000)
    local j0 = counts.jobs
    for _ = 1, 3600 do Steer(w) end
    local standing = counts.jobs - j0
    print(('  long trip, standing 60 s: %d jobs'):format(standing))
    check(standing <= 13, 'standing: on the long trip, at most a search every 5 s (' .. standing .. ' in 60 s)')
end

-- ---------------------------------------------------------------------------
-- The arrow against planning all at once (the released behaviour), at the
-- same places: a trip walked as planning all at once leads, then replayed
-- sliced. The two may differ only within one background job's length (plus
-- one frame) after a route change of planning all at once; the arrow never
-- leads back to a stop already passed.
-- ---------------------------------------------------------------------------
-- Kalimdor zone maps (tools/fixtures/travel/UiMap.csv, UiMapAssignment.csv)
local KALIMDOR = {
    {1412, 1, 266.66601562, 2479.166992, 6154.166992, 4102.082031},
    {1413, 1, 1612.499878, 2622.916504, 10133.33301, 6756.249878},
    {1440, 1, 4672.916504, 1699.999878, 5766.666382, 3843.749878},
    {1441, 1, -3966.666504, -433.333313, 4399.999695, 2933.333008},
    {1442, 1, 2916.666504, 3245.833252, 4883.33313, 3256.249817},
    {1443, 1, 452.083313, 4233.333008, 4495.833008, 2997.916565},
    {1444, 1, -2366.666504, 5441.666504, 6949.999756, 4633.333008},
    {1445, 1, -2033.333252, -974.999939, 5250.000061, 3499.999756},
    {1456, 1, -849.999939, 516.666626, 1043.749939, 695.833313},
}
for _, f in ipairs(KALIMDOR) do
    shippedMaps[f[1]] = { mapID = f[1], name = tostring(f[1]), cont = f[2], top = f[3], left = f[4], w = f[5], h = f[6],
        mapType = 3, parentMapID = 12 }
end
-- the stops still ahead, from the step the arrow is on
local function Ahead(p)
    if not p then return {} end
    local out = {}
    for i = p.index or 2, #p.path do out[#out + 1] = p.path[i].node.id or (p.path[i].node.goal and 'goal') or '?' end
    return out
end
-- a route change: what is ahead is not what was ahead, less stops passed
local function Changed(before, now)
    if #now > #before then return true end
    for k = 1, #now do if now[#now - k + 1] ~= before[#before - k + 1] then return true end end
    return false
end
local function Compare(label, sc)
    local function Session(sliced)
        UseShipped()
        ns.Set('travelFlights', false); ns.Set('travelBoats', false); ns.Set('travelPreference', sc.pref)
        T._SetSliced(sliced)
        WP.ClearAll(true)
        Stand(sc.from[1], sc.from[2], sc.from[3])
        if sc.setup then sc.setup() end
        local w = WP.Add(sc.to[1], sc.to[2], sc.to[3], { title = label })
        WP.SetActive(w, true)
        return w
    end
    -- the lead: planning all at once, the player walking as sc.policy says
    Session(false)
    local track = {}
    for f = 1, sc.seconds * 60 do
        if sc.events and sc.events[f] then sc.events[f]() end
        local w = WP.GetActive()
        Steer(w)
        if sc.policy == 'straight' then
            local gc, gx, gy = G.MapToWorld(w.m, w.x, w.y)
            Toward(gc, gx, gy, sc.speed / 60)
        else
            Walk(sc.speed / 60)
        end
        track[f] = { M.player.inst, M.player.wx, M.player.wy }
    end
    local function Replay(sliced)
        Session(sliced)
        local out, f0 = {}, #finishes
        local lastPlan, adoptedAt = nil, 0
        for f, at in ipairs(track) do
            M.player.inst, M.player.wx, M.player.wy = at[1], at[2], at[3]
            if sc.events and sc.events[f] then sc.events[f]() end
            local s = Steer(WP.GetActive())
            local p = T.Current()
            -- when the plan steered by came from a job's answer
            if p ~= lastPlan and p and finishes[#finishes] and finishes[#finishes].j.best and p.path == finishes[#finishes].j.best.path then adoptedAt = f end
            lastPlan = p
            out[f] = { title = s and s.title or '(plain arrow)', stop = p and p.target and (p.target.node.id or (p.target.node.goal and 'goal')) or '-',
                ahead = Ahead(p), plan = p ~= nil, adopted = adoptedAt }
        end
        local longest = 0
        for k = f0 + 1, #finishes do
            local fin = finishes[k]
            if fin.started and fin.j.urgent == false then longest = math.max(longest, fin.at - fin.started) end
        end
        return out, longest
    end
    local a, job = Replay(true)
    local b = Replay(false)
    local allow = math.floor(job * 60 + 0.5) + 1
    -- lastChange: planning all at once changed its route or its stop
    local lastChange, changes, differ, late, worst, back = -math.huge, 0, 0, 0, 0, 0
    local passed = {} -- stop -> the frame planning all at once left it behind
    for f = 1, #track do
        if f > 1 and Changed(b[f - 1].ahead, b[f].ahead) then
            lastChange, changes, passed = f, changes + 1, {}
        elseif f > 1 and b[f - 1].stop ~= b[f].stop then
            lastChange, passed[b[f - 1].stop] = f, f
        end
        passed[b[f].stop] = nil
        if a[f].plan and (a[f].title ~= b[f].title or a[f].stop ~= b[f].stop) then
            differ = differ + 1
            worst = math.max(worst, f - lastChange)
            if f - lastChange > allow then late = late + 1 end
        end
        -- an answer taken after planning all at once had passed the stop it leads to
        if a[f].plan and a[f].stop ~= b[f].stop and passed[a[f].stop] and a[f].adopted >= passed[a[f].stop] then back = back + 1 end
    end
    print(('  %s: %d frames, %d route changes all at once; %d frames differ, at most %d frames after a change (one background job: %d frames); %d frames lead back'):format(
        label, #track, changes, differ, worst == 0 and 0 or worst, allow, back))
    check(changes >= (sc.changes or 1), label .. ': (control) planning all at once changes route on the way')
    check(late == 0, label .. ': the arrow equals planning all at once, but within one background job after its route changes (' .. late .. ' frames later)')
    check(back == 0, label .. ': the arrow never leads back to a stop already passed (' .. back .. ' frames)')
end
Compare('over the hills (terrain legs)', { from = crossZone.from, to = crossZone.to, pref = 'safer', speed = 7, seconds = 60, policy = 'follow' })
-- the reviewer's R1 (s1_18r): mounted, straight at it, across Stonetalon
Compare('R1 Stonetalon', { from = { 1442, .2114, .2517 }, to = { 1442, .4018, .6204 }, pref = 'safer', speed = 14, seconds = 40, policy = 'straight' })
-- R3 (s1_20w): walking straight through Thousand Needles' crossings
Compare('R3 Thousand Needles', { from = { 1441, .5677, .2814 }, to = { 1441, .4033, .7004 }, pref = 'fastest', speed = 7, seconds = 120, policy = 'straight' })
-- R4 (s5_switch_Hs): mounted from the Barrens to Stonetalon, following the arrow
-- (the waypoint switched to another in the Barrens at 30 s and back at 90 s)
do
    local B
    Compare('R4 Barrens to Stonetalon', { from = { 1413, .4, .3 }, to = { 1442, .47, .62 }, pref = 'safer', speed = 14, seconds = 150, policy = 'follow',
        setup = function() B = WP.Add(1413, .7, .7, { title = 'B' }) end,
        events = { [30 * 60] = function() WP.SetActive(B, true) end, [90 * 60] = function() WP.SetActive(WP.List()[2] or B, true) end } })
end

-- ---------------------------------------------------------------------------
-- (s) One slice a frame: Travel.Refresh (TAXIMAP_OPENED) steers from the
-- event in a frame the arrow has already steered; the re-plan it asks for
-- still comes
-- ---------------------------------------------------------------------------
STEP = 1
do
    local w = Begin(thrall)
    WP.SetActive(w, true)
    Steer(w)
    local j = Job()
    check(j ~= nil and frame.pumped == j, 'refresh: (control) a job runs, resumed this frame')
    local p0, r0 = pops, counts.replan
    frame.pumped = nil
    T.Invalidate(); T.Refresh() -- the same frame (GetTime unchanged)
    check(frame.pumped == nil and pops == p0, 'refresh: no second slice in the frame (' .. (pops - p0) .. ' expansions)')
    check(counts.replan == r0 + 1 and Job() == j and Queued(), 'refresh: the re-plan falls due (queued after the urgent job)')
    Steer(w)
    check(frame.pumped == j and frame.pops > 0, 'refresh: the next frame resumes it once')
end

-- ---------------------------------------------------------------------------
-- (t) A job not resumed for over a second: the arrow hidden (Arrow.lua does
-- not steer), in the same area, it goes on at the urgent budget and a
-- search from where the player is follows it; aboard a ride it starts
-- again from where the player lands
-- ---------------------------------------------------------------------------
do
    local w = Begin(thrall)
    for _ = 1, 5 do Steer(w) end
    local j = Job()
    M.now = M.now + 1.5 -- no Steer for 1.5 s; meanwhile the player walked on
    M.player.wx = M.player.wx + 8
    Steer(w)
    local j2 = Job()
    check(j ~= nil and j2 == j and Urgent(j2) and frame.pumped == j and Queued() and upvalue(T.Steer, 'queuedUrgent') == true,
        'idle job: after 1.5 s unresumed (arrow hidden) it goes on at the urgent budget, and a search from here is queued after it')
    -- aboard a flight for 3 s: not resumed; after landing, from where you are
    for _ = 1, 5 do Steer(w) end
    j = Job()
    M.player.taxi = true
    for _ = 1, 180 do Steer(w) end
    check(Job() == j, 'idle job: (control) aboard, the job waits')
    M.player.taxi = false
    M.player.wx = M.player.wx + 30
    Steer(w)
    j2 = Job()
    check(j2 ~= nil and j2 ~= j and Here(j2), 'idle job: after a flight it starts again from where you landed')
end
STEP = 0.05

-- ---------------------------------------------------------------------------
-- (u) An answer worked out from where you were, when you have since passed
-- a stop of the route you follow: not taken (its first steps may lie behind
-- you); an urgent search from here starts in the same frame, and its answer
-- is taken whatever happens meanwhile (tests/run_travel_reroute.lua's network)
-- ---------------------------------------------------------------------------
STEP = 4 -- one node expansion a frame
do
    local at = RerouteNetwork()
    ns.Set('travelPreference', 'fastest')
    T._SetSliced(true)
    WP.ClearAll(true)
    Go(at(.2, .5))
    local w = WP.Add(37, .8, .5, { title = 'Passing stops' })
    Steer(w); Settle(w)
    local kept = T.Current()
    check(kept and kept.target.node.id == 'P', 'passed stop: (control) the plan leads to P first')
    Steer(w, 6) -- the periodic re-plan, 5 s after the last job: a background job
    local j1 = Job()
    check(j1 and j1.urgent == false, 'passed stop: (control) a background job runs')
    Go(at(.3, .5)) -- at P: the arrow moves on to the flight master
    local f0, rejectedAt = #finishes, nil
    for f = 1, 120 do
        Steer(w)
        if #finishes > f0 then
            local j2 = Job()
            check(finishes[#finishes].j == j1 and T.Current() and T.Current().path ~= j1.best.path, 'passed stop: the answer from before P is not taken')
            check(j2 and j2 ~= j1 and Urgent(j2) and Here(j2), 'passed stop: an urgent search from here starts in the same frame')
            rejectedAt = f
            break
        end
    end
    check(rejectedAt ~= nil, 'passed stop: (control) the background job answered')
    -- passing the next stop (the flight master) while that urgent job runs: its answer is taken anyway
    local j2 = Job()
    local fm = { T.Pos(T.Data().nodes.FM) }
    M.player.inst, M.player.wx, M.player.wy = fm[1], fm[2], fm[3]
    f0 = #finishes
    for _ = 1, 120 do
        Steer(w)
        if #finishes > f0 then break end
    end
    local last = finishes[#finishes]
    -- taken: no other search follows it (KeepFollowed may keep the route it re-anchored)
    check(last and last.j == j2 and Job() == nil and T.Current() ~= nil and (T.Current().path[1].node == j2.here or T.Current() == j2.old),
        'passed stop: the next answer is taken, though another stop was passed meanwhile')
    check(#M.errors == 1, 'passed stop: no errors ' .. tostring(M.errors[2]))
end
-- R3 (s1_20w): a search that began 14.9 yd past a crossing (within the 15 yd
-- a stop counts as reached) answers when you are 15.05 yd past it: its
-- route leads back over that crossing, as planning all at once would have
-- found it where the search began; the arrow, as there, goes on to the goal
do
    C_Map.GetBestMapForUnit = function() return 37 end
    local cont, wx, wy = mapToWorld(37, .1, .5)
    ns.TravelData = { areas = { 'near', 'far' }, indoor = {}, maps = '37\t1', regions = '37\t2\t80\t50\t10',
        nodes = table.concat({ 'A', 'pass', 1, cont, wx, wy, 37, 10, 50 }, '\t'), links = '', cities = '', towns = '', levels = '', factors = '' }
    T._Reset(); T.Data()
    T.AddCrossing('XR3', 1, 2, 37, .7, .5)
    ns.Set('travelPreference', 'fastest')
    local xc, xx, xy = mapToWorld(37, .7, .5)
    local function Past(yards) M.player.inst, M.player.wx, M.player.wy = xc, xx, xy + yards end
    local function Run(sliced)
        T._Reset(); T.Data(); T.AddCrossing('XR3', 1, 2, 37, .7, .5)
        T._SetSliced(sliced)
        WP.ClearAll(true)
        Past(14.9)
        local w = WP.Add(37, .85, .5, { title = 'Over the crossing' })
        Steer(w); if sliced then Settle(w) end
        return w
    end
    local w = Run(false)
    local p = T.Current()
    check(p and #p.path == 4 and p.path[2].node.id == 'XR3a' and p.index == 4 and T._PlayerPlace().area == 1,
        'R3 crossing: (control) all at once, 14.9 yd past the crossing the arrow leads on to the goal')
    w = Run(true)
    T.Invalidate()
    Steer(w)
    local j = Job()
    Past(15.05)
    for _ = 1, 60 do Steer(w); if not Job() then break end end
    p = T.Current()
    check(j and Urgent(j) and finishes[#finishes].j == j and p and p.path[1].node == j.here, 'R3 crossing: (control) the search from 14.9 yd answered at 15.05 yd and was taken')
    check(p and p.index == #p.path and p.target.node.goal, 'R3 crossing: the arrow leads on to the goal, not back to the crossing (' .. tostring(p and p.target and p.target.node.id) .. ')')
end
STEP = 0.05

-- ---------------------------------------------------------------------------
-- (v) A search spread over frames reads one floor position (Terrain.Record),
-- the one it began with, whatever another search or Terrain.Sample sets
-- between its slices
-- ---------------------------------------------------------------------------
do
    d = UseShipped()
    local E = ns.Terrain
    local keys = {}
    for key in pairs(d.walkEvidence) do keys[#keys + 1] = key end
    table.sort(keys)
    local e = d.walkEvidence[keys[1]]
    local st = E.Store()
    local saved = st.records[e.key]
    st.records[e.key] = { state = 'confirmed', build = d.buildKey, scope = 0, when = 0, count = 1,
        points = { { e.a.wx, e.a.wy, 0 }, { e.b.wx, e.b.wy, 0 } } }
    local unitPosition, at = UnitPosition, nil
    UnitPosition = function() return at[1], at[2], at[3], at[4] end
    local far = { e.a.wx + 500, e.a.wy, 0, e.a.cont }
    local above = { e.a.wx, e.a.wy, 10, e.a.cont } -- 10 yd over the trace's end: the trace isn't proof here
    at = above; E.Refresh()
    local controlAbove = E.Record(e) == nil
    at = far; E.Refresh()
    check(controlAbove and E.Record(e) ~= nil, 'floor: (control) the floor decides whether the record is proof')
    local seen = {}
    local co = coroutine.create(function()
        at = far; E.Refresh()
        coroutine.yield()
        seen[1] = E.Record(e) ~= nil
        coroutine.yield()
        seen[2] = E.Record(e) ~= nil
    end)
    assert(coroutine.resume(co))
    at = above; E.Refresh() -- a search all at once (Travel.Routes from a click) begins between its slices
    local main = E.Record(e) == nil
    assert(coroutine.resume(co))
    local co2 = coroutine.create(function()
        at = above; E.Refresh()
        coroutine.yield()
        seen[3] = E.Record(e) ~= nil
    end)
    assert(coroutine.resume(co2))
    assert(coroutine.resume(co))
    assert(coroutine.resume(co2))
    check(main, 'floor: a search all at once reads its own floor')
    check(seen[1] == true and seen[2] == true, 'floor: a paused search reads the floor it began with, before and after another search')
    check(seen[3] == false, 'floor: another paused search reads its own')
    UnitPosition = unitPosition
    st.records[e.key] = saved
end

-- C_Timer callbacks due by now (TravelAbilities reads its answers again a
-- second after an event)
local function RunTimers()
    local due, keep = {}, {}
    for _, tm in ipairs(M.timers) do if tm.at <= M.now then due[#due + 1] = tm else keep[#keep + 1] = tm end end
    M.timers = keep
    for _, tm in ipairs(due) do tm.fn() end
end

-- ---------------------------------------------------------------------------
-- (w) A slice's work, all of it: a search's set-up (Terrain's corridors:
-- a record per piece of surveyed evidence), the start's expansion (every
-- walk tried in its area, every node of the network looked over for
-- surveyed points) and each node. A work clock: the frame clock is the work
-- done, each call at what it costs on this Lua (tools: CanWalk 3.8 us,
-- Terrain.Decide 1.2, Danger 6, Dist 0.2, a heap pop 1, Terrain.Record 0.5).
-- Every slice ends within its budget and 0.4 ms (the most work between two
-- clock readings); a search's set-up never follows other work (over 10 us)
-- in a slice.
-- ---------------------------------------------------------------------------
do
    local UNIT = 0.001 -- ms per microsecond of work
    local work, sinceRead, co, inSlice, setupAfterWork = 0, 0, nil, 0, 0
    local worstGap, slices, over, worstBg, worstUrgent = 0, 0, 0, 0, 0
    local function Add(units)
        if co and coroutine.running() == co then work, sinceRead, inSlice = work + units, sinceRead + units, inSlice + units end
    end
    local saved = {}
    for name, cost in pairs({ CanWalk = 3.8, Dist = 0.2, Pop = 1, Danger = 6 }) do
        local fn, i = upvalue(T.Search, name)
        saved[name] = { fn, i }
        debug.setupvalue(T.Search, i, function(...) Add(cost); return fn(...) end)
    end
    local record, refresh, decide = ns.Terrain.Record, ns.Terrain.Refresh, ns.Terrain.Decide
    ns.Terrain.Record = function(...) Add(0.5); return record(...) end
    ns.Terrain.Decide = function(...) Add(1.2); return decide(...) end
    ns.Terrain.Refresh = function(...)
        if co and coroutine.running() == co and inSlice > 10 then setupAfterWork = setupAfterWork + 1 end
        return refresh(...)
    end
    local clockFn = debugprofilestop
    debugprofilestop = function()
        if co and coroutine.running() == co then worstGap, sinceRead = math.max(worstGap, sinceRead), 0 end
        return work * UNIT
    end
    local pump, pk = upvalue(T.Steer, 'Pump')
    debug.setupvalue(T.Steer, pk, function(...)
        local j = Job()
        co, sinceRead, inSlice = j and j.co, 0, 0
        local urgent = j and j.urgent
        local r = pump(...)
        local ms = inSlice * UNIT
        slices = slices + 1
        if urgent then worstUrgent = math.max(worstUrgent, ms) else worstBg = math.max(worstBg, ms) end
        if ms > (urgent and 4 or 1) + 0.4 then over = over + 1 end
        co = nil
        return r
    end)
    -- the long trip (its first job also searches the fastest way, for the
    -- offer: two searches), walking, with a Travel.Invalidate every 3 s
    -- (urgent jobs); the walk across a zone (background jobs); and from the
    -- Barrens, the area with the most stops (309: its start's expansion)
    for _, sc in ipairs({ thrall, ground, { from = { 1413, .52, .3 }, to = { 1442, .47, .62 }, map = 1413 } }) do
        d = UseShipped()
        -- (the mock's zone rectangles overlap there: the game says the Barrens)
        if sc.map then C_Map.GetBestMapForUnit = function() return sc.map end end
        ns.Set('travelFlights', sc.flights ~= false); ns.Set('travelBoats', sc.flights ~= false); ns.Set('travelPreference', 'safer')
        T._SetSliced(true)
        WP.ClearAll(true)
        Stand(sc.from[1], sc.from[2], sc.from[3])
        local w = WP.Add(sc.to[1], sc.to[2], sc.to[3], { title = 'Work per slice' })
        check(not sc.map or T._PlayerPlace().area == 54, 'work per slice: (control) the start is in the Barrens\' area (' .. tostring(T._PlayerPlace().area) .. ')')
        WP.SetActive(w, true)
        for f = 1, 60 * 30 do
            if f % 180 == 0 then T.Invalidate() end
            Steer(w)
            Walk(7 / 60)
        end
    end
    print(('  work per slice: %d slices, worst background %.2f ms, worst urgent %.2f ms, worst %.2f ms between clock readings (work clock), %d set-ups after other work'):format(
        slices, worstBg, worstUrgent, worstGap * UNIT, setupAfterWork))
    check(slices > 100, 'work per slice: (control) jobs ran (' .. slices .. ' slices)')
    check(over == 0, ('work per slice: every slice within its budget and 0.4 ms (%d over; worst background %.2f ms, urgent %.2f ms)'):format(over, worstBg, worstUrgent))
    check(worstGap * UNIT <= 0.4, ('work per slice: at most 0.4 ms of work between two clock readings (%.2f ms)'):format(worstGap * UNIT))
    check(setupAfterWork == 0, 'work per slice: a search\'s set-up never follows other work in its slice (' .. setupAfterWork .. ' times)')
    debug.setupvalue(T.Steer, pk, pump)
    for _, v in pairs(saved) do debug.setupvalue(T.Search, v[2], v[1]) end
    ns.Terrain.Record, ns.Terrain.Refresh, ns.Terrain.Decide = record, refresh, decide
    debugprofilestop = clockFn
end

-- ---------------------------------------------------------------------------
-- (x) A clock another addon restarts mid-slice (debugprofilestart: it goes
-- back), or one that stops: every slice still ends. A clock that went back
-- counts as the budget spent; the work cap (1000 units in the background,
-- 4000 urgent, a node expanded at least one) holds whatever the clock says.
-- ---------------------------------------------------------------------------
for _, mode in ipairs({ 'back', 'stopped' }) do
    local clockFn, fresh = debugprofilestop, false
    debugprofilestop = function()
        if mode == 'stopped' then return 5 end
        if fresh then fresh = false; return 1000 + pops * STEP end -- the slice begins
        return pops * STEP -- then the clock is restarted: 1000 ms back
    end
    local pump, pk = upvalue(T.Steer, 'Pump')
    local worst, whole, n = 0, 0, 0
    debug.setupvalue(T.Steer, pk, function(...) fresh = true; return pump(...) end)
    local w = Begin(thrall)
    for _ = 1, 60 * 20 do
        Steer(w)
        n = n + 1
        if frame.pumped then worst = math.max(worst, frame.pops) end
        if frame.whole then whole = whole + 1 end
        Walk(7 / 60)
    end
    debug.setupvalue(T.Steer, pk, pump)
    debugprofilestop = clockFn
    print(('  clock %s: worst %d node expansions in a slice, %d frames with a whole search'):format(mode, worst, whole))
    check(whole == 0, 'clock ' .. mode .. ': no frame holds a whole search (' .. whole .. ')')
    if mode == 'back' then
        -- (restarted in every slice: a node a frame, and the job goes on)
        check(worst > 0 and worst <= 2, 'clock gone back: the slice ends at its first checkpoint (' .. worst .. ' expansions)')
    else
        check(worst > 0 and worst <= 4000, 'clock stopped: the work cap ends every slice (' .. worst .. ' expansions)')
        check(T.Current() ~= nil, 'clock stopped: the route still arrives')
    end
end

-- ---------------------------------------------------------------------------
-- (x2) A clock that stops: the work cap alone ends each slice, and a slice
-- never counts more than its cap and 2 * START_WEIGHT units (the most one
-- pause holds: a walk from the start that can be walked). On the long trip,
-- and in a made-up field of 30 stops every walk from the start reaches
-- (each 3 * START_WEIGHT units: 1153.75 units in a slice before).
-- ---------------------------------------------------------------------------
do
    local START_WEIGHT = upvalue(T.Search, 'START_WEIGHT')
    check(START_WEIGHT == 64, 'frozen clock: (control) a walk from the start counts 64 units (' .. tostring(START_WEIGHT) .. ')')
    local clockFn = debugprofilestop
    debugprofilestop = function() return 5 end
    local pump, pk = upvalue(T.Steer, 'Pump')
    local real = upvalue(pump, 'pump') -- (the counters at the top wrap it)
    local slices, capped, worst, worstField = 0, 0, -math.huge, -math.huge
    debug.setupvalue(T.Steer, pk, function(...)
        local r = pump(...)
        local work, cap = upvalue(real, 'sliceWork'), upvalue(real, 'sliceWorkMax')
        slices = slices + 1
        if work >= cap then capped = capped + 1 end
        worst = math.max(worst, work - cap)
        return r
    end)
    d = UseShipped()
    ns.Set('travelFlights', true); ns.Set('travelBoats', true); ns.Set('travelPreference', 'safer')
    T._SetSliced(true)
    WP.ClearAll(true)
    Stand(thrall.from[1], thrall.from[2], thrall.from[3])
    local w = WP.Add(thrall.to[1], thrall.to[2], thrall.to[3], { title = 'Frozen clock' })
    WP.SetActive(w, true)
    for f = 1, 60 * 15 do
        if f % 180 == 0 then T.Invalidate() end
        Steer(w)
        Walk(7 / 60)
    end
    -- the field: one area, no terrain evidence; standing, background jobs
    local trip = worst
    worst = -math.huge
    C_Map.GetBestMapForUnit = function() return 37 end
    local rows = {}
    for i = 0, 29 do
        local x, y = .1 + (i % 10) * .08, .3 + math.floor(i / 10) * .2
        local c, px, py = mapToWorld(37, x, y)
        rows[#rows + 1] = table.concat({ 'F' .. i, 'pass', 1, c, px, py, 37, x * 100, y * 100 }, '\t')
    end
    ns.TravelData = { areas = { 'field' }, indoor = {}, maps = '37\t1', regions = '', nodes = table.concat(rows, '\n'),
        links = '', cities = '', towns = '', levels = '', factors = '' }
    T._Reset(); T.Data()
    T._SetSliced(true)
    WP.ClearAll(true)
    local c0, px0, py0 = mapToWorld(37, .05, .5)
    M.player.inst, M.player.wx, M.player.wy = c0, px0, py0
    w = WP.Add(37, .95, .5, { title = 'Frozen clock, field' })
    WP.SetActive(w, true)
    local s0, c0capped = slices, capped
    for _ = 1, 60 * 15 do Steer(w) end
    worstField = worst
    worst = math.max(trip, worstField)
    debug.setupvalue(T.Steer, pk, pump)
    debugprofilestop = clockFn
    print(('  frozen clock: %d slices, %d ended by the work cap; worst over the cap %.3f units on the trip, %.3f in the field'):format(
        slices, capped, trip, worstField))
    check(capped - c0capped >= 10 and slices - s0 >= 15, ('frozen clock: (control) in the field, the work cap ends slices (%d of %d)'):format(capped - c0capped, slices - s0))
    check(capped > 50, 'frozen clock: (control) the work cap ends slices (' .. capped .. ' of ' .. slices .. ')')
    check(worst < 2 * START_WEIGHT, ('frozen clock: every slice within its cap and 2 * START_WEIGHT units (worst %.3f over)'):format(worst))
end

-- ---------------------------------------------------------------------------
-- (y) A setting the planner reads changed while a job runs: its answer is
-- never taken; the urgent search queued since answers. Toggled every
-- frame, every route taken is one planned under the settings true then,
-- and routes keep coming (an answer kept aside is taken when its settings
-- come back, at most a frame later).
-- ---------------------------------------------------------------------------
do
    local w = Begin(thrall) -- boats and flights on: the way goes by zeppelin
    check(Job() ~= nil and Urgent(Job()) and T.Current() == nil, 'setting mid-job: (control) the first job runs')
    ns.Set('travelBoats', false)
    local bad, seen, n = 0, 0, 0
    for _ = 1, 600 do
        Steer(w)
        local p = T.Current()
        if p then
            seen = seen + 1
            for i = p.index or 2, #p.path do
                local how = p.path[i].via
                if type(how) == 'table' and (how.method == 'ship' or how.method == 'zeppelin') then bad = bad + 1; break end
            end
        end
        if not Job() and n > 0 then break end
        n = n + 1
    end
    check(bad == 0, 'setting mid-job: boats turned off, no frame follows a route by boat (' .. bad .. ' frames)')
    -- the travelFlights setting toggled every frame for 20 s (boats on)
    ns.Set('travelBoats', true)
    w = Begin(thrall)
    local took, wrong, listening = 0, 0, true
    local function OnPlanned(p)
        if listening and p and p.c and p.path[1].node.player then
            took = took + 1
            if p.c.flights ~= (ns.Get('travelFlights') and true or false) then wrong = wrong + 1 end
        end
    end
    ns.On('TRAVEL_PLANNED', OnPlanned)
    local took0 = took
    for f = 1, 60 * 20 do
        ns.Set('travelFlights', f % 2 == 0)
        Steer(w)
    end
    print(('  settings toggled every frame for 20 s: %d routes taken, %d under settings no longer true'):format(took - took0, wrong))
    check(wrong == 0, 'settings toggled every frame: no route taken under settings no longer true (' .. wrong .. ')')
    check(took - took0 >= 3, 'settings toggled every frame: routes are still taken (' .. (took - took0) .. ' in 20 s)')
    listening = false
    ns.Set('travelFlights', true)
end

-- ---------------------------------------------------------------------------
-- (y2) An answer kept aside (planned under a setting since changed) is taken
-- when the setting comes back only while it is still about where you are:
-- the area and city it was planned in, within REPLAN_MOVED (10 yd) of
-- there, and no older than REPLAN_EVERY (2 s). Else it is dropped, and the
-- search queued since answers.
-- ---------------------------------------------------------------------------
do
    -- in Undercity's sewers, 4.8 yd from another of the city's areas
    local sewers = { from = { 1458, .465, .35 }, to = thrall.to }
    local function Kept(sc, label, change)
        local w = Begin(sc)
        ns.Set('travelFlights', false)
        local n = 0
        while not upvalue(T.Steer, 'held') and n < 600 do Steer(w); n = n + 1 end
        local h = upvalue(T.Steer, 'held')
        check(h ~= nil and Job() ~= nil, label .. ': (control) an answer kept aside, the search queued since runs')
        if not h then return false, nil, w end
        check(T.Dist(T._PlayerPlace(), h.here) < 1e-6, label .. ': (control) kept aside where you stand')
        local dt = change(h)
        ns.Set('travelFlights', true)
        local f0 = #finishes
        Steer(w, dt)
        local took = false
        for k = f0 + 1, #finishes do if finishes[k].j == h then took = true end end
        return took, h, w
    end
    local function Near(h, label, area)
        local here = T._PlayerPlace()
        local dd = T.Dist(here, h.here)
        check(here.city == h.here.city and (here.area == h.here.area) == (area == 'same') and dd and dd < 10,
            ('%s: (control) %s area, %.1f yd from where it was planned'):format(label, area, dd or -1))
    end
    -- the setting back at once, in place or 5 yd on: taken
    local took = Kept(thrall, 'kept aside, in place', function() end)
    check(took, 'kept aside: the setting back at once, in place: the answer is taken')
    local h
    took, h = Kept(thrall, 'kept aside, 5 yd on', function() M.player.wx = M.player.wx + 5 end)
    if h then Near(h, 'kept aside, 5 yd on', 'same') end
    check(took, 'kept aside: the setting back at once, 5 yd on: the answer is taken')
    -- (a) into another area: over the sewers' border (4.8 yd), or far away
    local w
    took, h, w = Kept(sewers, 'kept aside, another area', function() Stand(1458, .47, .35) end)
    if h then Near(h, 'kept aside, another area', 'another') end
    check(not took, 'kept aside: into another area of the city (4.8 yd on): the answer is not taken')
    check(upvalue(T.Steer, 'held') ~= h, 'kept aside: into another area: it is dropped')
    Settle(w, 6000)
    local p = T.Current()
    check(p and h and p.c ~= h.c and p.c.flights == true and not Job(), 'kept aside: into another area: the search queued since answers')
    took = Kept(thrall, 'kept aside, far away', function() Stand(1411, .5, .5) end)
    check(not took, 'kept aside: far away in another zone: the answer is not taken')
    -- (b) over REPLAN_MOVED from where it was planned, in the same area
    took, h = Kept(thrall, 'kept aside, 11 yd on', function() M.player.wx = M.player.wx + 11 end)
    if h then
        local here = T._PlayerPlace()
        check(here.area == h.here.area and here.city == h.here.city and T.Dist(here, h.here) > 10,
            'kept aside, 11 yd on: (control) the same area, over 10 yd from where it was planned')
    end
    check(not took, 'kept aside: 11 yd on in the same area: the answer is not taken')
    -- (c) in place, the arrow hidden for over REPLAN_EVERY (no frame steers)
    took = Kept(thrall, 'kept aside, 2.1 s hidden', function() return 2.1 end)
    check(not took, 'kept aside: in place, the arrow hidden 2.1 s: the answer is not taken')
    took = Kept(thrall, 'kept aside, 1.5 s hidden', function() return 1.5 end)
    check(took, 'kept aside: in place, the arrow hidden 1.5 s: the answer is taken')
end

-- ---------------------------------------------------------------------------
-- (z) The arrow shown only in short windows ("hide in combat": 1.2 s
-- hidden, 0.4 s or 0.2 s shown) while walking on: jobs still answer (one
-- not resumed for over a second in the same area goes on, urgently, and the
-- search from where the player is follows it at once)
-- ---------------------------------------------------------------------------
for _, shown in ipairs({ 0.4, 0.2 }) do
    local w = Begin(thrall)
    local n = 0
    while not (T.Current() and not Job()) and n < 6000 do Steer(w); n = n + 1 end
    local f0, follow, resumed = #finishes, 0, 0
    local t0 = M.now
    while M.now - t0 < 60 do
        -- hidden: no Steer; the player walks on
        for _ = 1, 72 do M.now = M.now + 1 / 60; Walk(7 / 60) end
        local j = Job()
        for k = 1, math.floor(shown * 60 + 0.5) do
            Steer(w)
            if k == 1 and j and Job() == j then
                resumed = resumed + 1
                if Queued() and upvalue(T.Steer, 'queuedUrgent') == true then follow = follow + 1 end
            end
            Walk(7 / 60)
        end
    end
    local answered = #finishes - f0
    print(('  arrow shown %.1f s of every %.1f s, walking 60 s: %d jobs answered, %d resumed after a pause (%d with the search from here queued after)'):format(
        shown, shown + 1.2, answered, resumed, follow))
    check(answered >= 5, ('shown %.1f s at a time: jobs answer (%d in 60 s)'):format(shown, answered))
    check(resumed > 0 and follow == resumed, ('shown %.1f s at a time: a job resumed after a pause is followed by a search from where you are (%d/%d)'):format(shown, follow, resumed))
end

-- ---------------------------------------------------------------------------
-- (aa) While the search for the area you have just come into runs, the
-- arrow never aims at a crossing you have gone through (16 yd past it, not
-- within the 15 yd a stop counts as reached): it aims at the step after it.
-- Never past one you haven't: back over it, or beside it in the far area
-- still coming to it. And standing where the hearthstone landed: never
-- "use your hearthstone" again (the rest is a plain walk to the waypoint:
-- the normal arrow); before casting, it says to use it.
-- ---------------------------------------------------------------------------
STEP = 4 -- one node expansion a frame
do
    C_Map.GetBestMapForUnit = function() return 37 end
    -- area 1, then 2 (from x .6 at y .5), then 3 (from x .8); through a gate
    -- into each (a stop the arrow never takes as optional, as a surveyed
    -- crossing is not: the projection along the route stops there)
    local function row(id, area, x)
        local c, px, py = mapToWorld(37, x, .5)
        return table.concat({ id, 'pass', area, c, px, py, 37, x * 100, 50 }, '\t')
    end
    ns.TravelData = { areas = { 'one', 'two', 'three' }, indoor = {}, maps = '37\t1', regions = '37\t3\t120\t50\t40\n37\t2\t100\t30\t45',
        nodes = table.concat({ row('A', 1, .1), row('XD1a', 1, .6), row('XD1b', 2, .6), row('XD2a', 2, .81), row('XD2b', 3, .81) }, '\n'),
        links = 'XD1a\tXD1b\tgate\t0\nXD2a\tXD2b\tgate\t0', cities = '', towns = '', levels = '', factors = '' }
    local function Network()
        T._Reset(); T.Data()
        ns.Set('travelPreference', 'fastest'); ns.Set('travelHearth', false)
        T._SetSliced(true)
        WP.ClearAll(true)
    end
    local function At(x, y) local c, px, py = mapToWorld(37, x, y); M.player.inst, M.player.wx, M.player.wy = c, px, py end
    local function Aims(s, id)
        if not s or not s.dist then return false end
        return math.abs(s.dist - T.Dist(T._PlayerPlace(), T.Data().nodes[id])) < 1e-6
    end
    Network()
    At(.55, .5)
    local w = WP.Add(37, .95, .5, { title = 'Over two crossings' })
    WP.SetActive(w, true)
    Steer(w); Settle(w)
    local p = T.Current()
    check(p and p.target and p.target.node.id == 'XD1a' and #p.path == 6 and T._PlayerPlace().area == 1,
        'crossing: (control) the route goes through gate XD1 then XD2; the arrow leads to XD1')
    -- 16 yd past XD1, in area 2
    At(.6 + 16 / 3000, .5)
    local frames, back, forward = 0, 0, 0
    local s = Steer(w, 1)
    check(T._PlayerPlace().area == 2 and Job() and Urgent(Job()), 'crossing: (control) in area 2, an urgent search runs')
    while T.Current() == p and frames < 120 do
        frames = frames + 1
        if Aims(s, 'XD1a') or Aims(s, 'XD1b') then back = back + 1 elseif Aims(s, 'XD2a') then forward = forward + 1 end
        s = Steer(w)
    end
    check(frames > 1 and T.Current() ~= p, 'crossing: (control) the search for area 2 answered after ' .. frames .. ' frames')
    check(back == 0 and forward == frames, ('crossing: while it runs the arrow never aims back at the crossing gone through, but at the step after it (%d back, %d on of %d frames)'):format(back, forward, frames))
    -- back over it into area 1 while the search runs: the crossing is ahead again
    Network()
    At(.55, .5)
    w = WP.Add(37, .95, .5, { title = 'Over and back' })
    WP.SetActive(w, true)
    Steer(w); Settle(w)
    p = T.Current()
    At(.6 + 16 / 3000, .5)
    Steer(w, 1)
    At(.594, .5)
    s = Steer(w)
    check(T.Current() == p and T._PlayerPlace().area == 1 and Aims(s, 'XD1a'), 'crossing: touched area 2 and turned back: the arrow leads to the crossing again')
    -- in area 2 beside the crossing, still coming to it
    Network()
    At(.55, .5)
    w = WP.Add(37, .95, .5, { title = 'Beside the crossing' })
    WP.SetActive(w, true)
    Steer(w); Settle(w)
    p = T.Current()
    At(.58, .35)
    s = Steer(w, 1)
    check(T._PlayerPlace().area == 2 and T.Current() == p and Aims(s, 'XD1a'),
        'crossing: in the far area beside the crossing, not past it: the arrow still leads to it')
    -- the hearthstone: chosen to land at XD2b's spot (area 3); then standing there
    Network()
    At(.3, .5)
    w = WP.Add(37, .95, .5, { title = 'Hearth' })
    WP.SetActive(w, true)
    local start = T._PlayerPlace()
    local inn = T.Data().nodes.XD2b
    local cont3, gx, gy = mapToWorld(37, .95, .5)
    local goal = { m = 37, x = .95, y = .5, cont = cont3, wx = gx, wy = gy, area = 3, goal = true }
    local jump = { kind = 'hearth', item = 6948, name = 'Test inn', node = inn, cost = 20 }
    local path = { { node = start, at = 0, risk = 0 }, { node = inn, via = jump, at = 20, risk = 0 },
        { node = goal, via = 'walk', at = 60, risk = 0 } }
    T.Select(w, { path = path, total = 60, risk = 0, preference = 'fastest' })
    s = Steer(w)
    check(s and s.title == T.StepText(T.Current().path, 2, WP.ShortName(w)) and s.pin, 'hearth: (control) before casting the arrow says to use the hearthstone')
    local _, ix, iy = T.Pos(inn)
    M.player.wx, M.player.wy = ix, iy + 5 -- landed (a loading screen later)
    s = Steer(w)
    check(T._PlayerPlace().area == 3 and s == nil, 'hearth: standing where it landed, never "use your hearthstone" again: the normal arrow (' .. tostring(s and s.title) .. ')')
end
STEP = 0.05

-- ---------------------------------------------------------------------------
-- (ab) The hearthstone coming off cooldown, or going on it (an event the
-- game sends): the route reflects it within a second (TravelAbilities reads
-- again) and one urgent job, both ways. Thirty seconds of the six events at
-- 10 Hz with nothing changed: not one search more than without them.
-- ---------------------------------------------------------------------------
do
    d = UseShipped()
    ns.Set('travelFlights', true); ns.Set('travelBoats', true); ns.Set('travelPreference', 'safer'); ns.Set('travelHearth', true)
    T._SetSliced(true)
    WP.ClearAll(true)
    local savedItem, savedBind = C_Item, GetBindLocation
    local onCooldown = true
    C_Item = {}
    for k, v in pairs(savedItem or {}) do C_Item[k] = v end
    C_Item.GetItemCount = function(id) return id == 6948 and 1 or 0 end
    C_Item.GetItemCooldown = function(id) if id == 6948 and onCooldown then return M.now - 10, 3600, 1 end return 0, 0, 1 end
    C_Item.IsEquippedItem = function() return false end
    C_Item.IsUsableItem = function() return true, false end
    C_Item.GetItemNameByID = function(id) return 'Item ' .. id end
    GetBindLocation = function() return 'Orgrimmar' end
    Stand(thrall.from[1], thrall.from[2], thrall.from[3])
    local w = WP.Add(thrall.to[1], thrall.to[2], thrall.to[3], { title = 'Home by hearth' })
    WP.SetActive(w, true)
    do -- bound at the inn nearest the waypoint
        local gc, gx, gy = G.MapToWorld(w.m, w.x, w.y)
        local best, bd
        for _, t in ipairs(d.towns) do
            local c, x, y = T.Pos(t.inn)
            if c == gc and x then local dd = (x - gx) ^ 2 + (y - gy) ^ 2; if not bd or dd < bd then best, bd = t.inn, dd end end
        end
        T.Know().bind = { m = best.m, x = best.x, y = best.y, name = 'Orgrimmar' }
    end
    local function Hearth(p)
        for i = p and (p.index or 2) or 1, p and #p.path or 0 do
            local how = p.path[i].via
            if type(how) == 'table' and how.kind == 'hearth' then return true end
        end
        return false
    end
    local function Frame() Steer(w); RunTimers() end
    local function Until(want)
        local t0, f0 = M.now, #finishes
        for _ = 1, 60 * 30 do
            Frame()
            if T.Current() and Hearth(T.Current()) == want then break end
        end
        local job = 0
        for k = f0 + 1, #finishes do local f = finishes[k]; if f.j.urgent and f.started then job = math.max(job, f.at - f.started) end end
        return M.now - t0, job
    end
    Frame(); Settle(w, 6000)
    check(T.Current() and not Hearth(T.Current()), 'hearth event: (control) on cooldown, the route does not use the hearthstone')
    Settle(w, 6000)
    -- ready: the game says so (BAG_UPDATE_COOLDOWN) just after a job ended
    onCooldown = false
    M.FireEvent('BAG_UPDATE_COOLDOWN')
    local took, job = Until(true)
    print(('  hearthstone ready: the route uses it after %.2f s (urgent job %.2f s)'):format(took, job))
    check(Hearth(T.Current()) and took <= 1 + job + 1 / 30, ('hearth event: ready, the route uses it within 1 s and one urgent job (%.2f s, job %.2f s)'):format(took, job))
    for _ = 1, 120 do Frame() end
    Settle(w, 6000)
    onCooldown = true
    M.FireEvent('BAG_UPDATE_COOLDOWN')
    took, job = Until(false)
    print(('  hearthstone used: the route stops using it after %.2f s (urgent job %.2f s)'):format(took, job))
    check(not Hearth(T.Current()) and took <= 1 + job + 1 / 30, ('hearth event: on cooldown, the route stops using it within 1 s and one urgent job (%.2f s, job %.2f s)'):format(took, job))
    -- the event storm: 30 s standing still, with and without the six events at 10 Hz each
    local events = { 'BAG_UPDATE_COOLDOWN', 'SPELL_UPDATE_COOLDOWN', 'SPELLS_CHANGED', 'BAG_UPDATE_DELAYED', 'PLAYER_EQUIPMENT_CHANGED', 'PLAYER_REGEN_ENABLED' }
    local function Run(storm)
        Settle(w, 6000)
        for _ = 1, 30 do Frame() end
        local s0 = starts
        for f = 1, 60 * 30 do
            if storm and f % 6 == 0 then for _, e in ipairs(events) do M.FireEvent(e) end end
            Frame()
        end
        return starts - s0
    end
    local quiet, storm = Run(false), Run(true)
    print(('  30 s standing: %d searches without events, %d with the six events at 10 Hz'):format(quiet, storm))
    check(quiet > 0 and storm == quiet, ('hearth event: an event storm with nothing changed adds no search (%d / %d)'):format(storm, quiet))
    C_Item, GetBindLocation = savedItem, savedBind
    ns.Set('travelHearth', false)
end

check(#M.errors == 1, 'no other errors: ' .. tostring(M.errors[2] or M.errors[1]))
print(('Travel sliced: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
