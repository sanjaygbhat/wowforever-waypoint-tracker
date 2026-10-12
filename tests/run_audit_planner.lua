-- Offline planner property audit. Run at repo root: lua5.1 tests/run_audit_planner.lua
-- Optional --strict-long-legs fails on unverified implicit walks > 2000 yards.
-- Optional --no-client-cache exercises the checked-in-data-only CI fallback.
-- No addon files or saved variables are written. All fixtures are in memory.
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
local options = {}
for _, option in ipairs(arg or {}) do
    assert(option == "--strict-long-legs" or option == "--no-client-cache" or option == "--details", "unknown audit option: " .. option)
    options[option] = true
end
local function fileText(path)
    local f = assert(io.open(path)); local s = f:read("*a"); f:close(); return s
end
local sourceSnapshot = {}
for _, path in ipairs({"WaypointTracker/Travel.lua", "WaypointTracker/TravelData.lua", "tests/wowmock.lua"}) do sourceSnapshot[path] = fileText(path) end
local failures, checks, cases = {}, 0, 0
local function check(ok, category, detail)
    checks = checks + 1
    if not ok then
        failures[category] = (failures[category] or 0) + 1
        if failures[category] <= 8 then print("FAIL [" .. category .. "] " .. detail) end
    end
end
local function split(s, sep)
    local t = {}
    for f in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = f end
    return t
end
local function rows(s)
    local t = {}
    for line in (s or ""):gmatch("[^\n]+") do t[#t + 1] = split(line, "\t") end
    return t
end
local function csv(line)
    local t, field, quoted, i = {}, "", false, 1
    while i <= #line do
        local c = line:sub(i, i)
        if c == '"' then
            if quoted and line:sub(i + 1, i + 1) == '"' then field = field .. '"'; i = i + 1
            else quoted = not quoted end
        elseif c == "," and not quoted then t[#t + 1] = field; field = ""
        else field = field .. c end
        i = i + 1
    end
    t[#t + 1] = field:gsub("\r$", "")
    return t
end
local function readCSV(path)
    local f = io.open(path)
    if not f then return nil end
    local header, out = csv(f:read("*l")), {}
    for line in f:lines() do
        local values, row = csv(line), {}
        for i, h in ipairs(header) do row[h] = values[i] end
        out[#out + 1] = row
    end
    f:close(); return out
end
-- Independent client rectangles; unlike the default mock these represent Classic.
local geometry = {}
local assignments = not options["--no-client-cache"] and readCSV("tools/.cache/travel/UiMapAssignment.csv")
local maps = not options["--no-client-cache"] and readCSV("tools/.cache/travel/UiMap.csv")
if assignments and maps then
    local info = {}
    for _, r in ipairs(maps) do info[tonumber(r.ID)] = r end
    for _, r in ipairs(assignments) do
        local id = tonumber(r.UiMapID)
        if not geometry[id] and tonumber(r.UiMin_0) == 0 and tonumber(r.UiMin_1) == 0
            and tonumber(r.UiMax_0) == 1 and tonumber(r.UiMax_1) == 1 and info[id] then
            local g = {mapID = id, name = info[id].Name_lang, cont = tonumber(r.MapID),
                top = tonumber(r.Region_3), left = tonumber(r.Region_4),
                h = tonumber(r.Region_3) - tonumber(r.Region_0),
                w = tonumber(r.Region_4) - tonumber(r.Region_1),
                mapType = tonumber(info[id].Type), parentMapID = tonumber(info[id].ParentUiMapID)}
            if g.w > 0 and g.h > 0 then geometry[id] = g; M.maps[id] = g end
        end
    end
end
function GetUnitSpeed() return 0, 7, 7, 4.7 end
function GetItemCount() return 0 end
function GetServerTime() return 1700000000 + math.floor(M.now) end
local faction, level = "Alliance", 60
function UnitFactionGroup() return faction end
function UnitLevel() return level end
WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
local T, raw = ns.Travel, ns.TravelData
-- Avoid fictitious default-mock rectangles when no local client extraction exists.
ns.Geo.MapToWorld = function(m, x, y)
    local g = geometry[m]
    if g then return g.cont, g.top - y * g.h, g.left - x * g.w end
end
ns.Trails = nil -- fresh-character, no observed transport timetable or trails
T._Reset(); T.Data()
print("Coordinate source: " .. (assignments and maps and "cached Classic client UiMapAssignment/UiMap" or "shipped world coordinates (client cache absent)"))
local function numericMap(s)
    local t = {}
    for _, r in ipairs(rows(s)) do t[tonumber(r[1])] = tonumber(r[2]) end
    return t
end
local function graph(source)
    -- Parse raw TSV ourselves: the oracle never calls Travel.Data/Dist/Pos/Search.
    local g = {nodes = {}, order = {}, area = {}, out = {}, factors = numericMap(source.factors),
        levels = numericMap(source.levels), indoor = source.indoor or {}, cities = {}, barriers = {}, evidence = {}}
    for _, r in ipairs(rows(source.cities)) do g.cities[tonumber(r[1])] = r[2] end
    for _, r in ipairs(rows((source.nodes or "") .. "\n" .. (source.walkCandidates or ""))) do
        local n = {id = r[1], kind = r[2], area = tonumber(r[3]), cont = tonumber(r[4]),
            wx = tonumber(r[5]), wy = tonumber(r[6]), m = tonumber(r[7]),
            x = tonumber(r[8]) / 100, y = tonumber(r[9]) / 100, city = tonumber(r[10]),
            taxi = tonumber(r[12]), fac = r[13] ~= "" and r[13] or nil, discoverable = r[14] ~= "0", terrainOnly = r[1]:find("^TERRAIN_") and true or nil}
        local rect = geometry[n.m]
        if rect then n.cont, n.wx, n.wy = rect.cont, rect.top - n.y * rect.h, rect.left - n.x * rect.w end
        g.nodes[n.id] = n; g.order[#g.order + 1] = n
        if n.kind ~= "inn" and n.kind ~= "settlement" then
            g.area[n.area] = g.area[n.area] or {}; table.insert(g.area[n.area], n)
        end
    end
    table.sort(g.order, function(a, b) return a.id < b.id end)
    for i, n in ipairs(g.order) do n.index = i; g.out[i] = {} end
    for _,r in ipairs(rows(source.walkEvidence)) do
        g.evidence[r[1] .. ">" .. r[2]],g.evidence[r[2] .. ">" .. r[1]] = r[3],r[3]
    end
    local edgeRows = rows(source.links)
    for _,r in ipairs(rows(source.walkCandidateEdges)) do edgeRows[#edgeRows+1]={r[1],r[2],"walk","0","","","","","","","",""} end
    for _, r in ipairs(edgeRows) do
        local a, b = g.nodes[r[1]], g.nodes[r[2]]
        assert(a and b, "TravelData.lua missing link endpoint: " .. r[1] .. " -> " .. r[2])
        local function add(u, v)
            table.insert(g.out[u.index], {from = u, to = v, method = r[3], cost = tonumber(r[4]),
                ride = tonumber(r[5]), screens = tonumber(r[6]) or 0, fac = r[8] ~= "" and r[8] or nil,
                class = r[9] ~= "" and r[9] or nil, race = r[10] ~= "" and r[10] or nil, quest = tonumber(r[11]), dialogue = r[12] == "1" or nil})
        end
        add(a, b); if r[7] ~= "1" then add(b, a) end
    end
    for _, r in ipairs(rows(source.barriers)) do
        local rect = geometry[tonumber(r[1])]
        local a, b = {cont = tonumber(r[6]), wx = tonumber(r[7]), wy = tonumber(r[8])},
            {cont = tonumber(r[6]), wx = tonumber(r[9]), wy = tonumber(r[10])}
        if rect then
            a.cont, a.wx, a.wy = rect.cont, rect.top - tonumber(r[3]) / 100 * rect.h, rect.left - tonumber(r[2]) / 100 * rect.w
            b.cont, b.wx, b.wy = rect.cont, rect.top - tonumber(r[5]) / 100 * rect.h, rect.left - tonumber(r[4]) / 100 * rect.w
        end
        g.barriers[#g.barriers + 1] = {a, b}
    end
    return g
end
local function distance(a, b)
    if a.cont ~= b.cont then return nil end
    return math.sqrt((a.wx - b.wx)^2 + (a.wy - b.wy)^2)
end
local function evidenceState(g,a,b)
    local ai,bi=a.id or a.auditID,b.id or b.auditID
    return ai and bi and g.evidence[ai .. ">" .. bi]
end
local function geometryPenalty(g,a,b,seconds)
    local state=evidenceState(g,a,b)
    local weight=state=="UNCERTAIN" and 1 or state=="TERRAIN_CLEAR" and .25 or 0
    return weight>0 and weight*(3*seconds+120) or 0
end
local function blocked(g, a, b)
    if evidenceState(g,a,b)=="TERRAIN_BLOCKED" or evidenceState(g,a,b)=="UNAVAILABLE" then return true end
    if a.cont ~= b.cont then return true end
    if a.wx == b.wx and a.wy == b.wy then return false end
    local function orient(p, q, r) return (q.wx - p.wx) * (r.wy - p.wy) - (q.wy - p.wy) * (r.wx - p.wx) end
    for _, wall in ipairs(g.barriers) do
        local c, d = wall[1], wall[2]
        if a.cont == c.cont and a.cont == d.cont then
            local overlaps = math.min(a.wx, b.wx) <= math.max(c.wx, d.wx)+1e-8 and math.min(c.wx, d.wx) <= math.max(a.wx, b.wx)+1e-8
                and math.min(a.wy, b.wy) <= math.max(c.wy, d.wy)+1e-8 and math.min(c.wy, d.wy) <= math.max(a.wy, b.wy)+1e-8
            local x,y,z,w=orient(a,b,c),orient(a,b,d),orient(c,d,a),orient(c,d,b)
            if overlaps and math.min(x,y)<=1e-7 and math.max(x,y)>=-1e-7 and math.min(z,w)<=1e-7 and math.max(z,w)>=-1e-7 then return true end
        end
    end
    return false
end
local function walk(g, a, b, c, actual)
    local d = distance(a, b)
    if not d then return nil end
    local seconds = d * ((g.factors[a.m] or 1.15) + (g.factors[b.m] or 1.15)) / 2 / (g.indoor[b.area] and c.run or c.ground)
    return seconds
end
local function hostile(g, n, c)
    return n.city and g.cities[n.city] and g.cities[n.city] ~= "" and g.cities[n.city] ~= c.faction
end
local function permitted(l, mode, c, known)
    if (l.fac and l.fac ~= c.faction) or (l.class and l.class ~= c.class) or (l.race and l.race ~= c.race)
        or (l.quest and not (M.completedQuests or {})[l.quest]) then return false end
    if l.method == "taxi" then
        return c.flights and (l.dialogue or (l.from.discoverable and l.to.discoverable
            and (known[l.from.taxi] == true or mode == 2) and known[l.to.taxi] == true))
            and (not l.from.fac or l.from.fac == c.faction) and (not l.to.fac or l.to.fac == c.faction)
    end
    if l.method == "ship" or l.method == "zeppelin" or l.method == "tram" then return c.boats end
    return true
end
local function linkCost(g, l, mode, c, actual)
    if l.method == "gate" then return 0 end
    if l.method == "walk" or l.method == "lift" then return l.cost and l.cost > 0 and l.cost or walk(g, l.from, l.to, c, actual) or 0 end
    if l.method == "taxi" then return (l.cost or 0) * c.flightFactor + (mode == 1 and not l.dialogue and 0 or 6) end
    return (l.cost or 0) + l.screens * 10
end
local function clone(n)
    local t = {}
    for k, v in pairs(n) do if k ~= "id" and k ~= "index" then t[k] = v end end
    t.auditID = n.id
    return t
end
local function context(extra)
    local c = {faction = faction, class = "WARRIOR", race = "Human", level = 60, run = 7, ground = 14,
        flightFactor = 1, flights = true, boats = true, jumps = {}}
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end
-- Expanded graph oracle: numeric states and a sorted queue (no production heap,
-- relaxation, path reconstruction or production geometry helpers are reused).
-- Modes 0=ground, 1=aboard, 2=just unlocked, 3=special flight dialogue.
-- Discover costs six seconds. Risk is never counted as elapsed time.
local function oracle(g, start, goal, c, known, actual, allowUncertain)
    if not g.walkNeighbors then
        g.walkNeighbors = {}
        for _,n in ipairs(g.order) do
            local neighbors = {}
            for _,v in ipairs(g.area[n.area] or {}) do
                if n ~= v and n.city == v.city
                    and (not n.terrainOnly and not v.terrainOnly or (distance(n,v) or math.huge)<=3)
                    and not blocked(g,n,v) then neighbors[#neighbors+1] = v end
            end
            g.walkNeighbors[n.index] = neighbors
        end
    end
    local dist, queue, head = {}, {}, 1
    local function state(n, mode) return (n.index - 1) * 4 + mode + 1 end
    local function offer(n, mode, cost)
        local id = state(n, mode)
        if dist[id] and dist[id] <= cost + 1e-8 then return end
        dist[id] = cost
        local lo, hi = head, #queue + 1
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            if queue[mid][1] <= cost then lo = mid + 1 else hi = mid end
        end
        table.insert(queue, lo, {cost, id})
    end
    local function canInfer(a, b)
        return a.area == b.area and a.city == b.city
            and (not a.terrainOnly and not b.terrainOnly or (distance(a,b) or math.huge)<=3)
            and not blocked(g, a, b)
            and (allowUncertain or evidenceState(g,a,b)~="UNCERTAIN")
            and (not hostile(g, b, c) or b.city == start.city or b.city == goal.city)
    end
    local function walkScore(a,b)
        local seconds=walk(g,a,b,c,actual)
        return seconds and seconds+geometryPenalty(g,a,b,seconds)
    end
    local bestGoal = canInfer(start, goal) and walkScore(start,goal) or math.huge
    for _, v in ipairs(g.area[start.area] or {}) do if canInfer(start, v) then offer(v, 0, walkScore(start,v)) end end
    for _,v in ipairs(g.order) do
        if v.terrainOnly and (distance(start,v) or math.huge)<=3 then offer(v,0,walkScore(start,v)) end
    end
    for _, j in ipairs(c.jumps) do offer(g.nodes[j.node.id], 0, j.cost) end
    while head <= #queue do
        local item = queue[head]; head = head + 1
        local cost, id = item[1], item[2]
        if cost > bestGoal then break end
        if cost == dist[id] then
            local n, mode = g.order[math.floor((id - 1) / 4) + 1], (id - 1) % 4
            if canInfer(n, goal) then bestGoal = math.min(bestGoal, cost + walkScore(n,goal)) end
            for _, v in ipairs(g.walkNeighbors[n.index]) do
                if v ~= n and canInfer(n, v) then offer(v, 0, cost + walkScore(n,v)) end
            end
            if n.terrainOnly and (distance(n,goal) or math.huge)<=3 then bestGoal=math.min(bestGoal,cost+walkScore(n,goal)) end
            for _, l in ipairs(g.out[n.index]) do
                local ground=l.method=="walk" or l.method=="gate" or l.method=="lift"
                local state=ground and evidenceState(g,n,l.to)
                if permitted(l, mode, c, known) and state~="TERRAIN_BLOCKED" and state~="UNAVAILABLE" and (allowUncertain or state~="UNCERTAIN") then
                    local seconds=linkCost(g,l,mode,c,actual)
                    offer(l.to,l.method=="taxi" and (l.dialogue and 3 or 1) or 0,cost+seconds+(ground and geometryPenalty(g,n,l.to,seconds) or 0))
                end
            end
            if mode == 0 and n.taxi and n.discoverable and c.flights and known[n.taxi] ~= true
                and (not n.fac or n.fac == c.faction) and not hostile(g, n, c) then offer(n, 2, cost + 6) end
        end
    end
    if bestGoal==math.huge and not allowUncertain then return oracle(g,start,goal,c,known,actual,true) end
    return bestGoal
end
local longs, reversals, maxLeg, discoveredRoutes, taxiRoutes, crossed = {}, {}, 0, 0, 0, 0
local function label(path)
    local t = {}
    for _, e in ipairs(path or {}) do t[#t + 1] = (e.node.id or (e == path[1] and "origin" or "goal")) ..
        (type(e.via) == "table" and e.via.kind == "discover" and "[unlock]" or "") end
    return table.concat(t, " -> ")
end
local function runCase(g, a, b, c, tag, expected, actual)
    cases = cases + 1
    local known = T.Know().flights
    local snapshot = {}; for k, v in pairs(known) do snapshot[k] = v end
    local optimum = oracle(g, a, b, c, known, actual)
    local path, total,_,geometry = T.Search(a, b, c)
    check(T.lastExpanded<=4000,"planner-state-cap","Search exceeded existing 4000 expansion limit")
    local desc = "WaypointTracker/Travel.lua " .. tag .. " value=" .. tostring(total) .. " optimum=" .. tostring(optimum)
    check((path ~= nil) == (optimum < math.huge), "reachability", desc)
    if path then
        if not actual then check(math.abs(total + (geometry or 0) - optimum) < 1e-4, "least-graph-time", desc .. " path=" .. label(path)) end
        check(path[1].node == a and path[#path].node == b, "endpoint", desc)
        local seen, mode, cumulative, gotTaxi, gotDiscover = {}, 0, 0, false, false
        for i = 2, #path do
            local e, from = path[i], path[i - 1].node
            local n = e.node.id and g.nodes[e.node.id] or e.node
            local prev = from.id and g.nodes[from.id] or from
            check(not hostile(g, n, c) or n.city == a.city or n.city == b.city,
                "hostile-city-transit", desc .. " entry=" .. (n.id or "goal"))
            local how, cost = e.via
            if how == "walk" or type(how)=="table" and how.implicit then
                check(prev.area == n.area and prev.city == n.city and not blocked(g, prev, n), "illegal-walk", desc .. " entry=" .. (n.id or "goal"))
                cost = walk(g, prev, n, c, actual); mode = 0
                local length = distance(prev, n) or 0
                maxLeg = math.max(maxLeg, length)
                if length > 2000 and (tag:find("^Alliance/") or tag:find("^Horde/")) then
                    local key = (prev.id or prev.auditID or "origin") .. ">" .. (n.id or n.auditID or "goal")
                    longs[key] = math.max(longs[key] or 0, length)
                end
            elseif type(how) == "table" and how.kind == "discover" then
                check(from == e.node and mode == 0 and n.discoverable and known[n.taxi] ~= true and (not n.fac or n.fac == c.faction), "invalid-discovery", desc)
                cost, mode, gotDiscover = 6, 2, true
            elseif type(how) == "table" and how.kind then
                cost, mode = how.cost, 0
            else
                local found
                for _, l in ipairs(g.out[prev.index] or {}) do
                    if l.to.id == n.id and l.method == how.method and l.cost == how.cost
                        and l.fac == how.fac and l.class == how.class and l.race == how.race and l.quest == how.quest
                        and l.dialogue == how.dialogue then found = l; break end
                end
                check(found and permitted(found, mode, c, known), "faction-or-unusable-link", desc .. " entry=" .. (n.id or "goal"))
                cost = found and linkCost(g, found, mode, c, actual)
                if how.method == "taxi" then
                    gotTaxi = true
                    check(prev.cont == n.cont, "cross-continent-taxi", desc .. " entry=" .. n.id)
                end
                if prev.cont ~= n.cont then
                    crossed = crossed + 1
                    check(how.method ~= "walk" and how.method ~= "gate" and how.method ~= "lift", "cross-continent-ground", desc)
                end
                mode = how.method == "taxi" and (how.dialogue and 3 or 1) or 0
            end
            cumulative = cumulative + (cost or 0)
            if not actual then check(math.abs(e.at - cumulative) < 1e-4, "incorrect-ETA", desc .. " entry=" .. (n.id or "goal")) end
            local key = (n.id or "goal") .. ":" .. mode
            check(not seen[key], "state-cycle-backtracking", desc .. " entry=" .. key)
            seen[key] = true
            if i > 2 and how == "walk" and path[i - 1].via == "walk" then
                local p = path[i - 2].node
                local pp = p.id and g.nodes[p.id] or p
                local ux, uy, vx, vy = prev.wx - pp.wx, prev.wy - pp.wy, n.wx - prev.wx, n.wy - prev.wy
                local len = math.sqrt((ux*ux + uy*uy) * (vx*vx + vy*vy))
                if len > 0 and (ux*vx + uy*vy) / len < -.5 then reversals[(prev.id or "origin") .. ">" .. (n.id or "goal")] = true end
            end
        end
        if actual then
            check(math.abs(cumulative + (geometry or 0) - optimum) < 1e-4, "least-actual-time",
                desc .. " selected-elapsed=" .. cumulative .. " path=" .. label(path))
            check(math.abs(total - cumulative) < 1e-4, "danger-inflated-ETA",
                desc .. " selected-elapsed=" .. cumulative .. "; displayed seconds include risk penalty")
        end
        if gotTaxi then taxiRoutes = taxiRoutes + 1 end
        if gotDiscover then discoveredRoutes = discoveredRoutes + 1 end
        if expected then check(expected(path, total, gotTaxi, gotDiscover), "fixture-property", desc .. " path=" .. label(path)) end
    elseif expected then check(expected(nil), "fixture-property", desc) end
    for k, v in pairs(known) do check(snapshot[k] == v, "hypothetical-knowledge-write", desc .. " taxi=" .. k) end
    for k, v in pairs(snapshot) do check(known[k] == v, "hypothetical-knowledge-write", desc .. " taxi=" .. k) end
    return path, total
end
local g = graph(raw)
-- Deterministic representatives: all friendly taxis/crossings/docks/city gates,
-- sampled evenly from sorted ids separately on each continent.
for _, fac in ipairs({"Alliance", "Horde"}) do
    faction = fac
    local selected = {}
    for cont = 0, 1 do
        local pool = {}
        for _, n in ipairs(g.order) do
            if not n.terrainOnly and n.cont == cont and n.kind ~= "inn" and n.kind ~= "settlement" and (not n.fac or n.fac == fac)
                and not hostile(g, n, context()) then pool[#pool + 1] = n end
        end
        for i = 0, 15 do selected[#selected + 1] = pool[1 + math.floor(i * (#pool - 1) / 15)] end
    end
    for _, knownSet in ipairs({"all", "none", "alternating", "sparse", "explicit-false"}) do
        local known = T.Know().flights; wipe(known)
        for _, n in ipairs(g.order) do
            if n.taxi then
                if knownSet == "all" or (knownSet == "alternating" and n.taxi % 2 == 0)
                    or (knownSet == "sparse" and n.taxi % 7 == 0) then known[n.taxi] = true
                elseif knownSet == "explicit-false" then known[n.taxi] = false end
            end
        end
        local c = context()
        for i, a in ipairs(selected) do
            -- Eight destinations per origin include each continent and same-area.
            for j = 0, 7 do
                local b = selected[1 + ((i - 1 + j * 5) % #selected)]
                runCase(g, clone(a), clone(b), c, fac .. "/" .. knownSet .. " " .. a.id .. ">" .. b.id)
            end
        end
    end
    wipe(T.Know().flights)
    for _, n in ipairs(g.order) do if n.taxi then T.Know().flights[n.taxi] = true end end
    for i=1,16 do
        local a, b = selected[i], selected[1 + ((i * 7) % #selected)]
        runCase(g, clone(a), clone(b), context({ground=7, flightFactor=1/1.2}), fac .. "/fast-flights " .. a.id .. ">" .. b.id)
        runCase(g, clone(a), clone(b), context({ground=7, flights=false, boats=false}), fac .. "/ground-only " .. a.id .. ">" .. b.id)
        runCase(g, clone(a), clone(b), context({level=1, ground=7}), fac .. "/least-actual-time " .. a.id .. ">" .. b.id, nil, true)
    end
end
for _, profile in ipairs({{"Alliance", "TAXI_62", "TAXI_27"}, {"Horde", "TAXI_63", "TAXI_22"}}) do
    faction = profile[1]; wipe(T.Know().flights)
    local from, to = g.nodes[profile[2]], g.nodes[profile[3]]
    runCase(g, clone(from), clone(to), context({class="DRUID"}), faction .. "/druid-flight-dialogue " .. from.id .. ">" .. to.id,
        function(_, _, taxi, discover) return taxi and not discover end)
end
print("Shipped sweep: " .. cases .. " cases; " .. #g.order .. " graph nodes; two factions, two continents, five knowledge sets")
-- Exercise the player/waypoint/context/arrow integration at actual client map
-- coordinates, including route descriptions. Goals and starts use AreaAt here,
-- so the oracle uses the same resolved routing area rather than an FM's record.
if next(geometry) then
    local playerNode
    local oldPlayerMap, oldPlayerWorld = ns.Geo.GetPlayerMapPosition, ns.Geo.GetPlayerWorld
    ns.Geo.GetPlayerMapPosition = function() return playerNode.m, playerNode.x, playerNode.y end
    ns.Geo.GetPlayerWorld = function() return playerNode.cont, playerNode.wx, playerNode.wy end
    ns.Set("realRoutes", true); ns.Set("travelHearth", false); ns.Set("travelTrails", false)
    ns.Set("travelFlights", true); ns.Set("travelBoats", true)
    T.Know().mountSpeed = 14
    for _, fac in ipairs({"Alliance", "Horde"}) do
        faction = fac; wipe(T.Know().flights)
        for _, n in ipairs(g.order) do if n.taxi and (not n.fac or n.fac == fac) then T.Know().flights[n.taxi] = true end end
        local pool = {}
        for _, n in ipairs(g.order) do if n.taxi and (not n.fac or n.fac == fac) and geometry[n.m] then pool[#pool + 1] = n end end
        for i = 1, 16 do
            playerNode = pool[1 + math.floor((i - 1) * (#pool - 1) / 15)]
            local dest = pool[1 + ((i * 7) % #pool)]
            local from, to = clone(playerNode), clone(dest)
            from.area, from.city = T.AreaAt(from.m, from.x, from.y)
            to.area, to.city = T.AreaAt(to.m, to.x, to.y)
            local wp = {m=to.m, x=to.x, y=to.y, title="audit", id="audit-real-" .. i}
            M.now = M.now + 3; T.Invalidate()
            local steering = T.Steer(wp)
            local p = T.Current()
            local optimum = oracle(g, from, to, context(), T.Know().flights)
            local tag = "Travel.lua Steer " .. fac .. " " .. playerNode.id .. ">" .. dest.id .. " value=" .. tostring(p and p.total) .. " optimum=" .. optimum
            check((p ~= nil) == (optimum < math.huge), "steering-reachability", tag)
            if p then
                check(math.abs(p.total-optimum) < 1e-4, "steering-optimality", tag)
                check(#T.Describe(p) > 0, "steering-description", tag)
                check(steering or (#p.path == 2 and p.path[2].via == "walk"), "steering-instruction", tag)
                if steering and steering.bearing then check(p.target.node.cont == from.cont, "steering-cross-continent-bearing", tag) end
            else check(steering and steering.pin and not steering.bearing, "steering-unreachable-fallback", tag) end
        end
    end
    ns.Geo.GetPlayerMapPosition, ns.Geo.GetPlayerWorld = oldPlayerMap, oldPlayerWorld
    T.Know().mountSpeed = nil
    print("End-to-end shipped steering: 32 origin/destination cases")
end
-- Compact fixtures pin exact numbers and adversarial graph structures.
local function node(id, kind, area, wx, wy, taxi, fac, city, cont)
    return table.concat({id, kind, area, cont or 0, wx, wy, 9900 + area, 50, 50, city or "", "", taxi or "", fac or ""}, "\t")
end
local function fixture(nodes, links, extra)
    local r = {areas = {"a", "b", "c"}, indoor = {}, nodes = table.concat(nodes, "\n"), links = table.concat(links, "\n"),
        maps = "9901\t1\n9902\t2\n9903\t3", cities = "", barriers = "", levels = "", factors = "", regions = ""}
    for k, v in pairs(extra or {}) do r[k] = v end
    ns.TravelData = r; T._Reset(); T.Data(); wipe(T.Know().flights)
    return graph(r)
end
local function link(a, b, method, seconds, fac, oneway)
    return table.concat({a, b, method, seconds, "", "", oneway == false and "" or "1", fac or "", "", "", ""}, "\t")
end
faction = "Alliance"
local c = context({ground = 7})
local f = fixture({node("A", "taxi", 1, 100, 0, 101, faction), node("B", "taxi", 1, 4900, 0, 102, faction)},
    {link("A", "B", "taxi", 30, faction)})
local a, b = clone(f.nodes.A), clone(f.nodes.B); a.wx = 0; b.wx = 5000
T.Know().flights[102] = true
runCase(f, a, b, c, "unlock-nearby-FM-faster", function(_, t, taxi, discover) return taxi and discover and math.abs(t - (200*1.15/7+42)) < 1e-4 end)
check(T.Know().flights[101] == nil, "hypothetical-knowledge-write", "Travel.lua planned discovery must not mark TAXI_101 known")
T.Know().flights[101] = false
runCase(f, a, b, c, "explicitly-unreachable-origin-can-be-unlocked", function(_, _, taxi, discover) return taxi and discover end)
T.Know().flights[101] = true
runCase(f, a, b, c, "known-faster-flight", function(_, _, taxi, discover) return taxi and not discover end)
T.Know().flights[101] = nil; T.Know().flights[102] = nil
runCase(f, a, b, c, "unknown-destination-cannot-land", function(_, _, taxi, discover) return not taxi and not discover end)
T.Know().flights[102] = true; local near = clone(b); near.wx = 50
runCase(f, a, near, c, "unlock-detour-slower-than-direct", function(_, _, taxi, discover) return not taxi and not discover end)
runCase(f, a, b, context({flights = false}), "flights-disabled", function(_, _, taxi, discover) return not taxi and not discover end)
runCase(f, a, b, context({faction = "Horde"}), "enemy-FM-cannot-unlock", function(_, _, taxi, discover) return not taxi and not discover end)
-- A cheapest ground arrival at a connecting FM must not discard a slightly
-- slower aboard arrival that avoids the next six-second boarding charge.
f = fixture({node("A", "taxi", 1, 0, 0, 101, faction), node("B", "taxi", 1, 120, 0, 102, faction),
    node("C", "taxi", 2, 10000, 0, 103, faction)}, {link("A", "B", "taxi", 15, faction), link("B", "C", "taxi", 30, faction)})
for _, id in ipairs({101,102,103}) do T.Know().flights[id] = true end
runCase(f, clone(f.nodes.A), clone(f.nodes.C), c, "aboard-state-optimality", function(_, t) return math.abs(t-51) < 1e-4 end)
-- Disconnected continents never get an implicit walking edge.
f = fixture({node("A", "border", 1, 0, 0), node("B", "border", 1, 0, 0, nil, nil, nil, 1)}, {})
runCase(f, clone(f.nodes.A), clone(f.nodes.B), c, "disconnected-continents", function(p) return p == nil end)
f = fixture({node("A", "dock", 1, 0, 0), node("B", "dock", 2, 0, 0, nil, nil, nil, 1)}, {link("A", "B", "ship", 50, faction)})
runCase(f, clone(f.nodes.A), clone(f.nodes.B), c, "valid-cross-continent-ship", function(_, t) return math.abs(t-50) < 1e-4 end)
runCase(f, clone(f.nodes.A), clone(f.nodes.B), context({boats=false}), "boats-disabled", function(p) return p == nil end)
-- Product objective is elapsed travel time, not time multiplied by danger.
f = fixture({node("A", "border", 1, 0, 0), node("B", "border", 2, 100, 0), node("C", "border", 3, 200, 0)},
    {link("A", "B", "walk", 0), link("B", "C", "walk", 0), link("A", "C", "walk", 38)}, {levels = "9902\t40\t50"})
runCase(f, clone(f.nodes.A), clone(f.nodes.C), context({level=1, ground=7}), "low-level-danger-penalty", nil, true)
-- End-to-end steering at/near an unknown FM must show its unlock action.
f = fixture({node("A", "taxi", 1, 100, 0, 101, faction), node("B", "taxi", 1, 4900, 0, 102, faction)}, {link("A", "B", "taxi", 30, faction)})
T.Know().flights[102] = true
local wp = {m=9901, x=.9, y=.9, title="audit goal", id="audit"}
local player = {area=1, cont=0, wx=0, wy=0, m=9901, x=.1, y=.1}
local goal = {area=1, cont=0, wx=5000, wy=0, m=9901, x=.9, y=.9}
ns.Geo.GetPlayerMapPosition = function() return player.m, player.x, player.y end
ns.Geo.MapToWorld = function(m, x, y)
    if m == wp.m and x == wp.x and y == wp.y then return goal.cont, goal.wx, goal.wy end
    if m == player.m and x == player.x and y == player.y then return player.cont, player.wx, player.wy end
end
ns.Geo.GetPlayerWorld = function() return player.cont, player.wx, player.wy end
ns.Set("realRoutes", true); ns.Set("travelHearth", false); ns.Set("travelTrails", false)
ns.Set("travelFlights", true); ns.Set("travelBoats", true)
local s = T.Steer(wp)
check(s and s.bearing and T.Current().target.node.id == "A", "steering-unlock-approach", "Travel.lua unknown nearby A must be the first directional target")
player.wx = 100; M.now = M.now + 3
s = T.Steer(wp)
check(s and s.pin and T.Current() and type(T.Current().target.via) == "table" and T.Current().target.via.kind == "discover",
    "steering-unlock-action", "Travel.lua at unknown A must pin the discovery action")
-- With an impassable barrier and no surveyed bypass, a nil route must not
-- cause Arrow.lua's direct-bearing fallback through that barrier.
f = fixture({node("A", "border", 1, 0, 0), node("B", "border", 1, 100, 0)}, {},
    {barriers="9901\t0\t0\t100\t100\t0\t50\t-100\t50\t100"})
player.wx, goal.wx = 0, 100
runCase(f, clone(f.nodes.A), clone(f.nodes.B), c, "barrier-with-no-bypass", function(p) return p == nil end)
M.now = M.now + 3; s = T.Steer(wp)
check(s and s.pin and not s.bearing, "unsafe-unreachable-fallback",
    "WaypointTracker/Travel.lua pin=" .. tostring(s and s.pin) .. " bearing=" .. tostring(s and s.bearing)
    .. " for blocked same-area goal; Arrow.lua:552 uses direct-bearing fallback if steering is nil; expected non-directional blocked-route indication")
local count, longList, reversalCount = 0, {}, 0
for key, n in pairs(longs) do longList[#longList+1] = {key, n} end
table.sort(longList, function(a,b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
for _ in pairs(reversals) do reversalCount = reversalCount + 1 end
print(("Coverage: %d cases, %d assertions, %d taxi routes, %d unlock routes, %d cross-continent transport legs"):format(cases, checks, taxiRoutes, discoveredRoutes, crossed))
print(("REVIEW: %d unique implicit walking legs >2000 yards (maximum %.1f); %d geometric reversals >120 degrees; these need terrain verification, not automatic rejection"):format(#longList,maxLeg,reversalCount))
for i=1,(options["--details"] and #longList or math.min(8,#longList)) do print(("REVIEW WaypointTracker/TravelData.lua entry=%s value=%.1f yards: unsurveyed straight walking leg"):format(longList[i][1],longList[i][2])) end
if options["--strict-long-legs"] then check(#longList == 0, "unverified-long-legs", "TravelData.lua " .. #longList .. " long legs require surveyed corridors") end
for _, path in ipairs({"WaypointTracker/Travel.lua", "WaypointTracker/TravelData.lua", "tests/wowmock.lua"}) do
    check(fileText(path) == sourceSnapshot[path], "input-changed", path .. " changed during this audit; rerun against a stable snapshot")
end
local keys = {}; for k in pairs(failures) do keys[#keys + 1] = k end; table.sort(keys)
for _, k in ipairs(keys) do print("FAIL summary [" .. k .. "]: " .. failures[k]); count = count + failures[k] end
print(("Planner audit: %d checks passed, %d failed"):format(checks-count,count))
os.exit(count == 0 and 0 or 1)
