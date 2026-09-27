-- Builds WaypointTracker_Data/Curated.lua from All The Things' WoW Forever
-- database (MIT licence, https://github.com/ATTWoWAddon/AllTheThings):
-- quest givers and where they stand, NPCs, objects, flight masters, and
-- which NPC or object each item comes from.
--
-- The output uses the same text format as shared discoveries, so the addon
-- merges it the same way (below your own discoveries and other players').
--
-- Usage (from the repository root):
--   lua5.1 tools/build_att.lua /path/to/AllTheThings
package.path = "./tools/?.lua;" .. package.path
local ATT = arg[1] or error("usage: lua5.1 tools/build_att.lua /path/to/AllTheThings")
local OUT = "WaypointTracker_Data/Curated.lua"

local cats = require("att_load").Load(ATT .. "/db/Camelot")

-- ---------------------------------------------------------------------------
-- Names: the compiled database has none (the addon asks the game), but the
-- source files say who is who in their comments.
-- ---------------------------------------------------------------------------
local npcNames, objectNames, questNames = {}, {}, {}
local function Tidy1(s)
    s = s:gsub("\\(.)", "%1"):gsub("<.->", ""):gsub("<.*$", "")
    s = s:gsub("%s*%-%-.*$", ""):gsub("%s*//.*$", "")
    s = s:gsub("%s*%(.-%)%s*$", ""):gsub("%s+", " "):gsub("%s+$", ""):gsub("^%s+", "")
    return s
end
-- "Name [TBC+] / Classic Name": keep the name this era uses
local function Clean(s)
    local first
    for part in (s .. " / "):gmatch("(.-)%s+/%s+") do
        local tagged = part:find("%[%u+%+%]")
        part = Tidy1(part:gsub("%[.-%]", ""))
        if part ~= "" then
            first = first or part
            if not tagged then
                return part
            end
        end
    end
    return first or Tidy1(s:gsub("%[.-%]", ""))
end
local function ReadNames(path)
    local inCrs = false
    for line in io.lines(path) do
        local id, name = line:match("%f[%w]n%((%d+).-%-%-%s*(.+)$")
        if id then
            npcNames[tonumber(id)] = npcNames[tonumber(id)] or Clean(name)
        end
        for _, key in ipairs({ "qg", "cr" }) do
            id, name = line:match("%f[%w\"]" .. key .. "\"?%]?%s*=%s*(%d+),?%s*%-%-%s*(.+)$")
            if id then
                npcNames[tonumber(id)] = npcNames[tonumber(id)] or Clean(name)
            end
        end
        id, name = line:match("%f[%w]o%((%d+).-%-%-%s*(.+)$")
        if id then
            objectNames[tonumber(id)] = objectNames[tonumber(id)] or Clean(name)
        end
        if line:find("crs\"?%]?%s*=%s*{") then
            inCrs = true
        end
        if inCrs then
            id, name = line:match("^%s*(%d+),?%s*%-%-%s*(.+)$")
            if id then
                npcNames[tonumber(id)] = npcNames[tonumber(id)] or Clean(name)
            end
            if line:find("}") then
                inCrs = false
            end
        end
    end
end
-- more ways the source files name things: ["qg"] = 123, -- Name and
-- providers like { "n", 123 }, -- Name
local function ReadMoreNames(path)
    for line in io.lines(path) do
        for _, key in ipairs({ "qg", "cr", "creatureID", "npcID" }) do
            local id, name = line:match("[%[%s,{]\"" .. key .. "\"%]%s*=%s*(%d+),?%s*%-%-%s*(.+)$")
            if id then
                npcNames[tonumber(id)] = npcNames[tonumber(id)] or Clean(name)
            end
        end
        local id, name = line:match("[%[%s,{]\"objectID\"%]%s*=%s*(%d+),?%s*%-%-%s*(.+)$")
        if id then
            objectNames[tonumber(id)] = objectNames[tonumber(id)] or Clean(name)
        end
        id, name = line:match("%f[%w]q%((%d+).-%-%-%s*(.+)$")
        if id then
            questNames[tonumber(id)] = questNames[tonumber(id)] or Clean(name)
        end
        for kind, names in pairs({ n = npcNames, o = objectNames }) do
            id, name = line:match("{%s*\"" .. kind .. "\"%s*,%s*(%d+)%s*}%s*,?%s*%-%-%s*(.+)$")
            if id then
                names[tonumber(id)] = names[tonumber(id)] or Clean(name)
            end
        end
    end
end
local function EachSource(filter, fn)
    local list = io.popen('find "' .. ATT .. '/.contrib/.db/forever" -name "*.lua" ' .. filter .. ' -not -path "*/.config/*"')
    for path in list:lines() do
        fn(path)
    end
    list:close()
end
EachSource('-not -path "*/zzOLD/*"', ReadNames)
EachSource('-not -path "*/zzOLD/*"', ReadMoreNames)
-- ATT's own table of object names (English)
do
    local src = assert(io.open(ATT .. "/db/Camelot/LocalizationDB.lua")):read("*a")
    local block = src:match("local ObjectNames = (%b{})")
    for id, name in (block or ""):gmatch("%[(%d+)%]%s*=%s*\"(.-)\",") do
        objectNames[tonumber(id)] = objectNames[tonumber(id)] or Clean(name)
    end
end
-- last, names from ATT's older files (names rarely change)
EachSource('-path "*/zzOLD/*"', ReadNames)
EachSource('-path "*/zzOLD/*"', ReadMoreNames)
-- and from ATT's other game versions (Season of Discovery NPCs and quests)
do
    local list = io.popen('find "' .. ATT .. '/.contrib/.db/standard" -name "*.lua"')
    for path in list:lines() do
        ReadNames(path)
        ReadMoreNames(path)
    end
    list:close()
end

-- ---------------------------------------------------------------------------
-- Maps WoW Forever reshaped: ATT still has the Classic percentages there.
-- Classic bounds from the Classic Era client, Forever bounds from Forever's.
--             min x, min y, max x, max y (world yards)
-- ---------------------------------------------------------------------------
local RESHAPED = {
    [1412] = { { -3697.9165, -3089.5833, -272.9167, 2047.9166 }, { -3835.416, -3675, 266.666, 2479.167 } },
    [1423] = { { 1218.75, -6056.25, 3799.9998, -2185.4165 }, { 825, -6558.334, 3691.667, -2256.25 } },
    [1433] = { { -10022.916, -3741.6665, -8575, -1570.8332 }, { -10022.916, -3852.084, -8575, -1681.25 } },
    [1453] = { { -9175.205, 36.7006, -8278.8506, 1380.9714 }, { -9154.17, -14.584, -7995.83, 1722.92 } },
}
-- The classic database's spots on those maps (area IDs, 0.1% units), to
-- tell which ATT coordinates are still Classic ones: most are already
-- Forever's (players re-measured them), some were copied over unchanged.
local AREA = { [1412] = 215, [1423] = 139, [1433] = 44, [1453] = 1519 }
local classic = { npc = {}, object = {} }
local classicQuests = {}
do
    local src = assert(io.open("WaypointTracker_Data/Data.lua")):read("*a")
    for id in (src:match("quests = %[==%[\n(.-)%]==%]") or ""):gmatch("%f[^\n%z](%d+)\t") do
        classicQuests[tonumber(id)] = true
    end
    for _, spec in ipairs({ { "npc", "units", 5 }, { "object", "objects", 3 } }) do
        local body = src:match(spec[2] .. " = %[==%[\n(.-)%]==%]")
        for line in body:gmatch("[^\n]+") do
            local f = {}
            for v in (line .. "\t"):gmatch("([^\t]*)\t") do
                f[#f + 1] = v
            end
            local id = tonumber(f[1])
            for area, nums in (f[spec[3]] or ""):gmatch("(%d+):([%d,]+)") do
                area = tonumber(area)
                for m, a in pairs(AREA) do
                    if a == area then
                        local list = {}
                        for n in nums:gmatch("%d+") do
                            list[#list + 1] = tonumber(n) / 10
                        end
                        classic[spec[1]][id] = classic[spec[1]][id] or {}
                        classic[spec[1]][id][m] = list
                    end
                end
            end
        end
    end
end

-- Is this ATT coordinate still the Classic one?
local function IsClassic(kind, id, m, x, y)
    local ref = kind and id and classic[kind] and classic[kind][id]
    if not ref then
        -- not in the classic database: only NPCs new in Forever (IDs from
        -- about 245000) were measured on Forever's maps
        return not (kind == "npc" and id and id >= 245000)
    end
    local list = ref[m] or {}
    for i = 1, #list - 1, 2 do
        if math.abs(list[i] - x) <= 1.5 and math.abs(list[i + 1] - y) <= 1.5 then
            return true
        end
    end
    return false
end

local function Fix(m, x, y, kind, id) -- x, y in 0..100
    local b = RESHAPED[m]
    if not b or not IsClassic(kind, id, m, x, y) then
        return x, y
    end
    local c, f = b[1], b[2]
    local wx = c[3] - y / 100 * (c[3] - c[1])
    local wy = c[4] - x / 100 * (c[4] - c[2])
    return (f[4] - wy) / (f[4] - f[2]) * 100, (f[3] - wx) / (f[3] - f[1]) * 100
end

-- ---------------------------------------------------------------------------
-- Walking the tree
-- ---------------------------------------------------------------------------
local npcs, objects, quests, items, mailboxes = {}, {}, {}, {}, {}
local function Entry(tbl, id)
    local e = tbl[id]
    if not e then
        e = { spots = {}, id = id, kind = (tbl == objects) and "object" or "npc" }
        tbl[id] = e
    end
    return e
end

-- ATT coords: { [mapID] = { {x, y}, ... } } or { x, y, mapID }
local function Coords(t, fallbackMap)
    local out = {}
    local c = t.coords or t.coord
    if type(c) ~= "table" then
        return out
    end
    if type(c[1]) == "number" and type(c[2]) == "number" then
        out[#out + 1] = { c[3] or fallbackMap, c[1], c[2] }
        return out
    end
    for m, pts in pairs(c) do
        if type(m) == "number" and type(pts) == "table" then
            for _, p in ipairs(pts) do
                if type(p) == "table" and type(p[1]) == "number" then
                    out[#out + 1] = { m, p[1], p[2] }
                end
            end
        elseif type(pts) == "table" and type(pts[1]) == "number" then
            out[#out + 1] = { pts[3] or fallbackMap, pts[1], pts[2] }
        end
    end
    return out
end

local function AddSpots(e, coords)
    for _, c in ipairs(coords) do
        if c[1] and c[2] and c[3] and c[2] >= 0 and c[2] <= 100 and c[3] >= 0 and c[3] <= 100 then
            local x, y = Fix(c[1], c[2], c[3], e.kind, e.id)
            local list = e.spots[c[1]] or {}
            e.spots[c[1]] = list
            local cx, cy = math.floor(x), math.floor(y)
            local dup = false
            for i = 1, #list, 2 do
                if math.floor(list[i] / 10) == cx and math.floor(list[i + 1] / 10) == cy then
                    dup = true
                end
            end
            if not dup and #list < 60 then
                list[#list + 1] = math.floor(x * 10 + 0.5)
                list[#list + 1] = math.floor(y * 10 + 0.5)
            end
        end
    end
end

local function Faction(r)
    return (r == 1 and "H") or (r == 2 and "A") or ""
end

local function Refs(t, into)
    -- providers = { { "i", id }, { "o", id }, { "n", id } }; cost = { { "i", id, count } }
    for _, key in ipairs({ "providers", "cost" }) do
        for _, p in ipairs(type(t[key]) == "table" and t[key] or {}) do
            if type(p) == "table" and type(p[2]) == "number" then
                local k = p[1] == "i" and "I" or p[1] == "o" and "O" or p[1] == "n" and "U" or nil
                if k then
                    into[#into + 1] = k .. p[2]
                end
            end
        end
    end
end

local function Children(t)
    if type(t.g) == "table" then
        return t.g
    end
    if type(t[1]) == "table" then
        return t
    end
    return {}
end

local walk
local function WalkChildren(t, ctx)
    for _, c in ipairs(Children(t)) do
        if type(c) == "table" then
            walk(c, ctx)
        end
    end
end

walk = function(t, ctx)
    local kind, id = t._kind, t._id
    local here = { map = ctx.map, npc = ctx.npc, object = ctx.object, quest = ctx.quest, aqd = ctx.aqd, hqd = ctx.hqd }
    -- quest givers shared by every quest below (Alliance and Horde side)
    if type(t.aqd) == "table" then
        here.aqd = t.aqd
    end
    if type(t.hqd) == "table" then
        here.hqd = t.hqd
    end
    if kind == "map" and type(id) == "number" then
        here.map = id
    elseif kind == "header" or kind == "category" then
        here.npc, here.object = ctx.npc, ctx.object
    end
    local coords = Coords(t, here.map)

    if kind == "npc" and type(id) == "number" and id > 0 then
        local e = Entry(npcs, id)
        AddSpots(e, coords)
        e.fac = Faction(t.r)
        here.npc, here.object = id, nil
    elseif kind == "object" and type(id) == "number" and id > 0 then
        local e = Entry(objects, id)
        AddSpots(e, coords)
        here.object, here.npc = id, nil
    elseif kind == "flight" then
        local cr = t.cr or (type(t.crs) == "table" and t.crs[1])
        if cr then
            local e = Entry(npcs, cr)
            AddSpots(e, coords)
            e.flight = true
            e.fac = Faction(t.r)
        end
    elseif kind == "quest" and type(id) == "number" then
        local q = quests[id] or { needs = {} }
        quests[id] = q
        q.fac = Faction(t.r)
        local givers = {}
        for _, g in ipairs(type(t.qgs) == "table" and t.qgs or {}) do
            givers[#givers + 1] = "U" .. g
        end
        if t.qg then
            givers[#givers + 1] = "U" .. t.qg
        end
        local refs = {}
        Refs(t, refs)
        -- qss: the item that starts the quest; qis: items the quest needs
        for _, key in ipairs({ "qss", "qis" }) do
            for _, iid in ipairs(type(t[key]) == "table" and t[key] or {}) do
                refs[#refs + 1] = "I" .. iid
            end
        end
        for _, r in ipairs(refs) do
            if r:sub(1, 1) == "I" then
                q.needs[#q.needs + 1] = r
            elseif #givers == 0 then
                givers[#givers + 1] = r -- an object or NPC that starts it
            end
        end
        if #givers == 0 and ctx.npc then
            givers[1] = "U" .. ctx.npc
        end
        -- quests handed in at one NPC per faction (e.g. the librarians)
        if #givers == 0 and (ctx.aqd or ctx.hqd) then
            for _, qd in ipairs({ { ctx.aqd, 2 }, { ctx.hqd, 1 } }) do
                local d = qd[1]
                if type(d) == "table" and (t.r == nil or t.r == qd[2]) then
                    local g = (type(d.qgs) == "table" and d.qgs[1]) or d.qg
                    if g then
                        givers[#givers + 1] = "U" .. g
                        AddSpots(Entry(npcs, g), Coords(d, here.map))
                        Entry(npcs, g).fac = Faction(qd[2])
                    end
                end
            end
            q.enders = givers
        end
        if not q.giver and #givers > 0 then
            q.giver = table.concat(givers, ",")
        end
        -- the coordinates of a quest are its giver's
        if #givers == 1 and #coords > 0 and givers[1]:find("^[UO]%d+$") then
            local k, gid = givers[1]:sub(1, 1), tonumber(givers[1]:sub(2))
            AddSpots(Entry(k == "O" and objects or npcs, gid), coords)
        elseif #coords > 0 and not q.area then
            local c = coords[1]
            local x, y = Fix(c[1], c[2], c[3])
            q.area = { c[1], x, y }
        end
        here.quest, here.npc, here.object = id, nil, nil
    elseif kind == "objective" and ctx.quest then
        local q = quests[ctx.quest]
        Refs(t, q.needs)
        for _, cr in ipairs(type(t.crs) == "table" and t.crs or {}) do
            q.needs[#q.needs + 1] = "U" .. cr
        end
        if #coords > 0 and not q.area then
            local c = coords[1]
            local x, y = Fix(c[1], c[2], c[3])
            q.area = { c[1], x, y }
        end
    elseif ((kind == "item" or kind == "itemsource") and type(id) == "number") or type(t.itemID) == "number" then
        -- mounts, pets and recipes carry the item that teaches them in itemID
        if kind ~= "item" and kind ~= "itemsource" then
            id = t.itemID
        end
        local it = items[id] or { from = {}, sold = {} }
        items[id] = it
        if ctx.npc then
            -- an item with a price under an NPC is sold by it; else it drops
            if t.cost ~= nil then
                it.sold["U" .. ctx.npc] = true
            else
                it.from["U" .. ctx.npc] = true
            end
        end
        if ctx.object then
            it.from["O" .. ctx.object] = true
        end
        for _, cr in ipairs(type(t.crs) == "table" and t.crs or {}) do
            it.from["U" .. cr] = true
        end
        for _, p in ipairs(type(t.providers) == "table" and t.providers or {}) do
            if type(p) == "table" and p[1] == "o" and type(p[2]) == "number" then
                it.from["O" .. p[2]] = true
            end
        end
    end
    WalkChildren(t, here)
end

local function WalkAll(categories)
    for _, root in pairs(categories) do
        if type(root) == "table" then
            if root._kind then
                walk(root, {})
            else
                WalkChildren(root, {})
            end
        end
    end
end
WalkAll(cats)

-- ---------------------------------------------------------------------------
-- WoW Forever kept Season of Discovery's quests. For the ones in Forever's
-- client that ATT's Forever database doesn't cover yet, take the quest giver
-- and objectives from ATT's Season of Discovery database, with the NPCs and
-- objects they need. Forever's own data always comes first.
-- ---------------------------------------------------------------------------
do
    local foreverQuests = {}
    local src = assert(io.open("WaypointTracker/ForeverQuests.lua")):read("*a")
    for id in (src:match('foreverQuests = "([%d,]+)"') or ""):gmatch("%d+") do
        foreverQuests[tonumber(id)] = true
    end
    C_Seasons = { GetActiveSeason = function() return 2 end }
    GetCVar = function() return "" end
    local sod = require("att_load").Load(ATT .. "/db/VanillaSOD")
    local main = { npcs = npcs, objects = objects, quests = quests, items = items, mailboxes = mailboxes }
    npcs, objects, quests, items, mailboxes = {}, {}, {}, {}, {}
    WalkAll(sod)
    local sodNpcs, sodObjects, sodQuests = npcs, objects, quests
    npcs, objects, quests, items, mailboxes = main.npcs, main.objects, main.quests, main.items, main.mailboxes
    local added = 0
    for id, q in pairs(sodQuests) do
        if foreverQuests[id] and not quests[id] and not classicQuests[id] then
            q.sod = true
            quests[id] = q
            added = added + 1
            local refs = (q.giver or "") .. "," .. table.concat(q.enders or {}, ",") .. "," .. table.concat(q.needs or {}, ",")
            for kind, rid in refs:gmatch("([UO])(%d+)") do
                rid = tonumber(rid)
                local from, into = sodNpcs, npcs
                if kind == "O" then
                    from, into = sodObjects, objects
                end
                if from[rid] and not into[rid] and not classic[kind == "O" and "object" or "npc"][rid] then
                    into[rid] = from[rid]
                end
            end
        end
    end
    io.stderr:write(("Season of Discovery: %d Forever quests added\n"):format(added))
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------
local function SpotsText(spots)
    local parts, maps = {}, {}
    for m in pairs(spots) do
        maps[#maps + 1] = m
    end
    table.sort(maps)
    for _, m in ipairs(maps) do
        if #spots[m] > 0 then
            parts[#parts + 1] = m .. ":" .. table.concat(spots[m], ",")
        end
    end
    return table.concat(parts, ";")
end
local function Sorted(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end
-- one line of text for the shared format (the long string it goes in picks
-- a bracket level the text can't close)
local function Tidy(s)
    return ((s or ""):gsub("[%c]", " "))
end

local lines = { "WTL1\tatt\t1" }
local counts = { N = 0, O = 0, Q = 0, I = 0 }
for _, id in ipairs(Sorted(npcs)) do
    local e = npcs[id]
    local spots = SpotsText(e.spots)
    if spots ~= "" or e.flight then
        lines[#lines + 1] = table.concat({ "N", id, Tidy(npcNames[id]), "", "", e.flight and "flight" or "", spots, e.fac or "" }, "\t")
        counts.N = counts.N + 1
    end
end
for _, id in ipairs(Sorted(objects)) do
    local spots = SpotsText(objects[id].spots)
    if spots ~= "" then
        lines[#lines + 1] = table.concat({ "O", id, Tidy(objectNames[id]), spots }, "\t")
        counts.O = counts.O + 1
    end
end
for _, id in ipairs(Sorted(quests)) do
    local q = quests[id]
    local area = q.area and ("%d:%d,%d"):format(q.area[1], math.floor(q.area[2] * 10 + 0.5), math.floor(q.area[3] * 10 + 0.5)) or ""
    local seen, needs = {}, {}
    for _, r in ipairs(q.needs) do
        if not seen[r] then
            seen[r] = true
            needs[#needs + 1] = r
        end
    end
    if q.giver or area ~= "" or #needs > 0 then
        -- turned in where it was given when both sides use the same NPCs
        local ender = q.enders and table.concat(q.enders, ",") or ""
        -- an English title for quests the classic database doesn't name; the
        -- game's own title (in the player's language) replaces it in game
        -- (not for Season of Discovery quests: those show up once the game
        -- confirms WoW Forever has them by giving their name)
        local title = not classicQuests[id] and not q.sod and Tidy(questNames[id]) or ""
        lines[#lines + 1] = table.concat({ "Q", id, title, "", q.giver or "", ender, area, "", "", table.concat(needs, ","), q.fac or "" }, "\t")
        counts.Q = counts.Q + 1
    end
end
for _, id in ipairs(Sorted(items)) do
    local from, sold = Sorted(items[id].from), Sorted(items[id].sold)
    if #from + #sold > 0 then
        lines[#lines + 1] = table.concat({ "I", id, "", table.concat(from, ","), table.concat(sold, ",") }, "\t")
        counts.I = counts.I + 1
    end
end

local f = assert(io.open(OUT, "w"))
f:write("-- Generated by tools/build_att.lua. Bundled third-party data: see\n")
f:write("-- THIRD-PARTY-LICENSES.txt. Same format as shared discoveries. Do not edit.\n")
f:write("WaypointTrackerData = WaypointTrackerData or {}\n")
-- a Lua long string with a bracket level the text can't close
local body, level = table.concat(lines, "\n"), 2
while body:find("]" .. ("="):rep(level) .. "]", 1, true) do
    level = level + 1
end
local eq = ("="):rep(level)
f:write("WaypointTrackerData.curated = [", eq, "[\n", body, "\n]", eq, "]\n")
f:close()
print(("%s: %d NPCs, %d objects, %d quests, %d items"):format(OUT, counts.N, counts.O, counts.Q, counts.I))
