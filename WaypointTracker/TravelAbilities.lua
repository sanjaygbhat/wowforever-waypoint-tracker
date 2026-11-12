-- TravelAbilities: what this character can use to get somewhere faster, for
-- Real routes (Travel.lua): the hearthstone and Astral Recall, class
-- teleports (with their reagent in the bags), teleport items (engineering
-- transporters and the like: carried, charged, worn if a trinket, usable by
-- this character), riding skills, speed forms (Travel Form, Ghost Wolf,
-- Aspect of the Cheetah, Cat Form with Feral Swiftness) and the Frequent
-- Flier perk. Reagents, item rules and spell text come from the client's
-- tables via tools/build_travel.py.
--
-- Portions derived from MIT-licensed code and travel data; see
-- THIRD-PARTY-LICENSES.txt. The data is generated into TravelData.lua's
-- `abilities` block by tools/build_travel.py.
--
-- Every game API answer is sanitized (ns.Num/ns.Plain/ns.Str) and every
-- call is guarded: a missing or failing API means "not known / not owned",
-- never an error.
local _, ns = ...

local A = {}
ns.TravelAbilities = A

local GLOBAL_COOLDOWN = 1.5 -- a cooldown this short is the global cooldown, not the ability's
local TALENT_REFRESH = 30 -- seconds a talent-rank answer is reused

-- Before TravelData.lua carried an abilities block these were built in;
-- networks without an `abilities` block (tests, older data) keep them.
local FALLBACK = table.concat({
    "hearth\t6948\t8690\t10\t3600",
    "hearth\t\t556\t10\t900",
    "flier\t1225490\t0.2",
}, "\n")

local function Fields(line)
    local out, from = {}, 1
    while true do
        local i = line:find("\t", from, true)
        if not i then
            out[#out + 1] = line:sub(from)
            return out
        end
        out[#out + 1] = line:sub(from, i - 1)
        from = i + 1
    end
end

-- The abilities block of TravelData.lua, as tables. `nodes` resolves item landings.
function A.Parse(text, nodes)
    local ab = { hearths = {}, items = {}, forms = {}, riding = {} }
    for line in (text or FALLBACK):gmatch("[^\n]+") do
        local f = Fields(line)
        local kind = f[1]
        if kind == "hearth" then
            local spell = tonumber(f[3])
            if spell then
                ab.hearths[#ab.hearths + 1] = { item = tonumber(f[2]), spell = spell,
                    cast = tonumber(f[4]) or 10, cooldown = tonumber(f[5]) or 0 }
            end
        elseif kind == "item" then
            local item, node = tonumber(f[2]), nodes and nodes[f[3] or ""]
            if item and node then
                ab.items[#ab.items + 1] = { item = item, node = node, cast = tonumber(f[4]) or 10,
                    cooldown = tonumber(f[5]) or 0, fac = f[6] ~= "" and f[6] or nil,
                    equip = f[7] == "1", charges = f[8] == "1", ability = tonumber(f[9] or ""),
                    skill = tonumber(f[10] or ""), rank = tonumber(f[11] or ""), level = tonumber(f[12] or ""),
                    misfire = f[13] == "1" }
            end
        elseif kind == "form" then
            local spell = tonumber(f[2])
            if spell then
                ab.forms[#ab.forms + 1] = { spell = spell, bonus = tonumber(f[3]) or 0, indoor = f[4] == "1",
                    talent = tonumber(f[5]), perRank = tonumber(f[6]) or 0 }
            end
        elseif kind == "riding" then
            local spell = tonumber(f[2])
            if spell then
                ab.riding[#ab.riding + 1] = { spell = spell, bonus = tonumber(f[3]) or 0 }
            end
        elseif kind == "flier" then
            local spell = tonumber(f[2])
            if spell then
                ab.flier = { spell = spell, bonus = tonumber(f[3]) or 0 }
            end
        end
    end
    return ab
end

-- ---------------------------------------------------------------------------
-- What the game says
-- ---------------------------------------------------------------------------
-- A value the game hid from addons (in combat it can hand back "secret"
-- values). Only these fall back to the last readable answer below; a
-- missing, failing or empty answer keeps meaning "no".
local function Secret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end

-- The last readable answers, for when the game's answer is secret.
local knownMemo = {}
local countMemo = { count = {}, uses = {} }

-- Does the player know this spell? Modern spellbook first, then the
-- deprecated globals; an API that throws counts as absent. The first API
-- that answers decides; when its answer is secret, its last readable
-- answer stands (not known if there was none).
local function Ask(fn, ...)
    local ok, known = pcall(fn, ...)
    local plain = ok and ns.Plain(known)
    if not ok then
        return nil -- no answer
    end
    if plain == nil and Secret(known) then
        return "hidden"
    end
    return plain and "yes" or "no"
end

function A.Knows(spell)
    local say
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if C_SpellBook and C_SpellBook.IsSpellKnown and bank ~= nil then
        say = Ask(C_SpellBook.IsSpellKnown, spell, bank)
    end
    if say == nil and IsPlayerSpell then
        say = Ask(IsPlayerSpell, spell)
    end
    if say == nil and IsSpellKnown then
        say = Ask(IsSpellKnown, spell)
    end
    if say == "hidden" then
        return knownMemo[spell] == true
    end
    if say == nil then
        return false
    end
    knownMemo[spell] = say == "yes"
    return say == "yes"
end

-- How many of an item the bags hold (0 when the game can't say). With
-- `uses`, an item with charges counts its charges left instead. A secret
-- answer falls back to the last readable one (0 if there is none).
function A.ItemCount(item, uses)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not count then
        return 0
    end
    local ok, owned
    if uses then
        ok, owned = pcall(count, item, false, true)
    else
        ok, owned = pcall(count, item)
    end
    if not ok then
        return 0
    end
    local memo = uses and countMemo.uses or countMemo.count
    if Secret(owned) then
        return memo[item] or 0
    end
    owned = ns.Num(owned)
    if owned then
        memo[item] = owned
    end
    return owned or 0
end

-- Is this item worn? (A trinket only works equipped.) No API, or a failing
-- one: not worn. A secret answer falls back to the last readable one (not
-- worn if there is none).
local wornMemo, usableMemo = {}, {}
function A.IsEquipped(item)
    if not (C_Item and C_Item.IsEquippedItem) then
        return false
    end
    local ok, worn = pcall(C_Item.IsEquippedItem, item)
    if not ok then
        return false
    end
    if Secret(worn) then
        return wornMemo[item] == true
    end
    worn = ns.Plain(worn) == true
    wornMemo[item] = worn
    return worn
end

-- Does the game say this character can use the item (skill, specialization,
-- level)? true or false, or nil when it can't say. A secret answer falls
-- back to the last readable true or false (nil if there is none).
function A.IsUsable(item)
    if not (C_Item and C_Item.IsUsableItem) then
        return nil
    end
    local ok, usable = pcall(C_Item.IsUsableItem, item)
    if not ok then
        return nil
    end
    if Secret(usable) then
        return usableMemo[item]
    end
    usable = ns.Plain(usable)
    if usable == nil then
        return nil
    end
    usable = usable and true or false
    usableMemo[item] = usable
    return usable
end

-- From the last readable answer: `true` when it was ready, else the time
-- its cooldown ends. In combat the game can hand back secret values, and
-- those fall back to this. With no readable answer yet, a secret one means
-- not ready. A missing answer (no API, a failing one) only trusts a
-- remembered cooldown end, as before.
local readyAt = { spell = {}, item = {} }

local function Ready(memo, id, start, duration, hidden)
    local s, dur = ns.Num(start), ns.Num(duration)
    if not s or not dur then
        local at = memo[id]
        if at == true then
            return hidden and true or false
        end
        return at ~= nil and at - GetTime() <= 1
    end
    if s == 0 or dur <= GLOBAL_COOLDOWN then
        memo[id] = true
        return true
    end
    memo[id] = s + dur
    return (s + dur - GetTime()) <= 1
end

-- Is this spell off cooldown? No cooldown API at all: not ready.
function A.SpellReady(spell)
    local start, duration, hidden
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and type(info) == "table" then
            start, duration = ns.Num(info.startTime), ns.Num(info.duration)
            hidden = Secret(info.startTime) or Secret(info.duration)
        end
    elseif GetSpellCooldown then
        local ok, s, dur = pcall(GetSpellCooldown, spell)
        start, duration = ns.Num(s), ns.Num(dur)
        hidden = ok and (Secret(s) or Secret(dur))
    end
    return Ready(readyAt.spell, spell, start, duration, hidden)
end

-- Is this item off cooldown? No item cooldown API, or one that fails: ready
-- (owning the item is checked separately).
function A.ItemReady(item)
    local cd = (C_Item and C_Item.GetItemCooldown) or (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not cd then
        return true
    end
    local ok, start, duration = pcall(cd, item)
    if not ok then
        return true
    end
    return Ready(readyAt.item, item, start, duration, Secret(start) or Secret(duration))
end

-- An item's name, kept once the game has given one (the arrow's step text
-- asks every frame). No answer yet is not kept: item info can arrive late.
local itemNames = {}
local function ItemName(item)
    local cached = itemNames[item]
    if cached then
        return cached
    end
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, item)
        name = ok and ns.Str(name)
        if name and name ~= "" then
            itemNames[item] = name
            return name
        end
    end
    return "#" .. item
end
A.ItemName = ItemName

-- Points spent in the talent that teaches this spell (0 when none, or when
-- the client has no talent tree). Walks the active trait config.
local function WalkTalent(spell)
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
        and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then
        return 0
    end
    local ok, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    cfg = ok and ns.Num(cfg)
    if not cfg then return 0 end
    local okInfo, config = pcall(C_Traits.GetConfigInfo, cfg)
    if not okInfo or type(config) ~= "table" or type(config.treeIDs) ~= "table" then return 0 end
    for _, tree in ipairs(config.treeIDs) do
        tree = ns.Num(tree)
        local okNodes, nodes = pcall(C_Traits.GetTreeNodes, tree)
        for _, nodeID in ipairs(tree and okNodes and type(nodes) == "table" and nodes or {}) do
            local okNode, node = pcall(C_Traits.GetNodeInfo, cfg, nodeID)
            local entries = okNode and type(node) == "table" and type(node.entryIDs) == "table" and node.entryIDs or {}
            for _, entryID in ipairs(entries) do
                local okEntry, entry = pcall(C_Traits.GetEntryInfo, cfg, entryID)
                local def = okEntry and type(entry) == "table" and ns.Num(entry.definitionID)
                local okDef, info = false, nil
                if def then okDef, info = pcall(C_Traits.GetDefinitionInfo, def) end
                if okDef and type(info) == "table" and ns.Num(info.spellID) == spell then
                    return ns.Num(node.currentRank) or 0
                end
            end
        end
    end
    return 0
end

local talentCache = {}
function A.TalentRank(spell)
    local now = GetTime()
    local hit = talentCache[spell]
    if hit and now - hit.t < TALENT_REFRESH then
        return hit.rank
    end
    local rank = WalkTalent(spell)
    talentCache[spell] = { t = now, rank = rank }
    return rank
end

-- ---------------------------------------------------------------------------
-- Keeping the remembered answers current
-- ---------------------------------------------------------------------------
-- The answers above are remembered when they are read, and the planner
-- reads them. A hearthstone used, a rune sold or a spell unlearned while no
-- route is planned would leave them saying what they were, and in combat
-- (secret answers) the planner would trust that. So when the game says such
-- things changed, everything the planner last asked about is read again, at
-- most once a second (the events can come many times a second in combat).
-- A secret answer leaves what is remembered as it was. Talent ranks are not
-- read again here: they keep their own TALENT_REFRESH. After the read,
-- TRAVEL_ABILITIES_READ tells Travel, which plans again at once only when
-- what its route was planned with no longer holds.
local REFRESH_EVERY = 1
local NOTHING = {}
local refAb, refTeleports -- what the planner last asked about
local dirty, pending, refreshedAt = false, false, nil

-- `quiet`: the planner is reading them right now (Flush): nobody to tell.
function A.Refresh(quiet)
    dirty = false
    refreshedAt = GetTime()
    local ab = refAb
    if ab then
        for _, h in ipairs(ab.hearths or NOTHING) do
            if h.item then
                A.ItemCount(h.item)
                A.ItemReady(h.item)
            else
                A.Knows(h.spell)
                A.SpellReady(h.spell)
            end
        end
        for _, it in ipairs(ab.items or NOTHING) do
            A.ItemCount(it.item, it.charges)
            A.ItemReady(it.item)
            if it.equip then A.IsEquipped(it.item) end
            if it.ability then A.Knows(it.ability) end
            A.IsUsable(it.item)
        end
        for _, f in ipairs(ab.forms or NOTHING) do
            A.Knows(f.spell)
        end
        for _, r in ipairs(ab.riding or NOTHING) do
            A.Knows(r.spell)
        end
        if ab.flier then
            A.Knows(ab.flier.spell)
        end
    end
    for _, t in ipairs(refTeleports or NOTHING) do
        A.Knows(t.spell)
        A.SpellReady(t.spell)
        if t.reagent then A.ItemCount(t.reagent) end
    end
    if not quiet then ns.Fire("TRAVEL_ABILITIES_READ") end
end

-- Without C_Timer the read happens when the planner next asks.
local function Flush()
    if dirty and not (C_Timer and C_Timer.After)
        and (not refreshedAt or GetTime() - refreshedAt >= REFRESH_EVERY) then
        A.Refresh(true)
    end
end

local function RefreshLater()
    pending = false
    if dirty then
        ns.Call(A.Refresh)
    end
end

-- An event: only marks it, and asks for one read a second later.
local function Changed()
    if not (refAb or refTeleports) then
        return -- the planner hasn't asked about anything: nothing to keep current
    end
    dirty = true
    if not pending and C_Timer and C_Timer.After then
        pending = true
        C_Timer.After(REFRESH_EVERY, RefreshLater)
    end
end

-- ---------------------------------------------------------------------------
-- What it means for a trip
-- ---------------------------------------------------------------------------
-- Multipliers on run speed outdoors and indoors. Outdoors the best of the
-- riding skills the character knows (a character mounts as fast as they've
-- trained) and their speed forms; indoors only forms that work there.
function A.SpeedFactors(ab)
    Flush()
    refAb = ab or refAb
    local outdoor, indoor, form = 1, 1, nil
    for _, r in ipairs(ab and ab.riding or {}) do
        if 1 + r.bonus > outdoor and A.Knows(r.spell) then
            outdoor = 1 + r.bonus
        end
    end
    for _, f in ipairs(ab and ab.forms or {}) do
        if A.Knows(f.spell) then
            local bonus = f.bonus
            if f.talent and f.perRank > 0 then
                bonus = bonus + f.perRank * A.TalentRank(f.talent)
            end
            if 1 + bonus > outdoor then
                outdoor, form = 1 + bonus, f.spell
            end
            if f.indoor and 1 + bonus > indoor then
                indoor = 1 + bonus
            end
        end
    end
    return outdoor, indoor, form
end

-- Flight-path time multiplier: Frequent Flier makes the flight mount faster.
function A.FlightFactor(ab)
    Flush()
    refAb = ab or refAb
    local perk = ab and ab.flier
    if perk and A.Knows(perk.spell) then
        return 1 / (1 + perk.bonus)
    end
    return 1
end

local function Owns(h)
    if h.item then
        return A.ItemCount(h.item) > 0 and A.ItemReady(h.item)
    end
    return A.Knows(h.spell) and A.SpellReady(h.spell)
end

-- Has the bags the reagent a teleport needs (Rune of Teleportation)?
local function HasReagent(t)
    return not t.reagent or A.ItemCount(t.reagent) >= (t.reagents or 1)
end

-- Can this character use this teleport item right now? Carried (with a
-- charge left), off cooldown, worn when it's a trinket, the engineering
-- specialization it asks for, and the game's own say on skill and level.
-- A skill requirement only the game can confirm: no answer, no jump.
local function ItemUsable(it, level)
    if A.ItemCount(it.item, it.charges) <= 0 or not A.ItemReady(it.item) then
        return false
    end
    if (it.equip and not A.IsEquipped(it.item)) or (it.ability and not A.Knows(it.ability)) then
        return false
    end
    local usable = A.IsUsable(it.item)
    if usable == false or (it.skill and usable ~= true) then
        return false
    end
    if it.level and usable == nil then
        return (ns.Num(level) or 0) >= it.level
    end
    return true
end
A.ItemUsable = ItemUsable

-- The ways to jump from where you stand: { node, cost, kind, ... } for
-- Travel's search. `inn`/`name` is where the hearthstone goes, `teleports`
-- the network's class teleports, `faction` the player's, `loading` the
-- seconds a loading screen costs, `level` the character's.
function A.Jumps(ab, inn, name, teleports, faction, loading, level)
    Flush()
    refAb, refTeleports = ab or refAb, teleports or refTeleports
    local jumps = {}
    if inn then
        local best
        for _, h in ipairs(ab and ab.hearths or {}) do
            if (not best or h.cooldown < best.cooldown) and Owns(h) then
                best = h
            end
        end
        if best then
            jumps[#jumps + 1] = { node = inn, cost = best.cast + loading, kind = "hearth", name = name,
                item = best.item, spell = not best.item and best.spell or nil }
        end
    end
    for _, t in ipairs(teleports or {}) do
        if A.Knows(t.spell) and HasReagent(t) and A.SpellReady(t.spell) then
            jumps[#jumps + 1] = { node = t.node, cost = t.cost + loading, kind = "teleport", spell = t.spell }
        end
    end
    for _, it in ipairs(ab and ab.items or {}) do
        if (not it.fac or it.fac == faction) and ItemUsable(it, level) then
            jumps[#jumps + 1] = { node = it.node, cost = it.cast + loading, kind = "item", item = it.item,
                misfire = it.misfire or nil }
        end
    end
    return jumps
end

function A._Reset()
    readyAt = { spell = {}, item = {} }
    knownMemo = {}
    countMemo = { count = {}, uses = {} }
    wornMemo, usableMemo = {}, {}
    itemNames = {}
    talentCache = {}
    refAb, refTeleports = nil, nil
    dirty, pending, refreshedAt = false, false, nil
end

-- What can change these answers. (They are read again a second later at
-- most, and Travel is told then: A.Refresh.)
for _, event in ipairs({ "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED",
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED" }) do
    ns.RegisterEvent(event, Changed)
end
