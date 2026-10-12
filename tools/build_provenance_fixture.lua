-- Extract the independent pfQuest records checked by the offline audit.
-- Usage: lua5.1 tools/build_provenance_fixture.lua PFQUEST OUTPUT
-- Source: shagu/pfQuest, commit 104f35678ca39ab1fb78b655f815cc7016f5e0c8.
local PF, OUT = assert(arg[1]), assert(arg[2])
pfDB = { units = {}, objects = {}, quests = {}, items = {} }
for _, kind in ipairs({ "units", "objects", "quests", "items" }) do
    dofile(PF .. "/db/" .. kind .. ".lua")
    dofile(PF .. "/db/enUS/" .. kind .. ".lua")
end
dofile("WaypointTracker_Data/Data.lua")
local function keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end
local function encode(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local out = {}
    for _, k in ipairs(keys(value)) do
        out[#out + 1] = "[" .. encode(k) .. "]=" .. encode(value[k])
    end
    return "{" .. table.concat(out, ",") .. "}"
end
local fields = {
    units = { "fac", "coords" }, objects = { "fac", "coords" },
    quests = { "lvl", "min", "race", "class", "start", "end", "obj" }, items = {},
}
for _, kind in ipairs({ "units", "objects", "quests", "items" }) do
    local data, names = {}, {}
    for id in WaypointTrackerData.raw[kind]:gmatch("%f[%d](%d+)\t[^\n]*") do
        id = tonumber(id)
        local original = pfDB[kind].data[id]
        if original then
            data[id] = {}
            for _, field in ipairs(fields[kind]) do data[id][field] = original[field] end
            local name = pfDB[kind].enUS[id]
            names[id] = kind == "quests" and { T = name.T } or name
        end
    end
    for _, spec in ipairs({ { "/db/", "data", data }, { "/db/enUS/", "enUS", names } }) do
        local f = assert(io.open(OUT .. spec[1] .. kind .. ".lua", "w"))
        f:write("-- pfQuest 104f35678ca39ab1fb78b655f815cc7016f5e0c8 (MIT), selected audit fields.\n")
        f:write("pfDB." .. kind .. "." .. spec[2] .. "=" .. encode(spec[3]) .. "\n")
        f:close()
    end
end
