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
local secretSpeed = {}
local plainSecretValue = issecretvalue
function issecretvalue(value)
    return rawequal(value, secretSpeed) or plainSecretValue(value)
end
local walkSpeed, runSpeed, mounted = 0, 7, false
function GetUnitSpeed()
    return walkSpeed, runSpeed, 7, 4.7
end
function IsMounted()
    return mounted
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

-- Real routes is a standard feature: no opt-in notice flag, no chat teaser.
M.Tick(13)
check(ns.settings.travelNoticeShown == nil, "login sets no Real routes notice flag")
local teaser = false
for _, message in ipairs(M.printed) do
    if message:find(L.REAL_ROUTES, 1, true) then teaser = true end
end
check(not teaser, "login never prints a Real routes message to chat")

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
check(path and m.zeppelin, "both factions can take the zeppelin; hostile approaches remain separate")
-- no flights known: walking and boats only
path, total = Travel.Search(Place("TAXI_2"), Place("TAXI_4"), Ctx({ flights = false })) -- Stormwind to Sentinel Hill
m = Methods(path)
check(path and not m.taxi, "without flight paths it walks to Westfall")
local leaves = false
for _, e in ipairs(path or {}) do
    if type(e.via) == "table" and e.via.method == "gate" then
        leaves = true
    end
end
check(leaves, "out through Stormwind's gate, not through the wall")
local groundPath, groundTotal = Travel.Search(Place("TAXI_2"), Place("TAXI_4"), Ctx({ flights = false, boats = false }))
check(groundPath and total <= groundTotal + 1e-6, "boats enabled preserve the short Stormwind gate route")
for _, pair in ipairs({
    { "BORDER_WETLANDS_TO_ARATHI_HIGHLANDS", "PASS_LOCH_MODAN_ALGAZ_OUTER" },
    { "TAXI_6", "TAXI_8" }, -- Ironforge to Thelsamar
}) do
    local withBoats, boatTime = Travel.Search(Place(pair[1]), Place(pair[2]), Ctx({ flights = false }))
    local ground, groundTime = Travel.Search(Place(pair[1]), Place(pair[2]), Ctx({ flights = false, boats = false }))
    check(withBoats and ground and boatTime <= groundTime + 1e-6,
        "boats preserve the nearby ground route: " .. pair[1] .. " > " .. pair[2])
end

-- The walk to a vessel's unmeasured client stop (Riverglades' Powderfuse
-- Port) is labelled a bare straight line; the walk to an ordinary dock is not
check(d.nodes.DOCK_POWDERFUSE_CLIENT_STOP.vehicleStop and d.nodes.DOCK_STEAMWHEEDLE_CLIENT_STOP.vehicleStop
    and not d.nodes.DOCK_MENETHIL.vehicleStop and not d.nodes.DOCK_POWDERFUSE.vehicleStop,
    "only the two vehicle-stop-verified client stops are marked")
local function WalkTo(route, id)
    for k, e in ipairs(route or {}) do
        if e.node.id == id and e.via == "walk" then return k end
    end
end
local function LegLabel(route, k)
    return Travel._BareLine(route, k, { dist = Travel.Dist(route[k - 1].node, route[k].node) })
end
path = Travel.Search(Place("TAXI_3275"), Place("DOCK_STEAMWHEEDLE"), Ctx({ flights = false }))
local leg = WalkTo(path, "DOCK_POWDERFUSE_CLIENT_STOP")
check(leg and path[leg + 1] and type(path[leg + 1].via) == "table" and path[leg + 1].via.method == "ship"
    and LegLabel(path, leg) == true, "Powderfuse: the walk to the boat's client stop is labelled a straight line")
path = Travel.Search(Place("TAXI_7"), Place("DOCK_SOUTHSHORE"), Ctx({ flights = false }))
leg = WalkTo(path, "DOCK_MENETHIL")
check(leg and LegLabel(path, leg) == false, "Menethil: the walk to an ordinary dock is not")
-- a walking link the data flags unmeasured (an indoor passage) is labelled
local indoor
for _, l in ipairs(d.out.BORDER_BURNING_STEPPES_TO_BLACKROCK_MOUNTAIN or {}) do
    if l.to.id == "BORDER_BLACKROCK_MOUNTAIN_TO_BURNING_STEPPES" then indoor = l end
end
check(indoor and indoor.confidence == "unmeasured-indoor" and Travel._BareLine({ { node = indoor.from }, { node = indoor.to, via = indoor } }, 2, {}) == true,
    "Blackrock Mountain: the unmeasured indoor passage is labelled")
-- Travel.GoalArea: where a waypoint is, as the planner places it (no search)
local ga, gc = Travel.GoalArea(d.nodes.TAXI_2.m, d.nodes.TAXI_2.x, d.nodes.TAXI_2.y)
check(ga == d.nodes.TAXI_2.area and gc == d.nodes.TAXI_2.city, "GoalArea: Stormwind's flight master is in its area and city")
check(Travel.GoalArea(nil, 0.5, 0.5) == nil and Travel.GoalArea(1414, 0 / 0, 0.5) == nil, "GoalArea: nothing for an unusable point")

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
check(ns.Get("realRoutes") == true, "Real routes is on by default")
ns.Set("realRoutes", false)
check(Steer(westfall) == nil, "turned off: the arrow points straight")

ns.Set("realRoutes", true)
local s = Steer(westfall)
check(s and s.title == L.TRAVEL_HEAD_TO:format("Westfall"), "to another zone: head for the crossing (" .. tostring(s and s.title) .. ")")
local want = math.atan2(-600 - -2400, -2000 - -1000)
check(s and s.bearing and math.abs(s.bearing - want) < 0.01, "the arrow points at the crossing, not the waypoint")
check(s and s.total and s.total > 0, "with the time for the whole way")
M.Tick(0.2)
check(#M.errors == 0, "the arrow follows it without errors: " .. tostring(M.errors[1]))

-- A restricted speed must not break the arrow or write a trail. The sentinel
-- is recognized by issecretvalue and raises on numeric comparisons in Lua 5.1.
walkSpeed = secretSpeed
local errorsBefore = #M.errors
local ownBefore = Trails.Stats()
M.Tick(0.5, 0.5)
check(#M.errors == errorsBefore, "secret current speed raises no arrow or trail errors")
check(Trails.Stats() == ownBefore, "secret current speed records no trail")
walkSpeed, runSpeed, mounted = 0, secretSpeed, true
local mountBefore = know.mountSpeed
Travel.Invalidate()
local speedOK, speedStep = pcall(Steer, westfall)
check(speedOK and speedStep and speedStep.bearing, "secret run speed still allows planning")
check(know.mountSpeed == mountBefore, "secret run speed is not saved as mount speed")
runSpeed, mounted = 7, false

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
local unavailable = Steer(tirisfal)
check(unavailable and unavailable.pin and unavailable.title == L.TRAVEL_NO_PLAN,
    "no reachable flight destination: show no route instead of a straight fallback")
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
-- Live Forever can disable the deprecated spell/item globals entirely.
local legacyCount, legacyPlayer, legacyKnown = GetItemCount, IsPlayerSpell, IsSpellKnown
local oldItem, oldBook, oldBank, oldSpell = C_Item, C_SpellBook, Enum.SpellBookSpellBank, C_Spell
GetItemCount, IsPlayerSpell, IsSpellKnown = nil, nil, nil
C_Item = { GetItemCount = function(id) check(id == 6948, "modern item count receives hearthstone ID"); return 1 end }
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
local knownSpells = {}
C_SpellBook = { IsSpellKnown = function(id, bank)
    check(bank == 0, "modern spell query uses Player bank, including enum value zero")
    return knownSpells[id] or false
end }
C_Spell = { GetSpellCooldown = function() return { startTime = 0, duration = 0 } end }
local routes, context = Travel.Routes
Travel.Routes = function(_, _, c) context = c; return {} end
local function ReadContext() Travel.Choices(tirisfal); return context end
check(#ReadContext().jumps == 1, "modern item API alone enables hearthstone travel")
GetItemCount = function() error("deprecated item API must not run") end
check(#ReadContext().jumps == 1, "modern item API takes precedence over legacy global")
C_Item.GetItemCount = function() return 0 end
check(#ReadContext().jumps == 0, "modern zero count disables hearthstone")
knownSpells[556], knownSpells[1225490] = true, true
local c = ReadContext()
check(#c.jumps == 1, "Astral Recall works without deprecated spell globals")
check(c.flightFactor == 1 / 1.2, "modern Frequent Flier knowledge affects flight ETA")
knownSpells = {}
IsPlayerSpell = function() return true end
check(#ReadContext().jumps == 0 and context.flightFactor == 1, "modern false is authoritative over legacy true")
C_SpellBook = nil
check(#ReadContext().jumps > 0, "legacy IsPlayerSpell works when modern API is absent")
C_SpellBook = { IsSpellKnown = function() error("unavailable modern API") end }
check(#ReadContext().jumps > 0, "throwing modern spell API can use the legacy shim")
C_SpellBook = { IsSpellKnown = function() error("Player bank missing: must not query") end }
Enum.SpellBookSpellBank = nil
check(#ReadContext().jumps > 0, "missing Player bank uses legacy spell knowledge")
C_SpellBook = nil
IsPlayerSpell = nil
IsSpellKnown = function(id) return id == 556 end
check(#ReadContext().jumps == 1, "legacy IsSpellKnown works when IsPlayerSpell is absent")
IsSpellKnown = function() error("unavailable legacy shim") end
check(#ReadContext().jumps == 0, "a throwing legacy shim does not break planning")
C_Item = nil
GetItemCount = legacyCount
check(#ReadContext().jumps == 1, "legacy GetItemCount still enables hearthstone")
GetItemCount = nil
check(#ReadContext().jumps == 0, "absent item and spell APIs safely disable hearth travel")
C_Item = { GetItemCount = function() error("unavailable item API") end }
check(#ReadContext().jumps == 0, "throwing item API safely disables hearth travel")
Travel.Routes = routes
GetItemCount, IsPlayerSpell, IsSpellKnown = legacyCount, legacyPlayer, legacyKnown
C_Item, C_SpellBook, Enum.SpellBookSpellBank, C_Spell = oldItem, oldBook, oldBank, oldSpell
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
walkSpeed = secretSpeed
local secretSamplesOK = true
for i = 1, 8 do
    M.now = M.now + 0.5
    MoveTo(-1805 - i * 6, -2800 - i * 6)
    secretSamplesOK = pcall(Travel.Steer, durotar) and secretSamplesOK
end
check(secretSamplesOK, "secret current speed does not break boat samples")
check(not Travel.Riding(), "unknown walking speed is not evidence of boarding a boat")
walkSpeed = 0
MoveTo(-1805, -2800)
Steer(durotar)
for i = 1, 8 do
    M.now = M.now + 0.5
    MoveTo(-1805 - i * 6, -2800 - i * 6)
    s = Travel.Steer(durotar)
end
check(Travel.Riding() and s and s.title == L.TRAVEL_ON_BOAT:format("Durotar"), "aboard: on the way (" .. tostring(s and s.title) .. ")")
walkSpeed = secretSpeed
M.now = M.now + 0.5
local ridingOK, ridingStep = pcall(Travel.Steer, durotar)
check(ridingOK and ridingStep and Travel.Riding(), "secret speed aboard keeps the ride without errors")
walkSpeed = 0
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

-- what another player shares (walked-path sharing is opt-in)
local Enc, Key = Trails.Enc, Trails._Key
local msg = ("TP^0^%s%s%s%s"):format(Enc(Key(500, 500), 4), Enc(0, 1), Enc(Key(501, 500), 4), Enc(0, 1))
check(ns.Get("realRoutes") and not ns.Get("travelShare"), "walked-path sharing is off by default, with Real routes on")
ns.RoutesNet.OnMessage("WPTR", msg, "CHANNEL", "Other-Realm")
ns.RoutesNet.OnMessage("WPTR", msg, "CHANNEL", "Third-Realm")
local _, shared = Trails.Stats()
check(shared == 0, "by default other players' paths aren't taken")
ns.Set("travelShare", true)
ns.RoutesNet.OnMessage("WPTR", msg, "CHANNEL", "Other-Realm")
_, shared = Trails.Stats()
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

-- what the arrow was told is kept for bug reports, and so are errors
local log = WaypointTrackerDB.travelLog
check(type(log) == "table" and #log > 0 and log[#log].target and log[#log].here, "the arrow's steps are logged")
check(#log <= 60, "the log stays short")
local before = #M.errors
ns.ReportError("test error\nstack")
check(WaypointTrackerDB.errorLog and WaypointTrackerDB.errorLog[#WaypointTrackerDB.errorLog].error:find("test error", 1, true),
    "errors are kept in the saved variables")
for _ = #M.errors, before + 1, -1 do
    table.remove(M.errors)
end

-- ---------------------------------------------------------------------------
-- Why the arrow points straight (Travel.Note), on the arrow's third line and
-- in the travel log; and a leg the route only knows as a straight line
-- ---------------------------------------------------------------------------
-- the made-up world again (without the crossings walked and shared above);
-- `stop`: DOCK_E is a vessel's unmeasured client stop
ns.Set("travelShare", false)
wipe(Trails.Store().crossings)
local function MadeUp(stop)
    local t = {}
    for k, v in pairs(ns.TravelData) do t[k] = v end
    t.transportEvidence = stop and "DOCK_E\tCORRECTED\tvehicle-stop-verified,access-unmeasured" or ""
    ns.TravelData = t
    Travel._Reset()
    wipe(know.flights)
end
MadeUp(false)
ns.Set("realRoutes", true); ns.Set("travelHearth", false); ns.Set("travelTrails", false)
ns.Set("travelFlights", true); ns.Set("travelBoats", true)
local arrowLines = {}
for _, o in ipairs(M.frames) do
    if o._kind == "FontString" and o._parent == ns.Arrow.textFrame then arrowLines[#arrowLines + 1] = o end
end
local etaLine, noteLine = arrowLines[3], ns.Arrow.noteText
check(#arrowLines == 4 and arrowLines[4] == noteLine, "the arrow has its three text lines and the note's (" .. #arrowLines .. ")")
-- the note's line: the text frame's width, two lines at most (wrapped, the
-- rest truncated), inside the frame, so it never runs past it or its Edit
-- Mode box; the frame stays click-through
local tf = ns.Arrow.textFrame
check(noteLine:GetWidth() == tf:GetWidth() and noteLine:CanWordWrap() and noteLine:GetHeight() >= 20 and noteLine:GetHeight() <= 26
    and tf:GetHeight() >= 40 + noteLine:GetHeight() and not tf:IsMouseEnabled(),
    "the note's line fits the text frame: its width, two lines tall, inside the frame")
-- every note, in every locale, fits two lines of the frame's width (a
-- generous 40 characters a line at this size; CJK and Hangul count double)
for _, loc in ipairs({ "enUS", "deDE", "esES", "frFR", "ptBR", "ruRU", "zhCN", "zhTW", "koKR" }) do
    local strings = {}
    local chunk = assert(loadfile("WaypointTracker/Locales/" .. loc .. ".lua"))
    setfenv(chunk, setmetatable({ GetLocale = function() return loc end }, { __index = _G }))
    chunk("WaypointTracker", { L = strings, NewLocale = function() return strings end })
    check(loc == "enUS" or strings.TRAVEL_NOTE_GOAL_OFFNET, loc .. ": its notes are read for the length check")
    for _, key in ipairs({ "TRAVEL_NOTE_PLANNING", "TRAVEL_NOTE_OFFNET", "TRAVEL_NOTE_GOAL_OFFNET", "TRAVEL_NOTE_STRAIGHT" }) do
        local text, width = strings[key] or ns.L[key], 0
        for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do width = width + (#ch >= 3 and 2 or 1) end
        if width > 80 then check(false, ("%s %s fits two lines of the note (%d)"):format(loc, key, width)) end
    end
end
local function Shown(wp)
    WP.SetActive(wp, true)
    M.Tick(2.5, 0.1)
    return etaLine and etaLine:GetText(), noteLine:GetText()
end
local function Note(wp) return select(2, Shown(wp)) end
local function LastPlain()
    local entries = WaypointTrackerDB.travelLog
    for k = #entries, 1, -1 do
        if entries[k].plain then return entries[k] end
    end
end
check(ns.Get("showETA") == false, "(control) the ETA line is off by default")
WP.ClearAll(true)
westfall = WP.Add(52, 0.9, 0.5, { title = "Moonbrook" })
durotar = WP.Add(1, 0.5, 0.5, { title = "Razor Hill" })

-- a walk inside one area: the normal arrow, nothing to say
MoveTo(-1000, -2400)
local goldshire = WP.Add(37, 0.7, 0.6, { title = "Goldshire" })
WP.SetActive(goldshire, true)
check(Steer(goldshire) == nil and Travel.Note() == nil, "same area: the plain arrow and no note")
local eta3, note3 = Shown(goldshire)
check(eta3 == "" and note3 == "", "same area: the arrow's third line and its note stay empty")

-- the waypoint on a zone the network doesn't cover: not on the network
local pinned = WP.Add(7777, 0.5, 0.5, { title = "Unmapped zone" })
WP.SetActive(pinned, true)
s = Steer(pinned)
local why, text = Travel.Note()
check(s == nil and why == "goal-offnet" and text == L.TRAVEL_NOTE_GOAL_OFFNET,
    "a waypoint the network can't place: the plain arrow says so (" .. tostring(why) .. ")")
eta3, note3 = Shown(pinned)
check(eta3 == "" and note3 == L.TRAVEL_NOTE_GOAL_OFFNET, "on the note's line, with the ETA line off")
local entry = LastPlain()
check(entry and entry.plain == "goal-offnet" and entry.here and entry.route and not entry.target,
    "and in the travel log")

-- the player where the network has no area (on the continent map only)
MoveTo(5000, -1000)
WP.SetActive(goldshire, true)
s = Steer(goldshire)
why, text = Travel.Note()
check(s == nil and why == "offnet" and text == L.TRAVEL_NOTE_OFFNET, "where you are isn't on the network: said (" .. tostring(why) .. ")")
check(Note(goldshire) == L.TRAVEL_NOTE_OFFNET, "on the note's line")
check(LastPlain() and LastPlain().plain == "offnet", "and in the travel log")

-- a waypoint on another continent the network has no area for: the note
-- replaces the map name under "On another continent"
MoveTo(-1000, -2400)
local elsewhere = WP.Add(1411, 0.5, 0.5, { title = "Unmapped zone" })
eta3, note3 = Shown(elsewhere)
check(eta3 == ns.Geo.GetMapName(1411) and note3 == L.TRAVEL_NOTE_GOAL_OFFNET
    and arrowLines[2]:GetText() == L.ANOTHER_CONTINENT,
    "another continent: the reason after the zone's name, which stays (" .. tostring(etaLine:GetText()) .. ")")

-- no position at all: the arrow says it can't track; the reason is logged
WP.SetActive(goldshire, true)
Steer(goldshire)
M.player.noPosition = true
s = Steer(goldshire)
check(s == nil and Travel.Note() == "noposition", "no position: the reason is kept")
check(LastPlain() and LastPlain().plain == "noposition" and LastPlain().here == "no position", "and logged")
eta3, note3 = Shown(goldshire)
check(eta3 == "" and note3 == "" and arrowLines[2]:GetText() == L.CANT_TRACK_HERE, "the arrow says it can't track, nothing more")
M.player.noPosition = nil
ns.Set("realRoutes", false)
check(Steer(goldshire) == nil and Travel.Note() == nil, "Real routes off: no note")
ns.Set("realRoutes", true)

-- an ordinary walk inside an area is a straight line too, however long:
-- no label (it would be on almost every walk), the ETA line as it was
WP.SetActive(westfall, true)
MoveTo(-1000, -2400) -- 2059 yd from the crossing
s = Steer(westfall)
check(s and s.title == L.TRAVEL_HEAD_TO:format("Westfall") and s.note == nil,
    "a long ordinary walk is not labelled (" .. tostring(s and s.note) .. ")")
eta3, note3 = Shown(westfall)
check(eta3 == "" and note3 == "", "its third line stays as the ETA setting says, no note (" .. tostring(etaLine:GetText()) .. ")")
ns.Set("showETA", true)
local total, totalNote = Shown(westfall)
check(total and total ~= "" and totalNote == "", "with the ETA on: the total, no label (" .. tostring(total) .. ")")
ns.Set("showETA", false)
MoveTo(-1850, -700) -- 180 yd from it
s = Steer(westfall)
check(s and s.title == L.TRAVEL_HEAD_TO:format("Westfall") and s.note == nil, "a short one is not either")

-- the walk to an ordinary dock (200 yd): no label; at 50 yd still on the way
local function Settle(wp, wx, wy)
    MoveTo(wx, wy)
    M.now = M.now + 30 -- not a boat's drift
    for _ = 1, 9 do M.now = M.now + 0.3; Travel.Steer(wp) end
    return Steer(wp)
end
WP.SetActive(durotar, true)
s = Settle(durotar, -1700, -2630)
check(s and s.title == L.TRAVEL_TO_BOAT:format("Durotar") and s.note == nil, "the walk to an ordinary dock is not labelled")
s = Settle(durotar, -1760, -2770)
check(s and s.title == L.TRAVEL_TO_BOAT:format("Durotar"), "50 yd from an ordinary dock: still going to it (" .. tostring(s and s.title) .. ")")

-- a vessel's unmeasured client stop: the leg says it is a bare line, and
-- 60 yd counts as there (the nearest ground may be that far off)
MadeUp(true)
check(Travel.Data().nodes.DOCK_E.vehicleStop == true and Travel.Thresholds.boardUnmeasured == 60,
    "vehicle-stop-verified stops are read from the transport evidence")
WP.ClearAll(true)
durotar = WP.Add(1, 0.5, 0.5, { title = "Razor Hill" })
WP.SetActive(durotar, true)
s = Settle(durotar, -1700, -2630)
check(s and s.title == L.TRAVEL_TO_BOAT:format("Durotar") and s.note == L.TRAVEL_NOTE_STRAIGHT,
    "the walk to an unmeasured stop is labelled (" .. tostring(s and s.note) .. ")")
-- the label is on its own line: the waypoint and the total stay whole
eta3, note3 = Shown(durotar)
local _, under = noteLine:GetPoint()
check(eta3 == "" and note3 == L.TRAVEL_NOTE_STRAIGHT and under == arrowLines[2],
    "with the ETA off: the label on its own line, under the distance")
ns.Set("showETA", true)
local line3, label = Shown(durotar)
_, under = noteLine:GetPoint()
check(line3 and line3:find("Razor Hill", 1, true) and not line3:find(L.TRAVEL_NOTE_STRAIGHT, 1, true) and label == L.TRAVEL_NOTE_STRAIGHT
    and under == etaLine, "with the ETA on: the waypoint and the total whole, the label under them (" .. tostring(line3) .. ")")
ns.Set("showETA", false)
s = Settle(durotar, -1760, -2770)
check(s and s.pin and s.title == L.TRAVEL_BOAT:format("Durotar") and s.note == nil,
    "50 yd from an unmeasured stop: take the boat (" .. tostring(s and s.title) .. ")")
s = Settle(durotar, -1730, -2770)
check(s and s.title == L.TRAVEL_TO_BOAT:format("Durotar"), "70 yd from it: still going to it")

-- BareLine on its own: an explicit link, a surveyed or walked leg are never labelled
local A = { m = 37, x = 0.5, y = 0.5, cont = 0, wx = -1000, wy = -1500 }
local B = { m = 37, x = 0.5, y = 0.85, cont = 0, wx = -1000, wy = -2200, id = "B" }
local Bare = Travel._BareLine
check(Bare({ { node = A }, { node = B, via = "walk" } }, 2, { dist = 700 }) == false, "BareLine: not a 700-yd ordinary walk")
check(Bare({ { node = A }, { node = B, via = { method = "walk" } } }, 2, { dist = 700 }) == false, "BareLine: not along an explicit link")
check(Bare({ { node = A }, { node = B, via = { method = "gate", confidence = "unmeasured-traversal" } } }, 2, { dist = 80 }) == true,
    "BareLine: a walking link the data flags unmeasured")
check(Bare({ { node = A }, { node = B, via = { method = "walk", confidence = "unmeasured-indoor" } } }, 2, { dist = 80, trail = 1 }) == false,
    "BareLine: not even that along a walked path")
check(Bare({ { node = A }, { node = B, via = { method = "walk", terrain = true } } }, 2, { dist = 700 }) == false, "BareLine: not over surveyed ground")
check(Bare({ { node = A }, { node = B, via = "walk" } }, 2, { dist = 700, trail = 1 }) == false, "BareLine: not along a walked path")
MadeUp(false)
WP.ClearAll(true)

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
