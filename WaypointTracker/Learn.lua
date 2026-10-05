-- Learn: WoW Forever keeps its new quests, NPCs and objects on the server,
-- so no database has them yet. This quietly writes down what you meet while
-- you play, and Find uses it right away:
--   * quest givers and hand-ins (with the quest's title, level, text and
--     the objective area the game shows)
--   * NPCs around you (nameplates, your target, what you point at), with
--     their title ("Blacksmith"), and what they do (vendor, trainer...)
--   * what vendors sell
--   * mailboxes you use
--   * enemies and objects where you loot them, and which items they drop
--   * the objectives of the quests in your log (which item, enemy or object)
-- Everything stays on your computer. You can share it (Find > Share
-- discoveries) so it can be added to the database for everyone.
local _, ns = ...
local Geo = ns.Geo

local Learn = {}
ns.Learn = Learn

local MAX_SPOTS_PER_MAP = 30
local MAX_MAPS = 20
local MAX_NPCS = 20000 -- far more than a lifetime of play; keeps the file small
-- the most of each kind kept (what you see yourself, plus imports)
local MAX_ENTRIES = { npcs = MAX_NPCS, objects = 20000, quests = 20000, items = 40000 }
-- the services an NPC can offer (anything else in an import is ignored)
local SERVICES = {
    vendor = true, repair = true, flight = true, trainer = true, banker = true, innkeeper = true,
    auctioneer = true, stablemaster = true, spirithealer = true,
}
local MAX_SELLERS = 20 -- vendors kept per item
local MAX_STOCK = 300 -- items read from one vendor
local Int, CleanText = ns.Int, ns.CleanText
local EXPORT_TAG = "WTL1"

local Plain = ns.Plain

-- a map position kept to 0.1%
local function Round(v)
    return math.floor(v * 1000 + 0.5) / 1000
end

local function CountKeys(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- something new was written down (Find is told every few seconds)
local changed = false
local function Changed()
    changed = true
end

-- what was written down since the last check against the database
local touched = { npcs = {}, objects = {}, items = {} }
local function Touch(key, id)
    touched[key][id] = true
end

local function Enabled()
    return ns.Get("learn") and ns.settings ~= nil
end

local checkedStore -- the saved table already checked this session
local npcCount -- NPCs in it, counted when first needed

function Learn.Store()
    local db = WaypointTrackerDB
    if type(db) ~= "table" then
        return nil
    end
    local st = db.learned
    if type(st) ~= "table" then
        st = {}
        db.learned = st
    end
    -- a damaged SavedVariables file must not break learning: check it once
    -- per session, and drop anything that isn't the shape we write
    if checkedStore ~= st then
        for _, key in ipairs({ "npcs", "objects", "quests", "items" }) do
            if type(st[key]) ~= "table" then
                st[key] = {}
            end
            for id, e in pairs(st[key]) do
                if type(id) ~= "number" or type(e) ~= "table" then
                    st[key][id] = nil
                else
                    Learn.Repair(e)
                end
            end
        end
        if type(st.mailboxes) ~= "table" then
            st.mailboxes = {}
        end
        Learn.Repair(st.mailboxes)
        Learn.RepairFixes(st)
        checkedStore, npcCount = st, nil
    end
    return st
end

-- Drops any field of a saved entry that isn't the type the addon writes.
local FIELD_TYPES = {
    name = "string", title = "string", text = "string", giver = "string", ender = "string",
    level = "number", hostile = "boolean", shared = "boolean",
    spots = "table", services = "table", from = "table", sold = "table", objs = "table", needs = "table", area = "table",
}
function Learn.Repair(e)
    for k, v in pairs(e) do
        local want = FIELD_TYPES[k]
        if (want and type(v) ~= want) or (k == "fac" and v ~= "A" and v ~= "H") then
            e[k] = nil
        end
    end
    if e.spots then
        for m, list in pairs(e.spots) do
            if type(m) ~= "number" or type(list) ~= "table" then
                e.spots[m] = nil
            else
                for i = #list, 1, -1 do
                    if type(list[i]) ~= "number" then
                        e.spots[m] = nil
                        break
                    end
                end
            end
        end
    end
    local a = e.area
    if a and not (type(a[1]) == "number" and type(a[2]) == "number" and type(a[3]) == "number") then
        e.area = nil
    end
    -- lists of text: keep the text, in order, without gaps
    for _, key in ipairs({ "objs", "needs" }) do
        if e[key] then
            local order = {}
            for i, v in pairs(e[key]) do
                if type(i) == "number" and type(v) == "string" then
                    order[#order + 1] = i
                end
            end
            table.sort(order)
            local kept = {}
            for n, i in ipairs(order) do
                kept[n] = e[key][i]
            end
            e[key] = kept
        end
    end
end

-- ---------------------------------------------------------------------------
-- Corrections: you tell Find a spot is wrong, and where it really is
-- ---------------------------------------------------------------------------
-- st.fixes["N123"] (NPC) or ["O45"] (object) = list of
-- { wrong = { m, x, y } or nil, right = { m, x, y } or nil }: no wrong spot
-- adds a spot Find didn't have; no right spot says it isn't there at all.
local MAX_FIXES_PER_ENTRY, MAX_FIXED_ENTRIES = 5, 1000

local function ValidSpot(p)
    return type(p) == "table" and type(p[1]) == "number" and p[1] >= 1 and p[1] % 1 == 0
        and type(p[2]) == "number" and p[2] >= 0 and p[2] <= 1 and type(p[3]) == "number" and p[3] >= 0 and p[3] <= 1
end

function Learn.RepairFixes(st)
    if type(st.fixes) ~= "table" then
        st.fixes = {}
    end
    for key, list in pairs(st.fixes) do
        local ok = type(key) == "string" and key:match("^[NO]%d+$") and type(list) == "table"
        local kept = {}
        for _, fix in ipairs(ok and list or {}) do
            if type(fix) == "table" and (fix.wrong == nil or ValidSpot(fix.wrong)) and (fix.right == nil or ValidSpot(fix.right))
                and (fix.wrong or fix.right) and #kept < MAX_FIXES_PER_ENTRY then
                kept[#kept + 1] = { wrong = fix.wrong, right = fix.right, shared = fix.shared == true or nil }
            end
        end
        st.fixes[key] = #kept > 0 and kept or nil
    end
end

local function FixKey(kind, id)
    return (kind == "npc" and "N" or "O") .. id
end

local function SameSpot(a, b)
    return a and b and a[1] == b[1] and math.abs(a[2] - b[2]) <= 0.02 and math.abs(a[3] - b[3]) <= 0.02
end

-- Saves a correction. kind "npc"/"object"; wrong/right { m, x, y } (x, y
-- 0..1) or nil. A new correction of the same wrong spot replaces the old.
-- Returns true when saved.
local function AddFixTo(st, kind, id, wrong, right, shared)
    id = Int(id)
    if not st or not id or (kind ~= "npc" and kind ~= "object") then
        return false
    end
    wrong = ValidSpot(wrong) and { wrong[1], Round(wrong[2]), Round(wrong[3]) } or nil
    right = ValidSpot(right) and { right[1], Round(right[2]), Round(right[3]) } or nil
    if not wrong and not right then
        return false
    end
    local key = FixKey(kind, id)
    st.fixes = st.fixes or {}
    local list = st.fixes[key]
    if not list then
        if CountKeys(st.fixes) >= MAX_FIXED_ENTRIES then
            return false
        end
        list = {}
        st.fixes[key] = list
    end
    for i = #list, 1, -1 do
        local old = list[i]
        if (wrong and SameSpot(old.wrong, wrong)) or (not wrong and not old.wrong and SameSpot(old.right, right)) then
            if shared and not old.shared then
                return false -- yours wins over an imported one
            end
            table.remove(list, i)
        end
    end
    if #list >= MAX_FIXES_PER_ENTRY then
        return false
    end
    list[#list + 1] = { wrong = wrong, right = right, shared = shared or nil }
    Changed()
    return true
end

function Learn.AddFix(kind, id, wrong, right)
    return AddFixTo(Learn.Store(), kind, id, wrong, right)
end

-- Your corrections of one entry (a list, maybe empty).
function Learn.Fixes(kind, id)
    local st = Learn.Store()
    return st and st.fixes[FixKey(kind, id)] or {}
end

-- Forgets your own corrections of one entry.
function Learn.ClearFixes(kind, id)
    local st = Learn.Store()
    if st then
        st.fixes[FixKey(kind, id)] = nil
        Changed()
    end
end

-- "Creature-0-1-2-3-<id>-<spawn>" -> "npc", id
function Learn.ParseGUID(guid)
    guid = Plain(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    id = tonumber(id)
    if not id then
        return nil
    end
    if kind == "Creature" or kind == "Vehicle" then
        return "npc", id
    elseif kind == "GameObject" then
        return "object", id
    end
end

local function IdentityHidden(unit)
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
        local ok, hidden = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
        return ok and hidden
    end
    return false
end

local function Here()
    local m, x, y = Geo.GetPlayerMapPosition()
    return m, x, y
end

-- one spot per 1% square of the map, a few dozen per map at most
local function AddSpot(e, m, x, y)
    if not m then
        return false
    end
    e.spots = type(e.spots) == "table" and e.spots or {}
    local list = e.spots[m]
    if type(list) ~= "table" then
        local maps = 0
        for _ in pairs(e.spots) do
            maps = maps + 1
        end
        if maps >= MAX_MAPS then
            return false
        end
        list = {}
        e.spots[m] = list
    end
    local cx, cy = math.floor(x * 100), math.floor(y * 100)
    for i = 1, #list, 2 do
        if math.floor(list[i] * 100) == cx and math.floor(list[i + 1] * 100) == cy then
            return false
        end
    end
    if #list >= MAX_SPOTS_PER_MAP * 2 then
        return false
    end
    list[#list + 1] = math.floor(x * 1000 + 0.5) / 1000
    list[#list + 1] = math.floor(y * 1000 + 0.5) / 1000
    return true, #list - 1
end
Learn.AddSpot = AddSpot


-- ---------------------------------------------------------------------------
-- Units (the NPC you're talking to, a quest giver, ...)
-- ---------------------------------------------------------------------------
local nameCache = {} -- guid -> { name, level } from targets/mouseover
local nameCacheSize = 0
local titleChecked = {} -- NPC id -> true once its title was looked for

-- The line under an NPC's name in its tooltip ("Blacksmith"), if it has one.
-- Without a title that line is the level line, which has the word "Level".
-- Returns the title (or nil), and whether the game had the tooltip ready.
local function Title(unit, level)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
        return nil, true
    end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    local lines = ok and type(data) == "table" and data.lines
    if type(lines) ~= "table" or not lines[1] then
        return nil, false
    end
    local line = lines[2]
    local text = type(line) == "table" and Plain(line.leftText)
    if type(text) ~= "string" or text == "" then
        return nil, true
    end
    local levelWord = Plain(_G.LEVEL)
    if text:find("??", 1, true) or (type(levelWord) == "string" and levelWord ~= "" and text:find(levelWord, 1, true))
        or (level and text:find("%f[%d]" .. level .. "%f[%D]")) then
        return nil, true
    end
    return CleanText(text:match("^<(.*)>$") or text, 60), true
end

-- Friend or foe, the same for every player: an Alliance or Horde NPC is
-- friendly (to its own side: Find's faction filter takes care of the rest),
-- anything else is an enemy when you could attack it.
local function Hostile(unit)
    local fac = Plain(UnitFactionGroup(unit))
    if fac == "Alliance" or fac == "Horde" then
        return false, fac:sub(1, 1)
    end
    local reaction = Plain(UnitReaction(unit, "player"))
    if type(reaction) ~= "number" then
        return nil
    elseif reaction >= 5 then
        return false
    elseif reaction <= 3 then
        return true
    end
    return UnitCanAttack and Plain(UnitCanAttack("player", unit)) and true or false
end

-- What the game shows about an NPC: name, level, friend or foe, faction,
-- title. Returns true when something new was written down.
local function Describe(e, unit, id)
    local before = ("%s|%s|%s|%s|%s"):format(tostring(e.name), tostring(e.level), tostring(e.hostile), tostring(e.fac), tostring(e.title))
    e.name = CleanText(Plain(UnitName(unit))) or e.name
    local hostile, fac = Hostile(unit)
    if hostile ~= nil then
        e.hostile = hostile
    end
    e.fac = fac or e.fac
    local level = Int(Plain(UnitLevel(unit)))
    e.level = level or e.level
    if not titleChecked[id] then
        local title, ready = Title(unit, level)
        e.title = title or e.title
        titleChecked[id] = ready
    end
    return before ~= ("%s|%s|%s|%s|%s"):format(tostring(e.name), tostring(e.level), tostring(e.hostile), tostring(e.fac), tostring(e.title))
end

function Learn.Unit(unit, service)
    if not Enabled() or IdentityHidden(unit) then
        return
    end
    local guid = Plain(UnitGUID(unit))
    local kind, id = Learn.ParseGUID(guid)
    if not kind then
        return
    end
    local st = Learn.Store()
    local m, x, y = Here()
    local tbl = kind == "npc" and st.npcs or st.objects
    local e = tbl[id] or {}
    tbl[id] = e
    e.shared = nil -- seen in the game now, not just imported
    if kind == "npc" then
        Describe(e, unit, id)
    else
        e.name = CleanText(Plain(UnitName(unit))) or e.name
    end
    if service then
        e.services = e.services or {}
        e.services[service] = true
    end
    AddSpot(e, m, x, y)
    Touch(kind == "npc" and "npcs" or "objects", id)
    Changed()
    return kind, id
end

-- ---------------------------------------------------------------------------
-- Quests
-- ---------------------------------------------------------------------------
local function QuestEntry(id)
    local st = Learn.Store()
    local q = st.quests[id] or {}
    st.quests[id] = q
    q.shared = nil -- seen in the game now, not just imported
    return q
end

local function Giver()
    for _, unit in ipairs({ "questnpc", "npc" }) do
        if UnitExists(unit) then
            local kind, id = Learn.Unit(unit)
            if kind then
                return kind, id
            end
        end
    end
end

function Learn.QuestOffered()
    if not Enabled() or not GetQuestID then
        return
    end
    local id = Plain(GetQuestID())
    if not id or id == 0 then
        return
    end
    local q = QuestEntry(id)
    q.title = Plain(GetTitleText and GetTitleText()) or q.title
    q.text = Plain(GetObjectiveText and GetObjectiveText()) or q.text
    local kind, gid = Giver()
    if kind then
        q.giver = (kind == "npc" and "U" or "O") .. gid
    end
    Changed()
end

function Learn.QuestHandIn()
    if not Enabled() or not GetQuestID then
        return
    end
    local id = Plain(GetQuestID())
    if not id or id == 0 then
        return
    end
    local q = QuestEntry(id)
    q.title = q.title or Plain(GetTitleText and GetTitleText())
    local kind, gid = Giver()
    if kind then
        q.ender = (kind == "npc" and "U" or "O") .. gid
    end
    Changed()
end

function Learn.QuestAccepted(questID)
    if not Enabled() or not questID then
        return
    end
    local q = QuestEntry(questID)
    if C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo then
        local idx = C_QuestLog.GetLogIndexForQuestID(questID)
        local info = idx and C_QuestLog.GetInfo(idx)
        if info then
            q.title = Plain(info.title) or q.title
            q.level = Plain(info.level) or q.level
        end
    end
    Changed()
end

-- "Runes of the Sorcerer-Kings: 0/1" or "0/1 Runes..." -> the name
local function ObjectiveName(text)
    text = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*[:：]%s*%d+%s*/%s*%d+%s*$", "")
    text = text:gsub("%s*%(.-%)%s*$", "")
    return text ~= "" and text or nil
end

local OBJECTIVE_KINDS = { item = true, monster = true, object = true }

-- what each quest in your log asks for, as the game lists it
local function QuestObjectives()
    if not (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives) then
        return
    end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and Plain(info.questID)
        if id then
            local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, id)
            if ok and type(objectives) == "table" and #objectives > 0 then
                local list = {}
                for _, o in ipairs(objectives) do
                    local text, kind = Plain(o.text), Plain(o.type)
                    local name = type(text) == "string" and OBJECTIVE_KINDS[kind] and ObjectiveName(text)
                    if name then
                        list[#list + 1] = kind .. ":" .. name
                    end
                end
                if #list > 0 then
                    local q = QuestEntry(id)
                    q.title = q.title or Plain(info.title)
                    q.objs = list
                end
            end
        end
    end
end
Learn.ObjectiveName = ObjectiveName

-- where the game marks each quest in your log on the map you're on
local function QuestAreas()
    if not Enabled() or not C_QuestLog.GetQuestsOnMap then
        return
    end
    local m = C_Map.GetBestMapForUnit("player")
    if not m then
        return
    end
    local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, m)
    if not ok or type(quests) ~= "table" then
        return
    end
    pcall(QuestObjectives)
    for _, info in ipairs(quests) do
        local id, x, y = info.questID, ns.Num(info.x), ns.Num(info.y)
        if id and x and y and x > 0 and y > 0 then
            local q = QuestEntry(id)
            local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
            -- the marker moves to the hand-in once the quest is done
            if not done then
                q.area = { m, math.floor(x * 1000) / 1000, math.floor(y * 1000) / 1000 }
            end
            if not q.title and C_QuestLog.GetTitleForQuestID then
                q.title = Plain(C_QuestLog.GetTitleForQuestID(id))
            end
        end
    end
    Changed()
end

-- ---------------------------------------------------------------------------
-- Looting: enemies and objects
-- ---------------------------------------------------------------------------
local lastObjectName, lastObjectTime = nil, 0

function Learn.Looted()
    if not Enabled() or not GetNumLootItems or not GetLootSourceInfo then
        return
    end
    local m, x, y = Here()
    if not m then
        return
    end
    local st = Learn.Store()
    local seen = {}
    for slot = 1, GetNumLootItems() do
        local sources = { GetLootSourceInfo(slot) }
        -- which item this is, so Find knows what drops it
        local link = GetLootSlotLink and Plain(GetLootSlotLink(slot))
        local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        local item
        if itemID then
            item = st.items[itemID] or {}
            st.items[itemID] = item
            item.shared = nil
            Touch("items", itemID)
            local name = GetLootSlotInfo and Plain(select(2, GetLootSlotInfo(slot)))
            item.name = (type(name) == "string" and name ~= "") and name or item.name
            item.from = item.from or {}
        end
        for i = 1, #sources, 2 do
            local kind, id = Learn.ParseGUID(Plain(sources[i]))
            if item and kind then
                item.from[(kind == "npc" and "U" or "O") .. id] = true
            end
        end
        for i = 1, #sources, 2 do
            local guid = Plain(sources[i])
            if guid and not seen[guid] then
                seen[guid] = true
                local kind, id = Learn.ParseGUID(guid)
                if kind == "npc" then
                    local e = st.npcs[id] or {}
                    st.npcs[id] = e
                    e.shared = nil
                    Touch("npcs", id)
                    local known = nameCache[guid]
                    if known then
                        e.name = known.name or e.name
                        e.level = known.level or e.level
                    end
                    if e.hostile == nil then
                        e.hostile = true
                    end
                    AddSpot(e, m, x, y)
                elseif kind == "object" then
                    local e = st.objects[id] or {}
                    st.objects[id] = e
                    e.shared = nil
                    Touch("objects", id)
                    if lastObjectName and GetTime() - lastObjectTime < 8 then
                        e.name = e.name or lastObjectName
                    end
                    AddSpot(e, m, x, y)
                end
            end
        end
    end
    Changed()
end

local function Remember(unit)
    if IdentityHidden(unit) then
        return
    end
    local guid = Plain(UnitGUID(unit))
    if not guid then
        return
    end
    local name = Plain(UnitName(unit))
    if name then
        -- only needed until the loot window opens, so keep it small
        if nameCacheSize >= 500 then
            wipe(nameCache)
            nameCacheSize = 0
        end
        if not nameCache[guid] then
            nameCacheSize = nameCacheSize + 1
        end
        nameCache[guid] = { name = name, level = Plain(UnitLevel(unit)) }
    end
end

-- world objects show their name in the tooltip when you point at them
local function TooltipShown(tooltip)
    if not Enabled() or tooltip:GetOwner() ~= UIParent then
        return
    end
    if tooltip.GetUnit and Plain(tooltip:GetUnit()) then
        return
    end
    local line = _G[tooltip:GetName() .. "TextLeft1"]
    local text = line and Plain(line:GetText())
    if text and text ~= "" then
        lastObjectName, lastObjectTime = text, GetTime()
    end
end

-- the same from the game's tooltip data (the first line is the name)
local function ObjectTooltip(data)
    if not Enabled() or type(data) ~= "table" then
        return
    end
    local line = data.lines and data.lines[1]
    local text = line and Plain(line.leftText)
    if type(text) == "string" and text ~= "" then
        lastObjectName, lastObjectTime = text, GetTime()
    end
end

-- ---------------------------------------------------------------------------
-- NPC services
-- ---------------------------------------------------------------------------
local SERVICE_FOR = {}
local function MapInteractions()
    local T = Enum and Enum.PlayerInteractionType
    if not T then
        return
    end
    SERVICE_FOR[T.Merchant or -1] = "vendor"
    SERVICE_FOR[T.Vendor or -1] = "vendor"
    SERVICE_FOR[T.TaxiNode or -1] = "flight"
    SERVICE_FOR[T.Trainer or -1] = "trainer"
    SERVICE_FOR[T.Banker or -1] = "banker"
    SERVICE_FOR[T.Binder or -1] = "innkeeper"
    SERVICE_FOR[T.Auctioneer or -1] = "auctioneer"
    SERVICE_FOR[T.StableMaster or -1] = "stablemaster"
    SERVICE_FOR[T.SpiritHealer or -1] = "spirithealer"
    SERVICE_FOR[T.Gossip or -1] = false
    SERVICE_FOR[T.QuestGiver or -1] = false
    SERVICE_FOR[T.MailInfo or -1] = "mailbox"
end

function Learn.Interaction(kind)
    if not Enabled() then
        return
    end
    local service = SERVICE_FOR[kind]
    if service == nil then
        return
    end
    if service == "mailbox" then
        local m, x, y = Here()
        if m then
            local st = Learn.Store()
            if AddSpot(st.mailboxes, m, x, y) then
                Changed()
            end
        end
        return
    end
    if UnitExists("npc") then
        Learn.Unit("npc", service or nil)
        if service == "vendor" and CanMerchantRepair and CanMerchantRepair() then
            Learn.Unit("npc", "repair")
        end
    end
end

-- ---------------------------------------------------------------------------
-- NPCs around you: nameplates, your target and what you point at
-- ---------------------------------------------------------------------------
-- The game tells addons where you are, not where an NPC stands, but it does
-- say whether an NPC is within reach. So an NPC is written down where you are
-- once it's within about 28 yards, and that spot moves to where you stand
-- when you come within a few yards of it (7 to 10, depending on the game).
-- Only out of combat, once a second: a handful of quick checks.
local CLOSE, NEAR = 3, 4 -- CheckInteractDistance: duel (~7-10 yards), follow (~28 yards)
local SIGHT_UNITS = { "target", "mouseover", "focus", "softinteract" }
for i = 1, 40 do
    SIGHT_UNITS[#SIGHT_UNITS + 1] = "nameplate" .. i
end
local sighted, sightedCount = {}, 0 -- spawn (guid) -> what was written down

local function Reach(unit)
    -- the game only answers this outside combat
    if not CheckInteractDistance or (InCombatLockdown and InCombatLockdown()) then
        return nil
    end
    local ok, close = pcall(CheckInteractDistance, unit, CLOSE)
    if ok and Plain(close) then
        return "close"
    end
    local okNear, near = pcall(CheckInteractDistance, unit, NEAR)
    if okNear and Plain(near) then
        return "near"
    end
end

-- what was done with a spawn this session (kept small)
local function Mark(guid, state)
    if not sighted[guid] then
        if sightedCount >= 5000 then
            wipe(sighted)
            sightedCount = 0
        end
        sightedCount = sightedCount + 1
    end
    sighted[guid] = state
end

function Learn.Sight(unit)
    if not UnitExists(unit) or Plain(UnitIsPlayer(unit)) or IdentityHidden(unit) then
        return
    end
    -- pets, totems and other things players control aren't the world's NPCs
    if UnitPlayerControlled and Plain(UnitPlayerControlled(unit)) then
        return
    end
    local guid = Plain(UnitGUID(unit))
    local before = guid and sighted[guid]
    if not guid or before == true then
        return
    end
    local kind, id = Learn.ParseGUID(guid)
    if kind ~= "npc" then
        return
    end
    -- wild critters (level 1, neither friend nor foe) are only noise
    if Plain(UnitLevel(unit)) == 1 and Plain(UnitReaction(unit, "player")) == 4 then
        Mark(guid, true)
        return
    end
    local reach = Reach(unit)
    if not reach or (reach == "near" and before) then
        return
    end
    local m, x, y = Here()
    if not m then
        return
    end
    local st = Learn.Store()
    local e = st.npcs[id]
    if not e then
        if not npcCount then
            npcCount = 0
            for _ in pairs(st.npcs) do
                npcCount = npcCount + 1
            end
        end
        if npcCount >= MAX_NPCS then
            return
        end
        npcCount = npcCount + 1
        e = {}
        st.npcs[id] = e
    end
    local news = e.shared or false
    e.shared = nil
    news = Describe(e, unit, id) or news
    -- true: done with this one; "near": seen from a distance; a table: the
    -- rough spot written down, to move once you're close
    local state = true
    local list = type(before) == "table" and e.spots and e.spots[before[1]]
    if list and before[1] == m and list[before[2]] == before[3] and list[before[2] + 1] == before[4] then
        -- now right next to it: move the rough spot here
        list[before[2]], list[before[2] + 1] = Round(x), Round(y)
        news = true
    else
        local added, i = AddSpot(e, m, x, y)
        news = added or news
        if reach == "near" then
            state = added and { m, i, Round(x), Round(y) } or "near"
        end
    end
    Mark(guid, state)
    if news then
        Touch("npcs", id)
        Changed()
    end
end

function Learn.LookAround()
    if not Enabled() or (InCombatLockdown and InCombatLockdown()) then
        return
    end
    for _, unit in ipairs(SIGHT_UNITS) do
        Learn.Sight(unit)
    end
end

-- ---------------------------------------------------------------------------
-- Vendors: what they sell
-- ---------------------------------------------------------------------------
function Learn.Merchant()
    if not Enabled() or not GetMerchantNumItems or not GetMerchantItemLink then
        return
    end
    local kind, id = Learn.ParseGUID(Plain(UnitGUID("npc")))
    if kind ~= "npc" then
        return
    end
    local st = Learn.Store()
    local ref = "U" .. id
    local count = Int(Plain(GetMerchantNumItems())) or 0
    for slot = 1, math.min(count, MAX_STOCK) do
        local link = Plain(GetMerchantItemLink(slot))
        local itemID = type(link) == "string" and Int(link:match("item:(%d+)"))
        if itemID then
            local it = st.items[itemID] or {}
            st.items[itemID] = it
            it.shared = nil
            it.name = CleanText(link:match("|h%[(.-)%]|h")) or it.name
            it.sold = type(it.sold) == "table" and it.sold or {}
            if not it.sold[ref] and CountKeys(it.sold) < MAX_SELLERS then
                it.sold[ref] = true
                Touch("items", itemID)
                Changed()
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Keeping only what's new
-- ---------------------------------------------------------------------------
-- Once Find's database is loaded, anything you wrote down that it already
-- has (an NPC at a spot it knows, a vendor it lists) is dropped from your
-- saved discoveries: they hold only what's new or different. all: check
-- everything (after a merge), else only what changed since the last check.
function Learn.Compact(all)
    local DB = ns.DB
    local st = Learn.Store()
    if not (st and DB and DB.ready and DB.hasShipped and DB.AddsSomething) then
        return 0
    end
    local removed = 0
    for key, kind in pairs({ npcs = "npc", objects = "object" }) do
        local t = st[key]
        for id in pairs(all and t or touched[key]) do
            local e = t[id]
            if e and not DB.AddsSomething(kind, id, e) then
                t[id] = nil
                removed = removed + 1
                if key == "npcs" and npcCount then
                    npcCount = npcCount - 1
                end
            end
        end
        wipe(touched[key])
    end
    for id in pairs(all and st.items or touched.items) do
        local it = st.items[id]
        if it then
            for _, field in ipairs({ "from", "sold" }) do
                for ref in pairs(type(it[field]) == "table" and it[field] or {}) do
                    if not DB.AddsSomething(field == "from" and "drop" or "sold", id, ref) then
                        it[field][ref] = nil
                    end
                end
            end
            if not next(it.from or {}) and not next(it.sold or {}) then
                st.items[id] = nil
                removed = removed + 1
            end
        end
    end
    wipe(touched.items)
    return removed
end

-- ---------------------------------------------------------------------------
-- Counting, sharing, importing
-- ---------------------------------------------------------------------------
function Learn.Count()
    local st = Learn.Store()
    if not st then
        return 0
    end
    local n = 0
    for _, t in ipairs({ st.npcs, st.objects, st.quests, st.items, st.fixes }) do
        for _ in pairs(t) do
            n = n + 1
        end
    end
    return n
end

local function SpotsText(spots)
    local parts = {}
    for m, list in pairs(spots or {}) do
        local xy = {}
        for i = 1, #list do
            xy[i] = math.floor(list[i] * 1000 + 0.5)
        end
        parts[#parts + 1] = m .. ":" .. table.concat(xy, ",")
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

local function Clean(s)
    return (tostring(s or ""):gsub("[\t\n\r]", " "))
end

-- A plain-text block anyone can paste into Find > Import (or into a
-- GitHub issue, so it can go into the database for everyone). It leaves out
-- what the database already knows (a spot next to a known one, a vendor
-- already listed), so it stays short; Learn.Export(true) gives everything.
function Learn.Export(everything)
    local st = Learn.Store()
    local DB = ns.DB
    local check = not everything and DB and DB.Load and DB.Load() and DB.hasShipped and DB.AddsSomething
    if check then
        -- include what was learned in the last few seconds
        ns.Call(DB.MergeLearned)
    end
    local function keep(kind, id, value)
        return not check or DB.AddsSomething(kind, id, value)
    end
    local lines = { ("%s\t%s\t%s"):format(EXPORT_TAG, GetLocale(), tostring(ns.version)) }
    local function T(v)
        return type(v) == "table" and v or {}
    end
    for id, e in pairs(st.npcs) do
        local services = {}
        for s in pairs(T(e.services)) do
            services[#services + 1] = s
        end
        table.sort(services)
        if not e.shared and keep("npc", id, e) then
            lines[#lines + 1] = table.concat({ "N", id, Clean(e.name), e.hostile == nil and "" or (e.hostile and 1 or 0), e.level or "", table.concat(services, ","), SpotsText(e.spots), e.fac or "", Clean(e.title) }, "\t")
        end
    end
    for id, e in pairs(st.objects) do
        if not e.shared and keep("object", id, e) then
            lines[#lines + 1] = table.concat({ "O", id, Clean(e.name), SpotsText(e.spots) }, "\t")
        end
    end
    -- (what you imported is someone else's discovery: they share it)
    for id, q in pairs(st.quests) do
        if not q.shared then
            local area = q.area and (q.area[1] .. ":" .. math.floor(q.area[2] * 1000) .. "," .. math.floor(q.area[3] * 1000)) or ""
            local objs = {}
            for _, o in ipairs(T(q.objs)) do
                objs[#objs + 1] = Clean(o):gsub("|", "/")
            end
            lines[#lines + 1] = table.concat({ "Q", id, Clean(q.title), q.level or "", q.giver or "", q.ender or "", area, Clean(q.text), table.concat(objs, "|") }, "\t")
        end
    end
    for id, it in pairs(st.items) do
        local from, sold = {}, {}
        if it.shared then
            it = {}
        end
        for ref in pairs(T(it.from)) do
            if keep("drop", id, ref) then
                from[#from + 1] = ref
            end
        end
        for ref in pairs(T(it.sold)) do
            if keep("sold", id, ref) then
                sold[#sold + 1] = ref
            end
        end
        table.sort(from)
        table.sort(sold)
        if #from + #sold > 0 then
            lines[#lines + 1] = table.concat({ "I", id, Clean(it.name), table.concat(from, ","), table.concat(sold, ",") }, "\t")
        end
    end
    if st.mailboxes.spots then
        lines[#lines + 1] = "M\t" .. SpotsText(st.mailboxes.spots)
    end
    -- your corrections: kind, id, the wrong spot, the right one
    local function Spot(p)
        return p and ("%d:%d,%d"):format(p[1], math.floor(p[2] * 1000 + 0.5), math.floor(p[3] * 1000 + 0.5)) or ""
    end
    local keys = {}
    for key in pairs(T(st.fixes)) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        for _, fix in ipairs(st.fixes[key]) do
            if not fix.shared then
                lines[#lines + 1] = table.concat({ "C", key:sub(1, 1), key:sub(2), Spot(fix.wrong), Spot(fix.right) }, "\t")
            end
        end
    end
    return table.concat(lines, "\n")
end

-- A spot value: 0..1000 in the text, 0..1 on the map.
local function SpotValue(s)
    local n = tonumber(s)
    if n and n >= 0 and n <= 1000 then
        return n / 1000
    end
end

local function ParseSpots(text, e)
    for m, list in (text or ""):gmatch("(%d+):([%d,]+)") do
        m = Int(m)
        local nums = {}
        for n in list:gmatch("%d+") do
            nums[#nums + 1] = SpotValue(n) or false
        end
        for i = 1, #nums - 1, 2 do
            if m and nums[i] and nums[i + 1] then
                AddSpot(e, m, nums[i], nums[i + 1])
            end
        end
    end
end

-- Adds a reference like "U123" to a list once.
local function AddRef(list, ref)
    for i = 1, #list do
        if list[i] == ref then
            return
        end
    end
    list[#list + 1] = ref
end

-- Giver/ender field: "U1,O2" references only.
local function Refs(s)
    local out = {}
    for ref in (s or ""):gmatch("[UO]%d+") do
        if Int(ref:sub(2)) then
            AddRef(out, ref)
        end
    end
    return out[1] and table.concat(out, ",") or nil
end

local function Split(line)
    local out, pos = {}, 1
    while true do
        local tab = line:find("\t", pos, true)
        if not tab then
            out[#out + 1] = line:sub(pos)
            return out
        end
        out[#out + 1] = line:sub(pos, tab - 1)
        pos = tab + 1
    end
end
Learn.Split = Split

-- Adds shared discoveries to yours. Returns how many entries it read.
function Learn.Import(text, st, quiet)
    st = st or Learn.Store()
    if not st or type(text) ~= "string" or not text:find(EXPORT_TAG, 1, true) then
        return 0
    end
    st.items = st.items or {}
    local n = 0
    -- how many of each kind there are, so an import can't grow them forever
    local counts = {}
    for key in pairs(MAX_ENTRIES) do
        counts[key] = quiet and 0 or CountKeys(st[key] or {})
    end
    -- an entry to add to. Into your own discoveries (not quiet), a new one
    -- is marked as imported: someone else's discovery fills gaps in the
    -- database but never renames what's there, and isn't shared on as yours
    local function Entry(key, id)
        local t = st[key]
        if t[id] then
            return t[id]
        end
        if quiet then
            t[id] = {}
            return t[id]
        end
        if counts[key] >= MAX_ENTRIES[key] then
            return nil
        end
        counts[key] = counts[key] + 1
        t[id] = { shared = true }
        return t[id]
    end
    -- everything read here may come from a stranger: numbers are checked,
    -- text is cleaned of escape codes, and lists are kept short
    for line in text:gmatch("[^\r\n]+") do
        local f = Split(line)
        local kind, id = f[1], Int(f[2])
        local e = id and ((kind == "N" and Entry("npcs", id)) or (kind == "O" and Entry("objects", id)) or (kind == "Q" and Entry("quests", id)) or (kind == "I" and Entry("items", id)))
        if kind == "N" and e then
            e.name = e.name or CleanText(f[3])
            if e.hostile == nil and (f[4] == "1" or f[4] == "0") then
                e.hostile = f[4] == "1"
            end
            e.level = e.level or Int(f[5])
            e.fac = e.fac or ((f[8] == "A" or f[8] == "H") and f[8] or nil)
            e.title = e.title or CleanText(f[9], 60)
            for s in (f[6] or ""):gmatch("[%a_]+") do
                if SERVICES[s] then
                    e.services = e.services or {}
                    e.services[s] = true
                end
            end
            ParseSpots(f[7], e)
            n = n + 1
        elseif kind == "O" and e then
            e.name = e.name or CleanText(f[3])
            ParseSpots(f[4], e)
            n = n + 1
        elseif kind == "Q" and e then
            local q = e
            q.title = q.title or CleanText(f[3])
            q.level = q.level or Int(f[4])
            q.giver = q.giver or Refs(f[5])
            q.ender = q.ender or Refs(f[6])
            local m, x, y = (f[7] or ""):match("(%d+):(%d+),(%d+)")
            m, x, y = Int(m), SpotValue(x), SpotValue(y)
            if m and x and y and not q.area then
                q.area = { m, x, y }
            end
            q.text = q.text or CleanText(f[8], 1000)
            -- direct links: items (I), NPCs (U) and objects (O) the quest needs
            if f[10] and f[10] ~= "" then
                q.needs = q.needs or {}
                for ref in f[10]:gmatch("[IUO]%d+") do
                    if #q.needs < 40 and Int(ref:sub(2)) then
                        AddRef(q.needs, ref)
                    end
                end
            end
            q.fac = q.fac or ((f[11] == "A" or f[11] == "H") and f[11] or nil)
            if not q.objs and f[9] and f[9] ~= "" then
                q.objs = {}
                for o in f[9]:gmatch("[^|]+") do
                    o = CleanText(o)
                    if o and #q.objs < 10 then
                        q.objs[#q.objs + 1] = o
                    end
                end
            end
            n = n + 1
        elseif kind == "I" and e then
            local it = e
            it.name = it.name or CleanText(f[3])
            it.from = it.from or {}
            for ref in (f[4] or ""):gmatch("[UO]%d+") do
                if Int(ref:sub(2)) and CountKeys(it.from) < 40 then
                    it.from[ref] = true
                end
            end
            for ref in (f[5] or ""):gmatch("U%d+") do
                it.sold = it.sold or {}
                if Int(ref:sub(2)) and CountKeys(it.sold) < MAX_SELLERS then
                    it.sold[ref] = true
                end
            end
            n = n + 1
        elseif kind == "M" then
            ParseSpots(f[2], st.mailboxes)
            n = n + 1
        elseif kind == "C" and (f[2] == "N" or f[2] == "O") then
            -- a correction: the wrong spot and the right one ("map:x,y")
            local function Spot(text)
                local m, x, y = (text or ""):match("^(%d+):(%d+),(%d+)$")
                m, x, y = Int(m), SpotValue(x), SpotValue(y)
                return m and x and y and { m, x, y } or nil
            end
            if AddFixTo(st, f[2] == "N" and "npc" or "object", f[3], Spot(f[4]), Spot(f[5]), not quiet) then
                n = n + 1
            end
        end
    end
    if not quiet then
        Changed()
        ns.Fire("LEARNED")
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
ns.RegisterEvent("QUEST_DETAIL", Learn.QuestOffered)
ns.RegisterEvent("QUEST_PROGRESS", Learn.QuestHandIn)
ns.RegisterEvent("QUEST_COMPLETE", Learn.QuestHandIn)
ns.RegisterEvent("QUEST_ACCEPTED", function(a, b)
    -- (questID) in newer clients, (logIndex, questID) in older ones
    Learn.QuestAccepted(b or a)
end)
ns.RegisterEvent("LOOT_OPENED", Learn.Looted)
ns.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Learn.Interaction)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if Enabled() and UnitExists("target") then
        Remember("target")
    end
end)
ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
    if Enabled() and UnitExists("mouseover") then
        Remember("mouseover")
        if not (InCombatLockdown and InCombatLockdown()) then
            Learn.Sight("mouseover")
        end
    end
end)

-- a vendor's list can fill in over a moment (item details load), so read it
-- again shortly after it changes
local merchantPending = false
local function ReadMerchantSoon()
    if merchantPending or not Enabled() then
        return
    end
    merchantPending = true
    C_Timer.After(0.5, function()
        merchantPending = false
        ns.Call(Learn.Merchant)
    end)
end
local merchantOpen = false
ns.RegisterEvent("MERCHANT_SHOW", function()
    merchantOpen = true
    ReadMerchantSoon()
end)
ns.RegisterEvent("MERCHANT_CLOSED", function()
    merchantOpen = false
end)
ns.RegisterEvent("MERCHANT_UPDATE", ReadMerchantSoon)
ns.RegisterEvent("MERCHANT_FILTER_ITEM_UPDATE", ReadMerchantSoon)
-- items the game hadn't loaded yet arrive a moment later
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if merchantOpen then
        ReadMerchantSoon()
    end
end)

local areaPending = false
ns.RegisterEvent("QUEST_LOG_UPDATE", function()
    if areaPending or not Enabled() then
        return
    end
    areaPending = true
    C_Timer.After(3, function()
        areaPending = false
        ns.Call(QuestAreas)
    end)
end)

ns.On("LOGIN", function()
    MapInteractions()
    -- world objects' names: the game's tooltip data hook where there is one,
    -- the tooltip's OnShow otherwise
    local T = Enum and Enum.TooltipDataType
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and T and T.Object then
        TooltipDataProcessor.AddTooltipPostCall(T.Object, function(tooltip, data)
            pcall(ObjectTooltip, data)
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnShow", function(self)
            pcall(TooltipShown, self)
        end)
    end
end)

-- ---------------------------------------------------------------------------
-- Names of WoW Forever's new quests. The game client lists their IDs but has
-- no names for them, so ask the game, a couple at a time, while you play.
-- The names are kept per language and are not part of shared discoveries.
-- ---------------------------------------------------------------------------
local ASK_EVERY, ASK_PER_STEP = 0.5, 3

function Learn.QuestTitles()
    local db = WaypointTrackerDB
    if type(db) ~= "table" then
        return nil
    end
    local locale = GetLocale and GetLocale() or "enUS"
    local t = db.questTitles
    if type(t) ~= "table" or t.locale ~= locale or type(t.names) ~= "table" then
        t = { locale = locale, names = {} }
        db.questTitles = t
    end
    return t.names
end

local foreverSet, askList, askPos
local function ForeverSet()
    if not foreverSet then
        foreverSet, askList = {}, {}
        for id in (ns.foreverQuests or ""):gmatch("%d+") do
            id = tonumber(id)
            foreverSet[id] = true
            askList[#askList + 1] = id
        end
        askPos = 0
    end
    return foreverSet
end

local function RecordTitle(id)
    local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
    title = ok and Plain(title)
    if type(title) ~= "string" or title == "" then
        return false
    end
    local names = Learn.QuestTitles()
    if names and names[id] ~= title then
        names[id] = title
        Changed()
    end
    return true
end

-- One step of the background scan. Returns false when it is finished.
function Learn.AskTitles()
    if not (C_QuestLog and C_QuestLog.GetTitleForQuestID) then
        return false
    end
    ForeverSet()
    local names = Learn.QuestTitles()
    if not names then
        return true
    end
    if not Enabled() or (InCombatLockdown and InCombatLockdown()) then
        return true
    end
    local asked = 0
    while asked < ASK_PER_STEP do
        askPos = askPos + 1
        local id = askList[askPos]
        if not id then
            return false
        end
        if not names[id] and not RecordTitle(id) and C_QuestLog.RequestLoadQuestByID then
            pcall(C_QuestLog.RequestLoadQuestByID, id)
            asked = asked + 1
        end
    end
    return true
end

-- Start asking again from the first quest (the game may know more now).
function Learn.RestartTitleScan()
    ForeverSet()
    askPos = 0
end

function Learn.TitleProgress()
    ForeverSet()
    local n = 0
    for _ in pairs(Learn.QuestTitles() or {}) do
        n = n + 1
    end
    return n, #askList
end

ns.RegisterEvent("QUEST_DATA_LOAD_RESULT", function(questID, success)
    questID = Plain(questID)
    if success and questID and ForeverSet()[questID] then
        RecordTitle(questID)
    end
end)

-- tell Find about new discoveries every few seconds (not on every event),
-- and ask for quest names in the background
local ticker = CreateFrame("Frame")
local acc, askAcc, lookAcc, scanning, scanDone, lookBroken = 0, 0, 0, false, false, false
local LOOK_EVERY = 1
ns.On("LOGIN", function()
    C_Timer.After(20, function()
        scanning = true
    end)
end)

-- Is the first quest-name scan still going? Returns running, percent done.
-- Once one full scan has finished (per language), later ones run quietly:
-- they only pick up names the game didn't know last time.
function Learn.ScanProgress()
    if scanDone or not (C_QuestLog and C_QuestLog.GetTitleForQuestID) then
        return false, 100
    end
    Learn.QuestTitles()
    local t = type(WaypointTrackerDB) == "table" and WaypointTrackerDB.questTitles
    if type(t) == "table" and t.complete then
        return false, 100
    end
    ForeverSet()
    if #askList == 0 then
        return false, 100
    end
    return true, math.floor(math.min(askPos, #askList) * 100 / #askList)
end
ticker:SetScript("OnUpdate", function(_, elapsed)
    if scanning then
        askAcc = askAcc + elapsed
        if askAcc >= ASK_EVERY then
            askAcc = 0
            local ok, more = pcall(Learn.AskTitles)
            if not ok then
                ns.ReportError(more)
                scanning, scanDone = false, true
            elseif not more then
                scanning, scanDone = false, true
                Learn.QuestTitles()
                if type(WaypointTrackerDB) == "table" and type(WaypointTrackerDB.questTitles) == "table" then
                    WaypointTrackerDB.questTitles.complete = true
                end
            end
        end
    end
    lookAcc = lookAcc + elapsed
    if lookAcc >= LOOK_EVERY and not lookBroken then
        lookAcc = 0
        local ok, err = pcall(Learn.LookAround)
        if not ok then
            -- report it once and stop looking for this session
            ns.ReportError(err)
            lookBroken = true
        end
    end
    acc = acc + elapsed
    if acc < 5 then
        return
    end
    acc = 0
    if changed then
        changed = false
        ns.Call(Learn.Compact)
        ns.Fire("LEARNED")
    end
end)
