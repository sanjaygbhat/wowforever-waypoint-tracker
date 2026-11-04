-- Regression for the Thrall trip with the shipped network.
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local passed, failed = 0, 0
local function check(value, label)
    if value then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end

-- Client UiMapAssignment.csv, build 1.60.1.70338: overlapping map geometry.
local maps = {
    {1416, "Alterac Mountains", 0, 1500, 783.33331298828, 2799.99993896488, 1866.66665649414},
    {1424, "Hillsbrad Foothills", 0, 400, 1066.6666259766, 3199.9998779297, 2133.3332519531},
    {1420, "Tirisfal Glades", 0, 3837.4997558594, 3033.3332519531, 4518.7498779297, 3012.49981689456},
    {1458, "Undercity", 0, 1877.9453125, 873.19262695313, 959.37503051758, 640.1041259766},
    {1411, "Durotar", 1, 1808.3332519531, -1962.4998779297, 5287.4996337891, 3524.9998779297},
    {1454, "Orgrimmar", 1, 2273.8771972656, -3680.6010742188, 1402.6044921874, 935.4166259765},
}
for _, f in ipairs(maps) do
    M.maps[f[1]] = {mapID = f[1], name = f[2], cont = f[3], top = f[4], left = f[5],
        w = f[6], h = f[7], mapType = 3, parentMapID = f[3] == 0 and 13 or 12}
end
function UnitFactionGroup() return "Horde" end
function UnitLevel() return 30 end
C_TaxiMap.GetTaxiNodesForMap = function()
    return {{nodeID = 13, name = "Tarren Mill, Hillsbrad"}, {nodeID = 11, name = "Undercity, Tirisfal"}}
end
WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
local T, G = ns.Travel, ns.Geo
local d = T.Data()
local flights = T.Know().flights
wipe(flights)
for _, id in ipairs({10, 11, 13, 17, 18, 20}) do flights[id] = true end
for _, id in ipairs({21, 56, 68, 76, 3203}) do flights[id] = false end

local function Place(m, x, y)
    local cont, wx, wy = G.MapToWorld(m, x, y)
    local area, city = T.AreaAt(m, x, y)
    return {m = m, x = x, y = y, cont = cont, wx = wx, wy = wy, area = area, city = city}
end
local ctx = {faction = "Horde", level = 30, run = 7, ground = 7,
    flightFactor = 1, flights = true, boats = true, jumps = {}}
-- Destination: Thrall at Orgrimmar 32.0,37.8.
local goal = Place(1454, .32, .378)
local start = Place(1416, .4805, .8221)
local hx, hy = G.WorldToMap(start.cont, start.wx, start.wy, 1424)
local same = Place(1424, hx, hy)
check(start.area == same.area, "southern Alterac overlap agrees with Hillsbrad at the same world position")
check(T.AreaAt(1416, .5869, .8036) == same.area, "Tarren Mill itself agrees on both overlapping maps")
check(T.AreaAt(1416, .5125, .6819) ~= same.area, "the northern mountain pass stays in Alterac")
check(T.AreaAt(1416, .219, .828) ~= same.area, "Dalaran stays outside the foothills overlap")
check(d.byTaxi[13].m == 1424, "Tarren Mill flight master uses Hillsbrad's map")
check(d.byTaxi[64].m == 1447, "Talrendis Point retains Azshara despite a curated Ashenvale overlap")
local path, cost = T.Search(start, goal, ctx)
local ids = {}
for _, e in ipairs(path or {}) do ids[#ids + 1] = e.node.id or (e.node == goal and "Thrall" or "player") end
print(("Origin-position regression (%.1f s): %s"):format(cost or 0, table.concat(ids, " -> ")))
check(path and path[2].node.taxi == 13, "starting position goes straight to Tarren Mill FM")
check(path and path[3].node.taxi == 11 and path[3].via.method == "taxi", "flies from Tarren Mill to known Undercity")
local zeppelin, hostile, crossTaxi = false, false, false
for _, e in ipairs(path or {}) do
    if type(e.via) == "table" then
        zeppelin = zeppelin or e.via.method == "zeppelin"
        hostile = hostile or (e.via.fac and e.via.fac ~= "Horde")
        crossTaxi = crossTaxi or (e.via.method == "taxi" and e.via.from.cont0 ~= e.via.to.cont0)
    end
end
check(zeppelin and not crossTaxi, "crosses continents by zeppelin")
check(not hostile and path and path[#path].node == goal, "faction-correct route reaches Thrall inside Orgrimmar")
local equivalent, equivalentCost = T.Search(same, goal, ctx)
check(equivalent and cost and math.abs(cost - equivalentCost) < 1, "equivalent map coordinates give the same route cost")

-- A second Hillsbrad origin must choose the same transport.
local latest = Place(1424, .5552, .2685)
local latestPath, latestCost = T.Search(latest, goal, ctx)
check(latestPath and latestPath[2].node.taxi == 13 and latestPath[3].node.taxi == 11
    and latestPath[3].via.method == "taxi", "second origin also uses Tarren Mill then Undercity")
print(("Latest-position Thrall replay (%.1f s): Tarren Mill -> Undercity -> zeppelin -> Thrall"):format(latestCost or 0))

-- Both user policies preserve the corrected known/unknown-FM trip.
for _, preference in ipairs({"fastest", "safer"}) do
    ns.Set("travelPreference", preference)
    for _, known in ipairs({true, false}) do
        flights[13] = known
        for _, origin in ipairs({start, same, latest}) do
            local alternatives, route = T.Routes(origin, goal, ctx, ns.Get("travelPreference"))
            check(route and route.path[2].node.taxi == 13, preference .. " Thrall first targets Tarren Mill")
            local flightIndex = known and 3 or 4
            check(route and route.path[flightIndex].node.taxi == 11 and route.path[flightIndex].via.method == "taxi",
                preference .. " Thrall flies to Undercity")
            check(known or (route and route.path[3].via.kind == "discover"), preference .. " Thrall includes required unlock")
            check(flights[13] == known, preference .. " planning never writes discovery")
        end
    end
end
flights[13] = true
-- End-to-end steering: the first arrow and its flight-map action agree.
ns.Set("realRoutes", true)
ns.Set("travelHearth", false)
ns.Set("travelTrails", false)
M.player.inst, M.player.wx, M.player.wy = start.cont, start.wx, start.wy
C_Map.GetBestMapForUnit = function() return 1416 end
local wp = ns.WP.Add(1454, .32, .378, {title = "Thrall"})
ns.WP.SetActive(wp, true)
local s = T.Steer(wp)
check(s and s.title == ns.L.TRAVEL_TO_FLIGHT:format("Undercity, Tirisfal"), "arrow says go to the flight master and fly to Undercity")
check(T.Current() and T.Current().target.node.taxi == 13, "arrow targets Tarren Mill rather than a northern border")
local _, fx, fy = T.Pos(d.byTaxi[13])
M.player.wx, M.player.wy = fx, fy
M.now = M.now + 3
T.Steer(wp)
TaxiFrame = CreateFrame("Frame")
ns.TravelMap.OnFlightMap({{nodeID = 13, slotIndex = 1}, {nodeID = 11, slotIndex = 2}})
check(WaypointTrackerFlyButton and WaypointTrackerFlyButton:IsShown()
    and WaypointTrackerFlyButton.slot == 2, "flight-map action offers Tarren Mill to Undercity")

-- The same trip is still fastest when the starting FM needs discovery.
flights[13] = false
local unlockPath, unlockCost = T.Search(start, goal, ctx)
check(unlockPath and unlockPath[2].node.taxi == 13 and unlockPath[3].via.kind == "discover"
    and unlockPath[4].node.taxi == 11 and unlockPath[4].via.method == "taxi",
    "unknown Tarren Mill is reached on foot, unlocked, then flown from")
check(unlockCost and math.abs(unlockCost - cost - 6) < .01, "discovery adds its six-second action cost")
local groundCtx = {}; for k, v in pairs(ctx) do groundCtx[k] = v end; groundCtx.flights = false
local groundPath, groundCost = T.Search(start, goal, groundCtx)
print(("Unknown-origin replay: unlock + flight %.1f s; ground + zeppelin %.1f s"):format(unlockCost or 0, groundCost or 0))
check(groundPath and groundCost > unlockCost, "unlock and flight beats walking to the zeppelin")
check(flights[13] == false, "a hypothetical route does not save a discovery")
M.player.wx, M.player.wy = start.wx, start.wy
M.now = M.now + 3
T.Invalidate()
s = T.Steer(wp)
check(s and s.title == ns.L.TRAVEL_UNLOCK_FLIGHT:format("Tarren Mill, Hillsbrad")
    and T.Current().target.node.taxi == 13, "walking arrow labels the unlock at Tarren Mill")
local descriptions = T.Describe()
check(descriptions[1] == ns.L.TRAVEL_UNLOCK_FLIGHT:format("Tarren Mill, Hillsbrad")
    and descriptions[2] == ns.L.TRAVEL_FLY:format("Undercity, Tirisfal"),
    "route details list unlock before flying onward")
M.player.wx, M.player.wy = fx, fy
M.now = M.now + 3
T.Invalidate()
s = T.Steer(wp)
ns.TravelMap.OnFlightMap({{nodeID = 11, slotIndex = 2}})
check(s and s.pin and T.Current().target.via.kind == "discover"
    and not WaypointTrackerFlyButton:IsShown(), "at an unknown FM wait for discovery before offering flight")
C_TaxiMap.GetAllTaxiNodes = function()
    return {{nodeID = 13, state = 0, slotIndex = 1}, {nodeID = 11, state = 1, slotIndex = 2}}
end
M.FireEvent("TAXIMAP_OPENED")
check(flights[13] == true and WaypointTrackerFlyButton:IsShown()
    and WaypointTrackerFlyButton.slot == 2, "opening the FM map confirms discovery and offers Undercity")
flights[13] = nil
local unrecorded = T.Search(start, goal, ctx)
check(unrecorded and unrecorded[3].via.kind == "discover", "unrecorded origin also gets an explicit discovery step")
flights[13] = true

-- An undiscovered destination must still never be offered as a flight.
flights[11] = nil
local unknown = T.Search(start, goal, ctx)
local tookUnknown = false
for _, e in ipairs(unknown or {}) do
    tookUnknown = tookUnknown or (type(e.via) == "table" and e.via.method == "taxi" and e.node.taxi == 11)
end
check(unknown and not tookUnknown, "unknown Undercity falls back to ground travel and zeppelin")
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
