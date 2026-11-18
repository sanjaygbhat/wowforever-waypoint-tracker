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
-- The database is some 34,000 entries read from text: over a second of
-- work. DB.Load does it all at once, as it always did. DB.LoadAsync does
-- the same steps a little each frame where the client can pause a Lua
-- function (coroutines) and has a frame clock (debugprofilestop), so the
-- game never stops for it. Every loop that reads rows calls Tick; while a
-- slice of a spread-out load runs (`pace`), Tick pauses the load once the
-- frame's share is used up. All at once, Tick does nothing.
local SLICE_MS, SLICE_COMBAT_MS = 8, 2 -- a frame's share: out of combat (at most), in combat
-- Out of combat a slice takes this much of what the rest of the last frame
-- took (the frame less our own slice in it), so a high frame rate stays
-- high, but never less than SLICE_MIN_MS. With the frame rate capped at
-- 60 that settles at about 4.8 ms a frame (16.7 ms less the slice, times
-- 0.4); at 144 it is the least, 3 ms; the most, 8 ms, from about 36
-- frames a second down. Where the frame rate is not capped and the slice
-- lengthens the frame, 60 frames a second give about 6.7 ms.
local SLICE_SHARE, SLICE_MIN_MS = 0.4, 3
-- the same without a readable clock, counted in rows (about 100 a millisecond)
local SLICE_UNITS, SLICE_COMBAT_UNITS = 800, 200
local CLOCK_EVERY = 16 -- rows between two looks at the clock
local pace -- { units, next, start, ms, max, all } while a slice runs

-- The frame clock in milliseconds, or nil (no clock, or an unreadable answer).
local function Clock()
    return type(debugprofilestop) == "function" and ns.Num(debugprofilestop()) or nil
end

local function Tick(units)
    local p = pace
    if not p then
        return
    end
    local n = p.units + (units or 1)
    p.units = n
    if n < p.next then
        return
    end
    p.next = n + CLOCK_EVERY
    local now = p.start and Clock()
    local spent
    if now then
        spent = now - p.start >= p.ms
    else
        spent = n >= p.max
    end
    if spent then
        coroutine.yield()
    end
end

-- pairs for a loop that may pause: the keys there are now, in pairs' own
-- order (your discoveries can gain entries between two slices, which plain
-- pairs must never see happen). All at once it is pairs itself.
local function Each(t)
    if not pace then
        return pairs(t)
    end
    local keys, n = {}, 0
    for k in pairs(t) do
        n = n + 1
        keys[n] = k
    end
    local i = 0
    return function()
        while i < n do
            i = i + 1
            local v = t[keys[i]]
            if v ~= nil then
                return keys[i], v
            end
        end
    end
end

-- Shipped rows split in one native pattern; discoveries keep the general parser.
local fieldPatterns = {}
for _, count in ipairs({ 3, 4, 5, 12 }) do
    fieldPatterns[count] = "^" .. string.rep("([^\t]*)\t", count - 1) .. "([^\t]*)$"
end
local function Split(line, columns)
    if columns then
        local fields = { line:match(fieldPatterns[columns]) }
        if fields[1] then return fields end
    end
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

-- Keep the supplement as text until a service or a discovery needs its facts.
local EMPTY = {}
local supplementSource, supplementCache, supplementLines
local function ServiceRows(service, kind, id)
    local text = WaypointTrackerData and WaypointTrackerData.serviceSupplement or ""
    if text ~= supplementSource then
        supplementSource, supplementCache, supplementLines = text, {}, nil
    end
    local key = service or kind .. id
    if supplementCache[key] then return supplementCache[key] end
    if not service and supplementLines and not supplementLines[key] then return EMPTY end
    local rows = {}
    local function Add(line)
        if service then
            local services = line:match("^S[NO]\t%d+\t[^\t]*\t[^\t]*\t([^\t]*)\t")
            if not services or not ("," .. services .. ","):find("," .. service .. ",", 1, true) then return end
        end
        local f = Split(line)
        local row = { id = tonumber(f[2]), kind = f[1] == "SO" and "object" or "npc", fac = f[3],
            name = f[4], services = f[5], mode = f[6], spots = {} }
        if not row.id then return end
        for m, x, y, c in (f[7] or ""):gmatch("(%d+):([%d.]+),([%d.]+),(%d+)") do
            row.spots[#row.spots + 1] = { m = tonumber(m), x = tonumber(x), y = tonumber(y), c = tonumber(c) }
        end
        rows[#rows + 1] = row
    end
    if service then
        for line in text:gmatch("[^\n]+") do Add(line) end
    else
        -- Index text once, then parse only identities with discoveries.
        if not supplementLines then
            supplementLines = {}
            for line in text:gmatch("[^\n]+") do
                local tag, rid = line:match("^S([NO])\t(%d+)\t")
                if rid then
                    local identity = (tag == "N" and "npc" or "object") .. rid
                    local list = supplementLines[identity] or {}
                    supplementLines[identity] = list
                    list[#list + 1] = line
                end
            end
        end
        for _, line in ipairs(supplementLines[key] or {}) do Add(line) end
    end
    if not service and #rows == 0 then rows = EMPTY end
    supplementCache[key] = rows
    return rows
end

local function NumList(s)
    local out = {}
    for n in (s or ""):gmatch("%-?%d+") do
        out[#out + 1] = tonumber(n)
    end
    return out
end
DB.NumList = NumList

-- Most quests and items have nobody in most of their lists (who starts it,
-- what drops it...): tens of thousands of empty tables. They all hold this
-- one list instead, which is never written: a list gets a table of its own
-- when the first ID goes in (AddId, AddIds). Writing to it is an error.
local NO_IDS = setmetatable({}, {
    __newindex = function()
        error("the shared empty ID list is read-only: give the entry a list of its own", 2)
    end,
})
DB.NO_IDS = NO_IDS

-- NumList for an entry's field: the shared empty list when there are none.
local function IdList(s)
    if not s or s == "" then
        return NO_IDS
    end
    local out = NumList(s)
    return out[1] and out or NO_IDS
end

-- Adds an ID to an entry's list once (to a list of its own).
local function AddId(e, field, value)
    local list = e[field]
    for i = 1, #list do
        if list[i] == value then
            return
        end
    end
    if list == NO_IDS then
        e[field] = { value }
    else
        list[#list + 1] = value
    end
end

-- Adds several IDs to an entry's list, each once, in their order. Long
-- lists are checked through a set instead of read through for every ID.
local function AddIds(e, field, ids)
    local n = #ids
    if n == 0 then
        return
    end
    local list = e[field]
    if list == NO_IDS then
        list = {}
        e[field] = list
    end
    if #list + n <= 8 then
        for i = 1, n do
            local value, have = ids[i], false
            for k = 1, #list do
                if list[k] == value then
                    have = true
                    break
                end
            end
            if not have then
                list[#list + 1] = value
            end
        end
        return
    end
    local have = {}
    for i = 1, #list do
        have[list[i]] = true
    end
    for i = 1, n do
        local value = ids[i]
        if not have[value] then
            have[value] = true
            list[#list + 1] = value
        end
    end
end

local function NameTable(block, descriptions)
    local names = {}
    for line in Lines(block) do
        local id, name, more = line:match("^([^\t]+)\t([^\t]*)(.*)$")
        id = tonumber(id)
        if id then
            names[id] = descriptions and { name, more:match("^\t([^\t]*)") } or name
        end
        Tick(0.5)
    end
    return names
end

local function Parse(data)
    local loc = GetLocale()
    if loc == "esMX" then
        loc = "esES"
    end
    local en = data.names_enUS or {}
    local here = data["names_" .. loc] or {}
    local function names(kind)
        local localized = NameTable(here[kind], kind == "quests")
        -- English is a fallback; avoid splitting/allocating a second complete
        -- name table when the client locale already supplies the same IDs.
        if here ~= en then
            for line in Lines(en[kind]) do
                local id = tonumber(line:match("^(%d+)\t"))
                if id and not localized[id] then
                    local _, name, more = line:match("^([^\t]+)\t([^\t]*)(.*)$")
                    localized[id] = kind == "quests" and { name, more:match("^\t([^\t]*)") } or name
                end
                Tick(0.3)
            end
        end
        return localized
    end
    local unitNames, objectNames, questNames, itemNames, zoneNames = names("units"), names("objects"), names("quests"), names("items"), names("zones")
    -- the world's treasure chests, known by their English names in every language
    local enObjects = here == en and objectNames or NameTable(en.objects)
    local function IsChest(id)
        local f = enObjects[id]
        return f and ns.Treasure and ns.Treasure.IsChestName(f) or false
    end

    DB.zoneNames = zoneNames

    local function entry(kind, id, name)
        -- .words is filled in later, only when a search needs it
        return { kind = kind, id = id, name = name, key = Geo.Squash(name) }
    end

    local raw = data.raw or {}
    for line in Lines(raw.units) do
        local f = Split(line, 5)
        local id = tonumber(f[1])
        local n = id and unitNames[id]
        if n and n ~= "" then
            local e = entry("npc", id, n)
            e.level, e.fac, e.rank, e.coords = f[2], f[3], f[4], f[5]
            DB.units[id] = e
        end
        Tick()
    end
    for line in Lines(raw.objects) do
        local f = Split(line, 3)
        local id = tonumber(f[1])
        local n = id and objectNames[id]
        if n and n ~= "" then
            local e = entry("object", id, n)
            e.fac, e.coords = f[2], f[3]
            e.chest = IsChest(id) or nil
            -- ore and herbs, for the suggested gathering routes
            local en = enObjects[id]
            e.gather = en and ns.Routes and ns.Routes.GatherKind(en) or nil
            DB.objects[id] = e
        end
        Tick()
    end
    for line in Lines(raw.quests) do
        local f = Split(line, 12)
        local id = tonumber(f[1])
        local n = id and questNames[id]
        if n and n[1] ~= "" then
            local e = entry("quest", id, n[1])
            e.text = n[2]
            e.level, e.min = tonumber(f[2]), tonumber(f[3])
            e.race, e.class = tonumber(f[4]), tonumber(f[5])
            e.startU, e.startO = IdList(f[6]), IdList(f[7])
            e.endU, e.endO = IdList(f[8]), IdList(f[9])
            e.objU, e.objO, e.objI = IdList(f[10]), IdList(f[11]), IdList(f[12])
            DB.quests[id] = e
        end
        Tick(2)
    end
    for line in Lines(raw.items) do
        local f = Split(line, 4)
        local id = tonumber(f[1])
        local n = id and itemNames[id]
        if n and n ~= "" then
            local e = entry("item", id, n)
            e.dropU, e.dropO, e.soldBy = IdList(f[2]), IdList(f[3]), IdList(f[4])
            DB.items[id] = e
        end
        Tick()
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
            Tick(0.2)
        end
        DB.services[f[1]] = list
    end
end

-- Set by the loader once it has read the shipped stores: the next merge is
-- their first, and takes them apart (Bake, further down).
local bakeNext = false
local Merge -- (re)adds the stores and your discoveries; further down

-- The game reads the data addon's files in one go (there is no doing that
-- a little at a time): asked for while nothing of it is here yet.
local function ReadFiles()
    if not (WaypointTrackerData and WaypointTrackerData.raw) then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then
            pcall(load, DATA_ADDON)
        end
    end
end

-- The shipped rows are in the tables and the load has not finished: so
-- only when a failure nothing protects ended a spread-out load half-way.
-- The next try goes on from there (the game reads the data addon's files
-- once a session: there is no asking for the rows again).
local parsed = false

-- Everything after the files, the same all at once and a little each frame.
-- `call`: ns.Call, or its like for a step that may pause (Paused). `spread`:
-- the database says it is ready only when all of it is (other code runs
-- between the slices); all at once it says so where it always did.
local function Build(call, spread)
    local data = WaypointTrackerData
    if data and data.raw then
        if not call(Parse, data) then
            return false, "broken"
        end
        parsed = true
        -- the raw text isn't needed any more
        data.raw = nil
        for k in pairs(data) do
            if type(k) == "string" and k:find("^names_") then
                data[k] = nil
            end
        end
    elseif not parsed and DB.ready then
        -- still no database folder: keep searching your own discoveries
        DB.MergeIfLearned()
        return true, "missing"
    end
    local hasShipped = parsed
    if data and data.clientItems then
        call(DB.ParseClientItems, data)
        data.clientItems, data.clientItemNames = nil, nil
    end
    if data and data.sources then
        call(DB.ParseSources, data)
        data.sources, data.sourceNames = nil, nil
    end
    if data and type(data.client) == "table" then
        call(DB.ParseClient, data.client)
        data.client = nil
    end
    if not spread then
        DB.hasShipped = hasShipped
        DB.ready = true
        -- without the database folder, try loading it again next time
        DB.loaded = hasShipped
        parsed = false
    end
    -- Forever content: what the community shared (shipped with the data
    -- addon) and what you discovered yourself. A shipped store is the same
    -- format as discoveries; one that cannot be read is reported and left
    -- out (its text is let go first: it is not tried again), and Find
    -- works on with the rest.
    if ns.Learn then
        for _, source in ipairs({ "curated", "community" }) do
            local field = source == "curated" and "curated" or "forever"
            local text = data and data[field]
            if type(text) == "string" then
                data[field] = nil
                local st = { npcs = {}, objects = {}, quests = {}, mailboxes = {} }
                if call(ns.Learn.Import, text, st, true, Tick) then
                    DB[source] = st
                end
            end
        end
    end
    bakeNext = hasShipped
    -- learned data lives in SavedVariables: if it's damaged, Find still works
    call(Merge, true)
    if spread then
        DB.hasShipped = hasShipped
        DB.ready = true
        DB.loaded = hasShipped
        parsed = false
    end
    if not hasShipped then
        return true, "missing"
    end
    return true
end

-- ---------------------------------------------------------------------------
-- A little each frame
-- ---------------------------------------------------------------------------
-- Is loading spread over frames? Where the client can pause a Lua function
-- and has a frame clock. Without them it all happens at once, as before.
-- Tests can choose (nil: decide from the client).
local forceSliced
local function Sliced()
    local co = coroutine
    if forceSliced == false or type(co) ~= "table" or type(co.create) ~= "function" or type(co.resume) ~= "function"
        or type(co.yield) ~= "function" or type(co.status) ~= "function" then
        return false
    end
    return forceSliced == true or type(debugprofilestop) == "function"
end
DB.Sliced = Sliced

-- An error raised in a coroutine, with where it was raised when the client says.
local function Traced(co, err)
    local traceback = type(debug) == "table" and debug.traceback
    if type(traceback) == "function" then
        local ok, text = pcall(traceback, co, tostring(err))
        if ok and type(text) == "string" then
            return text
        end
    end
    return err
end

-- ns.Call for a step of a spread-out load: the step runs in a coroutine of
-- its own (a pause can't cross xpcall), which this one hands every pause
-- on from. An error is reported once and the load goes on, as with ns.Call.
local function Paused(fn, ...)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co, ...)
    while ok and coroutine.status(co) ~= "dead" do
        coroutine.yield()
        ok, err = coroutine.resume(co)
    end
    if not ok then
        ns.ReportError(Traced(co, err))
    end
    return ok
end

-- The load under way: { co, pace, waiting, share, stats, spent } (nil: none).
-- A hidden frame's OnUpdate gives it a slice every frame.
local job
local building = false -- DB.Load is reading it all at once right now
local driver = CreateFrame("Frame")
driver:Hide()

-- Rows a whole load reads, for the share done (DB.Loading): in English,
-- and in the other languages (which also read the English names, for
-- what theirs leave out). It only has to be about right: the share stops
-- at 99% until the load has finished.
local EXPECTED_UNITS, EXPECTED_UNITS_OTHER = 180000, 204000

local function Finish(j, ok, why)
    job = nil
    driver:Hide()
    j.finished, j.ok, j.why = true, ok, why
    j.stats.units = j.pace.all
    DB.loadStats = j.stats -- { slices, units, most (rows in one slice) }: how the load went (tests, the profile)
    for _, fn in ipairs(j.waiting) do
        ns.Call(fn, ok, why)
    end
    ns.Fire("DB_LOADED", ok, why)
    return ok, why
end

-- One slice. `atOnce`: the rest of the load, now (DB.Load while it runs).
-- `elapsed`: the seconds the last frame took (OnUpdate's).
-- Returns whether the load has finished, and then its answer.
local function Slice(j, atOnce, elapsed)
    local status = coroutine.status(j.co)
    if status == "dead" then
        return true, Finish(j, false, "broken")
    elseif status ~= "suspended" then
        return false -- asked for from inside the load itself: it is running
    end
    local p = j.pace
    if atOnce then
        pace = nil
    else
        local ms, max = SLICE_MS, SLICE_UNITS
        if InCombatLockdown and ns.Plain(InCombatLockdown()) then
            ms, max = SLICE_COMBAT_MS, SLICE_COMBAT_UNITS
        else
            -- what the rest of the last frame took: all of it but our own slice
            local frame = ns.Num(elapsed)
            if frame and frame > 0 then
                ms = math.max(SLICE_MIN_MS, math.min(SLICE_MS, (frame * 1000 - (j.spent or 0)) * SLICE_SHARE))
            end
        end
        p.units, p.next, p.start = 0, CLOCK_EVERY, Clock()
        p.ms, p.max = ms, max
        pace = p
    end
    local ok, a, b = coroutine.resume(j.co)
    pace = nil
    -- (with a clock that reads: without one a slice is a number of rows)
    local now = not atOnce and p.start and Clock()
    j.spent = now and now >= p.start and now - p.start or nil
    p.all = p.all + p.units
    if p.units > j.stats.most then
        j.stats.most = p.units
    end
    p.units = 0
    j.stats.slices = j.stats.slices + 1
    if coroutine.status(j.co) ~= "dead" then
        return false
    end
    if not ok then
        -- a failure that nothing protects (every step is protected: so in
        -- the loader's own lines): as a database that couldn't be read
        ns.ReportError(Traced(j.co, a))
        return true, Finish(j, false, "broken")
    end
    return true, Finish(j, a, b)
end

driver:SetScript("OnUpdate", ns.Safe(function(_, elapsed)
    local j = job
    if not j then
        driver:Hide()
        return
    end
    if not Slice(j, false, elapsed) then
        local share = math.min(0.99, j.pace.all / j.expected)
        if share > j.share then
            j.share = share
        end
        ns.Fire("DB_LOADING", j.share)
    end
end))

-- The share of a spread-out load that is done (0..1), or nil when none runs.
function DB.Loading()
    return job and job.share or nil
end

-- A failure in the loader's own lines, with where it was.
local function Trace(err)
    local stack = (type(debugstack) == "function" and debugstack(2))
        or (type(debug) == "table" and type(debug.traceback) == "function" and debug.traceback("", 2))
    return type(stack) == "string" and (tostring(err) .. "\n" .. stack) or err
end

-- All of it at once, the files having been asked for. An error in the
-- loader's own lines (every step is protected) goes on to whoever asked,
-- with where it happened.
local function BuildNow()
    if building then
        return false, "loading"
    end
    building = true
    local ran, ok, why = xpcall(function()
        return Build(ns.Call, false)
    end, Trace)
    building = false
    if not ran then
        error(ok, 0)
    end
    return ok, why
end

-- Returns true when the database is ready, or false plus a reason
-- ("missing" when the data addon isn't installed; "loading" when asked
-- from inside the load itself, which only a mistake would do). All of it
-- now: also what is left of a load that was being spread over frames.
function DB.Load()
    if DB.loaded then
        DB.MergeIfLearned()
        return true
    end
    local j = job
    if j then
        if coroutine.status(j.co) ~= "suspended" then
            return false, "loading"
        end
        local done, ok, why = Slice(j, true)
        while not done do
            done, ok, why = Slice(j, true)
        end
        return ok, why
    end
    if building then
        return false, "loading"
    end
    ReadFiles()
    return BuildNow()
end

-- The same, without stopping the game for it where loading can be spread
-- over frames. Returns ok, reason when the database is ready now (also
-- everywhere loading can't be spread out: then this is DB.Load). Otherwise
-- returns nothing and calls fn(ok, reason) once it is ready; until then
-- DB.Loading() says how far it is, DB_LOADING fires as it goes on and
-- DB_LOADED when it has finished.
function DB.LoadAsync(fn)
    if DB.loaded or building or not Sliced() then
        return DB.Load()
    end
    local started = false
    if not job then
        ReadFiles()
        if not (WaypointTrackerData and WaypointTrackerData.raw) and not parsed and DB.ready then
            -- still no database folder: nothing to spread out
            return BuildNow()
        end
        local locale = GetLocale and ns.Str(GetLocale())
        job = {
            co = coroutine.create(function()
                return Build(Paused, true)
            end),
            pace = { units = 0, next = CLOCK_EVERY, all = 0 },
            waiting = {}, share = 0, stats = { slices = 0, most = 0 },
            expected = (locale == nil or locale == "enUS" or locale == "enGB") and EXPECTED_UNITS or EXPECTED_UNITS_OTHER,
        }
        started = true
    end
    local j = job
    if started then
        driver:Show()
        ns.Fire("DB_LOADING", 0)
        -- what the announcement led to has finished the load (DB.Load,
        -- asked for by someone listening): then this is the answer, now
        if j.finished then
            return j.ok, j.why
        end
    end
    if fn then
        j.waiting[#j.waiting + 1] = fn
    end
end

-- tests: true/false forces loading spread over frames or all at once; nil decides from the client
function DB._SetSliced(on)
    forceSliced = on
end

-- ---------------------------------------------------------------------------
-- The WoW Forever game client's own tables (Client.lua): flight paths,
-- towns and quest map markers. Positions are world positions; the game
-- turns them into map positions.
-- ---------------------------------------------------------------------------
local function Lines(text, fn, units)
    for line in (text or ""):gmatch("[^\n]+") do
        fn(Split(line))
        Tick(units)
    end
end

local function NameTable(text)
    local out = {}
    for line in (text or ""):gmatch("[^\n]+") do
        local id, name = line:match("^(%-?%d+)\t([^\t]+)")
        if id then out[tonumber(id)] = name end
        Tick(0.3)
    end
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
        end, 2)
    end
    Lines(data.clientItems, function(f)
        local id = tonumber(f[1])
        if not id then
            return
        end
        local t = texts[id] or {}
        local e = DB.items[id]
        if not e and t.name then
            e = { kind = "item", id = id, name = t.name, key = Geo.Squash(t.name), dropU = NO_IDS, dropO = NO_IDS, soldBy = NO_IDS, learned = "game" }
            DB.items[id] = e
        end
        if e then
            e.class, e.subclass, e.quality = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
            e.ilvl, e.reqlevel, e.startsQuest = tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
            e.desc = t.desc
        end
    end, 2)
end

-- Who sells, drops or holds every item (Sources.lua), with the names of the
-- items nothing else names. Adds to what the classic database knows.
function DB.ParseSources(data)
    local loc = GetLocale and GetLocale() or "enUS"
    if loc == "esMX" then
        loc = "esES"
    end
    local names = data.sourceNames or {}
    local named = NameTable(names.enUS)
    if loc ~= "enUS" then
        for id, n in pairs(NameTable(names[loc])) do
            named[id] = n
        end
    end
    Lines(data.sources, function(f)
        local id = tonumber(f[1])
        if not id then
            return
        end
        local e = DB.items[id]
        if not e and named[id] then
            e = { kind = "item", id = id, name = named[id], key = Geo.Squash(named[id]), dropU = NO_IDS, dropO = NO_IDS, soldBy = NO_IDS }
            DB.items[id] = e
        end
        if e then
            e.dropU, e.dropO, e.soldBy = e.dropU or NO_IDS, e.dropO or NO_IDS, e.soldBy or NO_IDS
            if f[2] and f[2] ~= "" then AddIds(e, "dropU", NumList(f[2])) end
            if f[3] and f[3] ~= "" then AddIds(e, "dropO", NumList(f[3])) end
            if f[4] and f[4] ~= "" then AddIds(e, "soldBy", NumList(f[4])) end
        end
    end, 3)
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
                Tick(0.5)
            end
        end
    end
end

local function MyLetter()
    local f = ns.Str(UnitFactionGroup and UnitFactionGroup("player"))
    return (f == "Horde" and "H") or (f == "Alliance" and "A") or ""
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
            Tick(0.3)
        end
        index[tbl] = t
    end
    return index
end

-- What the database knows about an entry before your own discoveries are
-- added to it (taken the first time they are, or when first asked), so
-- only what's new is kept and shared.
local function SupplementFacts(ship, kind, id)
    local rows = ServiceRows(nil, kind, id)
    if ship.supplement == rows then return ship end
    ship.supplement = rows
    for _, row in ipairs(rows) do
        -- A newly created entry's name came from the discovery, not shipping.
        if ship.fresh or ship.name == "" then ship.name = row.name end
        ship.fresh = false
        if ship.services == EMPTY then ship.services = {} end
        if ship.access == EMPTY then ship.access = {} end
        for service in row.services:gmatch("[^,]+") do
            ship.services[service] = true
            ship.access[service] = ns.Trainers.MergeAccess(ship.access[service], row.fac)
        end
    end
    return ship
end

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
    local services, access = e.svc and {} or EMPTY, e.svcAccess and {} or EMPTY
    for service in pairs(e.svc or EMPTY) do services[service] = true end
    for service, fac in pairs(e.svcAccess or EMPTY) do access[service] = fac end
    local extra = e.extra and {} or EMPTY
    for _, p in ipairs(e.extra or EMPTY) do extra[#extra + 1] = p end
    return SupplementFacts({ extra = extra, fresh = created, findFresh = created or e.name == "", name = e.name, title = e.title, spots = #(e.extra or {}),
        enemy = DB.IsEnemy(e), hostile = e.hostile, fac = e.fac, services = services, access = access }, e.kind, e.id)
end

-- `note` (the first merge of a shipped store, Bake below): collects the
-- records that found no entry to add to (note.late) and the service rows
-- whose faction is the player's own letter (note.byLetter).
local function MergeStore(st, source, note)
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
                    if ns.Trainers.IsService(service) and not l.hostile then
                        e.svcAccess = e.svcAccess or {}
                        e.svcAccess[service] = ns.Trainers.MergeAccess(e.svcAccess[service], l.fac)
                    end
                end
                if e.kind == "npc" or e.kind == "object" then
                    DB.services[service] = DB.services[service] or {}
                    local row = { observedAccess = l.fac or (mine and (e.kind == "object" and "AH" or letter)) or "", id = e.kind == "object" and -e.id or e.id, fac = ns.Trainers.IsService(service) and (not l.hostile and l.fac or "") or (l.hostile and "" or (l.fac or (e.kind == "object" and "" or letter))) }
                    table.insert(DB.services[service], row)
                    if note and not ns.Trainers.IsService(service) and not l.hostile and not l.fac and e.kind ~= "object" then
                        note.byLetter[row] = true
                    end
                end
            end
        end
    end
    for id, l in Each(T(st.npcs)) do
        Tick(2)
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
            if l.fac then e.fac = ns.Trainers.MergeAccess(e.fac, l.fac) end
            e.extra = e.extra or {}
            Spots(l.spots, e.extra, source == "curated")
            e.points = nil
            Services(e, l)
        elseif note then
            note.late.npcs[id] = l
        end
    end
    for id, l in Each(T(st.objects)) do
        Tick(2)
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
        elseif note then
            note.late.objects[id] = l
        end
    end
    for id, l in Each(st.quests or {}) do
        Tick(2)
        local q = DB.quests[id]
        if not q and l.title then
            q = { kind = "quest", id = id, name = l.title, key = Geo.Squash(l.title), startU = NO_IDS, startO = NO_IDS, endU = NO_IDS, endO = NO_IDS, objU = NO_IDS, objO = NO_IDS, objI = NO_IDS }
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
                    q[field .. "U"], q[field .. "O"] = us[1] and us or NO_IDS, os[1] and os or NO_IDS
                end
            end
            link(l.giver, "start")
            link(l.ender, "end")
            if l.area then
                q.area = { m = l.area[1], x = l.area[2], y = l.area[3] }
            end
            for kind, rid in table.concat(l.needs or {}, ","):gmatch("([IUO])(%d+)") do
                AddId(q, kind == "I" and "objI" or kind == "U" and "objU" or "objO", tonumber(rid))
            end
            if l.fac and not q.race then
                q.fac = l.fac
            end
        elseif note then
            note.late.quests[id] = l
        end
    end
    for id, l in Each(T(st.items)) do
        Tick()
        local e = DB.items[id]
        if not e and type(l) == "table" and l.name then
            e = { kind = "item", id = id, name = l.name, key = Geo.Squash(l.name), dropU = NO_IDS, dropO = NO_IDS, soldBy = NO_IDS }
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
                    AddId(e, kind == "U" and "dropU" or "dropO", rid)
                end
            end
            for ref in pairs(T(l.sold)) do
                local rid = tonumber(tostring(ref):match("^U(%d+)$"))
                if rid then
                    AddId(e, "soldBy", rid)
                end
            end
        elseif note then
            note.late.items[id] = l
        end
    end
    -- quest objectives the game listed, by name: link them to what they are
    local byName
    for id, l in Each(st.quests or {}) do
        Tick(0.2)
        local q = DB.quests[id]
        if q and l.objs then
            byName = byName or NameIndex()
            for _, obj in ipairs(l.objs) do
                local kind, name = obj:match("^(%a+):(.+)$")
                local key = name and Geo.Squash(name)
                if kind == "item" and byName.items[key] then
                    AddId(q, "objI", byName.items[key].id)
                elseif kind == "monster" and byName.units[key] then
                    AddId(q, "objU", byName.units[key].id)
                elseif kind == "object" and byName.objects[key] then
                    AddId(q, "objO", byName.objects[key].id)
                end
            end
        end
    end
    -- corrections: the wrong spot goes, the right one comes
    for key, list in Each(T(st.fixes)) do
        Tick()
        local kind, id = tostring(key):match("^([NO])(%d+)$")
        local e = kind and (kind == "N" and DB.units or DB.objects)[tonumber(id)]
        -- A roster-only identity may have no raw/observed entry yet. Keep its
        -- corrections so a later fallback cannot resurrect a rejected spot.
        if kind and not e then
            local tbl = kind == "N" and DB.units or DB.objects
            e = { kind = kind == "N" and "npc" or "object", id = tonumber(id), name = "", key = "", learned = source }
            tbl[tonumber(id)] = e
        end
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

-- ---------------------------------------------------------------------------
-- The shipped stores, kept as what a merge needs of them
-- ---------------------------------------------------------------------------
-- Every merge starts again from the shipped rows: it takes out what the
-- last one added (spots, corrections, service rows, mailboxes) and adds the
-- curated store, the community store and your discoveries, in that order,
-- so yours win over the community's and the community's over the curated.
-- The two shipped stores never change, and nearly everything they do is
-- done for good by their first merge (names, levels, factions, links to
-- items: all only added, or only set where nothing was). What a later
-- merge still needs of each is kept here and the store itself let go:
--   * per NPC/object: whether it said hostile or not, its spots, its
--     corrections (all taken out, or written over, by every merge);
--   * per quest: its level, who gives and takes it, its area and faction
--     (which a merge writes whatever was there);
--   * its service rows and mailboxes, in the order it added them.
-- Two kinds of record stay whole, in a small store put in the shipped
-- one's place (DB.curated, DB.community), which MergeStore reads on every
-- merge as it read the whole store:
--   * records that found nothing to add to (an NPC without a name or a
--     spot that the database doesn't have yet), so they still join in once
--     you have seen their NPC;
--   * quests with objectives to match by name: that match depends on the
--     names known at each merge.
-- Records put into that store later, or a store put in its place, are
-- merged the same way (tests do both); a record put in for an ID replaces
-- what is kept here for that ID.
-- The order of a merge is the store's own: its NPCs and objects (spots),
-- its quests, the small store (MergeStore: with the objectives matched by
-- name), then its corrections and mailboxes. Service rows the small store
-- adds are put among the store's others, where the whole store had them.
local baked = {} -- "curated"/"community" -> what Bake kept
local NO_SPOTS = {} -- an NPC/object the store named without a spot (never written)

local function Rows(v)
    return type(v) == "table" and v or {}
end

-- Before a store's first merge: how many spots and corrections its
-- entries have, and how many rows every service has.
local function Count(st)
    local counts = { extra = {}, fixes = {}, rows = {} }
    local function Entry(e)
        if e then
            counts.extra[e], counts.fixes[e] = e.extra and #e.extra or 0, e.fixes and #e.fixes or 0
        end
    end
    for id in pairs(Rows(st.npcs)) do Entry(DB.units[id]) end
    for id in pairs(Rows(st.objects)) do Entry(DB.objects[id]) end
    for key in pairs(Rows(st.fixes)) do
        local kind, id = tostring(key):match("^([NO])(%d+)$")
        Entry(kind and (kind == "N" and DB.units or DB.objects)[tonumber(id)])
    end
    for service, list in pairs(DB.services) do
        counts.rows[service] = #list
    end
    return counts
end

-- After the store's first merge. counts: Count's answer from before it.
local function Bake(st, source, note, counts)
    local late = note.late
    for id, l in pairs(Rows(st.quests)) do
        if type(l) == "table" and l.objs and next(l.objs) ~= nil then
            late.quests[id] = l -- matched by name again at every merge
        end
    end
    local b = {
        proxy = { npcs = late.npcs, objects = late.objects, quests = late.quests, items = late.items,
            mailboxes = {}, fixes = {} },
        ents = {}, -- five a record: entry, hostile (0 unsaid, 1 yes, 2 no), spots, corrected spots, corrections
        quests = {}, -- eight a record: quest, level, startU, startO, endU, endO, area, faction (false: unsaid)
        rows = {}, -- service -> its rows, in order ({ mail = spot } for a mailbox)
        byLetter = note.byLetter,
    }
    local ents, n, slot = b.ents, 0, {}
    local function Entity(e)
        local i = slot[e]
        if not i then
            i, n = n + 1, n + 5
            slot[e] = i
            ents[i], ents[i + 1], ents[i + 2], ents[i + 3], ents[i + 4] = e, 0, false, 0, 0
        end
        return i
    end
    for id, l in pairs(Rows(st.npcs)) do
        Tick(0.3)
        local e = late.npcs[id] == nil and DB.units[id]
        if e then
            local i = Entity(e)
            if l.hostile ~= nil then
                ents[i + 1] = l.hostile and 1 or 2
            end
            ents[i + 2] = NO_SPOTS
        end
    end
    for id in pairs(Rows(st.objects)) do
        local e = late.objects[id] == nil and DB.objects[id]
        if e then
            ents[Entity(e) + 2] = NO_SPOTS
        end
    end
    -- corrections: how many, and how many with a right spot (the last of the entry's new spots)
    for key, list in pairs(Rows(st.fixes)) do
        local kind, id = tostring(key):match("^([NO])(%d+)$")
        local e = kind and (kind == "N" and DB.units or DB.objects)[tonumber(id)]
        if e then
            local i = Entity(e)
            for _, fix in ipairs(Rows(list)) do
                ents[i + 4] = ents[i + 4] + 1
                if fix.right then
                    ents[i + 3] = ents[i + 3] + 1
                end
            end
        end
    end
    for i = 1, n, 5 do
        Tick(0.3)
        local e = ents[i]
        local extra, fixes = e.extra, e.fixes
        local total, from = extra and #extra or 0, counts.extra[e] or 0
        local right, fixed = ents[i + 3], false
        local last = total - right -- of the store's own spots
        if ents[i + 2] and last > from then
            local spots = {}
            for k = from + 1, last do
                spots[#spots + 1] = extra[k]
            end
            ents[i + 2] = spots
        end
        if right > 0 then
            fixed = {}
            for k = last + 1, total do
                fixed[#fixed + 1] = extra[k]
            end
        end
        ents[i + 3] = fixed
        local kept = false
        if ents[i + 4] > 0 then
            kept = {}
            for k = (counts.fixes[e] or 0) + 1, #fixes do
                kept[#kept + 1] = fixes[k]
            end
        end
        ents[i + 4] = kept
    end
    local quests, qn = b.quests, 0
    for id, l in pairs(Rows(st.quests)) do
        Tick(0.3)
        local q = late.quests[id] == nil and DB.quests[id]
        if q then
            local level = tonumber(l.level)
            local giver = type(l.giver) == "string" and l.giver:find("[UO]%d") ~= nil
            local ender = type(l.ender) == "string" and l.ender:find("[UO]%d") ~= nil
            local fac = l.fac and not q.race and l.fac
            if level or giver or ender or l.area or fac then
                quests[qn + 1], quests[qn + 2] = q, level or false
                quests[qn + 3], quests[qn + 4] = giver and q.startU or false, giver and q.startO or false
                quests[qn + 5], quests[qn + 6] = ender and q.endU or false, ender and q.endO or false
                quests[qn + 7], quests[qn + 8] = l.area and q.area or false, fac or false
                qn = qn + 8
            end
        end
    end
    for service, list in pairs(DB.services) do
        local from = counts.rows[service] or 0
        if #list > from then
            local rows = {}
            for k = from + 1, #list do
                local row = list[k]
                rows[#rows + 1] = (row.entry and row.entry.id < 0) and { mail = row.entry.points[1] } or row
            end
            b.rows[service] = rows
        end
    end
    -- Records that wait for their entry: once it is there, their service
    -- rows go where the whole store would have put them, among its others.
    -- For that, where each NPC and object came in the store's own order.
    if next(late.npcs) ~= nil or next(late.objects) ~= nil then
        local seq, at = {}, 0
        for id in pairs(Rows(st.npcs)) do
            at = at + 1
            seq[id] = at
        end
        seq.npcs = at
        for id in pairs(Rows(st.objects)) do
            at = at + 1
            seq[-id] = at
        end
        b.seq = seq
    end
    baked[source] = b
    DB[source] = b.proxy
end

-- The service rows a store added in this merge (after the first `from[service]`
-- of each list), put in the store's own order: `seq` as Bake kept it. Rows
-- of records put into the store later come after its NPCs, or its objects.
local function InStoreOrder(seq, from)
    for service, list in pairs(DB.services) do
        local first, last = (from[service] or 0) + 1, #list
        local sorted, before = true, 0
        local keys
        for i = first, last do
            local id = list[i].id
            local key = id and (seq[id] or (id > 0 and seq.npcs + 0.5 or math.huge)) or math.huge
            if key < before then
                sorted = false
            end
            before = key
            keys = keys or {}
            keys[i - first + 1] = key
        end
        if not sorted then
            local order = {}
            for i = 1, last - first + 1 do
                order[i] = i
            end
            table.sort(order, function(a, c)
                if keys[a] ~= keys[c] then
                    return keys[a] < keys[c]
                end
                return a < c
            end)
            local rows = {}
            for i = 1, #order do
                rows[i] = list[first + order[i] - 1]
            end
            for i = 1, #rows do
                list[first + i - 1] = rows[i]
            end
        end
    end
end

-- What Bake kept of a shipped store, added again as MergeStore added it:
-- its NPCs, objects, quests and service rows (Replay), and after the small
-- store's own merge its corrections and mailboxes (ReplayLast).
local function Replay(b)
    local proxy = b.proxy
    local npcs, objects, quests = Rows(proxy.npcs), Rows(proxy.objects), Rows(proxy.quests)
    local ents = b.ents
    for i = 1, #ents, 5 do
        local e = ents[i]
        -- (a record put into the store for this ID stands in for the shipped one)
        if (e.kind == "npc" and npcs or objects)[e.id] == nil then
            local hostile, spots = ents[i + 1], ents[i + 2]
            if hostile ~= 0 then
                e.hostile = hostile == 1
            end
            if spots then
                local extra = e.extra
                if not extra then
                    extra = {}
                    e.extra = extra
                end
                for k = 1, #spots do
                    extra[#extra + 1] = spots[k]
                end
                e.points = nil
            end
        end
    end
    local list = b.quests
    for i = 1, #list, 8 do
        local q = list[i]
        if quests[q.id] == nil then
            if list[i + 1] then q.level = list[i + 1] end
            if list[i + 2] then q.startU, q.startO = list[i + 2], list[i + 3] end
            if list[i + 4] then q.endU, q.endO = list[i + 4], list[i + 5] end
            if list[i + 6] then q.area = list[i + 6] end
            if list[i + 7] and not q.race then q.fac = list[i + 7] end
        end
    end
    local letter, byLetter = MyLetter(), b.byLetter
    for service, rows in pairs(b.rows) do
        local into = DB.services[service]
        if not into then
            into = {}
            DB.services[service] = into
        end
        for k = 1, #rows do
            local row = rows[k]
            local id = row.id
            if not row.mail and not (id and ((id > 0 and npcs[id] ~= nil) or (id < 0 and objects[-id] ~= nil))) then
                if byLetter[row] then
                    row.fac = letter
                end
                into[#into + 1] = row
            end
        end
    end
end

local function ReplayLast(b, source)
    local fixes = Rows(b.proxy.fixes)
    local ents = b.ents
    for i = 1, #ents, 5 do
        local e = ents[i]
        local kept = ents[i + 4]
        if kept and fixes[(e.kind == "npc" and "N" or "O") .. e.id] == nil then
            local list = e.fixes
            if not list then
                list = {}
                e.fixes = list
            end
            for k = 1, #kept do
                list[#list + 1] = kept[k]
            end
            local fixed = ents[i + 3]
            if fixed then
                local extra = e.extra
                if not extra then
                    extra = {}
                    e.extra = extra
                end
                for k = 1, #fixed do
                    extra[#extra + 1] = fixed[k]
                end
            end
            e.points = nil
        end
    end
    for service, rows in pairs(b.rows) do
        local into
        for k = 1, #rows do
            local row = rows[k]
            if row.mail then
                into = into or DB.services[service]
                local e = { kind = "object", id = nextSpotID, name = L.SERVICE_MAILBOX, key = Geo.Squash(L.SERVICE_MAILBOX), fac = "", points = { row.mail }, learned = source }
                DB.objects[nextSpotID] = e
                into[#into + 1] = { entry = e, fac = "" }
                nextSpotID = nextSpotID - 1
            end
        end
    end
end

-- (Re)adds discoveries. Safe to call again after learning more.
Merge = function(deferCompaction)
    -- drop what a previous merge added, then add everything again
    for _, tbl in ipairs({ DB.units, DB.objects }) do
        for id, e in pairs(tbl) do
            if e.extra or e.fixes then
                e.extra, e.fixes, e.points = nil, nil, nil
            end
            if id < 0 then
                tbl[id] = nil
            end
            Tick(0.1)
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
    local titles = ns.Learn and ns.Learn.QuestTitles and ns.Learn.QuestTitles(true)
    for id, title in pairs(titles or {}) do
        local q = DB.quests[id]
        if not q then
            q = { kind = "quest", id = id, startU = NO_IDS, startO = NO_IDS, endU = NO_IDS, endO = NO_IDS, objU = NO_IDS, objO = NO_IDS, objI = NO_IDS, learned = "game" }
            DB.quests[id] = q
        end
        if q.learned == "game" and q.name ~= title then
            q.name, q.key, q.words = title, Geo.Squash(title), nil
        end
    end
    local bake = bakeNext
    bakeNext = false
    if bake then
        baked = {}
    end
    for _, source in ipairs({ "curated", "community" }) do
        local st, b = DB[source], baked[source]
        if bake and type(st) == "table" then
            -- the store's first merge, whole; then only what is needed of it is kept
            local counts = Count(st)
            local note = { late = { npcs = {}, objects = {}, quests = {}, items = {} }, byLetter = {} }
            MergeStore(st, source, note)
            Bake(st, source, note, counts)
        elseif b and st == b.proxy then
            local from
            if b.seq then
                from = {}
                for service, list in pairs(DB.services) do
                    from[service] = #list
                end
            end
            Replay(b)
            MergeStore(st, source)
            if from then
                InStoreOrder(b.seq, from)
            end
            ReplayLast(b, source)
        else
            baked[source] = nil -- another store was put in its place
            MergeStore(st, source)
        end
    end
    local learned = ns.Learn and ns.Learn.Store(true)
    MergeStore(learned, "you")
    -- keep only what adds to the database in your saved discoveries
    if learned and ns.Learn.Compact and not deferCompaction then
        ns.Learn.Compact(true)
    end
    -- mark what was added so the next merge can take it out again
    for service, list in pairs(DB.services) do
        for i = (before[service] or 0) + 1, #list do
            list[i].learned = true
        end
    end
    DB.generation = DB.generation + 1
end

function DB.MergeLearned(deferCompaction)
    if not DB.ready then
        return
    end
    Merge(deferCompaction)
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
        ns.Call(DB.MergeLearned, true)
    end
end

-- ---------------------------------------------------------------------------
-- Zones: the database uses the game's area IDs; turn them into map IDs by
-- name (both in the client's language), so they match WoW Forever's maps.
-- ---------------------------------------------------------------------------
local areaMap = {}
function DB.MapForArea(area, treeOnly)
    local cached = areaMap[area]
    if cached then
        return cached
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
    local function Match(zones, key)
        local best
        for _, z in ipairs(zones) do
            if z.key == key and (not best or (z.mapType == 3 and best.mapType ~= 3)) then best = z end
        end
        return best and best.id
    end
    -- Service spawns usually resolve in the native tree. Keep the exhaustive
    -- catalogue fallback for orphaned/phased maps absent from that tree.
    local zones, found = Geo.GetZoneList(true), false
    for _, name in ipairs(names) do
        local key = Geo.Squash(name)
        found = Match(zones, key)
        if not found and not treeOnly then
            zones = Geo.GetZoneList()
            found = Match(zones, key)
        end
        if found then break end
    end
    if found or not treeOnly then areaMap[area] = found end
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
    if e.classicCoords ~= e.coords then e.classic = nil end
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
    for m, list in pairs(e.classic or ClassicPoints(e)) do
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

local FlightAliases

-- Does something you discovered add to what the database knows? Sharing
-- leaves out what it already has. kind "npc"/"object" (value: your entry),
-- "drop"/"sold" (id: the item, value: "U123"/"O45").
function DB.AddsSomething(kind, id, value, cachedOnly)
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
    if type(value) ~= "table" then return true end
    -- Service text alone cannot reconstruct a Find identity on next login.
    if not e then return true end
    -- Tickers resolve through the native tree only; unavailable areas retry.
    for area in (e.coords or ""):gmatch("(%d+):") do
        if not DB.MapForArea(tonumber(area), cachedOnly) then return true, true end
    end
    e.ship = e.ship or DB.Snapshot(e, false)
    local ship = SupplementFacts(e.ship, kind, id)
    if ship.fresh or ship.findFresh then
        return true
    end
    if (value.name and (ship.name == "" or (#ship.supplement > 0 and value.name ~= ship.name)))
        or (value.title and not ship.title) then
        return true
    end
    -- Find infers enemies from an empty faction. Service/roster evidence can
    -- still offer that NPC, so an explicit hostile sighting must survive.
    local serviceHostility, trainers
    if kind == "npc" and value.hostile and ship.hostile == nil then
        trainers = ns.Trainers.Index(DB.generation)
        serviceHostility = next(ship.services) or (type(value.services) == "table" and next(value.services))
            or trainers.members[id]
    end
    if kind == "npc" and value.hostile ~= nil and ship.enemy ~= nil and (value.hostile ~= ship.enemy or serviceHostility) then
        return true
    end
    if kind == "npc" and value.fac then
        for letter in value.fac:gmatch("[AH]") do
            if not (ship.fac or ""):find(letter, 1, true) then return true end
        end
    end
    for service in pairs(type(value.services) == "table" and value.services or {}) do
        if not ship.services[service] then return true end
        if (ns.Trainers.IsService(service) or ship.access[service]) and value.fac then
            local known = ship.access[service] or ""
            for letter in value.fac:gmatch("[AH]") do
                if not known:find(letter, 1, true) then return true end
            end
        end
    end
    local spots = type(value.spots) == "table" and value.spots or {}
    if not next(spots) then
        return false
    end
    -- Raw-only identities have no alternative consumer positions. Compare
    -- the changed maps directly instead of allocating a second spawn list.
    if kind == "npc" then trainers = trainers or ns.Trainers.Index(DB.generation) end
    local location = trainers and trainers.positions[id]
    if location then
        for _, pending in pairs(trainers.pending) do
            for i = 1, #pending, 2 do
                if pending[i] == id then return true, true end
            end
        end
    end
    if ship.spots == 0 and not e.world and not e.fixes and #ship.supplement == 0
        and not (location and location.observed) then
        local classic = e.classicCoords == e.coords and e.classic or ClassicPoints(e)
        e.classic, e.classicCoords = classic, e.coords
        for m, list in pairs(spots) do
            local known = classic[m] or EMPTY
            for i = 1, #list - 1, 2 do
                local x, y, found = ns.Num(list[i]), ns.Num(list[i + 1]), false
                for _, p in ipairs(known) do
                    if x and y and math.abs(p.x - x) <= NEAR_KNOWN and math.abs(p.y - y) <= NEAR_KNOWN then found = true; break end
                end
                if not found then return true end
            end
            if #known <= MOVED_NPC_SPOTS then
                for _, p in ipairs(known) do
                    local found = false
                    for i = 1, #list - 1, 2 do
                        local x, y = ns.Num(list[i]), ns.Num(list[i + 1])
                        if x and y and math.abs(p.x - x) <= NEAR_KNOWN and math.abs(p.y - y) <= NEAR_KNOWN then found = true; break end
                    end
                    if not found then return true end
                end
            end
        end
        if not location or next(classic) then return false end
    end
    -- Judge Find against the shipped overlay, before personal spots suppress
    -- Classic spawns; judge each service against its R/M effective locations.
    local shipped = ship.comparison
    if not shipped or shipped.fixes ~= e.fixes then
        shipped = { coords = e.coords, world = e.world, extra = ship.extra, fixes = e.fixes }
        if e.fixes then
            shipped.extra = {}
            for _, p in ipairs(ship.extra) do shipped.extra[#shipped.extra + 1] = p end
            for i = ship.spots + 1, #(e.extra or EMPTY) do
                local p = e.extra[i]
                if p.fixed then shipped.extra[#shipped.extra + 1] = p end
            end
        end
        shipped.classic = e.classicCoords == e.coords and e.classic or ClassicPoints(shipped)
        shipped.classicCoords = shipped.coords
        e.classic, e.classicCoords = shipped.classic, shipped.coords
        ship.comparison = shipped
    end
    local data = WaypointTrackerData or {}
    local memo = ship.observation
    local same = memo and memo.shipped == shipped and memo.supplement == ship.supplement
        and memo.trainers == data.trainers and memo.locations == data.trainerLocations
    if same then
        for m, list in pairs(spots) do
            local old = memo.spots[m]
            if not old or #old ~= #list then same = false; break end
            for i, n in ipairs(list) do if old[i] ~= n then same = false; break end end
            if not same then break end
        end
        for m in pairs(memo.spots) do if not spots[m] then same = false; break end end
        if same then return memo.adds end
    end
    local function Result(adds)
        if adds then
            memo = { shipped = shipped, supplement = ship.supplement, trainers = data.trainers,
                locations = data.trainerLocations, spots = {}, adds = true }
            for m, list in pairs(spots) do
                local copy = {}; memo.spots[m] = copy
                for i, n in ipairs(list) do copy[i] = n end
            end
            ship.observation = memo
        else
            ship.observation = nil
        end
        return adds
    end
    local observed = { world = e.world, extra = {}, fixes = e.fixes }
    for _, p in ipairs(shipped.extra) do observed.extra[#observed.extra + 1] = p end
    Spots(spots, observed.extra)
    local points = not e.world and not e.fixes and observed.extra or DB.Points(observed)
    local function Has(list, point, tolerance)
        for _, p in ipairs(list) do
            if p.m == point.m and math.abs(p.x - point.x) <= tolerance and math.abs(p.y - point.y) <= tolerance then return true end
        end
        return false
    end
    local function Changes(other)
        local tolerance = 0.000500001 -- half of Learn's 0.001 coordinate step
        local observedSet, otherSet = {}, {}
        for _, p in ipairs(points) do observedSet[p] = true end
        for _, p in ipairs(other) do
            if not observedSet[p] and not Has(points, p, tolerance) then return true end
            otherSet[p] = true
        end
        for _, p in ipairs(points) do
            -- Shared Classic/curated point objects cannot have changed.
            if not otherSet[p] and not Has(other, p, tolerance) then return true end
        end
        return false
    end
    -- Unaffected Classic spawns share their point objects. Only additions
    -- and the one/two static spawns suppressed on observed maps can differ.
    local normal
    if next(shipped.extra) or e.world or e.fixes then normal = DB.Points(shipped) end
    local function Known(p, tolerance)
        return Has(normal or shipped.classic[p.m] or EMPTY, p, tolerance)
    end
    for _, p in ipairs(points) do
        if not Known(p, NEAR_KNOWN) then return Result(true) end
    end
    for m, list in pairs(shipped.classic) do
        if spots[m] and #list <= MOVED_NPC_SPOTS then
            for _, p in ipairs(list) do
                if Known(p, 1e-9) and not Has(points, p, NEAR_KNOWN) then return Result(true) end
            end
        end
    end
    local function AllPoints()
        if not observed.classic then
            observed.classic, observed.points = shipped.classic, nil
            points = DB.Points(observed)
        end
    end
    for _, row in ipairs(ship.supplement) do
        if kind == "npc" and not e.fixes and not e.hostile
            and ("," .. row.services .. ","):find(",flight,", 1, true) then
            -- Presence of a passive spot also suppresses nearby taxi labels.
            if next(FlightAliases(row)) then return Result(true) end
            if row.aliasGeneration ~= DB.generation then return true, true end
        end
        if #row.spots > 0 then
            AllPoints()
            local effective = {}
            for _, p in ipairs(row.spots) do effective[#effective + 1] = p end
            for _, p in ipairs(DB.Points(shipped)) do
                if row.mode == "M" or p.fixed then effective[#effective + 1] = p end
            end
            -- An observation selects the normal Find points instead of the
            -- supplement wrapper. Retain it if either result would change.
            local candidate = { extra = effective, fixes = e.fixes }
            -- Learn rounds coordinates to 0.001; a canonical service spot
            -- within its half-step adds no measurable discovery precision.
            if Changes(DB.Points(candidate)) then return Result(true) end
        end
    end
    -- A passive spot also disables the trainer roster's observed-position
    -- override, even when no trainer service was learned at the window.
    if kind == "npc" then
        if location and (location.observed or #DB.Points(shipped) == 0) then
            AllPoints()
            local fallback = { extra = {}, fixes = e.fixes }
            for _, p in ipairs(location.points) do fallback.extra[#fallback.extra + 1] = p end
            for _, p in ipairs(shipped.extra) do
                if p.fixed then fallback.extra[#fallback.extra + 1] = p end
            end
            if Changes(DB.Points(fallback)) then return Result(true) end
        end
    end
    return Result(false)
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
    local f = ns.Str(UnitFactionGroup and UnitFactionGroup("player"))
    if f == "Horde" then
        return "H", HORDE_RACES
    elseif f == "Alliance" then
        return "A", ALLIANCE_RACES
    end
end

-- False for NPCs/objects only friendly to the other faction, and quests
-- only the other faction can do.
local function ForFaction(e, letter, races)
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

function DB.ForMyFaction(e)
    return ForFaction(e, MyFaction())
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
    -- the player's faction, asked once for the search (not once an entry)
    local myLetter, myRaces
    if opts.faction then
        myLetter, myRaces = MyFaction()
    end

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
        if opts.faction and not ForFaction(e, myLetter, myRaces) then
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
        -- the player's faction, asked once for the scan (not once an entry)
        local myLetter, myRaces
        if opts.faction then
            myLetter, myRaces = MyFaction()
        end
        local function look(tbl, want)
            for _, e in pairs(tbl or {}) do
                if want(e) and (not opts.faction or ForFaction(e, myLetter, myRaces)) and MaybeOn(e, m, areas) then
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
        local level = UnitLevel and ns.Num(UnitLevel("player")) or 1
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
local nearestWorld = setmetatable({}, { __mode = "k" })
function DB.NearestOf(entries, opts)
    local bestE, bestP, bestD, fallbackE, fallbackP
    local players = {}
    local letter, races = MyFaction()
    for _, e in ipairs(entries) do
        if not (opts and opts.faction) or ForFaction(e, letter, races) then
            local pts = DB.Points(e)
            for _, p in ipairs(pts) do
                -- Fixed targets convert once; player position is sampled once
                -- per continent for this click (including phased fallback).
                local w = nearestWorld[p]
                if not w or w[1] ~= p.m or w[2] ~= p.x or w[3] ~= p.y then
                    local c, x, y = Geo.MapToWorld(p.m, p.x, p.y)
                    w = c and { p.m, p.x, p.y, c, x, y } or nil
                    nearestWorld[p] = w
                end
                if w then
                    local player = players[w[4]]
                    if player == nil then
                        local c, x, y = Geo.GetPlayerWorld(w[4])
                        player = c == w[4] and { x, y } or false
                        players[w[4]] = player
                    end
                    if player then
                        local dx, dy = w[5] - player[1], w[6] - player[2]
                        local d = dx * dx + dy * dy
                        if not bestD or d < bestD then bestE, bestP, bestD = e, p, d end
                    end
                end
                if not fallbackE then fallbackE, fallbackP = e, p end
            end
        end
    end
    if bestE then
        return bestE, bestP, math.sqrt(bestD)
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
local function ServiceCandidate(row, access)
    if row.generation == DB.generation and row.access == access then return row.entry end
    local base = (row.kind == "npc" and DB.units or DB.objects)[row.id]
    local store = WaypointTrackerDB and WaypointTrackerDB.learned
    local own = type(store) == "table" and (row.kind == "npc" and store.npcs or store.objects)
    own = type(own) == "table" and own[row.id]
    own = type(own) == "table" and own
    -- Personal and imported observations retain normal discovery precedence.
    if base and own and next(own.spots or {}) then
        row.entry = base
        if base.fac ~= access then
            local e = {}
            for key, value in pairs(base) do e[key] = value end
            e.fac = access
            row.entry = e
        end
    else
        local e = { kind = row.kind, id = row.id, fac = access,
            name = base and base.name ~= "" and base.name or row.name,
            learned = "community", minedService = true, extra = {}, fixes = base and base.fixes }
        e.key = Geo.Squash(e.name)
        local pending = false
        for _, p in ipairs(row.spots) do
            -- Keep unsupported/phased metadata from placing an observation on
            -- a different continent; existing resolved positions can fall back.
            local c, x, y = Geo.MapToWorld(p.m, p.x, p.y, p)
            if c == p.c then
                e.extra[#e.extra + 1] = p
                nearestWorld[p] = { p.m, p.x, p.y, c, x, y }
            elseif c == nil then
                pending = true
            end
        end
        if base then
            local merge = row.mode == "M" or #e.extra == 0
            for _, p in ipairs(DB.Points(base)) do
                if merge or p.fixed then e.extra[#e.extra + 1] = p end
            end
        end
        if not e.fixes then e.points = e.extra end
        -- A transient map failure must retry without an unrelated merge.
        if pending then return e end
        row.entry = e
    end
    row.generation, row.access = DB.generation, access
    return row.entry
end

-- Client taxi labels describe the same stop as a nearby observed flight NPC.
-- Associate using the shipped point, before applying movement/removal fixes.
FlightAliases = function(row)
    if row.aliasGeneration == DB.generation then return row.aliases end
    local aliases, pending = {}, false
    for _, p in ipairs(row.spots) do
        local c, x, y = Geo.MapToWorld(p.m, p.x, p.y)
        if not c then pending = true end
        if c == p.c then
            for _, s in ipairs(DB.services.flight or {}) do
                local e = s.entry
                for _, w in ipairs(e and e.world or {}) do
                    if w[1] == c and (w[3] - x)^2 + (w[4] - y)^2 <= 100^2 then aliases[e] = true end
                end
            end
        end
    end
    if not pending then row.aliases, row.aliasGeneration = aliases, DB.generation end
    return aliases
end

function DB.ServiceEntries(service)
    local letter = MyFaction()
    local out, replaced, seen, aliases = {}, {}, {}, {}
    local rows = ServiceRows(service)
    if rows.generation ~= DB.generation then
        local access = {}
        for _, s in ipairs(DB.services[service] or {}) do
            if s.id and s.learned then
                local fac = s.observedAccess or s.fac
                access[s.id] = ns.Trainers.MergeAccess(access[s.id], fac)
            end
        end
        for _, row in ipairs(rows) do
            local id = row.kind == "object" and -row.id or row.id
            row.allowed = ns.Trainers.MergeAccess(row.fac, access[id]) or ""
        end
        rows.generation, rows.entries = DB.generation, {}
    end
    local cached = rows.entries[letter or ""]
    if cached then return cached end
    local pending = false
    local learned = WaypointTrackerDB and WaypointTrackerDB.learned
    for _, row in ipairs(rows) do
        local id = row.kind == "object" and -row.id or row.id
        replaced[id] = true
        local base = (row.kind == "npc" and DB.units or DB.objects)[row.id]
        local personal = service == "flight" and learned and learned.npcs and learned.npcs[row.id]
        if service == "flight" and base and (base.fixes or base.hostile or (personal and next(personal.spots or {}))) then
            for e in pairs(FlightAliases(row)) do aliases[e] = true end
            if row.aliasGeneration ~= DB.generation then pending = true end
        end
        local fac = row.allowed
        if (not base or not base.hostile) and (not letter or fac:find(letter, 1, true)) then
            local e = ServiceCandidate(row, fac)
            if row.generation ~= DB.generation then pending = true end
            if e and not seen[e] then out[#out + 1], seen[e] = e, true end
        end
    end
    for _, s in ipairs(DB.services[service] or {}) do
        if not replaced[s.id] and (s.fac == "" or not letter or s.fac:find(letter, 1, true)) then
            local e = s.entry or (s.id < 0 and DB.objects[-s.id]) or DB.units[s.id]
            if e and not e.hostile and not aliases[e] and not seen[e] then
                out[#out + 1], seen[e] = e, true
            end
        end
    end
    if not pending then rows.entries[letter or ""] = out end
    return out
end

-- Keep the tiny roster as text, resolving identities only on a user request.
-- Supplemental/learned NPCs need not occur in raw Data.lua units. Unknown
-- trainer factions fail closed, regardless of Find's general faction toggle.
function DB.TrainerEntries(service)
    local out, seen = {}, {}
    if not (ns.Trainers.services[service] or ns.Trainers.additionalServices[service]) then return out end
    local letter = MyFaction()
    if not letter then return out end
    local index = ns.Trainers.Index(DB.generation)
    local learned = WaypointTrackerDB and WaypointTrackerDB.learned
    learned = learned and learned.npcs
    local function Add(id, fac, e)
        if fac and fac ~= "" and fac:find(letter, 1, true) and not seen[id] then
            e = e or DB.units[id]
            -- Trainer availability is stricter than general Find (which also
            -- searches enemies). Resolved observations override roster access.
            if e and e.hostile then return end
            local location = index.positions[id]
            local personal = learned and learned[id]
            -- Newest pinned observations replace older shipped coordinates.
            -- Personal/imported positions retain the existing merge semantics.
            local observed = location and location.observed and not (personal and personal.spots and next(personal.spots))
            if observed or not e or #DB.Points(e) == 0 then
                if location then
                    local cached = index.entries[id]
                    if not cached or cached.fac ~= fac then
                        -- Existing/localized names and corrections still win.
                        local name = e and e.name ~= "" and e.name or (GetLocale() == "enUS" and ns.CleanText(location.name) or "")
                        local points = {}
                        for _, p in ipairs(location.points) do points[#points + 1] = p end
                        -- A correction's replacement is already a resolved point.
                        for _, p in ipairs(e and e.extra or {}) do
                            if p.fixed then points[#points + 1] = p end
                        end
                        cached = { kind = "npc", id = id, fac = fac, name = name,
                            extra = points, fixes = e and e.fixes }
                        index.entries[id] = cached
                    end
                    e = cached
                end
            end
            if e and #DB.Points(e) > 0 then
                seen[id], out[#out + 1] = true, e
            end
        end
    end
    for _, row in ipairs(index.services[service] or {}) do
        Add(row.id, row.fac)
    end
    for _, row in ipairs(DB.services[service] or {}) do
        Add(row.id, row.fac, row.entry)
    end
    return out
end

-- Set the arrow on something from the database. Returns the waypoint.
function DB.GoTo(e, p, title, silent)
    if not e or not p then
        return nil
    end
    return ns.WP.Add(p.m, p.x, p.y, { title = title or e.name, source = "find", silent = silent })
end
