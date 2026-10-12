-- Deterministic offline tests of shipped taxi identities and interactions.
-- Run from repo root: lua5.1 tests/check_taxi_transport.lua
-- Taxi API contract: Gethe/wow-ui-source classic TaxiMapDocumentation.lua.
-- Dialog rules: Mapzeroth Data/Forever/Edges.lua, Nighthaven section.
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local nodes = {}
function GetTaxiMapID() return 1415 end
C_TaxiMap.GetAllTaxiNodes = function() return nodes end
Enum.FlightPathState = {Current = 0, Reachable = 1, Unreachable = 2}
WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
local T, d = ns.Travel, ns.Travel.Data()
local passed, failed = 0, 0
local function check(value, entry, current, why)
    if value then passed = passed + 1 else
        failed = failed + 1
        print("FAIL WaypointTracker/TravelData.lua / Travel.lua: " .. entry
            .. ": value=" .. tostring(current) .. "; " .. why)
    end
end
local function place(id)
    local n = assert(d.nodes[id], id)
    return {id = n.id, area = n.area, city = n.city, cont = n.cont0,
        wx = n.wx0, wy = n.wy0, m = n.m, x = n.x, y = n.y,
        taxi = n.taxi, fac = n.fac, discoverable = n.discoverable}
end
local function ctx(fac, class)
    return {faction = fac, class = class, race = "Human", level = 60,
        run = 7, ground = 7, flightFactor = 1, flights = true,
        boats = false, jumps = {}}
end
local function uses(path, from, to)
    for _, e in ipairs(path or {}) do
        local l = e.via
        if type(l) == "table" and l.method == "taxi"
            and l.from.id == from and l.to.id == to then return true end
    end
    return false
end
local function discovers(path, id)
    for _, e in ipairs(path or {}) do
        if e.node.id == id and type(e.via) == "table"
            and e.via.kind == "discover" then return true end
    end
    return false
end

-- Every shipped ordinary ID must be keyed by API nodeID. Deliberately make
-- slotIndex unrelated; Forever's high IDs also differ from saved-mask bits.
local ids = {}
for id in pairs(d.byTaxi) do
    if id ~= 46 and id ~= 62 and id ~= 63 then ids[#ids+1] = id end
end
table.sort(ids)
wipe(T.Know().flights)
for i, id in ipairs(ids) do
    nodes[i] = {nodeID = id, slotIndex = 10000 + i,
        state = i == 1 and Enum.FlightPathState.Current or Enum.FlightPathState.Reachable}
end
T.ReadFlightMap()
for i, id in ipairs(ids) do
    check(T.KnowsFlight(id) == true, "API nodeID " .. id, T.KnowsFlight(id),
        "Current/Reachable must map to the exact client TaxiNodes.ID")
    check(T.KnowsFlight(10000+i) == nil, "API slotIndex " .. (10000+i), T.KnowsFlight(10000+i),
        "slotIndex is a UI slot, never a discovery ID")
end
check(T.KnowsFlight(3203) and not T.KnowsFlight(1), "Rog'mar 3203 vs bit 1", T.KnowsFlight(1),
    "CharacterBitNumber=1 is not nodeID=3203 (TaxiNodes.csv)")
check(T.KnowsFlight(3275) and not T.KnowsFlight(50), "Powderfuse 3275 vs bit 50", T.KnowsFlight(50),
    "CharacterBitNumber=50 is not nodeID=3275 (TaxiNodes.csv)")

-- Exercise Current and Reachable separately for every ordinary node.
for _, id in ipairs(ids) do
    wipe(T.Know().flights)
    nodes = {{nodeID = id, slotIndex = 9999, state = Enum.FlightPathState.Current}}
    T.ReadFlightMap()
    check(T.KnowsFlight(id) == true, "Current nodeID " .. id, T.KnowsFlight(id), "Current must confirm discovery")
end
wipe(T.Know().flights)
nodes = {{nodeID=13, slotIndex=1, state=2}, {nodeID=11, slotIndex=2, state=0}}
T.ReadFlightMap()
check(T.KnowsFlight(13) == false, "unreachable Tarren Mill 13", T.KnowsFlight(13),
    "directly connected unreachable destination must be recorded undiscovered")
nodes = {{nodeID=3203, slotIndex=1, state=2}, {nodeID=11, slotIndex=2, state=0}}
T.Know().flights[3203] = true
T.ReadFlightMap()
check(T.KnowsFlight(3203) == true, "disconnected unreachable Rog'mar 3203", T.KnowsFlight(3203),
    "unreachable without a direct found neighbor is not evidence that a known flight was lost")

-- Node areas and player AreaAt must agree at every flight master; otherwise
-- a player on a mesa/island and that FM inhabit different walking graphs.
for _, id in ipairs(ids) do
    local n = d.byTaxi[id]
    local area, city = T.AreaAt(n.m, n.x, n.y)
    check(area == n.area and city == n.city, n.id .. " area at own coordinates",
        tostring(n.area) .. " vs " .. tostring(area),
        "FM area must equal AreaAt(map,x,y), including authored subregions")
end

-- Unknown nearby normal FM may be reached, registered, and boarded when its
-- destination is already known. Speculative unlock must never persist state.
wipe(T.Know().flights)
T.Know().flights[11] = true
local path = T.Search(place("TAXI_13"), place("TAXI_11"), ctx("Horde", "WARRIOR"))
check(uses(path, "TAXI_13", "TAXI_11") and discovers(path, "TAXI_13"), "13>11 unlock then fly", path,
    "normal unknown origin may be unlocked when faster than walking")
check(T.KnowsFlight(13) == nil, "speculative discovery 13", T.KnowsFlight(13), "route planning must not save a discovery")

-- A no-mount transport marker must not become an unlockable flight master.
if d.nodes.TAXI_46 then
    wipe(T.Know().flights)
    T.Know().flights[7] = true
    local slow = ctx("Alliance", "WARRIOR")
    slow.run, slow.ground = 1, 1
    path = T.Search(place("TAXI_46"), place("TAXI_7"), slow)
    check(not uses(path, "TAXI_46", "TAXI_7"), "Southshore Ferry 46>Menethil 7",
        uses(path, "TAXI_46", "TAXI_7"), "slow ground profile: TaxiNodes 46 has no mount; TaxiPath 253 is a transport spline, not a boardable flight")
end

-- Faction ownership is enforced even for a directly connected known pair.
for _, test in ipairs({{13,11,"Alliance"}, {2,4,"Horde"}}) do
    wipe(T.Know().flights)
    T.Know().flights[test[1]], T.Know().flights[test[2]] = true, true
    local from, to = "TAXI_" .. test[1], "TAXI_" .. test[2]
    path = T.Search(place(from), place(to), ctx(test[3], "WARRIOR"))
    check(not uses(path, from, to), from .. ">" .. to .. " hostile faction " .. test[3],
        uses(path, from, to), "known flight IDs never override faction restrictions")
end

-- Druid dialog services do not use a flight map or require discovered
-- destinations. An unknown dialog source must not acquire a fake taxi unlock.
for _, test in ipairs({{62,27,"Alliance"}, {63,22,"Horde"}}) do
    local a, b, fac = test[1], test[2], test[3]
    local from, to = "TAXI_" .. a, "TAXI_" .. b
    wipe(T.Know().flights)
    T.Know().flights[b] = true
    path = T.Search(place(from), place(to), ctx(fac, "WARRIOR"))
    check(not uses(path, from, to), from .. ">" .. to .. " WARRIOR", uses(path, from, to),
        "Nighthaven dialog service is DRUID-only; duplicate unrestricted client edge bypasses the rule")
    path = T.Search(place(from), place(to), ctx(fac, "DRUID"))
    check(uses(path, from, to) and not discovers(path, from), from .. ">" .. to .. " DRUID no taxi-map source",
        discovers(path, from), "dialog service must work without registering a non-discoverable source")
    wipe(T.Know().flights)
    path = T.Search(place(from), place(to), ctx(fac, "DRUID"))
    check(uses(path, from, to), from .. ">" .. to .. " DRUID unknown destination", uses(path, from, to),
        "dialog service goes to its fixed destination without prior taxi discovery")
end

-- The boarding action uses the transient slotIndex, while discovery and the
-- route use stable nodeID. A destination missing from the live map is hidden.
local currentFn, enabledFn = T.Current, T.Enabled
local ride
for _, l in ipairs(d.out.TAXI_13 or {}) do
    if l.method == "taxi" and l.to.taxi == 11 then ride = l; break end
end
assert(ride, "shipped 13>11 flight absent")
local fakePath = {{node = d.byTaxi[13]}, {node = d.byTaxi[11], via = ride}}
T.Current = function() return {path = fakePath, index = 2, target = fakePath[2]} end
T.Enabled = function() return true end
TaxiFrame = CreateFrame("Frame")
ns.TravelMap.OnFlightMap({{nodeID=11, slotIndex=7}, {nodeID=7, slotIndex=11}})
check(WaypointTrackerFlyButton and WaypointTrackerFlyButton.slot == 7,
    "Undercity nodeID 11 / slotIndex 7", WaypointTrackerFlyButton and WaypointTrackerFlyButton.slot,
    "flight-map button must select slotIndex=7 for stable destination ID=11")
local taken
TakeTaxiNode = function(slot) taken = slot end
if WaypointTrackerFlyButton then
    WaypointTrackerFlyButton:GetScript("OnClick")(WaypointTrackerFlyButton)
end
check(taken == 7, "TakeTaxiNode", taken, "boarding API expects the live slot, not the DB2 node ID")
ns.TravelMap.OnFlightMap({{nodeID=7, slotIndex=11}})
check(WaypointTrackerFlyButton and not WaypointTrackerFlyButton:IsShown(),
    "missing live destination 11", WaypointTrackerFlyButton and WaypointTrackerFlyButton:IsShown(),
    "missing destination must hide the flight action")
local dialog
for _, l in ipairs(d.out.TAXI_62 or {}) do
    if l.class == "DRUID" and l.to.taxi == 27 then dialog = l; break end
end
if dialog then
    local dialogPath = {{node = d.byTaxi[62]}, {node = d.byTaxi[27], via = dialog}}
    T.Current = function() return {path = dialogPath, index = 2, target = dialogPath[2]} end
    ns.TravelMap.OnFlightMap({{nodeID=27, slotIndex=8}})
    check(not WaypointTrackerFlyButton:IsShown(), "Nighthaven dialog flight boarding button",
        WaypointTrackerFlyButton:IsShown(), "dialog service must not offer TakeTaxiNode even when its destination appears on another flight map")
end
T.Current, T.Enabled = currentFn, enabledFn

print("RESULT " .. passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
