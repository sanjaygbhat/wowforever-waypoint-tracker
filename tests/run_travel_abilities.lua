-- Real routes' travel abilities (TravelAbilities.lua):
-- class teleports, the hearthstone and Astral Recall, teleport items, riding
-- skills, speed forms and Frequent Flier, against the fake WoW API and the
-- shipped network. Run from the repository root:
--     lua5.1 tests/run_travel_abilities.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end

-- The game state these tests control. The mock has none of these APIs.
local known, spellCD, spellDur, bags, itemCD = {}, {}, {}, {}, {}
-- charges left (GetItemCount with includeUses), worn items, and what the
-- game says about using an item (nil: usable, the game's default answer)
local charges, worn, usable = {}, {}, {}
local faction, level = "Alliance", 60
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
local function Book() return { IsSpellKnown = function(id, bank) return bank == 0 and known[id] == true end } end
local function Spell()
    return {
        GetSpellCooldown = function(id)
            local s = spellCD[id]
            return { startTime = s or 0, duration = s and (spellDur[id] or 1800) or 0 }
        end,
        GetSpellName = function(id) return "Spell " .. id end,
    }
end
local function Item()
    return {
        GetItemCount = function(id, _, includeUses)
            if includeUses and charges[id] ~= nil then return charges[id] end
            return bags[id] or 0
        end,
        GetItemCooldown = function(id) local s = itemCD[id]; return s or 0, s and 3600 or 0, 1 end,
        GetItemNameByID = function(id) return "Item " .. id end,
        IsEquippedItem = function(id) return worn[id] == true end,
        IsUsableItem = function(id) return usable[id] ~= false, false end,
    }
end
C_SpellBook, C_Spell, C_Item = Book(), Spell(), Item()
local mockFaction = UnitFactionGroup
function UnitFactionGroup(unit)
    if unit == "player" then return faction end
    return mockFaction(unit)
end
local mockLevel = UnitLevel
function UnitLevel(unit)
    if unit == "player" then return level end
    return mockLevel(unit)
end
local RUNE = 17031 -- Rune of Teleportation, the mage city teleports' reagent

-- A value the client marks secret (restricted in combat), recognised by
-- issecretvalue before the addon loads, as Core.lua captures it then.
local secret = setmetatable({}, { __lt = function() error("secret compared") end, __le = function() error("secret compared") end })
local plainSecret = issecretvalue
function issecretvalue(v) return rawequal(v, secret) or plainSecret(v) end

WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local Travel, A, L = ns.Travel, ns.TravelAbilities, ns.L

-- ---------------------------------------------------------------------------
-- On by default
-- ---------------------------------------------------------------------------
check(ns.Get("realRoutes") == true and Travel.Enabled(), "Real routes is on by default on a fresh profile")
check(ns.Get("travelShare") == false and ns.Get("routeSharing") == false and ns.Get("treasureHunt") == false,
    "walked-path sharing, route sharing and treasure hunt stay opt-in")
check(WaypointTrackerDB.version == 5, "fresh profile is at settings version 5")

-- ---------------------------------------------------------------------------
-- The generated data in TravelData.lua
-- ---------------------------------------------------------------------------
local d = Travel.Data()
local ab = d.abilities
check(ab and #ab.hearths == 2 and ab.hearths[1].item == 6948 and ab.hearths[1].cooldown == 3600
    and ab.hearths[2].spell == 556 and ab.hearths[2].item == nil and ab.hearths[2].cooldown == 900,
    "the hearthstone (item 6948) and Astral Recall (spell 556) are in the generated data")
local forms = {}
for _, f in ipairs(ab and ab.forms or {}) do forms[f.spell] = f end
check(forms[783] and forms[783].bonus == 0.4 and not forms[783].indoor, "Travel Form: +40% outdoors")
check(forms[2645] and forms[2645].bonus == 0.4 and not forms[2645].indoor, "Ghost Wolf: +40% outdoors")
check(forms[5118] and forms[5118].bonus == 0.3 and forms[5118].indoor, "Aspect of the Cheetah: +30%, indoors too")
check(forms[768] and forms[768].talent == 17002 and forms[768].perRank == 0.15 and forms[768].indoor,
    "Cat Form gets +15% per Feral Swiftness rank, indoors too")
check(ab and #ab.riding == 2 and ab.riding[1].spell == 33388 and ab.riding[1].bonus == 0.6
    and ab.riding[2].spell == 33391 and ab.riding[2].bonus == 1, "Apprentice +60% and Journeyman +100% riding")
check(ab and ab.flier and ab.flier.spell == 1225490 and ab.flier.bonus == 0.2, "Frequent Flier: flights 20% faster")
local teleports = {}
for _, t in ipairs(d.teleports) do teleports[t.spell] = t end
local wantTeleports = { [18960] = "TELEPORT_MOONGLADE", [3561] = "CITY_STORMWIND", [3562] = "CITY_IRONFORGE",
    [3565] = "CITY_DARNASSUS", [3563] = "CITY_UNDERCITY", [3566] = "CITY_THUNDER_BLUFF", [3567] = "CITY_ORGRIMMAR" }
for spell, node in pairs(wantTeleports) do
    local t = teleports[spell]
    check(t and t.node.id == node and t.cost == 10, "class teleport " .. spell .. " lands at " .. node .. " after a 10 s cast")
    -- The client's SpellReagents: the six mage city teleports use one Rune of Teleportation; Moonglade nothing.
    if spell == 18960 then
        check(t and t.reagent == nil, "Teleport: Moonglade needs no reagent")
    else
        check(t and t.reagent == RUNE and t.reagents == 1, "class teleport " .. spell .. " needs one Rune of Teleportation")
    end
end
-- Teleport items from the client's item tables (tools/travel_items.tsv).
local items = {}
for _, it in ipairs(ab.items) do items[it.item .. (it.fac or "")] = it end
local ripper, transporter = items["18984"], items["18986"]
local safT, ezThro = items["260820"], items["260819"]
local crumbleH, crumbleA = items["282006Horde"], items["282006Alliance"]
check(#ab.items == 6, "six teleport item rows ship (" .. #ab.items .. ")")
check(ripper and ripper.node.id == "INN_11118" and ripper.ability == 20222 and ripper.skill == 202 and ripper.rank == 260
    and ripper.cooldown == 14400 and ripper.cast == 10 and ripper.misfire and not ripper.equip and not ripper.charges,
    "Dimensional Ripper - Everlook: Everlook, Goblin Engineer, Engineering 260, 4 h cooldown, can misfire")
check(transporter and transporter.node.id == "INN_7733" and transporter.ability == 20219 and transporter.skill == 202
    and transporter.misfire, "Ultrasafe Transporter: Gadgetzan: Gadgetzan, Gnomish Engineer, can misfire")
check(safT and safT.node.id == "INN_11118" and safT.equip and safT.charges and safT.level == 55 and not safT.skill
    and not safT.ability and safT.misfire, "SAF-T Emergency Ripper: Everlook: a worn trinket with charges, level 55, no skill")
check(ezThro and ezThro.node.id == "INN_7733" and ezThro.equip and ezThro.charges and ezThro.level == 55,
    "EZ-Thro Field Transporter: Gadgetzan: a worn trinket with charges, level 55")
check(crumbleH and crumbleH.node.id == "CITY_ORGRIMMAR" and crumbleA and crumbleA.node.id == "CITY_STORMWIND"
    and not crumbleH.misfire and crumbleH.level == 1 and not crumbleH.equip,
    "Crumbling Hearthstone: Orgrimmar for the Horde, Stormwind for the Alliance")

-- ---------------------------------------------------------------------------
-- Class teleports in the planner
-- ---------------------------------------------------------------------------
local function Place(id, dx)
    local n = d.nodes[id]
    return { area = n.area, city = n.city, cont = n.cont0, wx = n.wx0 + (dx or 0), wy = n.wy0, m = n.m, x = n.x, y = n.y }
end
local function Context()
    Travel.Invalidate()
    return Travel._Context()
end
local function Jump(c, kind, field, value)
    for _, j in ipairs(c.jumps) do
        if j.kind == kind and (field == nil or j[field] == value) then return j end
    end
end
local function Uses(path, kind, field, value)
    for i, e in ipairs(path or {}) do
        local how = e.via
        if type(how) == "table" and how.kind == kind and (field == nil or how[field] == value) then return i end
    end
end

-- An Alliance mage in Darkshore heading for the Stormwind flight master.
local auberdine, stormwind = Place("TAXI_26"), Place("TAXI_2")
local c = Context()
check(not Jump(c, "teleport"), "no teleport when the spell isn't known")
local slowPath, slow = Travel.Search(auberdine, stormwind, c)
check(slowPath and not Uses(slowPath, "teleport"), "without the spell the route doesn't teleport")
known[3561] = true
c = Context()
check(not Jump(c, "teleport", "spell", 3561), "a known Teleport: Stormwind without a Rune of Teleportation is not a jump")
local noRune = Travel.Search(auberdine, stormwind, c)
check(noRune and not Uses(noRune, "teleport"), "without the rune the route doesn't teleport")
bags[RUNE] = 1
c = Context()
local j = Jump(c, "teleport", "spell", 3561)
check(j and j.node.id == "CITY_STORMWIND" and j.cost == 20, "a known Teleport: Stormwind is a jump (10 s cast + loading screen)")
local path, total = Travel.Search(auberdine, stormwind, c)
local at = Uses(path, "teleport", "spell", 3561)
check(at and total < slow, ("a known teleport is chosen when it is faster (%s s vs %s s)"):format(tostring(total), tostring(slow)))
check(at and Travel.StepText(path, at, "Goal") == L.TRAVEL_TELEPORT:format("Spell 3561"), "its step says which spell to cast")
-- Not when walking is quicker: the goal is twenty yards away.
path = Travel.Search(stormwind, Place("TAXI_2", 20), c)
check(path and not Uses(path, "teleport"), "a known teleport is not chosen when walking there is quicker")
-- Not on cooldown; the global cooldown doesn't count.
spellCD[3561] = GetTime()
c = Context()
check(not Jump(c, "teleport", "spell", 3561), "a teleport on cooldown is not a jump")
path = Travel.Search(auberdine, stormwind, c)
check(path and not Uses(path, "teleport"), "a teleport on cooldown is not chosen")
spellDur[3561] = 1.5
check(Jump(Context(), "teleport", "spell", 3561), "the global cooldown is not the teleport's cooldown")
spellCD[3561], spellDur[3561] = nil, nil
ns.Set("travelHearth", false)
check(#Context().jumps == 0, "turning off hearthstone and teleports drops every jump")
ns.Set("travelHearth", true)
known[3561] = nil

-- A Horde mage in Undercity heading for Orgrimmar; a druid going to Moonglade.
faction = "Horde"
known[3567] = true
c = Context()
path = Travel.Search(Place("TAXI_11"), Place("TAXI_23"), c)
check(c.faction == "Horde" and Uses(path, "teleport", "spell", 3567), "Teleport: Orgrimmar takes a Horde mage home")
known[3567] = nil
faction = "Alliance"
bags[RUNE] = nil
known[18960] = true
c = Context()
path = Travel.Search(auberdine, Place("TELEPORT_MOONGLADE", 15), c)
check(Uses(path, "teleport", "spell", 18960), "Teleport: Moonglade (no reagent) is chosen for a druid going to Moonglade")
known[18960] = nil

-- The reagent count: a secret, missing or failing answer means no rune.
-- (A secret answer falls back to the last readable count; with nothing
-- remembered it is no rune, so forget the readable counts seen above.)
known[3561] = true
bags[RUNE] = 1
local realCount = C_Item.GetItemCount
C_Item.GetItemCount = function(id) if id == RUNE then return secret end return realCount(id) end
A._Reset()
check(not Jump(Context(), "teleport", "spell", 3561), "a secret reagent count with nothing remembered is not a rune in the bags")
-- the mirror image: a rune count read as 1, then secret, still counts
C_Item.GetItemCount = realCount
check(Jump(Context(), "teleport", "spell", 3561), "a readable rune count of 1: the teleport is a jump")
C_Item.GetItemCount = function(id) if id == RUNE then return secret end return realCount(id) end
check(Jump(Context(), "teleport", "spell", 3561), "remembered as 1, then secret: still counted as a rune in the bags")
C_Item.GetItemCount = function(id) if id == RUNE then error("unavailable") end return realCount(id) end
check(not Jump(Context(), "teleport", "spell", 3561), "a failing reagent count is not a rune in the bags")
local savedItem, savedCount = C_Item, GetItemCount
C_Item, GetItemCount = nil, nil
check(not Jump(Context(), "teleport", "spell", 3561), "no item count API at all: the city teleport is not offered")
known[18960] = true
check(Jump(Context(), "teleport", "spell", 18960), "no item count API: Teleport: Moonglade still is (it needs no reagent)")
known[18960] = nil
GetItemCount = function(id) return bags[id] or 0 end
check(Jump(Context(), "teleport", "spell", 3561), "the legacy GetItemCount answers for the rune when C_Item is missing")
C_Item, GetItemCount = savedItem, savedCount
C_Item.GetItemCount = realCount
known[3561], bags[RUNE] = nil, nil

-- ---------------------------------------------------------------------------
-- The hearthstone and Astral Recall need the item, or the spell
-- ---------------------------------------------------------------------------
local town = d.towns[1]
local realAreaInfo = C_Map.GetAreaInfo
C_Map.GetAreaInfo = function(area)
    if area == town.area then return "Testhaven" end
    return realAreaInfo(area)
end
function GetBindLocation() return "Testhaven" end
c = Context()
check(not Jump(c, "hearth"), "no hearthstone in the bags and no Astral Recall: no hearth jump")
bags[6948] = 1
c = Context()
j = Jump(c, "hearth")
check(j and j.node == town.inn and j.item == 6948 and not j.spell and j.cost == 20, "the hearthstone in the bags goes to the bound inn")
itemCD[6948] = GetTime()
check(not Jump(Context(), "hearth"), "a hearthstone on cooldown is not a jump")
itemCD[6948] = nil
known[556] = true
c = Context()
j = Jump(c, "hearth")
check(j and j.spell == 556 and not j.item, "with both ready, Astral Recall (shorter cooldown) is spent before the hearthstone")
check(Travel.StepText({ { node = auberdine }, { node = town.inn, via = j } }, 2, "Goal") == L.TRAVEL_TELEPORT:format("Spell 556"),
    "an Astral Recall step names the spell")
spellCD[556] = GetTime()
j = Jump(Context(), "hearth")
check(j and j.item == 6948, "Astral Recall on cooldown: the hearthstone is used")
check(Travel.StepText({ { node = auberdine }, { node = town.inn, via = j } }, 2, "Goal") == L.TRAVEL_HEARTH:format("Testhaven"),
    "a hearthstone step names the bound inn")
bags[6948] = 0
check(not Jump(Context(), "hearth"), "both unavailable: no hearth jump")
spellCD[556], known[556] = nil, nil

-- ---------------------------------------------------------------------------
-- Shipped teleport items: owned, off cooldown, worn, skilled, and faster
-- ---------------------------------------------------------------------------
local everlook, gadgetzan = Place("INN_11118"), Place("INN_7733")
local function ItemJump(id, fac, lvl)
    for _, jj in ipairs(A.Jumps(ab, nil, nil, {}, fac or "Alliance", 10, lvl or level)) do
        if jj.kind == "item" and jj.item == id then return jj end
    end
end
-- Dimensional Ripper - Everlook: Engineering 260 and Goblin Engineer.
check(not ItemJump(18984), "Dimensional Ripper not in the bags: no jump")
bags[18984] = 1
check(not ItemJump(18984), "Dimensional Ripper without Goblin Engineer: no jump")
known[20219] = true
check(not ItemJump(18984), "Dimensional Ripper with the other (Gnomish) specialization: no jump")
known[20222] = true
j = ItemJump(18984)
check(j and j.node.id == "INN_11118" and j.cost == 20 and j.misfire, "Dimensional Ripper with Goblin Engineer: an Everlook jump")
usable[18984] = false
check(not ItemJump(18984), "Dimensional Ripper the game says isn't usable (skill too low): no jump")
usable[18984] = nil
local realUsable = C_Item.IsUsableItem
C_Item.IsUsableItem = nil
check(not ItemJump(18984), "no IsUsableItem: the Engineering skill can't be confirmed, no jump")
C_Item.IsUsableItem = function() return secret, false end
A._Reset()
check(not ItemJump(18984), "a secret IsUsableItem answer with nothing remembered: skill unconfirmed, no jump")
-- the mirror image: read as usable, then secret, still usable
C_Item.IsUsableItem = realUsable
check(ItemJump(18984), "IsUsableItem read as usable: the Dimensional Ripper is a jump")
C_Item.IsUsableItem = function() return secret, false end
check(ItemJump(18984), "remembered as usable, then a secret IsUsableItem answer: still a jump")
C_Item.IsUsableItem = function() error("unavailable") end
check(not ItemJump(18984), "a failing IsUsableItem: skill unconfirmed, no jump")
C_Item.IsUsableItem = realUsable
itemCD[18984] = GetTime()
check(not ItemJump(18984), "Dimensional Ripper on cooldown: no jump")
itemCD[18984] = nil
-- In the planner: chosen from the far side of the world, with the misfire note.
c = Context()
check(Jump(c, "item", "item", 18984), "the context offers the Dimensional Ripper")
path = Travel.Search(stormwind, everlook, c)
at = Uses(path, "item", "item", 18984)
check(at and Travel.StepText(path, at, "Goal") == L.TRAVEL_USE_ITEM_MISFIRE:format("Item 18984"),
    "Stormwind to Everlook uses the Dimensional Ripper and says it can misfire")
path = Travel.Search(Place("INN_11118", 30), everlook, c)
check(path and not Uses(path, "item"), "a teleport item is not used when walking there is quicker")
bags[18984] = nil
c = Context()
path = Travel.Search(stormwind, everlook, c)
check(path and not Uses(path, "item"), "without the item the route to Everlook doesn't use it")
-- Ultrasafe Transporter: Gadgetzan wants Gnomish Engineer.
bags[18986] = 1
known[20222] = nil
check(ItemJump(18986) and ItemJump(18986).node.id == "INN_7733", "Ultrasafe Transporter with Gnomish Engineer: a Gadgetzan jump")
known[20219] = nil
check(not ItemJump(18986), "Ultrasafe Transporter without Gnomish Engineer: no jump")
bags[18986] = nil
-- SAF-T Emergency Ripper: a level 55 trinket with charges, no skill needed.
bags[260820], charges[260820] = 1, 3
check(not ItemJump(260820), "the SAF-T Ripper in the bags but not worn: no jump")
worn[260820] = true
j = ItemJump(260820)
check(j and j.node.id == "INN_11118" and j.misfire, "the SAF-T Ripper worn, with charges: an Everlook jump")
charges[260820] = 0
check(not ItemJump(260820), "the SAF-T Ripper with no charges left: no jump")
charges[260820] = 2
usable[260820] = false
check(not ItemJump(260820), "the SAF-T Ripper the game says isn't usable: no jump")
usable[260820] = nil
C_Item.IsUsableItem = nil
check(not ItemJump(260820, "Alliance", 54), "no IsUsableItem and level 54: the level 55 trinket is not a jump")
check(ItemJump(260820, "Alliance", 55), "no IsUsableItem and level 55: the trinket is a jump (no skill to confirm)")
local realWorn = C_Item.IsEquippedItem
C_Item.IsEquippedItem = nil
check(not ItemJump(260820), "no IsEquippedItem: a trinket isn't assumed worn")
C_Item.IsEquippedItem = function() return secret end
A._Reset()
check(not ItemJump(260820), "a secret IsEquippedItem answer with nothing remembered: not worn")
-- the mirror image: read as worn, then secret, still worn
C_Item.IsEquippedItem = realWorn
check(ItemJump(260820), "IsEquippedItem read as worn: the SAF-T Ripper is a jump")
C_Item.IsEquippedItem = function() return secret end
check(ItemJump(260820), "remembered as worn, then a secret IsEquippedItem answer: still a jump")
C_Item.IsEquippedItem, C_Item.IsUsableItem = realWorn, realUsable
itemCD[260820] = GetTime()
check(not ItemJump(260820), "the SAF-T Ripper on cooldown: no jump")
itemCD[260820] = nil
bags[260820], charges[260820], worn[260820] = nil, nil, nil
-- EZ-Thro Field Transporter: Gadgetzan, the same rules.
bags[260819], charges[260819], worn[260819] = 1, 1, true
check(ItemJump(260819) and ItemJump(260819).node.id == "INN_7733", "the EZ-Thro Transporter worn: a Gadgetzan jump")
bags[260819], charges[260819], worn[260819] = nil, nil, nil
-- Crumbling Hearthstone: the client text picks the capital by faction.
bags[282006] = 1
j = ItemJump(282006, "Horde")
check(j and j.node.id == "CITY_ORGRIMMAR" and not j.misfire, "Crumbling Hearthstone takes the Horde to Orgrimmar")
j = ItemJump(282006, "Alliance")
check(j and j.node.id == "CITY_STORMWIND", "Crumbling Hearthstone takes the Alliance to Stormwind")
local n = 0
for _, jj in ipairs(A.Jumps(ab, nil, nil, {}, "Alliance", 10, level)) do if jj.item == 282006 then n = n + 1 end end
check(n == 1, "only the player's own faction's Crumbling Hearthstone landing is offered")
c = Context()
path = Travel.Search(auberdine, stormwind, c)
at = Uses(path, "item", "item", 282006)
check(at and Travel.StepText(path, at, "Goal") == L.TRAVEL_USE_ITEM:format("Item 282006"),
    "the planner uses the Crumbling Hearthstone and says to use it (no misfire note)")
bags[282006] = nil

-- The item row mechanism itself
local itemAb = A.Parse("item\t18986\tCITY_STORMWIND\t10\t14400\tAlliance\nitem\t1\tNO_SUCH_NODE\t10\t0\t", d.nodes)
check(#itemAb.items == 1 and itemAb.items[1].node.id == "CITY_STORMWIND", "item rows resolve their landing; unknown landings are dropped")
check(#A.Jumps(itemAb, nil, nil, {}, "Alliance", 10) == 0, "a teleport item that isn't in the bags is not a jump")
bags[18986] = 1
local jumps = A.Jumps(itemAb, nil, nil, {}, "Alliance", 10)
check(#jumps == 1 and jumps[1].kind == "item" and jumps[1].item == 18986 and jumps[1].cost == 20, "a carried teleport item is a jump")
check(#A.Jumps(itemAb, nil, nil, {}, "Horde", 10) == 0, "a teleport item for the other faction is not a jump")
itemCD[18986] = GetTime()
check(#A.Jumps(itemAb, nil, nil, {}, "Alliance", 10) == 0, "a teleport item on cooldown is not a jump")
itemCD[18986] = nil
c = Context()
c.jumps = A.Jumps(itemAb, nil, nil, {}, "Alliance", 10)
path = Travel.Search(auberdine, stormwind, c)
at = Uses(path, "item", "item", 18986)
check(at and Travel.StepText(path, at, "Goal") == L.TRAVEL_USE_ITEM:format("Item 18986"), "the planner uses a carried teleport item and says to use it")
bags[18986] = nil

-- ---------------------------------------------------------------------------
-- Riding skills, speed forms and Frequent Flier
-- ---------------------------------------------------------------------------
c = Context()
check(c.run == 7 and c.ground == 7 and c.flightFactor == 1, "no riding, forms or perk: run speed everywhere")
known[33388] = true
c = Context()
check(math.abs(c.ground - 11.2) < 1e-9 and c.run == 7, "Apprentice Riding: +60% outdoors, not indoors")
known[33391] = true
c = Context()
check(math.abs(c.ground - 14) < 1e-9, "Journeyman Riding: +100% outdoors")
known[33388], known[33391] = nil, nil
known[783] = true
c = Context()
check(math.abs(c.ground - 9.8) < 1e-9 and c.run == 7, "Travel Form: +40% outdoors only")
known[783] = nil
known[5118] = true
c = Context()
check(math.abs(c.run - 9.1) < 1e-9 and math.abs(c.ground - 9.1) < 1e-9, "Aspect of the Cheetah: +30% indoors and out")
known[5118] = nil
-- Cat Form: the bonus is the Feral Swiftness rank on the talent tree.
local rank = 2
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
C_Traits = {
    GetConfigInfo = function(cfg) return cfg == 7 and { treeIDs = { 70 } } or nil end,
    GetTreeNodes = function(tree) return tree == 70 and { 701, 702 } or {} end,
    GetNodeInfo = function(_, node) return { entryIDs = { node * 10 }, currentRank = node == 702 and rank or 1 } end,
    GetEntryInfo = function(_, entry) return { definitionID = entry + 1 } end,
    GetDefinitionInfo = function(def) return { spellID = def == 7021 and 17002 or 99 } end,
}
known[768] = true
A._Reset()
c = Context()
check(math.abs(c.run - 9.1) < 1e-9, "Cat Form with two ranks of Feral Swiftness: +30% indoors")
rank = 0
A._Reset()
check(Context().run == 7, "Cat Form without the talent is no faster")
C_Traits.GetConfigInfo = function() error("traits unavailable") end
A._Reset()
check(Context().run == 7, "a failing talent API means no talent bonus")
C_Traits, C_ClassTalents = nil, nil
A._Reset()
check(Context().run == 7, "no talent API at all: no talent bonus, no error")
known[768] = nil
-- Spirits use neither a mount nor a form.
known[33391], known[5118] = true, true
M.player.ghost = true
c = Context()
check(c.ghost and c.ground == 7 and c.run == 7, "a ghost is not planned at mounted or form speed")
M.player.ghost = false
known[33391], known[5118] = nil, nil
known[1225490] = true
check(Context().flightFactor == 1 / 1.2, "Frequent Flier makes flights 20% faster")
known[1225490] = nil

-- ---------------------------------------------------------------------------
-- Each ability source degrades gracefully when its API is missing
-- ---------------------------------------------------------------------------
bags[6948], bags[RUNE], known[556], known[3561], known[33391] = 1, 1, true, true, true
local function Try(label)
    local ok, ctx = pcall(Context)
    check(ok, label .. ": no Lua error (" .. tostring(not ok and ctx) .. ")")
    return ok and ctx or { jumps = {}, run = 0, ground = 0 }
end
C_SpellBook = nil
local legacyPlayer, legacyKnown = IsPlayerSpell, IsSpellKnown
IsPlayerSpell, IsSpellKnown = nil, nil
c = Try("no spellbook API")
check(not Jump(c, "teleport") and c.ground == 7 and c.flightFactor == 1 and Jump(c, "hearth", "item", 6948),
    "no spellbook API: no spells known, the hearthstone still works")
IsPlayerSpell = function(id) return known[id] == true end
c = Try("legacy spellbook global")
check(Jump(c, "teleport", "spell", 3561) and math.abs(c.ground - 14) < 1e-9, "the legacy IsPlayerSpell still answers when the modern API is missing")
IsPlayerSpell = function() error("unavailable") end
c = Try("throwing spellbook global")
check(not Jump(c, "teleport"), "a throwing spellbook API means not known")
IsPlayerSpell, IsSpellKnown = legacyPlayer, legacyKnown
C_SpellBook = Book()
C_Spell = nil
local legacyCooldown = GetSpellCooldown
GetSpellCooldown = nil
c = Try("no spell cooldown API")
check(not Jump(c, "teleport") and Jump(c, "hearth", "item", 6948), "no spell cooldown API: spells aren't trusted ready, the hearthstone still is")
GetSpellCooldown = function() return 0, 0 end
c = Try("legacy spell cooldown global")
check(Jump(c, "teleport", "spell", 3561), "the legacy GetSpellCooldown answers when C_Spell is missing")
GetSpellCooldown = legacyCooldown
C_Spell = Spell()
C_Item = { GetItemCount = function(id) return bags[id] or 0 end }
local legacyContainer = C_Container
C_Container = nil
local legacyItemCooldown = GetItemCooldown
GetItemCooldown = nil
c = Try("no item cooldown API")
check(Jump(c, "hearth"), "no item cooldown API: a carried hearthstone counts as ready")
C_Container = { GetItemCooldown = function() return GetTime(), 3600, 1 end }
known[556] = nil
c = Try("container cooldown fallback")
check(not Jump(c, "hearth"), "C_Container.GetItemCooldown is used when C_Item.GetItemCooldown is missing")
C_Container, GetItemCooldown = legacyContainer, legacyItemCooldown
local legacyCount = GetItemCount
C_Item, GetItemCount = nil, nil
c = Try("no item count API")
check(not Jump(c, "hearth"), "no item count API: the hearthstone isn't assumed carried")
C_Item = { GetItemCount = function() error("unavailable") end }
c = Try("throwing item count API")
check(not Jump(c, "hearth"), "a throwing item count API: not carried")
GetItemCount = legacyCount
C_Item = Item()
C_Item.GetItemNameByID = nil
check(A.ItemName(18986) == "#18986", "no item name API: the item's number")
C_Item = Item()
-- Secret cooldowns (in combat) fall back to the last readable answer.
A._Reset()
C_Spell.GetSpellCooldown = function() return { startTime = secret, duration = secret } end
check(not A.SpellReady(3561), "a secret cooldown with nothing remembered is not trusted ready")
local now = GetTime()
C_Spell.GetSpellCooldown = function() return { startTime = now, duration = 60 } end
check(not A.SpellReady(3561), "a readable cooldown is remembered")
C_Spell.GetSpellCooldown = function() return { startTime = secret, duration = secret } end
check(not A.SpellReady(3561), "a secret answer keeps the remembered cooldown")
M.now = M.now + 61
check(A.SpellReady(3561), "once the remembered cooldown is over, a secret answer counts as ready")
C_SpellBook.IsSpellKnown = function() return secret end
check(A.Knows(3561) == false, "a secret spellbook answer with nothing remembered is not known")
-- the mirror image: read as known, then secret, still known
C_SpellBook.IsSpellKnown = Book().IsSpellKnown
check(A.Knows(3561) == true, "a readable spellbook answer: known")
C_SpellBook.IsSpellKnown = function() return secret end
check(A.Knows(3561) == true, "remembered as known, then a secret spellbook answer: still known")
C_Item.GetItemCount = function() return secret end
check(A.ItemCount(6948) == 0, "a secret item count with nothing remembered is not carried")
-- the mirror image: read as 1, then secret, still counted
C_Item.GetItemCount = Item().GetItemCount
check(A.ItemCount(6948) == 1, "a readable item count of 1")
C_Item.GetItemCount = function() return secret end
check(A.ItemCount(6948) == 1, "remembered as 1, then a secret item count: still counted")
C_SpellBook, C_Spell, C_Item = Book(), Spell(), Item()
bags[6948], bags[RUNE], known[556], known[3561], known[33391] = nil, nil, nil, nil, nil

-- ---------------------------------------------------------------------------
-- Combat: what was last read stays true while the game hides it
-- ---------------------------------------------------------------------------
local secretSpellCD = function() return { startTime = secret, duration = secret } end
local secretItemCD = function() return secret, secret, 1 end
-- A cooldown last read as ready stays ready when it turns secret.
A._Reset()
check(A.SpellReady(3561), "a readable ready spell is ready")
C_Spell.GetSpellCooldown = secretSpellCD
check(A.SpellReady(3561), "a spell last read as ready stays ready when its cooldown turns secret")
C_Spell = Spell()
check(A.ItemReady(6948), "a readable ready item is ready")
C_Item.GetItemCooldown = secretItemCD
check(A.ItemReady(6948), "an item last read as ready stays ready when its cooldown turns secret")
C_Item = Item()
-- On cooldown: the secret answer uses the remembered end, then turns ready.
A._Reset()
spellCD[3561], spellDur[3561] = GetTime(), 30
itemCD[6948] = GetTime()
check(not A.SpellReady(3561) and not A.ItemReady(6948), "readable cooldowns are not ready")
C_Spell.GetSpellCooldown, C_Item.GetItemCooldown = secretSpellCD, secretItemCD
check(not A.SpellReady(3561) and not A.ItemReady(6948), "secret cooldowns keep the remembered end time")
M.now = M.now + 31
check(A.SpellReady(3561) and not A.ItemReady(6948), "a remembered spell cooldown that has passed is ready; the item's hour has not")
M.now = M.now + 3600
check(A.ItemReady(6948), "a remembered item cooldown that has passed is ready")
C_Spell, C_Item = Spell(), Item()
spellCD[3561], spellDur[3561], itemCD[6948] = nil, nil, nil
-- Never readable: not ready.
A._Reset()
C_Spell.GetSpellCooldown, C_Item.GetItemCooldown = secretSpellCD, secretItemCD
check(not A.SpellReady(3561) and not A.ItemReady(6948), "a cooldown never readable is not trusted ready")
C_Spell, C_Item = Spell(), Item()
-- A missing answer still only trusts a remembered cooldown end (as before).
A._Reset()
check(A.SpellReady(3561), "ready before the API goes away")
C_Spell.GetSpellCooldown = function() return nil end
check(not A.SpellReady(3561), "a missing (not secret) cooldown answer is not trusted ready")
C_Spell = Spell()
-- The route keeps the hearthstone and the teleport through combat.
A._Reset()
known[3561], bags[RUNE], bags[6948] = true, 1, 1
c = Context()
check(Jump(c, "hearth", "item", 6948) and Jump(c, "teleport", "spell", 3561), "out of combat: hearth and teleport jumps")
C_Spell.GetSpellCooldown, C_Item.GetItemCooldown = secretSpellCD, secretItemCD
c = Context()
check(Jump(c, "hearth", "item", 6948) and Jump(c, "teleport", "spell", 3561),
    "secret cooldowns in combat keep the hearth and teleport jumps")
C_SpellBook.IsSpellKnown = function() return secret end
C_Item.GetItemCount = function() return secret end
c = Context()
check(Jump(c, "hearth", "item", 6948) and Jump(c, "teleport", "spell", 3561),
    "secret spellbook and bag answers in combat keep them too")
C_SpellBook, C_Spell, C_Item = Book(), Spell(), Item()
known[3561], bags[RUNE], bags[6948] = nil, nil, nil
-- Knowledge under secrets.
A._Reset()
known[3561] = true
check(A.Knows(3561), "a readable known spell is known")
C_SpellBook.IsSpellKnown = function() return secret end
check(A.Knows(3561), "a spell last read as known stays known when the answer turns secret")
check(not A.Knows(3562), "a spell never readably known is not known while secret")
C_SpellBook = Book()
known[3561] = nil
check(not A.Knows(3561), "a readable no wins and refreshes the memo")
C_SpellBook.IsSpellKnown = function() return secret end
check(not A.Knows(3561), "a spell last read as unknown stays unknown when the answer turns secret")
C_SpellBook = Book()
known[3561] = true
A.Knows(3561)
A._Reset()
C_SpellBook.IsSpellKnown = function() return secret end
check(not A.Knows(3561), "_Reset forgets what was known")
C_SpellBook = Book()
known[3561] = nil
-- The first API that answers decides (run_travel.lua: modern false is
-- authoritative); a secret answer uses that spell's remembered verdict.
local savedPlayerSpell = IsPlayerSpell
IsPlayerSpell = function(id) return id == 3561 end
check(not A.Knows(3561), "the spellbook says no, IsPlayerSpell yes: the spellbook decides")
C_SpellBook.IsSpellKnown = function() return secret end
check(not A.Knows(3561), "a secret spellbook answer uses the remembered no, not the legacy yes")
C_SpellBook.IsSpellKnown = function() error("unavailable") end
check(A.Knows(3561), "a throwing spellbook: the legacy IsPlayerSpell answers")
IsPlayerSpell = function() return secret end
check(A.Knows(3561), "then a secret legacy answer keeps the remembered yes")
C_SpellBook = Book()
IsPlayerSpell = savedPlayerSpell
-- Bag counts under secrets.
A._Reset()
bags[6948], bags[260820], charges[260820] = 2, 1, 3
check(A.ItemCount(6948) == 2 and A.ItemCount(260820, true) == 3, "readable counts")
C_Item.GetItemCount = function() return secret end
check(A.ItemCount(6948) == 2 and A.ItemCount(260820, true) == 3 and A.ItemCount(260820) == 0,
    "secret counts use the last readable count of the same kind; none read means 0")
C_Item = Item()
bags[6948] = 0
check(A.ItemCount(6948) == 0, "a readable 0 wins")
C_Item.GetItemCount = function() return secret end
check(A.ItemCount(6948) == 0, "and is remembered")
A._Reset()
check(A.ItemCount(260820, true) == 0, "_Reset forgets the counts")
C_Item = Item()
bags[6948], bags[260820], charges[260820] = nil, nil, nil
-- The legacy cooldown global is guarded too.
A._Reset()
local savedLegacyCD = GetSpellCooldown
C_Spell, GetSpellCooldown = nil, function() error("unavailable") end
local okLegacy, legacyReady = pcall(A.SpellReady, 3561)
check(okLegacy and legacyReady == false, "a throwing legacy GetSpellCooldown: not ready, no error")
GetSpellCooldown = savedLegacyCD
C_Spell = Spell()
-- Item names: asked until the game has one, then kept.
A._Reset()
local nameCalls, nameReady = 0, false
C_Item.GetItemNameByID = function(id)
    nameCalls = nameCalls + 1
    if nameReady then return "Item " .. id end
end
check(A.ItemName(18986) == "#18986" and A.ItemName(18986) == "#18986" and nameCalls == 2,
    "no name yet: the number, and the game is asked again")
nameReady = true
check(A.ItemName(18986) == "Item 18986" and nameCalls == 3, "the name once the game has it")
for _ = 1, 10 do A.ItemName(18986) end
check(A.ItemName(18986) == "Item 18986" and nameCalls == 3, "a known name is not asked for again")
A._Reset()
check(A.ItemName(18986) == "Item 18986" and nameCalls == 4, "_Reset forgets item names")
C_Item = Item()
A._Reset()

-- ---------------------------------------------------------------------------
-- What is remembered stays current while no route is planned
-- ---------------------------------------------------------------------------
-- The game's events (cooldowns, bags, spells, equipment, leaving combat)
-- re-read what the planner last asked about, one second later and at most
-- once a second; a secret answer leaves what is remembered as it was.
local refreshes = 0
local realRefresh = A.Refresh
A.Refresh = function()
    refreshes = refreshes + 1
    return realRefresh()
end
local function Peace() C_SpellBook, C_Spell, C_Item = Book(), Spell(), Item() end
local function Combat() -- every answer secret
    C_SpellBook.IsSpellKnown = function() return secret end
    C_Spell.GetSpellCooldown = secretSpellCD
    C_Item.GetItemCount = function() return secret end
    C_Item.GetItemCooldown = secretItemCD
    C_Item.IsEquippedItem = function() return secret end
    C_Item.IsUsableItem = function() return secret, secret end
end
local function Clear()
    for _, t in ipairs({ known, spellCD, spellDur, bags, itemCD, charges, worn, usable }) do
        for k in pairs(t) do t[k] = nil end
    end
    Peace()
    A._Reset()
end

-- The reviewer's case: the hearthstone read as ready while planning; used
-- while no route is planned; two seconds later combat starts and a
-- waypoint is set.
Clear()
bags[6948] = 1
check(Jump(Context(), "hearth", "item", 6948), "planned out of combat: the hearthstone is ready")
M.Tick(5, 0.5)
itemCD[6948] = GetTime() -- used; nothing plans
M.FireEvent("BAG_UPDATE_COOLDOWN")
M.Tick(2, 0.5)
Combat()
check(not Jump(Context(), "hearth"),
    "hearthstone used while nothing was planned (BAG_UPDATE_COOLDOWN), then combat: no hearth jump")
-- Without the event nothing can know: the last read (ready) stands, as documented.
Clear()
bags[6948] = 1
check(Jump(Context(), "hearth", "item", 6948), "planned again: ready")
M.Tick(5, 0.5)
itemCD[6948] = GetTime() -- used, and the game says nothing
M.Tick(2, 0.5)
Combat()
check(Jump(Context(), "hearth", "item", 6948),
    "documented fallback: used with no event and no plan since, in combat the last readable answer (ready) stands")
-- Leaving combat reads it again, so the next combat knows.
Peace()
M.FireEvent("PLAYER_REGEN_ENABLED")
M.Tick(2, 0.5)
Combat()
check(not Jump(Context(), "hearth"), "after PLAYER_REGEN_ENABLED the cooldown was read again: the next combat has no hearth jump")

-- A rune sold, a spell unlearned, a trinket taken off: then combat.
Clear()
known[3561], bags[RUNE] = true, 1
check(Jump(Context(), "teleport", "spell", 3561), "planned: Teleport: Stormwind with a rune in the bags")
bags[RUNE] = 0
M.FireEvent("BAG_UPDATE_DELAYED")
M.Tick(2, 0.5)
Combat()
check(not Jump(Context(), "teleport", "spell", 3561), "rune sold (BAG_UPDATE_DELAYED), then combat: the teleport is not offered")
Clear()
known[3561], bags[RUNE] = true, 1
check(Jump(Context(), "teleport", "spell", 3561), "planned: the teleport again")
known[3561] = nil
M.FireEvent("SPELLS_CHANGED")
M.Tick(2, 0.5)
Combat()
check(not Jump(Context(), "teleport", "spell", 3561), "spell unlearned (SPELLS_CHANGED), then combat: the teleport is not offered")
Clear()
bags[260820], charges[260820], worn[260820] = 1, 2, true
check(ItemJump(260820), "planned: the SAF-T Ripper worn")
worn[260820] = nil
M.FireEvent("PLAYER_EQUIPMENT_CHANGED")
M.Tick(2, 0.5)
Combat()
check(not ItemJump(260820), "trinket taken off (PLAYER_EQUIPMENT_CHANGED), then combat: not offered")

-- The original fix stays: ready, then combat (the events keep coming, their
-- re-reads are secret): still ready.
Clear()
known[3561], bags[RUNE], bags[6948] = true, 1, 1
c = Context()
check(Jump(c, "hearth", "item", 6948) and Jump(c, "teleport", "spell", 3561), "out of combat: hearth and teleport")
Combat()
for _ = 1, 20 do
    M.FireEvent("SPELL_UPDATE_COOLDOWN")
    M.FireEvent("BAG_UPDATE_COOLDOWN")
    M.Tick(0.5, 0.5)
end
c = Context()
check(Jump(c, "hearth", "item", 6948) and Jump(c, "teleport", "spell", 3561),
    "ready, then ten seconds of combat events with secret re-reads: still ready")
-- On cooldown, then combat: ready once the remembered end has passed.
Clear()
known[3561], bags[RUNE] = true, 1
spellCD[3561], spellDur[3561] = GetTime(), 30
check(not Jump(Context(), "teleport", "spell", 3561), "on cooldown out of combat: no teleport")
Combat()
for _ = 1, 20 do
    M.FireEvent("SPELL_UPDATE_COOLDOWN")
    M.Tick(0.5, 0.5)
end
check(not Jump(Context(), "teleport", "spell", 3561), "in combat, ten seconds in: still on the remembered cooldown")
for _ = 1, 50 do
    M.FireEvent("SPELL_UPDATE_COOLDOWN")
    M.Tick(0.5, 0.5)
end
check(Jump(Context(), "teleport", "spell", 3561), "in combat, once the remembered end has passed: the teleport is ready")

-- A Refresh while every answer is secret changes nothing remembered, even
-- when the game changed meanwhile.
Clear()
known[3561], known[20222], bags[RUNE], bags[6948], bags[18984] = true, true, 1, 1, 1
bags[260820], charges[260820], worn[260820] = 1, 2, true
spellCD[3561], spellDur[3561] = GetTime(), 30
Context()
check(ItemJump(18984) and ItemJump(260820), "both teleport items read as usable")
Combat()
local function Snapshot()
    return table.concat({ tostring(A.Knows(3561)), A.ItemCount(RUNE), A.ItemCount(6948), A.ItemCount(260820, true),
        tostring(A.SpellReady(3561)), tostring(A.ItemReady(6948)), tostring(A.IsEquipped(260820)),
        tostring(A.IsUsable(18984)) }, ",")
end
local before = Snapshot()
known[3561], bags[RUNE], bags[6948], charges[260820], worn[260820], usable[18984] = nil, 0, 0, 0, nil, false
itemCD[6948] = GetTime()
refreshes = 0
A.Refresh()
M.FireEvent("SPELL_UPDATE_COOLDOWN")
M.Tick(2, 0.5)
check(refreshes == 2 and Snapshot() == before,
    ("a Refresh with every answer secret changes nothing remembered (%s / %s, %d)"):format(before, Snapshot(), refreshes))

-- Worn and usable: the last readable answer; never readable is no.
Clear()
worn[260820] = true
check(A.IsEquipped(260820) == true and A.IsUsable(18984) == true, "readable: worn and usable")
usable[18986] = false
check(A.IsUsable(18986) == false, "readable: not usable")
Combat()
check(A.IsEquipped(260820) == true and A.IsUsable(18984) == true, "read as worn and usable, then secret: still worn and usable")
check(A.IsUsable(18986) == false, "read as not usable, then secret: still not usable")
check(A.IsEquipped(260819) == false and A.IsUsable(260819) == nil,
    "never readable, then secret: not worn, and usability unknown (as before: skill items fail closed)")

-- Coalescing: 200 events inside a second make one Refresh; a steady stream
-- never more than one a second; an event costs no allocation but the flag.
Clear()
Context()
local events = { "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED" }
refreshes = 0
for i = 1, 200 do
    M.FireEvent(events[i % #events + 1])
    M.Tick(0.004, 0.004)
end
check(refreshes == 0, "during the burst's first second nothing is read yet (" .. refreshes .. ")")
M.Tick(2, 0.05)
check(refreshes == 1, "200 events in under a second: exactly one Refresh (" .. refreshes .. ")")
refreshes = 0
for i = 1, 1000 do
    M.FireEvent(events[i % #events + 1])
    M.Tick(0.01, 0.01)
end
check(refreshes >= 9 and refreshes <= 10, "1000 events over ten seconds: at most one Refresh a second (" .. refreshes .. ")")
M.Tick(2, 0.05)
M.FireEvent("SPELL_UPDATE_COOLDOWN") -- a Refresh is now waiting
-- the addon's own event dispatch (Core.lua's OnEvent), not the mock's
-- FireEvent, which allocates for its varargs
local frame = M.eventFrames.SPELL_UPDATE_COOLDOWN[1]
local onEvent = frame._scripts.OnEvent
collectgarbage("collect")
collectgarbage("stop")
local kb = collectgarbage("count")
for _ = 1, 1000 do onEvent(frame, "SPELL_UPDATE_COOLDOWN") end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
check(grew < 1, ("1000 more events while a Refresh waits allocate nothing (%.2f KB)"):format(grew))
M.Tick(2, 0.05)

-- Without C_Timer: read when the planner next asks, at most once a second.
local savedTimer = C_Timer
C_Timer = nil
Clear()
Context()
refreshes = 0
M.FireEvent("SPELLS_CHANGED")
check(refreshes == 0, "no C_Timer: an event alone reads nothing")
Context()
check(refreshes == 1, "no C_Timer: the planner's next ask reads again first")
M.FireEvent("SPELLS_CHANGED")
Context()
check(refreshes == 1, "no C_Timer: not again within a second")
M.now = M.now + 1.1
Context()
check(refreshes == 2, "no C_Timer: again a second later")
C_Timer = savedTimer

-- Nothing asked about yet: an event or a Refresh calls no game API.
Clear()
local calls = 0
local function Counted(t)
    local out = {}
    for k, fn in pairs(t) do
        out[k] = function(...)
            calls = calls + 1
            return fn(...)
        end
    end
    return out
end
C_SpellBook, C_Spell, C_Item = Counted(Book()), Counted(Spell()), Counted(Item())
refreshes = 0
for _, e in ipairs(events) do M.FireEvent(e) end
M.Tick(2, 0.5)
check(refreshes == 0, "nothing asked about yet: events schedule no Refresh")
A.Refresh()
check(calls == 0, "nothing asked about yet: a Refresh calls no game API (" .. calls .. ")")
-- After a plan, one Refresh re-reads everything the planner asked about.
Context()
calls = 0
A.Refresh()
print(("one Refresh after a plan with the shipped data: %d game API calls"):format(calls))
check(calls > 0 and calls <= 60, "one Refresh after a plan makes a bounded number of game API calls (" .. calls .. ")")

A.Refresh = realRefresh
Clear()

-- ---------------------------------------------------------------------------
-- What a route was planned with against what the abilities say now: Travel
-- plans again at once only when it differs (Travel._AbilitiesChanged), and
-- hears of every read (TRAVEL_ABILITIES_READ) a second after an event.
-- ---------------------------------------------------------------------------
local reads = 0
ns.On("TRAVEL_ABILITIES_READ", function() reads = reads + 1 end)
local changed = Travel._AbilitiesChanged or function() return nil end
bags[6948], bags[RUNE], known[3561] = 1, 2, true
local planned = Context()
check(Jump(planned, "hearth") and Jump(planned, "teleport", "spell", 3561), "planned with: (control) the hearthstone and Teleport: Stormwind")
check(changed(planned) == false, "nothing changed: what the route was planned with still holds")
bags[RUNE] = 1
check(changed(planned) == false, "a rune used, one left: still holds (the teleport still has its reagent)")
bags[RUNE] = 0
check(changed(planned) == true, "the last rune gone: changed (the teleport is no jump now)")
bags[RUNE] = 2
itemCD[6948] = GetTime()
check(changed(planned) == true, "the hearthstone used: changed (on cooldown)")
itemCD[6948] = nil
known[3561] = nil
check(changed(planned) == true, "the teleport unlearned: changed")
known[3561] = true
known[33388] = true
check(changed(planned) == true, "riding learned: changed (faster on the ground)")
known[33388] = nil
check(changed(planned) == false, "all back as it was planned: holds again")
itemCD[6948] = GetTime()
local planned2 = Context()
itemCD[6948] = nil
check(not Jump(planned2, "hearth") and changed(planned2) == true, "planned while the hearthstone was on cooldown, now ready: changed")
Combat()
check(changed(planned) == false and changed(planned2) == true,
    "in combat (every answer secret) the last readable answers stand: no change from secrets")
Peace()
reads = 0
M.FireEvent("BAG_UPDATE_COOLDOWN")
M.Tick(0.5, 0.5)
check(reads == 0, "an event alone tells Travel nothing yet")
M.Tick(1, 0.5)
check(reads == 1, "a second after the event the answers are read again, and Travel is told once (" .. reads .. ")")
reads = 0
for i = 1, 100 do M.FireEvent(events[i % #events + 1]); M.Tick(0.01, 0.01) end
M.Tick(2, 0.5)
check(reads == 1, "a burst of events: told once, with the one read (" .. reads .. ")")
itemCD[6948] = GetTime()
ns.Set("travelHearth", false)
check(changed(planned) == false, "hearthstone and teleports turned off: their state does not count")
ns.Set("travelHearth", true)
check(changed(planned) == true, "(control) turned on again: the hearthstone on cooldown counts")
itemCD[6948] = nil
Clear()

check(#M.errors == 0, "no reported Lua errors: " .. tostring(M.errors[1]))
print(("Travel abilities: %d passed, %d failed"):format(passed, failed))
os.exit((failed == 0 and #M.errors == 0) and 0 or 1)
