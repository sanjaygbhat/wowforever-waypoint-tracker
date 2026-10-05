-- The window. Same look as WoW Translate's settings panel: a classic dialog
-- box, gold headings, plain checkboxes and sliders.
--
-- Left: everything most players need (set a waypoint, your waypoints, arrow
-- basics). "Show more options" opens a second panel on the right.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 420, 590
local ADV_WIDTH = 400
local ROWS = 6
local ROW_HEIGHT = 22

local BACKDROP_DIALOG = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local BACKDROP_BOX = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local BACKDROP_SLIDER = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

local refreshers = {} -- functions that re-read settings into widgets
local frame, advanced

-- ---------------------------------------------------------------------------
-- Widget helpers
-- ---------------------------------------------------------------------------
local function AddTooltip(widget, titleText, body)
    if not body or body == "" then
        return
    end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(titleText, 1, 1, 1)
        GameTooltip:AddLine(body, 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function Header(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    return fs
end

local function Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height or 24)
    b:SetText(text)
    return b
end

-- Checkbox bound to a setting.
local function Check(parent, label, key, x, y, desc, labelWidth)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    text:SetJustifyH("LEFT")
    text:SetWidth(labelWidth or 300)
    text:SetWordWrap(false)
    text:SetText(label)
    cb.label = text
    -- make the text clickable too
    cb:SetHitRectInsets(0, -math.min(text:GetStringWidth() + 4, labelWidth or 300), 0, 0)
    cb:SetScript("OnClick", function(self)
        PlaySound((SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856)
        if key then
            ns.Set(key, self:GetChecked() and true or false)
        end
        if self.onChange then
            self.onChange(self:GetChecked() and true or false)
        end
    end)
    AddTooltip(cb, label, desc)
    cb.settingKey = key
    UI.allChecks = UI.allChecks or {}
    UI.allChecks[#UI.allChecks + 1] = cb
    if key then
        refreshers[#refreshers + 1] = function()
            cb:SetChecked(ns.Get(key) and true or false)
        end
    end
    return cb
end

-- Slider bound to a setting. fmt(value) -> text
local function Slider(parent, label, key, minV, maxV, step, x, y, width, fmt, desc)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 44)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local title = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 2, 0)
    title:SetText(label)

    local valueText = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("TOPRIGHT", -2, 0)

    local s = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(17)
    s:SetPoint("TOPLEFT", 0, -16)
    s:SetPoint("TOPRIGHT", 0, -16)
    s:SetBackdrop(BACKDROP_SLIDER)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouseWheel(true)

    local updating = false
    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(fmt(value))
        if not updating and key then
            ns.Set(key, value)
        end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(ns.Clamp(self:GetValue() + delta * step, minV, maxV))
    end)
    AddTooltip(s, label, desc)

    refreshers[#refreshers + 1] = function()
        updating = true
        local v = tonumber(ns.Get(key)) or minV
        s:SetValue(v)
        valueText:SetText(fmt(v))
        updating = false
    end
    holder.slider = s
    return holder
end

-- Text box with the same dark style as WoW Translate.
local function Box(parent, width, placeholder)
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetSize(width, 26)
    bg:SetBackdrop(BACKDROP_BOX)
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    local edit = CreateFrame("EditBox", nil, bg)
    edit:SetPoint("TOPLEFT", 7, -4)
    edit:SetPoint("BOTTOMRIGHT", -7, 4)
    edit:SetFontObject(ChatFontNormal)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(80)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        bg:SetBackdropBorderColor(1, 0.82, 0, 1)
        self:HighlightText()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        bg:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        self:HighlightText(0, 0)
    end)

    if placeholder then
        local ph = edit:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        ph:SetPoint("LEFT", 1, 0)
        ph:SetText(placeholder)
        edit.placeholder = ph
        edit:HookScript("OnTextChanged", function(self)
            ph:SetShown(self:GetText() == "")
        end)
    end
    bg.edit = edit
    return bg
end

-- "< Option >" selector like WoW Translate's language picker.
local function Cycler(parent, label, key, options, x, y, width, desc)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 46)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local title = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 2, 0)
    title:SetText(label)

    local prev = CreateFrame("Button", nil, holder)
    prev:SetSize(24, 24)
    prev:SetPoint("TOPLEFT", 0, -16)
    prev:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prev:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prev:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local display = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    display:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    display:SetWidth(width - 70)
    display:SetJustifyH("CENTER")

    local nextB = CreateFrame("Button", nil, holder)
    nextB:SetSize(24, 24)
    nextB:SetPoint("LEFT", display, "RIGHT", 6, 0)
    nextB:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextB:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextB:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local function Index()
        local cur = ns.Get(key)
        for i, o in ipairs(options) do
            if o.value == cur then
                return i
            end
        end
        return 1
    end
    local function Step(delta)
        local i = Index() + delta
        if i < 1 then
            i = #options
        elseif i > #options then
            i = 1
        end
        PlaySound((SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856)
        ns.Set(key, options[i].value)
    end
    prev:SetScript("OnClick", function()
        Step(-1)
    end)
    nextB:SetScript("OnClick", function()
        Step(1)
    end)
    AddTooltip(prev, label, desc)
    AddTooltip(nextB, label, desc)

    refreshers[#refreshers + 1] = function()
        display:SetText(options[Index()].text)
    end
    holder.nextButton = nextB
    return holder
end

-- shared with the Find window
UI.W = {
    AddTooltip = AddTooltip,
    Slider = Slider,
    Header = Header,
    Button = Button,
    Check = Check,
    Box = Box,
    BACKDROP_DIALOG = BACKDROP_DIALOG,
    BACKDROP_BOX = BACKDROP_BOX,
}

local function Percent(v)
    return ("%d%%"):format(math.floor(v * 100 + 0.5))
end
UI.W.Percent = Percent

local function Yards(v)
    return Geo.FormatDistance(v)
end

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
local zoneBox, xBox, yBox, noteBox, statusText
local selectedZone -- mapID picked in the zone box
local zoneList -- dropdown
local rows = {}
local listOffset = 0
local emptyText, moreText

local function SetStatus(text, good)
    statusText:SetText(text or "")
    if good then
        statusText:SetTextColor(0.3, 1, 0.3)
    else
        statusText:SetTextColor(1, 0.35, 0.3)
    end
end

local function SelectZone(id)
    selectedZone = id
    zoneBox.edit.ignoreChange = true
    zoneBox.edit:SetText(id and Geo.GetMapName(id) or "")
    zoneBox.edit:SetCursorPosition(0)
    zoneBox.edit.ignoreChange = false
end

-- Search dropdown: zones and places (quests, flight masters, ...) ----------
local ZONE_ROWS = 10
local zoneResults = {}
local zoneScroll = 0
local zoneCursor = 1 -- highlighted row (keyboard)

local PLACE_COLOURS = {
    quest = { 1, 0.82, 0 },
    turnin = { 1, 0.82, 0 },
    flight = { 0.45, 1, 0.45 },
    dungeon = { 0.6, 0.8, 1 },
    poi = { 0.8, 0.8, 1 },
    rare = { 1, 0.55, 0.25 },
}

-- One list: with nothing typed it shows where you are, then your quests,
-- then every zone. When typing, the best matches of any kind come first.
local function BuildResults(text)
    local zones = Geo.SearchZones(text or "")
    local places = ns.Places and ns.Places.Search(text or "") or {}
    local out = {}
    if Geo.Squash(text or "") == "" then
        local current = C_Map.GetBestMapForUnit("player")
        for _, z in ipairs(zones) do
            if z.id == current then
                out[#out + 1] = { zone = z, here = true }
            end
        end
        for _, p in ipairs(places) do
            out[#out + 1] = { place = p }
        end
        for _, z in ipairs(zones) do
            if z.id ~= current then
                out[#out + 1] = { zone = z }
            end
        end
        return out
    end
    local i, j = 1, 1
    while i <= #zones or j <= #places do
        local z, p = zones[i], places[j]
        if z and (not p or (z.score or 99) <= (p.score or 99)) then
            out[#out + 1] = { zone = z }
            i = i + 1
        else
            out[#out + 1] = { place = p }
            j = j + 1
        end
    end
    return out
end

local function RefreshZoneList()
    for i = 1, ZONE_ROWS do
        local b = zoneList.buttons[i]
        local r = zoneResults[i + zoneScroll]
        b.result = r
        if r then
            if r.zone then
                b.text:SetText(r.zone.name)
                b.text:SetTextColor(1, 1, 1)
                b.sub:SetText(r.here and L.YOU_ARE_HERE or Geo.ZoneSubtitle(r.zone))
            else
                local p = r.place
                local c = PLACE_COLOURS[p.kind] or PLACE_COLOURS.poi
                b.text:SetText(p.name)
                b.text:SetTextColor(c[1], c[2], c[3])
                b.sub:SetText(("%s - %s"):format(ns.Places.Label(p), Geo.GetMapName(p.m)))
            end
            b.cursor:SetShown(i + zoneScroll == zoneCursor)
            b:Show()
        else
            b:Hide()
        end
    end
    zoneList.empty:SetShown(#zoneResults == 0)
    zoneList.more:SetShown(#zoneResults > zoneScroll + ZONE_ROWS)
end

local function ShowZoneList(text)
    zoneResults = BuildResults(text)
    zoneScroll = 0
    zoneCursor = 1
    RefreshZoneList()
    zoneList:Show()
end

local function MoveCursor(delta)
    if #zoneResults == 0 then
        return
    end
    zoneCursor = ns.Clamp(zoneCursor + delta, 1, #zoneResults)
    if zoneCursor <= zoneScroll then
        zoneScroll = zoneCursor - 1
    elseif zoneCursor > zoneScroll + ZONE_ROWS then
        zoneScroll = zoneCursor - ZONE_ROWS
    end
    RefreshZoneList()
end

local AddPlace -- defined below (needs the status line)

local function PickResult(r)
    if not r then
        return
    end
    zoneList:Hide()
    if r.zone then
        SelectZone(r.zone.id)
        zoneBox.edit:ClearFocus()
        xBox.edit:SetFocus()
    else
        zoneBox.edit:ClearFocus()
        AddPlace(r.place)
    end
end

local function CreateZoneList()
    zoneList = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    zoneList:SetBackdrop(BACKDROP_BOX)
    zoneList:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    zoneList:SetFrameStrata("FULLSCREEN_DIALOG")
    zoneList:SetPoint("TOPLEFT", zoneBox, "BOTTOMLEFT", 0, 2)
    zoneList:SetPoint("TOPRIGHT", zoneBox, "BOTTOMRIGHT", 0, 2)
    zoneList:SetHeight(ZONE_ROWS * 20 + 22)
    zoneList:EnableMouseWheel(true)
    zoneList:Hide()
    zoneList.buttons = {}
    for i = 1, ZONE_ROWS do
        local b = CreateFrame("Button", nil, zoneList)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 20)
        b:SetPoint("TOPRIGHT", -5, -5 - (i - 1) * 20)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.cursor = b:CreateTexture(nil, "BACKGROUND")
        b.cursor:SetAllPoints()
        b.cursor:SetColorTexture(1, 0.82, 0, 0.15)
        b.cursor:Hide()
        b.sub = b:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        b.sub:SetPoint("RIGHT", -4, 0)
        b.sub:SetJustifyH("RIGHT")
        b.sub:SetWordWrap(false)
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        b.text:SetPoint("LEFT", 4, 0)
        b.text:SetPoint("RIGHT", b.sub, "LEFT", -8, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(self)
            PickResult(self.result)
        end)
        zoneList.buttons[i] = b
    end
    zoneList.empty = zoneList:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    zoneList.empty:SetPoint("TOP", 0, -10)
    zoneList.empty:SetText(L.NO_ZONES_FOUND)
    zoneList.more = zoneList:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    zoneList.more:SetPoint("BOTTOMRIGHT", -8, 5)
    zoneList.more:SetText(L.MORE_BELOW)
    zoneList:SetScript("OnMouseWheel", function(_, delta)
        zoneScroll = ns.Clamp(zoneScroll - delta, 0, math.max(0, #zoneResults - ZONE_ROWS))
        RefreshZoneList()
    end)
end

-- Adding a waypoint --------------------------------------------------------
local function ReadCoord(box)
    local n = Geo.ParseNumber(box.edit:GetText())
    if n and n >= 0 and n <= 100 then
        return n
    end
end

-- The zone, X and Y typed in the window, checked. Shows what's wrong and
-- returns nil if they don't make a spot. With allowBlank, empty X and Y
-- return "blank" instead of an error.
local function ReadSpot(allowBlank)
    local blank = ns.Trim(xBox.edit:GetText()) == "" and ns.Trim(yBox.edit:GetText()) == ""
    if blank and allowBlank then
        return "blank"
    end
    local zoneText = ns.Trim(zoneBox.edit:GetText())
    local mapID = selectedZone
    if mapID and Geo.GetMapName(mapID) ~= zoneText then
        mapID = nil
    end
    if not mapID and zoneText ~= "" then
        local extra
        mapID, extra = Geo.FindZone(zoneText)
        local suggestions = type(extra) == "table" and extra or nil
        if not mapID then
            if suggestions and #suggestions > 0 then
                SetStatus(L.DID_YOU_MEAN:format(table.concat(suggestions, ", ")))
            else
                SetStatus(L.UNKNOWN_ZONE:format(zoneText))
            end
            return
        end
        SelectZone(mapID)
    end
    if not mapID then
        SetStatus(L.NO_ZONE_SELECTED)
        return
    end
    local x, y = ReadCoord(xBox), ReadCoord(yBox)
    if not x or not y then
        SetStatus(blank and L.NO_COORDS or L.INVALID_COORDS)
        return
    end
    return mapID, x / 100, y / 100
end

local function SubmitWaypoint()
    local mapID, x, y = ReadSpot()
    if not mapID then
        return
    end
    local wp = WP.Add(mapID, x, y, { title = noteBox.edit:GetText() })
    if wp then
        SetStatus(L.ADDED:format(WP.Describe(wp)), true)
        xBox.edit:SetText("")
        yBox.edit:SetText("")
        noteBox.edit:SetText("")
        xBox.edit:ClearFocus()
        yBox.edit:ClearFocus()
        noteBox.edit:ClearFocus()
    else
        SetStatus(L.INVALID_COORDS)
    end
end

-- Picking a quest, flight master, ... sets the waypoint straight away.
AddPlace = function(p)
    local wp = WP.Add(p.m, p.x, p.y, { title = p.name, source = "place" })
    if wp then
        SelectZone(p.m)
        SetStatus(L.ADDED:format(WP.Describe(wp)), true)
    end
end

-- Share what's typed (or, with X and Y empty, where you stand) without
-- setting a waypoint.
local function ShareTyped(button)
    local mapID, x, y = ReadSpot(true)
    local title = noteBox.edit:GetText()
    local spot
    if mapID == "blank" then
        spot = ns.Share.MySpot(title)
        if not spot then
            SetStatus(L.NO_POSITION)
            return
        end
    elseif mapID then
        spot = ns.Share.Spot(mapID, x, y, title)
    end
    if spot then
        SetStatus("")
        ns.Share.ShowMenu(button, spot)
    end
end

local function UseMyPosition()
    local mapID, x, y = Geo.GetPlayerMapPosition()
    if not mapID then
        SetStatus(L.NO_POSITION)
        return
    end
    SelectZone(mapID)
    xBox.edit:SetText(("%.1f"):format(x * 100))
    yBox.edit:SetText(("%.1f"):format(y * 100))
    SetStatus("")
end

-- Pasting "45.2 67.8" (or "/way 45.2 67.8") into X fills both boxes.
local function SmartPaste(self, userInput)
    if not userInput then
        return
    end
    local text = self:GetText()
    -- only react to two numbers ("45.2 67.8", "45.2, 67.8", "45.2,67.8");
    -- a lone "45,2" is a European decimal and stays as it is
    if not (text:find("%d[%s;]+%d") or text:find("%d,%s+%d") or text:find("%d%.%d*,%d")) then
        return
    end
    local zone, x, y, rest = Geo.ParseWayArgs((text:gsub("^/%S+%s*", "")))
    if x and y then
        xBox.edit:SetText(("%g"):format(x))
        yBox.edit:SetText(("%g"):format(y))
        if rest and rest ~= "" then
            noteBox.edit:SetText(rest)
        end
        if zone and zone ~= "" then
            local id = Geo.FindZone(zone)
            if id then
                SelectZone(id)
            end
        end
        yBox.edit:SetFocus()
        yBox.edit:SetCursorPosition(#yBox.edit:GetText())
    end
end

-- Waypoint list ------------------------------------------------------------
local function RefreshList()
    if not frame or not frame:IsShown() then
        return
    end
    local list = WP.List()
    local activeWp = WP.GetActive()
    listOffset = ns.Clamp(listOffset, 0, math.max(0, #list - ROWS))
    -- newest first reads better
    for i = 1, ROWS do
        local row = rows[i]
        local wp = list[#list - listOffset - i + 1]
        if wp then
            row.wp = wp
            local zone = Geo.GetMapName(wp.m)
            local coordsText = Geo.FormatCoords(wp.x, wp.y)
            if wp.title then
                row.text:SetText(("%s  |cff999999%s %s|r"):format(wp.title, zone, coordsText))
            else
                row.text:SetText(("%s  |cff999999%s|r"):format(zone, coordsText))
            end
            local dist = Geo.GetVector(wp)
            row.dist:SetText(dist and Geo.FormatDistance(dist) or "")
            local isActive = wp == activeWp
            row.marker:SetVertexColor(isActive and 1 or 0.55, isActive and 0.82 or 0.8, isActive and 0 or 1)
            row.activeBg:SetShown(isActive)
            row:Show()
        else
            row.wp = nil
            row:Hide()
        end
    end
    emptyText:SetShown(#list == 0)
    moreText:SetShown(#list > ROWS)
end

local function CreateRow(parent, i, y)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", parent, "RIGHT", -22, 0)
    row:RegisterForClicks("LeftButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.activeBg = row:CreateTexture(nil, "BACKGROUND")
    row.activeBg:SetAllPoints()
    row.activeBg:SetColorTexture(1, 0.82, 0, 0.10)

    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetTexture(ns.MEDIA .. "Pin")
    row.marker:SetSize(14, 14)
    row.marker:SetPoint("LEFT", 2, 0)

    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(18, 18)
    row.remove:SetPoint("RIGHT", -2, 0)
    row.remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    row.remove:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    row.remove:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    row.remove:SetScript("OnClick", function()
        if row.wp then
            WP.Remove(row.wp)
        end
    end)
    row.remove:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L.REMOVE)
        GameTooltip:Show()
    end)
    row.remove:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row.share = Button(row, L.SHARE, 56, 18)
    row.share:SetNormalFontObject(GameFontNormalSmall)
    row.share:SetHighlightFontObject(GameFontHighlightSmall)
    row.share:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    row.share:SetScript("OnClick", function(self)
        if row.wp then
            ns.Share.ShowMenu(self, row.wp)
        end
    end)
    AddTooltip(row.share, L.SHARE_TITLE, L.SHARE_DESC)

    row.dist = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.dist:SetPoint("RIGHT", row.share, "LEFT", -6, 0)
    row.dist:SetTextColor(0.8, 0.8, 0.8)

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.marker, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.dist, "LEFT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        if not self.wp then
            return
        end
        if IsShiftKeyDown() then
            ns.Share.ToChatBox(self.wp)
        else
            WP.SetActive(self.wp)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.wp then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(WP.ShortName(self.wp), 1, 0.82, 0)
        GameTooltip:AddLine(("%s  %s"):format(Geo.GetMapName(self.wp.m), Geo.FormatCoords(self.wp.x, self.wp.y)), 1, 1, 1)
        GameTooltip:AddLine(L.ROW_TOOLTIP_CLICK, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L.ROW_TOOLTIP_SHARE, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L.ROW_TOOLTIP_REMOVE, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row:Hide()
    return row
end

local function SavePosition(self)
    local point, _, relPoint, x, y = self:GetPoint()
    if point then
        ns.Set("windowPos", { point, relPoint, x, y })
    end
end

local function CreateMain()
    frame = CreateFrame("Frame", "WaypointTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop(BACKDROP_DIALOG)
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:Hide()
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    tinsert(UISpecialFrames, "WaypointTrackerFrame")

    local point, rel, x, y = ns.SavedPoint(ns.Get("windowPos"))
    if point then
        frame:SetPoint(point, UIParent, rel, x, y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -120, 40)
    end

    -- title bar
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "Icon")
    icon:SetSize(26, 26)
    icon:SetPoint("TOPLEFT", 20, -16)
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(L.ADDON_TITLE)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    -- Set a waypoint -------------------------------------------------------
    Header(frame, L.SET_WAYPOINT_HEADER, 24, -54)

    local zoneLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    zoneLabel:SetPoint("TOPLEFT", 26, -88)
    zoneLabel:SetText(L.ZONE)
    local xLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    xLabel:SetPoint("TOPLEFT", 26, -120)
    xLabel:SetText(L.X)
    local noteLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    noteLabel:SetPoint("TOPLEFT", 26, -152)
    noteLabel:SetText(L.NOTE)

    -- boxes start after the widest label, so every language fits
    local labelW = math.max(zoneLabel:GetStringWidth() or 0, noteLabel:GetStringWidth() or 0, 50)
    local boxX = math.min(26 + labelW + 12, 150)
    local boxW = WIDTH - boxX - 30

    zoneBox = Box(frame, boxW, L.ZONE_SEARCH_HINT)
    zoneBox:SetPoint("TOPLEFT", boxX, -81)
    xBox = Box(frame, 70)
    xBox:SetPoint("TOPLEFT", boxX, -113)
    local yLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    yLabel:SetPoint("LEFT", xBox, "RIGHT", 14, 0)
    yLabel:SetText(L.Y)
    yBox = Box(frame, 70)
    yBox:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)
    noteBox = Box(frame, boxW, L.NOTE_HINT)
    noteBox:SetPoint("TOPLEFT", boxX, -145)

    -- "Use My Position" fills the X and Y boxes, so it sits next to them
    local hereBtn = Button(frame, L.USE_MY_POSITION, 120, 24)
    hereBtn:SetPoint("LEFT", yBox, "RIGHT", 12, 0)
    hereBtn:SetPoint("RIGHT", frame, "RIGHT", -30, 0)
    hereBtn:SetNormalFontObject(GameFontNormalSmall)
    hereBtn:SetHighlightFontObject(GameFontHighlightSmall)
    hereBtn:SetScript("OnClick", UseMyPosition)
    AddTooltip(hereBtn, L.USE_MY_POSITION, L.USE_MY_POSITION_DESC)

    local setBtn = Button(frame, L.SET_WAYPOINT, 170, 26)
    setBtn:SetPoint("TOPLEFT", 26, -182)
    setBtn:SetScript("OnClick", SubmitWaypoint)
    local shareBtn = Button(frame, L.SHARE, 170, 26)
    shareBtn:SetPoint("LEFT", setBtn, "RIGHT", 16, 0)
    shareBtn:SetScript("OnClick", ShareTyped)
    AddTooltip(shareBtn, L.SHARE_TITLE, L.SHARE_SPOT_DESC)

    statusText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", 28, -213)
    statusText:SetWidth(WIDTH - 56)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(false)

    -- Find: one button per kind of thing, each opens the Find window on
    -- that tab (quests, friendly NPCs, enemies, objects)
    local findLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    findLabel:SetPoint("TOPLEFT", 26, -232)
    findLabel:SetText(L.FIND_LABEL)
    local findButtons = {}
    local prevFind
    -- four buttons share what's left of the row, so long translations fit
    local findWidth = math.min(76, math.floor((WIDTH - 26 - findLabel:GetStringWidth() - 8 - 24 - 3 * 4) / 4))
    for _, spec in ipairs({ { "quest", L.TAB_QUESTS }, { "npc", L.TAB_NPCS }, { "enemy", L.TAB_ENEMIES }, { "object", L.TAB_OBJECTS } }) do
        local b = Button(frame, spec[2], findWidth, 22)
        b:SetNormalFontObject(GameFontNormalSmall)
        b:SetHighlightFontObject(GameFontHighlightSmall)
        if prevFind then
            b:SetPoint("LEFT", prevFind, "RIGHT", 4, 0)
        else
            b:SetPoint("LEFT", findLabel, "RIGHT", 8, 0)
        end
        local tab = spec[1]
        b:SetScript("OnClick", function()
            ns.Find.Show(nil, tab)
        end)
        AddTooltip(b, L.FIND_TITLE, L.FIND_BUTTON_DESC)
        b.tab = tab
        findButtons[#findButtons + 1] = b
        prevFind = b
    end
    AddTooltip(setBtn, L.SET_WAYPOINT, L.TIP_MAP)

    -- text box behaviour
    local zoneEdit = zoneBox.edit
    zoneEdit:SetScript("OnTextChanged", function(self, userInput)
        if self.placeholder then
            self.placeholder:SetShown(self:GetText() == "")
        end
        if userInput and not self.ignoreChange then
            selectedZone = nil
            ShowZoneList(self:GetText())
        end
    end)
    zoneEdit:HookScript("OnEditFocusGained", function(self)
        ShowZoneList(selectedZone and "" or self:GetText())
    end)
    zoneEdit:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.2, function()
            if not zoneBox.edit:HasFocus() then
                zoneList:Hide()
            end
        end)
    end)
    zoneEdit:SetScript("OnEnterPressed", function(self)
        if zoneList:IsShown() and zoneResults[zoneCursor] and not selectedZone then
            PickResult(zoneResults[zoneCursor])
            return
        end
        zoneList:Hide()
        self:ClearFocus()
        xBox.edit:SetFocus()
    end)
    -- up / down arrows walk through the list
    zoneEdit:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then
            MoveCursor(-1)
        elseif key == "DOWN" then
            MoveCursor(1)
        end
    end)
    zoneEdit:SetScript("OnTabPressed", function()
        xBox.edit:SetFocus()
    end)

    xBox.edit:HookScript("OnTextChanged", SmartPaste)
    xBox.edit:SetScript("OnTabPressed", function()
        yBox.edit:SetFocus()
    end)
    xBox.edit:SetScript("OnEnterPressed", SubmitWaypoint)
    yBox.edit:SetScript("OnTabPressed", function()
        noteBox.edit:SetFocus()
    end)
    yBox.edit:SetScript("OnEnterPressed", SubmitWaypoint)
    noteBox.edit:SetScript("OnTabPressed", function()
        zoneBox.edit:SetFocus()
    end)
    noteBox.edit:SetScript("OnEnterPressed", SubmitWaypoint)

    CreateZoneList()

    -- handles for the automated tests
    UI.widgets = { find = findButtons, zone = zoneEdit, x = xBox.edit, y = yBox.edit, note = noteBox.edit, set = setBtn, here = hereBtn, share = shareBtn, zoneList = zoneList, rows = rows }

    -- Your waypoints -------------------------------------------------------
    Header(frame, L.YOUR_WAYPOINTS, 24, -262)
    local clearAll = Button(frame, L.CLEAR_ALL, 100, 22)
    clearAll:SetPoint("TOPRIGHT", -24, -258)
    clearAll:SetScript("OnClick", function()
        local count = WP.Count()
        if count < 2 or not (StaticPopup_Show and StaticPopupDialogs) then
            WP.ClearAll()
            return
        end
        StaticPopupDialogs.WAYPOINTTRACKER_CLEAR_ALL = StaticPopupDialogs.WAYPOINTTRACKER_CLEAR_ALL or {
            text = L.CLEAR_ALL_CONFIRM,
            button1 = L.YES,
            button2 = L.NO,
            OnAccept = function()
                WP.ClearAll()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("WAYPOINTTRACKER_CLEAR_ALL", count)
    end)
    moreText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    moreText:SetPoint("RIGHT", clearAll, "LEFT", -8, 0)
    moreText:SetText(L.MORE_BELOW)
    moreText:Hide()

    local listTop = -290
    for i = 1, ROWS do
        rows[i] = CreateRow(frame, i, listTop)
    end
    emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("TOP", frame, "TOP", 0, listTop - 40)
    emptyText:SetText(L.NO_WAYPOINTS)

    local listArea = CreateFrame("Frame", nil, frame)
    listArea:SetPoint("TOPLEFT", 22, listTop)
    listArea:SetPoint("RIGHT", -22, 0)
    listArea:SetHeight(ROWS * ROW_HEIGHT)
    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, delta)
        listOffset = listOffset - delta
        RefreshList()
    end)

    -- Arrow ------------------------------------------------------------------
    Header(frame, L.ARROW_HEADER, 24, -426)
    Check(frame, L.SHOW_ARROW, "arrowShown", 22, -454, nil, 134)
    -- The arrow never catches clicks (so right-click to attack always works);
    -- it is moved from here instead.
    local moveBtn = Button(frame, L.MOVE_ARROW, 112, 22)
    moveBtn:SetPoint("TOPLEFT", 190, -456)
    moveBtn:SetScript("OnClick", function()
        ns.Arrow.SetMoving(not ns.Arrow.moving)
    end)
    AddTooltip(moveBtn, L.MOVE_ARROW, L.MOVE_ARROW_DESC .. "\n\n" .. L.EDIT_MODE_HINT)
    local resetBtn = Button(frame, L.RESET_POSITION, 96, 22)
    resetBtn:SetPoint("LEFT", moveBtn, "RIGHT", 6, 0)
    resetBtn:SetScript("OnClick", function()
        ns.Arrow.Reset()
    end)
    AddTooltip(resetBtn, L.RESET_POSITION, L.RESET_POSITION_DESC)
    ns.On("ARROW_MOVING", function(on)
        moveBtn:SetText(on and L.DONE_MOVING or L.MOVE_ARROW)
    end)
    UI.widgets.move, UI.widgets.reset = moveBtn, resetBtn
    Slider(frame, L.ARROW_SIZE, "arrowScale", 0.5, 2.0, 0.05, 28, -488, 170, Percent)
    Slider(frame, L.ARROW_TRANSPARENCY, "arrowAlpha", 0.2, 1.0, 0.05, 220, -488, 170, Percent)

    -- More options toggle ---------------------------------------------------
    local more = Check(frame, L.SHOW_MORE_OPTIONS, "showAdvanced", 22, -546, nil, 200)
    UI.widgets.treasure = Check(frame, L.TREASURE_HUNT, "treasureHunt", 236, -546, L.TREASURE_HUNT_DESC, 150)
    UI.widgets.more = more
    more.label:SetFontObject("GameFontNormal")
    more.onChange = function(on)
        UI.SetAdvancedShown(on)
    end

    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMRIGHT", -22, 20)
    version:SetText("v" .. tostring(ns.version))

    frame:SetScript("OnShow", function()
        if ns.Arrow then
            ns.Arrow.SetPreview(true)
        end
        if not selectedZone and zoneBox.edit:GetText() == "" then
            local mapID = C_Map.GetBestMapForUnit("player")
            if mapID then
                SelectZone(mapID)
            end
        end
        SetStatus("")
        UI.Refresh()
        UI.SetAdvancedShown(ns.Get("showAdvanced"))
    end)
    frame:SetScript("OnHide", function()
        if ns.Arrow then
            ns.Arrow.SetPreview(false)
            if ns.Arrow.moving then
                ns.Arrow.SetMoving(false)
            end
        end
        if zoneList then
            zoneList:Hide()
        end
    end)

    -- keep distances fresh while open
    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc > 0.5 then
            acc = 0
            RefreshList()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- "More options" panel (scrolls, so long translations always fit)
-- ---------------------------------------------------------------------------
local function OpenColourPicker()
    local c = ns.Get("singleColor")
    local prev = { r = c.r, g = c.g, b = c.b }
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
        return
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = c.r,
        g = c.g,
        b = c.b,
        hasOpacity = false,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ns.Set("singleColor", { r = r, g = g, b = b })
        end,
        cancelFunc = function()
            ns.Set("singleColor", prev)
        end,
    })
end

local function CreateAdvanced()
    advanced = CreateFrame("Frame", "WaypointTrackerOptionsFrame", frame, "BackdropTemplate")
    advanced:SetSize(ADV_WIDTH, HEIGHT)
    advanced:SetPoint("TOPLEFT", frame, "TOPRIGHT", -6, 0)
    advanced:SetBackdrop(BACKDROP_DIALOG)
    advanced:SetBackdropColor(0, 0, 0, 1)
    advanced:EnableMouse(true)
    advanced:Hide()

    local title = advanced:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -22)
    title:SetText(L.MORE_OPTIONS)
    local close = CreateFrame("Button", nil, advanced, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function()
        ns.Set("showAdvanced", false)
        UI.SetAdvancedShown(false)
    end)

    local scroll = CreateFrame("ScrollFrame", "WaypointTrackerOptionsScroll", advanced, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -50)
    scroll:SetPoint("BOTTOMRIGHT", -36, 16)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ADV_WIDTH - 56, 800)
    scroll:SetScrollChild(content)

    local y = -4
    local labelWidth = ADV_WIDTH - 100
    local function H(text)
        y = y - 8
        Header(content, text, 8, y)
        y = y - 30
    end
    local function C(label, key, desc)
        local cb = Check(content, label, key, 4, y, desc, labelWidth)
        y = y - 26
        return cb
    end

    H(L.ARROW_EXTRAS_HEADER)
    local cycler = Cycler(content, L.COLOUR, "colorMode", {
        { value = "distance", text = L.COLOUR_DISTANCE },
        { value = "direction", text = L.COLOUR_DIRECTION },
        { value = "single", text = L.COLOUR_SINGLE },
    }, 8, y, 260, L.COLOUR_DESC)
    local swatch = CreateFrame("Button", nil, content)
    swatch:SetSize(22, 22)
    swatch:SetPoint("LEFT", cycler.nextButton, "RIGHT", 10, 0)
    local swatchBorder = swatch:CreateTexture(nil, "BACKGROUND")
    swatchBorder:SetColorTexture(0.9, 0.9, 0.9, 1)
    swatchBorder:SetAllPoints()
    local swatchColour = swatch:CreateTexture(nil, "ARTWORK")
    swatchColour:SetPoint("TOPLEFT", 2, -2)
    swatchColour:SetPoint("BOTTOMRIGHT", -2, 2)
    swatchColour:SetColorTexture(1, 1, 1, 1)
    swatch:SetScript("OnClick", OpenColourPicker)
    AddTooltip(swatch, L.PICK_COLOUR, L.PICK_COLOUR_DESC)
    refreshers[#refreshers + 1] = function()
        local c = ns.Get("singleColor")
        swatchColour:SetColorTexture(c.r or 1, c.g or 0.82, c.b or 0, 1)
        swatch:SetShown(ns.Get("colorMode") == "single")
    end
    y = y - 50

    C(L.FADE_ON_COURSE, "fadeOnCourse", L.FADE_ON_COURSE_DESC)
    C(L.HIDE_IN_COMBAT, "hideInCombat", L.HIDE_IN_COMBAT_DESC)
    C(L.HIDE_ON_TAXI, "hideOnTaxi", L.HIDE_ON_TAXI_DESC)

    H(L.TEXT_HEADER)
    Slider(content, L.TEXT_SIZE, "textScale", 0.5, 2.0, 0.05, 10, y, 250, Percent, L.TEXT_SIZE_DESC)
    y = y - 50
    Slider(content, L.TEXT_VISIBILITY, "textAlpha", 0.2, 1.0, 0.05, 10, y, 250, Percent, L.TEXT_VISIBILITY_DESC)
    y = y - 50
    C(L.TEXT_SEPARATE, "textSeparate", L.TEXT_SEPARATE_DESC)
    C(L.SHOW_TITLE, "showTitle", L.SHOW_TITLE_DESC)
    C(L.SHOW_DISTANCE, "showDistance", L.SHOW_DISTANCE_DESC)
    C(L.SHOW_ETA, "showETA", L.SHOW_ETA_DESC)

    H(L.ARRIVAL_HEADER)
    Slider(content, L.ARRIVAL_DISTANCE, "arrivalDistance", 3, 50, 1, 10, y, 250, Yards, L.ARRIVAL_DISTANCE_DESC)
    y = y - 50
    C(L.AUTO_CLEAR, "autoClear", L.AUTO_CLEAR_DESC)
    C(L.ARRIVAL_SOUND, "arrivalSound", L.ARRIVAL_SOUND_DESC)
    C(L.AUTO_NEXT, "autoNext", L.AUTO_NEXT_DESC)

    H(L.MAPS_HEADER)
    C(L.WORLD_PINS, "worldPins", L.WORLD_PINS_DESC)
    C(L.MINIMAP_PINS, "minimapPins", L.MINIMAP_PINS_DESC)
    C(L.MINIMAP_EDGE, "minimapEdge", L.MINIMAP_EDGE_DESC)
    C(L.WORLD_COORDS, "worldCoords", L.WORLD_COORDS_DESC)
    C(L.MAP_CLICK, "mapClick", L.MAP_CLICK_DESC)
    C(L.COORDS_BOX, "coordsBox", L.COORDS_BOX_DESC)
    C(L.FOLLOW_MAP_PINS, "followMapPins", L.FOLLOW_MAP_PINS_DESC)

    H(L.TREASURE_HEADER)
    C(L.TREASURE_HUNT, "treasureHunt", L.TREASURE_HUNT_DESC)
    C(L.TREASURE_CHESTS, "treasureChests", L.TREASURE_CHESTS_DESC)
    C(L.TREASURE_RARES, "treasureRares", L.TREASURE_RARES_DESC)
    C(L.TREASURE_OTHER, "treasureOther", L.TREASURE_OTHER_DESC)
    C(L.TREASURE_KNOWN, "treasureKnownSpots", L.TREASURE_KNOWN_DESC)
    C(L.TREASURE_PING, "treasurePing", L.TREASURE_PING_DESC)
    C(L.TREASURE_FOCUS, "treasureFocus", L.TREASURE_FOCUS_DESC)

    H(L.GENERAL_HEADER)
    C(L.FOLLOW_QUEST, "followQuest", L.FOLLOW_QUEST_DESC)
    C(L.CORPSE_WAYPOINT, "corpseWaypoint", L.CORPSE_WAYPOINT_DESC)
    C(L.LEARN, "learn", L.LEARN_DESC)
    C(L.AUTO_CLOSEST, "autoClosest", L.AUTO_CLOSEST_DESC)
    C(L.PERSIST, "persist", L.PERSIST_DESC)
    C(L.MINIMAP_BUTTON, "minimapButton", L.MINIMAP_BUTTON_DESC)
    C(L.CHAT_MESSAGES, "chatMessages", L.CHAT_MESSAGES_DESC)
    C(L.USE_METRES, "useMetres", L.USE_METRES_DESC)
    C(L.ADDON_WAYPOINTS, "addonWaypoints", L.ADDON_WAYPOINTS_DESC)
    C(L.BLIZZARD_PIN, "blizzardPin", L.BLIZZARD_PIN_DESC)

    y = y - 12
    local reset = Button(content, L.RESET_SETTINGS, 200, 24)
    reset:SetPoint("TOPLEFT", 10, y)
    reset:SetScript("OnClick", function()
        if StaticPopup_Show and StaticPopupDialogs then
            StaticPopupDialogs.WAYPOINTTRACKER_RESET = StaticPopupDialogs.WAYPOINTTRACKER_RESET or {
                text = L.RESET_CONFIRM,
                button1 = L.YES,
                button2 = L.NO,
                OnAccept = function()
                    ns.ResetSettings()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("WAYPOINTTRACKER_RESET")
        else
            ns.ResetSettings()
        end
    end)
    y = y - 40
    content:SetHeight(-y)
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
-- Re-reads settings into every widget (also ones outside the window).
function UI.RefreshWidgets()
    for i = 1, #refreshers do
        ns.Call(refreshers[i])
    end
end

function UI.Refresh()
    if not frame then
        return
    end
    UI.RefreshWidgets()
    RefreshList()
end

function UI.SetAdvancedShown(on)
    if not frame then
        return
    end
    if on then
        if not advanced then
            CreateAdvanced()
            UI.Refresh()
        end
        advanced:Show()
    elseif advanced then
        advanced:Hide()
    end
end

local function Ensure()
    if not frame then
        CreateMain()
    end
end

function UI.Show()
    if not ns.settings then
        return
    end
    Ensure()
    frame:Show()
    frame:Raise()
end

function UI.Hide()
    if frame then
        frame:Hide()
    end
end

function UI.Toggle()
    if frame and frame:IsShown() then
        UI.Hide()
    else
        UI.Show()
    end
end

function WaypointTracker_ToggleWindow()
    UI.Toggle()
end

ns.On("WAYPOINTS_CHANGED", RefreshList)
ns.On("ACTIVE_CHANGED", RefreshList)
ns.On("SETTING_CHANGED", function(key)
    if frame and frame:IsShown() and key ~= "windowPos" then
        UI.Refresh()
    end
    -- other addons look for the waypoint API while they load, so this needs a reload
    if key == "addonWaypoints" then
        ns.Print(L.RELOAD_NEEDED, true)
    end
end)

-- ---------------------------------------------------------------------------
-- Entry in the game's Options > AddOns list
-- ---------------------------------------------------------------------------
ns.On("LOGIN", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.ADDON_TITLE)
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetText(L.OPTIONS_PANEL_DESC)
    local open = Button(panel, L.OPEN_WINDOW, 220, 28)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            if SettingsPanel.Close then
                SettingsPanel:Close(true)
            else
                HideUIPanel(SettingsPanel)
            end
        end
        UI.Show()
    end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, L.ADDON_TITLE)
    if ok and category then
        pcall(Settings.RegisterAddOnCategory, category)
    end
end)
