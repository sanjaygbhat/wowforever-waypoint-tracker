-- Real routes (Travel.lua, Trails.lua, TravelMap.lua) against the fake WoW
-- API: a small made-up world on the mock's maps, then the shipped network.
-- Run from the repository root:
--     lua5.1 tests/run_travel.lua
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

-- what the mock doesn't have
local bags = { [6948] = 1 }
function GetItemCount(id)
    return bags[id] or 0
end
local hearthCooldown = 0
C_Container = C_Container or {}
C_Container.GetItemCooldown = function()
    return hearthCooldown, hearthCooldown > 0 and 3600 or 0, 1
end
local walkSpeed = 0
function GetUnitSpeed()
    return walkSpeed, 7, 7, 4.7
end
function IsMounted()
    return false
end
function GetServerTime()
    return math.floor(M.now) + 1700000000
end
local bind = "Brill"
function GetBindLocation()
    return bind
end
function GetTaxiMapID()
    return 1415
end
local taxiNodes = {}
C_TaxiMap.GetAllTaxiNodes = function()
    return taxiNodes
end
local realAreaInfo = C_Map.GetAreaInfo
C_Map.GetAreaInfo = function(area)
    if area == 999 then
        return "Brill"
    end
    return realAreaInfo(area)
end

WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local WP, Travel, Trails, L = ns.WP, ns.Travel, ns.Trails, ns.L

-- Logging in must leave the Routes-tab notice for the player to acknowledge.
M.Tick(13)
check(not ns.Get("travelNoticeShown"), "login does not acknowledge the Real routes notice after 12 seconds")
local teaser = false
for _, message in ipairs(M.printed) do
    if message:find(L.TRAVEL_NEW, 1, true) then teaser = true end
end
check(not teaser, "login never prints the Real routes teaser to chat")

-- ---------------------------------------------------------------------------
-- The shipped network
-- ---------------------------------------------------------------------------
local real = ns.TravelData
check(real and real.nodes and real.links, "the travel network ships with the addon")
local d = Travel.Data()
local nodes, flights, ships, borders = 0, 0, 0, 0
for _, n in pairs(d.nodes) do
    nodes = nodes + 1
    if n.kind == "border" then
        borders = borders + 1
    end
end
for _, list in pairs(d.out) do
    for _, l in ipairs(list) do
        if l.method == "taxi" then
            flights = flights + 1
        elseif l.method == "ship" or l.method == "zeppelin" then
            ships = ships + 1
        end
    end
end
check(nodes > 250 and borders > 90, "crossings, gates, docks and flight masters (" .. nodes .. " stops)")
check(flights > 250, "the flight network (" .. flights .. " flights)")
check(ships >= 20, "boats and zeppelins (" .. ships .. ")")
-- every link's ends exist and every area has somewhere to go
for id, list in pairs(d.out) do
    for _, l in ipairs(list) do
        if not (l.from and l.to and l.from.id == id) then
            check(false, "link " .. tostring(l.key) .. " is whole")
        end
    end
end

-- quickest routes across the real world (positions from the data: the mock
-- doesn't know these maps)
local function Place(id)
    local n = d.nodes[id]
    return { area = n.area, city = n.city, cont = n.cont0, wx = n.wx0, wy = n.wy0, m = n.m, x = n.x, y = n.y }
end
local know = Travel.Know()
for id in pairs(d.byTaxi) do
    know.flights[id] = true
end
local function Ctx(extra)
    local c = {
        faction = "Alliance", level = 60, run = 7, ground = 14, flightFactor = 1,
        flights = true, boats = true, jumps = {},
    }
    for k, v in pairs(extra or {}) do
        c[k] = v
    end
    return c
end
local function Methods(path)
    local seen = {}
    for _, e in ipairs(path or {}) do
        local how = e.via
        if type(how) == "table" then
            seen[how.method or how.kind] = true
        end
    end
    return seen
end
local t0 = os.clock()
local path, total = Travel.Search(Place("TAXI_2"), Place("TAXI_27"), Ctx()) -- Stormwind to Rut'theran
local searchTime = os.clock() - t0
check(path and total < 1800, "Stormwind to Teldrassil has a route (" .. tostring(total and math.floor(total)) .. " s)")
check(searchTime < 0.25, ("a search across the world is quick (%.3f s)"):format(searchTime))
local m = Methods(path)
check(m.ship or m.taxi, "it sails or flies")
path = Travel.Search(Place("TAXI_23"), Place("TAXI_11"), Ctx({ faction = "Horde" })) -- Orgrimmar to Undercity
m = Methods(path)
check(path and m.zeppelin, "the Horde takes the zeppelin from Orgrimmar to Undercity")
path = Travel.Search(Place("TAXI_23"), Place("TAXI_11"), Ctx({ faction = "Alliance", flights = false }))
m = Methods(path)
check(not m.zeppelin, "the Alliance doesn't take Horde zeppelins")
-- no flights known: walking and boats only
path = Travel.Search(Place("TAXI_2"), Place("TAXI_4"), Ctx({ flights = false })) -- Stormwind to Sentinel Hill
m = Methods(path)
check(path and not m.taxi, "without flight paths it walks to Westfall")
local leaves = false
for _, e in ipairs(path or {}) do
    if type(e.via) == "table" and e.via.method == "gate" then
        leaves = true
    end
end
check(leaves, "out through Stormwind's gate, not through the wall")

-- ---------------------------------------------------------------------------
-- A made-up world on the mock's maps
-- ---------------------------------------------------------------------------
-- Elwynn (37) and Westfall (52) meet at world x = -2000; Stormwind (84) is
-- north of Elwynn, entered by a gate; Tirisfal (18) is far north with a
-- flight; Durotar (1) is over the sea.
ns.TravelData = {
    areas = { "ek.elwynn", "ek.westfall", "ek.tirisfal", "kal.durotar" },
    indoor = {},
    nodes = table.concat({
        "B_EW\tborder\t1\t0\t-2000\t-600\t37\t20\t100\t\t\t\t",
        "B_WE\tborder\t2\t0\t-2000\t-600\t52\t44\t0\t\t\t\t",
        "G_OUT\tentrance\t1\t0\t0\t-300\t37\t10\t0\t\t\t\t",
        "G_IN\tentrance\t1\t0\t100\t-300\t84\t75\t100\t84\t\t\t",
        "TAXI_1\ttaxi\t1\t0\t-1000\t-1500\t37\t50\t50\t\t\t1\tAlliance",
        "TAXI_2\ttaxi\t3\t0\t10000\t1000\t18\t50\t57.142857\t\t\t2\tAlliance",
        "DOCK_E\tdock\t1\t0\t-1800\t-2800\t37\t93.333333\t90\t\t\t\t",
        "DOCK_D\tdock\t4\t1\t-1000\t-4000\t1\t33.333333\t28.571429\t\t\t\t",
        "INN_T\tinn\t3\t0\t9000\t0\t18\t75\t85.714286\t\t999\t\t",
    }, "\n"),
    links = table.concat({
        "B_EW\tB_WE\twalk\t0\t\t\t\t\t\t\t",
        "G_IN\tG_OUT\tgate\t0\t\t\t\t\t\t\t",
        "TAXI_1\tTAXI_2\ttaxi\t120\t\t\t1\tAlliance\t\t\t",
        "TAXI_2\tTAXI_1\ttaxi\t120\t\t\t1\tAlliance\t\t\t",
        "DOCK_E\tDOCK_D\tship\t200\t80\t1\t\t\t\t\t",
    }, "\n"),
    maps = "37\t1\n52\t2\n18\t3\n1\t4\n84\t1",
    regions = "",
    cities = "84\tAlliance",
    towns = "brill\t999\tINN_T",
    teleports = "",
    factors = "",
    levels = "",
}
Travel._Reset()
wipe(know.flights)

local function MoveTo(wx, wy, inst)
    M.player.inst = inst or 0
    M.player.wx, M.player.wy = wx, wy
end
local function Steer(wp)
    M.now = M.now + 2.5 -- a fresh plan
    return Travel.Steer(wp)
end

WP.ClearAll(true)
MoveTo(-1000, -2400) -- Elwynn 80, 50
local westfall = WP.Add(52, 0.9, 0.5, { title = "Moonbrook" })
WP.SetActive(westfall, true)
check(Steer(westfall) == nil, "off by default: the arrow points straight")

ns.Set("realRoutes", true)
local s = Steer(westfall)
check(s and s.title == L.TRAVEL_HEAD_TO:format("Westfall"), "to another zone: head for the crossing (" .. tostring(s and s.title) .. ")")
local want = math.atan2(-600 - -2400, -2000 - -1000)
check(s and s.bearing and math.abs(s.bearing - want) < 0.01, "the arrow points at the crossing, not the waypoint")
check(s and s.total and s.total > 0, "with the time for the whole way")
M.Tick(0.2)
check(#M.errors == 0, "the arrow follows it without errors: " .. tostring(M.errors[1]))

-- past the crossing (but still in Elwynn on the map): the arrow doesn't turn back
MoveTo(-1990, -600)
Steer(westfall)
MoveTo(-1990, -640)
s = Travel.Steer(westfall)
check(not (s and s.title == L.TRAVEL_HEAD_TO:format("Westfall") and s.dist and s.dist > 30), "a crossing you reached stays behind you")
MoveTo(-1000, -2400)

-- no route: not worked out again every frame
local plans = 0
ns.On("TRAVEL_PLANNED", function()
    plans = plans + 1
end)
local nowhere = WP.Add(5001, 0.5, 0.5, { title = "Nowhere" })
WP.SetActive(nowhere, true)
for _ = 1, 20 do
    M.now = M.now + 0.02
    Travel.Steer(nowhere)
end
check(plans <= 2, "no route isn't looked for every frame (" .. plans .. ")")

-- a waypoint in the same zone: just the arrow
local near = WP.Add(37, 0.7, 0.6, { title = "Goldshire" })
WP.SetActive(near, true)
check(Steer(near) == nil, "same zone: the plain arrow")

-- Tirisfal: only by air, and no flight path found yet
local tirisfal = WP.Add(18, 0.5, 0.5, { title = "Brill" })
WP.SetActive(tirisfal, true)
ns.Set("travelHearth", false)
check(Steer(tirisfal) == nil, "no flight path found yet: no route")
taxiNodes = { { nodeID = 1, state = 0, slotIndex = 1 }, { nodeID = 2, state = 1, slotIndex = 2 } }
M.FireEvent("TAXIMAP_OPENED", 1)
check(Travel.KnowsFlight(1) == true and Travel.KnowsFlight(2) == true, "a flight master's map says which points are found")
s = Steer(tirisfal)
check(s and s.title == L.TRAVEL_TO_FLIGHT:format("Tirisfal Glades"), "go to the flight master (" .. tostring(s and s.title) .. ")")
local steps = Travel.Describe()
check(steps[#steps] == L.TRAVEL_FLY:format("Tirisfal Glades") or steps[2] == L.TRAVEL_FLY:format("Tirisfal Glades"), "the steps say where to fly")
MoveTo(-1005, -1500) -- at the flight master
s = Steer(tirisfal)
check(s and s.pin and s.title == L.TRAVEL_FLY:format("Tirisfal Glades"), "at the flight master: fly (" .. tostring(s and s.title) .. ")")
M.player.taxi = true
s = Steer(tirisfal)
check(s and s.title == L.TRAVEL_ON_TAXI:format("Tirisfal Glades"), "in the air: flying to (" .. tostring(s and s.title) .. ")")
M.player.taxi = false
MoveTo(10000, 1000)
s = Steer(tirisfal)
check(s == nil, "landed in the zone: the plain arrow again")

-- an unreachable point with a flight from a found one wasn't found either
taxiNodes = { { nodeID = 1, state = 0 }, { nodeID = 2, state = 2 } }
M.FireEvent("TAXIMAP_OPENED", 1)
check(Travel.KnowsFlight(2) == false, "Unreachable next to a found point: not found")

-- the hearthstone
ns.Set("travelHearth", true)
MoveTo(-1000, -2400)
s = Steer(tirisfal)
check(s and s.title == L.TRAVEL_HEARTH:format("Brill"), "the hearthstone home when it's quicker (" .. tostring(s and s.title) .. ")")
hearthCooldown = M.now
s = Steer(tirisfal)
check(not (s and s.title == L.TRAVEL_HEARTH:format("Brill")), "not while it's cooling down")
hearthCooldown = 0
ns.Set("travelHearth", false)

-- over the sea by boat, and noticing the boat has left with you
local durotar = WP.Add(1, 0.5, 0.5, { title = "Razor Hill" })
WP.SetActive(durotar, true)
MoveTo(-1000, -2400)
s = Steer(durotar)
check(s and s.title == L.TRAVEL_TO_BOAT:format("Durotar"), "go to the boat (" .. tostring(s and s.title) .. ")")
MoveTo(-1805, -2800)
s = Steer(durotar)
check(s and s.pin and s.title == L.TRAVEL_BOAT:format("Durotar"), "at the dock: take the boat (" .. tostring(s and s.title) .. ")")
walkSpeed = 0
for i = 1, 8 do
    M.now = M.now + 0.5
    MoveTo(-1805 - i * 6, -2800 - i * 6)
    s = Travel.Steer(durotar)
end
check(Travel.Riding() and s and s.title == L.TRAVEL_ON_BOAT:format("Durotar"), "aboard: on the way (" .. tostring(s and s.title) .. ")")
local st = Trails.Store()
check(st.boats["DOCK_E>DOCK_D"], "the time the boat left is written down")
local wait = Trails.NextDeparture("DOCK_E>DOCK_D", 0)
check(wait and wait > 0 and wait <= 2 * (80 + 60), "and the next one can be told (" .. tostring(wait) .. " s)")
local back = Trails.NextDeparture("DOCK_D>DOCK_E", 0)
check(back ~= nil, "including the way back")
MoveTo(-1000, -3990, 1)
s = Travel.Steer(durotar)
check(not Travel.Riding(), "off the boat at the other end")

-- out of Stormwind through its gate
WP.SetActive(westfall, true)
MoveTo(600, 0) -- inside Stormwind
s = Steer(westfall)
check(s and s.title == L.TRAVEL_LEAVE:format(ns.Geo.GetMapName(84)), "inside a walled city: leave by the gate (" .. tostring(s and s.title) .. ")")

-- ---------------------------------------------------------------------------
-- Trails: paths you walk, and crossings
-- ---------------------------------------------------------------------------
walkSpeed = 7
local function Walk(fromX, fromY, toX, toY)
    local dx, dy = toX - fromX, toY - fromY
    local n = math.ceil(math.max(math.abs(dx), math.abs(dy)) / 8)
    for i = 0, n do
        MoveTo(fromX + dx * i / n, fromY + dy * i / n)
        M.Tick(0.5, 0.5)
    end
end
-- an L: south, then east (y falls going east)
Walk(-300, -500, -1300, -500)
Walk(-1300, -500, -1300, -1500)
local own = Trails.Stats()
check(own > 50, "walking writes the path down (" .. own .. " squares)")
local here = { cont = 0, wx = -300, wy = -500 }
local target = { cont = 0, wx = -1300, wy = -1500 }
local bearing = Trails.Steer(here, target)
local straight = math.atan2(-1500 - -500, -1300 - -300)
check(bearing and math.abs(bearing - math.pi) < 0.3, "the arrow follows the walked path (south first)")
check(bearing and math.abs(bearing - straight) > 0.4, "not the straight line")
-- crossing into Westfall somewhere new
Walk(-1900, -1800, -2100, -1800)
local crossings = 0
for _, c in pairs(st.crossings) do
    if c.mine and c.used then
        crossings = crossings + 1
    end
end
check(crossings == 1, "a crossing you walk becomes a way between the zones")
MoveTo(-1900, -1800)
WP.SetActive(westfall, true)
s = Steer(westfall)
local wantNew = math.atan2(-1800 - -1800, -2000 - -1900)
check(s and s.bearing and math.abs(s.bearing - wantNew) < 0.5, "and routes use it")

-- what another player shares
local Enc, Key = Trails.Enc, Trails._Key
local msg = ("TP^0^%s%s%s%s"):format(Enc(Key(500, 500), 4), Enc(0, 1), Enc(Key(501, 500), 4), Enc(0, 1))
ns.RoutesNet.OnMessage("WPTR", msg, "CHANNEL", "Other-Realm")
local _, shared = Trails.Stats()
check(shared == 0, "one player's path waits for a second")
ns.RoutesNet.OnMessage("WPTR", msg, "CHANNEL", "Third-Realm")
_, shared = Trails.Stats()
check(shared >= 2, "two players' paths are used (" .. shared .. ")")
-- what can't be trusted is turned away
for _, bad in ipairs({ "TP^nan^" .. Enc(1, 4) .. "0", "TP^inf^" .. Enc(1, 4) .. "0", "TP^77^" .. Enc(1, 4) .. "0",
    "TP^0.5^" .. Enc(1, 4) .. "0", "TX^37^nan^0.5^ek.elwynn^ek.westfall", "TX^1e309^0.5^0.5^ek.elwynn^ek.westfall",
    "TX^37^0.5^0.5^nowhere^ek.westfall", "TX^18^0.5^0.5^ek.elwynn^ek.westfall", "TB^DOCK_E>DOCK_D^nan" }) do
    ns.RoutesNet.OnMessage("WPTR", bad, "CHANNEL", "Bad-Realm")
end
local conts = 0
for c in pairs(st.shared) do
    conts = conts + 1
    check(c == 0, "no grid for a made-up continent: " .. tostring(c))
end
for c in pairs(st.pending) do
    check(c == 0, "nothing waiting for a made-up continent: " .. tostring(c))
end
local badCrossing = false
for k, c in pairs(st.crossings) do
    if c.by and c.by["Bad-Realm"] then
        badCrossing = true
    end
end
check(not badCrossing, "made-up crossings are turned away")
check(#M.errors == 0, "bad messages raise no errors: " .. tostring(M.errors[1]))
-- nothing is taken in while sharing is off
ns.Set("travelShare", false)
ns.RoutesNet.OnMessage("WPTR", ("TP^0^%s%s"):format(Enc(Key(600, 600), 4), Enc(0, 1)), "CHANNEL", "Other-Realm")
ns.RoutesNet.OnMessage("WPTR", ("TP^0^%s%s"):format(Enc(Key(600, 600), 4), Enc(0, 1)), "CHANNEL", "Third-Realm")
check(not st.shared[0][Key(600, 600)], "sharing off: other players' paths aren't taken")
ns.Set("travelShare", true)
ns.RoutesNet.OnMessage("WPTR", "TX^37^0.3^0.99^ek.elwynn^ek.westfall", "CHANNEL", "Other-Realm")
local n1 = 0
for _, c in pairs(st.crossings) do
    if not c.mine and c.used then
        n1 = n1 + 1
    end
end
check(n1 == 0, "one player's crossing isn't trusted yet")
ns.RoutesNet.OnMessage("WPTR", "TX^37^0.3^0.99^ek.elwynn^ek.westfall", "CHANNEL", "Third-Realm")
local n2 = 0
for _, c in pairs(st.crossings) do
    if not c.mine and c.used then
        n2 = n2 + 1
    end
end
check(n2 == 1, "two players' is")
ns.RoutesNet.OnMessage("WPTR", "TP^0^%%%%%", "CHANNEL", "Other-Realm")
ns.RoutesNet.OnMessage("WPTR", "TX^37^9^9^a^b", "CHANNEL", "Other-Realm")
ns.RoutesNet.OnMessage("WPTR", "TB^NOPE^1", "CHANNEL", "Other-Realm")

-- the slash command and the world map
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "travel steps")
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "travel status")
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "travel off")
check(not ns.Get("realRoutes"), "/wp travel off turns it off")
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "travel")
check(ns.Get("realRoutes"), "/wp travel turns it on")
ns.TravelMap.Draw()

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
