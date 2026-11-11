-- Dumps Mapzeroth's WoW Forever travel data (MIT, github.com/tr0tsky0/Mapzeroth,
-- branch "rebuild", Data/Forever) to the mz_*.tsv files tools/build_travel.py reads.
-- mz_abilities.tsv (hearthstones, teleport items, speed forms, riding skills and the
-- Frequent Flier perk, for TravelAbilities.lua) was dumped from rebuild commit
-- 1976d4f35e0460fdc587dd8361612a1b98095364; see tools/fixtures/manifest.json.
--     git clone --depth 1 -b rebuild https://github.com/tr0tsky0/Mapzeroth /tmp/mz
--     lua5.1 tools/mapzeroth_dump.lua /tmp/mz/Data/Forever tools/.cache/travel
-- The data files are plain tables; each runs in its own sandbox.
local dir, out = assert(arg[1], "usage: lua5.1 tools/mapzeroth_dump.lua <Data/Forever> <out dir>"), arg[2] or "."
local addon = { RULESET = "forever" }
local files = { "Containers", "PathFactors", "Nodes_EasternKingdoms", "Nodes_Kalimdor", "Nodes_ZephrasIsle",
    "Pois", "Borders", "Blackrock", "Edges", "Abilities", "RidingSkills", "Game" }
for _, f in ipairs(files) do
    local fn = assert(loadfile(dir .. "/" .. f .. ".lua"))
    setfenv(fn, { table = table, ipairs = ipairs, pairs = pairs, math = math, string = string,
        tostring = tostring, tonumber = tonumber, type = type })
    fn("Mapzeroth", addon)
end
local function S(v) if v == nil then return "" end return tostring(v) end
local h = io.open(out .. "/mz_nodes.tsv", "w")
local lists = {}
for k in pairs(addon.Nodes) do lists[#lists + 1] = k end
table.sort(lists)
for _, k in ipairs(lists) do
    for _, n in ipairs(addon.Nodes[k]) do
        local kind = n.kind or n.id:match("^([A-Z]+)_") or ""
        local npc = n.npcs and n.npcs[1] and n.npcs[1].id
        h:write(table.concat({ n.id, kind:lower(), S(n.container), S(n.mapID), S(n.x), S(n.y), S(n.city), S(n.town),
            S(n.faction), S(n.area), S(npc), k }, "\t"), "\n")
    end
end
h:close()
h = io.open(out .. "/mz_edges.tsv", "w")
for _, e in ipairs(addon.Edges) do
    local r = e.requirements or {}
    h:write(table.concat({ e.from, e.to, S(e.method), S(e.cost), S(e.ride), S(e.loadingScreens), e.oneway and "1" or "",
        S(r.faction), S(r.class), S(r.race), S(r.quest) }, "\t"), "\n")
end
h:close()
h = io.open(out .. "/mz_settlements.tsv", "w")
for kind, t in pairs({ city = addon.Cities, town = addon.Towns }) do
    for key, s in pairs(t) do
        h:write(table.concat({ kind, key, S(s.mapID), S(s.x), S(s.y), S(s.taxi), S(s.faction), S(s.area) }, "\t"), "\n")
    end
end
h:close()
h = io.open(out .. "/mz_misc.tsv", "w")
for m, f in pairs(addon.PathFactors) do h:write("factor\t", m, "\t", f, "\n") end
for path, c in pairs(addon.Containers) do h:write("container\t", path, "\t", c.indoor and "indoor" or "", "\n") end
for _, t in ipairs(addon.Abilities.Teleports) do h:write("teleport\t", t.spellID, "\t", t.to, "\t", t.cost, "\n") end
h:close()
-- What players can use to travel faster (TravelAbilities.lua). Kind-tagged rows:
--   hearth  item id, spell id, cast seconds, cooldown seconds (the bound inn; no item: a spell)
--   item    item id, landing node, cast seconds, cooldown seconds, faction (bag items only)
--   form    spell id, speed bonus, indoors too (1 or empty), talent spell id, bonus per talent rank
--   riding  spell id, mounted speed bonus
--   flier   spell id, flight speed bonus
h = io.open(out .. "/mz_abilities.tsv", "w")
local A = addon.Abilities or {}
for _, a in ipairs(A.Hearthstones or {}) do
    h:write(table.concat({ "hearth", S(a.itemID), S(a.spellID), S(a.cost), S(a.cooldown) }, "\t"), "\n")
end
for _, a in ipairs(A.Items or {}) do
    -- Toys sit in the toy box and need their own API; a list of landings is a choice.
    if not a.toy and a.to and not a.toList then
        h:write(table.concat({ "item", S(a.itemID), a.to, S(a.cost), S(a.cooldown), S(a.faction) }, "\t"), "\n")
    end
end
for _, f in ipairs(A.GroundForms or {}) do
    local t = f.talents and f.talents[1]
    h:write(table.concat({ "form", S(f.spellID), S(f.bonus or 0), f.indoorCapable and "1" or "",
        S(t and t.spellID), S(t and t.perRank) }, "\t"), "\n")
end
for _, r in ipairs(addon.RidingSkills or {}) do
    h:write(table.concat({ "riding", S(r.spellID), S(r.bonus) }, "\t"), "\n")
end
if addon.FREQUENT_FLIER then
    h:write(table.concat({ "flier", S(addon.FREQUENT_FLIER.spellID), S(addon.FREQUENT_FLIER.speedBonus) }, "\t"), "\n")
end
h:close()
