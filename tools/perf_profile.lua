-- Resource profile of the addon against the fake WoW API (tests/wowmock.lua).
-- Loads the real modules, logs in, then plays fixed scenarios frame by frame
-- (60 frames a second) and reports, for each:
--   * Lua heap after a full collection (KB)
--   * KB allocated per simulated second (collector stopped while measuring):
--     by the addon's own Lua ("addon"), and with what the fake API and
--     widgets allocate inside their calls on top ("total")
--   * CPU time per frame spent in the addon's handlers (median / worst, ms)
--   * widget calls and game API calls per simulated second
--   * the same split by the module that owns each OnUpdate/timer/event
-- Allocation and call counts do not depend on the machine's speed (the
-- planner runs on its expansion-count budget: no clock) and repeat from run
-- to run, the planner's allocation to within a fraction of a percent; CPU
-- times depend on the machine and its load.
-- In the game a widget call allocates nothing in Lua, and an API call only
-- the table it hands back (a map position, say): "addon" leaves both out,
-- and the calls are counted instead.
--
-- Run from the repository root:
--     lua5.1 tools/perf_profile.lua [--out FILE] [--compare FILE] [--verbose] [--quick]
-- --out writes "name value" lines; --compare prints them beside an earlier
-- file; --quick leaves out the scenarios that load the database (40 MB).
-- tests/run_perf_budget.lua runs the quick scenarios as a gate on the exact
-- numbers (allocation and calls), never on times.
package.path = "./tests/?.lua;" .. package.path

local P = {}
local args = { ... }
local asModule = args[1] == "module"
local outFile, compareFile, verbose, quick
do
    local i = 1
    while args[i] do
        if args[i] == "--out" then outFile, i = args[i + 1], i + 1
        elseif args[i] == "--compare" then compareFile, i = args[i + 1], i + 1
        elseif args[i] == "--verbose" then verbose = true
        elseif args[i] == "--quick" then quick = true end
        i = i + 1
    end
end

local clock = os.clock
local heapBefore = collectgarbage("count")
local M = require("wowmock")
collectgarbage("collect")
local heapMock = collectgarbage("count")

-- ---------------------------------------------------------------------------
-- Counting: game API calls (globals and C_ namespaces) and widget calls
-- ---------------------------------------------------------------------------
local apiCalls, widgetCalls = {}, {}
local apiTotal, widgetTotal = 0, 0
-- KB allocated inside the outermost fake API or widget call under way
local mockKB, inMock = 0, false
local kb = collectgarbage
local function Leave(k0, ...)
    mockKB = mockKB + (kb("count") - k0)
    inMock = false
    return ...
end
local LUA = { print = true, pairs = true, ipairs = true, type = true, tostring = true, tonumber = true,
    select = true, unpack = true, next = true, pcall = true, xpcall = true, error = true, assert = true,
    setmetatable = true, getmetatable = true, rawget = true, rawset = true, rawequal = true, require = true,
    loadstring = true, loadfile = true, dofile = true, load = true, collectgarbage = true, gcinfo = true,
    getfenv = true, setfenv = true, module = true, newproxy = true,
    -- not game work: object construction and plain helpers written in Lua
    CreateFrame = true, Mixin = true, CreateFromMixins = true, wipe = true, tinsert = true, tremove = true,
    strsplit = true, strtrim = true, format = true, CopyTable = true, hooksecurefunc = true,
    geterrorhandler = true, debugstack = true, issecretvalue = true, GetTime = true }
local function Counted(name, fn)
    return function(...)
        if inMock then return fn(...) end
        apiCalls[name] = (apiCalls[name] or 0) + 1
        apiTotal = apiTotal + 1
        inMock = true
        return Leave(kb("count"), fn(...))
    end
end
local function CountApis()
    for name, v in pairs(_G) do
        if type(name) == "string" and not LUA[name] then
            if type(v) == "function" then
                _G[name] = Counted(name, v)
            elseif type(v) == "table" and name:find("^C_") then
                for k, f in pairs(v) do
                    if type(f) == "function" then v[k] = Counted(name .. "." .. k, f) end
                end
            end
        end
    end
    -- widget methods that reach the game's renderer or layout
    local F = M.FrameMethods
    for name, fn in pairs(F) do
        if type(fn) == "function" and not M.TEST_HELPERS[name] and (name:find("^Set") or name:find("^Clear")
            or name == "Show" or name == "Hide" or name:find("^Get") or name:find("^Is")) then
            F[name] = function(...)
                -- one a widget method makes itself (SetShown showing) is not the addon's
                if inMock then return fn(...) end
                widgetCalls[name] = (widgetCalls[name] or 0) + 1
                widgetTotal = widgetTotal + 1
                inMock = true
                return Leave(kb("count"), fn(...))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The world: six real maps (so the shipped travel network applies) beside
-- the mock's own, a character who can ride nothing and knows every flight
-- ---------------------------------------------------------------------------
local MAPS = {
    { 1416, 0, 1500, 783.33331298828, 2799.99993896488, 1866.66665649414 },
    { 1424, 0, 400, 1066.6666259766, 3199.9998779297, 2133.3332519531 },
    { 1420, 0, 3837.4997558594, 3033.3332519531, 4518.7498779297, 3012.49981689456 },
    { 1458, 0, 1877.9453125, 873.19262695313, 959.37503051758, 640.1041259766 },
    { 1411, 1, 1808.3332519531, -1962.4998779297, 5287.4996337891, 3524.9998779297 },
    { 1454, 1, 2273.8771972656, -3680.6010742188, 1402.6044921874, 935.4166259765 },
}
local shippedMaps, useShipped = {}, false
for _, f in ipairs(MAPS) do
    shippedMaps[f[1]] = { mapID = f[1], name = "Map " .. f[1], cont = f[2], top = f[3], left = f[4], w = f[5], h = f[6],
        mapType = 3, parentMapID = f[2] == 0 and 13 or 12 }
end
function UnitFactionGroup() return "Horde" end
function UnitLevel() return 30 end
function GetUnitSpeed() return 7, 7, 7, 4.7 end
function GetServerTime() return math.floor(M.now) + 1700000000 end
function GetItemCount() return 0 end
-- The planner budgets its work in expansions when the clock gives nothing,
-- which keeps every run identical; the client has the function.
function debugprofilestop() return nil end
-- A live client build, as the game reports it (the mock has no build): the
-- terrain sampler's records apply on the surveyed build 70338 only.
function GetBuildInfo() return "1.60.1", "70862", "Nov 10 2026", 16001 end
local mockBestMap = C_Map.GetBestMapForUnit
C_Map.GetBestMapForUnit = function(...)
    if not useShipped then return mockBestMap(...) end
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
-- a quest log of twenty, three of them with spots on the map
M.quests = {}
for i = 1, 20 do
    M.quests[i] = { id = 100 + i, title = "Quest " .. i, objectives = { { text = "0/8 things", finished = false } },
        onMap = i <= 3 and { [37] = { 0.3 + i * 0.05, 0.6 } } or nil }
end

-- ---------------------------------------------------------------------------
-- Measuring
-- ---------------------------------------------------------------------------
local playerState = getmetatable(M.player).__index -- written directly: no clock skew
local labels = setmetatable({}, { __mode = "k" })
local function Label(fn)
    local l = labels[fn]
    if l then return l end
    local f = fn
    for _ = 1, 3 do
        local info = debug.getinfo(f, "S")
        local src = info.short_src or "?"
        if src:find("Core.lua", 1, true) then
            -- ns.Safe wrapper: the wrapped function says whose it is
            local inner
            for i = 1, 10 do
                local n, v = debug.getupvalue(f, i)
                if not n then break end
                if n == "fn" and type(v) == "function" then inner = v end
            end
            if not inner then break end
            f = inner
        else
            break
        end
    end
    local info = debug.getinfo(f, "S")
    l = (info.short_src or "?"):gsub("^.*/", ""):gsub("%.lua$", "")
    labels[fn] = l
    return l
end

local seg -- the segment being measured
local function NewSegment(name)
    return { name = name, frames = 0, seconds = 0, kb = 0, own = 0, time = 0, frameTimes = {}, by = {},
        api0 = apiTotal, widget0 = widgetTotal, apiBy0 = {}, widgetBy0 = {} }
end
local function Charge(label, all, own, t, api)
    local b = seg.by[label]
    if not b then b = { kb = 0, own = 0, time = 0, calls = 0, api = 0 }; seg.by[label] = b end
    b.kb, b.own, b.time, b.calls, b.api = b.kb + all, b.own + own, b.time + t, b.calls + 1, b.api + api
end
local count = collectgarbage
local function Run(label, fn, ...)
    inMock = false
    local k0, m0, a0, t0 = count("count"), mockKB, apiTotal, clock()
    fn(...)
    local t, all = clock() - t0, count("count") - k0
    if seg then
        local own = all - (mockKB - m0)
        Charge(label, all, own, t, apiTotal - a0)
        seg.kb, seg.own, seg.time = seg.kb + all, seg.own + own, seg.time + t
    end
    return t
end

local STEP = 1 / 60
local IsVisible = M.FrameMethods.IsVisible -- the uncounted one: this is the game asking, not the addon
local function Frame()
    M.now = M.now + STEP
    local spent = 0
    local timers = M.timers
    M.timers = {}
    for _, tm in ipairs(timers) do
        if tm.at <= M.now then
            spent = spent + Run("timer:" .. Label(tm.fn), tm.fn)
        else
            table.insert(M.timers, tm)
        end
    end
    local frames = M.frames
    for i = 1, #frames do
        local f = frames[i]
        local fn = f._scripts.OnUpdate
        if fn and IsVisible(f) then
            spent = spent + Run(Label(fn), fn, f, STEP)
        end
    end
    if seg then
        seg.frames = seg.frames + 1
        seg.frameTimes[seg.frames] = spent
    end
end
local function Fire(event, ...)
    for _, f in ipairs(M.eventFrames[event] or {}) do
        local fn = f._scripts.OnEvent
        if fn then Run("event:" .. event, fn, f, event, ...) end
    end
end

local results, order = {}, {}
local function Metric(name, value)
    if results[name] == nil then order[#order + 1] = name end
    results[name] = value
end
local function Heap()
    collectgarbage("collect"); collectgarbage("collect")
    return collectgarbage("count")
end

-- A run that takes longer than this many CPU seconds stops with an error
-- (a hung scenario must not hang the test suite).
local deadline
local function InTime()
    if deadline and clock() > deadline then
        error("perf profile: over its time limit", 0)
    end
end

-- Plays `seconds` of frames; each(frame index) runs before every frame.
local function Play(name, seconds, each)
    InTime()
    seg = NewSegment(name)
    for k, v in pairs(apiCalls) do seg.apiBy0[k] = v end
    for k, v in pairs(widgetCalls) do seg.widgetBy0[k] = v end
    local frames = math.floor(seconds / STEP + 0.5)
    collectgarbage("collect")
    collectgarbage("stop")
    for i = 1, frames do
        if each then each(i) end
        Frame()
        if i % 60 == 0 then
            -- empty the heap between seconds without counting the collection
            collectgarbage("collect"); collectgarbage("stop")
            InTime()
        end
    end
    collectgarbage("restart")
    local s = seg
    seg = nil
    s.seconds = frames * STEP
    table.sort(s.frameTimes)
    local n = #s.frameTimes
    Metric(name .. ".alloc_addon_kb_per_s", s.own / s.seconds)
    Metric(name .. ".alloc_total_kb_per_s", s.kb / s.seconds)
    Metric(name .. ".cpu_ms_per_frame_median", s.frameTimes[math.ceil(n / 2)] * 1000)
    Metric(name .. ".cpu_ms_per_frame_p99", s.frameTimes[math.ceil(n * 0.99)] * 1000)
    Metric(name .. ".cpu_ms_per_frame_worst", s.frameTimes[n] * 1000)
    Metric(name .. ".cpu_ms_per_s", s.time * 1000 / s.seconds)
    Metric(name .. ".api_calls_per_s", (apiTotal - s.api0) / s.seconds)
    Metric(name .. ".widget_calls_per_s", (widgetTotal - s.widget0) / s.seconds)
    Metric(name .. ".heap_after_kb", Heap())
    if verbose then
        print(("\n== %s: %.1f s, %d frames"):format(name, s.seconds, frames))
        local rows = {}
        for label, b in pairs(s.by) do rows[#rows + 1] = { label, b } end
        table.sort(rows, function(a, b) return a[2].time > b[2].time end)
        print(("  %-34s %10s %10s %10s %9s"):format("handler", "addon KB/s", "total KB/s", "ms/s", "calls/s"))
        for _, r in ipairs(rows) do
            print(("  %-34s %10.3f %10.3f %10.3f %9.1f"):format(r[1], r[2].own / s.seconds, r[2].kb / s.seconds,
                r[2].time * 1000 / s.seconds, r[2].calls / s.seconds))
        end
        local function Top(title, now, was)
            local list = {}
            for k, v in pairs(now) do
                local d = v - (was[k] or 0)
                if d > 0 then list[#list + 1] = { k, d } end
            end
            table.sort(list, function(a, b) return a[2] > b[2] end)
            local parts = {}
            for i = 1, math.min(12, #list) do
                parts[#parts + 1] = ("%s %.1f"):format(list[i][1], list[i][2] / s.seconds)
            end
            print("  " .. title .. " /s: " .. table.concat(parts, ", "))
        end
        Top("api", apiCalls, s.apiBy0)
        Top("widget", widgetCalls, s.widgetBy0)
    end
    return s
end

-- A burst: `event` fired `n` times within one second of frames.
local function Burst(name, event, n, ...)
    seg = NewSegment(name)
    collectgarbage("collect")
    collectgarbage("stop")
    for i = 1, n do
        Fire(event, ...)
        if i % 4 == 0 then Frame() end
    end
    -- what it left queued (delayed reads) lands within the next seconds
    for _ = 1, 240 do Frame() end
    collectgarbage("restart")
    local s = seg
    seg = nil
    local own, t, api = 0, 0, 0
    for label, b in pairs(s.by) do
        if label == "event:" .. event or label:find("^timer:") then
            own, t, api = own + b.own, t + b.time, api + b.api
        end
    end
    Metric(name .. ".alloc_addon_kb_per_event", own / n)
    Metric(name .. ".cpu_us_per_event", t * 1e6 / n)
    Metric(name .. ".api_calls_per_event", api / n)
    if verbose then
        print(("\n== %s: %d x %s: %.4f KB and %.2f us an event (with what it queued)"):format(name, n, event, own / n,
            t * 1e6 / n))
    end
end

-- ---------------------------------------------------------------------------
-- Scenarios
-- ---------------------------------------------------------------------------
local ns
local function Stand(m, x, y)
    local cont, wx, wy = ns.Geo.MapToWorld(m, x, y)
    playerState.inst, playerState.wx, playerState.wy = cont, wx, wy
end
-- walks towards a world point at `speed` yards a second, turning to face it
local function WalkTo(cont, wx, wy, speed)
    if cont ~= playerState.inst then return end
    local dx, dy = wx - playerState.wx, wy - playerState.wy
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1e-6 then return end
    local k = math.min(1, speed * STEP / d)
    playerState.wx, playerState.wy = playerState.wx + dx * k, playerState.wy + dy * k
    playerState.facing = math.atan2(dy, dx) % (2 * math.pi)
end
-- a slow circle, so position and facing change every frame
local function Circle(i)
    local a = i * STEP * 0.35
    playerState.wx, playerState.wy = playerState.wx + math.cos(a) * 7 * STEP, playerState.wy + math.sin(a) * 7 * STEP
    playerState.facing = a % (2 * math.pi)
end

-- opts.quick: without the scenarios that load the database;
-- opts.seconds: the CPU time allowed (an error after it)
function P.Run(opts)
    opts = opts or {}
    deadline = opts.seconds and clock() + opts.seconds or nil
    CountApis()
    collectgarbage("collect")
    local h0, t0 = collectgarbage("count"), clock()
    ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
    local loadTime = clock() - t0
    Metric("load.files_ms", loadTime * 1000)
    Metric("load.heap_files_kb", Heap() - h0)
    t0 = clock()
    M.FireEvent("ADDON_LOADED", "WaypointTracker")
    M.FireEvent("PLAYER_LOGIN")
    M.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    Metric("load.login_ms", (clock() - t0) * 1000)
    Metric("load.heap_login_kb", Heap() - h0)
    for id, m in pairs(shippedMaps) do M.maps[id] = m end
    local WP, T = ns.WP, ns.Travel
    ns.Set("chatMessages", false)

    -- the first half minute: delayed start-up work (title scan, first reads)
    Play("login30s", 30)
    Metric("load.heap_after_30s_kb", Heap() - h0)

    -- 1. nothing to do: no waypoint, standing still
    Play("idle", 30)
    -- 2. no waypoint, walking around
    Play("idle_moving", 30, Circle)

    -- 3. one waypoint in the zone, walking to it (plain arrow)
    Stand(37, 0.40, 0.30)
    local wp = WP.Add(37, 0.62, 0.55, { title = "Perf target" })
    local cont, wx, wy = ns.Geo.MapToWorld(37, 0.62, 0.55)
    Play("waypoint_walk", 30, function() WalkTo(cont, wx, wy, 7) end)
    Metric("waypoint_walk.heap_delta_kb", results["waypoint_walk.heap_after_kb"] - results["idle_moving.heap_after_kb"])
    -- 4. the same, standing still facing one way (nothing on screen changes)
    Play("waypoint_still", 20)
    -- 5. the same with the arrow turned off
    ns.Set("arrowShown", false)
    Play("waypoint_arrow_hidden", 20, function() WalkTo(cont, wx, wy, 7) end)
    ns.Set("arrowShown", true)

    -- 6. ten waypoints, minimap pins, the coordinates box, walking
    WP.ClearAll(true)
    Stand(37, 0.40, 0.30)
    for i = 1, 10 do WP.Add(37, 0.30 + i * 0.03, 0.35 + (i % 3) * 0.05, { title = "Stop " .. i }) end
    ns.Set("coordsBox", true)
    Play("ten_waypoints", 30, Circle)
    ns.Set("coordsBox", false)

    -- 7. the world map open over them
    WorldMapFrame:Show()
    Play("worldmap_open", 15, Circle)
    WorldMapFrame:Hide()

    -- 8. the window open on the Waypoints tab
    WaypointTracker_ToggleWindow()
    Play("window_open", 15, Circle)
    WaypointTracker_ToggleWindow()
    WP.ClearAll(true)

    -- 9. Real routes on the shipped network: a walk through two zones
    useShipped = true
    T._Reset()
    T._SetSliced(true)
    local d = T.Data()
    for id in pairs(d.byTaxi) do T.Know().flights[id] = true end
    ns.Set("travelHearth", false)
    Stand(1424, 0.615, 0.209)
    wp = WP.Add(1416, 0.231, 0.604, { title = "Across the border" })
    Play("real_route_walk", 40, function()
        local p = T.Current()
        local e = p and p.target
        if e then
            local how = e.via
            if not (type(how) == "table" and (how.kind or (how.method ~= "walk" and how.method ~= "gate"
                and how.method ~= "lift"))) then
                local tc, tx, ty = T.Pos(e.node)
                WalkTo(tc, tx, ty, 7)
            end
        end
    end)
    Metric("real_route_walk.heap_delta_kb", results["real_route_walk.heap_after_kb"] - results["window_open.heap_after_kb"])
    WP.ClearAll(true)
    Play("real_route_after_clear", 10)
    useShipped = false
    Stand(37, 0.40, 0.30)

    -- 10. Treasure hunt (beta) on, walking (it loads the database)
    if not opts.quick then
        ns.Set("treasureHunt", true)
        Play("treasure_on", 20, Circle)
        ns.Set("treasureHunt", false)
    end

    -- 11. event bursts
    M.units.mouseover = { guid = "Creature-0-1-0-0-4242-0000000001", name = "Perf Wolf", reaction = 2, level = 10 }
    M.units.target = M.units.mouseover
    M.units.nameplate1 = M.units.mouseover
    Burst("ev_quest_log_update", "QUEST_LOG_UPDATE", 200)
    Burst("ev_mouseover", "UPDATE_MOUSEOVER_UNIT", 200)
    Burst("ev_target", "PLAYER_TARGET_CHANGED", 200)
    Burst("ev_nameplate", "NAME_PLATE_UNIT_ADDED", 200, "nameplate1")
    Burst("ev_spellcast", "UNIT_SPELLCAST_SUCCEEDED", 200, "player", "Cast-0", 133)
    Burst("ev_bag_cooldown", "BAG_UPDATE_COOLDOWN", 200)
    Burst("ev_spell_cooldown", "SPELL_UPDATE_COOLDOWN", 200)
    Burst("ev_chat_addon_other", "CHAT_MSG_ADDON", 200, "OtherAddon", "payload", "GUILD", "Someone-Realm")
    Burst("ev_vignettes", "VIGNETTES_UPDATED", 200)
    Burst("ev_item_info", "GET_ITEM_INFO_RECEIVED", 200, 6948, true)
    M.units = {}

    if opts.quick then
        Play("idle_after_all", 20)
        Metric("final.heap_kb", Heap() - h0)
        return results, order
    end

    -- 12. the database: loading it, and a search
    local before = Heap()
    t0 = clock()
    ns.DB.Load()
    Metric("database.load_ms", (clock() - t0) * 1000)
    Metric("database.heap_kb", Heap() - before)
    t0 = clock()
    ns.Find.Show("wolf")
    for _ = 1, 60 do Frame() end
    Metric("find.search_ms", (clock() - t0) * 1000)
    Play("find_open", 10, Circle)
    Metric("find.heap_kb", Heap() - before)
    ns.Window.Hide()
    Play("idle_after_all", 20)
    Metric("final.heap_kb", Heap() - h0)
    return results, order
end

function P.Read(path)
    local out = {}
    local f = io.open(path)
    if not f then return nil end
    for line in f:lines() do
        local k, v = line:match("^(%S+)%s+(%S+)$")
        if k then out[k] = tonumber(v) end
    end
    f:close()
    return out
end

P.mock = M
if asModule then
    return P
end

local res, names = P.Run({ quick = quick })
local old = compareFile and assert(P.Read(compareFile), "cannot read " .. compareFile)
print(("\nheap of the mock alone: %.0f KB (not counted below; interpreter start %.0f KB)"):format(heapMock, heapBefore))
if old then
    print(("%-46s %12s %12s %9s"):format("metric", "before", "after", "change"))
else
    print(("%-46s %12s"):format("metric", "value"))
end
for _, name in ipairs(names) do
    local v = res[name]
    if old and old[name] then
        local was = old[name]
        local change = was ~= 0 and ("%+.0f%%"):format((v - was) / was * 100) or (v == 0 and "=" or "new")
        print(("%-46s %12.3f %12.3f %9s"):format(name, was, v, change))
    else
        print(("%-46s %12.3f"):format(name, v))
    end
end
if outFile then
    local f = assert(io.open(outFile, "w"))
    for _, name in ipairs(names) do f:write(("%s %.6f\n"):format(name, res[name])) end
    f:close()
end
if #M.errors > 0 then
    print("\nerrors reported while profiling:")
    for _, e in ipairs(M.errors) do print("  " .. tostring(e)) end
    os.exit(1)
end
