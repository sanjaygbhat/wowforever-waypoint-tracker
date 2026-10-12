-- Least-time planning, discovery, transport arrival states and terrain.
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local passed, failed = 0, 0
local function check(value, label)
    if value then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end
function UnitFactionGroup() return "Horde" end
function UnitLevel() return 30 end
function GetUnitSpeed() return 0, 7 end
WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
local T, G = ns.Travel, ns.Geo
local function Network(nodes, links, barriers)
    ns.TravelData = {areas = {"outdoors", "destination"}, indoor = {}, nodes = nodes, links = links,
        maps = "37\t1", regions = "", cities = "", towns = "", teleports = "", factors = "", levels = "",
        barriers = barriers or ""}
    T._Reset()
    return T.Data()
end
local function Node(id, area, x, y, faction)
    local cont, wx, wy = G.MapToWorld(37, x, y)
    return table.concat({"TAXI_" .. id, "taxi", area, cont, wx, wy, 37, x * 100, y * 100,
        "", "", id, faction or "Horde"}, "\t")
end
local function Place(x, y, area)
    local cont, wx, wy = G.MapToWorld(37, x, y)
    return {m = 37, x = x, y = y, area = area or 1, cont = cont, wx = wx, wy = wy}
end
local ctx = {faction = "Horde", level = 30, run = 7, ground = 7,
    flightFactor = 1, flights = true, boats = true, jumps = {}}
local flights = T.Know().flights
local function Has(path, kind)
    for _, e in ipairs(path or {}) do
        if type(e.via) == "table" and (e.via.kind == kind or e.via.method == kind) then return true end
    end
    return false
end
local d = Network(table.concat({Node(1, 1, .13, .5), Node(2, 1, .77, .5), Node(3, 1, .135, .5)}, "\n"),
    "TAXI_1\tTAXI_2\ttaxi\t40\t\t\t1\tHorde\t\t\t\nTAXI_3\tTAXI_2\ttaxi\t45\t\t\t1\tHorde\t\t\t")
wipe(flights); flights[1], flights[2], flights[3] = false, true, true
local start, goal = Place(.1, .5), Place(.8, .5)
local fast, cost = T.Search(start, goal, ctx)
check(fast and Has(fast, "discover") and fast[2].node.taxi == 1, "fast unknown-FM detour wins over known flights and walking")
check(math.abs(cost - (180 * 1.15 / 7 + 6 + 6 + 40)) < .01, "cost includes ground, discovery, boarding and flight")
local short, shortCost = T.Search(start, Place(.1, .55), ctx)
check(short and #short == 2 and not Has(short, "discover"), "slower unknown-FM detour loses to direct walking")
check(math.abs(shortCost - 100 * 1.15 / 7) < .01, "winning walk has the minimum modeled time")

local disabled = {}; for k, v in pairs(ctx) do disabled[k] = v end; disabled.flights = false
local foot = T.Search(start, goal, disabled)
check(foot and not Has(foot, "taxi") and not Has(foot, "discover"), "disabled flights also disable discovery detours")
d.byTaxi[1].fac = "Alliance"
local friendly = T.Search(start, goal, ctx)
check(friendly and not Has(friendly, "discover"), "enemy FM cannot be unlocked for a Horde flight")
d.byTaxi[1].fac = "Horde"
d.out.TAXI_1[1].class = "MAGE"
local restricted = T.Search(start, goal, ctx)
check(restricted and not Has(restricted, "discover"), "discovery does not bypass a class-restricted flight")
d.out.TAXI_1[1].class = nil
d.out.TAXI_1[1].quest = 123456
restricted = T.Search(start, goal, ctx)
check(restricted and not Has(restricted, "discover"), "discovery does not bypass an incomplete quest requirement")
d.out.TAXI_1[1].quest = nil
flights[2] = false
local noLanding = T.Search(start, goal, ctx)
check(noLanding and not Has(noLanding, "taxi"), "unknown destination is never invented as a landing point")
flights[2] = true

-- Fastest followed routes retain only tiny gains below 3 seconds or 2%.
ns.Set("travelPreference", "fastest"); ns.Set("realRoutes", true); ns.Set("travelHearth", false); ns.Set("travelTrails", false)
M.player.inst, M.player.wx, M.player.wy = start.cont, start.wx, start.wy
C_Map.GetBestMapForUnit = function() return 37 end
local wp = ns.WP.Add(37, .8, .5, {title = "Goal"})
ns.WP.SetActive(wp, true)
T.Steer(wp)
local old = T.Current()
check(old and old.target.node.taxi == 1, "initial displayed route selects the fastest unknown FM")
d.out.TAXI_3[1].cost = 38
M.now = M.now + 3; T.Invalidate(); T.Steer(wp)
local new = T.Current()
check(new and old and new.total < old.total and new.total > old.total * .9,
    "competing route improves total time by less than ten percent")
check(new and new.target.node.taxi == 3, "followed route switches for a gain above the small hysteresis threshold")

-- A known boat is cheaper than either flight candidate (20 + two short walks).
local boatA, boatB = Node(4, 1, .13, .5), Node(5, 1, .77, .5)
d = Network(ns.TravelData.nodes .. "\n" .. boatA .. "\n" .. boatB,
    ns.TravelData.links .. "\nTAXI_4\tTAXI_5\tship\t20\t10\t0\t1\tHorde\t\t\t")
local boat = T.Search(start, goal, ctx)
check(boat and Has(boat, "ship") and not Has(boat, "discover"), "faster boat beats the unknown-FM detour")

-- This barrier cuts every inferred approach to the FM and the goal.
d = Network(ns.TravelData.nodes, ns.TravelData.links, "37\t11.5\t49\t11.5\t51\t0\t-980\t-345\t-1020\t-345")
check(T.Search(start, goal, ctx) == nil, "discovery and boats do not bypass an impassable approach barrier")
local blocked = T.Steer(wp)
check(blocked and blocked.pin and not blocked.bearing and blocked.title == ns.L.TRAVEL_NO_PLAN,
    "blocked route displays no reachable route instead of pointing through terrain")

-- Arrival state matters: walking to the connector costs 40 seconds, while
-- reaching it aboard costs 44. Staying aboard saves the 6-second reboarding
-- fee, so the two-flight itinerary wins 84 vs 86 seconds. A node-only search
-- incorrectly discards the 44-second aboard arrival.
d = Network(table.concat({Node(1, 1, .1, .5), Node(2, 1, .1 + (40 * 7 / 1.15) / 3000, .5),
    Node(3, 2, .8, .5)}, "\n"),
    "TAXI_1\tTAXI_2\ttaxi\t38\t\t\t1\tHorde\t\t\t\nTAXI_2\tTAXI_3\ttaxi\t40\t\t\t1\tHorde\t\t\t")
wipe(flights); flights[1], flights[2], flights[3] = true, true, true
local chain, chainCost = T.Search(Place(.1, .5), Place(.8, .5, 2), ctx)
local count = 0
for _, e in ipairs(chain or {}) do if type(e.via) == "table" and e.via.method == "taxi" then count = count + 1 end end
check(chain and count == 2 and math.abs(chainCost - 84) < .01, "aboard and ground arrivals remain separate to find the true minimum")
check(chain and not Has(chain, "discover"), "known connecting flight needs no discovery action")

-- A soft danger multiplier must not turn a quicker walk into a slower
-- flight. Actual faction/class/quest and terrain checks remain mandatory.
d = Network(Node(1, 1, .1, .5) .. "\n" .. Node(2, 1, .14, .5),
    "TAXI_1\tTAXI_2\ttaxi\t15\t\t\t1\tHorde\t\t\t")
wipe(flights); flights[1], flights[2] = true, true
d.levels[37] = {60, 63}
local quickest, quickestCost = T.Search(Place(.1, .5), Place(.14, .5), ctx)
check(quickest and #quickest == 2 and math.abs(quickestCost - 120 * 1.15 / 7) < .01,
    "zone danger does not inflate elapsed time and select a slower flight")

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
