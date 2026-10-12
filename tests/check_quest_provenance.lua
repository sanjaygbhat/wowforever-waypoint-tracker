-- Independent offline provenance audit against a pinned pfQuest checkout.
-- Run from repo root:
--   lua5.1 tests/check_quest_provenance.lua /path/to/pfQuest [--dump]
-- --dump emits authoritative source spawn points for world-space spot checks.
-- Nothing is downloaded or written; no game APIs or SavedVariables are used.
local PF = arg[1] or "tools/fixtures/pfquest"
local dump = arg[2] == "--dump"
pfDB = { units = {}, objects = {}, quests = {}, items = {} }
for _, kind in ipairs({ "units", "objects", "quests", "items" }) do
    assert(loadfile(PF .. "/db/" .. kind .. ".lua"))()
    assert(loadfile(PF .. "/db/enUS/" .. kind .. ".lua"))()
end
assert(loadfile("WaypointTracker_Data/Data.lua"))()
assert(loadfile("WaypointTracker_Data/Names_enUS.lua"))()
local raw = WaypointTrackerData.raw
local failures, checks, pairsChecked, hubs = 0, 0, 0, {}
local function split(s)
    local out = {}
    for v in (s .. "\t"):gmatch("([^\t]*)\t") do out[#out+1] = v end
    return out
end
local function sorted(t)
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end
    table.sort(keys)
    return keys
end
local function rows(body)
    local out = {}
    for line in body:gmatch("[^\n]+") do
        local f = split(line)
        out[tonumber(f[1])] = f
    end
    return out
end
local function clean(s)
    return tostring(s or ""):gsub("[\r\n\t]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end
local db, names = {}, {}
for _, kind in ipairs({ "units", "objects", "quests", "items" }) do
    db[kind] = rows(raw[kind])
    names[kind] = rows(WaypointTrackerData.names_enUS[kind])
end
-- Locate exact lines in the bundled file, without searching big transcripts.
local sourceText = assert(io.open("WaypointTracker_Data/Data.lua")):read("*a")
local lines, label = {}, nil
local n = 0
for line in (sourceText .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    label = line:match("^%s*(%w+) = %[%=+%[") or label
    local id = tonumber(line:match("^(%d+)\t"))
    if id then lines[label .. ":" .. id] = n end
end
local function check(ok, kind, id, value, why)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print(("FAIL WaypointTracker_Data/Data.lua:%d %s %d value=%s: %s; source %s/db/%s.lua"):
            format(lines[kind .. ":" .. id] or 1, kind, id, tostring(value), why, PF, kind))
    end
end
local function integerList(s)
    local out = {}
    for id in (s or ""):gmatch("%d+") do out[#out+1] = tonumber(id) end
    return out
end
for _, kind in ipairs({ "units", "objects" }) do
    for _, id in ipairs(sorted(db[kind])) do
        local f, original = db[kind][id], pfDB[kind].data[id]
        check(original ~= nil, kind, id, "defined", "ID missing from pfQuest")
        if original then
            local fac = f[kind == "units" and 3 or 2]
            check(fac == (original.fac or ""), kind, id, fac, "friendly faction must be " .. (original.fac or ""))
            check(names[kind][id][2] == clean(pfDB[kind].enUS[id]), kind, id, names[kind][id][2], "English name differs from source")
            local points = {}
            for _, c in ipairs(original.coords or {}) do
                if c[1] and c[2] and c[3] then
                    local key = c[3] .. ":" .. math.floor(c[1]*10+.5) .. "," .. math.floor(c[2]*10+.5)
                    points[key] = true
                    if dump then print(("SOURCE\t%s\t%d\t%d\t%.6f\t%.6f"):format(kind, id, c[3], c[1], c[2])) end
                end
            end
            for area, nums in f[kind == "units" and 5 or 3]:gmatch("(%d+):([%d,]+)") do
                local list = integerList(nums)
                for i = 1, #list-1, 2 do
                    local key = area .. ":" .. list[i] .. "," .. list[i+1]
                    check(points[key], kind, id, key, "map/coordinate pair absent from independently loaded pfQuest source")
                    pairsChecked = pairsChecked + 1
                end
            end
        end
    end
end
local function expectList(src, filter)
    local out = {}
    for _, id in ipairs(src or {}) do
        if not filter or filter[id] then out[#out+1] = tostring(id) end
    end
    return table.concat(out, ",")
end
for _, id in ipairs(sorted(db.quests)) do
    local f, q = db.quests[id], pfDB.quests.data[id]
    check(q ~= nil, "quests", id, "defined", "quest absent from independent pfQuest source")
    if q then
        for _, spec in ipairs({ { 2, "lvl" }, { 3, "min" }, { 4, "race" }, { 5, "class" } }) do
            check(f[spec[1]] == tostring(q[spec[2]] or ""), "quests", id, f[spec[1]], spec[2] .. " must be " .. tostring(q[spec[2]] or ""))
        end
        local specs = { {6,"start","U","units"}, {7,"start","O","objects"}, {8,"end","U","units"},
            {9,"end","O","objects"}, {10,"obj","U","units"}, {11,"obj","O","objects"}, {12,"obj","I"} }
        for _, spec in ipairs(specs) do
            local list = (q[spec[2]] or {})[spec[3]]
            local expected = expectList(list, spec[4] and db[spec[4]])
            check(f[spec[1]] == expected, "quests", id, f[spec[1]], spec[2] .. spec[3] .. " must be " .. expected .. " (only bundled entity IDs retained)")
            if spec[2] == "start" or spec[2] == "end" then
                for _, hub in ipairs(integerList(f[spec[1]])) do hubs[spec[4] .. ":" .. hub] = true end
            end
        end
        local title = pfDB.quests.enUS[id] and pfDB.quests.enUS[id].T
        check(names.quests[id][2] == clean(title), "quests", id, names.quests[id][2], "quest title differs from pfQuest")
    end
end
local hubCount = 0
for _, key in ipairs(sorted(hubs)) do
    local kind, id = key:match("^(%a+):(%d+)$")
    id = tonumber(id)
    hubCount = hubCount + 1
    check(db[kind][id] ~= nil and pfDB[kind].data[id] ~= nil, kind, id, "chain hub", "giver/turn-in missing authoritative location record")
end
-- Reproducible pseudorandom sample: Fisher-Yates with Park-Miller seed 5574949.
-- Every raw record was verified above, so this is also an auditable sample roster.
for _, kind in ipairs({ "units", "objects", "quests" }) do
    local list = sorted(db[kind])
    local seed = 5574949
    for i = #list, 2, -1 do
        seed = (seed*48271)%2147483647
        local j = seed%i+1
        list[i], list[j] = list[j], list[i]
    end
    local sample = {}
    for i = 1, math.min(128,#list) do sample[#sample+1] = list[i] end
    print("SAMPLE " .. kind .. " (128): " .. table.concat(sample, ","))
end
for _, spec in ipairs({ { "units", 4949 }, { "units", 2437 }, { "units", 2359 }, { "quests", 557 } }) do
    local f = db[spec[1]][spec[2]]
    check(f ~= nil, spec[1], spec[2], "critical hub", "required Thrall/Bracers of Binding record missing")
    if f then print("CRITICAL " .. spec[1] .. " " .. spec[2] .. ": " .. table.concat(f, " | ")) end
end
print(("PROVENANCE: %d raw NPCs, %d objects, %d quests; %d coordinate pairs; %d distinct quest-chain giver/turn-in hubs; 384 sampled IDs"):
    format(#sorted(db.units), #sorted(db.objects), #sorted(db.quests), pairsChecked, hubCount))
print(("RESULT: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
