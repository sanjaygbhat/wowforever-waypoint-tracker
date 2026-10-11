-- Find: a database browser for NPCs, quests, objects and quest items
-- that sends the arrow to them. Also "nearest" choices for the places
-- everyone looks for: mailbox, innkeeper, flight
-- master, repair, bank and auction house.
local _, ns = ...
local L, Geo, WP, DB = ns.L, ns.Geo, ns.WP, ns.DB

local Find = {}
ns.Find = Find

local ROW_H = 22
local LIST_W = 286
local MAX_IMPORT = 4 * 1024 * 1024

local frame, searchBox, countText, emptyText, rows, detail, list
local kind, discoveries
local Widgets, Window = ns.Widgets, ns.Window
local results, total = {}, 0
-- with nothing typed, the list shows what's near you: nearby is true then,
-- nearDist has each entry's distance and nearMap the map it was made for
local nearby, nearDist, nearMap = false, {}, nil
local offset = 0
local selected
local tipShown = false

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

-- The background scan for WoW Forever's quest names: running, percent done.
local function Scanning()
    if ns.Learn and ns.Learn.ScanProgress then
        return ns.Learn.ScanProgress()
    end
    return false, 100
end

local function Status(text, good)
    Window.SetStatus(text, good)
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
    if list.items ~= results then
        list.offset = offset
    end
    list.selected = selected
    list:SetItems(results)
    for _, row in ipairs(rows) do
        row.entry = row.item
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
        if frame and Window.IsShown() and Window.GetTab() == "find" and frame:IsShown() then
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
    kind:Refresh()
end

-- ---------------------------------------------------------------------------
-- Building the tab
-- ---------------------------------------------------------------------------
local function Build(content)
    frame = content
    searchBox = Widgets.EditBox(frame, 330, { search = true, placeholder = L.FIND_HINT })
    searchBox:SetPoint("TOPLEFT", 4, -4)
    searchBox.edit:HookScript("OnTextChanged", function(_, userInput)
        if userInput then ScheduleSearch() end
    end)
    if searchBox.edit.clearButton then
        searchBox.edit.clearButton:HookScript("OnClick", ScheduleSearch)
    end
    searchBox.edit:SetScript("OnEnterPressed", ns.Safe(function(self)
        RunSearch()
        if results[1] then Activate(selected or results[1]) end
        self:ClearFocus()
    end))
    kind = Widgets.Dropdown(frame, 114, {
        text = function() return L[CurrentTab().label] end,
        menu = function(root)
            for _, t in ipairs(TABS) do
                root:CreateRadio(L[t.label], function() return CurrentTab().key == t.key end, ns.Safe(function()
                    ns.Set("findTab", t.key)
                    RefreshTabs()
                    RunSearch()
                end))
            end
        end,
    })
    kind:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    local nearest = Widgets.Dropdown(frame, 144, {
        text = function() return L.NEAREST_MENU end,
        menu = function(root)
            for _, s in ipairs(SERVICES) do
                root:CreateButton(L[s.label], ns.Safe(function()
                    if not DB.Load() then Status(L.DB_BROKEN); return end
                    GoToNearest(DB.ServiceEntries(s.key))
                end))
            end
        end,
    })
    nearest:SetPoint("LEFT", kind, "RIGHT", 6, 0)
    Widgets.Tooltip(kind, L.TAB_ALL, L.FIND_KIND_DESC)
    Widgets.Tooltip(nearest, L.NEAREST_MENU, L.NEAREST_DESC)

    local faction = Widgets.Check(frame, L.MY_FACTION_ONLY, "findFaction", L.MY_FACTION_ONLY_DESC, 180)
    faction:SetPoint("TOPLEFT", 2, -34)
    faction.onChange = ScheduleSearch
    local zoneOnly = Widgets.Check(frame, L.THIS_ZONE_ONLY, "findThisZone", L.THIS_ZONE_ONLY_DESC, 170)
    zoneOnly:SetPoint("TOPLEFT", 214, -34)
    zoneOnly.onChange = ScheduleSearch
    discoveries = Widgets.Dropdown(frame, 190, {
        text = function() return L.LEARNED_COUNT:format(ns.Learn and ns.Learn.Count() or 0) end,
        menu = function(root)
            root:CreateButton(L.SHARE_DISCOVERIES, ns.Safe(function() Find.ShowShareBox("export") end))
            root:CreateButton(L.IMPORT_DISCOVERIES, ns.Safe(function() Find.ShowShareBox("import") end))
        end,
    })
    discoveries:SetPoint("TOPRIGHT", -4, -35)
    Widgets.Tooltip(discoveries, L.DISCOVERIES_MENU, L.SHARE_DISCOVERIES_DESC)

    local listBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 4, -66)
    listBg:SetPoint("BOTTOMLEFT", 4, 34)
    listBg:SetWidth(LIST_W)
    listBg:SetBackdrop(Widgets.BACKDROP_BOX)
    listBg:SetBackdropColor(0, 0, 0, 0.6)
    listBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    list = Widgets.List(listBg, {
        rowHeight = ROW_H, emptyText = L.FIND_START,
        rowInit = function(row)
            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(1, 0.82, 0, 0.12)
            row.sel:Hide()
            row.right = Widgets.Label(row, "", "GameFontHighlightSmall")
            row.right:SetPoint("RIGHT", -4, 0)
            row.right:SetTextColor(0.75, 0.75, 0.75)
            row.text = Widgets.Label(row, "")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
            row.text:SetWordWrap(false)
        end,
        rowUpdate = function(row, e, _, isSelected)
            row.entry = e
            local text, right = RowInfo(e)
            local c = ColourOf(e)
            row.text:SetText(text)
            row.text:SetTextColor(c[1], c[2], c[3])
            row.right:SetText(right or "")
            row.sel:SetShown(isSelected)
        end,
        onClick = function(_, e, button)
            if button == "LeftButton" then ShowDetail(e); RefreshRows() end
        end,
        onDoubleClick = function(_, e) Activate(e) end,
    })
    list:SetPoint("TOPLEFT", 5, -5)
    list:SetPoint("BOTTOMRIGHT", -5, 5)
    rows, emptyText = list.rows, list.emptyText
    emptyText:SetJustifyH("LEFT")
    countText = Widgets.Label(frame, "", "GameFontDisableSmall")
    countText:SetPoint("BOTTOMLEFT", 8, 4)
    countText:SetWidth(120)
    countText:SetWordWrap(false)

    detail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 10, 0)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 34)
    detail:SetBackdrop(Widgets.BACKDROP_BOX)
    detail:SetBackdropColor(0, 0, 0, 0.6)
    detail:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    detail.name = Widgets.Label(detail, "", "GameFontNormalLarge")
    detail.name:SetPoint("TOPLEFT", 10, -10)
    detail.name:SetPoint("RIGHT", -10, 0)
    detail.kind = Widgets.Label(detail, "", "GameFontDisableSmall")
    detail.kind:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -4)
    detail.kind:SetPoint("RIGHT", -10, 0)
    detail.body = Widgets.Label(detail, "", "GameFontHighlightSmall")
    detail.body:SetPoint("TOPLEFT", detail.kind, "BOTTOMLEFT", 0, -10)
    detail.body:SetPoint("RIGHT", -10, 0)
    detail.body:SetPoint("BOTTOM", detail, "BOTTOM", 0, 96)
    detail.body:SetJustifyV("TOP")
    detail.buttons = {}
    for i = 1, 3 do
        local b = Widgets.Button(detail, "", 200, 24)
        b:SetPoint("BOTTOMLEFT", 10, 10 + (3 - i) * 28)
        b:SetPoint("RIGHT", -10, 0)
        b:SetScript("OnClick", ns.Safe(function(self)
            if self.action then self.action()
            elseif self.targets then GoToNearest(self.targets, self.title) end
        end))
        b:SetScript("OnEnter", ns.Safe(function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self:GetText(), 1, 1, 1)
            local help = self.action and selected and L.FIX_HELP_NEW:format(selected.name) or L.NEAREST_DESC
            GameTooltip:AddLine(help, 1, 0.82, 0, true)
            GameTooltip:Show()
        end))
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:Hide()
        detail.buttons[i] = b
    end

    local note = Widgets.Label(frame, "", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", countText, "BOTTOMRIGHT", 12, 0)
    note:SetPoint("RIGHT", -8, 0)
    note:SetHeight(28)
    note:SetJustifyH("RIGHT")
    note:SetJustifyV("BOTTOM")
    local wasScanning
    frame.UpdateScanNote = function()
        local running, pct = Scanning()
        note:SetText(running and L.SCAN_PROGRESS:format(pct) or "")
        if wasScanning and not running then
            DB.MergeIfLearned()
            ShowDetail(selected)
        end
        wasScanning = running
    end
    Find.widgets = { search = searchBox.edit, rows = rows, detail = detail, kind = kind,
        nearest = nearest, faction = faction, zoneOnly = zoneOnly, discoveries = discoveries,
        empty = emptyText, note = note, count = countText, list = list }
end

Window.RegisterTab{
    key = "find", order = 2, title = L.FIND_TITLE, build = Build,
    onShow = function()
        RefreshTabs()
        discoveries:Refresh()
        Status("")
        if not tipShown then
            tipShown = true
            Status(L.DB_NOTE, "info")
        end
        frame.UpdateScanNote()
        RunSearch()
    end,
    onUpdate = function()
        if not frame:IsShown() then return end
        frame.UpdateScanNote()
        discoveries:Refresh()
        if nearby and C_Map.GetBestMapForUnit("player") ~= nearMap then RunSearch()
        else RefreshRows() end
    end,
}

-- ---------------------------------------------------------------------------
-- Share / import box: a big text box to copy from or paste into
-- ---------------------------------------------------------------------------
-- mode: "export" (copy your discoveries) or "import" (paste someone's)
function Find.ShowShareBox(mode)
    if not ns.Learn then return end
    if not Window.Show("find") then return end
    local exporting = mode == "export"
    local box = Window.PushPage("find", {
        key = exporting and "share" or "import",
        title = exporting and L.SHARE_DISCOVERIES or L.IMPORT,
        build = function(page)
            page.help = Widgets.Label(page, "", "GameFontHighlightSmall")
            page.help:SetPoint("TOPLEFT", 8, -8)
            page.help:SetPoint("RIGHT", -8, 0)
            local area = Widgets.TextArea(page)
            area:SetPoint("TOPLEFT", page.help, "BOTTOMLEFT", 0, -12)
            area:SetPoint("BOTTOMRIGHT", -8, 44)
            page.edit = area.edit
            page.action = Widgets.Button(page, L.IMPORT, 140, 24)
            page.action:SetPoint("BOTTOMRIGHT", -8, 8)
            Widgets.Tooltip(page.action, L.IMPORT, L.IMPORT_DESC)
            page.result = Widgets.Label(page, "", "GameFontHighlightSmall")
            page.result:SetPoint("BOTTOMLEFT", 8, 14)
            page.result:SetPoint("RIGHT", page.action, "LEFT", -8, 0)
            page.action:SetScript("OnClick", ns.Safe(function()
                local text, n = page.edit:GetText(), 0
                if #text <= MAX_IMPORT then n = ns.Learn.Import(text) end
                page.result:SetText(n > 0 and L.IMPORTED:format(n) or L.IMPORT_NOTHING)
                if n > 0 then
                    page.result:SetTextColor(0.3, 1, 0.3)
                    discoveries:Refresh()
                    RunSearch()
                else
                    page.result:SetTextColor(1, 0.35, 0.3)
                end
            end))
        end,
    })
    box.help:SetText(exporting and (ns.Learn.Count() > 0 and L.SHARE_BOX_HELP or L.SHARE_NOTHING) or L.IMPORT_BOX_HELP)
    box.edit:SetText(exporting and ns.Learn.Export() or "")
    box.action:SetShown(not exporting)
    box.result:SetText("")
    Find.shareBox = box
    box.edit:SetFocus()
    if exporting then box.edit:HighlightText() end
end

-- ---------------------------------------------------------------------------
-- Correcting a spot: "Find has it here, but it's really there"
-- ---------------------------------------------------------------------------
local function AfterFix(fixBox, text, good)
    ns.Call(DB.MergeLearned)
    fixBox.result:SetText(text)
    if good then
        fixBox.result:SetTextColor(0.3, 1, 0.3)
    else
        fixBox.result:SetTextColor(1, 0.35, 0.3)
    end
    fixBox.undo:SetShown(#ns.Learn.Fixes(fixBox.entry.kind, fixBox.entry.id) > 0)
    if frame and selected == fixBox.entry then
        ShowDetail(selected)
        RefreshRows()
    end
    if frame then
        discoveries:Refresh()
    end
end

local function BuildFixBox(fixBox)
    local w = Widgets
    fixBox.help = fixBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fixBox.help:SetPoint("TOPLEFT", 8, -8)
    fixBox.help:SetPoint("RIGHT", -8, 0)
    fixBox.help:SetJustifyH("LEFT")

    fixBox.x = w.EditBox(fixBox, 70, { placeholder = "X", maxLetters = 8 })
    fixBox.x:SetPoint("TOPLEFT", fixBox.help, "BOTTOMLEFT", 0, -16)
    fixBox.y = w.EditBox(fixBox, 70, { placeholder = "Y", maxLetters = 8 })
    fixBox.y:SetPoint("LEFT", fixBox.x, "RIGHT", 8, 0)
    fixBox.x.edit:SetMaxLetters(8)
    fixBox.y.edit:SetMaxLetters(8)
    fixBox.x.edit:SetScript("OnTabPressed", function()
        fixBox.y.edit:SetFocus()
    end)
    fixBox.here = w.Button(fixBox, L.USE_MY_POSITION, 140, 24)
    fixBox.here:SetPoint("LEFT", fixBox.y, "RIGHT", 10, 0)
    w.Tooltip(fixBox.here, L.USE_MY_POSITION, L.USE_MY_POSITION_DESC)
    fixBox.here:SetScript("OnClick", ns.Safe(function()
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
    end))
    fixBox.mapText = fixBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fixBox.mapText:SetPoint("TOPLEFT", fixBox.x, "BOTTOMLEFT", 2, -4)

    fixBox.save = w.Button(fixBox, L.FIX_SAVE, 150, 24)
    fixBox.save:SetPoint("TOPLEFT", fixBox.mapText, "BOTTOMLEFT", -2, -16)
    fixBox.save:SetScript("OnClick", ns.Safe(function()
        local x, y = Geo.ParseNumber(fixBox.x.edit:GetText()), Geo.ParseNumber(fixBox.y.edit:GetText())
        if not (fixBox.map and x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100) then
            fixBox.result:SetText(L.FIX_BAD)
            fixBox.result:SetTextColor(1, 0.35, 0.3)
            return
        end
        local e = fixBox.entry
        if ns.Learn.AddFix(e.kind, e.id, fixBox.wrong, { fixBox.map, x / 100, y / 100 }) then
            AfterFix(fixBox, L.FIX_SAVED, true)
        else
            AfterFix(fixBox, L.FIX_FULL)
        end
    end))
    fixBox.gone = w.Button(fixBox, L.FIX_GONE, 200, 24)
    fixBox.gone:SetPoint("LEFT", fixBox.save, "RIGHT", 6, 0)
    fixBox.gone:SetScript("OnEnter", ns.Safe(function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L.FIX_GONE, 1, 1, 1)
        GameTooltip:AddLine(fixBox.help:GetText(), 1, 0.82, 0, true)
        GameTooltip:Show()
    end))
    fixBox.gone:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    fixBox.gone:SetScript("OnClick", ns.Safe(function()
        local e = fixBox.entry
        if ns.Learn.AddFix(e.kind, e.id, fixBox.wrong, nil) then
            AfterFix(fixBox, L.FIX_SAVED, true)
        else
            AfterFix(fixBox, L.FIX_FULL)
        end
    end))
    fixBox.undo = w.Button(fixBox, L.FIX_UNDO, 240, 24)
    fixBox.undo:SetPoint("TOPLEFT", fixBox.save, "BOTTOMLEFT", 0, -6)
    fixBox.undo:SetScript("OnClick", ns.Safe(function()
        local e = fixBox.entry
        ns.Learn.ClearFixes(e.kind, e.id)
        AfterFix(fixBox, L.FIX_REMOVED, true)
    end))
    fixBox.result = fixBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fixBox.result:SetPoint("TOPLEFT", fixBox.undo, "BOTTOMLEFT", 0, -12)
    fixBox.result:SetPoint("RIGHT", -22, 0)
    fixBox.result:SetJustifyH("LEFT")
    w.Tooltip(fixBox.save, L.FIX_SAVE, L.FIX_SAVED)
    w.Tooltip(fixBox.undo, L.FIX_UNDO, L.FIX_REMOVED)
end

-- Opens the box to correct where an NPC or object is. The spot corrected is
-- the one Find leads to (the closest); without one, it adds a spot.
function Find.ShowFixBox(e)
    if not ns.Learn or not Correctable(e) then
        return
    end
    if not Window.Show("find") then return end
    local fixBox = Window.PushPage("find", { key = "fix", title = L.FIX_TITLE, build = BuildFixBox })
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
    Find.fixBox = fixBox
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
function Find.Show(text, tab)
    if not ns.settings then return end
    if not Window.Show("find") then return end
    Window.PopAll("find")
    ns.Set("findTab", tab or "all")
    searchBox.edit:SetText(text or "")
    RefreshTabs()
    RunSearch()
    if text and text ~= "" then searchBox.edit:ClearFocus()
    else searchBox.edit:SetFocus() end
end

function Find.Toggle()
    Window.Toggle("find")
end

function Find.IsShown()
    return Window.IsShown() and Window.GetTab() == "find"
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
                if not ns.Get("chatMessages") then
                    ns.Print(L.ADDED:format(WP.Describe(wp)), true)
                end
                return wp
            end
        end
    end
    Find.Show(text)
end
