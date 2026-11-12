-- Trails: how often Trails.Steer searches the walked squares, and the
-- walked-path sharing queue. Run from the repository root with Lua 5.1:
--     lua5.1 tests/run_trails_search.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local speed = 7
function GetUnitSpeed() return speed, 7, 7, 4.7 end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end

WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local Trails, Travel = ns.Trails, ns.Travel
local Key, Enc = Trails._Key, Trails.Enc
check(ns.Get("realRoutes") and ns.Get("travelTrails") and not ns.Get("travelShare"),
    "defaults: Real routes and trails on, walked-path sharing off")
Travel.Data()

-- Count the path searches Steer runs (its FindPath upvalue).
local searches = 0
do
    local i = 1
    while true do
        local name, fn = debug.getupvalue(Trails.Steer, i)
        if not name then break end
        if name == "FindPath" then
            debug.setupvalue(Trails.Steer, i, function(...)
                searches = searches + 1
                return fn(...)
            end)
            break
        end
        i = i + 1
    end
end

local CELL = 20
local st = Trails.Store()
local function Fresh()
    st = Trails.Store()
    st.own, st.shared, st.pending = {}, {}, {}
    st.own[0] = {}
end
-- a dense walked block: every square linked to all eight around it
local function Block(x0, x1, y0, y1)
    for x = x0, x1 do
        for y = y0, y1 do
            st.own[0][Key(x, y)] = 255
        end
    end
end
local function Corridor(x, y0, y1)
    for y = y0, y1 do
        local bits = 0
        if y > y0 then bits = bits + 64 end -- (0,-1)
        if y < y1 then bits = bits + 4 end -- (0,1)
        st.own[0][Key(x, y)] = bits
    end
end
local function Center(cx, cy) return { cont = 0, wx = (cx + .5) * CELL, wy = (cy + .5) * CELL } end

-- Walk `yards` along y from `from`, `step` yards at a time at walking
-- speed, steering for `target` each step; `each(here)` runs before Steer.
local function Walk(from, yards, step, target, each)
    local here = { cont = 0, wx = from.wx, wy = from.wy }
    local bearing
    for _ = 0, yards / step do
        if each then each(here) end
        bearing = Trails.Steer(here, target)
        here = { cont = 0, wx = here.wx, wy = here.wy + step }
        M.now = M.now + step / speed
    end
    return bearing, here
end

-- ---------------------------------------------------------------------------
-- 1. Walked ground, no way to the goal: one search per NO_PATH_AGAIN
-- ---------------------------------------------------------------------------
Fresh()
Block(0, 9, 0, 29) -- 200 x 600 yards
Block(200, 205, 0, 5) -- the goal's block, cut off
local goal = Center(202, 2)
M.now = M.now + 100
searches = 0
local start = M.now
local bearing = Walk(Center(5, 0), 400, 5, goal)
local walked = M.now - start
check(bearing == nil, "no walked way: no bearing")
-- unfixed code: one search per 20-yard square (21 here)
check(searches >= 1 and searches <= math.ceil(walked / 10) + 1,
    ("walking 400 yd with no way: searches at most every 10 s (%d searches in %.0f s)"):format(searches, walked))

-- ---------------------------------------------------------------------------
-- 2. New ground recorded as you walk, next to a block with no way to the goal
-- ---------------------------------------------------------------------------
-- Elwynn Forest in the mock: world x = -2000 * map y, world y = -3000 * map x.
Fresh()
Block(-60, -41, -45, -36)
Block(-60, -41, -14, -5) -- the goal's block, across a one-square gap from the walk's end
local goal2 = Center(-60, -5)
local function Record(here)
    M.player.inst, M.player.wx, M.player.wy = 0, here.wx, here.wy
    Trails._Record()
end
M.now = M.now + 100
searches = 0
start = M.now
local before = 0
for _, g in pairs(st.own) do for _ in pairs(g) do before = before + 1 end end
local _, here = Walk(Center(-50, -36), 400, 5, goal2, Record)
walked = M.now - start
local after = 0
for _, g in pairs(st.own) do for _ in pairs(g) do after = after + 1 end end
check(after >= before + 19, "the walk wrote down new squares (" .. (after - before) .. ")")
check(searches >= 1 and searches <= math.ceil(walked / 10) + 1,
    ("new ground that only adds dead ends: searches at most every 10 s (%d in %.0f s)"):format(searches, walked))
check(Trails.Steer(here, goal2) == nil, "still no way to the goal")

-- 2b. squares from two other players bridge the gap: the next search finds the way
ns.Set("travelShare", true)
local tp = ("TP^0^%s%s%s%s"):format(Enc(Key(-50, -16), 4), Enc(2, 1), Enc(Key(-50, -15), 4), Enc(2, 1))
ns.RoutesNet.OnMessage("WPTR", tp, "CHANNEL", "Other-Realm")
ns.RoutesNet.OnMessage("WPTR", tp, "CHANNEL", "Third-Realm")
local _, sharedSquares = Trails.Stats()
check(sharedSquares >= 2, "two players' squares are taken (" .. sharedSquares .. ")")
ns.Set("travelShare", false)
local beside = { cont = 0, wx = (-50 + .5) * CELL, wy = (-16 + .5) * CELL }
M.now = M.now + 0.6
searches = 0
bearing = Trails.Steer(beside, goal2)
check(searches == 1 and bearing ~= nil, "squares received since the failed search: searched again, way found ("
    .. searches .. ", " .. tostring(bearing) .. ")")

-- 2c. a square you walk that joins two walked places makes the next call search
Fresh()
Block(-60, -41, -45, -36)
Block(-60, -41, -14, -5)
M.now = M.now + 100
local path0 = { cont = 0, wx = (-50 + .5) * CELL, wy = (-36 + .5) * CELL }
Walk(path0, 400, 5, goal2, Record) -- up to square -16, as above
local gap = { cont = 0, wx = (-50 + .5) * CELL, wy = (-15 + .5) * CELL }
M.now = M.now + 1
Record(gap) -- a dead end: no new search
M.now = M.now + 0.6
searches = 0
check(Trails.Steer(gap, goal2) == nil and searches == 0, "a dead-end square alone: no new search (" .. searches .. ")")
local into = { cont = 0, wx = (-50 + .5) * CELL, wy = (-14 + .5) * CELL }
M.now = M.now + 1
Record(into) -- joins the gap square to the goal's block
M.now = M.now + 0.6
searches = 0
bearing = Trails.Steer(gap, goal2)
check(searches == 1 and bearing ~= nil, "a recorded step joining walked places: searched again, way found ("
    .. searches .. ", " .. tostring(bearing) .. ")")

-- 2d. a failed search, nothing changed: standing still, no new search
Fresh()
Block(0, 9, 0, 29)
Block(200, 205, 0, 5)
M.now = M.now + 100
local near = Center(5, 10)
Trails.Steer(near, goal)
M.now = M.now + 0.6
searches = 0
Trails.Steer(near, goal)
check(searches == 0, "failed, nothing changed: no new search")

-- ---------------------------------------------------------------------------
-- 3. A way exists: the search cadence is what it was
-- ---------------------------------------------------------------------------
-- (counts measured on the unfixed Trails.lua: on the path 1, beside it 21)
Fresh()
Corridor(0, 0, 60)
local far = Center(0, 60)
M.now = M.now + 100
searches = 0
bearing = Walk(Center(0, 0), 400, 5, far)
check(bearing ~= nil and searches == 1, "on a walked way: one search for the whole walk (" .. searches .. ")")
M.now = M.now + 100
searches = 0
-- 45 yards beside it: too far to follow (Steer re-searches as before)
local side = { cont = 0, wx = Center(0, 0).wx + 45, wy = Center(0, 0).wy }
Walk(side, 400, 5, far)
check(searches == 21, "beside a walked way: the same searches as before (" .. searches .. ")")

-- ---------------------------------------------------------------------------
-- 4. Walked-path sharing off: nothing is queued or built for it
-- ---------------------------------------------------------------------------
Fresh()
local shares = 0
local realShare = Trails.Share
Trails.Share = function(msg)
    shares = shares + 1
    return realShare(msg)
end
local fresh = Trails._fresh
local function WalkTicking(seconds, x0, y0)
    -- walk east in Elwynn (world y falls), half a second a tick
    for i = 1, seconds * 2 do
        M.player.inst, M.player.wx, M.player.wy = 0, x0, y0 - i * 3.5
        M.Tick(0.5, 0.5)
    end
end
check(not ns.Get("travelShare"), "sharing is off")
local own0 = Trails.Stats()
WalkTicking(60, -1000, -300)
local own1 = Trails.Stats()
check(own1 > own0 + 5, "with sharing off the walk is still written down (" .. (own1 - own0) .. " squares)")
check(#fresh == 0, "with sharing off nothing waits to be shared (" .. #fresh .. ")")
check(shares == 0, "with sharing off no share payloads are built (" .. shares .. ")")
-- turning it on: what is walked from then on is queued, nothing from before
ns.Set("travelShare", true)
WalkTicking(30, -1100, -300)
local queued = #fresh
check(queued > 5, "with sharing on, steps walked are queued (" .. queued .. ")")
local onlyNew = true
for _, s in ipairs(fresh) do
    if s[2] * CELL > -1050 then onlyNew = false end
end
check(onlyNew, "only steps walked after turning sharing on are queued")
-- and are sent once old enough (SHARE_AFTER), as before
local sent = {}
Trails.Share = function(msg)
    shares = shares + 1
    sent[#sent + 1] = msg
    return true
end
M.Tick(620, 0.5)
local tp0 = false
for _, msg in ipairs(sent) do
    if msg:sub(1, 5) == "TP^0^" then tp0 = true end
end
check(tp0 and #fresh < queued, "queued steps are shared after ten minutes (" .. #sent .. " messages, " .. #fresh .. " left)")
-- turning it off again drops what still waits
WalkTicking(10, -1200, -300)
check(#fresh > 0, "steps walked while sharing queue")
ns.Set("travelShare", false)
M.Tick(21, 0.5)
check(#fresh == 0, "turning sharing off drops the queue")
Trails.Share = realShare

-- ---------------------------------------------------------------------------
-- 5. Walking on a map the travel data has no row for (Darkspear Islands,
--    the battlegrounds) doesn't fill the world-position cache: the area
--    lookup of the player's live position climbs to the parent map uncached
-- ---------------------------------------------------------------------------
local Geo, d5 = ns.Geo, Travel.Data()
check(d5 and d5.mapArea[2524] == nil and d5.regions[2524] == nil, "map 2524 has no row in the travel data")
-- Darkspear Islands as in the client's UiMap table: an orphan map under Kalimdor
M.maps[2524] = { mapID = 2524, name = "Darkspear Islands", mapType = 6, parentMapID = 12, cont = 1,
    top = -6000, left = -6000, w = 2000, h = 2000 }
local realBest = C_Map.GetBestMapForUnit
C_Map.GetBestMapForUnit = function() return 2524 end
M.player.inst = 1
-- one first sample: the parent map's fixed reference point is cached once
M.player.wx, M.player.wy = -6500, -6500
M.Tick(0.5, 0.5)
local cache0 = Geo._WorldCacheSize()
local recorded0 = Trails.Stats()
for i = 1, 600 do -- five minutes of walking, half a second a tick
    M.player.wx, M.player.wy = -6500 + i * 1.5, -6500 - i * 2.5
    M.Tick(0.5, 0.5)
end
check(Trails.Stats() > recorded0, "the walk on map 2524 is written down (" .. (Trails.Stats() - recorded0) .. " squares)")
check(Geo._WorldCacheSize() == cache0, ("600 walking samples on map 2524 leave the world-position cache as it was (%d -> %d)")
    :format(cache0, Geo._WorldCacheSize()))
C_Map.GetBestMapForUnit = realBest
M.maps[2524] = nil
M.player.inst = 0

check(#M.errors == 0, "no reported Lua errors: " .. tostring(M.errors[1]))
print(("Trails search: %d passed, %d failed"):format(passed, failed))
os.exit((failed == 0 and #M.errors == 0) and 0 or 1)
