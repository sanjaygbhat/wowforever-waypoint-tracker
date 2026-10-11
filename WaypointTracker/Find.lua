-- Find: a database browser for NPCs, quests, objects and quest items
-- that sends the arrow to them. Also one-click "nearest"
-- buttons for the places everyone looks for: mailbox, innkeeper, flight
-- master, repair, bank and auction house.
local _, ns = ...
local L, Geo, WP, DB = ns.L, ns.Geo, ns.WP, ns.DB

local Find = {}
ns.Find = Find

local WIDTH, HEIGHT = 720, 556
local ROWS = 14
local ROW_H = 22
local LIST_W = 410
local MAX_IMPORT = 4 * 1024 * 1024

local frame, searchBox, countText, emptyText, rows, detail, tabs
local results, total = {}, 0
-- with nothing typed, the list shows what's near you: nearby is true then,
-- nearDist has each entry's distance and nearMap the map it was made for
local nearby, nearDist, nearMap = false, {}, nil
local offset = 0
local selected

local TABS = {
    { key = "all", label = "TAB_ALL", kinds = { quest = true, npc = true, enemy = true, object = true, item = true, place = true } },
    { key = "quest", label = "TAB_QUESTS", kinds = { quest = true } },
    { key = "npc", label = "TAB_NPCS", kinds = { npc = true } },
    { key = "enemy", label = "TAB_ENEMIES", kinds = { enemy = true } },
    { key = "object", label = "TAB_OBJECTS", kinds = { object = true } },
    { key = "item", label = "TAB_ITEMS", kinds = { item = true } },
}

local SERVICES = {
    { key = "mailbox", label = "SERVICE_MAILBOX" },
    { key = "innkeeper", label = "SERVICE_INNKEEPER" },
    { key = "flight", label = "SERVICE_FLIGHT" },
    { key = "repair", label = "SERVICE_REPAIR" },
    { key = "banker", label = "SERVICE_BANKER" },
    { key = "auctioneer", label = "SERVICE_AUCTIONEER" },
}

local KIND_COLOUR = {
    quest = { 1, 0.82, 0 },
    npc = { 1, 1, 1 },
    enemy = { 1, 0.45, 0.4 },
    object = { 0.6, 0.8, 1 },
    spot = { 1, 0.82, 0 },
    place = { 0.45, 1, 0.45 },
    item = { 0.12, 1, 0 },
}

local KIND_LABEL = { quest = "TYPE_QUEST", npc = "TYPE_NPC", enemy = "TYPE_ENEMY", object = "TYPE_OBJECT", item = "TYPE_ITEM", place = "TYPE_PLACE" }
-- only what players found is labelled; shipped data needs no label
local LEARNED_LABEL = { you = "LEARNED_BY_YOU", community = "LEARNED_BY_COMMUNITY" }
-- item quality colours, as the game shows them
local QUALITY_COLOUR = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 1, 1, 1 },
    [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1, 0.5, 0 },
    [6] = { 0.9, 0.8, 0.5 },
}
local RANK_LABEL = { ["1"] = "RANK_ELITE", ["2"] = "RANK_RARE_ELITE", ["3"] = "RANK_BOSS", ["4"] = "RANK_RARE" }

-- friendly NPCs and enemies share a table; tell them apart here
local function KindOf(e)
    if e.kind == "npc" and DB.IsEnemy(e) then
        return "enemy"
    end
    return e.kind
end

local function ColourOf(e)
    if e.kind == "item" and QUALITY_COLOUR[e.quality or -1] then
        return QUALITY_COLOUR[e.quality]
    end
    return KIND_COLOUR[KindOf(e)] or KIND_COLOUR.npc
end

-- "Reagent", "Armor - Cloth"... in the client's language
local function ItemTypeText(e)
    local classInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
    local subInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    if not e.class or not classInfo then
        return nil
    end
    local ok, class = pcall(classInfo, e.class)
    if not ok or type(class) ~= "string" or class == "" then
        return nil
    end
    local sok, sub = pcall(subInfo or function() end, e.class, e.subclass or 0)
    if sok and type(sub) == "string" and sub ~= "" and sub ~= class then
        return class .. " - " .. sub
    end
    return class
end

local function W()
    return ns.UI.W
end

-- The background scan for WoW Forever's quest names: running, percent done.
local function Scanning()
    if ns.Learn and ns.Learn.ScanProgress then
        return ns.Learn.ScanProgress()
    end
    return false, 100
end

local function Status(text, good)
    frame.status:SetText(text or "")
    if good then
        frame.status:SetTextColor(0.3, 1, 0.3)
    else
        frame.status:SetTextColor(1, 0.35, 0.3)
    end
end

-- Sends the arrow to the nearest spawn of any of `entries`.
local function WaypointToNearest(entries, title)
    local e, p = DB.NearestOf(entries, { faction = ns.Get("findFaction") })
    if not e then
        return nil
    end
    if e.name == "" then
        return DB.GoTo(e, p, title or Geo.GetMapName(p.m))
    end
    return DB.GoTo(e, p, title and (title .. " - " .. e.name) or e.name)
end

local function GoToNearest(entries, title)
    local wp = WaypointToNearest(entries, title)
    if wp then
        Status(L.ADDED:format(WP.Describe(wp)), true)
    else
        Status(L.NO_LOCATION)
    end
end

-- Sets the arrow for an entry (a quest's next step, an item's source...).
local function WaypointFor(e)
    if e.kind == "quest" then
        return WaypointToNearest(DB.QuestTargets(e, DB.DefaultQuestStep(e)), e.name)
    elseif e.kind == "item" then
        return WaypointToNearest(DB.ItemSources(e), e.name)
    end
    return WaypointToNearest({ e })
end

-- ---------------------------------------------------------------------------
-- Detail pane (right side)
-- ---------------------------------------------------------------------------
local function NamesOf(list, max)
    local out, seen = {}, {}
    for _, e in ipairs(list) do
        -- something the database has no name for: say where it is
        local p = e.name == "" and DB.Points(e)[1]
        local name = p and Geo.GetMapName(p.m) or e.name
        if name ~= "" and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
            if #out >= (max or 4) then
                break
            end
        end
    end
    return table.concat(out, ", ")
end

local function ClearButtons()
    for _, b in ipairs(detail.buttons) do
        b:Hide()
        b.targets, b.title, b.action = nil, nil, nil
    end
end

local function AddButton(i, label, targets, title)
    local b = detail.buttons[i]
    b:SetText(label)
    b.targets, b.title = targets, title
    b:SetEnabled(#targets > 0)
    b:Show()
end

-- a detail button that does something other than set the arrow
local function AddAction(i, label, action)
    local b = detail.buttons[i]
    b:SetText(label)
    b.action = action
    b:SetEnabled(true)
    b:Show()
end

-- NPCs and objects from the database can have their spot corrected
local function Correctable(e)
    return (e.kind == "npc" or e.kind == "object") and e.id > 0
end

local function CorrectedByYou(e)
    for _, fix in ipairs(e.fixes or {}) do
        if fix.mine then
            return true
        end
    end
    return false
end

local function ShowDetail(e)
    selected = e
    ClearButtons()
    if not e then
        detail.name:SetText("")
        detail.kind:SetText("")
        detail.body:SetText(L.FIND_EMPTY_DETAIL)
        return
    end
    local kind = KindOf(e)
    local c = ColourOf(e)
    detail.name:SetText(e.name)
    detail.name:SetTextColor(c[1], c[2], c[3])
    local kindLine = e.sub or L[KIND_LABEL[kind]] or ""
    local body = {}
    if e.title then
        body[#body + 1] = "<" .. e.title .. ">"
    end
    if LEARNED_LABEL[e.learned] then
        body[#body + 1] = "|cff66ccff" .. L[LEARNED_LABEL[e.learned]] .. "|r"
    end

    if e.kind == "quest" then
        if e.level then
            kindLine = kindLine .. "  -  " .. L.LEVEL_FMT:format(tostring(e.level))
        end
        local state = DB.QuestState(e)
        body[#body + 1] = "|cffffd100" .. (L["QUEST_STATE_" .. state:upper()] or "") .. "|r"
        if e.text and e.text ~= "" then
            body[#body + 1] = e.text
        end
        local starts = DB.QuestTargets(e, "start")
        local objs = DB.QuestTargets(e, "objective")
        local ends = DB.QuestTargets(e, "end")
        if #starts > 0 then
            body[#body + 1] = L.QUEST_GIVER_FMT:format(NamesOf(starts))
        end
        if #ends > 0 then
            body[#body + 1] = L.QUEST_TURNIN_FMT:format(NamesOf(ends))
        end
        if #starts == 0 and #objs == 0 and #ends == 0 then
            body[#body + 1] = "|cff999999" .. L.QUEST_NO_SPOTS .. "|r"
        end
        AddButton(1, L.GO_GIVER, starts, e.name)
        AddButton(2, L.GO_OBJECTIVE, objs, e.name)
        AddButton(3, L.GO_TURNIN, ends, e.name)
    elseif e.kind == "item" then
        local src = DB.ItemSources(e)
        local typeText = ItemTypeText(e)
        if typeText then
            kindLine = typeText
        end
        if e.ilvl and e.ilvl > 0 then
            kindLine = kindLine .. "  -  " .. L.ITEM_LEVEL_FMT:format(e.ilvl)
        end
        if e.desc then
            body[#body + 1] = "|cffffd100\"" .. e.desc .. "\"|r"
        end
        if e.reqlevel and e.reqlevel > 1 then
            body[#body + 1] = L.REQUIRES_LEVEL_FMT:format(e.reqlevel)
        end
        if e.startsQuest then
            local q = DB.quests[e.startsQuest]
            body[#body + 1] = L.STARTS_QUEST:format(q and q.name or ("#" .. e.startsQuest))
        end
        local needed = DB.QuestsNeeding(e)
        if #needed > 0 then
            body[#body + 1] = L.NEEDED_FOR:format(NamesOf(needed, 3))
        elseif Scanning() then
            -- the quest that needs it may be one whose name isn't in yet
            body[#body + 1] = "|cff999999" .. L.SCAN_ITEM_NOTE .. "|r"
        end
        if #e.dropU == 0 and #e.dropO == 0 and #e.soldBy == 0 then
            body[#body + 1] = "|cff999999" .. L.ITEM_NO_SOURCE .. "|r"
        end
        if #e.dropU > 0 or #e.dropO > 0 then
            local droppers = {}
            for _, id in ipairs(e.dropU) do
                droppers[#droppers + 1] = DB.units[id]
            end
            for _, id in ipairs(e.dropO) do
                droppers[#droppers + 1] = DB.objects[id]
            end
            body[#body + 1] = L.DROPPED_BY:format(NamesOf(droppers, 5))
        end
        if #e.soldBy > 0 then
            local sellers = {}
            for _, id in ipairs(e.soldBy) do
                sellers[#sellers + 1] = DB.units[id]
            end
            body[#body + 1] = L.SOLD_BY:format(NamesOf(sellers, 4))
        end
        AddButton(1, L.GO_NEAREST_SOURCE, src, e.name)
    else
        if e.level and e.level ~= "" then
            kindLine = kindLine .. "  -  " .. L.LEVEL_FMT:format(e.level)
        end
        if RANK_LABEL[e.rank or ""] then
            kindLine = kindLine .. "  -  " .. L[RANK_LABEL[e.rank]]
        end
        local zones = DB.ZonesOf(e)
        if #zones > 0 then
            body[#body + 1] = L.FOUND_IN:format(table.concat(zones, ", "))
        end
        local _, dist = DB.Nearest(DB.Points(e))
        if dist then
            body[#body + 1] = L.NEAREST_FMT:format(Geo.FormatDistance(dist))
        end
        if CorrectedByYou(e) then
            body[#body + 1] = "|cff66ccff" .. L.FIX_MARK .. "|r"
        end
        AddButton(1, L.GO_THERE, { e })
        if Correctable(e) then
            AddAction(2, #DB.Points(e) > 0 and L.FIX_SPOT or L.FIX_ADD, function()
                Find.ShowFixBox(e)
            end)
        end
    end
    detail.kind:SetText(kindLine)
    detail.body:SetText(table.concat(body, "\n\n"))
end

-- ---------------------------------------------------------------------------
-- Results list
-- ---------------------------------------------------------------------------
local function RowInfo(e)
    if e.kind == "quest" then
        local lvl = e.level and ("[" .. e.level .. "] ") or ""
        local state = DB.QuestState(e)
        local tag = state == "done" and L.QUEST_TAG_DONE or state == "ready" and L.QUEST_TAG_READY or (state ~= "new" and L.QUEST_TAG_ACTIVE) or ""
        if nearby and nearDist[e] then
            local d = Geo.FormatDistance(nearDist[e])
            tag = tag ~= "" and (tag .. "  " .. d) or d
        end
        return lvl .. e.name, tag
    elseif e.kind == "item" then
        return e.name, L.TYPE_ITEM
    end
    local p, dist = DB.Nearest(DB.Points(e))
    local where = p and Geo.GetMapName(p.m) or ""
    if dist then
        where = Geo.FormatDistance(dist)
    end
    if e.title then
        return e.name .. " |cff999999<" .. e.title .. ">|r", where
    end
    return e.name, where
end

local function RefreshRows()
    offset = ns.Clamp(offset, 0, math.max(0, #results - ROWS))
    for i = 1, ROWS do
        local row = rows[i]
        local e = results[i + offset]
        row.entry = e
        if e then
            local text, right = RowInfo(e)
            local c = ColourOf(e)
            row.text:SetText(text)
            row.text:SetTextColor(c[1], c[2], c[3])
            row.right:SetText(right or "")
            row.sel:SetShown(e == selected)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function CurrentTab()
    local key = ns.Get("findTab")
    for _, t in ipairs(TABS) do
        if t.key == key then
            return t
        end
    end
    return TABS[1]
end

local function DoSearch()
    local ok, why = DB.Load()
    if not ok then
        results, total = {}, 0
        emptyText:SetText(L.DB_BROKEN)
        emptyText:Show()
        countText:SetText("")
        RefreshRows()
        return
    end
    -- without the database folder, Find still searches your discoveries
    local missing = why == "missing"
    local text = searchBox.edit:GetText()
    local opts = { faction = ns.Get("findFaction") }
    if ns.Get("findThisZone") then
        opts.zone = C_Map.GetBestMapForUnit("player")
    end
    local kinds = CurrentTab().kinds
    nearby = Geo.Squash(text) == "" and (kinds.quest or kinds.npc or kinds.enemy or kinds.object or kinds.place) and true or false
    if nearby then
        -- nothing typed: what's near you, nearest first
        results, total, nearDist = DB.Nearby(kinds, opts)
        nearMap = C_Map.GetBestMapForUnit("player")
    else
        results, total = DB.Search(text, kinds, opts)
        nearDist, nearMap = {}, nil
    end
    offset = 0
    if nearby then
        emptyText:SetText(missing and L.DB_MISSING or L.NEARBY_NONE)
        emptyText:SetShown(#results == 0)
        countText:SetText(#results > 0 and L.NEARBY_COUNT:format(total or #results) or "")
    elseif Geo.Squash(text) == "" then
        emptyText:SetText(missing and L.DB_MISSING or L.FIND_START)
        emptyText:Show()
        countText:SetText("")
    else
        local none = L.NO_RESULTS
        if Scanning() then
            none = none .. "\n\n" .. L.SCAN_SEARCH_NOTE
        end
        emptyText:SetText(missing and L.DB_MISSING or none)
        emptyText:SetShown(#results == 0)
        countText:SetText(L.RESULTS_FMT:format(total or #results))
    end
    if not results[1] or results[1] ~= selected then
        ShowDetail(results[1])
    end
    RefreshRows()
end

-- every search goes through here, so a problem is reported once, not on each key
local function RunSearch()
    ns.Call(DoSearch)
end

-- typing: search a moment after you stop, so it stays smooth
local pendingSearch = false
local function ScheduleSearch()
    if pendingSearch then
        return
    end
    pendingSearch = true
    C_Timer.After(0.25, function()
        pendingSearch = false
        if frame and frame:IsShown() then
            RunSearch()
        end
    end)
end

local function Activate(e)
    if not e then
        return
    end
    local wp = WaypointFor(e)
    if wp then
        Status(L.ADDED:format(WP.Describe(wp)), true)
    else
        Status(L.NO_LOCATION)
    end
end

local function RefreshTabs()
    local current = CurrentTab().key
    for _, b in ipairs(tabs) do
        if b.key == current then
            b:LockHighlight()
            b.bar:Show()
        else
            b:UnlockHighlight()
            b.bar:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Building the window
-- ---------------------------------------------------------------------------
local function Create()
    local w = W()
    frame = CreateFrame("Frame", "WaypointTrackerFindFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop(w.BACKDROP_DIALOG)
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.moved = true
    end)
    frame:Hide()
    tinsert(UISpecialFrames, "WaypointTrackerFindFrame")

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "Icon")
    icon:SetSize(26, 26)
    icon:SetPoint("TOPLEFT", 20, -16)
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(L.FIND_TITLE)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    -- the main window: your waypoints, coordinates and settings
    local waypointsBtn = w.Button(frame, L.OPEN_WAYPOINTS, 130, 22)
    waypointsBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
    waypointsBtn:SetScript("OnClick", function()
        ns.UI.Show()
    end)
    w.AddTooltip(waypointsBtn, L.OPEN_WAYPOINTS, L.OPEN_WAYPOINTS_DESC)
    local routesBtn = w.Button(frame, L.ROUTES_TITLE, 100, 22)
    routesBtn:SetPoint("RIGHT", waypointsBtn, "LEFT", -4, 0)
    routesBtn:SetScript("OnClick", function()
        ns.RoutesUI.Show()
    end)
    w.AddTooltip(routesBtn, L.ROUTES_TITLE, L.ROUTES_DESC)

    -- nearest services ----------------------------------------------------
    local nearLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    nearLabel:SetPoint("TOPLEFT", 24, -56)
    nearLabel:SetText(L.NEAREST)
    local prev
    frame.serviceButtons = {}
    -- the buttons share what's left of the row, so long translations fit
    local serviceWidth = math.min(96, math.floor((WIDTH - 24 - nearLabel:GetStringWidth() - 10 - 24 - (#SERVICES - 1) * 4) / #SERVICES))
    for _, s in ipairs(SERVICES) do
        local b = w.Button(frame, L[s.label], serviceWidth, 22)
        b:SetNormalFontObject(GameFontNormalSmall)
        b:SetHighlightFontObject(GameFontHighlightSmall)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            b:SetPoint("LEFT", nearLabel, "RIGHT", 10, 0)
        end
        b:SetScript("OnClick", function()
            local ok = DB.Load()
            if not ok then
                Status(L.DB_BROKEN)
                return
            end
            GoToNearest(DB.ServiceEntries(s.key))
        end)
        w.AddTooltip(b, L[s.label], L.NEAREST_DESC)
        frame.serviceButtons[#frame.serviceButtons + 1] = b
        b.service = s.key
        prev = b
    end

    -- search box ----------------------------------------------------------
    searchBox = w.Box(frame, LIST_W, L.FIND_HINT)
    searchBox:SetPoint("TOPLEFT", 22, -88)
    searchBox.edit:HookScript("OnTextChanged", function(_, userInput)
        if userInput then
            ScheduleSearch()
        end
    end)
    searchBox.edit:SetScript("OnEnterPressed", function(self)
        RunSearch()
        if results[1] then
            Activate(selected or results[1])
        end
        self:ClearFocus()
    end)

    -- filters
    local faction = w.Check(frame, L.MY_FACTION_ONLY, "findFaction", LIST_W + 34, -86, L.MY_FACTION_ONLY_DESC, 240)
    faction.onChange = ScheduleSearch
    local zoneOnly = w.Check(frame, L.THIS_ZONE_ONLY, "findThisZone", LIST_W + 34, -110, L.THIS_ZONE_ONLY_DESC, 240)
    zoneOnly.onChange = ScheduleSearch

    -- tabs
    tabs = {}
    prev = nil
    for _, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, frame)
        b:SetHeight(22)
        local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("CENTER")
        fs:SetText(L[t.label])
        b:SetFontString(fs)
        b:SetWidth(math.max(60, fs:GetStringWidth() + 20))
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetColorTexture(1, 0.82, 0, 0.9)
        b.bar:SetHeight(2)
        b.bar:SetPoint("BOTTOMLEFT", 4, 0)
        b.bar:SetPoint("BOTTOMRIGHT", -4, 0)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else
            b:SetPoint("TOPLEFT", 22, -120)
        end
        b.key = t.key
        b:SetScript("OnClick", function()
            ns.Set("findTab", t.key)
            RefreshTabs()
            RunSearch()
        end)
        tabs[#tabs + 1] = b
        prev = b
    end
    -- long translations: give every tab the same share of the list's width
    -- (text that still doesn't fit is cut) so they never reach the filters
    local tabsWidth = (#tabs - 1) * 2
    for _, b in ipairs(tabs) do
        tabsWidth = tabsWidth + b:GetWidth()
    end
    if tabsWidth > LIST_W then
        local each = math.floor((LIST_W - (#tabs - 1) * 2) / #tabs)
        for _, b in ipairs(tabs) do
            b:SetWidth(each)
            local fs = b:GetFontString()
            fs:SetWidth(each - 6)
            fs:SetWordWrap(false)
        end
    end

    -- results list ----------------------------------------------------------
    local listBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 20, -146)
    listBg:SetSize(LIST_W + 4, ROWS * ROW_H + 10)
    listBg:SetBackdrop(w.BACKDROP_BOX)
    listBg:SetBackdropColor(0, 0, 0, 0.6)
    listBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    listBg:EnableMouseWheel(true)
    listBg:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        RefreshRows()
    end)

    rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, listBg)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 6, -5 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -6, 0)
        row:RegisterForClicks("LeftButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.12)
        row.sel:Hide()
        row.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.right:SetPoint("RIGHT", -4, 0)
        row.right:SetTextColor(0.75, 0.75, 0.75)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", ns.Safe(function(self)
            ShowDetail(self.entry)
            RefreshRows()
        end))
        row:SetScript("OnDoubleClick", ns.Safe(function(self)
            Activate(self.entry)
        end))
        rows[i] = row
    end
    emptyText = listBg:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 12, -14)
    emptyText:SetPoint("RIGHT", -12, 0)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText(L.FIND_START)

    countText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    countText:SetPoint("TOPRIGHT", listBg, "BOTTOMRIGHT", -4, -4)

    -- detail pane ------------------------------------------------------------
    detail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 10, 0)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 76)
    detail:SetBackdrop(w.BACKDROP_BOX)
    detail:SetBackdropColor(0, 0, 0, 0.6)
    detail:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    detail.name = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    detail.name:SetPoint("TOPLEFT", 10, -10)
    detail.name:SetPoint("RIGHT", -10, 0)
    detail.name:SetJustifyH("LEFT")
    detail.kind = detail:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    detail.kind:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -4)
    detail.kind:SetPoint("RIGHT", -10, 0)
    detail.kind:SetJustifyH("LEFT")
    detail.body = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detail.body:SetPoint("TOPLEFT", detail.kind, "BOTTOMLEFT", 0, -10)
    detail.body:SetPoint("RIGHT", -10, 0)
    detail.body:SetPoint("BOTTOM", detail, "BOTTOM", 0, 96)
    detail.body:SetJustifyH("LEFT")
    detail.body:SetJustifyV("TOP")
    detail.buttons = {}
    for i = 1, 3 do
        local b = w.Button(detail, "", 200, 24)
        b:SetPoint("BOTTOMLEFT", 10, 10 + (3 - i) * 28)
        b:SetPoint("RIGHT", -10, 0)
        b:SetScript("OnClick", function(self)
            if self.action then
                self.action()
            elseif self.targets then
                GoToNearest(self.targets, self.title)
            end
        end)
        b:Hide()
        detail.buttons[i] = b
    end

    -- footer -----------------------------------------------------------------
    frame.status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 24, 50)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)
    local note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 24, 16)
    note:SetPoint("RIGHT", -24, 0)
    note:SetHeight(28)
    note:SetJustifyH("LEFT")
    note:SetJustifyV("BOTTOM")
    note:SetText(L.DB_NOTE)
    frame.note = note
    -- while the quest-name scan runs, the tip line shows how far it is
    local wasScanning
    local function UpdateScanNote()
        local running, pct = Scanning()
        if running then
            note:SetText(L.SCAN_PROGRESS:format(pct))
        else
            note:SetText(L.DB_NOTE)
        end
        if wasScanning and not running then
            -- done: bring the new names in and drop the "still learning" notes
            DB.MergeIfLearned()
            ShowDetail(selected)
        end
        wasScanning = running
    end
    frame.UpdateScanNote = UpdateScanNote
    local scanAcc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        scanAcc = scanAcc + elapsed
        if scanAcc >= 1 then
            scanAcc = 0
            ns.Call(UpdateScanNote)
            -- near you: distances as you walk, and a new list on a new map
            if nearby then
                if C_Map.GetBestMapForUnit("player") ~= nearMap then
                    RunSearch()
                else
                    ns.Call(RefreshRows)
                end
            end
        end
    end)

    -- sharing discoveries
    local shareBtn = w.Button(frame, L.SHARE_DISCOVERIES, 150, 20)
    shareBtn:SetNormalFontObject(GameFontNormalSmall)
    shareBtn:SetHighlightFontObject(GameFontHighlightSmall)
    shareBtn:SetPoint("BOTTOMRIGHT", -24, 48)
    shareBtn:SetScript("OnClick", function()
        Find.ShowShareBox("export")
    end)
    w.AddTooltip(shareBtn, L.SHARE_DISCOVERIES, L.SHARE_DISCOVERIES_DESC)
    local importBtn = w.Button(frame, L.IMPORT, 80, 20)
    importBtn:SetNormalFontObject(GameFontNormalSmall)
    importBtn:SetHighlightFontObject(GameFontHighlightSmall)
    importBtn:SetPoint("RIGHT", shareBtn, "LEFT", -4, 0)
    importBtn:SetScript("OnClick", function()
        Find.ShowShareBox("import")
    end)
    w.AddTooltip(importBtn, L.IMPORT, L.IMPORT_DESC)
    frame.learnedText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.learnedText:SetPoint("RIGHT", importBtn, "LEFT", -8, 0)
    frame.status:SetPoint("RIGHT", frame.learnedText, "LEFT", -8, 0)

    frame:SetScript("OnShow", function()
        frame.learnedText:SetText(ns.Learn and L.LEARNED_COUNT:format(ns.Learn.Count()) or "")
        faction:SetChecked(ns.Get("findFaction") and true or false)
        zoneOnly:SetChecked(ns.Get("findThisZone") and true or false)
        RefreshTabs()
        Status("")
        UpdateScanNote()
        RunSearch()
    end)

    Find.widgets = { search = searchBox.edit, rows = rows, detail = detail, tabs = tabs, faction = faction, zoneOnly = zoneOnly, share = shareBtn, import = importBtn, empty = emptyText, note = frame.note, waypoints = waypointsBtn, routes = routesBtn, count = countText }
end

-- ---------------------------------------------------------------------------
-- Share / import box: a big text box to copy from or paste into
-- ---------------------------------------------------------------------------
local shareBox

local function CreateShareBox()
    local w = W()
    shareBox = CreateFrame("Frame", "WaypointTrackerShareBox", UIParent, "BackdropTemplate")
    shareBox:SetSize(520, 380)
    shareBox:SetPoint("CENTER", 0, 20)
    shareBox:SetFrameStrata("FULLSCREEN_DIALOG")
    shareBox:SetToplevel(true)
    shareBox:EnableMouse(true)
    shareBox:SetMovable(true)
    shareBox:RegisterForDrag("LeftButton")
    shareBox:SetScript("OnDragStart", shareBox.StartMoving)
    shareBox:SetScript("OnDragStop", shareBox.StopMovingOrSizing)
    shareBox:SetBackdrop(w.BACKDROP_DIALOG)
    shareBox:SetBackdropColor(0, 0, 0, 1)
    shareBox:Hide()
    tinsert(UISpecialFrames, "WaypointTrackerShareBox")

    shareBox.title = shareBox:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    shareBox.title:SetPoint("TOPLEFT", 22, -20)
    local close = CreateFrame("Button", nil, shareBox, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    shareBox.help = shareBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    shareBox.help:SetPoint("TOPLEFT", 22, -46)
    shareBox.help:SetPoint("RIGHT", -22, 0)
    shareBox.help:SetJustifyH("LEFT")

    local bg = CreateFrame("Frame", nil, shareBox, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", 18, -86)
    bg:SetPoint("BOTTOMRIGHT", -18, 50)
    bg:SetBackdrop(w.BACKDROP_BOX)
    bg:SetBackdropColor(0, 0, 0, 0.8)
    local scroll = CreateFrame("ScrollFrame", "WaypointTrackerShareScroll", bg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(440)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    scroll:SetScrollChild(edit)
    shareBox.edit = edit

    shareBox.action = w.Button(shareBox, L.IMPORT, 140, 24)
    shareBox.action:SetPoint("BOTTOMRIGHT", -22, 18)
    shareBox.action:SetScript("OnClick", function()
        local text = edit:GetText()
        local n = 0
        -- a few MB is far more than anyone discovers; bigger isn't a share
        if #text <= MAX_IMPORT then
            ns.Call(function()
                n = ns.Learn.Import(text)
            end)
        end
        if n > 0 then
            shareBox.result:SetText(L.IMPORTED:format(n))
            shareBox.result:SetTextColor(0.3, 1, 0.3)
            if frame and frame:IsShown() then
                frame.learnedText:SetText(L.LEARNED_COUNT:format(ns.Learn.Count()))
                RunSearch()
            end
        else
            shareBox.result:SetText(L.IMPORT_NOTHING)
            shareBox.result:SetTextColor(1, 0.35, 0.3)
        end
    end)
    shareBox.result = shareBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    shareBox.result:SetPoint("BOTTOMLEFT", 24, 24)
    shareBox.result:SetPoint("RIGHT", shareBox.action, "LEFT", -8, 0)
    shareBox.result:SetJustifyH("LEFT")
end

-- mode: "export" (copy your discoveries) or "import" (paste someone's)
function Find.ShowShareBox(mode)
    if not shareBox then
        CreateShareBox()
    end
    shareBox.result:SetText("")
    if mode == "export" then
        shareBox.title:SetText(L.SHARE_DISCOVERIES)
        shareBox.help:SetText(ns.Learn.Count() > 0 and L.SHARE_BOX_HELP or L.SHARE_NOTHING)
        shareBox.edit:SetText(ns.Learn.Export())
        shareBox.action:Hide()
        shareBox:Show()
        shareBox.edit:SetFocus()
        shareBox.edit:HighlightText()
    else
        shareBox.title:SetText(L.IMPORT)
        shareBox.help:SetText(L.IMPORT_BOX_HELP)
        shareBox.edit:SetText("")
        shareBox.action:Show()
        shareBox:Show()
        shareBox.edit:SetFocus()
    end
    Find.shareBox = shareBox
end

-- ---------------------------------------------------------------------------
-- Correcting a spot: "Find has it here, but it's really there"
-- ---------------------------------------------------------------------------
local fixBox

local function AfterFix(text, good)
    ns.Call(DB.MergeLearned)
    fixBox.result:SetText(text)
    if good then
        fixBox.result:SetTextColor(0.3, 1, 0.3)
    else
        fixBox.result:SetTextColor(1, 0.35, 0.3)
    end
    fixBox.undo:SetShown(#ns.Learn.Fixes(fixBox.entry.kind, fixBox.entry.id) > 0)
    if frame and frame:IsShown() and selected == fixBox.entry then
        ShowDetail(selected)
        RefreshRows()
    end
    if frame then
        frame.learnedText:SetText(L.LEARNED_COUNT:format(ns.Learn.Count()))
    end
end

local function CreateFixBox()
    local w = W()
    fixBox = CreateFrame("Frame", "WaypointTrackerFixBox", UIParent, "BackdropTemplate")
    fixBox:SetSize(460, 284)
    fixBox:SetPoint("CENTER", 0, 40)
    fixBox:SetFrameStrata("FULLSCREEN_DIALOG")
    fixBox:SetToplevel(true)
    fixBox:EnableMouse(true)
    fixBox:SetMovable(true)
    fixBox:RegisterForDrag("LeftButton")
    fixBox:SetScript("OnDragStart", fixBox.StartMoving)
    fixBox:SetScript("OnDragStop", fixBox.StopMovingOrSizing)
    fixBox:SetBackdrop(w.BACKDROP_DIALOG)
    fixBox:SetBackdropColor(0, 0, 0, 1)
    fixBox:Hide()
    tinsert(UISpecialFrames, "WaypointTrackerFixBox")

    fixBox.title = fixBox:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fixBox.title:SetPoint("TOPLEFT", 22, -20)
    fixBox.title:SetText(L.FIX_TITLE)
    local close = CreateFrame("Button", nil, fixBox, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    fixBox.help = fixBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fixBox.help:SetPoint("TOPLEFT", 22, -48)
    fixBox.help:SetPoint("RIGHT", -22, 0)
    fixBox.help:SetJustifyH("LEFT")

    fixBox.x = w.Box(fixBox, 70, "X")
    fixBox.x:SetPoint("TOPLEFT", 22, -118)
    fixBox.y = w.Box(fixBox, 70, "Y")
    fixBox.y:SetPoint("LEFT", fixBox.x, "RIGHT", 8, 0)
    fixBox.x.edit:SetMaxLetters(8)
    fixBox.y.edit:SetMaxLetters(8)
    fixBox.x.edit:SetScript("OnTabPressed", function()
        fixBox.y.edit:SetFocus()
    end)
    fixBox.here = w.Button(fixBox, L.USE_MY_POSITION, 140, 24)
    fixBox.here:SetPoint("LEFT", fixBox.y, "RIGHT", 10, 0)
    fixBox.here:SetScript("OnClick", function()
        local m, x, y = Geo.GetPlayerMapPosition()
        if not m then
            fixBox.result:SetText(L.FIX_BAD)
            fixBox.result:SetTextColor(1, 0.35, 0.3)
            return
        end
        fixBox.map = m
        fixBox.x.edit:SetText(("%.1f"):format(x * 100))
        fixBox.y.edit:SetText(("%.1f"):format(y * 100))
        fixBox.mapText:SetText(Geo.GetMapName(m) or "")
    end)
    fixBox.mapText = fixBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fixBox.mapText:SetPoint("TOPLEFT", fixBox.x, "BOTTOMLEFT", 2, -4)

    fixBox.save = w.Button(fixBox, L.FIX_SAVE, 150, 24)
    fixBox.save:SetPoint("TOPLEFT", 22, -172)
    fixBox.save:SetScript("OnClick", function()
        local x, y = Geo.ParseNumber(fixBox.x.edit:GetText()), Geo.ParseNumber(fixBox.y.edit:GetText())
        if not (fixBox.map and x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100) then
            fixBox.result:SetText(L.FIX_BAD)
            fixBox.result:SetTextColor(1, 0.35, 0.3)
            return
        end
        local e = fixBox.entry
        if ns.Learn.AddFix(e.kind, e.id, fixBox.wrong, { fixBox.map, x / 100, y / 100 }) then
            AfterFix(L.FIX_SAVED, true)
        else
            AfterFix(L.FIX_FULL)
        end
    end)
    fixBox.gone = w.Button(fixBox, L.FIX_GONE, 200, 24)
    fixBox.gone:SetPoint("LEFT", fixBox.save, "RIGHT", 6, 0)
    fixBox.gone:SetScript("OnClick", function()
        local e = fixBox.entry
        if ns.Learn.AddFix(e.kind, e.id, fixBox.wrong, nil) then
            AfterFix(L.FIX_SAVED, true)
        else
            AfterFix(L.FIX_FULL)
        end
    end)
    fixBox.undo = w.Button(fixBox, L.FIX_UNDO, 240, 24)
    fixBox.undo:SetPoint("TOPLEFT", fixBox.save, "BOTTOMLEFT", 0, -6)
    fixBox.undo:SetScript("OnClick", function()
        local e = fixBox.entry
        ns.Learn.ClearFixes(e.kind, e.id)
        AfterFix(L.FIX_REMOVED, true)
    end)
    fixBox.result = fixBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fixBox.result:SetPoint("TOPLEFT", 22, -238)
    fixBox.result:SetPoint("RIGHT", -22, 0)
    fixBox.result:SetJustifyH("LEFT")
end

-- Opens the box to correct where an NPC or object is. The spot corrected is
-- the one Find leads to (the closest); without one, it adds a spot.
function Find.ShowFixBox(e)
    if not ns.Learn or not Correctable(e) then
        return
    end
    if not fixBox then
        CreateFixBox()
    end
    fixBox.entry = e
    local p = DB.Nearest(DB.Points(e))
    fixBox.wrong = p and { p.m, p.x, p.y } or nil
    fixBox.map = p and p.m or Geo.GetPlayerMapPosition()
    local name = e.name ~= "" and e.name or (p and Geo.GetMapName(p.m)) or ""
    if p then
        fixBox.help:SetText(L.FIX_HELP:format(name, Geo.GetMapName(p.m) or "", p.x * 100, p.y * 100))
    else
        fixBox.help:SetText(L.FIX_HELP_NEW:format(name))
    end
    fixBox.mapText:SetText(fixBox.map and Geo.GetMapName(fixBox.map) or "")
    fixBox.x.edit:SetText("")
    fixBox.y.edit:SetText("")
    fixBox.result:SetText("")
    fixBox.gone:SetShown(p ~= nil)
    fixBox.undo:SetShown(#ns.Learn.Fixes(e.kind, e.id) > 0)
    fixBox:Show()
    Find.fixBox = fixBox
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
function Find.Show(text, tab)
    if not ns.settings then
        return
    end
    -- opens on All unless a tab was asked for (the Quests/NPCs/... buttons)
    ns.Set("findTab", tab or "all")
    if not frame then
        Create()
    end
    local hasText = text and text ~= ""
    if hasText then
        searchBox.edit:SetText(text)
    end
    -- showing it searches (OnShow); if it's already open, search again here
    if frame:IsShown() then
        RefreshTabs()
        RunSearch()
    end
    frame:Show()
    frame:Raise()
    if not hasText then
        searchBox.edit:SetFocus()
    end
end

function Find.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        Find.Show()
    end
end

-- /wp, the minimap button and the button by the arrow: what's near you,
-- with the search box ready for typing. Open already: closes it.
function Find.ToggleNearby()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    if frame then
        searchBox.edit:SetText("")
    end
    Find.Show()
end

-- /wp: your waypoints and Find side by side, the search box ready. Both
-- open already: closes both.
function Find.ToggleBoth()
    local UI = ns.UI
    if frame and frame:IsShown() and UI.IsShown() then
        frame:Hide()
        UI.Hide()
        return
    end
    if frame then
        searchBox.edit:SetText("")
    end
    Find.Show()
    UI.Show()
    -- next to each other, unless you've moved one of them
    if not frame.moved and not ns.Get("windowPos") then
        local half = (WIDTH + UI.WIDTH + 8) / 2
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", half - WIDTH / 2, 40)
        UI.MoveTo(-half + UI.WIDTH / 2, 40)
    end
    frame:Raise()
    searchBox.edit:SetFocus()
end

function Find.IsShown()
    return frame and frame:IsShown() or false
end

function Find.IsNearby()
    return nearby
end

function Find.Activate(e)
    Activate(e)
end

-- "/way <name>": when exactly one thing has that exact name, the arrow goes
-- straight there. Several with that name, or none: Find opens to choose.
local EVERYTHING = { quest = true, npc = true, enemy = true, object = true, item = true, place = true }
function Find.Way(text)
    if DB.Load() then
        local q = Geo.PrepareQuery(text)
        local exact = {}
        for _, e in ipairs(DB.Search(text, EVERYTHING, { faction = ns.Get("findFaction") }, 50)) do
            if e.key == q then
                exact[#exact + 1] = e
            end
        end
        if #exact == 1 then
            local wp = WaypointFor(exact[1])
            if wp then
                ns.Print(L.ADDED:format(WP.Describe(wp)), true)
                return wp
            end
        end
    end
    Find.Show(text)
end

function WaypointTracker_ToggleFind()
    Find.Toggle()
end
