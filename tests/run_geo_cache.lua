-- Geo.MapToWorld cache bounds and Geo.MapToWorldLive, against the fake WoW
-- API. Run from the repository root with Lua 5.1; WT_PLAIN_VECTORS=1 too.
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

local plain = os.getenv("WT_PLAIN_VECTORS") == "1"

local function load()
    local ns = {}
    assert(loadfile("WaypointTracker/Locales/enUS.lua"))("WaypointTracker", ns)
    assert(loadfile("WaypointTracker/Core.lua"))("WaypointTracker", ns)
    assert(loadfile("WaypointTracker/Geo.lua"))("WaypointTracker", ns)
    return ns.Geo
end

local function same(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local POINTS = {
    { 37, 0.5, 0.5 }, { 37, 0.0, 0.0 }, { 37, 1.0, 1.0 }, { 37, 0.41, 0.61 },
    { 37, 0.123456, 0.654321 }, { 37, -0.25, 1.5 }, { 52, 0.3, 0.7 }, { 1, 0.9, 0.1 },
    { 18, 0.55, 0.45 }, { 291, 0.2, 0.8 }, { 13, 0.5, 0.5 }, { 947, 0.5, 0.5 },
    { 7777, 0.5, 0.5 }, { 424242, 0.5, 0.5 },
}

-- Live and cached answers agree, for maps with and without world positions.
local function agreement(Geo, label)
    for _, p in ipairs(POINTS) do
        local live = { Geo.MapToWorldLive(p[1], p[2], p[3]) }
        local cached = { Geo.MapToWorld(p[1], p[2], p[3]) }
        local again = { Geo.MapToWorld(p[1], p[2], p[3]) }
        check(same(live, cached) and same(cached, again) and select("#", unpack(live)) == select("#", unpack(cached)),
            label .. ": live equals cached at " .. table.concat(p, ","))
    end
    local c, x, y = Geo.MapToWorldLive(37, 0.5, 0.5)
    check(c ~= nil and type(x) == "number" and type(y) == "number", label .. ": live answers a valid zone")
    check(Geo.MapToWorldLive(424242, 0.5, 0.5) == nil and Geo.MapToWorldLive(947, 0.5, 0.5) == nil, label .. ": live has no answer for a map without world position")
end

-- Invalid input gives nil for both, without asking the game or caching.
local function invalid(Geo, label)
    local before = Geo._WorldCacheSize()
    local calls = 0
    local real = C_Map.GetWorldPosFromMapPos
    C_Map.GetWorldPosFromMapPos = function(...) calls = calls + 1; return real(...) end
    local bad = { { nil, 0.5, 0.5 }, { "37", 0.5, 0.5 }, { 37, "0.5", 0.5 }, { 37, 0.5, nil }, { 37, {}, 0.5 } }
    for i, b in ipairs(bad) do
        local n1 = select("#", Geo.MapToWorld(b[1], b[2], b[3]))
        local n2 = select("#", Geo.MapToWorldLive(b[1], b[2], b[3]))
        check(Geo.MapToWorld(b[1], b[2], b[3]) == nil and Geo.MapToWorldLive(b[1], b[2], b[3]) == nil
            and n1 == 1 and n2 == 1, label .. ": invalid input " .. i .. " returns nil")
    end
    check(calls == 0, label .. ": invalid input never asks the game")
    check(Geo._WorldCacheSize() == before, label .. ": invalid input is not cached")
    -- the game throwing: nil, as before
    C_Map.GetWorldPosFromMapPos = function() error("boom") end
    check(Geo.MapToWorld(37, 0.3131, 0.3131) == nil and Geo.MapToWorldLive(37, 0.3131, 0.3131) == nil,
        label .. ": an error from the game gives nil")
    C_Map.GetWorldPosFromMapPos = real
end

local function suite(label)
    local Geo = load()
    check(type(Geo.MapToWorldLive) == "function" and type(Geo._WorldCacheSize) == "function",
        label .. ": live variant and cache-size hook exist")
    if type(Geo.MapToWorldLive) ~= "function" or type(Geo._WorldCacheSize) ~= "function" then
        return
    end
    agreement(Geo, label)
    invalid(Geo, label)

    -- 10,000 distinct live positions leave the cache alone
    local size = Geo._WorldCacheSize()
    for i = 1, 10000 do
        local c = Geo.MapToWorldLive(37, 0.1 + i / 20000, 0.2 + i / 30000)
        if not c then
            check(false, label .. ": live position " .. i .. " answered")
            break
        end
    end
    check(Geo._WorldCacheSize() == size, label .. ": 10,000 live positions add nothing to the cache (size "
        .. tostring(Geo._WorldCacheSize()) .. " vs " .. tostring(size) .. ")")

    -- the cache is bounded: past the cap it starts again, answers stay right
    local maxSeen, wiped, last = 0, false, Geo._WorldCacheSize()
    for i = 1, 25000 do
        Geo.MapToWorld(37, i / 25000, 0.5)
        local n = Geo._WorldCacheSize()
        if n < last then wiped = true end
        if n > maxSeen then maxSeen = n end
        last = n
    end
    check(wiped, label .. ": cache started again past the cap")
    check(maxSeen <= 20000, label .. ": cache never holds more than 20000 entries (max " .. maxSeen .. ")")
    -- negative answers count too
    local start = Geo._WorldCacheSize()
    for i = 1, 100 do Geo.MapToWorld(424242, i / 1000, 0.5) end
    check(Geo._WorldCacheSize() == start + 100 or Geo._WorldCacheSize() < start,
        label .. ": cached misses are counted")
    for i = 1, 25000 do Geo.MapToWorld(424242, i / 25000, 0.25) end
    check(Geo._WorldCacheSize() <= 20000, label .. ": misses alone are bounded too")
    agreement(Geo, label .. " after wipe")

    -- the reusable point: used when the game's point has SetXY
    local v = CreateVector2D(0, 0)
    check(not (type(v) == "table" and v.SetXY), label .. ": the mock's point has no SetXY by default")
end

suite(plain and "plain vectors" or "Vector2D")

-- With a refillable point (the real client's Vector2DMixin has SetXY), the
-- live variant reuses one point and still agrees with the cache.
if not plain then
    local mt = getmetatable(CreateVector2D(0, 0))
    local created = 0
    local realCreate = CreateVector2D
    mt.SetXY = function(self, x, y) self.x, self.y = x, y end
    CreateVector2D = function(x, y) created = created + 1; return realCreate(x, y) end
    local Geo = load()
    local seen = {}
    local realWorld = C_Map.GetWorldPosFromMapPos
    C_Map.GetWorldPosFromMapPos = function(id, vec)
        seen[vec] = true
        return realWorld(id, vec)
    end
    agreement(Geo, "SetXY vectors")
    C_Map.GetWorldPosFromMapPos = function(id, vec)
        seen[vec] = true
        return realWorld(id, vec)
    end
    seen = {}
    for i = 1, 50 do Geo.MapToWorldLive(37, i / 50, 0.5) end
    local distinct = 0
    for _ in pairs(seen) do distinct = distinct + 1 end
    check(distinct == 1, "SetXY vectors: live lookups reuse one point (" .. distinct .. ")")
    C_Map.GetWorldPosFromMapPos = realWorld
    mt.SetXY = nil
    CreateVector2D = realCreate
end

-- Translating a live position (Geo.TranslateToMap / Geo.ProjectToMap with
-- `live`) gives the cached path's answers and keeps nothing in the cache.
do
    local Geo = load()
    local fresh = load() -- a cache that has never seen these points
    local pairs_ = { { 5001, 0.2, 0.7, 18 }, { 5001, 0.9, 0.1, 13 }, { 37, 0.41, 0.61, 13 }, { 37, 0.5, 0.5, 52 },
        { 52, 0.3, 0.7, 13 }, { 18, 0.3, 0.3, 2070 }, { 291, 0.5, 0.5, 52 }, { 7777, 0.5, 0.5, 13 } }
    for _, p in ipairs(pairs_) do
        local live = { Geo.TranslateToMap(p[1], p[2], p[3], p[4], true) }
        local cached = { fresh.TranslateToMap(p[1], p[2], p[3], p[4]) }
        check(live[1] == cached[1] and live[2] == cached[2] and #live == #cached,
            "live translation equals the cached one at " .. table.concat(p, ","))
        for _, to in ipairs({ p[4], 947, 13 }) do
            local lp = { Geo.ProjectToMap(p[1], p[2], p[3], to, true) }
            local cp = { fresh.ProjectToMap(p[1], p[2], p[3], to) }
            check(lp[1] == cp[1] and lp[2] == cp[2] and #lp == #cp,
                "live projection equals the cached one at " .. table.concat(p, ",") .. ">" .. to)
        end
    end
    -- the target maps' own fixed points may be cached once; moving points never
    for i = 1, 100 do Geo.ProjectToMap(5001, i / 200, 0.5, 947, true); Geo.TranslateToMap(5001, i / 200, 0.5, 18, true) end
    local size = Geo._WorldCacheSize()
    for i = 1, 10000 do
        Geo.ProjectToMap(5001, 0.1 + i / 20000, 0.2 + i / 30000, 947, true)
        Geo.ProjectToMap(5001, 0.1 + i / 20000, 0.2 + i / 30000, 13, true)
        Geo.TranslateToMap(5001, 0.1 + i / 20000, 0.2 + i / 30000, 18, true)
    end
    check(Geo._WorldCacheSize() == size, "10,000 live translations/projections add nothing to the cache (size "
        .. Geo._WorldCacheSize() .. " vs " .. size .. ")")
end

-- Steering through the real modules: 10,000 frames, 10,000 distinct player
-- positions on a small map inside a zone (its area comes from the zone's,
-- Travel.AreaAt translating the position), a waypoint in another zone. The
-- cache holds what it held after the first 100 frames.
do
    local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
    M.FireEvent("ADDON_LOADED", "WaypointTracker"); M.FireEvent("PLAYER_LOGIN")
    local T, G, WP = ns.Travel, ns.Geo, ns.WP
    local function row(id, kind, area, m, x, y)
        local cont, wx, wy = G.MapToWorld(m, x, y)
        return table.concat({ id, kind, area, cont, wx, wy, m, x * 100, y * 100, "", "", "", "" }, "\t")
    end
    ns.TravelData = { areas = { "tirisfal", "elwynn" }, indoor = {},
        nodes = row("B_TE", "border", 1, 18, .5, .99) .. "\n" .. row("B_ET", "border", 2, 37, .5, .01),
        links = "B_TE\tB_ET\twalk\t0\t\t\t\t\t\t\t", maps = "18\t1\n37\t2", regions = "", cities = "",
        towns = "", teleports = "", factors = "", levels = "" }
    T._Reset(); T.Data()
    ns.Set("realRoutes", true); ns.Set("travelTrails", false); ns.Set("travelHearth", false)
    local realBest = C_Map.GetBestMapForUnit
    C_Map.GetBestMapForUnit = function() return 5001 end -- Deathknell, inside Tirisfal (18)
    WP.ClearAll(true)
    local w = WP.Add(37, .5, .5, { title = "Elwynn" })
    WP.SetActive(w, true)
    local cont, wx, wy = G.MapToWorld(5001, .1, .5)
    M.player.inst, M.player.wx, M.player.wy = cont, wx, wy
    local after100, planned, distinct, lastX = nil, 0, 0, nil
    for f = 1, 10000 do
        M.now = M.now + 1 / 60
        M.player.wy = wy - f * 0.04 -- 0.04 yd west a frame: 400 yd across Deathknell
        T.Steer(w)
        local p = T.Current()
        if p and #p.path >= 3 then planned = planned + 1 end
        local _, x = G.GetPlayerMapPosition()
        if x ~= lastX then distinct, lastX = distinct + 1, x end
        if f == 100 then after100 = G._WorldCacheSize() end
    end
    check(distinct == 10000, "the player stood at 10,000 distinct positions (" .. distinct .. ")")
    check(planned >= 9900, "a multi-stop route was followed while moving (" .. planned .. " frames)")
    check(G._WorldCacheSize() == after100, "steering 10,000 frames keeps the cache as it was after 100 frames ("
        .. G._WorldCacheSize() .. " vs " .. tostring(after100) .. ")")
    check(#M.errors == 0, "steering: no errors " .. tostring(M.errors[1]))
    C_Map.GetBestMapForUnit = realBest
end

print(("run_geo_cache: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
    os.exit(1)
end
