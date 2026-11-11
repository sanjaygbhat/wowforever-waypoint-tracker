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
local faction = "Alliance"
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
        GetItemCount = function(id) return bags[id] or 0 end,
        GetItemCooldown = function(id) local s = itemCD[id]; return s or 0, s and 3600 or 0, 1 end,
        GetItemNameByID = function(id) return "Item " .. id end,
    }
end
C_SpellBook, C_Spell, C_Item = Book(), Spell(), Item()
local mockFaction = UnitFactionGroup
function UnitFactionGroup(unit)
    if unit == "player" then return faction end
    return mockFaction(unit)
end

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
for _, t in ipairs(d.teleports) do teleports[t.spell] = t.node.id end
local wantTeleports = { [18960] = "TELEPORT_MOONGLADE", [3561] = "CITY_STORMWIND", [3562] = "CITY_IRONFORGE",
    [3565] = "CITY_DARNASSUS", [3563] = "CITY_UNDERCITY", [3566] = "CITY_THUNDER_BLUFF", [3567] = "CITY_ORGRIMMAR" }
for spell, node in pairs(wantTeleports) do
    check(teleports[spell] == node, "class teleport " .. spell .. " lands at " .. node)
end
check(#ab.items == 0, "the Forever data has no fixed-destination teleport items")

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
known[18960] = true
c = Context()
path = Travel.Search(auberdine, Place("TELEPORT_MOONGLADE", 15), c)
check(Uses(path, "teleport", "spell", 18960), "Teleport: Moonglade is chosen for a druid going to Moonglade")
known[18960] = nil

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
-- Teleport items need the item (the mechanism; Forever's data has none yet)
-- ---------------------------------------------------------------------------
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
bags[6948], known[556], known[3561], known[33391] = 1, true, true, true
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
check(A.Knows(3561) == false, "a secret spellbook answer is not known")
C_Item.GetItemCount = function() return secret end
check(A.ItemCount(6948) == 0, "a secret item count is not carried")
C_SpellBook, C_Spell, C_Item = Book(), Spell(), Item()
bags[6948], known[556], known[3561], known[33391] = nil, nil, nil, nil

check(#M.errors == 0, "no reported Lua errors: " .. tostring(M.errors[1]))
print(("Travel abilities: %d passed, %d failed"):format(passed, failed))
os.exit((failed == 0 and #M.errors == 0) and 0 or 1)
