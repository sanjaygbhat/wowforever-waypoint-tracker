-- Quest 557 / terrain barriers, using the bundled DB and real map geometry.
-- Lua 5.1; also run with WT_PLAIN_VECTORS=1. No SavedVariables are read.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
-- First full-map assignments from tools/.cache/travel/UiMapAssignment.csv
-- (Forever 1.60.1.70338); independent of the generated barrier coordinates.
M.maps[1416] = { mapID = 1416, name = "Alterac Mountains", mapType = 3, parentMapID = 13,
    cont = 0, top = 1500, left = 783.33331298828, w = 2799.99993896488, h = 1866.66665649414 }
M.maps[1424] = { mapID = 1424, name = "Hillsbrad Foothills", mapType = 3, parentMapID = 13,
    cont = 0, top = 400, left = 1066.6666259766, w = 3199.9998779297, h = 2133.3332519531 }
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
assert(ns.DB.Load())
local T, d = ns.Travel, ns.Travel.Data()
local passed, failed = 0, 0
local function check(ok, msg)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function place(m, x, y)
    local cont, wx, wy = ns.Geo.MapToWorld(m, x, y)
    return { m = m, x = x, y = y, cont = cont, wx = wx, wy = wy, area = T.AreaAt(m, x, y) }
end
local function ids(path)
    local out = {}
    for _, e in ipairs(path or {}) do out[#out + 1] = e.node.id or "position" end
    return table.concat(out, ",")
end
local c = { faction = "Horde", level = 34, run = 7, ground = 7, flightFactor = 1,
    flights = false, boats = false, jumps = {} }
-- Curated.lua NPC 2437; Data.lua quest 557 -> item 3715 -> NPC 2359.
local start = place(1424, .615, .209)
M.player.inst, M.player.wx, M.player.wy = 0, start.wx, start.wy
local q = ns.DB.quests[557]
check(q.name == "Bracers of Binding" and q.objI[1] == 3715 and q.endU[1] == 2437, "quest and turn-in identity")
local source, p = ns.DB.NearestOf(ns.DB.QuestTargets(q, "objective"))
check(source.id == 2359 and p.m == 1416 and p.x == .229 and p.y == .595, "verified reachable objective spawn from Tarren Mill")
local goal = place(p.m, p.x, p.y)
local barriers = d.barriers
check(#barriers == 15, "the fifteen verdict-backed local barriers parse")
-- Reproduce the old inferred shortcut, without terrain constraints.
local terrain = ns.Terrain; ns.Terrain = nil
d.barriers = {}
local old, oldCost = T.Search(start, goal, c)
check(ids(old) == "position,BORDER_HILLSBRAD_FOOTHILLS_TO_ALTERAC_MOUNTAINS,BORDER_ALTERAC_MOUNTAINS_TO_HILLSBRAD_FOOTHILLS,position",
    "old route enters eastern Alterac then cuts straight west")
check(oldCost and oldCost > 0, "unconstrained graph prices the original shortcut")
d.barriers = barriers; ns.Terrain = terrain
local path, total = T.Search(start, goal, c)
local function completeGround(route)
    if not route or #route<2 then return false end
    for i=2,#route do
        local a,b=route[i-1].node,route[i].node
        local e=terrain.Evidence(a,b)
        if e and (e.state == "TERRAIN_BLOCKED" or e.state == "UNAVAILABLE") then return false end
        local via=route[i].via
        if (via == "walk" or type(via)=="table" and (via.method=="walk" or via.method=="gate" or via.method=="lift")) and not T.CanWalk(a,b) then return false end
    end
    return true
end
local expected = ids(path)
check(completeGround(path), "quest 557 retains the western corridor without blocked chords")
check(total and total > oldCost, "complete verified geometry costs more than the unconstrained shortcut")
-- Check the complete bundled spawn set, not only the selected spawn, and
-- retrace the return journey. Each endpoint can use either overlapping map.
for _, spot in ipairs(ns.DB.Points(source)) do
    if spot.m == 1416 or spot.m == 1424 then
        local there = place(spot.m, spot.x, spot.y)
        local outward = T.Search(start, there, c)
        local back = T.Search(there, start, c)
        for _, trip in ipairs({ { outward, "out" }, { back, "back" } }) do
            local route = ids(trip[1])
            check(completeGround(trip[1]),
                "Darrow Hill detour " .. trip[2] .. " " .. spot.m .. " " .. spot.x .. "," .. spot.y)
        end
    end
end
-- Replanning after the first bend must keep going west, not return to TM.
local junction = place(1424, .556, .346)
path = T.Search(junction, goal, c)
check(completeGround(path), "replan at eastern road bend preserves western approach")
path = T.Search(place(1424, .38, .36), goal, c)
check(completeGround(path), "replan at western road bend keeps an eligible western approach")
path = T.Search(place(1416, .219, .828), goal, c)
check(completeGround(path), "Dalaran skirt approach completes without a blocked ground chord")
-- Main mountain road remains useful for eastern Alterac destinations.
path = T.Search(start, place(1416, .60, .55), c)
check(ids(path):find("BORDER_HILLSBRAD_FOOTHILLS_TO_ALTERAC_MOUNTAINS,", 1, true), "retain the main pass for eastern Alterac")

-- Both options retain the surveyed road detour for the nearest quest objective
-- and every other bundled objective spawn, outward and on the return journey.
for _, preference in ipairs({"fastest", "safer"}) do
    ns.Set("travelPreference", preference)
    local _, route = T.Routes(start, goal, c, ns.Get("travelPreference"))
    check(route and completeGround(route.path), preference .. " quest 557 uses the safe terrain corridor")
    for _, spot in ipairs(ns.DB.Points(source)) do
        if spot.m == 1416 or spot.m == 1424 then
            local there = place(spot.m, spot.x, spot.y)
            for _, endpoints in ipairs({{start, there}, {there, start}}) do
                local _, trip = T.Routes(endpoints[1], endpoints[2], c, preference)
                check(trip and completeGround(trip.path),
                    preference .. " quest 557 objective and return respect Darrow Hill barrier")
            end
        end
    end
end

-- Small world: generic segment intersection, independent of local geography.
ns.TravelData = {
    areas = { "test" }, maps = "37\t1\n52\t1", nodes = "", links = "",
    -- Elwynn 50,20 -> 50,80: world x -400 -> -1600, world y -1500
    barriers = "37\t50\t20\t50\t80\t0\t-400\t-1500\t-1600\t-1500",
}
T._Reset(); d = T.Data()
local function search(a, b) return T.Search(place(37, a[1], a[2]), place(37, b[1], b[2]), c) end
check(search({ .25, .5 }, { .75, .5 }) == nil, "reject an implicit walk through a barrier")
check(search({ .75, .5 }, { .25, .5 }) == nil, "barriers apply in both directions")
check(search({ .25, .1 }, { .75, .1 }) ~= nil, "allow a walk around a barrier end")
check(search({ .50, .20 }, { .50, .80 }) == nil, "reject a collinear overlap")
check(search({ .25, .20 }, { .75, .20 }) == nil, "reject touching an endpoint")
check(search({ .25, .5 }, { .25, .5 }) ~= nil, "coincident positions still have a zero-length walk")
-- Same world segment represented on Westfall instead of Elwynn.
local a = place(37, .25, .5)
local b = { m = 52, area = 1, cont = 0, wx = -1000, wy = -2250 }
check(T.Search(a, b, c) == nil, "overlapping maps cannot bypass a world barrier")
local bridgeA = { id = "bridgeA", area = 1, m = 37, x = .25, y = .5 }
local bridgeB = { id = "bridgeB", area = 1, m = 37, x = .75, y = .5 }
d.byArea[1] = { bridgeA, bridgeB }
d.out.bridgeA = { { from = bridgeA, to = bridgeB, method = "walk", cost = 12 } }
path, total = search({ .25, .5 }, { .75, .5 })
check(path and total == 12, "an explicit surveyed crossing overrides an inferred barrier")
-- A map unavailable to the mock uses shipped world coordinates, like nodes.
ns.TravelData.barriers = "9999\t50\t20\t50\t80\t0\t-400\t-1500\t-1600\t-1500"
T._Reset(); T.Data()
check(search({ .25, .5 }, { .75, .5 }) == nil, "barriers retain world-coordinate fallback")
print(("Travel binding: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
