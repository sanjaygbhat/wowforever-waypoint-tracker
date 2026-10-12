-- Travel: Real routes (beta). Instead of pointing straight at the waypoint,
-- the arrow follows a way you can actually go there: around mountains and
-- through the passes, gates and tunnels between zones, and by flight path,
-- boat, zeppelin, the tram, your hearthstone or a teleport when that's
-- quicker.
--
-- The game tells addons nothing about the ground, so the ways between places
-- are data (TravelData.lua): the zone crossings, city gates, docks and
-- flights. Inside one area (a zone, or part of one) the way is a straight
-- line between them. Trails.lua adds what players have walked themselves.
--
-- Flights land only at flight paths this character has found. A quicker
-- trip may walk to an unknown flight master and unlock it before flying.
-- Discovery is confirmed only by opening the flight master's map, and is
-- written down then (per character), never by a hypothetical plan.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local Travel = {}
ns.Travel = Travel

local sqrt, floor, min, max, huge = math.sqrt, math.floor, math.min, math.max, math.huge

local RUN_SPEED = 7 -- yards a second on foot
local DEFAULT_FACTOR = 1.15 -- real walks are this much longer than the straight line
local LOADING = 10 -- seconds a loading screen costs
local CAST = 10 -- casting the hearthstone or a teleport
local TAXI_TALK = 6 -- talking to the flight master and getting on
local TAXI_UNLOCK = 6 -- registering a new flight path before boarding
local NEAR = 15 -- yards: a stop this close is behind you
local BOARD_NEAR = 30 -- yards from a dock or flight master that count as there
local REPLAN_EVERY = 2 -- seconds
local REPLAN_MOVED, REPLAN_MIN = 10, 0.5 -- yards; minimum seconds between movement searches
local LOOK_AHEAD, DEVIATION, CORRIDOR_JOIN = 45, 40, 40 -- yards
local DANGER_LEVELS, DANGER_PENALTY = 3, 0.6
local TOWN_RADIUS = 200 -- estimated guard exposure around a faction town's inn; not an access boundary
local OFFER_SECONDS, OFFER_FRACTION, OFFER_LIFETIME, OFFER_FADE = 15, 0.05, 10, 2
local KEEP_SECONDS, KEEP_FRACTION = 3, 0.02
Travel.Thresholds = { dangerLevels = DANGER_LEVELS, dangerPenalty = DANGER_PENALTY,
    townRadius = TOWN_RADIUS, offerSeconds = OFFER_SECONDS, offerFraction = OFFER_FRACTION,
    offerLifetime = OFFER_LIFETIME, offerFade = OFFER_FADE, keepSeconds = KEEP_SECONDS, keepFraction = KEEP_FRACTION }
local FREQUENT_FLIER = 1225490 -- WoW Forever's perk: flight paths 20% faster
local HEARTHSTONE, ASTRAL_RECALL = 6948, 556

local TRANSPORT = { taxi = true, ship = true, zeppelin = true, tram = true, portal = true, transition = true }
local WALKING = { walk = true, gate = true, lift = true }

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------
local data -- the parsed network, built the first time a route is asked for

local function Fields(line)
    local out, from = {}, 1
    while true do
        local i = line:find("\t", from, true)
        if not i then
            out[#out + 1] = line:sub(from)
            return out
        end
        out[#out + 1] = line:sub(from, i - 1)
        from = i + 1
    end
end

local function Rows(text, fn)
    for line in (text or ""):gmatch("[^\n]+") do
        fn(Fields(line))
    end
end

local function Blank(s)
    return s ~= "" and s or nil
end

local function AddLink(d, from, to, l)
    local list = d.out[from.id]
    if not list then
        list = {}
        d.out[from.id] = list
    end
    l.from, l.to = from, to
    list[#list + 1] = l
end

-- crossings, gates, docks, flights... from TravelData.lua
local function Parse()
    local T = ns.TravelData
    if not T then
        return nil
    end
    local d = {
        nodes = {}, byArea = {}, out = {}, mapArea = {}, regions = {}, cities = {}, towns = {},
        teleports = {}, factors = {}, levels = {}, byTaxi = {}, barriers = {},
        areas = T.areas or {}, indoor = T.indoor or {}, ghostCorridors = {}, buildKey = T.buildKey,
    }
    Rows(T.nodes, function(f)
        local n = {
            id = f[1], kind = f[2], area = tonumber(f[3]), cont0 = tonumber(f[4]),
            wx0 = tonumber(f[5]), wy0 = tonumber(f[6]), m = tonumber(f[7]),
            x = (tonumber(f[8]) or 0) / 100, y = (tonumber(f[9]) or 0) / 100,
            city = tonumber(f[10]), town = tonumber(f[11]), taxi = tonumber(f[12]), fac = Blank(f[13] or ""),
            discoverable = f[14] ~= "0",
            indoorOverride = f[15] == "mapzeroth-indoor" and d.indoor[tonumber(f[3])] or nil,
        }
        if n.id and n.area and n.m then
            d.nodes[n.id] = n
            if n.taxi then
                d.byTaxi[n.taxi] = n
            end
            -- inns and city centres are where a hearthstone or teleport lands:
            -- somewhere you leave from, never a stop on the way
            if n.kind ~= "inn" and n.kind ~= "settlement" then
                local list = d.byArea[n.area] or {}
                d.byArea[n.area] = list
                list[#list + 1] = n
            end
        end
    end)
    Rows(T.links, function(f)
        local a, b = d.nodes[f[1]], d.nodes[f[2]]
        if not (a and b) then
            return
        end
        local function Make()
            return {
                method = f[3], cost = tonumber(f[4]), ride = tonumber(f[5]), screens = tonumber(f[6]) or 0,
                fac = Blank(f[8] or ""), class = Blank(f[9] or ""), race = Blank(f[10] or ""),
                quest = tonumber(f[11]), key = f[1] .. ">" .. f[2], oneway = f[7] == "1" or nil,
                dialogue = f[12] == "1" or nil,
            }
        end
        AddLink(d, a, b, Make())
        if f[7] ~= "1" then
            local back = Make()
            back.key = f[2] .. ">" .. f[1]
            AddLink(d, b, a, back)
        end
    end)
    Rows(T.maps, function(f)
        d.mapArea[tonumber(f[1])] = tonumber(f[2])
    end)
    Rows(T.unmeasuredLinks, function(f)
        for _, pair in ipairs({{f[1], f[2]}, {f[2], f[1]}}) do
            for _, link in ipairs(d.out[pair[1]] or {}) do
                if link.to.id == pair[2] and link.method == f[3] then link.confidence = f[4] end
            end
        end
    end)
    Rows(T.regions, function(f)
        local m = tonumber(f[1])
        d.regions[m] = d.regions[m] or {}
        table.insert(d.regions[m], {
            area = tonumber(f[2]), x = tonumber(f[3]) / 100, y = tonumber(f[4]) / 100, r = tonumber(f[5]) / 100,
        })
    end)
    Rows(T.cities, function(f)
        d.cities[tonumber(f[1])] = f[2]
    end)
    Rows(T.towns, function(f)
        local inn = d.nodes[f[3]]
        if inn then
            table.insert(d.towns, { area = tonumber(f[2]), inn = inn, fac = Blank(f[4] or "") })
        end
    end)
    Rows(T.teleports, function(f)
        local n = d.nodes[f[2]]
        if n then
            table.insert(d.teleports, { spell = tonumber(f[1]), node = n, cost = tonumber(f[3]) or CAST })
        end
    end)
    Rows(T.factors, function(f)
        d.factors[tonumber(f[1])] = tonumber(f[2])
    end)
    Rows(T.levels, function(f)
        d.levels[tonumber(f[1])] = { tonumber(f[2]), tonumber(f[3]) }
    end)
    Rows(T.barriers, function(f)
        local m, cont = tonumber(f[1]), tonumber(f[6])
        if m and cont then
            d.barriers[#d.barriers + 1] = {
                { m = m, x = tonumber(f[2]) / 100, y = tonumber(f[3]) / 100,
                    cont0 = cont, wx0 = tonumber(f[7]), wy0 = tonumber(f[8]) },
                { m = m, x = tonumber(f[4]) / 100, y = tonumber(f[5]) / 100,
                    cont0 = cont, wx0 = tonumber(f[9]), wy0 = tonumber(f[10]) },
            }
        end
    end)
    local corridors = {}
    Rows(T.ghostCorridors, function(f)
        local points = corridors[f[1]] or {}
        corridors[f[1]] = points
        points[tonumber(f[2])] = { id = f[1] .. "_" .. f[2], corridor = f[1], kind = "pass",
            area = tonumber(f[3]), m = tonumber(f[4]), x = tonumber(f[5]) / 100, y = tonumber(f[6]) / 100,
            cont0 = tonumber(f[7]), wx0 = tonumber(f[8]), wy0 = tonumber(f[9]) }
    end)
    for _, id in ipairs((function()
        local ids = {}; for id in pairs(corridors) do ids[#ids + 1] = id end; table.sort(ids); return ids
    end)()) do d.ghostCorridors[#d.ghostCorridors + 1] = corridors[id] end
    if ns.Terrain then ns.Terrain.Load(T, d, Rows) end
    return d
end

local function Data()
    if data == nil then
        data = Parse() or false
        if data then
            ns.Fire("TRAVEL_LOADED", data)
        end
    end
    return data or nil
end
Travel.Data = Data

-- Players' own crossings (Trails.lua) join the network as zero-length links.
function Travel.AddCrossing(id, areaA, areaB, m, x, y)
    local d = Data()
    if not d or d.nodes[id .. "a"] or areaA == areaB then
        return
    end
    local a = { id = id .. "a", kind = "border", area = areaA, m = m, x = x, y = y, learned = true }
    local b = { id = id .. "b", kind = "border", area = areaB, m = m, x = x, y = y, learned = true }
    for _, n in ipairs({ a, b }) do
        d.nodes[n.id] = n
        d.byArea[n.area] = d.byArea[n.area] or {}
        table.insert(d.byArea[n.area], n)
    end
    AddLink(d, a, b, { method = "walk", cost = 0, screens = 0, key = a.id })
    AddLink(d, b, a, { method = "walk", cost = 0, screens = 0, key = b.id })
end

-- Where a node is in the world. The game's own map maths when it knows the
-- map (so it agrees with the player's position), the shipped numbers if not.
local function Pos(n)
    if n.wx == nil then
        local cont, wx, wy = Geo.MapToWorld(n.m, n.x, n.y)
        if cont then
            n.cont, n.wx, n.wy = cont, wx, wy
        else
            n.cont, n.wx, n.wy = n.cont0, n.wx0, n.wy0
        end
    end
    return n.cont, n.wx, n.wy
end

local function Dist(a, b)
    local ca, ax, ay = Pos(a)
    local cb, bx, by = Pos(b)
    if not (ca and cb and ax and bx) or ca ~= cb then
        return nil
    end
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end
Travel.Dist, Travel.Pos = Dist, Pos

-- Closest point on a polyline, measured by segment projection, with a
-- monotonic arc-length floor. The caller bounds the search at unreached gates.
function Travel.ProjectPolyline(points, here, first, last, minimum)
    first, last, minimum = first or 1, last or #points, minimum or 0
    local best, walked = nil, 0
    for i = 1, last - 1 do
        local ac, ax, ay = Pos(points[i])
        local bc, bx, by = Pos(points[i + 1])
        local length = ac == bc and ax and bx and sqrt((bx - ax)^2 + (by - ay)^2) or 0
        if i >= first and length > 0 and ac == here.cont and walked + length >= minimum then
            local t = ((here.wx - ax) * (bx - ax) + (here.wy - ay) * (by - ay)) / (length * length)
            t = max(max(0, (minimum - walked) / length), min(1, t))
            local x, y = ax + t * (bx - ax), ay + t * (by - ay)
            local distance = sqrt((here.wx - x)^2 + (here.wy - y)^2)
            local progress = walked + t * length
            if not best or distance < best.distance - 1e-6
                or (math.abs(distance - best.distance) <= 1e-6 and progress > best.progress) then
                best = { segment = i, t = t, progress = progress, distance = distance,
                    point = { cont = ac, wx = x, wy = y } }
            end
        end
        walked = walked + length
    end
    return best
end

function Travel.LookAhead(points, projection, yards, last)
    local point, remaining = projection.point, yards
    for i = projection.segment + 1, last or #points do
        local distance = Dist(point, points[i])
        if not distance then break end
        if distance > remaining then
            local cont, x, y = Pos(points[i])
            local t = remaining / distance
            return { cont = cont, wx = point.wx + t * (x - point.wx), wy = point.wy + t * (y - point.wy) }
        end
        remaining = remaining - distance
        local cont, x, y = Pos(points[i])
        point = { cont = cont, wx = x, wy = y }
    end
    local cont, x, y = Pos(point)
    return { cont = cont, wx = x, wy = y }
end

-- The area a map position is in: a part of a map that is its own area, the
-- map's area, or (for a cave or a small map) the area of a map above it.
-- Also returns the walled city's map when the position is inside one.
-- An optional registered node ID supplies captured indoor WMO context at
-- that exact anchor, without assigning a guessed footprint to nearby points.
-- Player/waypoint coordinates alone still use the surface map classification.
function Travel.AreaAt(m, x, y, nodeID)
    local d = Data()
    if not d or not m then
        return nil
    end
    local node = nodeID and d.nodes[nodeID]
    if node and node.indoorOverride and node.m == m and node.x == x and node.y == y then
        return node.area, node.city
    end
    local city
    for _ = 1, 6 do
        if d.cities[m] then
            city = city or m
        end
        for _, r in ipairs(d.regions[m] or {}) do
            local dx, dy = x - r.x, y - r.y
            if dx * dx + dy * dy <= r.r * r.r then
                return r.area, city
            end
        end
        local area = d.mapArea[m]
        if area then
            return area, city
        end
        local info = Geo.GetMapInfo(m)
        local parent = info and info.parentMapID
        if not parent or parent == 0 or (info.mapType or 3) < 3 then
            return nil
        end
        local px, py = Geo.TranslateToMap(m, x, y, parent)
        if not px then
            return nil
        end
        m, x, y = parent, px, py
    end
end

-- ---------------------------------------------------------------------------
-- What this character knows: flight paths, where the hearthstone goes, how
-- fast they travel
-- ---------------------------------------------------------------------------
local function Know()
    local db = ns.charDB
    if not db then
        return {}
    end
    if type(db.travel) ~= "table" then
        db.travel = {}
    end
    local k = db.travel
    if type(k.flights) ~= "table" then
        k.flights = {}
    end
    return k
end
Travel.Know = Know

local function FlightState(nodeID)
    return Know().flights[nodeID]
end

-- true: found it, false: hasn't, nil: don't know yet
function Travel.KnowsFlight(nodeID)
    return FlightState(nodeID)
end

function Travel.KnowsAnyFlight()
    return next(Know().flights) ~= nil
end

-- A flight master's map is open: the game says which points are found
-- (Current or Reachable). An Unreachable one with a flight from a found one
-- can't have been found either, or it would have been Reachable.
function Travel.ReadFlightMap()
    local d = Data()
    if not d or not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then
        return
    end
    local mapID = (GetTaxiMapID and select(2, pcall(GetTaxiMapID))) or nil
    if type(mapID) ~= "number" then
        local m = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local info = m and Geo.GetMapInfo(m)
        while info and info.mapType and info.mapType > 2 and info.parentMapID do
            m = info.parentMapID
            info = Geo.GetMapInfo(m)
        end
        mapID = m
    end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok or type(nodes) ~= "table" then
        return
    end
    local enum = Enum and Enum.FlightPathState or {}
    local CURRENT, REACHABLE = enum.Current or 0, enum.Reachable or 1
    local flights, found, unreachable = Know().flights, {}, {}
    for _, node in ipairs(nodes) do
        if node.nodeID then
            if node.state == CURRENT or node.state == REACHABLE then
                flights[node.nodeID] = true
                found[node.nodeID] = true
            else
                unreachable[node.nodeID] = true
            end
        end
    end
    for id in pairs(unreachable) do
        local n = d.byTaxi[id]
        for _, l in ipairs(n and d.out[n.id] or {}) do
            if l.method == "taxi" and l.to.taxi and found[l.to.taxi] then
                flights[id] = false
                break
            end
        end
    end
    Travel.flightNodes = nodes
    Travel.Invalidate()
    return nodes
end

-- plan again now (after a flight master's map has said what's found)
function Travel.Refresh()
    local wp = WP.GetActive()
    if wp and Travel.Enabled() then
        lastPlanTime = 0
        Travel.Steer(wp)
    end
end

-- The inn the hearthstone takes you to: where you bound, or the town the
-- game names (in your language) matched against our towns.
local bindCache = {}
local function BindNode()
    local d = Data()
    if not d then
        return nil
    end
    local k = Know()
    local name = GetBindLocation and GetBindLocation()
    if k.bind and k.bind.name == name and k.bind.m then
        local best, bestD
        local spot = { m = k.bind.m, x = k.bind.x, y = k.bind.y }
        for _, t in ipairs(d.towns) do
            local dd = Dist(spot, t.inn)
            if dd and dd < 400 and (not bestD or dd < bestD) then
                best, bestD = t.inn, dd
            end
        end
        if best then
            return best, name
        end
    end
    if not name or name == "" then
        return nil
    end
    if bindCache[name] == nil then
        bindCache[name] = false
        local getName = C_Map and C_Map.GetAreaInfo
        for _, t in ipairs(d.towns) do
            local areaName = getName and getName(t.area)
            if areaName and areaName == name then
                bindCache[name] = t.inn
                break
            end
        end
    end
    return bindCache[name] or nil, name
end
Travel.BindNode = BindNode

local function Ready(start, duration)
    start, duration = ns.Num(start), ns.Num(duration)
    if not start or not duration then
        return false
    end
    return start == 0 or (start + duration - GetTime()) <= 1
end

local function HearthReady()
    if not GetItemCount or GetItemCount(HEARTHSTONE) == 0 then
        return false
    end
    local cd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not cd then
        return true
    end
    local ok, start, duration = pcall(cd, HEARTHSTONE)
    return not ok or Ready(start, duration)
end

local function Knows(spell)
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spell)
        return ok and known or false
    end
    return IsSpellKnown and IsSpellKnown(spell) or false
end

local function SpellReady(spell)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and type(info) == "table" then
            start, duration = ns.Num(info.startTime), ns.Num(info.duration)
        end
    elseif GetSpellCooldown then
        start, duration = GetSpellCooldown(spell)
        start, duration = ns.Num(start), ns.Num(duration)
    end
    return Ready(start, duration)
end

-- remember how fast this character rides, for when they aren't mounted yet
local function NoteSpeed()
    if not (GetUnitSpeed and IsMounted) or not IsMounted() then
        return
    end
    local _, run = GetUnitSpeed("player")
    run = ns.Num(run)
    if run and run > RUN_SPEED and run < 40 then
        Know().mountSpeed = floor(run * 10 + 0.5) / 10
    end
end

-- everything about the player a plan depends on
local function Context()
    local c = {}
    c.faction = UnitFactionGroup and UnitFactionGroup("player")
    if UnitClass then
        local _, class = UnitClass("player")
        c.class = ns.Plain(class)
    end
    if UnitRace then
        local _, race = UnitRace("player")
        c.race = ns.Plain(race)
    end
    c.level = (UnitLevel and ns.Num(UnitLevel("player"))) or 1
    local run = RUN_SPEED
    if GetUnitSpeed then
        local _, r = GetUnitSpeed("player")
        run = max(RUN_SPEED, ns.Num(r) or RUN_SPEED)
    end
    c.run = run
    c.ground = max(run, Know().mountSpeed or 0)
    c.flightFactor = Knows(FREQUENT_FLIER) and (1 / 1.2) or 1
    c.dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) and true or false
    c.ghost = (UnitIsGhost and UnitIsGhost("player")) and true or false
    if c.ghost then c.ground = c.run end -- remembered mount speed does not apply to spirits
    c.flights = not c.dead and ns.Get("travelFlights")
    c.boats = not c.dead and ns.Get("travelBoats")
    c.jumps = {}
    if not c.dead and ns.Get("travelHearth") then
        local inn, name = BindNode()
        if inn and (HearthReady() or (Knows(ASTRAL_RECALL) and SpellReady(ASTRAL_RECALL))) then
            c.jumps[#c.jumps + 1] = { node = inn, cost = CAST + LOADING, kind = "hearth", name = name }
        end
        local d = Data()
        for _, t in ipairs(d and d.teleports or {}) do
            if Knows(t.spell) and SpellReady(t.spell) then
                c.jumps[#c.jumps + 1] = { node = t.node, cost = t.cost + LOADING, kind = "teleport", spell = t.spell }
            end
        end
    end
    return c
end

-- ---------------------------------------------------------------------------
-- Planning
-- ---------------------------------------------------------------------------
local function Hostile(cityMap, c)
    local d = data
    local owner = cityMap and d and d.cities[cityMap]
    return owner and owner ~= "" and c.faction and owner ~= c.faction
end

local function Usable(l, c, unlockedFrom)
    if l.ghostOnly and not c.ghost then return false end
    if l.fac and l.fac ~= c.faction then
        return false
    end
    if l.class and l.class ~= c.class then
        return false
    end
    if l.race and l.race ~= c.race then
        return false
    end
    if l.quest then
        local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
        if not (done and done(l.quest)) then
            return false
        end
    end
    local m = l.method
    if m == "taxi" then
        if not c.flights then
            return false
        end
        if not l.dialogue and (l.from.discoverable == false or l.to.discoverable == false
            or (FlightState(l.from.taxi) ~= true and not unlockedFrom) or FlightState(l.to.taxi) ~= true) then
            return false
        end
        return not (l.from.fac and l.from.fac ~= c.faction) and not (l.to.fac and l.to.fac ~= c.faction)
    end
    if m == "ship" or m == "zeppelin" or m == "tram" then
        return c.boats and true or false
    end
    return true
end

local function Factor(a, b)
    local f = data.factors
    return ((f[a.m] or DEFAULT_FACTOR) + (f[b.m] or DEFAULT_FACTOR)) / 2
end

local function WalkCost(a, b, c)
    local dd = Dist(a, b)
    if not dd then
        return nil
    end
    local speed = data.indoor[b.area] and c.run or c.ground
    -- Zone danger is not elapsed time. Actual access restrictions belong
    -- in Usable; inflating walks can select a slower flight or detour.
    return dd * Factor(a, b) / speed
end

-- Preference cost only. Never put this surcharge into elapsed seconds.
-- Check both endpoint maps (including a high-level area being left) and
-- exposure along the segment near enemy towns, even if neither stop is in town.
local function Danger(a, b, c, seconds)
    if c.ghost then return 0 end -- living-enemy exposure is not a corpse-run cost
    local la, lb = data.levels[a.m], data.levels[b.m]
    if Hostile(a.city, c) or Hostile(b.city, c) then
        return seconds * DANGER_PENALTY, a.city or b.city, "city"
    end
    local high = (la and la[1] > (c.level or 1) + DANGER_LEVELS and a.m)
        or (lb and lb[1] > (c.level or 1) + DANGER_LEVELS and b.m)
    local cont, ax, ay = Pos(a)
    local bc, bx, by = Pos(b)
    local exposure, town = 0, nil
    if cont and cont == bc and ax and ay and bx and by then
        local dx, dy = bx - ax, by - ay
        local length2 = dx * dx + dy * dy
        for _, t in ipairs(data.towns) do
            if (t.fac == "Alliance" or t.fac == "Horde") and c.faction and t.fac ~= c.faction then
                local tc, tx, ty = Pos(t.inn)
                if tc == cont and tx and ty then
                    local fraction = 0
                    if length2 == 0 then
                        if (ax - tx)^2 + (ay - ty)^2 <= TOWN_RADIUS^2 then fraction = 1 end
                    else
                        local projection = ((tx - ax) * dx + (ty - ay) * dy) / length2
                        local perpendicular2 = (tx - ax)^2 + (ty - ay)^2 - projection^2 * length2
                        if perpendicular2 < TOWN_RADIUS^2 then
                            local half = sqrt((TOWN_RADIUS^2 - max(0, perpendicular2)) / length2)
                            fraction = max(0, min(1, projection + half) - max(0, projection - half))
                        end
                    end
                    if fraction > exposure then exposure, town = fraction, t.area end
                end
            end
        end
    end
    if town then return seconds * DANGER_PENALTY * (high and 1 or exposure), town, "town" end
    if high then return seconds * DANGER_PENALTY, high, "level" end
    return 0
end
Travel.Danger = Danger

-- Areas allow implicit walking edges, but known ridges/cliffs can cut an
-- area in two. Test in world coordinates so overlapping zone maps agree.
-- Explicit links remain authoritative (a surveyed pass, tunnel or gate can
-- cross a barrier); only inferred straight walks are rejected here.
local function CanWalk(a, b)
    if ns.Terrain and not ns.Terrain.Decide(a, b) then return false end
    local cont, ax, ay = Pos(a)
    local bc, bx, by = Pos(b)
    if not cont or cont ~= bc or not ax or not ay or not bx or not by then
        return false
    end
    if ax == bx and ay == by then
        return true
    end
    local function Side(px, py, qx, qy, rx, ry)
        return (qx - px) * (ry - py) - (qy - py) * (rx - px)
    end
    for _, barrier in ipairs(data.barriers) do
        local ac, cx, cy = Pos(barrier[1])
        local dc, dx, dy = Pos(barrier[2])
        if cont == ac and cont == dc and cx and cy and dx and dy
            and max(min(ax, bx), min(cx, dx)) <= min(max(ax, bx), max(cx, dx)) + 1e-8
            and max(min(ay, by), min(cy, dy)) <= min(max(ay, by), max(cy, dy)) + 1e-8 then
            local s1, s2 = Side(ax, ay, bx, by, cx, cy), Side(ax, ay, bx, by, dx, dy)
            local s3, s4 = Side(cx, cy, dx, dy, ax, ay), Side(cx, cy, dx, dy, bx, by)
            -- Map/world round trips must not make an exactly blocked chord
            -- appear parallel a few floating-point units beside its constraint.
            if min(s1,s2) <= 1e-7 and max(s1,s2) >= -1e-7
                and min(s3,s4) <= 1e-7 and max(s3,s4) >= -1e-7 then
                return false
            end
        end
    end
    return true
end

Travel.CanWalk = function(a, b) return Data() and CanWalk(a, b) or false end

-- seconds a link takes when you get to its start at `at` seconds from now
local function LinkCost(l, at, c, arrivedBy)
    local m = l.method
    if m == "gate" then
        return 0
    elseif m == "walk" or m == "lift" then
        if l.cost and l.cost > 0 then
            return l.cost
        end
        return WalkCost(l.from, l.to, c) or 0
    elseif m == "taxi" then
        local cost = (l.cost or 0) * c.flightFactor
        -- a trip through several flight points is one flight
        if l.dialogue or arrivedBy ~= "taxi" then
            cost = cost + TAXI_TALK
        end
        return cost
    end
    local cost = (l.cost or 0) + (l.screens or 0) * LOADING
    -- a boat or zeppelin whose timetable players have seen: wait for the next one
    local T = ns.Trails
    if l.ride and T and T.NextDeparture then
        local wait = T.NextDeparture(l.key, at)
        if wait then
            cost = wait + l.ride + (l.screens or 0) * LOADING
        end
    end
    return cost
end

-- a small binary heap of { cost, node }
local function Push(h, cost, n)
    local i = #h + 1
    h[i] = { cost, n }
    while i > 1 do
        local p = floor(i / 2)
        if h[p][1] <= h[i][1] then
            break
        end
        h[p], h[i] = h[i], h[p]
        i = p
    end
end

local function Pop(h)
    local top = h[1]
    local last = table.remove(h)
    if #h > 0 then
        h[1] = last
        local i, n = 1, #h
        while true do
            local l, r, s = i * 2, i * 2 + 1, i
            if l <= n and h[l][1] < h[s][1] then
                s = l
            end
            if r <= n and h[r][1] < h[s][1] then
                s = r
            end
            if s == i then
                break
            end
            h[s], h[i] = h[i], h[s]
            i = s
        end
    end
    return top
end

-- The quickest way from `start` to `goal` (both { area, city, cont, wx, wy }
-- places). Returns the list of stops { node, via, at } or nil.
local function Search(start, goal, c, allowUncertain)
    if ns.Terrain then ns.Terrain.Refresh() end
    local d = data
    local corridorOut, joins = {}, {}
    local function Connector(point, endpoint, id)
        local x, y = Geo.WorldToMap(point.cont, point.wx, point.wy, endpoint.m)
        if not x then return nil end
        local area, city = Travel.AreaAt(endpoint.m, x, y)
        if area ~= endpoint.area or city ~= endpoint.city or not CanWalk(point, endpoint) then return nil end
        return { id = id, corridor = id, kind = "pass", m = endpoint.m, x = x, y = y,
            area = area, city = city, cont = point.cont, wx = point.wx, wy = point.wy }
    end
    if c.ghost then
        for _, points in ipairs(d.ghostCorridors) do
            for i = 1, #points - 1 do
                local a, b = points[i], points[i + 1]
                local stops = { { t = 0, node = a }, { t = 1, node = b } }
                for _, endpoint in ipairs({start, goal}) do
                    local projection = Travel.ProjectPolyline({a, b}, endpoint)
                    if projection and projection.distance <= CORRIDOR_JOIN then
                        local node = Connector(projection.point, endpoint, a.corridor)
                        if node then
                            stops[#stops + 1] = { t = projection.t, node = node }
                            if endpoint == start then joins[#joins + 1] = node
                            else node.exit = true end
                        end
                    end
                end
                table.sort(stops, function(x, y) return x.t < y.t end)
                for j = 1, #stops - 1 do
                    local from, to = stops[j].node, stops[j + 1].node
                    corridorOut[from] = corridorOut[from] or {}
                    corridorOut[from][#corridorOut[from] + 1] = { from = from, to = to, method = "walk",
                        ghostOnly = true, corridor = a.corridor, key = a.corridor }
                end
            end
        end
    end
    if not c.ghost and ns.Terrain then
        -- Exact living traces are private, bidirectional polylines. Rejoin a
        -- nearby segment during replanning; do not walk back to its origin.
        for _,corridor in ipairs(ns.Terrain.Corridors()) do
            local proof,record=corridor.e,corridor.r
            local points={}
            for i,p in ipairs(record.points) do
                points[i]={id=proof.key .. ":" .. i,corridor=proof.key,terrainOnly=true,kind="pass",
                    cont=proof.a.cont,wx=p[1],wy=p[2],m=proof.a.node.m,area=proof.a.node.area,city=proof.a.node.city}
            end
            local forward=(record.points[1][1]-proof.a.wx)^2+(record.points[1][2]-proof.a.wy)^2
                <= (record.points[#record.points][1]-proof.a.wx)^2+(record.points[#record.points][2]-proof.a.wy)^2
            local function Link(a,b)
                corridorOut[a]=corridorOut[a] or {}
                corridorOut[a][#corridorOut[a]+1]={from=a,to=b,method="walk",terrain=true,
                    observedGround=true,corridor=proof.key,evidenceKey=proof.key}
            end
            local first,last=forward and proof.a.node or proof.b.node,forward and proof.b.node or proof.a.node
            Link(first,points[1]);Link(points[1],first);Link(last,points[#points]);Link(points[#points],last)
            for i=1,#points-1 do
                local a,b=points[i],points[i+1]
                local stops={{t=0,node=a},{t=1,node=b}}
                for _,endpoint in ipairs({start,goal}) do
                    local projection=Travel.ProjectPolyline({a,b},endpoint)
                    if projection and projection.distance<=3 then
                        local node=Connector(projection.point,endpoint,proof.key)
                        if node then
                            stops[#stops+1]={t=projection.t,node=node}
                            if endpoint==start then joins[#joins+1]=node else node.exit=true end
                        end
                    end
                end
                table.sort(stops,function(x,y) return x.t<y.t end)
                for j=1,#stops-1 do Link(stops[j].node,stops[j+1].node);Link(stops[j+1].node,stops[j].node) end
            end
        end
    end
    -- Ground, unlocked and aboard arrivals have different onward costs.
    -- In particular, the cheapest arrival at a connecting FM need not give
    -- the cheapest flight: staying aboard avoids another boarding charge.
    local states = {}
    local function State(node, mode)
        mode = mode or "ground"
        local list = states[node] or {}
        states[node] = list
        if not list[mode] then list[mode] = { node = node, mode = mode } end
        return list[mode]
    end
    local first = State(start)
    local penalties = { [first] = 0 }
    local best, elapsed, risks, via, prev, done = { [first] = 0 }, { [first] = 0 }, { [first] = 0 }, {}, {}, {}, {}
    -- Timetable waits depend on arrival time, not time plus danger. Preserve
    -- nondominated arrival/risk labels so a safer arrival catching the same
    -- departure is not discarded by a cheaper score at the boarding point.
    local frontiers = c.preference == "safer" and { [start] = { ground = { first } } }
    local heap = {}
    Push(heap, 0, first)
    local function Relax(u, node, cost, how, mode)
        if not cost then return end
        local walking = how == "walk" or (type(how) == "table" and WALKING[how.method])
        local surcharge, proof, observation = 0, nil, nil
        if walking and ns.Terrain and not (type(how) == "table" and (how.ghostOnly or how.observedGround)) then
            local ok, uncertainty
            ok, uncertainty, proof, observation = ns.Terrain.Decide(u.node, node,
                type(how) == "table" and how.groundPolyline and "polyline" or type(how) == "table")
            if not ok or (uncertainty >= 1 and not allowUncertain) then return end
            surcharge = uncertainty > 0 and uncertainty * (3 * cost + 120) or 0
            if proof then
                local link = type(how) == "table" and how or {method="walk",from=u.node,to=node}
                local copy = {}; for k,v in pairs(link) do copy[k]=v end
                copy.terrain, copy.evidenceKey, copy.provenance = true, proof.key, proof.provenance
                copy.implicit = how == "walk" or copy.implicit
                if observation and observation.points then
                    copy.observed = observation.points
                    local points = observation.points
                    local _,sx,sy=Pos(u.node);local _,tx,ty=Pos(node)
                    local forward=(points[1][1]-sx)^2+(points[1][2]-sy)^2 <= (points[#points][1]-sx)^2+(points[#points][2]-sy)^2
                    local firstPoint,lastPoint=points[forward and 1 or #points],points[forward and #points or 1]
                    local length = sqrt((firstPoint[1]-sx)^2+(firstPoint[2]-sy)^2)+sqrt((lastPoint[1]-tx)^2+(lastPoint[2]-ty)^2)
                    for i=2,#points do length=length+sqrt((points[i][1]-points[i-1][1])^2+(points[i][2]-points[i-1][2])^2) end
                    -- Keep the actually walked bends; never certify the endpoint chord.
                    cost = length * Factor(u.node,node) / (data.indoor[node.area] and c.run or c.ground)
                end
                how = copy
            end
        end
        local risk = walking and (c.preference == "safer" or c.measureDanger) and Danger(u.node, node, c, cost) or 0
        local g = best[u] + cost + surcharge + (c.preference == "safer" and risk or 0)
        local v
        if frontiers then
            mode = mode or "ground"
            local modes = frontiers[node] or {}; frontiers[node] = modes
            local labels = modes[mode] or {}; modes[mode] = labels
            local arrival, exposure, geometry = elapsed[u] + cost, risks[u] + risk, penalties[u] + surcharge
            for _, label in ipairs(labels) do
                if not label.discarded and elapsed[label] <= arrival + 1e-6
                    and risks[label] <= exposure + 1e-6 and penalties[label] <= geometry + 1e-6 then return end
            end
            for _, label in ipairs(labels) do
                if arrival <= elapsed[label] + 1e-6 and exposure <= risks[label] + 1e-6 and geometry <= penalties[label] + 1e-6 then
                    label.discarded = true
                end
            end
            v = { node = node, mode = mode }; labels[#labels + 1] = v
        else
            v = State(node, mode)
            if done[v] then return end
        end
        if best[v] == nil or g < best[v] - 1e-6 or (c.preference == "safer"
            and math.abs(g - best[v]) <= 1e-6 and risks[u] + risk < risks[v] - 1e-6) then
            best[v], via[v], prev[v] = g, how, u
            elapsed[v], risks[v], penalties[v] = elapsed[u] + cost, risks[u] + risk, penalties[u] + surcharge
            Push(heap, g, v)
        end
    end
    local expanded, finish = 0, nil
    while heap[1] do
        local top = Pop(heap)
        local u = top[2]
        if finish and top[1] > best[finish] + 1e-6 then break end
        if not done[u] and not u.discarded and top[1] <= (best[u] or huge) then
            done[u] = true
            local n = u.node
            if n == goal then
                if not finish or risks[u] < risks[finish] - 1e-6 then finish = u end
                if not frontiers then break end
            else
                if expanded >= 4000 then break end
                expanded = expanded + 1
                -- walking inside the area, on the same side of a city wall
                if n.area and not n.corridor and not n.terrainOnly then
                    for _, v in ipairs(d.byArea[n.area] or {}) do
                        if v ~= n and not v.terrainOnly and v.city == n.city
                            and (not Hostile(v.city, c) or v.city == goal.city or v.city == start.city)
                            and CanWalk(n, v) then
                            Relax(u, v, WalkCost(n, v, c), "walk")
                        end
                    end
                    if goal.area == n.area and goal.city == n.city and CanWalk(n, goal) then
                        Relax(u, goal, WalkCost(n, goal, c), "walk")
                    end
                end
                if u == first then
                    for _, node in ipairs(joins) do Relax(u, node, WalkCost(n, node, c), "walk") end
                elseif n.exit then
                    Relax(u, goal, WalkCost(n, goal, c), "walk")
                end
                for _, link in ipairs(corridorOut[n] or {}) do
                    Relax(u, link.to, WalkCost(n, link.to, c), link)
                end
                -- Terrain points have only indexed neighbours. Exact endpoint
                -- connectors do not expose the supplemental all-to-all graph.
                if n.terrainOnly and Dist(n, goal) and Dist(n, goal) <= 3 and CanWalk(n, goal) then
                    Relax(u, goal, WalkCost(n, goal, c), "walk")
                end
                if u == first then
                    for _, v in pairs(d.nodes) do
                        if v.terrainOnly and Dist(n,v) and Dist(n,v) <= 3 and CanWalk(n,v) then
                            Relax(u,v,WalkCost(n,v,c),"walk")
                        end
                    end
                end
                -- gates, crossings, flights, boats...
                for _, l in ipairs(n.id and d.out[n.id] or {}) do
                    if Usable(l, c, u.mode == "unlocked") then
                        Relax(u, l.to, LinkCost(l, elapsed[u], c, u.mode == "taxi" and "taxi" or "walk"),
                            l, l.method == "taxi" and (l.dialogue and "dialogue" or "taxi") or "ground")
                    end
                end
                -- Discover only after physically reaching a friendly FM. This
                -- self edge is an explicit action, not a change to saved knowledge.
                if u.mode == "ground" and n.taxi and n.discoverable ~= false and c.flights and FlightState(n.taxi) ~= true
                    and (not n.fac or n.fac == c.faction) and not Hostile(n.city, c) then
                    Relax(u, n, TAXI_UNLOCK, { kind = "discover" }, "unlocked")
                end
                -- the hearthstone and teleports, from where you stand
                if u == first then
                    for _, j in ipairs(c.jumps) do
                        Relax(u, j.node, j.cost, j)
                    end
                end
            end
        end
    end
    Travel.lastExpanded = expanded
    if not finish then
        if not allowUncertain then return Search(start, goal, c, true) end
        return nil
    end
    local path, n = {}, finish
    while n do
        table.insert(path, 1, { node = n.node, via = via[n], at = elapsed[n], risk = risks[n], terrainPenalty = penalties[n] })
        n = prev[n]
    end
    local expandedPath = { path[1] }
    for i=2,#path do
        local entry, previous = path[i], path[i-1]
        local how = type(entry.via) == "table" and entry.via
        if how and how.observed then
            local pts = how.observed
            local _,ax,ay = Pos(previous.node)
            local reverse = (pts[#pts][1]-ax)^2+(pts[#pts][2]-ay)^2 < (pts[1][1]-ax)^2+(pts[1][2]-ay)^2
            local length, distances = 0, {}
            for j=2,#pts do length=length+sqrt((pts[j][1]-pts[j-1][1])^2+(pts[j][2]-pts[j-1][2])^2);distances[j]=length end
            for j=2,#pts-1 do
                local k = reverse and #pts-j+1 or j
                local fraction = length > 0 and (reverse and length-(distances[k] or 0) or distances[k] or 0)/length or 0
                local node = {cont=previous.node.cont or select(1,Pos(previous.node)),wx=pts[k][1],wy=pts[k][2],
                    m=entry.node.m,area=entry.node.area,city=entry.node.city,kind="pass",terrainOnly=true}
                expandedPath[#expandedPath+1] = {node=node,via={method="walk",terrain=true,observedGround=true,
                    evidenceKey=how.evidenceKey,from=expandedPath[#expandedPath].node,to=node},
                    at=previous.at+fraction*(entry.at-previous.at),risk=previous.risk+fraction*(entry.risk-previous.risk),
                    terrainPenalty=previous.terrainPenalty}
            end
            local retained = {};for k,v in pairs(how) do retained[k]=v end
            retained.from,retained.observed,retained.observedGround = expandedPath[#expandedPath].node,nil,true
            entry.via = retained
        end
        expandedPath[#expandedPath+1] = entry
    end
    return expandedPath, elapsed[finish], risks[finish], penalties[finish]
end
Travel.Search = Search

-- Pure candidate planning: no active-plan state or hysteresis. The safe
-- candidate always comes from the danger-aware search, with no detour cap.
function Travel.Routes(start, goal, c, preference)
    local ctx = {}; for k, v in pairs(c) do ctx[k] = v end
    ctx.preference, ctx.measureDanger = "fastest", true
    local fp, ft, fr, fg = Search(start, goal, ctx)
    if not fp then return {} end
    local fastest = { path = fp, total = ft, risk = fr, terrainPenalty = fg, preference = "fastest" }
    ctx.preference = "safer"
    local sp, st, sr, sg = Search(start, goal, ctx)
    if not sp then return { fastest }, fastest end
    local safer = { path = sp, total = st, risk = sr, terrainPenalty = sg, preference = "safer" }
    return { fastest, safer }, preference == "fastest" and fastest or safer
end

function Travel.CanOffer(fast, safe)
    return fast and safe and fast.risk > safe.risk + 1e-6
        and safe.total - fast.total >= max(OFFER_SECONDS, safe.total * OFFER_FRACTION) - 1e-6
end

-- ---------------------------------------------------------------------------
-- Names for what the route says
-- ---------------------------------------------------------------------------
local taxiNames
local function FlightName(n)
    if not taxiNames then
        taxiNames = {}
        for _, m in ipairs({ 1414, 1415 }) do
            local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, m)
            for _, node in ipairs(ok and type(list) == "table" and list or {}) do
                if node.nodeID and node.name then
                    taxiNames[node.nodeID] = node.name
                end
            end
        end
    end
    return (n.taxi and taxiNames[n.taxi]) or Geo.GetMapName(n.m)
end

local function PlaceName(n)
    if n.town and C_Map and C_Map.GetAreaInfo then
        local name = C_Map.GetAreaInfo(n.town)
        if name and name ~= "" then
            return name
        end
    end
    if n.kind == "taxi" then
        return FlightName(n)
    end
    return Geo.GetMapName(n.m)
end
Travel.PlaceName = PlaceName

local function SpellName(spell)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spell)
        if ok and name then
            return name
        end
    end
    return GetSpellInfo and GetSpellInfo(spell) or ("#" .. spell)
end

local METHOD_TEXT = {
    ship = "TRAVEL_BOAT", zeppelin = "TRAVEL_ZEPPELIN", tram = "TRAVEL_TRAM", portal = "TRAVEL_PORTAL",
    transition = "TRAVEL_PORTAL", taxi = "TRAVEL_FLY",
}
local GOTO_TEXT = {
    ship = "TRAVEL_TO_BOAT", zeppelin = "TRAVEL_TO_ZEPPELIN", tram = "TRAVEL_TO_TRAM", taxi = "TRAVEL_TO_FLIGHT",
    portal = "TRAVEL_TO_PORTAL", transition = "TRAVEL_TO_PORTAL",
}

-- where a ride starting at stop i ends: flights through several points are one
local function RideEnd(path, i)
    local method = path[i].via.method
    local j = i
    while method == "taxi" and path[j + 1] and type(path[j + 1].via) == "table" and path[j + 1].via.method == "taxi" do
        -- Dialog flights are separate tickets, never a taxi-map flight chain.
        if path[j].via.dialogue or path[j + 1].via.dialogue then break end
        j = j + 1
    end
    return path[j].node, j
end

Travel.RideEnd = RideEnd

-- What to do at stop i of a path, as one line
local function StepText(path, i, wpName)
    local e = path[i]
    local how = e.via
    if type(how) == "table" and how.kind == "discover" then
        return L.TRAVEL_UNLOCK_FLIGHT:format(PlaceName(e.node))
    elseif type(how) == "table" and how.kind == "hearth" then
        return L.TRAVEL_HEARTH:format(how.name or PlaceName(e.node))
    elseif type(how) == "table" and how.kind == "teleport" then
        return L.TRAVEL_TELEPORT:format(SpellName(how.spell))
    elseif type(how) == "table" and how.dialogue then
        return L.TRAVEL_DIALOG_FLIGHT:format(PlaceName(e.node))
    elseif type(how) == "table" and TRANSPORT[how.method] then
        local to = RideEnd(path, i)
        return L[METHOD_TEXT[how.method]]:format(PlaceName(to))
    elseif type(how) == "table" and how.method == "lift" then
        return L.TRAVEL_LIFT
    end
    -- walking to stop i: say what comes after it
    if i == #path then
        return wpName
    end
    local n, nextE = e.node, path[i + 1]
    local nh = nextE.via
    if type(nh) == "table" and nh.kind == "discover" then
        return L.TRAVEL_UNLOCK_FLIGHT:format(PlaceName(n))
    elseif type(nh) == "table" and TRANSPORT[nh.method] then
        local to = RideEnd(path, i + 1)
        return L[GOTO_TEXT[nh.method]]:format(PlaceName(to))
    elseif type(nh) == "table" and nh.method == "lift" then
        return L.TRAVEL_TO_LIFT
    elseif type(nh) == "table" and nh.method == "gate" then
        if nextE.node.city then
            return L.TRAVEL_ENTER:format(Geo.GetMapName(nextE.node.city))
        end
        return L.TRAVEL_LEAVE:format(Geo.GetMapName(n.city or n.m))
    elseif type(nh) == "table" and nh.method == "walk" and nextE.node.area ~= n.area then
        return L.TRAVEL_HEAD_TO:format(Geo.GetMapName(nextE.node.m))
    end
    return L.TRAVEL_WALK_TO:format(Geo.GetMapName(n.m))
end
Travel.StepText = StepText

-- ---------------------------------------------------------------------------
-- Following a plan
-- ---------------------------------------------------------------------------
local plan -- { wp, path, total, built, index, target }
local lastPlanTime, generation, planGeneration, planWp = 0, 0, -1, nil
local reached = {} -- stops you've been at on the way to this waypoint
local atDock -- { link, t }: the last dock the plan sent you to
local riding -- { link, from, to, until } while aboard a boat, zeppelin or flight
local samples = {} -- the last few player positions, to tell a moving boat from walking

function Travel.Invalidate()
    generation = generation + 1
end

function Travel.Enabled()
    return ns.Get("realRoutes") and Data() ~= nil
end

local function PlayerPlace()
    local m, x, y = Geo.GetPlayerMapPosition()
    if not m then
        return nil
    end
    -- from the map, the way the stops' positions are worked out (a phased
    -- copy of a continent has an instance id of its own)
    local cont, wx, wy = Geo.MapToWorld(m, x, y)
    if not cont then
        cont, wx, wy = Geo.GetPlayerWorld()
    end
    if not cont then
        return nil
    end
    local area, city = Travel.AreaAt(m, x, y)
    return { id = nil, area = area, city = city, cont = cont, wx = wx, wy = wy, m = m, x = x, y = y, player = true }
end

local function GoalPlace(wp)
    local cont, wx, wy = Geo.MapToWorld(wp.m, wp.x, wp.y)
    if not cont then
        return nil
    end
    local area, city = Travel.AreaAt(wp.m, wp.x, wp.y)
    return { area = area, city = city, cont = cont, wx = wx, wy = wy, m = wp.m, x = wp.x, y = wp.y, goal = true }
end

local function PlainWalk(how)
    return how == "walk" or (type(how) == "table" and how.method == "walk")
end

local function OptionalStop(e, nextE)
    local kind = e.node.kind
    return PlainWalk(e.via) and nextE and PlainWalk(nextE.via)
        and (kind == "pass" or kind == "border" or kind == nil)
        and not e.node.taxi and not e.node.corridor and not e.node.terrainOnly
        and not (type(e.via) == "table" and e.via.terrain)
end

local function Approach(here, to)
    return here.area == to.area and here.city == to.city and CanWalk(here, to)
end

-- the stop the arrow points at: the first one not already behind you
local function Target(path, here, index)
    local i = index or 2
    while i < #path do
        local e, nextE = path[i], path[i + 1]
        local walkedTo = e.via == "walk" or (type(e.via) == "table" and WALKING[e.via.method])
        if not walkedTo then
            break
        end
        -- Reached walking hints stay behind us, but a new approach to an
        -- action/entrance must actually reach it again before advancing.
        if not reached[e.node] or not OptionalStop(e, nextE) or not Approach(here, nextE.node) then
            local near = (e.node.terrainOnly or type(e.via) == "table" and e.via.terrain) and 3
                or (type(nextE.via) == "table" and TRANSPORT[nextE.via.method]) and BOARD_NEAR or NEAR
            local dd = Dist(here, e.node)
            if not dd or dd > near then
                break
            end
            -- once there, it stays behind you (no turning back for it)
            if e.node.id then
                reached[e.node] = true
            end
        end
        i = i + 1
    end
    return i
end

-- Progress belongs to segments, not the nearest vertex. Stop the projection
-- at the next action/doorway or road bend whose shortcut is not walkable.
local function ProjectPlan(p, here)
    local path, index = p.path, p.index
    if not here or not index or not PlainWalk(path[index].via) then return nil end
    p.points = p.points or {}
    for i, e in ipairs(path) do p.points[i] = e.node end
    local limit = index
    while limit < #path do
        local e, nextE = path[limit], path[limit + 1]
        local observed = p.c.ghost and e.node.corridor
            and e.node.corridor == nextE.node.corridor
        local proof = p.c.ghost and ns.Terrain and ns.Terrain.Evidence(e.node, nextE.node)
        local verified = proof and proof.state == "TERRAIN_CLEAR" and PlainWalk(nextE.via)
            and e.node.kind ~= "entrance" and not e.node.taxi
        local previous = path[limit - 1]
        local crossed = p.c.ghost and previous and e.node.kind == "border" and PlainWalk(e.via)
            and previous.node.area ~= e.node.area and (Dist(here, e.node) or math.huge) <= CORRIDOR_JOIN
        local crossing = crossed and ns.Terrain and ns.Terrain.Evidence(previous.node, e.node)
        crossed = crossing and crossing.state == "TERRAIN_CLEAR" and CanWalk(here, nextE.node)
        if not observed and not verified and not crossed and (not OptionalStop(e, nextE) or not Approach(here, nextE.node)) then break end
        limit = limit + 1
    end
    local projection = Travel.ProjectPolyline(p.points, here, index - 1, limit, p.progress)
    if not projection then return nil end
    p.progress = projection.progress
    local nextIndex = projection.segment + 1
    for i = index, nextIndex - 1 do reached[path[i].node] = true end
    p.index, p.target = nextIndex, path[nextIndex]
    local aim = Travel.LookAhead(p.points, projection, LOOK_AHEAD, limit)
    local observed = p.c.ghost and path[projection.segment].node.corridor
        and path[projection.segment].node.corridor == path[nextIndex].node.corridor
    -- A look-ahead chord around a bend must not cut a wall or ridge. Explicit
    -- crossings retain their next gate; observed ghost legs retain their mode.
    if not observed and not CanWalk(here, aim) then
        local cont, wx, wy = Pos(path[nextIndex].node)
        aim = { cont = cont, wx = wx, wy = wy }
    end
    return projection, aim
end

-- Reprice only the followed suffix, including current waits, access rules
-- and discovery state. A stale/blocked suffix is never retained.
local function Reprice(p, here, c, index, shortcut)
    local t = p.path[index]
    if not t then return nil end
    local path = { { node = here, at = 0, risk = 0 } }
    local elapsed, risk, mode, unlocked = 0, 0, "walk", false
    local corridor = type(t.via) == "table" and t.via.corridor
    local firstWalk = shortcut or (PlainWalk(t.via) and not corridor and Approach(here, t.node))
    if corridor then
        -- A retained observed leg is joined along its segment, under the same
        -- distance/area/barrier rules as search, never by skipping a bend.
        local from = p.path[index - 1].node
        local projection = Travel.ProjectPolyline({ from, t.node }, here)
        local x, y
        if projection then x, y = Geo.WorldToMap(projection.point.cont, projection.point.wx, projection.point.wy, here.m) end
        local area, city
        if x and y then area, city = Travel.AreaAt(here.m, x, y) end
        if not c.ghost or not projection or projection.distance > CORRIDOR_JOIN
            or area ~= here.area or city ~= here.city
            or not CanWalk(here, projection.point) then return nil end
        local join = { m = here.m, x = x, y = y, area = area, city = city,
            cont = projection.point.cont, wx = projection.point.wx, wy = projection.point.wy,
            corridor = corridor, kind = "pass" }
        elapsed = WalkCost(here, join, c)
        if not elapsed then return nil end
        path[#path + 1] = { node = join, via = "walk", at = elapsed, risk = 0 }
        firstWalk = true
    end
    if not firstWalk then
        local from = p.path[index - 1].node
        local dd = Dist(here, from)
        if not dd or dd > BOARD_NEAR or from.area ~= here.area or from.city ~= here.city
            or not CanWalk(here, from) then return nil end
        elapsed = WalkCost(here, from, c)
        if not elapsed then return nil end
        risk = Danger(here, from, c, elapsed)
        path[#path + 1] = { node = from, via = "walk", at = elapsed, risk = risk }
    end
    for i = index, #p.path do
        local e, from = p.path[i], path[#path].node
        local how, seconds = e.via, nil
        if type(how) == "table" and how.terrain then return nil end -- rebuild exact evidence/observed bends
        if i == index and firstWalk then
            if corridor then
                local retained = {}; for k, v in pairs(how) do retained[k] = v end
                retained.from = from
                how = retained
            else how = "walk" end
        end
        if how == "walk" then
            if from.area ~= e.node.area or from.city ~= e.node.city or not CanWalk(from, e.node) then return nil end
            seconds = WalkCost(from, e.node, c)
        elseif type(how) == "table" and how.kind == "discover" then
            if FlightState(e.node.taxi) ~= true then
                if not c.flights or e.node.discoverable == false or (e.node.fac and e.node.fac ~= c.faction) then return nil end
                seconds, unlocked = TAXI_UNLOCK, true
            end
        elseif type(how) == "table" and how.method then
            if not Usable(how, c, unlocked) then return nil end
            seconds = LinkCost(how, elapsed, c, mode)
        else
            return nil -- casts/cooldowns are reconsidered by the new search
        end
        if seconds then
            local walking = how == "walk" or (type(how) == "table" and WALKING[how.method])
            risk = risk + (walking and Danger(from, e.node, c, seconds) or 0)
            elapsed = elapsed + seconds
            path[#path + 1] = { node = e.node, via = how, at = elapsed, risk = risk }
            mode = type(how) == "table" and how.method == "taxi" and not how.dialogue and "taxi" or "walk"
            if not (type(how) == "table" and how.kind == "discover") then unlocked = false end
        end
    end
    return { wp = p.wp, path = path, total = elapsed, risk = risk, here = here,
        built = GetTime(), c = c, preference = p.preference, index = 2, target = path[2], followed = true }
end

-- A chosen itinerary constrains the onward actions, not an obsolete walking
-- approach. Join a later stop only using the planner's same-area, same-city,
-- barrier checks. Never trim an entrance, action or surveyed crossing.
local function Remaining(p, here, c)
    local best = Reprice(p, here, c, p.index)
    if not best then return nil end
    local function Score(route)
        return route.total + (p.preference == "safer" and route.risk or 0)
    end
    local function WalkingScore(route)
        local seconds, risk = 0, 0
        for i = 2, #route.path do
            local e, prev = route.path[i], route.path[i - 1]
            if not PlainWalk(e.via) then break end
            seconds, risk = seconds + e.at - prev.at, risk + e.risk - prev.risk
        end
        return seconds + (p.preference == "safer" and risk or 0)
    end
    for i = p.index + 1, #p.path do
        local prev, e = p.path[i - 1], p.path[i]
        if not OptionalStop(prev, e) or prev.node.area ~= e.node.area
            or prev.node.city ~= e.node.city then break end
        if Approach(here, e.node) then
            local joined = Reprice(p, here, c, i, true)
            -- Even a sub-hysteresis saving removes a redundant walking hint;
            -- itinerary alternatives still use KeepFollowed below.
            if joined then
                local gain = Score(best) - Score(joined)
                -- A scheduled departure can absorb all time saved walking.
                -- Prefer the shorter approach even when arrival ETA ties.
                if gain > 1e-6 or (math.abs(gain) <= 1e-6
                    and WalkingScore(joined) < WalkingScore(best) - 1e-6) then best = joined end
            end
        end
    end
    best.index = Target(best.path, here)
    best.target = best.path[best.index]
    return best
end

function Travel.KeepFollowed(old, new, preference, explicit)
    if not old or not old.followed or old.wp ~= new.wp or old.preference ~= preference then return false end
    -- The same waypoint object can move as quest objectives change. Explicit
    -- itinerary selection must never retain a route to its previous position.
    if old.path and new.path then
        local a, b = old.path[#old.path], new.path[#new.path]
        a, b = a and a.node, b and b.node
        if not a or not b or ns.Num(a.m) ~= ns.Num(b.m)
            or ns.Num(a.x) ~= ns.Num(b.x) or ns.Num(a.y) ~= ns.Num(b.y) then return false end
    end
    if (old.terrainPenalty or 0) ~= (new.terrainPenalty or 0) then return false end
    if explicit then return true end
    local oldCost = old.total + (preference == "safer" and old.risk or 0)
    local newCost = new.total + (preference == "safer" and new.risk or 0)
    return oldCost - newCost < max(KEEP_SECONDS, oldCost * KEEP_FRACTION) - 1e-6
end

function Travel.Choices(wp)
    if not wp or not Travel.Enabled() then return {} end
    local here, goal = PlayerPlace(), GoalPlace(wp)
    if not (here and goal and here.area and goal.area) then return {} end
    return Travel.Routes(here, goal, Context(), wp.travelPreference or ns.Get("travelPreference"))
end

local function Plan(wp)
    local d = Data()
    if not d then
        return nil
    end
    local here = PlayerPlace()
    local goal = GoalPlace(wp)
    if not (here and goal and here.area and goal.area) then
        return nil
    end
    local c = Context()
    local preference = wp.travelPreference or ns.Get("travelPreference")
    local _, candidate = Travel.Routes(here, goal, c, preference)
    if not candidate then
        return nil
    end
    local new = { wp = wp, path = candidate.path, total = candidate.total, risk = candidate.risk, terrainPenalty = candidate.terrainPenalty,
        preference = preference, here = here, built = GetTime(), c = c, followed = WP.GetActive() == wp }
    new.index = Target(new.path, here)
    new.target = new.path[new.index]
    if plan and plan.followed and new.followed and plan.wp == wp and plan.preference == preference then
        local old = Remaining(plan, here, c)
        if Travel.KeepFollowed(old, new, preference, wp.travelChosen) then return old end
    end
    return new
end

local trip, offerFrame
local function HideOffer()
    if offerFrame then offerFrame:Hide(); offerFrame.trip = nil end
end

local function TripFor(wp)
    if wp.source == "corpse" then return nil end -- suspend the living trip
    if wp.travelTrip and wp.travelTrip == trip then
        trip.wp = wp
        return trip
    end
    HideOffer()
    trip = { wp = wp, attempted = false }
    wp.travelTrip = trip
    -- Old picker choices and choices from a previous trip never set the default.
    wp.travelPreference, wp.travelChosen = nil, nil
    return trip
end

function Travel.Select(wp, candidate)
    if not wp or not WP.IsValid(wp) or not candidate then return end
    if WP.GetActive() ~= wp then WP.SetActive(wp, true) end
    local currentTrip = TripFor(wp)
    if currentTrip then currentTrip.attempted = true end
    HideOffer()
    wp.travelPreference, wp.travelChosen = candidate.preference, true
    WP.Save()
    wipe(reached)
    local here = PlayerPlace()
    if not here then Travel.Invalidate(); return end
    local path = candidate.path
    local index = Target(path, here)
    plan = { wp = wp, path = path, total = candidate.total, risk = candidate.risk, terrainPenalty = candidate.terrainPenalty,
        preference = candidate.preference, here = here, built = GetTime(), c = Context(),
        index = index, target = path[index], followed = true }
    planWp, planGeneration, lastPlanTime = wp, generation, GetTime()
    ns.Fire("TRAVEL_PLANNED", plan)
end

local function RiskReason(fast, safe, c)
    local seen = {}
    for i = 2, #safe.path do
        local e, a = safe.path[i], safe.path[i - 1]
        if e.via == "walk" or (type(e.via) == "table" and WALKING[e.via.method]) then
            local _, id, kind = Danger(a.node, e.node, c, e.at - a.at)
            if id then seen[kind .. ":" .. id] = true end
        end
    end
    for i = 2, #fast.path do
        local e, a = fast.path[i], fast.path[i - 1]
        if e.via == "walk" or (type(e.via) == "table" and WALKING[e.via.method]) then
            local _, id, kind = Danger(a.node, e.node, c, e.at - a.at)
            if id and not seen[kind .. ":" .. id] then
                local name = kind == "town" and C_Map and C_Map.GetAreaInfo and ns.Str(C_Map.GetAreaInfo(id))
                    or Geo.GetMapName(id)
                return (kind == "level" and L.TRAVEL_RISK_LEVEL or L.TRAVEL_RISK_VIA):format(name or Geo.GetMapName(e.node.m))
            end
        end
    end
    return L.TRAVEL_RISK_WALK
end

local function BuildOffer()
    if offerFrame then return offerFrame end
    -- This is an independent, unprotected addon control. The arrow itself
    -- stays noninteractive, and Blizzard's frames/scripts are never changed.
    local button = ns.Widgets.Button(UIParent, "", 360, 40)
    offerFrame, Travel.offerButton = button, button
    button:SetPoint("TOP", ns.Arrow.textFrame, "BOTTOM", 0, -6)
    button:RegisterForClicks("LeftButtonUp")
    local text = button:GetFontString()
    if text then text:SetWordWrap(true) end
    button:Hide()
    button:SetScript("OnEnter", function(self) self.hovered = true; self:SetAlpha(1) end)
    button:SetScript("OnLeave", function(self) self.hovered = false end)
    button:SetScript("OnHide", function(self) self.hovered = false end)
    button:SetScript("OnUpdate", ns.Safe(function(self, elapsed)
        if not self.trip or self.trip ~= trip or WP.GetActive() ~= trip.wp then HideOffer(); return end
        if not self.hovered then self.remaining = self.remaining - (ns.Num(elapsed) or 0) end
        if self.remaining <= 1e-6 then HideOffer(); return end
        self:SetAlpha(self.hovered and 1 or min(1, self.remaining / OFFER_FADE))
    end))
    button:SetScript("OnClick", ns.Safe(function(self)
        if not self.trip or self.trip ~= trip or WP.GetActive() ~= trip.wp then HideOffer(); return end
        local wp = trip.wp
        -- Recompute at click time: the player may have moved or transport
        -- discovery/access conditions may have changed during the offer.
        local candidates, safe = Travel.Choices(wp)
        local fast = candidates[1]
        if Travel.CanOffer(fast, safe) then
            Travel.Select(wp, fast)
            -- Keep the trip's risky preference while allowing normal rerouting.
            wp.travelChosen = nil
        end
        HideOffer()
    end))
    return button
end

-- Only a route start can attempt an offer. Replans and repeated tracking
-- clicks share the trip token; ignoring the offer leaves the safe plan alone.
function Travel.Offer(wp)
    if not wp or WP.GetActive() ~= wp then return end
    local currentTrip = TripFor(wp)
    if not currentTrip or currentTrip.attempted or not Travel.Enabled() then return end
    if ns.Get("travelPreference") == "fastest" or wp.travelPreference == "fastest" then
        currentTrip.attempted = true
        return
    end
    local candidates, safe = Travel.Choices(wp)
    if not safe then return end -- no position yet: retry when steering starts
    currentTrip.attempted = true
    local fast = candidates[1]
    if not Travel.CanOffer(fast, safe) then return end
    local button = BuildOffer()
    button.trip, button.remaining, button.hovered = currentTrip, OFFER_LIFETIME, false
    button:SetText(L.TRAVEL_FASTER_OFFER:format(Geo.FormatTime(safe.total - fast.total)) .. "\n" .. RiskReason(fast, safe, Context()))
    button:SetAlpha(1)
    button:Show()
end

ns.On("LOGIN", BuildOffer)

-- One of the boat or zeppelin rides in the plan has started: the player is
-- on board, moving without walking.
local function Sample(here)
    local now = GetTime()
    local prev = samples[#samples]
    if prev and now - prev.t < 0.25 then
        return
    end
    local s = { t = now, cont = here.cont, wx = here.wx, wy = here.wy }
    local walking = GetUnitSpeed and ns.Num(GetUnitSpeed("player"))
    if GetUnitSpeed and not walking then
        -- Unknown speed cannot tell walking from a boat; start sampling afresh.
        wipe(samples)
        return
    end
    walking = walking or 0
    s.walking = walking > 0.1
    table.insert(samples, s)
    while #samples > 8 do
        table.remove(samples, 1)
    end
end

local function DriftSpeed()
    local a, b = samples[1], samples[#samples]
    if not (a and b) or a == b or a.cont ~= b.cont or b.t - a.t < 1 then
        return 0, false
    end
    local walked = false
    for _, s in ipairs(samples) do
        walked = walked or s.walking
    end
    local dx, dy = b.wx - a.wx, b.wy - a.wy
    return sqrt(dx * dx + dy * dy) / (b.t - a.t), walked
end

function Travel.Riding()
    return riding
end

local function FinishRide(destination)
    if plan and plan.followed and plan.wp.travelChosen and destination then
        for i = plan.index, #plan.path - 1 do
            if plan.path[i].node == destination then
                plan.index, plan.target = i + 1, plan.path[i + 1]
                return -- retain the chosen onward itinerary after disembarking
            end
        end
    end
    plan = nil
end

local function UpdateRiding(here)
    if UnitIsGhost and UnitIsGhost("player") then
        riding, atDock = nil, nil
        return false
    end
    if UnitOnTaxi and UnitOnTaxi("player") then
        if not riding or riding.method ~= "taxi" then
            local dest
            if plan and plan.target and type(plan.target.via) == "table" and plan.target.via.method == "taxi" then
                dest = RideEnd(plan.path, plan.index)
            end
            riding = { method = "taxi", to = dest, since = GetTime() }
        end
        return true
    elseif riding and riding.method == "taxi" then
        FinishRide(riding.to)
        riding = nil
        Travel.Invalidate()
        return false
    end
    if not riding then
        if not here then
            return false
        end
        -- a boat or zeppelin of the plan's: has it set off with us? (the dock
        -- the plan sent you to, or any of its rides leaving from near here)
        local candidates = {}
        if atDock and GetTime() - atDock.t < 900 then
            candidates[1] = atDock.link
        end
        for _, e in ipairs(plan and plan.path or {}) do
            local l = type(e.via) == "table" and e.via
            if l and (l.method == "ship" or l.method == "zeppelin") then
                local dd = Dist(here, l.from)
                if dd and dd < 100 then
                    candidates[#candidates + 1] = l
                end
            end
        end
        local speed, walked = DriftSpeed()
        -- moving with your feet still, or faster than any mount
        if (speed > 5 and not walked) or speed > 18 then
            for _, l in ipairs(candidates) do
                local fromD = Dist(here, l.from)
                if fromD and fromD > 20 and fromD < 600 then
                    local now = GetTime()
                    riding = { method = l.method, link = l, from = l.from, to = l.to, since = now }
                    -- it left about when it started moving away from the dock
                    ns.Fire("TRAVEL_BOARDED", l.key, now - fromD / max(speed, 1))
                    break
                end
            end
        end
        return riding ~= nil
    end
    -- aboard: until you're at the other end, or clearly not on it any more
    local toD = here and Dist(here, riding.to)
    local ride = riding.link and riding.link.ride or 300
    local elapsed = GetTime() - riding.since
    local walking = GetUnitSpeed and (ns.Num(GetUnitSpeed("player")) or 0) > 0.1
    if (toD and toD < 150) or (elapsed > ride and walking and toD and toD < 600) or elapsed > ride + 300 then
        if riding.link then
            ns.Fire("TRAVEL_ARRIVED", riding.link.key, GetTime())
        end
        FinishRide(riding.to)
        riding = nil
        Travel.Invalidate()
        return false
    end
    if here and IsSwimming and IsSwimming() then
        riding = nil -- fell off
        Travel.Invalidate()
        return false
    end
    return true
end

-- What the arrow should do for this waypoint, or nil to point straight at
-- it: { dist, bearing (nil: show a pin), title, sub, total }
-- A short record of what the arrow was told to do (in the saved variables,
-- the last 60 changes), so a wrong turn reported from the game can be
-- traced afterwards.
local lastLog
local function Log(here, target, s)
    if type(WaypointTrackerDB) ~= "table" then
        return
    end
    local now = GetTime()
    local key = tostring(target.id) .. ">" .. tostring(here.area) .. ">" .. tostring(s.trail ~= nil)
    if lastLog and lastLog.key == key and now - lastLog.t < 15 then
        return
    end
    lastLog = { key = key, t = now }
    local log = type(WaypointTrackerDB.travelLog) == "table" and WaypointTrackerDB.travelLog or {}
    WaypointTrackerDB.travelLog = log
    local d = data or {}
    local tc, tx, ty = Pos(target)
    local facing = GetPlayerFacing and ns.Num(GetPlayerFacing())
    local route = {}
    for i, e in ipairs(plan and plan.path or {}) do
        route[i] = e.node.id or (e.node.player and "you") or (e.node.goal and "goal") or "?"
    end
    table.insert(log, {
        when = time and time() or 0,
        step = s.title,
        here = ("%s %.4f %.4f | %s %.1f %.1f | %s %s"):format(tostring(here.m), here.x or 0, here.y or 0,
            tostring(here.cont), here.wx or 0, here.wy or 0, tostring(d.areas and d.areas[here.area] or here.area),
            tostring(here.city or "")),
        target = ("%s | %s %.1f %.1f"):format(tostring(target.id), tostring(tc), tx or 0, ty or 0),
        bearing = s.bearing and floor(math.deg(s.bearing) + 0.5),
        trail = s.trail and true or nil,
        facing = facing and floor(math.deg(facing) + 0.5),
        route = table.concat(route, " "),
    })
    while #log > 60 do
        table.remove(log, 1)
    end
end

function Travel.Steer(wp)
    if not wp or not Travel.Enabled() then
        plan = nil
        return nil
    end
    Travel.Offer(wp)
    local now = GetTime()
    local here = PlayerPlace()
    if here then
        Sample(here)
        NoteSpeed()
    end
    local aboard = UpdateRiding(here)
    if aboard then
        local title = riding.method == "taxi" and L.TRAVEL_ON_TAXI or L.TRAVEL_ON_BOAT
        local s = { title = title:format(riding.to and PlaceName(riding.to) or WP.ShortName(wp)), sub = WP.ShortName(wp) }
        if riding.to and here then
            s.dist = Dist(here, riding.to)
        end
        return s
    end
    local moved = here and plan and plan.here and Dist(here, plan.here)
    local changedArea = here and plan and plan.here
        and (here.area ~= plan.here.area or here.city ~= plan.here.city)
    local projection = plan and ProjectPlan(plan, here)
    local deviated = projection and projection.distance > DEVIATION
    if planWp ~= wp or planGeneration ~= generation or now - lastPlanTime >= REPLAN_EVERY
        or (now - lastPlanTime >= REPLAN_MIN and (deviated or changedArea or (moved and moved >= REPLAN_MOVED))) then
        if planWp ~= wp then
            wipe(reached)
        end
        lastPlanTime, planGeneration, planWp = now, generation, wp
        plan = Plan(wp)
        ns.Fire("TRAVEL_PLANNED", plan)
    end
    if plan and not here then
        -- no position: on the tram, or in a dungeon on the way
        local t = plan.target
        local how = t and type(t.via) == "table" and t.via
        if how and how.method == "tram" then
            return { title = StepText(plan.path, plan.index, WP.ShortName(wp)), sub = WP.ShortName(wp) }
        end
        return nil
    end
    if not plan then
        -- No reachable graph route: do not replace it with a straight arrow
        -- through a known barrier or an unavailable transport connection.
        return { title = L.TRAVEL_NO_PLAN, sub = WP.ShortName(wp), pin = true }
    end
    local path = plan.path
    -- a plain walk to a waypoint in the same area: the normal arrow
    if #path == 2 and path[2].via == "walk" then
        return nil
    end
    local i = Target(path, here, plan.index)
    plan.index, plan.target = i, path[i]
    local progress, aim = ProjectPlan(plan, here)
    i = plan.index
    local e = path[i]
    local how = e.via
    if type(how) == "table" and (how.method == "ship" or how.method == "zeppelin") then
        atDock = { link = how, t = now }
    end
    local s = { total = plan.total, step = i - 1, steps = #path - 1, sub = WP.ShortName(wp) }
    s.title = StepText(path, i, WP.ShortName(wp))
    if type(how) == "table" and (how.kind or TRANSPORT[how.method]) then
        -- at the dock, flight master or portal (or about to cast): no direction
        local from = path[i - 1].node
        s.dist = (how.kind == nil) and Dist(here, from) or nil
        s.pin = true
        local T = ns.Trails
        if how.ride and T and T.NextDeparture then
            local wait = T.NextDeparture(how.key, 0)
            if wait then
                s.wait = wait
            end
        end
        return s
    end
    local target = e.node
    local tc, tx, ty = Pos(target)
    if tc ~= here.cont or not tx then
        -- not on the same world map as the player (a phased copy, say):
        -- better no direction than a wrong one
        s.pin = true
        Log(here, target, s)
        return s
    end
    local dNorth, dWest = tx - here.wx, ty - here.wy
    s.dist = sqrt(dNorth * dNorth + dWest * dWest)
    if aim then
        dNorth, dWest = aim.wx - here.wx, aim.wy - here.wy
        s.aim, s.progress, s.deviation = aim, progress.progress, progress.distance
    end
    s.bearing = math.atan2(dWest, dNorth)
    -- walking inside an area: a path players have walked beats the straight line
    local T = ns.Trails
    if T and T.Steer and ns.Get("travelTrails") and not plan.c.ghost
        and not (type(how) == "table" and how.terrain) and not target.terrainOnly then
        local bearing = T.Steer(here, target)
        if bearing then
            s.trail = bearing
            s.bearing = bearing
        end
    end
    Log(here, target, s)
    return s
end

-- The current plan, for the map and the waypoint window
function Travel.Current()
    return plan
end

-- The current plan as lines of text, one a step
function Travel.Describe(p)
    p = p or plan
    if not p then
        return {}
    end
    local lines, path = {}, p.path
    local i = 2
    while i <= #path do
        local e = path[i]
        local text = StepText(path, i, WP.ShortName(p.wp))
        local how = e.via
        if type(how) == "table" and how.method == "taxi" then
            local _, j = RideEnd(path, i)
            i = j
        end
        if lines[#lines] ~= text then
            lines[#lines + 1] = text
        end
        i = i + 1
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
ns.RegisterEvent("TAXIMAP_OPENED", function()
    if Data() then
        Travel.ReadFlightMap()
        Travel.Refresh()
    end
end)

ns.RegisterEvent("HEARTHSTONE_BOUND", function()
    local m, x, y = Geo.GetPlayerMapPosition()
    if m then
        Know().bind = { m = m, x = x, y = y, name = GetBindLocation and GetBindLocation() }
        Travel.Invalidate()
    end
end)

for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "BAG_UPDATE_COOLDOWN",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
    ns.RegisterEvent(e, function()
        Travel.Invalidate()
    end)
end

ns.On("ACTIVE_CHANGED", function(wp)
    C_Timer.After(0, function()
        if WP.GetActive() ~= wp then return end
        if wp then Travel.Offer(wp) else HideOffer(); trip = nil end
    end)
    plan, riding, atDock = nil, nil, nil
    wipe(reached)
    Travel.Invalidate()
end)

ns.On("SETTING_CHANGED", function(key)
    if type(key) == "string" and (key == "realRoutes" or key:find("^travel")) then
        HideOffer()
        plan, riding = nil, nil
        Travel.Invalidate()
    end
end)

-- for the tests: forget the network and the plan
function Travel._Reset()
    HideOffer()
    trip = nil
    data, plan, riding, taxiNames, atDock, planWp = nil, nil, nil, nil, nil, nil
    bindCache, samples = {}, {}
    wipe(reached)
    Travel.Invalidate()
end
