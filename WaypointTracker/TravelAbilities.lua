-- TravelAbilities: what this character can use to get somewhere faster, for
-- Real routes (Travel.lua): the hearthstone and Astral Recall, class
-- teleports, teleport items in the bags, riding skills, speed forms (Travel
-- Form, Ghost Wolf, Aspect of the Cheetah, Cat Form with Feral Swiftness)
-- and the Frequent Flier perk.
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
                    cooldown = tonumber(f[5]) or 0, fac = f[6] ~= "" and f[6] or nil }
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
-- Does the player know this spell? Modern spellbook first, then the
-- deprecated globals; an API that throws counts as absent.
function A.Knows(spell)
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if C_SpellBook and C_SpellBook.IsSpellKnown and bank ~= nil then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spell, bank)
        if ok then return ns.Plain(known) and true or false end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spell)
        if ok then return ns.Plain(known) and true or false end
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, spell)
        return ok and ns.Plain(known) and true or false
    end
    return false
end

-- How many of an item the bags hold (0 when the game can't say).
function A.ItemCount(item)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not count then
        return 0
    end
    local ok, owned = pcall(count, item)
    return ok and ns.Num(owned) or 0
end

-- The time each cooldown ends, from the last readable answer: in combat the
-- game can hand back secret values, and those fall back to this. With no
-- readable answer yet, a secret one means not ready.
local readyAt = { spell = {}, item = {} }

local function Ready(memo, id, start, duration)
    local s, dur = ns.Num(start), ns.Num(duration)
    if not s or not dur then
        local at = memo[id]
        return at ~= nil and at - GetTime() <= 1
    end
    if s == 0 or dur <= GLOBAL_COOLDOWN then
        memo[id] = nil
        return true
    end
    memo[id] = s + dur
    return (s + dur - GetTime()) <= 1
end

-- Is this spell off cooldown? No cooldown API at all: not ready.
function A.SpellReady(spell)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and type(info) == "table" then
            start, duration = ns.Num(info.startTime), ns.Num(info.duration)
        end
    elseif GetSpellCooldown then
        start, duration = GetSpellCooldown(spell)
        start, duration = ns.Num(start), ns.Num(duration)
    end
    return Ready(readyAt.spell, spell, start, duration)
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
    return Ready(readyAt.item, item, start, duration)
end

local function ItemName(item)
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, item)
        name = ok and ns.Str(name)
        if name and name ~= "" then
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
-- What it means for a trip
-- ---------------------------------------------------------------------------
-- Multipliers on run speed outdoors and indoors. Outdoors the best of the
-- riding skills the character knows (a character mounts as fast as they've
-- trained) and their speed forms; indoors only forms that work there.
function A.SpeedFactors(ab)
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

-- The ways to jump from where you stand: { node, cost, kind, ... } for
-- Travel's search. `inn`/`name` is where the hearthstone goes, `teleports`
-- the network's class teleports, `faction` the player's, `loading` the
-- seconds a loading screen costs.
function A.Jumps(ab, inn, name, teleports, faction, loading)
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
        if A.Knows(t.spell) and A.SpellReady(t.spell) then
            jumps[#jumps + 1] = { node = t.node, cost = t.cost + loading, kind = "teleport", spell = t.spell }
        end
    end
    for _, it in ipairs(ab and ab.items or {}) do
        if (not it.fac or it.fac == faction) and A.ItemCount(it.item) > 0 and A.ItemReady(it.item) then
            jumps[#jumps + 1] = { node = it.node, cost = it.cast + loading, kind = "item", item = it.item }
        end
    end
    return jumps
end

function A._Reset()
    readyAt = { spell = {}, item = {} }
    talentCache = {}
end
