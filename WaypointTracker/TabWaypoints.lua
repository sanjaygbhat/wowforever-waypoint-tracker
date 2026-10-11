-- Home: add a spot, follow the arrow, and manage your waypoints.
local _, ns = ...
local L, Geo, WP, W, Window = ns.L, ns.Geo, ns.WP, ns.Widgets, ns.Window

local TabWaypoints = {}
ns.TabWaypoints = TabWaypoints
local widgets = {}
TabWaypoints.widgets = widgets
local content, selectedZone, changing, tipShown
local zoneResults, zoneScroll, zoneCursor = {}, 0, 1
local ZONE_ROWS = 10
local PLACE_COLOURS = {
    quest = { 1, 0.82, 0 }, turnin = { 1, 0.82, 0 },
    flight = { 0.45, 1, 0.45 }, dungeon = { 0.6, 0.8, 1 },
    poi = { 0.8, 0.8, 1 }, rare = { 1, 0.55, 0.25 },
}

local function SetStatus(text, good)
    Window.SetStatus(text, good)
end

local function InputText()
    return ns.Trim(widgets.add:GetText()):gsub("^/%S+%s*", "")
end

-- ParseWayArgs rejects out-of-range pairs too. Keep those out of Find.
local function HasCoordinates(text)
    local previous
    for token in text:gmatch("%S+") do
        local number = Geo.ParseNumber((token:gsub(",$", "")))
        if number and previous then return true end
        previous = number
    end
    return text:match("^#%d+") or text:match("^[%d%.%-]")
        or text:match("%d+%.?%d*,%s*%d")
end

local function ReadSpot()
    local text = InputText()
    local zone, x, y, title = Geo.ParseWayArgs(text)
    if not x then return nil, text == "" and L.NO_COORDS or L.INVALID_COORDS end
    local mapID
    if zone == "" then
        mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not mapID then return nil, L.NO_POSITION end
    elseif zone:match("^#%d+$") then
        mapID = tonumber(zone:sub(2))
        if not Geo.IsValidMap(mapID) then return nil, L.UNKNOWN_ZONE:format(zone) end
    elseif selectedZone and Geo.GetMapName(selectedZone) == zone then
        mapID = selectedZone
    else
        local extra
        mapID, extra = Geo.FindZone(zone)
        if not mapID then
            if type(extra) == "table" and #extra > 0 then
                return nil, L.DID_YOU_MEAN:format(table.concat(extra, ", "))
            end
            return nil, L.UNKNOWN_ZONE:format(zone)
        end
    end
    local name = ns.Trim(widgets.name:GetText())
    return mapID, x / 100, y / 100, name ~= "" and name or title
end

local function BuildResults(text)
    local zones = Geo.SearchZones(text or "")
    local places = ns.Places and ns.Places.Search(text or "") or {}
    local out = {}
    if Geo.Squash(text or "") == "" then
        local current = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        for _, z in ipairs(zones) do
            if z.id == current then out[#out + 1] = { zone = z, here = true } end
        end
        for _, p in ipairs(places) do out[#out + 1] = { place = p } end
        for _, z in ipairs(zones) do
            if z.id ~= current then out[#out + 1] = { zone = z } end
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
    local list = widgets.zoneList
    for i = 1, ZONE_ROWS do
        local b, r = list.buttons[i], zoneResults[i + zoneScroll]
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
        end
        b:SetShown(r ~= nil)
    end
    list.empty:SetShown(#zoneResults == 0)
    list.more:SetShown(#zoneResults > zoneScroll + ZONE_ROWS)
end

local function ShowZoneList(text)
    if HasCoordinates(text) then widgets.zoneList:Hide(); return end
    zoneResults = BuildResults(text)
    zoneScroll, zoneCursor = 0, 1
    RefreshZoneList()
    widgets.zoneList:Show()
end

local function MoveCursor(delta)
    if #zoneResults == 0 then return end
    zoneCursor = ns.Clamp(zoneCursor + delta, 1, #zoneResults)
    if zoneCursor <= zoneScroll then
        zoneScroll = zoneCursor - 1
    elseif zoneCursor > zoneScroll + ZONE_ROWS then
        zoneScroll = zoneCursor - ZONE_ROWS
    end
    RefreshZoneList()
end

local function PickResult(r)
    if not r then return end
    widgets.zoneList:Hide()
    if r.zone then
        selectedZone = r.zone.id
        changing = true
        widgets.add:SetText(r.zone.name .. " ")
        widgets.add:SetFocus()
        widgets.add:SetCursorPosition(#widgets.add:GetText())
        changing = false
        SetStatus(L.ZONE_PICKED_HINT:format(r.zone.name), "info")
    else
        widgets.add:ClearFocus()
        local p = r.place
        local wp = WP.Add(p.m, p.x, p.y, { title = p.name, source = "place", silent = true })
        SetStatus(wp and L.ADDED:format(WP.Describe(wp)) or L.INVALID_COORDS, wp ~= nil)
    end
end

local function CreateZoneList(addBox)
    local ok, list = pcall(CreateFrame, "Frame", nil, Window.frame, "BackdropTemplate")
    if not ok then list = CreateFrame("Frame", nil, Window.frame) end
    if list.SetBackdrop then
        list:SetBackdrop(W.BACKDROP_BOX)
        list:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    end
    list:SetFrameStrata("DIALOG")
    list:SetFrameLevel(Window.frame:GetFrameLevel() + 20)
    list:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", 0, 2)
    list:SetPoint("TOPRIGHT", addBox, "BOTTOMRIGHT", 0, 2)
    list:SetHeight(ZONE_ROWS * 20 + 22)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list:Hide()
    list.buttons = {}
    for i = 1, ZONE_ROWS do
        local b = CreateFrame("Button", nil, list)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 20)
        b:SetPoint("TOPRIGHT", -5, -5 - (i - 1) * 20)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.cursor = b:CreateTexture(nil, "BACKGROUND")
        b.cursor:SetAllPoints()
        b.cursor:SetColorTexture(1, 0.82, 0, 0.15)
        b.sub = W.Label(b, "", "GameFontDisableSmall")
        b.sub:SetPoint("RIGHT", -4, 0)
        b.sub:SetWidth(170)
        b.sub:SetJustifyH("RIGHT")
        b.sub:SetWordWrap(false)
        b.text = W.Label(b, "")
        b.text:SetPoint("LEFT", 4, 0)
        b.text:SetPoint("RIGHT", b.sub, "LEFT", -8, 0)
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", ns.Safe(function(self) PickResult(self.result) end))
        list.buttons[i] = b
    end
    list.empty = W.Label(list, L.NO_ZONES_FOUND, "GameFontDisable")
    list.empty:SetPoint("TOP", 0, -10)
    list.more = W.Label(list, L.MORE_BELOW, "GameFontDisableSmall")
    list.more:SetPoint("BOTTOMRIGHT", -8, 5)
    list:SetScript("OnMouseWheel", ns.Safe(function(_, delta)
        zoneScroll = ns.Clamp(zoneScroll - delta, 0, math.max(0, #zoneResults - ZONE_ROWS))
        RefreshZoneList()
    end))
    widgets.zoneList = list
end

local function SubmitWaypoint()
    widgets.zoneList:Hide()
    local text = InputText()
    if text ~= "" and not HasCoordinates(text) and not Geo.ParseWayArgs(text) then
        if ns.Find and ns.Find.Way then
            widgets.add:ClearFocus()
            ns.Find.Way(text)
            if ns.Find.IsShown and ns.Find.IsShown() then Window.ShowTab("find") end
        end
        return
    end
    local mapID, x, y, title = ReadSpot()
    if not mapID then SetStatus(x); return end
    local wp = WP.Add(mapID, x, y, { title = title, silent = true })
    SetStatus(wp and L.ADDED:format(WP.Describe(wp)) or L.INVALID_COORDS, wp ~= nil)
    if wp then
        changing = true
        widgets.add:SetText("")
        widgets.name:SetText("")
        changing = false
        widgets.add:ClearFocus()
        widgets.name:ClearFocus()
        selectedZone = nil
    end
end

local function ShareTyped(button)
    if not ns.Share then return end
    widgets.zoneList:Hide()
    local spot
    if InputText() == "" then
        spot = ns.Share.MySpot(widgets.name:GetText())
        if not spot then SetStatus(L.NO_POSITION); return end
    else
        local mapID, x, y, title = ReadSpot()
        if not mapID then SetStatus(x); return end
        spot = ns.Share.Spot(mapID, x, y, title)
    end
    if spot then SetStatus(""); ns.Share.ShowMenu(button, spot) end
end

local function UseMyPosition()
    local mapID, x, y = Geo.GetPlayerMapPosition()
    if not mapID then SetStatus(L.NO_POSITION); return end
    selectedZone, changing = mapID, true
    widgets.add:SetText(("%s %.1f %.1f"):format(Geo.GetMapName(mapID), x * 100, y * 100))
    widgets.add:SetCursorPosition(#widgets.add:GetText())
    changing = false
    widgets.zoneList:Hide()
    SetStatus("")
end

local function RowMenu(row, wp)
    W.Menu(row, function(root)
        root:CreateButton(L.ROW_MENU_POINT, function() WP.SetActive(wp, true) end)
        if ns.Share then
            local share = root:CreateButton(L.SHARE)
            local nested = share and type(share.CreateButton) == "function"
            local target = nested and share or root
            for _, ch in ipairs(ns.Share.Channels()) do
                local command = ch[2]
                target:CreateButton(nested and ch[1] or L.ROUTE_SHARE_POST:format(ch[1]), function()
                    ns.Share.ToChannel(wp, command)
                end)
            end
            target:CreateButton(L.SHARE_CHATBOX, function() ns.Share.ToChatBox(wp) end)
        end
        root:CreateButton(L.REMOVE, function() WP.Remove(wp, true) end)
    end)
end

local function RowInit(row)
    row.activeBg = row:CreateTexture(nil, "BACKGROUND")
    row.activeBg:SetAllPoints()
    row.activeBg:SetColorTexture(1, 0.82, 0, 0.10)
    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetTexture(ns.MEDIA .. "Pin")
    row.marker:SetSize(14, 14)
    row.marker:SetPoint("LEFT", 2, 0)
    row.dist = W.Label(row, "", "GameFontHighlightSmall")
    row.dist:SetPoint("RIGHT", -4, 0)
    row.dist:SetWidth(80)
    row.dist:SetJustifyH("RIGHT")
    row.dist:SetTextColor(0.8, 0.8, 0.8)
    row.zone = W.Label(row, "", "GameFontDisableSmall")
    row.zone:SetPoint("RIGHT", row.dist, "LEFT", -8, 0)
    row.zone:SetWidth(220)
    row.zone:SetJustifyH("RIGHT")
    row.zone:SetWordWrap(false)
    row.text = W.Label(row, "")
    row.text:SetPoint("LEFT", row.marker, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.zone, "LEFT", -8, 0)
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", ns.Safe(function(self)
        if not self.item or not GameTooltip then return end
        local wp = self.item
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(WP.ShortName(wp), 1, 0.82, 0)
        GameTooltip:AddLine(Geo.GetMapName(wp.m) .. "  " .. Geo.FormatCoords(wp.x, wp.y), 1, 1, 1)
        GameTooltip:AddLine(L.ROW_TOOLTIP_CLICK, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L.ROW_TOOLTIP_SHARE, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L.ROW_TOOLTIP_MENU, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end))
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function RowUpdate(row, wp, _, active)
    row.wp = wp
    row.text:SetText(WP.ShortName(wp))
    row.zone:SetText(Geo.GetMapName(wp.m) .. "  " .. Geo.FormatCoords(wp.x, wp.y))
    local dist = Geo.GetVector(wp)
    row.dist:SetText(dist and Geo.FormatDistance(dist) or "")
    row.marker:SetVertexColor(active and 1 or 0.55, active and 0.82 or 0.8, active and 0 or 1)
    row.activeBg:SetShown(active)
end

local function RefreshStatus()
    local wp = WP.GetActive()
    local text = wp and L.POINTING_TO:format(WP.ShortName(wp)) or L.ACTIVE_NONE
    local dist = wp and Geo.GetVector(wp)
    widgets.pointing:SetText(text .. (dist and " · " .. Geo.FormatDistance(dist) or ""))
    local routes = ns.Routes
    local run = routes and routes.Run and routes.Run()
    widgets.route:SetShown(run ~= nil)
    widgets.skip:SetShown(run ~= nil)
    widgets.stop:SetShown(run ~= nil)
    if run then
        local r = routes.Get and routes.Get(run.id)
        local name = r and r.name or run.id
        local following = run.mode == "loop" and L.FOLLOWING_LOOP:format(name, (run.lap or 0) + 1)
            or L.FOLLOWING_ROUTE:format(name, wp and wp.routeID == run.id and wp.routeIndex or (run.done or 0) + 1, run.total or 0)
        widgets.route:SetText(following)
    end
end

function TabWaypoints.Refresh()
    if not content then return end
    RefreshStatus()
    local newest, list = {}, WP.List()
    if widgets.clearAll then widgets.clearAll:SetEnabled(#list > 0) end
    for i = #list, 1, -1 do newest[#newest + 1] = list[i] end
    widgets.list:SetSelected(WP.GetActive())
    widgets.list:SetItems(newest)
    widgets.count:SetText(L.WAYPOINT_COUNT:format(#list))
end

W.Confirm("WAYPOINTTRACKER_CLEAR_ALL", {
    text = L.CLEAR_ALL_CONFIRM, button1 = L.YES, button2 = L.NO,
    onAccept = function() WP.ClearAll(true) end,
})

local function ClearAll()
    if WP.Count() < 2 then WP.ClearAll(true); return end
    W.Ask("WAYPOINTTRACKER_CLEAR_ALL", WP.Count())
end

local function HideDropdown()
    if not content then return end
    widgets.zoneList:Hide()
    widgets.add:ClearFocus()
    widgets.name:ClearFocus()
    if HelpTip and HelpTip.Hide then pcall(HelpTip.Hide, HelpTip, widgets.addBox, L.TIP_ADD_BOX) end
end

local function ShowTip()
    if tipShown or not content:IsVisible() or not ns.settings or ns.settings.tipsShown.add then return end
    tipShown = true
    if HelpTip and HelpTip.Show and HelpTip.ButtonStyle and HelpTip.Point then
        local ok, shown = pcall(HelpTip.Show, HelpTip, widgets.addBox, {
            text = L.TIP_ADD_BOX, buttonStyle = HelpTip.ButtonStyle.Close,
            targetPoint = HelpTip.Point.BottomEdgeCenter,
            onAcknowledgeCallback = function() ns.settings.tipsShown.add = true end,
        })
        if ok and shown ~= false then return end
    end
    SetStatus(L.TIP_ADD_BOX, "info")
    ns.settings.tipsShown.add = true
end

local function Build(parent)
    content = parent
    content:SetScript("OnShow", ns.Safe(ShowTip))
    widgets.status = Window.frame.status
    widgets.clearAll = Window.tabs.waypoints.leftButton
    if widgets.clearAll and widgets.clearAll.SetMotionScriptsWhileDisabled then
        widgets.clearAll:SetMotionScriptsWhileDisabled(true)
    end
    widgets.pointing = W.Label(content, "")
    widgets.pointing:SetPoint("TOPLEFT", 4, -4)
    widgets.pointing:SetPoint("TOPRIGHT", -4, -4)
    widgets.pointing:SetWordWrap(false)
    widgets.stop = W.Button(content, L.ROUTE_STOP, 110, 22)
    widgets.stop:SetPoint("TOPRIGHT", -4, -24)
    widgets.skip = W.Button(content, L.ROUTE_SKIP, 150, 22)
    widgets.skip:SetPoint("RIGHT", widgets.stop, "LEFT", -4, 0)
    widgets.route = W.Label(content, "", "GameFontHighlightSmall")
    widgets.route:SetPoint("TOPLEFT", 4, -28)
    widgets.route:SetPoint("RIGHT", widgets.skip, "LEFT", -8, 0)
    widgets.route:SetWordWrap(false)
    widgets.skip:SetScript("OnClick", ns.Safe(function()
        if ns.Routes and ns.Routes.Skip then ns.Routes.Skip() end
    end))
    widgets.stop:SetScript("OnClick", ns.Safe(function()
        if ns.Routes and ns.Routes.Stop then ns.Routes.Stop() end
    end))
    W.Tooltip(widgets.skip, L.ROUTE_SKIP, L.BINDING_ROUTE_NEXT)
    W.Tooltip(widgets.stop, L.ROUTE_STOP, nil)
    local addBox = W.EditBox(content, 360, { placeholder = L.ADD_HINT, search = true })
    addBox:SetPoint("TOPLEFT", 4, -58)
    local nameBox = W.EditBox(content, 140, { placeholder = L.NAME_HINT })
    nameBox:SetPoint("LEFT", addBox, "RIGHT", 12, 0)
    widgets.addBox, widgets.add, widgets.name = addBox, addBox.edit, nameBox.edit
    CreateZoneList(addBox)
    widgets.here = W.Button(content, L.HERE, nil, 24)
    widgets.here:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", 0, -8)
    widgets.here:SetScript("OnClick", ns.Safe(UseMyPosition))
    W.Tooltip(widgets.here, L.HERE, L.USE_MY_POSITION_DESC)
    widgets.set = W.Button(content, L.SET, nil, 24)
    widgets.set:SetPoint("LEFT", widgets.here, "RIGHT", 6, 0)
    widgets.set:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    widgets.set:SetScript("OnClick", ns.Safe(function(self, button)
        if button == "RightButton" then ShareTyped(self) else SubmitWaypoint() end
    end))
    W.Tooltip(widgets.set, L.SET, L.SHARE_INSTEAD)
    widgets.add:HookScript("OnTextChanged", ns.Safe(function(self, userInput)
        if not changing and (userInput or self:HasFocus()) then ShowZoneList(InputText()) end
    end))
    widgets.add:HookScript("OnEditFocusGained", ns.Safe(function()
        if not changing then ShowZoneList(InputText()) end
    end))
    widgets.add:HookScript("OnEditFocusLost", function() widgets.zoneList:Hide() end)
    widgets.add:SetScript("OnEnterPressed", ns.Safe(function()
        if widgets.zoneList:IsShown() and zoneResults[zoneCursor] then
            PickResult(zoneResults[zoneCursor])
        else
            SubmitWaypoint()
        end
    end))
    widgets.add:SetScript("OnArrowPressed", ns.Safe(function(_, key)
        if not widgets.zoneList:IsShown() then ShowZoneList(InputText()) end
        if key == "UP" then MoveCursor(-1) elseif key == "DOWN" then MoveCursor(1) end
    end))
    widgets.add:SetScript("OnTabPressed", function() widgets.add:ClearFocus(); widgets.name:SetFocus() end)
    widgets.name:SetScript("OnTabPressed", function() widgets.name:ClearFocus(); widgets.add:SetFocus() end)
    widgets.name:SetScript("OnEnterPressed", ns.Safe(SubmitWaypoint))
    local header = W.Header(content, L.YOUR_WAYPOINTS)
    header:SetPoint("TOPLEFT", 4, -132)
    widgets.count = W.Label(content, "", "GameFontDisableSmall")
    widgets.count:SetPoint("TOPRIGHT", -4, -134)
    widgets.list = W.List(content, {
        rowHeight = 22, rowInit = RowInit, rowUpdate = RowUpdate,
        emptyText = L.NO_WAYPOINTS_LONG,
        onClick = function(row, wp, button)
            if button == "RightButton" then
                RowMenu(row, wp)
            elseif IsShiftKeyDown and IsShiftKeyDown() and ns.Share then
                ns.Share.ToChatBox(wp)
            else
                WP.SetActive(wp, true)
            end
        end,
    })
    widgets.list:SetSize(Window.frame:GetWidth() - 32, Window.frame:GetHeight() - 286)
    widgets.list:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -156)
    widgets.list:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 4)
    TabWaypoints.Refresh()
end

Window.RegisterTab {
    key = "waypoints", order = 1, title = L.TAB_WAYPOINTS,
    leftButton = { text = L.CLEAR_ALL, onClick = ClearAll, tooltip = L.CLEAR_ALL_DESC },
    build = Build,
    onShow = function() TabWaypoints.Refresh(); ShowTip() end,
    onHide = HideDropdown,
    onUpdate = TabWaypoints.Refresh,
}

ns.On("WAYPOINTS_CHANGED", TabWaypoints.Refresh)
ns.On("ACTIVE_CHANGED", TabWaypoints.Refresh)
ns.On("ROUTES_CHANGED", TabWaypoints.Refresh)
ns.On("SETTING_CHANGED", TabWaypoints.Refresh)
ns.On("UI_TAB_SHOWN", function(key)
    if key == "waypoints" then TabWaypoints.Refresh() else HideDropdown() end
end)
ns.On("UI_HIDDEN", HideDropdown)
