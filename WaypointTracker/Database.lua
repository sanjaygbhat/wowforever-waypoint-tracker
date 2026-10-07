-- Database: NPCs, objects, quests and quest items with their spawn points,
-- for the Find window. The data lives in a separate load-on-demand addon
-- (WaypointTracker_Data), so it costs
-- nothing until you open Find the first time.
local _, ns = ...
local L, Geo = ns.L, ns.Geo

local DB = {}
ns.DB = DB

local DATA_ADDON = "WaypointTracker_Data"
local ALLIANCE_RACES = 1 + 4 + 8 + 64 -- human, dwarf, night elf, gnome
local HORDE_RACES = 2 + 16 + 32 + 128 -- orc, undead, tauren, troll

local band = (bit and bit.band) or function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            r = r + p
        end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end

DB.units, DB.objects, DB.quests, DB.items, DB.services = {}, {}, {}, {}, {}
DB.places, DB.marks = {}, {}
DB.generation = 0 -- goes up with every merge, so lists worked out before it are redone
DB.loaded = false

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------
local function Split(line)
    local out, pos = {}, 1
    while true do
        local tab = line:find("\t", pos, true)
        if not tab then
            out[#out + 1] = line:sub(pos)
            return out
        end
        out[#out + 1] = line:sub(pos, tab - 1)
        pos = tab + 1
    end
end

local function Lines(s)
    return (s or ""):gmatch("[^\n]+")
end

local function NumList(s)
    local out = {}
    for n in (s or ""):gmatch("%-?%d+") do
        out[#out + 1] = tonumber(n)
    end
    return out
end
DB.NumList = NumList

local function NameTable(block)
    local t = {}
    for line in Lines(block) do
        local f = Split(line)
        local id = tonumber(f[1])
        if id then
            t[id] = f
        end
    end
    return t
end

local function Parse(data)
    local loc = GetLocale()
    if loc == "esMX" then
        loc = "esES"
    end
    local en = data.names_enUS or {}
    local here = data["names_" .. loc] or {}
    local function names(kind)
        local base, over = NameTable(en[kind]), NameTable(here[kind])
        for id, f in pairs(over) do
            base[id] = f
        end
        return base
    end
    local unitNames, objectNames, questNames, itemNames, zoneNames = names("units"), names("objects"), names("quests"), names("items"), names("zones")
    -- the world's treasure chests, known by their English names in every language
    local enObjects = NameTable(en.objects)
    local function IsChest(id)
        local f = enObjects[id]
        return f and ns.Treasure and ns.Treasure.IsChestName(f[2]) or false
    end

    DB.zoneNames = {}
    for id, f in pairs(zoneNames) do
        DB.zoneNames[id] = f[2]
    end

    local function entry(kind, id, name)
        -- .words is filled in later, only when a search needs it
        return { kind = kind, id = id, name = name, key = Geo.Squash(name) }
    end

    local raw = data.raw or {}
    for line in Lines(raw.units) do
        local f = Split(line)
        local id = tonumber(f[1])
        local n = id and unitNames[id]
        if n and n[2] and n[2] ~= "" then
            local e = entry("npc", id, n[2])
            e.level, e.fac, e.rank, e.coords = f[2], f[3], f[4], f[5]
            DB.units[id] = e
        end
    end
    for line in Lines(raw.objects) do
        local f = Split(line)
        local id = tonumber(f[1])
        local n = id and objectNames[id]
        if n and n[2] and n[2] ~= "" then
            local e = entry("object", id, n[2])
            e.fac, e.coords = f[2], f[3]
            e.chest = IsChest(id) or nil
            DB.objects[id] = e
        end
    end
    for line in Lines(raw.quests) do
        local f = Split(line)
        local id = tonumber(f[1])
        local n = id and questNames[id]
        if n and n[2] and n[2] ~= "" then
            local e = entry("quest", id, n[2])
            e.text = n[3]
            e.level, e.min = tonumber(f[2]), tonumber(f[3])
            e.race, e.class = tonumber(f[4]), tonumber(f[5])
            e.startU, e.startO = NumList(f[6]), NumList(f[7])
            e.endU, e.endO = NumList(f[8]), NumList(f[9])
            e.objU, e.objO, e.objI = NumList(f[10]), NumList(f[11]), NumList(f[12])
            DB.quests[id] = e
        end
    end
    for line in Lines(raw.items) do
        local f = Split(line)
        local id = tonumber(f[1])
        local n = id and itemNames[id]
        if n and n[2] and n[2] ~= "" then
            local e = entry("item", id, n[2])
            e.dropU, e.dropO, e.soldBy = NumList(f[2]), NumList(f[3]), NumList(f[4])
            DB.items[id] = e
        end
    end
    for line in Lines(raw.services) do
        local f = Split(line)
        local list = {}
        for id, fac in (f[2] or ""):gmatch("(%-?%d+):(%a*)") do
            id = tonumber(id)
            list[#list + 1] = { id = id, fac = fac }
            -- remembered on the entry too, so sharing can skip what's known
            local e = id < 0 and DB.objects[-id] or DB.units[id]
            if e then
                e.svc = e.svc or {}
                e.svc[f[1]] = true
            end
        end
        DB.services[f[1]] = list
    end
end

-- Returns true when the database is ready, or false plus a reason
-- ("missing" when the data addon isn't installed).
function DB.Load()
    if DB.loaded then
        DB.MergeIfLearned()
        return true
    end
    if not WaypointTrackerData then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then
            pcall(load, DATA_ADDON)
        end
    end
    local shipped = WaypointTrackerData and WaypointTrackerData.raw
    if not shipped and DB.ready then
        -- still no database folder: keep searching your own discoveries
        DB.MergeIfLearned()
        return true, "missing"
    end
    if shipped then
        if not ns.Call(Parse, WaypointTrackerData) then
            return false, "broken"
        end
        -- the raw text isn't needed any more
        WaypointTrackerData.raw = nil
        for k in pairs(WaypointTrackerData) do
            if k:find("^names_") then
                WaypointTrackerData[k] = nil
            end
        end
    end
    if WaypointTrackerData and WaypointTrackerData.clientItems then
        ns.Call(DB.ParseClientItems, WaypointTrackerData)
        WaypointTrackerData.clientItems, WaypointTrackerData.clientItemNames = nil, nil
    end
    if WaypointTrackerData and type(WaypointTrackerData.client) == "table" then
        ns.Call(DB.ParseClient, WaypointTrackerData.client)
        WaypointTrackerData.client = nil
    end
    DB.hasShipped = shipped and true or false
    DB.ready = true
    -- without the database folder, try loading it again next time
    DB.loaded = DB.hasShipped
    -- Forever content: what the community shared (shipped with the data
    -- addon) and what you discovered yourself
    -- the curated WoW Forever database (same format as discoveries)
    if WaypointTrackerData and type(WaypointTrackerData.curated) == "string" and ns.Learn then
        local curated = { npcs = {}, objects = {}, quests = {}, mailboxes = {} }
        ns.Learn.Import(WaypointTrackerData.curated, curated, true)
        DB.curated = curated
        WaypointTrackerData.curated = nil
    end
    if WaypointTrackerData and type(WaypointTrackerData.forever) == "string" and ns.Learn then
        local community = { npcs = {}, objects = {}, quests = {}, mailboxes = {} }
        ns.Learn.Import(WaypointTrackerData.forever, community, true)
        DB.community = community
        WaypointTrackerData.forever = nil
    end
    -- learned data lives in SavedVariables: if it's damaged, Find still works
    ns.Call(DB.MergeLearned)
    if not shipped then
        return true, "missing"
    end
    return true
end

-- ---------------------------------------------------------------------------
-- The WoW Forever game client's own tables (Client.lua): flight paths,
-- towns and quest map markers. Positions are world positions; the game
-- turns them into map positions.
-- ---------------------------------------------------------------------------
local function Lines(text, fn)
    for line in (text or ""):gmatch("[^\n]+") do
        fn(Split(line))
    end
end

local function NameTable(text)
    local out = {}
    Lines(text, function(f)
        if f[2] and f[2] ~= "" then
            out[tonumber(f[1])] = f[2]
        end
    end)
    return out
end

function DB.ParseClient(c)
    local names, fallback = c.names or {}, c.fallbackNames or {}
    local function Named(kind)
        local mine, en = NameTable(names[kind]), NameTable(fallback[kind])
        return function(id)
            return mine[id] or en[id]
        end
    end
    local flightName, townName = Named("flights"), Named("towns")
    local function Place(id, f, name, sub)
        local e = {
            kind = "place", id = id, name = name, key = Geo.Squash(name), sub = sub,
            fac = f[6] or "", learned = "game",
            world = { { tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]) } },
        }
        DB.places[id] = e
        return e
    end
    Lines(c.flights, function(f)
        local id = tonumber(f[1])
        local name = id and flightName(id)
        if name then
            local e = Place(-100000 - id, f, name, L.SERVICE_FLIGHT)
            DB.services.flight = DB.services.flight or {}
            table.insert(DB.services.flight, { entry = e, fac = e.fac })
        end
    end)
    Lines(c.towns, function(f)
        local id = tonumber(f[1])
        local name = id and townName(id)
        if name then
            Place(-200000 - id, f, name)
        end
    end)
    -- quest markers: start, objectives and hand-in of Forever quests
    Lines(c.pois, function(f)
        local q = tonumber(f[1])
        if not q then
            return
        end
        local step = f[2] == "start" and "start" or f[2] == "end" and "end" or "objective"
        local marks = DB.marks[q] or {}
        DB.marks[q] = marks
        marks[step] = marks[step] or {}
        table.insert(marks[step], { tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]) })
    end)
    DB.foreverQuests = c.quests
end

-- Items from the game client: every item the classic database lacks (with
-- its name in your language), plus quality, level, type, description and
-- the quest it starts for the ones it has.
function DB.ParseClientItems(data)
    local loc = GetLocale and GetLocale() or "enUS"
    local texts = {}
    local names = data.clientItemNames or {}
    for _, l in ipairs(loc == "enUS" and { "enUS" } or { "enUS", loc }) do
        Lines(names[l], function(f)
            local id = tonumber(f[1])
            if id then
                local t = texts[id] or {}
                texts[id] = t
                if f[2] and f[2] ~= "" then
                    t.name = f[2]
                end
                if f[3] and f[3] ~= "" then
                    t.desc = f[3]
                end
            end
        end)
    end
    Lines(data.clientItems, function(f)
        local id = tonumber(f[1])
        if not id then
            return
        end
        local t = texts[id] or {}
        local e = DB.items[id]
        if not e and t.name then
            e = { kind = "item", id = id, name = t.name, key = Geo.Squash(t.name), dropU = {}, dropO = {}, soldBy = {}, learned = "game" }
            DB.items[id] = e
        end
        if e then
            e.class, e.subclass, e.quality = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
            e.ilvl, e.reqlevel, e.startsQuest = tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
            e.desc = t.desc
        end
    end)
end

-- Quests that need this item.
function DB.QuestsNeeding(item)
    local out = {}
    for _, q in pairs(DB.quests) do
        for _, id in ipairs(q.objI or {}) do
            if id == item.id then
                out[#out + 1] = q
                break
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Discoveries (Learn.lua) and community Forever data
-- ---------------------------------------------------------------------------
local nextSpotID = -1
-- curated: spots from the curated database, which replace the classic ones
local function Spots(store, out, curated)
    if type(store) ~= "table" then
        return
    end
    for m, list in pairs(store) do
        if type(list) == "table" then
            for i = 1, #list - 1, 2 do
                local x, y = ns.Num(list[i]), ns.Num(list[i + 1])
                if x and y then
                    out[#out + 1] = { m = tonumber(m), x = x, y = y, curated = curated }
                end
            end
        end
    end
end

local function MyLetter()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Horde" and "H") or (f == "Alliance" and "A") or ""
end

local function AddUnique(list, value)
    for _, have in ipairs(list) do
        if have == value then
            return
        end
    end
    list[#list + 1] = value
end

local function Richness(e)
    return #(e.coords or "") + #(e.extra or {}) * 8
end

-- name -> entry, for matching the names the game shows to the database
local function NameIndex()
    local index = {}
    for _, tbl in ipairs({ "items", "units", "objects" }) do
        local t = {}
        for id, e in pairs(DB[tbl]) do
            -- when names repeat, prefer the one with more known spots
            if id > 0 and e.key and (not t[e.key] or (tbl ~= "items" and Richness(e) > Richness(t[e.key]))) then
                t[e.key] = e
            end
        end
        index[tbl] = t
    end
    return index
end

-- What the database knows about an entry before your own discoveries are
-- added to it (taken the first time they are, or when first asked), so
-- only what's new is kept and shared.
function DB.Snapshot(e, created)
    if e.kind == "item" then
        local ship = { drop = {}, sold = {} }
        for _, rid in ipairs(e.dropU or {}) do
            ship.drop["U" .. rid] = true
        end
        for _, rid in ipairs(e.dropO or {}) do
            ship.drop["O" .. rid] = true
        end
        for _, rid in ipairs(e.soldBy or {}) do
            ship.sold["U" .. rid] = true
        end
        return ship
    end
    return { fresh = created, name = e.name, title = e.title, spots = #(e.extra or {}), enemy = DB.IsEnemy(e) }
end

local function MergeStore(st, source)
    if type(st) ~= "table" then
        return
    end
    local letter = MyLetter()
    local mine = source == "you"
    -- what you imported is labelled as other players' discoveries
    local function Label(l)
        return (mine and type(l) == "table" and l.shared) and "community" or source
    end
    local function T(v)
        return type(v) == "table" and v or {}
    end
    -- what the database knew before your own discoveries were added, so
    -- sharing can leave out what it already has (kept from the first merge)
    local function Remember(e, created)
        if mine and not e.ship then
            e.ship = DB.Snapshot(e, created)
        end
    end
    local function Services(e, l)
        for service in pairs(T(l.services)) do
            if type(service) == "string" then
                if not mine then
                    e.svc = e.svc or {}
                    e.svc[service] = true
                end
                if e.kind == "npc" then
                    DB.services[service] = DB.services[service] or {}
                    table.insert(DB.services[service], { id = e.id, fac = l.hostile and "" or (l.fac or letter) })
                end
            end
        end
    end
    for id, l in pairs(T(st.npcs)) do
        local e = DB.units[id]
        local created = not e
        if not e and type(l) == "table" and (l.name or next(T(l.spots))) then
            -- without a name it can't be searched for, but still leads the
            -- way as a quest giver or hand-in
            e = { kind = "npc", id = id, name = l.name or "", key = l.name and Geo.Squash(l.name) or "", fac = "", learned = Label(l) }
            DB.units[id] = e
        end
        if e then
            Remember(e, created)
            -- what the game showed you (not what you imported) wins
            local own = mine and not l.shared
            if type(l.name) == "string" and (own or e.name == "") then
                -- the name the game showed you, in your language
                e.name, e.key, e.words = l.name, Geo.Squash(l.name), nil
            end
            if type(l.title) == "string" and (own or not e.title) then
                e.title, e.tkey = l.title, Geo.Squash(l.title)
            end
            if l.hostile ~= nil then
                e.hostile = l.hostile and true or false
            end
            if l.level and (not e.level or e.level == "") then
                e.level = tostring(l.level)
            end
            if l.fac and (e.fac or "") == "" then
                e.fac = l.fac
            end
            e.extra = e.extra or {}
            Spots(l.spots, e.extra, source == "curated")
            e.points = nil
            Services(e, l)
        end
    end
    for id, l in pairs(T(st.objects)) do
        local e = DB.objects[id]
        local created = not e
        if not e and type(l) == "table" and (l.name or next(T(l.spots))) then
            -- without a name it can't be searched for, but still leads the
            -- way as a quest giver or hand-in
            e = { kind = "object", id = id, name = l.name or "", key = l.name and Geo.Squash(l.name) or "", fac = "", learned = Label(l) }
            DB.objects[id] = e
        end
        if e then
            Remember(e, created)
            if type(l.name) == "string" and ((mine and not l.shared) or e.name == "") then
                e.name, e.key, e.words = l.name, Geo.Squash(l.name), nil
            end
            -- the curated database's names are English
            if source == "curated" and ns.Treasure and ns.Treasure.IsChestName(l.name) then
                e.chest = true
            end
            e.extra = e.extra or {}
            Spots(l.spots, e.extra, source == "curated")
            e.points = nil
            Services(e, l)
        end
    end
    for id, l in pairs(st.quests or {}) do
        local q = DB.quests[id]
        if not q and l.title then
            q = { kind = "quest", id = id, name = l.title, key = Geo.Squash(l.title), startU = {}, startO = {}, endU = {}, endO = {}, objU = {}, objO = {}, objI = {} }
            DB.quests[id] = q
        end
        if q then
            q.learned = q.learned or Label(l)
            local imported = mine and l.shared
            local own = mine and not imported
            if own and type(l.title) == "string" then
                q.name, q.key, q.words = l.title, Geo.Squash(l.title), nil
            end
            if type(l.text) == "string" and l.text ~= "" and (own or not q.text or q.text == "") then
                q.text = l.text
            end
            q.level = tonumber(l.level) or q.level
            -- who gives and takes the quest in the game replaces the shipped
            -- guess (a later merge of your own discoveries wins)
            -- one ref or several ("U1,U2": a different NPC per faction)
            local function link(ref, field)
                local us, os = {}, {}
                for kind, rid in (ref or ""):gmatch("([UO])(%d+)") do
                    table.insert(kind == "U" and us or os, tonumber(rid))
                end
                -- an import only fills a step the database has nobody for
                local empty = #(q[field .. "U"] or {}) + #(q[field .. "O"] or {}) == 0
                if #us + #os > 0 and (not imported or empty) then
                    q[field .. "U"], q[field .. "O"] = us, os
                end
            end
            link(l.giver, "start")
            link(l.ender, "end")
            if l.area then
                q.area = { m = l.area[1], x = l.area[2], y = l.area[3] }
            end
            for kind, rid in table.concat(l.needs or {}, ","):gmatch("([IUO])(%d+)") do
                AddUnique(kind == "I" and q.objI or kind == "U" and q.objU or q.objO, tonumber(rid))
            end
            if l.fac and not q.race then
                q.fac = l.fac
            end
        end
    end
    for id, l in pairs(T(st.items)) do
        local e = DB.items[id]
        if not e and type(l) == "table" and l.name then
            e = { kind = "item", id = id, name = l.name, key = Geo.Squash(l.name), dropU = {}, dropO = {}, soldBy = {} }
            DB.items[id] = e
        end
        if e then
            if not e.learned or e.learned == "game" then
                e.learned = Label(l)
            end
            if mine and not e.ship then
                e.ship = DB.Snapshot(e)
            end
            for ref in pairs(T(l.from)) do
                local kind, rid = tostring(ref):match("^([UO])(%d+)$")
                rid = tonumber(rid)
                if rid then
                    AddUnique(kind == "U" and e.dropU or e.dropO, rid)
                end
            end
            for ref in pairs(T(l.sold)) do
                local rid = tonumber(tostring(ref):match("^U(%d+)$"))
                if rid then
                    AddUnique(e.soldBy, rid)
                end
            end
        end
    end
    -- quest objectives the game listed, by name: link them to what they are
    local byName
    for id, l in pairs(st.quests or {}) do
        local q = DB.quests[id]
        if q and l.objs then
            byName = byName or NameIndex()
            for _, obj in ipairs(l.objs) do
                local kind, name = obj:match("^(%a+):(.+)$")
                local key = name and Geo.Squash(name)
                if kind == "item" and byName.items[key] then
                    AddUnique(q.objI, byName.items[key].id)
                elseif kind == "monster" and byName.units[key] then
                    AddUnique(q.objU, byName.units[key].id)
                elseif kind == "object" and byName.objects[key] then
                    AddUnique(q.objO, byName.objects[key].id)
                end
            end
        end
    end
    -- corrections: the wrong spot goes, the right one comes
    for key, list in pairs(T(st.fixes)) do
        local kind, id = tostring(key):match("^([NO])(%d+)$")
        local e = kind and (kind == "N" and DB.units or DB.objects)[tonumber(id)]
        if e then
            for _, fix in ipairs(T(list)) do
                e.fixes = e.fixes or {}
                table.insert(e.fixes, { wrong = fix.wrong, mine = mine and not fix.shared })
                local r = fix.right
                if r then
                    e.extra = e.extra or {}
                    table.insert(e.extra, { m = r[1], x = r[2], y = r[3], fixed = true })
                end
            end
            e.points = nil
        end
    end
    -- mailboxes: one "object" per spot
    local mail = {}
    Spots(st.mailboxes and st.mailboxes.spots, mail)
    for _, p in ipairs(mail) do
        local e = { kind = "object", id = nextSpotID, name = L.SERVICE_MAILBOX, key = Geo.Squash(L.SERVICE_MAILBOX), fac = "", points = { p }, learned = source }
        DB.objects[nextSpotID] = e
        DB.services.mailbox = DB.services.mailbox or {}
        table.insert(DB.services.mailbox, { entry = e, fac = "" })
        nextSpotID = nextSpotID - 1
    end
end

-- (Re)adds discoveries. Safe to call again after learning more.
function DB.MergeLearned()
    if not DB.ready then
        return
    end
    -- drop what a previous merge added, then add everything again
    for _, tbl in ipairs({ DB.units, DB.objects }) do
        for id, e in pairs(tbl) do
            if e.extra or e.fixes then
                e.extra, e.fixes, e.points = nil, nil, nil
            end
            if id < 0 then
                tbl[id] = nil
            end
        end
    end
    for _, list in pairs(DB.services) do
        for i = #list, 1, -1 do
            if list[i].learned then
                table.remove(list, i)
            end
        end
    end
    local before = {}
    for service, list in pairs(DB.services) do
        before[service] = #list
    end
    -- WoW Forever's new quests, with the names the game gave us
    local titles = ns.Learn and ns.Learn.QuestTitles and ns.Learn.QuestTitles()
    for id, title in pairs(titles or {}) do
        local q = DB.quests[id]
        if not q then
            q = { kind = "quest", id = id, startU = {}, startO = {}, endU = {}, endO = {}, objU = {}, objO = {}, objI = {}, learned = "game" }
            DB.quests[id] = q
        end
        if q.learned == "game" and q.name ~= title then
            q.name, q.key, q.words = title, Geo.Squash(title), nil
        end
    end
    MergeStore(DB.curated, "curated")
    MergeStore(DB.community, "community")
    MergeStore(ns.Learn and ns.Learn.Store(), "you")
    -- keep only what adds to the database in your saved discoveries
    if ns.Learn and ns.Learn.Compact then
        ns.Learn.Compact(true)
    end
    -- mark what was added so the next merge can take it out again
    for service, list in pairs(DB.services) do
        for i = (before[service] or 0) + 1, #list do
            list[i].learned = true
        end
    end    DB.generation = DB.generation + 1
end

-- Merging is a big job (tens of milliseconds), and learning happens all the
-- time while you play, so it waits until Find is used again.
local learnedSinceMerge = false
ns.On("LEARNED", function()
    learnedSinceMerge = true
end)

function DB.MergeIfLearned()
    if learnedSinceMerge and DB.ready then
        learnedSinceMerge = false
        ns.Call(DB.MergeLearned)
    end
end

-- ---------------------------------------------------------------------------
-- Zones: the database uses the game's area IDs; turn them into map IDs by
-- name (both in the client's language), so they match WoW Forever's maps.
-- ---------------------------------------------------------------------------
local areaMap = {}
function DB.MapForArea(area)
    local cached = areaMap[area]
    if cached ~= nil then
        return cached or nil
    end
    local names = {}
    if C_Map.GetAreaInfo then
        local ok, n = pcall(C_Map.GetAreaInfo, area)
        if ok and type(n) == "string" and n ~= "" then
            names[#names + 1] = n
        end
    end
    if DB.zoneNames and DB.zoneNames[area] then
        names[#names + 1] = DB.zoneNames[area]
    end
    local found = false
    local zones = Geo.GetZoneList()
    for _, name in ipairs(names) do
        local key = Geo.Squash(name)
        local best
        for _, z in ipairs(zones) do
            if z.key == key and (not best or (z.mapType == 3 and best.mapType ~= 3)) then
                best = z
            end
        end
        if best then
            found = best.id
            break
        end
    end
    areaMap[area] = found
    return found or nil
end

-- Spawn points of an NPC/object as { m, x, y } (x/y 0..1), cached.
-- WoW Forever reshaped a few maps (Stormwind got its harbour, and Mulgore,
-- Redridge and the Eastern Plaguelands moved). The classic database's
-- percentages are for the old shapes: turn them into world positions with
-- the old map bounds (from the Classic Era client) and let the game place
-- them on today's map.
--            continent, min x, min y, max x, max y (world yards)
local CLASSIC_BOUNDS = {
    [1412] = { 1, -3697.9165, -3089.5833, -272.9167, 2047.9166 }, -- Mulgore
    [1423] = { 0, 1218.75, -6056.25, 3799.9998, -2185.4165 }, -- Eastern Plaguelands
    [1433] = { 0, -10022.916, -3741.6665, -8575, -1570.8332 }, -- Redridge Mountains
    [1453] = { 0, -9175.205, 36.7006, -8278.8506, 1380.9714 }, -- Stormwind City
}
DB.CLASSIC_BOUNDS = CLASSIC_BOUNDS

function DB.FromClassicMap(m, x, y)
    local b = CLASSIC_BOUNDS[m]
    if not b then
        return x, y
    end
    local wx = b[4] - y * (b[4] - b[2])
    local wy = b[5] - x * (b[5] - b[3])
    local nx, ny = Geo.WorldToMap(b[1], wx, wy, m)
    if nx and ny then
        return nx, ny
    end
    return x, y
end

-- The classic database's spots of an entry, per map: { [m] = { p, ... } }.
local function ClassicPoints(e)
    local out = {}
    for area, list in (e.coords or ""):gmatch("(%d+):([%d,]+)") do
        local m = DB.MapForArea(tonumber(area))
        if m then
            local nums = NumList(list)
            local on = out[m] or {}
            out[m] = on
            for i = 1, #nums - 1, 2 do
                local x, y = DB.FromClassicMap(m, nums[i] / 1000, nums[i + 1] / 1000)
                on[#on + 1] = { m = m, x = x, y = y }
            end
        end
    end
    return out
end

-- Spots seen in the game or given by the curated WoW Forever database come
-- first. On a map the curated database covers, the classic spots are
-- replaced. On a map where only players saw it, the classic spots are
-- replaced when there are just one or two (an NPC that stands in one place
-- and may have moved), and kept when there are more (enemies with many
-- spawns: one sighting doesn't mean the others are gone).
local MOVED_NPC_SPOTS = 2
local NEAR_KNOWN = 0.02 -- 2% of the map: the same place
function DB.Points(e)
    if not e then
        return {}
    end
    if e.points then
        return e.points
    end
    local pts, curated, seen = {}, {}, {}
    for _, w in ipairs(e.world or {}) do
        local x, y = Geo.WorldToMap(w[1], w[3], w[4], w[2] ~= 0 and w[2] or nil)
        local m = w[2] ~= 0 and w[2] or select(3, Geo.WorldToMap(w[1], w[3], w[4]))
        if x and y and m and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            pts[#pts + 1] = { m = m, x = x, y = y }
        end
    end
    for _, p in ipairs(e.extra or {}) do
        pts[#pts + 1] = p
        if p.curated then
            curated[p.m] = true
        else
            seen[p.m] = true
        end
    end
    for m, list in pairs(ClassicPoints(e)) do
        if not curated[m] and not (seen[m] and #list <= MOVED_NPC_SPOTS) then
            for _, p in ipairs(list) do
                pts[#pts + 1] = p
            end
        end
    end
    -- a spot someone said is wrong is left out (the right one is kept)
    if e.fixes then
        local kept = {}
        for _, p in ipairs(pts) do
            local wrong = false
            for _, fix in ipairs(e.fixes) do
                local w = fix.wrong
                if not p.fixed and w and w[1] == p.m and math.abs(w[2] - p.x) <= NEAR_KNOWN and math.abs(w[3] - p.y) <= NEAR_KNOWN then
                    wrong = true
                    break
                end
            end
            if not wrong then
                kept[#kept + 1] = p
            end
        end
        pts = kept
    end
    e.points = pts
    return pts
end

-- Does something you discovered add to what the database knows? Sharing
-- leaves out what it already has. kind "npc"/"object" (value: your entry),
-- "drop"/"sold" (id: the item, value: "U123"/"O45").
function DB.AddsSomething(kind, id, value)
    if kind == "drop" or kind == "sold" then
        local e = DB.items[id]
        if not e then
            return true
        end
        -- (without a snapshot, your discoveries haven't touched it yet: what
        -- it has now is what the database has)
        e.ship = e.ship or DB.Snapshot(e)
        return not e.ship[kind][value]
    end
    local e = (kind == "npc" and DB.units or DB.objects)[id]
    if not e or type(value) ~= "table" then
        return true
    end
    e.ship = e.ship or DB.Snapshot(e, false)
    local ship = e.ship
    if ship.fresh then
        return true
    end
    if (value.name and ship.name == "") or (value.title and not ship.title) then
        return true
    end
    -- friend or foe the other way round
    if kind == "npc" and value.hostile ~= nil and ship.enemy ~= nil and value.hostile ~= ship.enemy then
        return true
    end
    for service in pairs(type(value.services) == "table" and value.services or {}) do
        if not (e.svc and e.svc[service]) then
            return true
        end
    end
    local spots = type(value.spots) == "table" and value.spots or {}
    if not next(spots) then
        return false
    end
    local known = ClassicPoints(e)
    for i = 1, ship.spots do
        local p = e.extra and e.extra[i]
        if p then
            known[p.m] = known[p.m] or {}
            table.insert(known[p.m], p)
        end
    end
    for m, list in pairs(spots) do
        local here = known[tonumber(m)] or {}
        for i = 1, #list - 1, 2 do
            local x, y = ns.Num(list[i]), ns.Num(list[i + 1])
            local found = false
            for _, p in ipairs(here) do
                if x and y and math.abs(p.x - x) <= NEAR_KNOWN and math.abs(p.y - y) <= NEAR_KNOWN then
                    found = true
                    break
                end
            end
            if not found then
                return true
            end
        end
    end
    return false
end

-- Names of the zones something can be found in.
function DB.ZonesOf(e)
    local seen, out = {}, {}
    for _, p in ipairs(DB.Points(e)) do
        if not seen[p.m] then
            seen[p.m] = true
            out[#out + 1] = Geo.GetMapName(p.m)
        end
    end
    return out
end

-- Closest spawn point to you (on your continent), plus its distance.
-- Falls back to the first known point when none is on your continent.
function DB.Nearest(points)
    local best, bestDist
    for _, p in ipairs(points) do
        local dist = Geo.GetVector(p)
        if dist and (not bestDist or dist < bestDist) then
            best, bestDist = p, dist
        end
    end
    return best or points[1], bestDist
end

-- ---------------------------------------------------------------------------
-- Faction
-- ---------------------------------------------------------------------------
local function MyFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Horde" then
        return "H", HORDE_RACES
    elseif f == "Alliance" then
        return "A", ALLIANCE_RACES
    end
end

-- False for NPCs/objects only friendly to the other faction, and quests
-- only the other faction can do.
function DB.ForMyFaction(e)
    local letter, races = MyFaction()
    if not letter then
        return true
    end
    if e.kind == "quest" then
        if e.fac then
            return e.fac:find(letter, 1, true) ~= nil
        end
        return not e.race or e.race == 0 or band(e.race, races) ~= 0
    end
    local fac = e.fac or ""
    if fac == "" or e.hostile then
        return true -- monsters and neutral things
    end
    return fac:find(letter, 1, true) ~= nil
end

-- Enemies: monsters, plus anything you've seen be hostile.
function DB.IsEnemy(e)
    if e.kind ~= "npc" then
        return false
    end
    if e.hostile ~= nil then
        return e.hostile
    end
    return (e.fac or "") == ""
end

-- ---------------------------------------------------------------------------
-- Searching
-- ---------------------------------------------------------------------------
local KIND_TABLE = { npc = "units", enemy = "units", object = "objects", quest = "quests", item = "items", place = "places" }

-- kinds: set like { npc = true, quest = true }; opts: faction (bool),
-- zone (map ID to stay in). Returns entries best first.
function DB.Search(text, kinds, opts, limit)
    opts = opts or {}
    limit = limit or 300
    local q, qWords = Geo.PrepareQuery(text)
    if q == "" then
        return {}
    end
    local scored = {}
    local first = q:sub(1, 1)

    -- fast: exact, starts with, every word starts a word, contains
    local function quick(e)
        local key = e.key
        if key == q then
            return 0
        end
        if key:sub(1, #q) == q then
            return 1
        end
        local contains = key:find(q, 1, true)
        if #qWords > 1 then
            -- all typed letters must be in the name for any word match
            local possible = true
            for _, w in ipairs(qWords) do
                if not key:find(w, 1, true) then
                    possible = false
                    break
                end
            end
            if possible then
                e.words = e.words or Geo.Words(e.name)
                local all = true
                for _, qw in ipairs(qWords) do
                    local found = false
                    for _, w in ipairs(e.words) do
                        if w:sub(1, #qw) == qw then
                            found = true
                            break
                        end
                    end
                    if not found then
                        all = false
                        break
                    end
                end
                if all then
                    return 2
                end
            end
        end
        if contains then
            return 3
        end
        -- an NPC's title: "blacksmith" finds the blacksmiths
        local tkey = e.tkey
        if tkey and #q >= 3 and tkey:find(q, 1, true) then
            return tkey:sub(1, #q) == q and 4 or 5
        end
    end

    local function consider(e, allowTypos)
        if opts.faction and not DB.ForMyFaction(e) then
            return
        end
        local s
        if allowTypos then
            -- slow typo matching, only for names starting with the same letter
            if e.key:sub(1, 1) == first then
                e.words = e.words or Geo.Words(e.name)
                s = Geo.MatchScore(e, q, qWords)
            end
        else
            s = quick(e)
        end
        if s and opts.zone and e.kind ~= "quest" then
            local inZone = false
            for _, p in ipairs(DB.Points(e)) do
                if Geo.SameMap(p.m, opts.zone) then
                    inZone = true
                    break
                end
            end
            if not inZone then
                s = nil
            end
        end
        if s then
            scored[#scored + 1] = { e = e, s = s }
        end
    end
    -- which tables to look in, and whether an entry belongs to the tab
    local tables = {}
    for kind in pairs(kinds) do
        tables[KIND_TABLE[kind]] = true
    end
    local function wanted(e)
        if e.kind == "npc" then
            local enemy = DB.IsEnemy(e)
            return (enemy and kinds.enemy) or (not enemy and kinds.npc)
        end
        return true
    end
    local function pass(allowTypos)
        for tbl in pairs(tables) do
            for _, e in pairs(DB[tbl] or {}) do
                if wanted(e) then
                    consider(e, allowTypos)
                end
            end
        end
    end
    pass(false)
    -- nothing? try again allowing typos (not for very long searches, where
    -- a typo guess would be both slow and useless)
    if #scored == 0 and #q >= 4 and #q <= 24 and #qWords <= 4 then
        pass(true)
    end
    table.sort(scored, function(a, b)
        if a.s ~= b.s then
            return a.s < b.s
        end
        if #a.e.name ~= #b.e.name then
            return #a.e.name < #b.e.name
        end
        return a.e.id < b.e.id
    end)
    local out = {}
    for i = 1, math.min(limit, #scored) do
        out[i] = scored[i].e
    end
    return out, #scored
end

-- ---------------------------------------------------------------------------
-- Near you: what /wp opens to before you type anything
-- ---------------------------------------------------------------------------
-- The classic database's area IDs on the same ground as map m.
local areasOn = {}
local function AreasOn(m)
    local set = areasOn[m]
    if set then
        return set
    end
    set = {}
    for area in pairs(DB.zoneNames or {}) do
        local am = DB.MapForArea(area)
        if am and Geo.SameMap(am, m) then
            set[area] = true
        end
    end
    -- kept once found (a new WoW Forever map has none: looked up again, it's quick)
    if next(set) then
        areasOn[m] = set
    end
    return set
end

-- Could it have a spot on map m? A quick look before working its spots out.
local function MaybeOn(e, m, areas)
    if e.points then
        for _, p in ipairs(e.points) do
            if Geo.SameMap(p.m, m) then
                return true
            end
        end
        return false
    end
    for _, w in ipairs(e.world or {}) do
        if w[2] == 0 or Geo.SameMap(w[2], m) then
            return true
        end
    end
    for _, p in ipairs(e.extra or {}) do
        if Geo.SameMap(p.m, m) then
            return true
        end
    end
    local c = e.coords
    if c and c ~= "" then
        for area in c:gmatch("(%d+):") do
            if areas[tonumber(area)] then
                return true
            end
        end
    end
    return false
end

-- How far its closest spot on map m is, in yards.
local function DistanceOn(e, m)
    local best
    for _, p in ipairs(DB.Points(e)) do
        if Geo.SameMap(p.m, m) then
            local d = Geo.GetVector(p)
            if d and (not best or d < best) then
                best = d
            end
        end
    end
    return best
end

-- What's on the map you're on, nearest first: NPCs, enemies, objects and
-- places by their closest spot, quests by who gives them (new ones you're
-- old enough for) or where the game shows them (the ones in your log).
-- kinds and opts as in DB.Search. Returns entries, how many there were,
-- and each entry's distance in yards.
local nearbyCache = {}
function DB.Nearby(kinds, opts, limit)
    opts = opts or {}
    limit = limit or 300
    local m = C_Map.GetBestMapForUnit("player")
    if not m then
        return {}, 0, {}
    end
    -- the entries on this map (slow: kept until the next merge); distances every time
    local cacheKey = table.concat({ m, opts.faction and "f" or "", kinds.quest and "q" or "", kinds.npc and "n" or "",
        kinds.enemy and "e" or "", kinds.object and "o" or "", kinds.place and "p" or "" }, ":")
    local cached = nearbyCache[cacheKey]
    if not (cached and cached.gen == DB.generation) then
        local areas = AreasOn(m)
        local list = {}
        local function look(tbl, want)
            for _, e in pairs(tbl or {}) do
                if want(e) and (not opts.faction or DB.ForMyFaction(e)) and MaybeOn(e, m, areas) then
                    list[#list + 1] = e
                end
            end
        end
        if kinds.npc or kinds.enemy or kinds.quest then
            look(DB.units, function(e)
                if e.name == "" then
                    return false
                end
                local enemy = DB.IsEnemy(e)
                -- quest givers are looked at for the quests they give
                return (enemy and kinds.enemy) or (not enemy and (kinds.npc or kinds.quest))
            end)
        end
        if kinds.object or kinds.quest then
            look(DB.objects, function(e)
                return e.name ~= ""
            end)
        end
        if kinds.place then
            look(DB.places, function()
                return true
            end)
        end
        cached = { gen = DB.generation, list = list }
        nearbyCache[cacheKey] = cached
    end

    local dist, out = {}, {}
    local here = {} -- NPC/object -> distance, for the quests they give
    for _, e in ipairs(cached.list) do
        local d = DistanceOn(e, m)
        if d then
            here[e] = d
            local wanted
            if e.kind == "npc" then
                local enemy = DB.IsEnemy(e)
                wanted = (enemy and kinds.enemy) or (not enemy and kinds.npc)
            elseif e.kind == "object" then
                wanted = kinds.object
            else
                wanted = kinds.place
            end
            if wanted then
                dist[e] = d
                out[#out + 1] = e
            end
        end
    end

    if kinds.quest then
        local level = UnitLevel and tonumber(UnitLevel("player")) or 1
        local function closest(ids, tbl)
            local best
            for _, id in ipairs(ids or {}) do
                local d = tbl[id] and here[tbl[id]]
                if d and (not best or d < best) then
                    best = d
                end
            end
            return best
        end
        -- new quests from who's around you
        for _, q in pairs(DB.quests) do
            if (q.startU or q.startO) and (not q.min or q.min <= level) and (not opts.faction or DB.ForMyFaction(q)) then
                local du, dobj = closest(q.startU, DB.units), closest(q.startO, DB.objects)
                local d = du and dobj and math.min(du, dobj) or du or dobj
                if d and DB.QuestState(q) == "new" then
                    dist[q] = d
                    out[#out + 1] = q
                end
            end
        end
        -- quests in your log: where to go next, when that's on this map
        if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestIDForLogIndex then
            local ok, num = pcall(C_QuestLog.GetNumQuestLogEntries)
            for i = 1, (ok and tonumber(num) or 0) do
                local okID, id = pcall(C_QuestLog.GetQuestIDForLogIndex, i)
                local q = okID and id and DB.quests[id]
                if q and not dist[q] then
                    local best
                    for _, t in ipairs(DB.QuestTargets(q, DB.DefaultQuestStep(q))) do
                        local d = DistanceOn(t, m)
                        if d and (not best or d < best) then
                            best = d
                        end
                    end
                    if best then
                        dist[q] = best
                        out[#out + 1] = q
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if dist[a] ~= dist[b] then
            return dist[a] < dist[b]
        end
        return a.id < b.id
    end)
    local total = #out
    for i = total, limit + 1, -1 do
        dist[out[i]] = nil
        out[i] = nil
    end
    return out, total, dist
end

-- ---------------------------------------------------------------------------
-- Quests
-- ---------------------------------------------------------------------------
local function Collect(out, ids, tbl)
    for _, id in ipairs(ids or {}) do
        local e = tbl[id]
        if e then
            out[#out + 1] = e
        end
    end
end

-- Where the game's own map shows a quest in your log right now: its
-- objective while you work on it, the hand-in once it's complete. This is
-- what makes Forever quests the database has no spots for still work.
local function LiveSpot(q, step)
    if not ns.Places or not ns.Places.QuestPosition then
        return nil
    end
    local state = DB.QuestState(q)
    if (step == "objective" and state ~= "active") or (step == "end" and state ~= "ready") then
        return nil
    end
    local m, x, y = ns.Places.QuestPosition(q.id)
    if m and ns.Num(x) and ns.Num(y) then
        return { kind = "spot", id = 0, name = Geo.GetMapName(m) or q.name, points = { { m = m, x = x, y = y } } }
    end
end

-- The NPCs/objects for a step of a quest: "start", "objective" or "end".
function DB.QuestTargets(q, step)
    local out = {}
    local live = step ~= "start" and LiveSpot(q, step)
    if live then
        out[1] = live
    end
    -- the game's own quest map marker for this step
    local marks = DB.marks[q.id] and DB.marks[q.id][step]
    local function AddMarks()
        for _, w in ipairs(marks or {}) do
            out[#out + 1] = { kind = "spot", id = 0, name = Geo.GetMapName(w[2]) or q.name, world = { w } }
        end
    end
    if step == "start" then
        Collect(out, q.startU, DB.units)
        Collect(out, q.startO, DB.objects)
        if #out == 0 then
            AddMarks()
        end
    elseif step == "end" then
        Collect(out, q.endU, DB.units)
        Collect(out, q.endO, DB.objects)
        if #out == 0 then
            AddMarks()
        end
    else
        AddMarks()
        -- the objective area the game showed you for it
        if q.area then
            out[#out + 1] = { kind = "spot", id = 0, name = Geo.GetMapName(q.area.m) or q.name, points = { q.area } }
        end
        Collect(out, q.objU, DB.units)
        Collect(out, q.objO, DB.objects)
        for _, itemID in ipairs(q.objI or {}) do
            local item = DB.items[itemID]
            if item then
                Collect(out, item.dropU, DB.units)
                Collect(out, item.dropO, DB.objects)
                Collect(out, item.soldBy, DB.units)
            end
        end
    end
    return out
end

-- Where an item comes from.
function DB.ItemSources(item)
    local out = {}
    Collect(out, item.dropU, DB.units)
    Collect(out, item.dropO, DB.objects)
    Collect(out, item.soldBy, DB.units)
    return out
end

-- Closest spawn of any of the given NPCs/objects: returns entry, point, dist.
function DB.NearestOf(entries, opts)
    local bestE, bestP, bestD, fallbackE, fallbackP
    for _, e in ipairs(entries) do
        if not (opts and opts.faction) or DB.ForMyFaction(e) then
            local pts = DB.Points(e)
            if #pts > 0 then
                local p, d = DB.Nearest(pts)
                if d and (not bestD or d < bestD) then
                    bestE, bestP, bestD = e, p, d
                elseif not fallbackE then
                    fallbackE, fallbackP = e, p
                end
            end
        end
    end
    if bestE then
        return bestE, bestP, bestD
    end
    return fallbackE, fallbackP
end

-- Is this quest in your log / done?
function DB.QuestState(q)
    if C_QuestLog then
        if C_QuestLog.GetLogIndexForQuestID then
            local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, q.id)
            if ok and idx then
                local okc, done = pcall(C_QuestLog.IsComplete, q.id)
                return (okc and done) and "ready" or "active"
            end
        end
        if C_QuestLog.IsQuestFlaggedCompleted then
            local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, q.id)
            if ok and done then
                return "done"
            end
        end
    end
    return "new"
end

-- The step a click on a quest should lead to.
function DB.DefaultQuestStep(q)
    local state = DB.QuestState(q)
    if state == "ready" then
        return "end"
    elseif state == "active" then
        return #DB.QuestTargets(q, "objective") > 0 and "objective" or "end"
    end
    return "start"
end

-- ---------------------------------------------------------------------------
-- Services: nearest mailbox, innkeeper, flight master, ...
-- ---------------------------------------------------------------------------
function DB.ServiceEntries(service)
    local letter = MyFaction()
    local out = {}
    for _, s in ipairs(DB.services[service] or {}) do
        if s.fac == "" or not letter or s.fac:find(letter, 1, true) then
            local e = s.entry or (s.id < 0 and DB.objects[-s.id]) or DB.units[s.id]
            if e then
                out[#out + 1] = e
            end
        end
    end
    return out
end

-- Set the arrow on something from the database. Returns the waypoint.
function DB.GoTo(e, p, title)
    if not e or not p then
        return nil
    end
    return ns.WP.Add(p.m, p.x, p.y, { title = title or e.name, source = "find" })
end
