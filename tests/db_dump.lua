-- Helper for tests/run_db_equivalence.lua (not a test by itself): builds the
-- Find database one way and writes everything in it, entry by entry and
-- field by field, then replays a history of personal discoveries, imports
-- and replaced stores, writing what each merge changed.
--     [WT_LOCALE=xx] [WT_SIDE=Horde] lua5.1 tests/db_dump.lua MODE OUTFILE
-- MODE: sync      DB.Load(), all at once
--       sliced    DB.LoadAsync(), a slice a frame (forced on: the mock has no frame clock)
--       clocked   DB.LoadAsync() with a frame clock, as in the game: slices by time
--       reference the 1.4.2 loader (tests/fixtures/loader-1.4.2: Database.lua,
--                 Learn.lua and Core.lua as released), all at once
-- Two runs that write the same file built the same database.
package.path = "./tests/?.lua;" .. package.path
local mode, outPath = arg[1], arg[2]
assert(mode == "sync" or mode == "sliced" or mode == "clocked" or mode == "reference",
    "usage: db_dump.lua sync|sliced|clocked|reference OUTFILE")
local M = require("wowmock")
local out = assert(io.open(assert(outPath, "no output file"), "w"))

-- the player's faction (WT_SIDE=Horde for the other one), which a merge
-- writes into the service rows of NPCs seen without one
local HOME = os.getenv("WT_SIDE") == "Horde" and "Horde" or "Alliance"
local AWAY = HOME == "Horde" and "Alliance" or "Horde"
local side = HOME
function UnitFactionGroup() return side end
function UnitLevel() return 30 end

-- The addon, with the released loader's files in place of today's for "reference"
local REFERENCE = { ["Database.lua"] = true, ["Learn.lua"] = true, ["Core.lua"] = true }
local function LoadAddon()
    local ns, dir, name = {}, "WaypointTracker", "WaypointTracker"
    local toc = assert(io.open(dir .. "/" .. name .. ".toc")):read("*a")
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^##") and line:match("%S") then
            local file = line:gsub("\\", "/"):gsub("%s+$", "")
            if file:match("%.lua$") then
                local path = dir .. "/" .. file
                if mode == "reference" and REFERENCE[file] then path = "tests/fixtures/loader-1.4.2/" .. file end
                assert(loadfile(path))(name, ns)
            end
        end
    end
    return ns
end

-- IDs to play with, from the shipped stores' own text (the same in every mode)
local function StoreIDs(file)
    local text = assert(io.open("WaypointTracker_Data/" .. file)):read("*a")
    local ids = { N = {}, O = {}, Q = {}, I = {}, giver = {}, service = {}, plain = {}, area = {}, level = {} }
    for line in text:gmatch("[^\r\n]+") do
        local kind, id, rest = line:match("^([NOQI])\t(%d+)\t(.*)$")
        if kind then
            id = tonumber(id)
            ids[kind][#ids[kind] + 1] = id
            local f = {}
            for field in (rest .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
            if kind == "Q" and (f[3] or "") ~= "" then ids.giver[#ids.giver + 1] = id end
            if kind == "Q" and (f[3] or "") == "" and (f[5] or "") ~= "" then ids.area[#ids.area + 1] = id end
            if kind == "Q" and (f[3] or "") == "" and (f[2] or "") ~= "" then ids.level[#ids.level + 1] = id end
            if kind == "N" and (f[4] or "") ~= "" then ids.service[#ids.service + 1] = id end
            if kind == "N" and (f[4] or "") == "" and (f[5] or "") ~= "" then ids.plain[#ids.plain + 1] = id end
        end
    end
    for _, list in pairs(ids) do table.sort(list) end
    return ids
end
local curated, community = StoreIDs("Curated.lua"), StoreIDs("Forever.lua")

local ns = LoadAddon()
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
local DB, Learn = ns.DB, ns.Learn
ns.settings.learn = false -- no background learning between the slices of a load

-- ---------------------------------------------------------------------------
-- Writing a value down: lists in their order, other keys sorted, entries of
-- the database by reference
-- ---------------------------------------------------------------------------
local isEntry = {}
local function Num(v)
    if v ~= v then return "nan" end
    if v == math.floor(v) and math.abs(v) < 1e15 then return ("%d"):format(v) end
    return ("%.14g"):format(v)
end
local function Mixed(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
end
local function Ser(v, depth, seen)
    local t = type(v)
    if t == "number" then return Num(v) end
    if t == "string" then return ("%q"):format(v) end
    if t == "boolean" or t == "nil" then return tostring(v) end
    if t ~= "table" then return "<" .. t .. ">" end
    if depth > 0 and isEntry[v] then return "<" .. tostring(v.kind) .. ":" .. tostring(v.id) .. ">" end
    if seen[v] then return "<again>" end
    if depth > 8 then return "<deep>" end
    seen[v] = true
    local parts, n, keys, strings = {}, #v, nil, true
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
            keys = keys or {}
            keys[#keys + 1] = k
            if type(k) ~= "string" then strings = false end
        end
    end
    for i = 1, n do
        parts[i] = i .. "=" .. Ser(v[i], depth + 1, seen)
    end
    if keys then
        if strings then table.sort(keys) else table.sort(keys, Mixed) end
        for _, k in ipairs(keys) do
            local key = type(k) == "table" and Ser(k, depth + 1, seen) or (type(k) == "number" and Num(k) or tostring(k))
            parts[#parts + 1] = key .. "=" .. Ser(v[k], depth + 1, seen)
        end
    end
    seen[v] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Everything in the database as key -> text.
-- `watch`: of the items only these (a merge in between only ever adds to an
-- item's lists; every item is written at the load and at the end).
-- `unordered`: the rows of a service in any order. Once a record has been
-- put into a shipped store after the load (only tests do), where its row
-- lands among the store's others was the hash order of the whole store,
-- which is no longer kept.
local TABLES = { "units", "objects", "quests", "items", "places" }
local function Snapshot(watch, unordered)
    isEntry = {}
    for _, name in ipairs(TABLES) do
        for _, e in pairs(DB[name]) do isEntry[e] = true end
    end
    local all = {}
    -- what Find's buttons would offer: the nearest services and trainers
    -- (first: asking works out and keeps an entry's points, which are written below)
    local services = {}
    for service in pairs(DB.services) do services[#services + 1] = service end
    for service in pairs(ns.Trainers.services) do services[#services + 1] = service end
    table.sort(services)
    for _, service in ipairs(services) do
        local ids = {}
        local trainer = ns.Trainers.services[service]
        for i, e in ipairs(trainer and DB.TrainerEntries(service) or DB.ServiceEntries(service)) do
            ids[i] = tostring(e.id) .. "/" .. #DB.Points(e)
        end
        if unordered then table.sort(ids) end -- (they come in their rows' order)
        all["offer " .. service] = table.concat(ids, " ")
    end
    for _, name in ipairs(TABLES) do
        for id, e in pairs(DB[name]) do
            if name ~= "items" or not watch or watch[id] then
                all[("%s %012d"):format(name, id + 500000000)] = Ser(e, 0, {})
            end
        end
    end
    for service, list in pairs(DB.services) do
        if unordered then
            local rows = {}
            for i, row in ipairs(list) do rows[i] = Ser(row, 1, {}) end
            table.sort(rows)
            all["service " .. service] = table.concat(rows, ";")
        else
            all["service " .. service] = Ser(list, 0, {})
        end
    end
    for q, marks in pairs(DB.marks) do
        all[("marks %012d"):format(q)] = Ser(marks, 0, {})
    end
    all["zoneNames"] = Ser(DB.zoneNames or false, 0, {})
    all["foreverQuests"] = Ser(DB.foreverQuests or false, 0, {})
    all["state"] = Ser({ loaded = DB.loaded, ready = DB.ready, hasShipped = DB.hasShipped }, 0, {})
    all["personal"] = Ser(WaypointTrackerDB.learned or false, 0, {})
    return all
end

local previous = {}
local function Stage(name, watch, unordered)
    local all = Snapshot(watch, unordered)
    local keys = {}
    for k, v in pairs(all) do
        if previous[k] ~= v then keys[#keys + 1] = k end
    end
    for k in pairs(previous) do
        if all[k] == nil and not (watch and k:find("^items ")) then keys[#keys + 1] = k end
    end
    if watch then
        -- the items not written this time are as they were
        for k, v in pairs(previous) do
            if all[k] == nil and k:find("^items ") then all[k] = v end
        end
    end
    table.sort(keys)
    out:write(("== %s: %d changed\n"):format(name, #keys))
    for _, k in ipairs(keys) do
        out:write(name, " ", k, " ", all[k] or "<gone>", "\n")
    end
    previous = all
end

-- ---------------------------------------------------------------------------
-- The personal discoveries the database is loaded with
-- ---------------------------------------------------------------------------
local own1, own2, own3 = curated.plain[1], curated.plain[2], curated.plain[3]
local theirs1 = community.N[1]
local questA, questB, questC = curated.giver[1], curated.giver[2], curated.giver[3]
local questArea, questLevel = curated.area[1], community.level[1] -- a curated quest with an area, a community quest with a level
local theirs2 = community.plain[1] ~= theirs1 and community.plain[1] or community.plain[2] -- a community NPC with spots
local theirs3 = community.service[1] ~= theirs1 and community.service[1] or community.service[2] -- and one with a service
local NEW_NPC, NEW_ITEM, NEW_QUEST = 990001, 990101, 990201
assert(own3 and theirs1 and theirs2 and theirs3 and questC and questArea and questLevel and curated.O[1] and curated.I[1], "the shipped stores have the records this history plays with")

-- The shipped stores with more in them than they hold today, so that every
-- part of a merge is compared: corrections (with and without a right
-- spot, for an NPC both stores correct), a mailbox in the curated store,
-- records without a name or a spot for NPCs the database only gets from
-- you (they join in at the merge after yours, and from then on), and a
-- quest whose objectives are matched by name with what you found.
do
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    assert(load("WaypointTracker_Data"), "the data addon loads")
    local D = WaypointTrackerData
    D.curated = D.curated .. "\n" .. table.concat({
        ("C\tN\t%d\t37:500,500\t37:510,520"):format(own3),
        ("C\tN\t%d\t37:300,300"):format(own2),
        ("C\tO\t%d\t37:120,130\t37:125,135"):format(curated.O[1]),
        "M\t37:111,222",
        ("N\t%d\t\t1\t33\trepair\t\tH"):format(NEW_NPC),
        ("Q\t%d\t\t44\tU%d\tU%d"):format(NEW_QUEST + 3, NEW_NPC, NEW_NPC),
    }, "\n")
    D.forever = D.forever .. "\n" .. table.concat({
        ("C\tN\t%d\t37:520,530\t37:525,535"):format(own3),
        ("C\tN\t%d\t37:455,400"):format(theirs1),
        ("N\t%d\t\t0\t\tvendor"):format(NEW_NPC + 2),
        ("N\t%d\t\t0\t12\tinnkeeper\t\tA"):format(NEW_NPC),
        -- objectives named after things the database only gets from you
        ("Q\t%d\tA shared quest with objectives\t\t\t\t\t\titem:An item of yours|monster:Learned later"):format(NEW_QUEST + 4),
    }, "\n")
end
WaypointTrackerDB.questTitles = { locale = GetLocale(), names = { [NEW_QUEST] = "A quest the game named" } }
local personal = {
    npcs = {
        [own1] = { name = "Renamed by the game", hostile = true, level = 61, spots = { [37] = { 0.411, 0.322 } } },
        [theirs1] = { name = "An imported name", shared = true, spots = { [37] = { 0.52, 0.53 } } },
        [NEW_NPC] = { name = "Seen only by you", fac = "A", services = { vendor = true, repair = true },
            spots = { [37] = { 0.6, 0.6, 0.61, 0.62 } } },
    },
    objects = { [990301] = { name = "A chest of yours", spots = { [37] = { 0.2, 0.2 } } } },
    quests = {
        [questA] = { title = "Your own title", level = 77, giver = "U" .. NEW_NPC, text = "Text you read.",
            needs = { "U" .. NEW_NPC, "I" .. NEW_ITEM }, objs = { "monster:Seen only by you" } },
        [questB] = { giver = "U" .. NEW_NPC, ender = "U" .. NEW_NPC, shared = true },
    },
    items = {
        [NEW_ITEM] = { name = "An item of yours", from = { ["U" .. NEW_NPC] = true }, sold = { ["U" .. NEW_NPC] = true } },
    },
    mailboxes = { spots = { [37] = { 0.33, 0.34 } } },
    fixes = { ["N" .. own2] = { { wrong = { 37, 0.5, 0.5 }, right = { 37, 0.51, 0.52 } } } },
}

-- A matrix of records in the shipped stores' own text (so they are taken
-- apart like the real ones): every pairing of what the curated store, the
-- community store and you say about an NPC's hostility and faction, with
-- services, corrections from each, records without a name or a spot for
-- NPCs only you have seen; and quests whose level, giver, taker, area and
-- faction each of the three sets or leaves alone.
local MATRIX = 997000
do
    local D = WaypointTrackerData
    local cur, com = {}, {}
    local HOSTILE, FACTION, SERVICE = { "", "1", "0" }, { "", "A", "H", "AH" }, { "vendor", "trainer_weapon", "innkeeper" }
    local id = MATRIX
    for ch = 1, 3 do for cf = 1, 4 do for oh = 1, 3 do for of = 1, 4 do
        for s = 1, 3, 2 do
            id = id + 1
            local service = SERVICE[((ch + cf + oh + of + s) % 3) + 1]
            cur[#cur + 1] = ("N\t%d\tCurated %d\t%s\t\t%s\t37:%d,%d\t%s"):format(id, id, HOSTILE[ch], service, 100 + id % 700, 200, FACTION[cf])
            if id % 5 == 0 then
                -- the community store only knows of an NPC that is yours alone
                com[#com + 1] = ("N\t%d\t\t%s\t\t%s\t\t%s"):format(id + 5000, HOSTILE[oh], service, FACTION[of])
                personal.npcs[id + 5000] = { name = "Only yours " .. id, spots = { [37] = { 0.3, 0.3 } } }
            else
                com[#com + 1] = ("N\t%d\tCommunity %d\t%s\t\t%s\t37:%d,%d\t%s"):format(id, id, HOSTILE[oh], service, 300, 100 + id % 700, FACTION[of])
            end
            -- yours: hostile or not, a faction and the service, or a correction of the curated spot
            local k = id % 4
            if k == 1 then
                personal.npcs[id] = { hostile = (id % 8 == 1), spots = { [37] = { 0.41, 0.42 } } }
            elseif k == 2 then
                personal.npcs[id] = { fac = (id % 8 == 2) and "H" or "A", services = { [service] = true } }
            elseif k == 3 then
                personal.fixes["N" .. id] = { { wrong = { 37, (100 + id % 700) / 1000, 0.2 }, right = { 37, 0.55, 0.56 } } }
            end
            -- both stores correct the same NPC
            if id % 6 == 0 then
                cur[#cur + 1] = ("C\tN\t%d\t37:%d,200\t37:610,620"):format(id, 100 + id % 700)
                com[#com + 1] = ("C\tN\t%d\t37:300,%d"):format(id, 100 + id % 700)
            end
        end
    end end end end
    for q = 1, 60 do
        local qid = MATRIX + 20000 + q
        cur[#cur + 1] = ("Q\t%d\tCurated quest %d\t%s\tU%d\tU%d\t%s\t\t\t\t%s"):format(qid, q, q % 3 == 0 and "" or tostring(q),
            MATRIX + q, MATRIX + q + 1, q % 2 == 0 and "37:100,100" or "", q % 4 == 0 and "A" or "")
        if q % 2 == 1 then
            com[#com + 1] = ("Q\t%d\t\t%s\t%s\tO%d\t%s\t\t\t\t%s"):format(qid, q % 5 == 0 and "" or tostring(q + 1),
                q % 3 == 0 and "" or ("U" .. (MATRIX + q + 2)), 4000 + q, q % 4 == 1 and "37:200,200" or "", q % 4 == 3 and "H" or "")
        end
        if q % 3 == 1 then
            personal.quests[qid] = { level = 70 + q, giver = q % 2 == 0 and ("U" .. (MATRIX + q + 3)) or nil,
                area = q % 5 == 1 and { 37, 0.3, 0.3 } or nil, shared = (q % 6 == 4) or nil }
        end
    end
    D.curated = D.curated .. "\n" .. table.concat(cur, "\n")
    D.forever = D.forever .. "\n" .. table.concat(com, "\n")
end
WaypointTrackerDB.learned = personal

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------
if mode == "sliced" or mode == "clocked" then
    assert(DB.LoadAsync and DB._SetSliced, "this loader cannot be sliced")
    if mode == "clocked" then
        -- a frame clock for the length of the load (every look at it takes
        -- a tenth of a millisecond): the loader finds it and slices by time
        local now = 0
        function debugprofilestop()
            now = now + 0.1
            return now
        end
        assert(DB.Sliced() == true, "a client with a frame clock loads a slice a frame")
    else
        DB._SetSliced(true)
    end
    local answer
    assert(DB.LoadAsync(function(ok, why) answer = { ok, why } end) == nil, "a sliced load answers later")
    assert(not DB.loaded and not DB.ready, "a sliced load is not ready at once")
    local frames, share, held = 0, 0, 0
    while not answer and frames < 100000 do
        M.Tick(1 / 60, 1 / 60)
        frames = frames + 1
        assert(answer or not DB.ready, "the database says ready before its load has finished")
        local now = DB.Loading()
        if now then
            assert(now >= share and now <= 0.99, "the share done only rises, and not to all of it")
            share = now
            if now == 0.99 then held = held + 1 end
        end
    end
    debugprofilestop = nil
    assert(answer and answer[1] == true and answer[2] == nil, "the sliced load finished: " .. tostring(answer and answer[2]))
    assert(frames > 20, "the load was spread over frames (" .. frames .. ")")
    -- in every language the share says about how far the load is: near
    -- the end when it ends, and not held at its last value for long
    local hint = ": when the shipped data has changed, set EXPECTED_UNITS and EXPECTED_UNITS_OTHER in Database.lua"
        .. " to a little over the rows a load reads (tests/run_db_sliced.lua prints them)"
    assert(share > 0.9, "the share done is near the end when the load ends (" .. share .. ")" .. hint)
    -- (this history's own records are a tenth more to read than is shipped)
    assert(held <= frames * 0.1, "the share done does not wait at 99% (" .. held .. " of " .. frames .. " frames)" .. hint)
else
    local ok, why = DB.Load()
    assert(ok == true and why == nil, "the database loaded: " .. tostring(why))
end
Stage("load")

-- Merged again with nothing new (the first use after a load, when
-- something had been learned before it). Not nothing: the mailboxes get
-- new numbers, and shipped records that waited for something only you
-- have found (it is in the database from your first merge on) join in.
ns.Fire("LEARNED")
assert(DB.Load() == true)
Stage("again")

-- ---------------------------------------------------------------------------
-- A history of merges
-- ---------------------------------------------------------------------------
local WATCH = { [NEW_ITEM] = true, [NEW_ITEM + 1] = true, [curated.I[1]] = true }
local unordered = false
local function Merge(name, last)
    DB.MergeLearned()
    Stage(name, not last and WATCH or nil, unordered)
end
local st = Learn.Store()

-- more discoveries, and another faction
st.npcs[own1] = { name = "Renamed again", hostile = false, title = "A title you saw", spots = { [37] = { 0.7, 0.71 } } }
st.npcs[own3] = { hostile = true, fac = "H" }
st.quests[questC] = { giver = "O990301", ender = "U" .. NEW_NPC, area = { 37, 0.4, 0.4 }, level = 12, fac = "H" }
st.items[curated.I[1]] = { from = { ["O990301"] = true } }
st.quests[questArea] = { area = { 37, 0.1, 0.1 }, level = 3, fac = "H", giver = "U" .. NEW_NPC }
st.quests[questLevel] = { area = { 37, 0.2, 0.2 }, level = 9, ender = "O990301" }
-- the matrix: some of yours go, hostile turns friendly and back, half your corrections go
for id, l in pairs(st.npcs) do
    if id > MATRIX then
        if id % 3 == 0 then
            st.npcs[id] = nil
        elseif l.hostile ~= nil then
            l.hostile = not l.hostile
        end
    end
end
for key in pairs(st.fixes) do
    local id = tonumber(key:sub(2))
    if id > MATRIX and id % 2 == 0 then st.fixes[key] = nil end
end
side = AWAY
Merge("more")

-- taken back: what the shipped stores say must show again where they say anything
st.npcs[own1], st.npcs[own3] = nil, nil
st.quests[questA], st.quests[questC] = nil, nil
st.quests[questArea], st.quests[questLevel] = nil, nil
for id in pairs(st.quests) do
    if id > MATRIX and id % 2 == 0 then st.quests[id] = nil end
end
for id in pairs(st.npcs) do
    if id > MATRIX then st.npcs[id] = nil end
end
st.fixes = {}
st.mailboxes = {}
WaypointTrackerDB.questTitles.names[NEW_QUEST + 1] = "Another the game named"
side = HOME
Merge("taken back")

-- an import from another player
Learn.Import(table.concat({
    "WTL1\ttest\t1",
    ("N\t%d\tA shared sighting\t0\t40\tvendor\t37:455,466\tA\tShared title"):format(NEW_NPC + 1),
    ("N\t%d\tA shared name for a curated NPC\t1\t\t\t37:300,310"):format(own2),
    ("Q\t%d\tA shared quest\t33\tU%d\tU%d\t37:400,410\tShared text\t\tU%d\tA"):format(NEW_QUEST + 2, NEW_NPC + 1, NEW_NPC, NEW_NPC),
    ("Q\t%d\t\t\tU%d\tU%d"):format(questB, NEW_NPC + 1, NEW_NPC + 1),
    ("I\t%d\tA shared item\tU%d\tU%d"):format(NEW_ITEM + 1, NEW_NPC, NEW_NPC + 1),
    "M\t37:801,802",
    ("C\tN\t%d\t37:455,466\t37:460,470"):format(theirs1),
}, "\n"))
Merge("import")

-- the way DB.Load merges after something was learned
st.npcs[NEW_NPC + 2] = { name = "Learned later", spots = { [37] = { 0.11, 0.12 } } }
ns.Fire("LEARNED")
assert(DB.Load() == true)
Stage("learned", WATCH)

-- records added to the shipped community store (as tests do)
DB.community.npcs[NEW_NPC + 3] = { name = "Added to the community store", hostile = false, level = 60,
    fac = "A", services = { vendor = true }, spots = { [37] = { 0.25, 0.26 } } }
DB.community.quests[questA] = { level = 5, giver = "U" .. (NEW_NPC + 3), fac = "A" }
-- and records put in for IDs it has: they stand in for the shipped ones
DB.community.npcs[theirs2] = { level = 5 }
DB.community.npcs[theirs3] = { level = 6 } -- (no longer with its service)
DB.community.quests[questLevel] = { area = { 37, 0.5, 0.5 } }
st.quests[questLevel] = { level = 9 }
unordered = true
Merge("community record")
st.quests[questLevel] = nil
Merge("community record kept")

-- stores put in the shipped ones' place (as tests do)
DB.curated = { npcs = { [own1] = { hostile = true, spots = { [37] = { 0.9, 0.9 } } } }, objects = {}, quests = {}, items = {},
    mailboxes = { spots = { [37] = { 0.15, 0.16 } } }, fixes = {} }
Merge("curated replaced")
DB.community = { npcs = {}, objects = {}, quests = {}, items = {}, mailboxes = {}, fixes = {} }
Merge("community replaced")
DB.curated = nil
Merge("no curated store", true)

out:write("errors ", #M.errors, " ", tostring(M.errors[1]), "\n")
out:close()
