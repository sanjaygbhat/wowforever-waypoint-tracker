-- Named, source-backed missing references remain visible without made-up spots.
package.path = "tests/?.lua;" .. package.path
local M = require("wowmock")
-- This provenance fixture uses English client map names and pfQuest enUS.
-- Parent locale-matrix runs must not translate the zone-name lookup here.
M.locale = "enUS"
-- Client UiMapAssignment build 70338; the default mock omits these maps.
M.maps[1427] = { mapID = 1427, name = "Searing Gorge", cont = 0, top = -6100,
    left = -322.91665649414, w = 2231.24984741206, h = 1487.4995117188,
    mapType = 3, parentMapID = 13 }
M.maps[1428] = { mapID = 1428, name = "Burning Steppes", cont = 0, top = -7031.2495117188,
    left = -266.66665649414, w = 2929.16659545896, h = 1952.0834960937,
    mapType = 3, parentMapID = 13 }
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
assert(ns.DB.Load(), "database must load the reference supplement")
local checked = 0
for _, spec in ipairs({
    { ns.DB.units, 3981, "Vorrel Sengutz" },
    { ns.DB.units, 5588, "[PH] Alliance Mine Guard" },
    { ns.DB.items, 15885, "Pendant of the Sea Lion" },
}) do
    local e = assert(spec[1][spec[2]], "referenced definition missing: " .. spec[2])
    assert(e.name == spec[3], "verified pfQuest name differs: " .. spec[2] .. " " .. tostring(e.name))
    assert(#ns.DB.Points(e) == 0, "reference-only definitions must not invent locations: " .. spec[2])
    checked = checked + 1
end
for _, id in ipairs({ 8924, 9026, 16033 }) do
    assert(#ns.DB.Points(assert(ns.DB.units[id])) > 0, "valid raw fallback lost: " .. id)
    checked = checked + 1
end
for _, spec in ipairs({ { ns.DB.units, 12237 }, { ns.DB.units, 15549 },
    { ns.DB.objects, 124371 }, { ns.DB.objects, 180667 } }) do
    assert(#ns.DB.Points(assert(spec[1][spec[2]])) == 0, "unsupported spot retained: " .. spec[2])
    checked = checked + 1
end
-- Verify every supplied name against the independently extracted source;
-- none of these definitions may acquire fabricated coordinates.
pfDB = { units = {}, objects = {}, items = {} }
for _, kind in ipairs({ "units", "objects", "items" }) do
    dofile("tools/fixtures/reference-pfquest/db/enUS/" .. kind .. ".lua")
end
local source = assert(io.open("WaypointTracker_Data/ReferenceData.lua")):read("*a")
local tables = { N = ns.DB.units, O = ns.DB.objects, I = ns.DB.items }
local names = { N = pfDB.units.enUS, O = pfDB.objects.enUS, I = pfDB.items.enUS }
for kind, id, name in source:gmatch("([NOI])\t(%d+)\t([^\t\n]+)") do
    id = tonumber(id)
    local e = assert(tables[kind][id], "reference missing after database merge: " .. kind .. id)
    assert(name == names[kind][id], "source name differs: " .. kind .. id)
    assert(#ns.DB.Points(e) == 0, "reference supplement supplied an unverified location: " .. kind .. id)
    checked = checked + 1
end
assert(#M.errors == 0, table.concat(M.errors, "\n"))
print(("Reference data: %d checks passed"):format(checked))
