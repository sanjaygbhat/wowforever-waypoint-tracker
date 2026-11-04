-- Offline terrain audit helper; Python supplies client map geometry and probes.
-- Run through: python3 tools/validate_terrain_geometry.py
-- Uses Lua 5.1, the addon's toolchain. Loads real Geo/planner code, no UI/game.
local maps, probes = {}, {}
local function fields(line)
    local f = {}
    for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
    return f
end
for line in io.lines() do
    local f = fields(line)
    if f[1] == "M" then
        maps[tonumber(f[2])] = { cont = tonumber(f[3]), top = tonumber(f[4]),
            left = tonumber(f[5]), h = tonumber(f[6]), w = tonumber(f[7]),
            parentMapID = tonumber(f[8]), mapType = tonumber(f[9]), mapID = tonumber(f[2]) }
    else probes[#probes + 1] = f end
end
assert(next(maps), "no client map input; run python3 tools/validate_terrain_geometry.py with Lua 5.1")
local function noop() end
local ns = { L = {}, WP = {}, RegisterEvent = noop, On = noop, Fire = noop,
    charDB = { travel = { flights = {} } } }
function ns.Num(value) return type(value) == "number" and value or nil end
function ns.XY(pos) return pos.x, pos.y end
C_Map = {}
function C_Map.GetWorldPosFromMapPos(m, pos)
    local a = maps[m]
    if a then return a.cont, { x = a.top - pos.y * a.h, y = a.left - pos.x * a.w } end
end
function C_Map.GetMapInfo(m) return maps[m] end
function C_Map.GetMapPosFromWorldPos(cont, pos, m)
    local a = maps[m]
    if a and a.cont == cont then return m, { x = (a.left - pos.y) / a.w, y = (a.top - pos.x) / a.h } end
end
assert(loadfile("WaypointTracker/Geo.lua"))("WaypointTracker", ns)
assert(loadfile("WaypointTracker/TravelData.lua"))("WaypointTracker", ns)
ns.Plain = function(v) return v end
ns.Get = function() return false end
ns.Call = function(fn) return fn() end
CreateFrame = function() return {SetScript = function() end} end
assert(loadfile("WaypointTracker/Terrain.lua"))("WaypointTracker", ns)
assert(loadfile("WaypointTracker/Travel.lua"))("WaypointTracker", ns)
local T, d = ns.Travel, ns.Travel.Data()
-- Test the production predicate itself without copying it into the test.
local canWalk
for i = 1, 100 do
    local name, value = debug.getupvalue(T.Search, i)
    if not name then break end
    if name == "CanWalk" then canWalk = value; break end
end
assert(canWalk, "Travel.Search no longer exposes CanWalk; update terrain audit integration")
local failed, checked = 0, 0
for _, f in ipairs(probes) do
    checked = checked + 1
    if f[1] == "P" then
        local a = { cont = tonumber(f[2]), wx = tonumber(f[3]), wy = tonumber(f[4]) }
        local b = { cont = tonumber(f[5]), wx = tonumber(f[6]), wy = tonumber(f[7]) }
        local actual = canWalk(a, b)
        if actual ~= (f[8] == "1") then
            failed = failed + 1
            print("FAIL RUNTIME_BARRIER " .. f[9] .. " actual=" .. tostring(actual) .. " expected=" .. f[8])
        end
    elseif f[1] == "A" or f[1] == "N" then
        local actual = T.AreaAt(tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), f[1] == "N" and f[6] or nil)
        if actual ~= tonumber(f[5]) then
            failed = failed + 1
            print("FAIL RUNTIME_AREA " .. f[6] .. " actual=" .. tostring(actual) .. " expected=" .. f[5])
        end
    elseif f[1] == "G" then
        local m, x, y = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
        local cont, wx, wy = ns.Geo.MapToWorld(m, x, y)
        local rx, ry = ns.Geo.WorldToMap(cont, wx, wy, m)
        if cont ~= tonumber(f[5]) or math.abs(wx - tonumber(f[6])) > 1e-6
            or math.abs(wy - tonumber(f[7])) > 1e-6 or not rx or not ry
            or math.abs(rx - x) > 1e-10 or math.abs(ry - y) > 1e-10 then
            failed = failed + 1
            print("FAIL RUNTIME_TRANSFORM map=" .. m .. " x=" .. x .. " y=" .. y)
        end
    elseif f[1] == "O" then
        local m, x, y, other = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
        local ox, oy = ns.Geo.TranslateToMap(m, x, y, other)
        if not ox or not oy or math.abs(ox - tonumber(f[6])) > 1e-10
            or math.abs(oy - tonumber(f[7])) > 1e-10 then
            failed = failed + 1
            print("FAIL RUNTIME_OVERLAP maps=" .. m .. ">" .. other .. " x=" .. x .. " y=" .. y)
        end
    end
end
-- Physical access regressions. A planner route to the graph flight master
-- must respect the existing access connection, including Freewind's lift.
local cases = {
    { "LIFT_FREEWIND_POST_BOTTOM", "TAXI_30", "lift", "Horde" },
    { "PASS_THERAMORE_BRIDGE_MAINLAND", "TAXI_32", "connection", "Alliance" },
    { "PASS_NIJELS_POINT_RAMP_LOW", "TAXI_37", "connection", "Alliance" },
    { "DOCK_FORGOTTENCOAST", "TAXI_41", "ship", "Alliance" },
    { "ENTRANCE_SW_WIZARDS_SANCTUM_OUTER", "PORTAL_STORMWIND_DALARAN", "connection", "Alliance" },
    { "PORTAL_STORMWIND_DALARAN", "ENTRANCE_SW_WIZARDS_SANCTUM_OUTER", "connection", "Alliance" },
}
local function isConnection(how, target)
    if type(how) ~= "table" then return false end
    return how.from.area ~= how.to.area
        and (how.from.area == target.area or how.to.area == target.area)
end
for _, c in ipairs(cases) do
    local a, b = d.nodes[c[1]], d.nodes[c[2]]
    assert(a and b, "missing regression anchor " .. c[1] .. " or " .. c[2])
    -- The target's physical area is authoritative for the access requirement.
    local physicalArea = T.AreaAt(b.m, b.x, b.y, b.id)
    local path, cost = T.Search(a, b, { faction = c[4], run = 7, ground = 7, level = 60,
        flights = false, boats = true, flightFactor = 1, jumps = {} })
    local used, ids = false, {}
    for _, e in ipairs(path or {}) do
        ids[#ids + 1] = e.node.id or "goal"
        local h = e.via
        if c[3] == "connection" then
            used = used or isConnection(h, { area = physicalArea })
        elseif type(h) == "table" then
            used = used or h.method == c[3]
        end
    end
    checked = checked + 1
    if not path or not used then
        failed = failed + 1
        print("FAIL RUNTIME_ACCESS " .. c[1] .. " -> " .. c[2] .. " physicalArea="
            .. tostring(physicalArea) .. " requires=" .. c[3] .. " cost=" .. tostring(cost)
            .. " path=" .. table.concat(ids, " -> "))
    end
end
-- WMO context applies only to registered, marked anchors at their own exact
-- coordinates. It must not turn the doorway/nearby surface into a room circle.
local function check(value, label)
    checked = checked + 1
    if not value then failed = failed + 1; print("FAIL RUNTIME_INDOOR " .. label) end
end
local outer = assert(d.nodes.ENTRANCE_SW_WIZARDS_SANCTUM_OUTER)
for _, id in ipairs({ "ENTRANCE_SW_WIZARDS_SANCTUM_INNER", "PORTAL_STORMWIND_DALARAN" }) do
    local n = assert(d.nodes[id])
    check(n.indoorOverride and d.indoor[n.area], id .. " parsed indoor marker")
    check(n.area ~= outer.area, id .. " distinct walking group")
    check(T.AreaAt(n.m, n.x, n.y) == outer.area, id .. " surface remains unclassified indoors")
    local area, city = T.AreaAt(n.m, n.x, n.y, id)
    check(area == n.area and city == n.city, id .. " captured anchor context")
    check(T.AreaAt(n.m, n.x + .000001, n.y, id) == outer.area, id .. " no guessed footprint")
    check(T.AreaAt(outer.m, outer.x, outer.y, id) == outer.area, id .. " exterior is surface")
    check(T.AreaAt(n.m, n.x, n.y, "UNKNOWN_INDOOR_NODE") == outer.area, id .. " unknown ID rejected")
    check(T.AreaAt(n.m, n.x, n.y, { id = id, indoorOverride = true }) == outer.area, id .. " fabricated context rejected")
    n.indoorOverride = nil
    check(T.AreaAt(n.m, n.x, n.y, id) == outer.area, id .. " runtime requires marker")
    n.indoorOverride = true
end
check(not outer.indoorOverride and T.AreaAt(outer.m, outer.x, outer.y, outer.id) == outer.area,
    "exterior has no override")
local inner, portal = d.nodes.ENTRANCE_SW_WIZARDS_SANCTUM_INNER, d.nodes.PORTAL_STORMWIND_DALARAN
local function context(ground, faction, race)
    return { faction = faction or "Alliance", race = race, run = 7, ground = ground, level = 60,
        flights = false, boats = false, flightFactor = 1, jumps = {} }
end
local _, foot = T.Search(inner, portal, context(7))
local _, mounted = T.Search(inner, portal, context(14))
check(foot and mounted and foot > 0 and math.abs(foot - mounted) < 1e-9, "indoor walking uses running speed")
local dalaran = assert(d.nodes.PORTAL_DALARAN_STORMWIND)
for _, pair in ipairs({ { portal, dalaran }, { dalaran, portal } }) do
    for _, c in ipairs({ context(7, "Alliance", "Skyborne"), context(7, "Alliance", "Human"),
        context(7, "Horde", "Skyborne") }) do
        local path = T.Search(pair[1], pair[2], c)
        local used = false
        for _, e in ipairs(path or {}) do
            used = used or (type(e.via) == "table" and e.via.method == "portal")
        end
        check(used == (c.faction == "Alliance" and c.race == "Skyborne"),
            "portal eligibility " .. pair[1].id .. " " .. c.faction .. " " .. c.race)
    end
end
print("RUNTIME checked=" .. checked .. " failed=" .. failed)
os.exit(failed == 0 and 0 or 1)
