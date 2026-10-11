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
-- Flights only use flight paths this character has found. The game only
-- says which those are while a flight master's map is open, so they are
-- written down then (per character).
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
local NEAR = 15 -- yards: a stop this close is behind you
local BOARD_NEAR = 30 -- yards from a dock or flight master that count as there
local REPLAN_EVERY = 2 -- seconds
local DANGER_LEVELS = 3 -- a zone this many levels above you is avoided when it can be
local DANGER_FACTOR = 1.6
local KEEP_PLAN = 0.9 -- a new plan must be this much quicker to change your course
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
        teleports = {}, factors = {}, levels = {}, byTaxi = {},
        areas = T.areas or {}, indoor = T.indoor or {},
    }
    Rows(T.nodes, function(f)
        local n = {
            id = f[1], kind = f[2], area = tonumber(f[3]), cont0 = tonumber(f[4]),
            wx0 = tonumber(f[5]), wy0 = tonumber(f[6]), m = tonumber(f[7]),
            x = (tonumber(f[8]) or 0) / 100, y = (tonumber(f[9]) or 0) / 100,
            city = tonumber(f[10]), town = tonumber(f[11]), taxi = tonumber(f[12]), fac = Blank(f[13] or ""),
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
            table.insert(d.towns, { area = tonumber(f[2]), inn = inn })
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

-- The area a map position is in: a part of a map that is its own area, the
-- map's area, or (for a cave or a small map) the area of a map above it.
-- Also returns the walled city's map when the position is inside one.
function Travel.AreaAt(m, x, y)
    local d = Data()
    if not d or not m then
        return nil
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
    return not start or start == 0 or (start + (duration or 0) - GetTime()) <= 1
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
            start, duration = info.startTime, info.duration
        end
    elseif GetSpellCooldown then
        start, duration = GetSpellCooldown(spell)
    end
    return Ready(start, duration)
end

-- remember how fast this character rides, for when they aren't mounted yet
local function NoteSpeed()
    if not (GetUnitSpeed and IsMounted) or not IsMounted() then
        return
    end
    local _, run = GetUnitSpeed("player")
    if run and run > RUN_SPEED and run < 40 then
        Know().mountSpeed = floor(run * 10 + 0.5) / 10
    end
end

-- everything about the player a plan depends on
local function Context()
    local c = {}
    c.faction = UnitFactionGroup and UnitFactionGroup("player")
    c.class = UnitClass and select(2, UnitClass("player"))
    c.race = UnitRace and select(2, UnitRace("player"))
    c.level = UnitLevel and UnitLevel("player") or 1
    local run = RUN_SPEED
    if GetUnitSpeed then
        local _, r = GetUnitSpeed("player")
        run = max(RUN_SPEED, r or RUN_SPEED)
    end
    c.run = run
    c.ground = max(run, Know().mountSpeed or 0)
    c.flightFactor = Knows(FREQUENT_FLIER) and (1 / 1.2) or 1
    c.dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) and true or false
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

local function Usable(l, c)
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
        if not c.flights or FlightState(l.from.taxi) ~= true or FlightState(l.to.taxi) ~= true then
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
    local cost = dd * Factor(a, b) / speed
    local lv = data.levels[b.m]
    if lv and c.level and lv[1] > c.level + DANGER_LEVELS then
        cost = cost * DANGER_FACTOR
    end
    return cost
end

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
        if arrivedBy ~= "taxi" then
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
local function Search(start, goal, c)
    local d = data
    local best, via, prev, done = { [start] = 0 }, {}, {}, {}
    local heap = {}
    Push(heap, 0, start)
    local function Relax(u, v, cost, how)
        if not cost then
            return
        end
        local g = best[u] + cost
        if best[v] == nil or g < best[v] - 1e-6 then
            best[v], via[v], prev[v] = g, how, u
            Push(heap, g, v)
        end
    end
    local expanded = 0
    while heap[1] do
        local top = Pop(heap)
        local u = top[2]
        if not done[u] and top[1] <= (best[u] or huge) then
            done[u] = true
            if u == goal then
                break
            end
            expanded = expanded + 1
            if expanded > 4000 then
                break
            end
            -- walking inside the area, on the same side of a city wall
            if u.area then
                for _, v in ipairs(d.byArea[u.area] or {}) do
                    if v ~= u and not done[v] and v.city == u.city
                        and (not Hostile(v.city, c) or v.city == goal.city or v.city == start.city) then
                        Relax(u, v, WalkCost(u, v, c), "walk")
                    end
                end
                if goal.area == u.area and goal.city == u.city then
                    Relax(u, goal, WalkCost(u, goal, c), "walk")
                end
            end
            -- gates, crossings, flights, boats...
            for _, l in ipairs(u.id and d.out[u.id] or {}) do
                if not done[l.to] and Usable(l, c) then
                    local how = via[u]
                    Relax(u, l.to, LinkCost(l, best[u], c, type(how) == "table" and how.method or how), l)
                end
            end
            -- the hearthstone and teleports, from where you stand
            if u == start then
                for _, j in ipairs(c.jumps) do
                    Relax(u, j.node, j.cost, j)
                end
            end
        end
    end
    if not best[goal] then
        return nil
    end
    local path, n = {}, goal
    while n do
        table.insert(path, 1, { node = n, via = via[n], at = best[n] })
        n = prev[n]
    end
    return path, best[goal]
end
Travel.Search = Search

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
        j = j + 1
    end
    return path[j].node, j
end

Travel.RideEnd = RideEnd

-- What to do at stop i of a path, as one line
local function StepText(path, i, wpName)
    local e = path[i]
    local how = e.via
    if type(how) == "table" and how.kind == "hearth" then
        return L.TRAVEL_HEARTH:format(how.name or PlaceName(e.node))
    elseif type(how) == "table" and how.kind == "teleport" then
        return L.TRAVEL_TELEPORT:format(SpellName(how.spell))
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
    if type(nh) == "table" and TRANSPORT[nh.method] then
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

-- seconds to finish an existing plan from where the player is now
local function Remaining(p, here, c)
    local t = p.target
    local walkedTo = t and (t.via == "walk" or (type(t.via) == "table" and WALKING[t.via.method]))
    if not walkedTo or t.node.area ~= here.area or t.node.city ~= here.city then
        return nil
    end
    local walk = WalkCost(here, t.node, c)
    return walk and (walk + (p.total - t.at)) or nil
end

-- the stop the arrow points at: the first one not already behind you
local function Target(path, here)
    local i = 2
    while i < #path do
        local e, nextE = path[i], path[i + 1]
        local walkedTo = e.via == "walk" or (type(e.via) == "table" and WALKING[e.via.method])
        if not walkedTo then
            break
        end
        if not reached[e.node] then
            local near = (type(nextE.via) == "table" and TRANSPORT[nextE.via.method]) and BOARD_NEAR or NEAR
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
    local path, total = Search(here, goal, c)
    if not path then
        return nil
    end
    local new = { wp = wp, path = path, total = total, here = here, built = GetTime(), c = c }
    new.index = Target(path, here)
    new.target = path[new.index]
    -- keep going the way you were unless the new way is clearly quicker
    if plan and plan.wp == wp and plan.target and new.target and plan.target.node ~= new.target.node
        and GetTime() - plan.built < 20 then
        local old = Remaining(plan, here, c)
        if old and total > old * KEEP_PLAN then
            plan.here = here
            return plan
        end
    end
    return new
end

-- One of the boat or zeppelin rides in the plan has started: the player is
-- on board, moving without walking.
local function Sample(here)
    local now = GetTime()
    local prev = samples[#samples]
    if prev and now - prev.t < 0.25 then
        return
    end
    local s = { t = now, cont = here.cont, wx = here.wx, wy = here.wy }
    local walking = GetUnitSpeed and GetUnitSpeed("player") or 0
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

local function UpdateRiding(here)
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
        riding, plan = nil, nil
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
    local walking = GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0.1
    if (toD and toD < 150) or (elapsed > ride and walking and toD and toD < 600) or elapsed > ride + 300 then
        if riding.link then
            ns.Fire("TRAVEL_ARRIVED", riding.link.key, GetTime())
        end
        riding, plan = nil, nil
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
function Travel.Steer(wp)
    if not wp or not Travel.Enabled() then
        plan = nil
        return nil
    end
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
    if planWp ~= wp or planGeneration ~= generation or now - lastPlanTime >= REPLAN_EVERY then
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
        return nil
    end
    local path = plan.path
    -- a plain walk to a waypoint in the same area: the normal arrow
    if #path == 2 and path[2].via == "walk" then
        return nil
    end
    local i = Target(path, here)
    if plan.index and i > plan.index then
        lastPlanTime = 0 -- a stop behind you: plan on from here at once
    end
    plan.index, plan.target = i, path[i]
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
    local _, tx, ty = Pos(target)
    local dNorth, dWest = tx - here.wx, ty - here.wy
    s.dist = sqrt(dNorth * dNorth + dWest * dWest)
    s.bearing = math.atan2(dWest, dNorth)
    -- walking inside an area: a path players have walked beats the straight line
    local T = ns.Trails
    if T and T.Steer and ns.Get("travelTrails") then
        local bearing = T.Steer(here, target)
        if bearing then
            s.bearing = bearing
        end
    end
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

for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "BAG_UPDATE_COOLDOWN" }) do
    ns.RegisterEvent(e, function()
        Travel.Invalidate()
    end)
end

ns.On("ACTIVE_CHANGED", function()
    plan, riding, atDock = nil, nil, nil
    wipe(reached)
    Travel.Invalidate()
end)

ns.On("SETTING_CHANGED", function(key)
    if type(key) == "string" and (key == "realRoutes" or key:find("^travel")) then
        plan, riding = nil, nil
        Travel.Invalidate()
    end
end)

-- for the tests: forget the network and the plan
function Travel._Reset()
    data, plan, riding, taxiNames, atDock, planWp = nil, nil, nil, nil, nil, nil
    bindCache, samples = {}, {}
    wipe(reached)
    Travel.Invalidate()
end
