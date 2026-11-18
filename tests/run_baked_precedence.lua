-- Precedence with the shipped stores as the loader keeps them. The other
-- precedence suites (run_trainer_precedence, run_service_precedence,
-- run_trainer_index) put fresh tables in DB.curated and DB.community, which
-- are merged whole. Here the same kinds of record are in the shipped
-- stores' own text before the load, so the first merge takes the stores
-- apart (Bake) and every later one adds back what was kept (Replay,
-- ReplayLast, InStoreOrder): yours still win over the community's, and the
-- community's over the curated store's, merge after merge, also once your
-- discoveries are taken back.
--   * trainers: every roster access, observed access and hostility, from
--     each shipped store;
--   * an NPC all three know, with a correction from none or each of them;
--   * corrections of trainers and service NPCs/objects that are only in the
--     roster or the service supplement, from each shipped store;
--   * a vendor's hostility said by a shipped store and by you;
--   * the two shipped stores against each other, and you against both;
--   * a shipped record for an NPC that only you have seen;
--   * a shipped vendor seen without a faction, for a character of each.
-- At the end the stores are read again from the same text and merged whole,
-- as 1.4.2 did: every service's rows must come in the very same order.
-- Run from the repository root: lua5.1 tests/run_baked_precedence.lua
-- (which also runs itself with --sliced, a slice a frame, and --clocked,
-- with a frame clock as in the game)
package.path = "./tests/?.lua;" .. package.path
local mode = arg and arg[1] or "sync"
local M = require("wowmock")
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
local DB, Learn = ns.DB, ns.Learn
ns.Set("realRoutes", false)
ns.settings.learn = false
local passed, failed = 0, 0
local function check(ok, text)
    if ok then passed = passed + 1 else failed = failed + 1; if failed < 40 then print("FAIL (" .. mode .. "): " .. text) end end
end
local side = "Alliance"
UnitFactionGroup = function() return side end
local function has(fac, letter) return fac:find(letter, 1, true) ~= nil end
local mapForArea = DB.MapForArea
DB.MapForArea = function(area) if area == 12 then return 37 end return mapForArea(area) end
local cont = ns.Geo.MapToWorld(37, .5, .5)

-- ---------------------------------------------------------------------------
-- The records, as text in the data addon's tables before the load
-- ---------------------------------------------------------------------------
assert(C_AddOns.LoadAddOn("WaypointTracker_Data"), "the data addon loads")
local D = WaypointTrackerData
local text = { curated = {}, community = {} }
local raw, names, roster, places, supplement = {}, {}, {}, {}, {}
local personal = { npcs = {}, objects = {}, quests = {}, items = {}, mailboxes = {}, fixes = {} }
local HOSTILE = { unknown = "", friendly = "0", hostile = "1" }
local function Npc(source, id, name, hostile, service, spot, fac)
    local list = text[source]
    list[#list + 1] = ("N\t%d\t%s\t%s\t\t%s\t%s\t%s"):format(id, name, hostile, service, spot, fac)
end
local function Fix(source, kind, id, wrong, right)
    local list = text[source]
    list[#list + 1] = ("C\t%s\t%d\t%s%s"):format(kind, id, wrong, right and ("\t" .. right) or "")
end
local id = 994000
local cases = { trainers = {}, layered = {}, rosterOnly = {}, supplementOnly = {}, vendors = {}, stores = {}, late = {}, unsided = {} }

-- 1. trainers: roster access x observed access x hostility, from each shipped store
for _, source in ipairs({ "curated", "community" }) do
    for _, rosterFac in ipairs({ "", "A", "H", "AH" }) do
        for _, observedFac in ipairs({ "", "A", "H", "AH" }) do
            for _, hostility in ipairs({ "unknown", "friendly", "hostile" }) do
                id = id + 1
                Npc(source, id, "Evidence", HOSTILE[hostility], "trainer_weapon", "37:500,500", observedFac)
                roster[#roster + 1] = id .. ":" .. rosterFac
                places[#places + 1] = id .. "\tFallback\t37:0.5,0.5;37:0.8,0.8"
                cases.trainers[#cases.trainers + 1] = { id = id, source = source, roster = rosterFac, observed = observedFac, hostility = hostility }
            end
        end
    end
end

-- 2. an NPC of the shipped rows that the curated store, the community store
-- and you all know, with a correction of the curated spot from none or each
for _, lowerHostile in ipairs({ false, true }) do
    for _, liveHostile in ipairs({ false, true }) do
        for _, correction in ipairs({ "none", "curated", "community", "learned" }) do
            id = id + 1
            raw[#raw + 1] = id .. "\t10\tAH\t\t12:500,500"
            names[#names + 1] = id .. "\tPackaged"
            Npc("curated", id, "Curated", lowerHostile and "1" or "0", "", "37:600,600", "")
            Npc("community", id, "Community", lowerHostile and "1" or "0", "", "37:700,700", "")
            personal.npcs[id] = { name = "Live", hostile = liveHostile, fac = "AH", spots = { [37] = { .8, .8 } } }
            if correction == "learned" then
                personal.fixes["N" .. id] = { { wrong = { 37, .6, .6 } } }
            elseif correction ~= "none" then
                Fix(correction, "N", id, "37:600,600")
            end
            roster[#roster + 1] = id .. ":AH"
            places[#places + 1] = id .. "\tFallback\t37:0.9,0.9"
            cases.layered[#cases.layered + 1] = { id = id, lower = lowerHostile, live = liveHostile, correction = correction }
        end
    end
end

-- 3. corrections of a trainer that is only in the roster
for _, source in ipairs({ "curated", "community" }) do
    for _, replacement in ipairs({ false, true }) do
        id = id + 1
        Fix(source, "N", id, "37:500,500", replacement and "37:900,900" or nil)
        roster[#roster + 1] = id .. ":AH"
        places[#places + 1] = id .. "\tFallback\t37:0.5,0.5"
        cases.rosterOnly[#cases.rosterOnly + 1] = { id = id, source = source, replacement = replacement }
    end
end

-- 4. corrections of a service NPC or object that is only in the supplement
for _, kind in ipairs({ "npc", "object" }) do
    for _, source in ipairs({ "curated", "community" }) do
        for _, replacement in ipairs({ false, true }) do
            id = id + 1
            Fix(source, kind == "npc" and "N" or "O", id, "37:500,500", replacement and "37:900,900" or nil)
            supplement[#supplement + 1] = table.concat({ kind == "npc" and "SN" or "SO", id, "AH", "Only supplement", "vendor", "R", "37:0.5,0.5," .. cont }, "\t")
            cases.supplementOnly[#cases.supplementOnly + 1] = { id = id, kind = kind, source = source, replacement = replacement }
        end
    end
end

-- 5. a vendor whose hostility a shipped store says, and you
for _, source in ipairs({ "curated", "community" }) do
    for _, lowerHostile in ipairs({ false, true }) do
        for _, liveHostile in ipairs({ false, true }) do
            id = id + 1
            Npc(source, id, "Same vendor", lowerHostile and "1" or "0", "vendor", "37:500,500", "A")
            personal.npcs[id] = { name = "Same vendor", fac = "A", hostile = liveHostile, services = { vendor = true }, spots = { [37] = { .5, .5 } } }
            supplement[#supplement + 1] = table.concat({ "SN", id, "A", "Same vendor", "vendor", "R", "37:0.5,0.5," .. cont }, "\t")
            cases.vendors[#cases.vendors + 1] = { id = id, source = source, lower = lowerHostile, live = liveHostile }
        end
    end
end

-- 6. the two shipped stores about one vendor, and you about both
for _, curatedSays in ipairs({ "unknown", "friendly", "hostile" }) do
    for _, communitySays in ipairs({ "unknown", "friendly", "hostile" }) do
        for _, youSay in ipairs({ "nothing", "friendly", "hostile" }) do
            id = id + 1
            Npc("curated", id, "Vendor of both", HOSTILE[curatedSays], "vendor", "37:610,610", "A")
            Npc("community", id, "Vendor of both", HOSTILE[communitySays], "vendor", "37:710,710", "A")
            if youSay ~= "nothing" then
                personal.npcs[id] = { hostile = youSay == "hostile", fac = "A", spots = { [37] = { .81, .81 } } }
            end
            cases.stores[#cases.stores + 1] = { id = id, curated = curatedSays, community = communitySays, you = youSay }
        end
    end
end

-- 7. a shipped record without a name or a spot, for an NPC only you have seen
for _, source in ipairs({ "curated", "community" }) do
    for _, fac in ipairs({ "A", "H" }) do
        id = id + 1
        Npc(source, id, "", "0", "vendor", "", fac)
        personal.npcs[id] = { name = "Only yours", spots = { [37] = { .3, .3 } } }
        cases.late[#cases.late + 1] = { id = id, source = source, fac = fac }
    end
end

-- 8. a shipped vendor seen without a faction: offered to the character's own
for _, source in ipairs({ "curated", "community" }) do
    for _, hostility in ipairs({ "unknown", "friendly", "hostile" }) do
        id = id + 1
        Npc(source, id, "Vendor without a side", HOSTILE[hostility], "vendor", "37:520,520", "")
        cases.unsided[#cases.unsided + 1] = { id = id, source = source, hostility = hostility }
    end
end

D.curated = D.curated .. "\n" .. table.concat(text.curated, "\n")
D.forever = D.forever .. "\n" .. table.concat(text.community, "\n")
local curatedText, communityText = D.curated, D.forever
D.raw.units = D.raw.units .. "\n" .. table.concat(raw, "\n")
D.names_enUS.units = D.names_enUS.units .. "\n" .. table.concat(names, "\n")
D.trainers = "trainer_weapon\t" .. table.concat(roster, ",")
D.trainerLocations = table.concat(places, "\n")
D.serviceSupplement = D.serviceSupplement .. "\n" .. table.concat(supplement, "\n")
WaypointTrackerDB.learned = personal

-- ---------------------------------------------------------------------------
-- The load
-- ---------------------------------------------------------------------------
if mode == "sync" then
    assert(DB.Load() == true, "the database loads")
else
    if mode == "--clocked" then
        local now = 0
        function debugprofilestop() -- every look at it takes a tenth of a millisecond
            now = now + 0.1
            return now
        end
        assert(DB.Sliced() == true, "a client with a frame clock loads a slice a frame")
    else
        DB._SetSliced(true)
    end
    local answer
    assert(DB.LoadAsync(function(ok) answer = ok end) == nil, "a sliced load answers later")
    local frames = 0
    while answer == nil and frames < 100000 do
        M.Tick(1 / 60, 1 / 60)
        frames = frames + 1
    end
    debugprofilestop = nil
    assert(answer == true and frames > 20, "the database loads a slice a frame")
end
-- the stores were taken apart: none of these records is kept whole but the late ones
local whole, kept = 0, 0
for _, source in ipairs({ "curated", "community" }) do
    for _, kind in ipairs({ "npcs", "objects", "quests", "items" }) do
        for _ in pairs(DB[source][kind] or {}) do whole = whole + 1 end
    end
    for _, c in ipairs(cases.late) do
        if c.source == source and DB[source].npcs[c.id] then kept = kept + 1 end
    end
    for _, c in ipairs(cases.trainers) do
        check(DB[source].npcs[c.id] == nil, source .. " record " .. c.id .. " is not kept whole")
    end
    check(next(DB[source].fixes or {}) == nil, source .. " corrections are not kept as a store's")
end
check(whole < 3000 and kept == #cases.late, "only records that wait for something are kept whole (" .. whole .. ", " .. kept .. " of these)")

-- ---------------------------------------------------------------------------
-- What must hold after the load's merge and after every later one
-- ---------------------------------------------------------------------------
local function trainer(id)
    for _, e in ipairs(DB.TrainerEntries("trainer_weapon")) do if e.id == id then return e end end
end
local function vendor(id, kind)
    for _, e in ipairs(DB.ServiceEntries("vendor")) do
        if e.id == id and e.kind == (kind or "npc") and #DB.Points(e) > 0 then return e end
    end
end
local function spots(e)
    local at = {}
    for _, p in ipairs(DB.Points(e)) do at[p.x] = true end
    return at
end

-- `yours`: your discoveries are still there (false: taken back)
local function Verify(when, yours, merges)
    for _, c in ipairs(cases.trainers) do
        for _, faction in ipairs({ "Alliance", "Horde" }) do
            side = faction
            local letter = faction:sub(1, 1)
            local expected = c.hostility ~= "hostile" and (has(c.roster, letter) or has(c.observed, letter))
            local e = trainer(c.id)
            local label = table.concat({ when, c.source, c.roster, c.observed, c.hostility, faction }, "/")
            check((e ~= nil) == expected, label .. " availability")
            if e then check(#DB.Points(e) == 1, label .. " points") end
        end
    end
    side = "Alliance"
    for _, c in ipairs(cases.layered) do
        local label = table.concat({ when, "layered", tostring(c.lower), tostring(c.live), c.correction }, "/")
        local e = trainer(c.id)
        -- yours says hostile or not last; without yours the shipped stores do
        local hostile = c.live
        if not yours then hostile = c.lower end
        check((e ~= nil) == (not hostile), label .. " hostility")
        if e then
            check(e.name == "Live", label .. " your name stays")
            local at = spots(e)
            local corrected = c.correction ~= "none" and (yours or c.correction ~= "learned")
            check(not at[.5] and not at[.9] and at[.7], label .. " curated replaces the shipped row's spot, the community adds its own")
            check((at[.8] == true) == yours, label .. " your spot")
            check((at[.6] == true) == not corrected, label .. " the corrected curated spot")
        end
    end
    for _, c in ipairs(cases.rosterOnly) do
        local e = trainer(c.id)
        check((e ~= nil) == c.replacement, when .. " " .. c.source .. " correction of a roster-only trainer")
        if e then check(DB.Points(e)[1].x == .9, when .. " " .. c.source .. " replacement of a roster-only trainer's spot") end
    end
    for _, c in ipairs(cases.supplementOnly) do
        local e = vendor(c.id, c.kind)
        check((e ~= nil) == c.replacement, when .. " " .. c.kind .. "/" .. c.source .. " correction of a supplement-only service")
        if e then check(DB.Points(e)[1].x == .9, when .. " " .. c.kind .. "/" .. c.source .. " replacement of its spot") end
    end
    for _, c in ipairs(cases.vendors) do
        local hostile = c.live
        if not yours then hostile = c.lower end
        check((vendor(c.id) ~= nil) == (not hostile), table.concat({ when, "vendor", c.source, tostring(c.lower), tostring(c.live) }, "/") .. " hostility")
    end
    for _, c in ipairs(cases.stores) do
        -- the last one that says anything: curated, then the community, then you
        local says = c.curated
        if c.community ~= "unknown" then says = c.community end
        if yours and c.you ~= "nothing" then says = c.you end
        local label = table.concat({ when, "stores", c.curated, c.community, c.you }, "/")
        if not yours and c.you ~= "nothing" and c.community == "unknown" and c.curated == "unknown" then
            -- nobody says any more: what you said last stands until something does
            says = c.you
        end
        local e = vendor(c.id)
        check((e ~= nil) == (says ~= "hostile"), label .. " hostility")
        if e then
            local at = spots(e)
            check(at[.61] and at[.71] and (at[.81] == true) == (yours and c.you ~= "nothing"), label .. " every store's spot")
        end
    end
    for _, c in ipairs(cases.unsided) do
        -- (merged as an Alliance character)
        for _, faction in ipairs({ "Alliance", "Horde" }) do
            side = faction
            check((vendor(c.id) ~= nil) == (c.hostility ~= "hostile" and faction == "Alliance"),
                table.concat({ when, "unsided", c.source, c.hostility, faction }, "/") .. " service")
        end
    end
    for _, c in ipairs(cases.late) do
        for _, faction in ipairs({ "Alliance", "Horde" }) do
            side = faction
            -- it joins in at the merge after the one that brought your NPC,
            -- and is offered while the NPC has a spot: yours
            local expected = yours and merges >= 2 and c.fac == faction:sub(1, 1)
            check((vendor(c.id) ~= nil) == expected, table.concat({ when, "late", c.source, c.fac, faction }, "/") .. " service")
        end
    end
    side = "Alliance"
end

Verify("load", true, 1)
local st = Learn.Store()
for cycle = 2, 4 do
    DB.MergeLearned()
    Verify("merge " .. cycle, true, cycle)
    if cycle == 2 then
        -- what you know that the shipped stores say too is not kept twice
        for _, c in ipairs(cases.vendors) do
            check((st.npcs[c.id] ~= nil) == (c.lower ~= c.live),
                table.concat({ "vendor", c.source, tostring(c.lower), tostring(c.live) }, "/") .. " only a new hostility flag is kept")
        end
    end
end
-- merged as a Horde character, the vendors without a faction are that one's
side = "Horde"
DB.MergeLearned()
for _, c in ipairs(cases.unsided) do
    for _, faction in ipairs({ "Horde", "Alliance" }) do
        side = faction
        check((vendor(c.id) ~= nil) == (c.hostility ~= "hostile" and faction == "Horde"),
            table.concat({ "as Horde", "unsided", c.source, c.hostility, faction }, "/") .. " service")
    end
end
side = "Alliance"
DB.MergeLearned()
Verify("Alliance again", true, 6)
-- every service's rows, in their order
local function Rows()
    local all = {}
    for service, list in pairs(DB.services) do
        local ids = {}
        for i, row in ipairs(list) do
            local p = row.entry and row.entry.points and row.entry.points[1]
            ids[i] = tostring(row.id or (p and ("mail " .. p.m .. " " .. p.x .. " " .. p.y)))
                .. "/" .. tostring(row.fac) .. "/" .. tostring(row.observedAccess)
        end
        all[service] = table.concat(ids, " ")
    end
    return all
end
local function SameRows(a, b)
    local n = 0
    for service, ids in pairs(a) do
        n = n + 1
        if b[service] ~= ids then return false, service end
    end
    for service in pairs(b) do
        if a[service] == nil then return false, service end
    end
    return n > 5
end
do
    local before = Rows()
    DB.MergeLearned()
    local same, where = SameRows(before, Rows())
    check(same, "service rows keep their order from merge to merge: " .. tostring(where))
end
-- your discoveries taken back: the shipped stores say again what they said
WaypointTrackerDB.learned = { npcs = {}, objects = {}, quests = {}, items = {}, mailboxes = {}, fixes = {} }
Learn.Store()
for cycle = 1, 2 do
    DB.MergeLearned()
    Verify("taken back " .. cycle, false, 5 + cycle)
end
-- The stores read again from the same text and merged whole, as 1.4.2
-- merged them: the same rows in the same order (a record that waited for
-- its NPC has its row among its store's others, not after them), and
-- everything above still holds.
do
    local taken = Rows()
    local function Whole(text)
        local store = { npcs = {}, objects = {}, quests = {}, mailboxes = {} }
        Learn.Import(text, store, true)
        return store
    end
    DB.curated, DB.community = Whole(curatedText), Whole(communityText)
    DB.MergeLearned()
    local same, where = SameRows(taken, Rows())
    check(same, "merged whole, every service's rows are the same and in the same order: " .. tostring(where))
    Verify("whole stores", false, 9)
end
check(#M.errors == 0, "no captured Lua errors: " .. tostring(M.errors[1]))
DB.MapForArea = mapForArea

-- the same a slice a frame, and by a frame clock
if mode == "sync" then
    local lua = arg and arg[-1] or "lua5.1"
    for _, other in ipairs({ "--sliced", "--clocked" }) do
        local status = os.execute(("'%s' tests/run_baked_precedence.lua %s"):format(lua:gsub("'", "'\\''"), other))
        check(status == 0 or status == true, "the same holds " .. other)
    end
end
print(("Baked precedence%s: %d passed, %d failed"):format(mode == "sync" and "" or " (" .. mode .. ")", passed, failed))
os.exit(failed == 0 and 0 or 1)
