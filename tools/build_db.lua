-- Builds WaypointTracker_Data (the load-on-demand database used by the Find
-- window) from pfQuest's database (MIT licence, (c) Shagu,
-- https://github.com/shagu/pfQuest).
--
--     git clone --depth 1 https://github.com/shagu/pfQuest /tmp/pfQuest
--     lua5.1 tools/build_db.lua /tmp/pfQuest
--
-- Output is written as long strings, which load very fast, and parsed
-- lazily in game:
--   WaypointTracker_Data/Data.lua         spawn points, quest links, services
--   WaypointTracker_Data/Names_<loc>.lua  names in each client language
local PF = assert(arg[1], "usage: lua5.1 tools/build_db.lua <path to pfQuest>")
local OUT = "WaypointTracker_Data/"
local LOCALES = { "enUS", "deDE", "frFR", "esES", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
local MAX_SPAWNS_PER_ZONE = 25
local MAX_ITEM_SOURCES = 12

pfDB = {}
for _, k in ipairs({ "items", "units", "objects", "quests", "zones", "meta" }) do
    pfDB[k] = {}
end
local function load(file)
    local chunk = assert(loadfile(PF .. "/db/" .. file))
    chunk()
end
for _, f in ipairs({ "units.lua", "objects.lua", "quests.lua", "items.lua", "meta.lua" }) do
    load(f)
end
for _, loc in ipairs(LOCALES) do
    for _, f in ipairs({ "units", "objects", "quests", "items", "zones" }) do
        local path = PF .. "/db/" .. loc .. "/" .. f .. ".lua"
        local fh = io.open(path)
        if fh then
            fh:close()
            load(loc .. "/" .. f .. ".lua")
        end
    end
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

local function clean(s)
    s = tostring(s or "")
    s = s:gsub("[\r\n\t]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("%]==%]", "] ==]")
    return s
end

local JUNK = { "Only GM", "%[UNUSED%]", "^UNUSED", "%[PH%]", "^zz", "^ZZ", "%(OLD%)", "^OLD", "DEPRECATED", "%[DEP%]", "^Test ", " Test$", "TEST" }
local function isJunk(name)
    if not name or name == "" then
        return true
    end
    for _, p in ipairs(JUNK) do
        if name:find(p) then
            return true
        end
    end
    return false
end

-- spawn points: keep one per 1% square, at most MAX_SPAWNS_PER_ZONE per zone
local usedZones = {}
local function encodeCoords(coords)
    local byZone, order = {}, {}
    for _, c in ipairs(coords or {}) do
        local x, y, zone = c[1], c[2], c[3]
        if x and y and zone and x >= 0 and x <= 100 and y >= 0 and y <= 100 and not (x == 0 and y == 0) then
            if not byZone[zone] then
                byZone[zone] = { seen = {}, pts = {} }
                order[#order + 1] = zone
            end
            local z = byZone[zone]
            local cell = math.floor(x) .. ":" .. math.floor(y)
            if not z.seen[cell] then
                z.seen[cell] = true
                z.pts[#z.pts + 1] = { math.floor(x * 10 + 0.5), math.floor(y * 10 + 0.5) }
            end
        end
    end
    local parts = {}
    for _, zone in ipairs(order) do
        local pts = byZone[zone].pts
        local keep = {}
        if #pts <= MAX_SPAWNS_PER_ZONE then
            keep = pts
        else
            for i = 1, MAX_SPAWNS_PER_ZONE do
                keep[i] = pts[math.floor((i - 1) * #pts / MAX_SPAWNS_PER_ZONE) + 1]
            end
        end
        local flat = {}
        for _, p in ipairs(keep) do
            flat[#flat + 1] = p[1] .. "," .. p[2]
        end
        parts[#parts + 1] = zone .. ":" .. table.concat(flat, ",")
        usedZones[zone] = true
    end
    return table.concat(parts, ";")
end

local enUnits = pfDB.units.enUS or {}
local enObjects = pfDB.objects.enUS or {}
local enQuests = pfDB.quests.enUS or {}
local enItems = pfDB.items.enUS or {}

-- units ----------------------------------------------------------------------
local unitLines, keptUnits = {}, {}
for _, id in ipairs(sortedKeys(pfDB.units.data)) do
    local u = pfDB.units.data[id]
    local name = enUnits[id]
    if not isJunk(name) and u.coords and #u.coords > 0 then
        local coords = encodeCoords(u.coords)
        if coords ~= "" then
            keptUnits[id] = true
            unitLines[#unitLines + 1] = table.concat({ id, u.lvl or "", u.fac or "", u.rnk or "", coords }, "\t")
        end
    end
end

-- objects --------------------------------------------------------------------
local objectLines, keptObjects = {}, {}
for _, id in ipairs(sortedKeys(pfDB.objects.data)) do
    local o = pfDB.objects.data[id]
    local name = enObjects[id]
    if not isJunk(name) and o.coords and #o.coords > 0 then
        local coords = encodeCoords(o.coords)
        if coords ~= "" then
            keptObjects[id] = true
            objectLines[#objectLines + 1] = table.concat({ id, o.fac or "", coords }, "\t")
        end
    end
end

-- quests ---------------------------------------------------------------------
local function list(t, filter)
    local out = {}
    for _, v in ipairs(t or {}) do
        if not filter or filter[v] then
            out[#out + 1] = v
        end
    end
    return table.concat(out, ",")
end

local questItems = {}
local questLines, keptQuests = {}, {}
for _, id in ipairs(sortedKeys(pfDB.quests.data)) do
    local q = pfDB.quests.data[id]
    local title = enQuests[id] and enQuests[id].T
    if not isJunk(title) and (q.start or q["end"]) then
        local s, e, o = q.start or {}, q["end"] or {}, q.obj or {}
        for _, item in ipairs(o.I or {}) do
            questItems[item] = true
        end
        keptQuests[id] = true
        questLines[#questLines + 1] = table.concat({
            id, q.lvl or "", q.min or "", q.race or "", q.class or "",
            list(s.U, keptUnits), list(s.O, keptObjects),
            list(e.U, keptUnits), list(e.O, keptObjects),
            list(o.U, keptUnits), list(o.O, keptObjects), list(o.I),
        }, "\t")
    end
end

-- quest items: where to get them --------------------------------------------
local itemLines, keptItems = {}, {}
for _, id in ipairs(sortedKeys(questItems)) do
    local it = pfDB.items.data[id]
    if it and enItems[id] then
        local function top(src, filter)
            local arr = {}
            for sid, chance in pairs(src or {}) do
                if filter[sid] then
                    arr[#arr + 1] = { sid, tonumber(chance) or 0 }
                end
            end
            table.sort(arr, function(a, b)
                if a[2] ~= b[2] then
                    return a[2] > b[2]
                end
                return a[1] < b[1]
            end)
            local out = {}
            for i = 1, math.min(MAX_ITEM_SOURCES, #arr) do
                out[i] = arr[i][1]
            end
            return table.concat(out, ",")
        end
        local u, o, v = top(it.U, keptUnits), top(it.O, keptObjects), top(it.V, keptUnits)
        if u ~= "" or o ~= "" or v ~= "" then
            keptItems[id] = true
            itemLines[#itemLines + 1] = table.concat({ id, u, o, v }, "\t")
        end
    end
end

-- services (mailbox, innkeeper, flight master, ...) -------------------------
local SERVICES = { "mailbox", "innkeeper", "flight", "repair", "banker", "auctioneer", "vendor", "stablemaster", "spirithealer", "battlemaster", "meetingstone" }
local metaLines = {}
for _, cat in ipairs(SERVICES) do
    local entries = {}
    for _, id in ipairs(sortedKeys(pfDB.meta[cat] or {})) do
        local fac = pfDB.meta[cat][id]
        local ok = (id < 0 and keptObjects[-id]) or (id > 0 and keptUnits[id])
        if ok then
            entries[#entries + 1] = id .. ":" .. (type(fac) == "string" and fac or "")
        end
    end
    metaLines[#metaLines + 1] = cat .. "\t" .. table.concat(entries, ",")
end

-- write Data.lua ---------------------------------------------------------------
-- text as a Lua long string, with a bracket level the text can't close
local function LongString(body, level)
    level = level or 2
    while body:find("]" .. ("="):rep(level) .. "]", 1, true) do
        level = level + 1
    end
    local eq = ("="):rep(level)
    return "[" .. eq .. "[\n" .. body .. "\n]" .. eq .. "]"
end

local function block(name, lines)
    return ("    %s = %s,\n"):format(name, LongString(table.concat(lines, "\n")))
end

local header = [[
-- Generated by tools/build_db.lua. Bundled third-party data: see
-- THIRD-PARTY-LICENSES.txt. Do not edit.
]]
local f = assert(io.open(OUT .. "Data.lua", "w"))
f:write(header)
f:write("WaypointTrackerData = WaypointTrackerData or {}\n")
f:write("local D = WaypointTrackerData\n")
f:write("D.version = 1\n")
f:write("D.raw = {\n")
f:write("    -- id, level, friendly to (A/H), rank, spawns (zone:x,y,x,y;zone:...) with x/y in 0.1%\n")
f:write(block("units", unitLines))
f:write("    -- id, friendly to, spawns\n")
f:write(block("objects", objectLines))
f:write("    -- id, level, min level, races, classes, start npcs, start objects, end npcs, end objects, npcs to kill/talk to, objects to use, items to get\n")
f:write(block("quests", questLines))
f:write("    -- id, dropped by npcs, found in objects, sold by npcs\n")
f:write(block("items", itemLines))
f:write("    -- service, id:faction (negative id = object)\n")
f:write(block("services", metaLines))
f:write("}\n")
f:close()

-- write Names_<loc>.lua ---------------------------------------------------------
for _, loc in ipairs(LOCALES) do
    local units, objects, quests, items, zones = {}, {}, {}, {}, {}
    local lu, lo, lq, li, lz = pfDB.units[loc] or {}, pfDB.objects[loc] or {}, pfDB.quests[loc] or {}, pfDB.items[loc] or {}, pfDB.zones[loc] or {}
    for _, id in ipairs(sortedKeys(keptUnits)) do
        if lu[id] then
            units[#units + 1] = id .. "\t" .. clean(lu[id])
        end
    end
    for _, id in ipairs(sortedKeys(keptObjects)) do
        if lo[id] then
            objects[#objects + 1] = id .. "\t" .. clean(lo[id])
        end
    end
    for _, id in ipairs(sortedKeys(keptQuests)) do
        local q = lq[id]
        if q and q.T then
            quests[#quests + 1] = id .. "\t" .. clean(q.T) .. "\t" .. clean(q.O)
        end
    end
    for _, id in ipairs(sortedKeys(keptItems)) do
        if li[id] then
            items[#items + 1] = id .. "\t" .. clean(li[id])
        end
    end
    for _, id in ipairs(sortedKeys(usedZones)) do
        if lz[id] then
            zones[#zones + 1] = id .. "\t" .. clean(lz[id])
        end
    end
    local out = assert(io.open(OUT .. "Names_" .. loc .. ".lua", "w"))
    out:write(header)
    if loc ~= "enUS" then
        local check = loc == "esES" and 'local l = GetLocale()\nif l ~= "esES" and l ~= "esMX" then\n    return\nend\n'
            or ('if GetLocale() ~= "%s" then\n    return\nend\n'):format(loc)
        out:write(check)
    end
    out:write("WaypointTrackerData = WaypointTrackerData or {}\n")
    out:write(("WaypointTrackerData.names_%s = {\n"):format(loc))
    out:write(block("units", units))
    out:write(block("objects", objects))
    out:write("    -- id, title, what to do\n")
    out:write(block("quests", quests))
    out:write(block("items", items))
    out:write(block("zones", zones))
    out:write("}\n")
    out:close()
    print(("%s: %d npcs, %d objects, %d quests, %d items, %d zones"):format(loc, #units, #objects, #quests, #items, #zones))
end
print(("data: %d npcs, %d objects, %d quests, %d quest items"):format(#unitLines, #objectLines, #questLines, #itemLines))
