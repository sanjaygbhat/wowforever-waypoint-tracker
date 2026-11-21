-- Real routes: where a waypoint is, and jumps into where you already are,
-- on the shipped network with the client's real map rectangles
-- (tools/fixtures/travel/UiMapAssignment.csv and UiMap.csv; the stock mock
-- has made-up rectangles and no city maps).
-- - A goal on a zone map inside the rectangle of the walled city you stand
--   in may be on either side of the wall: no trip out of the gate and back
--   in for it (Thunder Bluff and Undercity excepted).
-- - A waypoint on a continent map is planned as the zone point there; a map
--   ID the network doesn't know, for ground it knows by another ID, as that.
-- - A short hop over a sub-area circle's edge is not a kilometres-long trip.
-- - The reported trip: Southshore to Gadgetzan as a mage; after Teleport:
--   Stormwind lands in the Mage Quarter the step moves on, and never says
--   to cast it again. The hearthstone is never used to save seconds.
-- Run from the repository root: lua5.1 tests/run_travel_city.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end

-- ---------------------------------------------------------------------------
-- The client's map rectangles and tree
-- ---------------------------------------------------------------------------
local function csv(line)
    local t, field, quoted, i = {}, "", false, 1
    while i <= #line do
        local ch = line:sub(i, i)
        if ch == '"' then
            if quoted and line:sub(i + 1, i + 1) == '"' then field = field .. '"'; i = i + 1
            else quoted = not quoted end
        elseif ch == "," and not quoted then t[#t + 1] = field; field = ""
        else field = field .. ch end
        i = i + 1
    end
    t[#t + 1] = (field:gsub("\r$", ""))
    return t
end
local function readCSV(path)
    local f = assert(io.open(path))
    local header, out = csv(f:read("*l")), {}
    for line in f:lines() do
        local values, row = csv(line), {}
        for i, h in ipairs(header) do row[h] = values[i] end
        out[#out + 1] = row
    end
    f:close()
    return out
end
local info = {}
for _, r in ipairs(readCSV("tools/fixtures/travel/UiMap.csv")) do info[tonumber(r.ID)] = r end
for id in pairs(M.maps) do M.maps[id] = nil end
M.maps[947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 0 }
local geometry = {}
for _, r in ipairs(readCSV("tools/fixtures/travel/UiMapAssignment.csv")) do
    local id = tonumber(r.UiMapID)
    if id ~= 947 and not geometry[id] and tonumber(r.UiMin_0) == 0 and tonumber(r.UiMin_1) == 0
        and tonumber(r.UiMax_0) == 1 and tonumber(r.UiMax_1) == 1 and info[id] then
        local g = { mapID = id, name = info[id].Name_lang, cont = tonumber(r.MapID),
            top = tonumber(r.Region_3), left = tonumber(r.Region_4),
            h = tonumber(r.Region_3) - tonumber(r.Region_0), w = tonumber(r.Region_4) - tonumber(r.Region_1),
            mapType = tonumber(info[id].Type), parentMapID = tonumber(info[id].ParentUiMapID) }
        if g.w > 0 and g.h > 0 then geometry[id] = g; M.maps[id] = g end
    end
end
check(geometry[1415] and geometry[1415].mapType == 2 and geometry[1457] and geometry[1438] and geometry[2665] and geometry[2521],
    "(control) the client's rectangles for the continents, Darnassus, Teldrassil and both Zephras Isle IDs are loaded")
M.worldRects = { [1415] = { 0.55, 0.95, 0.10, 0.90 }, [1414] = { 0.05, 0.45, 0.10, 0.90 } }

local function Inside(g, wx, wy)
    local x, y = (g.left - wy) / g.w, (g.top - wx) / g.h
    return x >= 0 and x <= 1 and y >= 0 and y <= 1, x, y
end
-- The map the client calls best for the player: an explicit M.player.map,
-- else the smallest zone map (not a city's) around them.
local CITY = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
function C_Map.GetBestMapForUnit()
    if M.player.noPosition then return nil end
    if M.player.map then return M.player.map end
    local best, size
    for id, g in pairs(geometry) do
        if g.mapType == 3 and g.cont == M.player.inst and not CITY[id] and Inside(g, M.player.wx, M.player.wy)
            and (not size or g.w * g.h < size) then best, size = id, g.w * g.h end
    end
    return best
end
-- The zone under a continent map's point, as the client answers it (it
-- hit-tests the zones' shapes; rectangles overlap, so: the zone whose
-- rectangle has the point most inside it)
function C_Map.GetMapInfoAtPosition(id, x, y)
    local parent = geometry[id]
    if not parent then return nil end
    if parent.mapType >= 3 then return C_Map.GetMapInfo(id) end
    local wx, wy = parent.top - y * parent.h, parent.left - x * parent.w
    local best, margin
    for zid, g in pairs(geometry) do
        local inside, zx, zy = Inside(g, wx, wy)
        local m = math.min(zx, 1 - zx, zy, 1 - zy)
        if g.mapType == 3 and g.parentMapID == id and not CITY[zid] and inside
            and (not margin or m > margin) then best, margin = zid, m end
    end
    return best and C_Map.GetMapInfo(best) or C_Map.GetMapInfo(id)
end

-- ---------------------------------------------------------------------------
-- The character
-- ---------------------------------------------------------------------------
local known, bags, spellNames = {}, { [6948] = 1 }, {}
local faction, class, race = "Alliance", "WARRIOR", "Human"
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
C_SpellBook = { IsSpellKnown = function(id, bank) return bank == 0 and known[id] == true end }
C_Spell = {
    GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
    GetSpellName = function(id) return spellNames[id] or ("Spell " .. id) end,
}
C_Item = {
    GetItemCount = function(id) return bags[id] or 0 end,
    GetItemCooldown = function() return 0, 0, 1 end,
    GetItemNameByID = function(id) return "Item " .. id end,
    IsEquippedItem = function() return false end,
    IsUsableItem = function() return true, false end,
}
C_Container = C_Container or {}
C_Container.GetItemCooldown = C_Item.GetItemCooldown
function GetItemCount(id) return bags[id] or 0 end
local mockFaction, mockLevel = UnitFactionGroup, UnitLevel
function UnitFactionGroup(unit) if unit == nil or unit == "player" then return faction end return mockFaction(unit) end
function UnitLevel(unit) if unit == "player" then return 60 end return mockLevel(unit) end
function UnitClass() return class, class end
function UnitRace() return race, race end
function GetUnitSpeed() return 0, 7, 7, 4.7 end
function IsMounted() return false end
function GetServerTime() return math.floor(M.now) + 1700000000 end
local bind = "Nowhere"
function GetBindLocation() return bind end
function GetTaxiMapID() return 1415 end
C_TaxiMap.GetAllTaxiNodes = function() return {} end
local AREA = { [271] = "Southshore", [87] = "Goldshire" }
local realAreaInfo = C_Map.GetAreaInfo
C_Map.GetAreaInfo = function(a) return AREA[a] or realAreaInfo(a) end
-- no clock: planning spread over frames works by expansion count (repeatable)
function debugprofilestop() return nil end

WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local T, WP, G, L = ns.Travel, ns.WP, ns.Geo, ns.L
local d = T.Data()
ns.Set("realRoutes", true); ns.Set("travelTrails", false)

local function PlaceOnMap(m, x, y, best)
    local g = assert(geometry[m], "no rectangle for map " .. tostring(m))
    M.player.inst, M.player.wx, M.player.wy, M.player.map = g.cont, g.top - y * g.h, g.left - x * g.w, best or m
end
local function Place(m, x, y, goal)
    if goal then return T._GoalPlace({ m = m, x = x, y = y }) end -- as a waypoint is planned
    local cont, wx, wy = G.MapToWorld(m, x, y)
    local area, city = T.AreaAt(m, x, y)
    return { area = area, city = city, cont = cont, wx = wx, wy = wy, m = m, x = x, y = y,
        player = not goal or nil, goal = goal or nil }
end
local function Ids(path)
    local out = {}
    for i = 2, #(path or {}) - 1 do out[#out + 1] = path[i].node.id or "?" end
    return table.concat(out, ">")
end
local function Jumps(path, from)
    for i = from or 2, #(path or {}) do
        local how = path[i].via
        if type(how) == "table" and how.kind then return how.kind end
    end
end
-- the flight points this character has found: all, one continent's, or none
local function KnowFlights(cont)
    local k = T.Know()
    for id in pairs(k.flights) do k.flights[id] = nil end
    for id, n in pairs(d.byTaxi) do
        if cont == "all" or n.cont0 == cont then k.flights[id] = true end
    end
end
-- the planning context for what the character can do now (abilities read again)
local function Context()
    T.Invalidate()
    ns.TravelAbilities._Reset()
    return T._Context()
end
-- Plan the waypoint all at once, as the arrow would (a re-plan is due)
local function Steer(wp)
    M.now = M.now + 2.5
    return T.Steer(wp)
end

-- ---------------------------------------------------------------------------
-- (1) The goal on the zone map inside the walled city you are in: which side
-- of the wall it is on is unknown. Out of the gate and back is not a route.
-- (No flight points found, as the cases were measured.)
-- ---------------------------------------------------------------------------
T._SetSliced(false)
KnowFlights("none")
ns.Set("travelHearth", false)
local CASES = {
    -- label, faction, player map/x/y, goal map/x/y, expected: "direct" or "kept"
    { "Darnassus bank -> Ainethil on the Teldrassil map (202 yd)", "Alliance", 1457, .40, .42, 1438, .2860, .5190, "direct" },
    { "Darnassus bank -> the innkeeper on the Teldrassil map (343 yd)", "Alliance", 1457, .40, .42, 1438, .312, .502, "direct" },
    { "just inside the Darnassus gate -> Ainethil on the Teldrassil map", "Alliance", 1457, .86, .36, 1438, .2860, .5190, "kept" },
    { "Stormwind inn -> Herbalist Pomeroy in Elwynn", "Alliance", 1453, .604, .753, 1429, .400, .484, "kept" },
    { "Stormwind Old Town -> Herbalist Pomeroy in Elwynn", "Alliance", 1453, .76, .60, 1429, .400, .484, "kept" },
    { "Orgrimmar inn -> the Durotar coast", "Horde", 1454, .54, .686, 1411, .585, .102, "kept" },
    { "Undercity inn -> Tirisfal (Undercity excepted)", "Horde", 1458, .668, .386, 1420, .520, .695, "kept" },
    { "Ironforge inn -> Dun Morogh", "Alliance", 1455, .184, .514, 1426, .603, .360, "kept" },
    { "Thunder Bluff inn -> the Mulgore ground below (Thunder Bluff excepted)", "Horde", 1456, .454, .634, 1412, .399, .425, "kept" },
    { "Teldrassil outside the gate -> Ainethil on the Teldrassil map (not in the city)", "Alliance", 1438, .40, .50, 1438, .2860, .5190, "kept" },
}
for _, case in ipairs(CASES) do
    local label, fac, pm, px, py, gm, gx, gy, want = unpack(case)
    faction = fac
    race = fac == "Horde" and "Orc" or "Human"
    local c = Context()
    local start, goal = Place(pm, px, py), Place(gm, gx, gy, true)
    check(start.area and goal.area, label .. ": (control) both ends are on the network")
    -- the route as found (no rule), the candidates and the steering choice
    local ctx = {}; for k, v in pairs(c) do ctx[k] = v end
    ctx.preference, ctx.measureDanger = "fastest", true
    local raw = T.Search(Place(pm, px, py), Place(gm, gx, gy, true), ctx)
    local routes = T.Routes(start, goal, c, "fastest")
    local fastest, safer = routes[1], routes[2]
    check(raw and (#raw > 2 or want == "kept"), label .. ": (control) the search alone goes by the network (" .. Ids(raw) .. ")")
    if want == "direct" then
        check(fastest and #fastest.path == 2 and fastest.path[2].via == "walk" and safer and #safer.path == 2,
            label .. ": walk straight there, both candidates (" .. Ids(fastest and fastest.path) .. ")")
    else
        check(fastest and Ids(fastest.path) == Ids(raw), label .. ": the route stands as found (" .. Ids(fastest and fastest.path) .. ")")
    end
    -- Travel.Routes and the steering search are one decision
    for _, preference in ipairs({ "fastest", "safer" }) do
        local _, chosen = T.Routes(Place(pm, px, py), Place(gm, gx, gy, true), c, preference)
        local steer = T._Preferred(Place(pm, px, py), Place(gm, gx, gy, true), c, preference)
        check(chosen and steer and Ids(chosen.path) == Ids(steer.path) and #chosen.path == #steer.path
            and math.abs(chosen.total - steer.total) < 1e-6,
            ("%s: Travel.Routes and the steering search agree (%s)"):format(label, preference))
    end
end

-- The reported case, steered: no "Leave Darnassus" for a trainer inside it
-- whose point is the Teldrassil map's copy; the same from beside the
-- innkeeper; the hearthstone bound in Darnassus changes nothing.
faction, race = "Alliance", "NightElf"
for _, b in ipairs({ "Nowhere", "Darnassus" }) do
    bind = b
    ns.Set("travelHearth", true)
    for _, at in ipairs({ { .40, .42 }, { .45, .48 } }) do
        WP.ClearAll(true)
        PlaceOnMap(1457, at[1], at[2])
        local w = WP.Add(1438, .2860, .5190, { title = "Ainethil", silent = true })
        WP.SetActive(w, true)
        local s = Steer(w)
        local p = T.Current()
        check(T._PlayerPlace().city == 1457, "Darnassus: (control) the player is in the city")
        check(s == nil and p and #p.path == 2,
            ("Darnassus (%.2f, %.2f; hearth %s): a trainer on the Teldrassil map's copy is a straight walk, no \"Leave Darnassus\" (%s)"):format(
                at[1], at[2], b, tostring(s and s.title)))
    end
end
bind = "Nowhere"
ns.Set("travelHearth", false)

-- ---------------------------------------------------------------------------
-- (2) A waypoint on a continent map: the zone point there. Goldshire to
-- Darkshire: the pin on the Eastern Kingdoms map plans as the one on Duskwood.
-- ---------------------------------------------------------------------------
faction, race = "Alliance", "Human"
Context()
WP.ClearAll(true)
PlaceOnMap(1429, .42, .65)
local darkshire = { -10559, -1189 }
local function MapPoint(m, wx, wy) local g = geometry[m]; return (g.left - wy) / g.w, (g.top - wx) / g.h end
local ex, ey = MapPoint(1415, darkshire[1], darkshire[2])
local zx, zy = MapPoint(1431, darkshire[1], darkshire[2])
check(T.AreaAt(1415, ex, ey) == nil, "continent pin: (control) the Eastern Kingdoms map itself has no area there")
local zoneWp = WP.Add(1431, zx, zy, { title = "Darkshire (Duskwood map)", silent = true })
WP.SetActive(zoneWp, true)
local zs = Steer(zoneWp)
local zoneRoute = T.Current()
check(zs and zoneRoute and #zoneRoute.path > 2, "continent pin: (control) the Duskwood-map pin gets a route (" .. tostring(zs and zs.title) .. ")")
WP.ClearAll(true)
local contWp = WP.Add(1415, ex, ey, { title = "Darkshire (Eastern Kingdoms map)", silent = true })
WP.SetActive(contWp, true)
local cs = Steer(contWp)
local contRoute = T.Current()
check(cs and contRoute and zoneRoute and Ids(contRoute.path) == Ids(zoneRoute.path)
    and math.abs(contRoute.total - zoneRoute.total) < 1,
    ("continent pin: the Eastern Kingdoms-map pin gets the same route as on Duskwood (%s / %s)"):format(
        Ids(contRoute and contRoute.path), Ids(zoneRoute and zoneRoute.path)))
check(cs and cs.title == zs.title, "continent pin: the same first step (" .. tostring(cs and cs.title) .. ")")
check(contWp.m == 1415 and contWp.x == ex and contWp.y == ey, "continent pin: the waypoint itself is not changed")

-- ---------------------------------------------------------------------------
-- (3) A map ID the network doesn't know for ground it knows by another:
-- Zephras Isle is 2521 and 2665 (the network has 2521). The player's place
-- and a waypoint on 2665 are planned as on 2521.
-- ---------------------------------------------------------------------------
local zephras = T.AreaAt(2521, .5, .5)
check(zephras ~= nil and G.SameMap(2521, 2665), "Zephras: (control) 2521 is on the network, and 2665 is the same ground")
check(T.AreaAt(2665, .5, .5) == zephras and T.AreaAt(2665, .62, .72) == T.AreaAt(2521, .62, .72),
    "Zephras: a point on map 2665 is in 2521's area")
WP.ClearAll(true)
PlaceOnMap(2521, .5, .5)
local valanaar = WP.Add(2521, .62, .72, { title = "Valanaar", silent = true })
WP.SetActive(valanaar, true)
Steer(valanaar)
local on2521 = T.Current()
check(on2521 ~= nil, "Zephras: (control) a route on map 2521")
M.player.map = 2665
M.FireEvent("ZONE_CHANGED_NEW_AREA")
Steer(valanaar)
check(T._PlayerPlace().area == zephras and T.Current() ~= nil and Ids(T.Current().path) == Ids(on2521.path),
    "Zephras: the client calling the player's map 2665, the route stays")
WP.ClearAll(true)
local on2665 = WP.Add(2665, .62, .72, { title = "Valanaar (2665)", silent = true })
WP.SetActive(on2665, true)
Steer(on2665)
check(T.Current() ~= nil and Ids(T.Current().path) == Ids(on2521.path), "Zephras: a waypoint on map 2665 gets the same route")
M.player.map = nil

-- ---------------------------------------------------------------------------
-- (4) A short hop over a sub-area circle's edge: 30 yd inside and 30 yd
-- outside a circle. Left on foot (Blackrock Mountain, the Ironforge
-- approach): the straight walk. Left by portal (Rut'theran), boat (Sardor
-- Isle) or lift (Freewind Post): the route stands. 200 yd apart: it stands.
-- ---------------------------------------------------------------------------
KnowFlights("all")
local function Region(m, x, y)
    local area = T.AreaAt(m, x, y)
    for _, r in ipairs(d.regions[m] or {}) do
        local g = geometry[m]
        local dx, dy = (x - r.x), (y - r.y)
        if r.area == area and dx * dx + dy * dy <= r.r * r.r then return r, g end
    end
end
local function Pair(m, x, y, yards)
    local r, g = Region(m, x, y)
    if not r then return nil end
    local ux, uy = (x - r.x) * g.w, (y - r.y) * g.h
    local len = math.sqrt(ux * ux + uy * uy)
    ux, uy = ux / len, uy / len
    return Place(m, x, y), Place(m, x + ux * yards / g.w, y + uy * yards / g.h, true)
end
local HOPS = {
    { "Blackrock Mountain -> Burning Steppes", 1428, .201, .288, "direct" },
    { "the Ironforge approach -> Dun Morogh", 1426, .610, .350, "direct" },
    { "Rut'theran -> Teldrassil (portal)", 1438, .619, .967, "kept" },
    { "Sardor Isle -> Feralas (boat)", 1444, .169, .490, "kept" },
    { "Freewind Post -> Thousand Needles (lift)", 1441, .445, .532, "kept" },
}
local c = Context()
for _, hop in ipairs(HOPS) do
    local label, m, x, y, want = unpack(hop)
    for _, yards in ipairs({ 60, 200 }) do
        local start, goal = Pair(m, x, y, yards)
        check(start and goal and start.area and goal.area and start.area ~= goal.area,
            label .. ": (control) the ends are in different areas")
        if start and goal then
            local straight = T.Dist(start, goal)
            local ctx = {}; for k, v in pairs(c) do ctx[k] = v end
            ctx.preference, ctx.measureDanger = "fastest", true
            local raw = T.Search(Pair(m, x, y, yards), select(2, Pair(m, x, y, yards)), ctx)
            local routes = T.Routes(start, goal, c, "fastest")
            local tag = ("%s, %d yd apart"):format(label, math.floor(straight + 0.5))
            check(raw and #raw > 2, tag .. ": (control) the search alone takes a long way round (" .. Ids(raw) .. ")")
            if want == "direct" and yards <= 120 then
                check(routes[1] and #routes[1].path == 2 and routes[2] and #routes[2].path == 2,
                    tag .. ": walk straight there (" .. Ids(routes[1] and routes[1].path) .. ")")
            else
                check(routes[1] and Ids(routes[1].path) == Ids(raw), tag .. ": the route stands (" .. Ids(routes[1] and routes[1].path) .. ")")
            end
            for _, preference in ipairs({ "fastest", "safer" }) do
                local s1, g1 = Pair(m, x, y, yards)
                local s2, g2 = Pair(m, x, y, yards)
                local _, chosen = T.Routes(s1, g1, c, preference)
                local steer = T._Preferred(s2, g2, c, preference)
                check(chosen and steer and Ids(chosen.path) == Ids(steer.path) and #chosen.path == #steer.path,
                    ("%s: Travel.Routes and the steering search agree (%s)"):format(tag, preference))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- (5) The hearthstone is never used to save seconds: bound in Goldshire,
-- the waypoint beside the inn, 150, 300 and 500 yd away (it saved 2 s).
-- ---------------------------------------------------------------------------
bind = "Goldshire"
ns.Set("travelHearth", true)
faction, race = "Alliance", "Human"
local c2 = Context()
local inn = d.nodes.INN_295
check(T.BindNode() == inn and c2.jumps[1] and c2.jumps[1].kind == "hearth", "hearthstone: (control) bound at the Goldshire inn, ready")
local _, ix, iy = T.Pos(inn)
for _, yards in ipairs({ 150, 300, 500 }) do
    WP.ClearAll(true)
    M.player.inst, M.player.wx, M.player.wy, M.player.map = 0, ix - yards, iy, 1429
    local w = WP.Add(1429, inn.x + 0.002, inn.y, { title = "by the inn", silent = true })
    WP.SetActive(w, true)
    local s = Steer(w)
    local p = T.Current()
    check(p and not Jumps(p.path) and (s == nil or s.title ~= L.TRAVEL_HEARTH:format("Goldshire")),
        ("hearthstone: %d yd from its inn, never \"%s\" (%s)"):format(yards, L.TRAVEL_HEARTH:format("Goldshire"), tostring(s and s.title)))
end
bind = "Nowhere"

-- ---------------------------------------------------------------------------
-- (6) The reported trip: an Alliance mage in Southshore (hearthstone bound
-- there) heading for Gadgetzan, Eastern Kingdoms flight points known. The
-- route begins "Cast Teleport: Stormwind". The spell lands in the Mage
-- Quarter, 246 yd from the network's landing node: the step moves on at
-- once, and never says to cast it again. Sliced and all at once.
-- ---------------------------------------------------------------------------
class, race, faction = "MAGE", "Human", "Alliance"
bind = "Southshore"
known[3561], bags[17031] = true, 5
spellNames[3561] = "Teleport: Stormwind"
local castText = L.TRAVEL_TELEPORT:format("Teleport: Stormwind")
-- what the arrow says (planning sliced, the route held while its new search
-- runs may still have its index at the cast: the arrow steers past it)
local function Casting(s)
    return s ~= nil and s.title == castText
end
for _, sliced in ipairs({ false, true }) do
    local mode = sliced and "sliced" or "all at once"
    T._SetSliced(sliced)
    KnowFlights(0)
    Context()
    WP.ClearAll(true)
    PlaceOnMap(1424, .51, .58)
    M.Tick(0.5)
    local w = WP.Add(1446, .515, .28, { title = "Gadgetzan", silent = true })
    WP.SetActive(w, true)
    local s
    for _ = 1, 600 do
        M.now = M.now + 1 / 60
        s = T.Steer(w)
        if T.Current() and s and s.title == castText then break end
    end
    local p0 = T.Current()
    check(Casting(s) and p0 and type(p0.path[p0.index].via) == "table" and p0.path[p0.index].via.kind == "teleport", ("mage trip (%s): in Southshore the route begins %q (%s)"):format(mode, castText, tostring(s and s.title)))
    -- the cast: a loading screen, then the Mage Quarter
    M.player.noPosition = true
    for _ = 1, 30 do M.now = M.now + 1 / 30; T.Steer(w) end
    PlaceOnMap(1453, .4884, .8807, 1453)
    M.player.noPosition = nil
    bags[17031] = 4
    M.FireEvent("PLAYER_ENTERING_WORLD")
    M.FireEvent("ZONE_CHANGED_NEW_AREA")
    M.FireEvent("BAG_UPDATE_DELAYED")
    local here = T._PlayerPlace()
    check(here.city == 1453 and math.abs(T.Dist(here, d.nodes.CITY_STORMWIND) - 246) < 5,
        ("mage trip (%s): (control) landed in Stormwind's Mage Quarter, %d yd from the modelled landing"):format(mode, T.Dist(here, d.nodes.CITY_STORMWIND)))
    M.now = M.now + 1 / 60
    s = T.Steer(w)
    check(s and not Casting(s),
        ("mage trip (%s): the first frame in Stormwind no longer says %q (%s)"):format(mode, castText, tostring(s and s.title)))
    local again, frames = 0, 0
    for _ = 1, 60 * 10 do
        M.now = M.now + 1 / 60
        s = T.Steer(w)
        frames = frames + 1
        if Casting(s) then again = again + 1 end
        if not sliced and frames % 60 == 0 then M.Tick(0.05) end
    end
    local p = T.Current()
    check(again == 0, ("mage trip (%s): over 10 s in Stormwind no frame says to cast the teleport again (%d of %d)"):format(mode, again, frames))
    check(p and not Jumps(p.path, p.index) and s and s.title ~= castText and p.target and p.target.node.taxi == 2,
        ("mage trip (%s): the step is the walk to the Stormwind flight master (%s)"):format(mode, tostring(s and s.title)))
end
known[3561], bags[17031] = nil, nil
class, bind = "WARRIOR", "Nowhere"

check(#M.errors == 0, "no reported Lua errors: " .. tostring(M.errors[1]))
print(("Travel city: %d passed, %d failed"):format(passed, failed))
os.exit((failed == 0 and #M.errors == 0) and 0 or 1)
