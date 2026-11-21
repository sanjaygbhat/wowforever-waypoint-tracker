-- Where the player stands, as Travel.Steer reads it every frame: one table
-- written over as they move (Travel._LivePlace), which nothing may keep.
-- Whatever keeps the player's place (a planning job, a route re-anchored
-- there, the last job's place) holds a table of its own, made once and never
-- changed, so "the very same table" still means "hasn't moved since".
-- Checked while walking a route through two zones, planning spread over
-- frames and all at once: after every few frames nothing reachable from the
-- addon holds the live table; kept places don't move with the player; and
-- steering while walking makes no table per frame.
-- Run from the repository root: lua5.1 tests/run_travel_place.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end

local MAPS = {
    { 1416, 0, 1500, 783.33331298828, 2799.99993896488, 1866.66665649414 },
    { 1424, 0, 400, 1066.6666259766, 3199.9998779297, 2133.3332519531 },
}
local shippedMaps = {}
for _, f in ipairs(MAPS) do
    shippedMaps[f[1]] = { mapID = f[1], name = "Map " .. f[1], cont = f[2], top = f[3], left = f[4], w = f[5], h = f[6],
        mapType = 3, parentMapID = 13 }
end
function UnitFactionGroup() return "Horde" end
function UnitLevel() return 30 end
function GetUnitSpeed() return 7, 7, 7, 4.7 end
function GetServerTime() return math.floor(M.now) + 1700000000 end
function GetItemCount() return 0 end
-- no clock: planning spread over frames works by expansion count (repeatable)
function debugprofilestop() return nil end
C_Map.GetBestMapForUnit = function()
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

local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
for id, m in pairs(shippedMaps) do M.maps[id] = m end
local T, WP, G = ns.Travel, ns.WP, ns.Geo
local live = T._LivePlace
check(type(live) == "table", "Travel exposes the live place for this test")
local player = getmetatable(M.player).__index -- written directly: no clock skew
local STEP = 1 / 60

local function upvalue(fn, name)
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if not n then return nil end
        if n == name then return v end
    end
end

-- the player's place when the last answered job began (Replan's and Finish's)
local function JobPlace()
    return upvalue(upvalue(T.Steer, "Replan"), "jobPlace")
end

-- Everything reachable from the addon's namespace (tables, and functions'
-- upvalues) that holds the live place, other than the upvalue it lives in
-- and the test hook.
local function Holders()
    local seen, found, names = {}, {}, { "ns" }
    local function note(name)
        found[#found + 1] = table.concat(names, ".") .. "." .. name
    end
    local visit
    local function child(v, name)
        local t = type(v)
        if (t == "table" or t == "function") and not seen[v] then
            names[#names + 1] = name
            visit(v)
            names[#names] = nil
        end
    end
    visit = function(v)
        seen[v] = true
        if type(v) == "table" then
            for k, x in next, v do
                if x == live then
                    if not (v == T and k == "_LivePlace") then note(tostring(k)) end
                else
                    child(x, tostring(k))
                end
                if k == live then note("(as a key)") else child(k, "(key)") end
            end
        else
            for i = 1, 255 do
                local n, x = debug.getupvalue(v, i)
                if not n then break end
                if x == live then
                    if n ~= "livePlace" then note("^" .. n) end
                else
                    child(x, "^" .. n)
                end
            end
        end
    end
    visit(ns)
    return found
end

-- the scan sees a kept table (so an empty answer means something)
ns._probe = { deep = { live } }
local probe = Holders()
check(#probe == 1 and probe[1]:find("_probe", 1, true), "(control) the scan finds the live place when something keeps it")
ns._probe = nil
check(#Holders() == 0, "before any steering nothing holds the live place")

local function Stand(m, x, y)
    local cont, wx, wy = G.MapToWorld(m, x, y)
    player.inst, player.wx, player.wy = cont, wx, wy
end
local function Follow(yards)
    local p = T.Current()
    local e = p and p.target
    if not e then return end
    local how = e.via
    if type(how) == "table" and (how.kind or (how.method ~= "walk" and how.method ~= "gate" and how.method ~= "lift")) then
        return
    end
    local tc, tx, ty = T.Pos(e.node)
    if tc ~= player.inst then return end
    local dx, dy = tx - player.wx, ty - player.wy
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1e-6 then return end
    local k = math.min(1, yards / d)
    player.wx, player.wy = player.wx + dx * k, player.wy + dy * k
end

for _, sliced in ipairs({ true, false }) do
    local label = sliced and "sliced: " or "all at once: "
    T._Reset()
    local d = T.Data()
    for id in pairs(d.byTaxi) do T.Know().flights[id] = true end
    ns.Set("realRoutes", true); ns.Set("travelHearth", false)
    ns.Set("travelFlights", false); ns.Set("travelBoats", false); ns.Set("travelPreference", "safer")
    T._SetSliced(sliced)
    WP.ClearAll(true)
    Stand(1424, 0.615, 0.209)
    local wp = WP.Add(1416, 0.231, 0.604, { title = "Across the border" })

    local held, planned, anchors, jobs, moved = 0, 0, 0, 0, 0
    local kept = {} -- every place a plan or job kept: the table and what it said when first seen
    local function Note(place)
        if type(place) == "table" and place.player and not kept[place] then
            kept[place] = { place.wx, place.wy, place.m, place.x, place.y, place.area }
        end
    end
    local lastHere
    for f = 1, 1800 do
        -- walks, with a second standing still every eight
        if f % 480 >= 60 then Follow(7 * STEP) end
        M.now = M.now + STEP
        T.Steer(wp, true)
        local p = T.Current()
        if p then
            planned = planned + 1
            Note(p.here)
            Note(p.path[1].node)
            if p.here ~= lastHere then lastHere, anchors = p.here, anchors + 1 end
        end
        local j = sliced and upvalue(T.Steer, "job")
        if j then
            jobs = jobs + 1
            Note(j.place)
            Note(j.here)
        end
        Note(JobPlace())
        if f % 30 == 0 then
            held = held + #Holders()
        end
    end
    check(planned > 1500, label .. "(control) a route was followed (" .. planned .. " frames)")
    check(anchors > 10, label .. "(control) the route was re-anchored where the player stood (" .. anchors .. " times)")
    check(not sliced or jobs > 20, label .. "(control) planning jobs ran (" .. jobs .. " frames)")
    check(held == 0, label .. "nothing holds the live place (" .. held .. " holders found)")
    local count, changed = 0, 0
    for place, was in pairs(kept) do
        count = count + 1
        if place == live then changed = changed + 1 end
        if place.wx ~= was[1] or place.wy ~= was[2] or place.m ~= was[3] or place.x ~= was[4] or place.y ~= was[5]
            or place.area ~= was[6] then changed = changed + 1 end
    end
    check(count > 10, label .. "(control) plans and jobs kept places (" .. count .. ")")
    check(changed == 0, label .. "a kept place never changes afterwards (" .. changed .. " did)")

    -- standing still: the player's place is one table, the one a job began at
    for _ = 1, 600 do
        M.now = M.now + STEP
        T.Steer(wp, true)
    end
    local a, b = T._PlayerPlace(), T._PlayerPlace()
    check(a and a == b and a ~= live, label .. "standing still, the player's place is one table of its own")
    check(not sliced or JobPlace() == a, label .. "and the very table the last job began at")
    M.now = M.now + STEP
    T.Steer(wp, true)
    check(T._PlayerPlace() == a, label .. "steering again does not replace it")
    player.wx = player.wx + 3
    M.now = M.now + STEP
    T.Steer(wp, true)
    local c = T._PlayerPlace()
    check(c and c ~= a and c ~= live and c.wx ~= a.wx, label .. "a moved player is a new place, and the old one is as it was")

    -- walking with a route: no table per frame for the place (0.7 KB each before)
    for _ = 1, 30 do Follow(7 * STEP); M.now = M.now + STEP; T.Steer(wp, true) end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local frames = 0
    for _ = 1, 600 do
        local plan, job = T.Current(), sliced and upvalue(T.Steer, "job")
        Follow(7 * STEP)
        M.now = M.now + STEP
        local k0 = collectgarbage("count")
        T.Steer(wp, true)
        -- frames that plan (a job's slice, a re-anchored route) make what they must
        if T.Current() == plan and not job and not (sliced and upvalue(T.Steer, "job")) then
            frames = frames + 1
        else
            before = before + (collectgarbage("count") - k0)
        end
    end
    local each = (collectgarbage("count") - before) / math.max(frames, 1)
    collectgarbage("restart")
    check(frames > 200, label .. "(control) most walking frames only steer (" .. frames .. " of 600)")
    check(each < 0.6, label .. ("a steering frame while walking allocates %.3f KB (a place table is 0.7)"):format(each))
    check(#Holders() == 0, label .. "and still nothing holds the live place")
end

-- A map ID the network doesn't know, for ground it knows by another ID:
-- WoW Forever's Zephras Isle is both 2521 (on the network) and 2665. With
-- the client calling the player's map 2665, the place is in 2521's area;
-- the answer is remembered per map ID (Geo.SameMap is not asked again).
do
    local z = M.maps[2521]
    M.maps[2665] = { mapID = 2665, name = z.name, mapType = 3, parentMapID = 0, cont = z.cont,
        top = z.top, left = z.left, w = z.w, h = z.h }
    local zephras = T.AreaAt(2521, .5, .5)
    check(zephras ~= nil and G.SameMap(2521, 2665), "Zephras: (control) map 2521 has an area, and 2665 is the same ground")
    local same, asked = G.SameMap, 0
    G.SameMap = function(...) asked = asked + 1; return same(...) end
    check(T.AreaAt(2665, .5, .5) == zephras, "Zephras: a point on map 2665 is in 2521's area")
    local first = asked
    check(T.AreaAt(2665, .3, .6) == T.AreaAt(2521, .3, .6) and asked == first,
        "Zephras: remembered per map ID (" .. (asked - first) .. " more SameMap questions)")
    G.SameMap = same
    check(T.AreaAt(7777, .5, .5) == nil, "a map that is no network map's ground still has no area")
    local best = C_Map.GetBestMapForUnit
    C_Map.GetBestMapForUnit = function() return 2665 end
    player.inst, player.wx, player.wy = z.cont, z.top - .5 * z.h, z.left - .5 * z.w
    M.now = M.now + 1
    local m = G.GetPlayerMapPosition()
    local place = T._PlayerPlace()
    check(m == 2665 and place and place.area == zephras, "Zephras: best map 2665, the player's place is in 2521's area")
    C_Map.GetBestMapForUnit = best
end

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("Travel place: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
