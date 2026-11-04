-- Routes pages, popups, sharing and the recorder against the fake WoW API.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

-- The shared mock doesn't yet model font height or ScrollFrame offsets.
local probe = M.NewObject("Frame", nil, UIParent)
local shims = {}
if not probe:GetVerticalScroll() then
    shims.GetVerticalScroll = function(self) return self._verticalScroll or 0 end
    shims.SetVerticalScroll = function(self, value) self._verticalScroll = value end
end
if not probe:GetStringHeight() then
    shims.GetStringHeight = function(self)
        local text = (self:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local lines, width = 0, math.max(1, self:GetWidth())
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            lines = lines + math.max(1, math.ceil(#line * 6 / width))
        end
        return lines * 12
    end
end
local mt, previousIndex = getmetatable(probe), getmetatable(probe).__index
local focusCalls = 0
shims.SetFocus = function(self)
    focusCalls = focusCalls + 1
    previousIndex(self, "SetFocus")(self)
end
mt.__index = function(self, key) return shims[key] or previousIndex(self, key) end

-- Some mock versions expose GetOwner but leave SetOwner as a recorded no-op.
local nativeTooltipOwner = GameTooltip.SetOwner
GameTooltip:SetOwner(probe, "ANCHOR_RIGHT")
if GameTooltip:GetOwner() ~= probe then
    GameTooltip.SetOwner = function(self, owner, anchor)
        M.tooltipOwner = owner
        return nativeTooltipOwner(self, owner, anchor)
    end
end
GameTooltip:Hide()

-- Model the native info-button size and button FontString so the reviewed
-- geometry runs through the same controls as FrameXML.
local originalCreate = CreateFrame
CreateFrame = function(kind, name, parent, template)
    local f = originalCreate(kind, name, parent, template)
    local createFontString = f.CreateFontString
    function f:CreateFontString(name, layer, font)
        local fs = createFontString(self, name, layer, font)
        fs.parcelFont = font
        local setPoint, clearPoints = fs.SetPoint, fs.ClearAllPoints
        function fs:SetPoint(...)
            self.parcelPoints = self.parcelPoints or {}
            self.parcelPoints[#self.parcelPoints + 1] = { ... }
            setPoint(self, ...)
        end
        function fs:ClearAllPoints()
            self.parcelPoints = {}
            clearPoints(self)
        end
        function fs:SetWordWrap(on) self.parcelWordWrap = on end
        -- Count UTF-8 characters, rather than bytes, for translated labels.
        function fs:GetStringWidth()
            local _, count = (self:GetText() or ""):gsub("[^\128-\191]", "")
            return count * 7
        end
        return fs
    end
    if template == "UIPanelInfoButton" then f:SetSize(16, 16) end
    if template == "UIPanelButtonTemplate" then
        -- Disabled buttons receive native hover events only when opted in.
        function f:SetMotionScriptsWhileDisabled(on) self.parcelDisabledMotion = on end
        function f:Hover(on)
            if self:IsEnabled() or self.parcelDisabledMotion then
                self:RunScript(on and "OnEnter" or "OnLeave")
            end
        end
        local fs = f:CreateFontString()
        f:SetFontString(fs)
    end
    return f
end
local originalMenu = MenuUtil.CreateContextMenu
MenuUtil.CreateContextMenu = function(owner, generator)
    return originalMenu(owner, function(menuOwner, root)
        local createButton = root.CreateButton
        function root:CreateButton(...)
            local entry = createButton(self, ...)
            function entry:SetTooltip(fn) self.tooltip = fn end
            return entry
        end
        generator(menuOwner, root)
    end)
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function item(menu, text)
    for _, entry in ipairs(menu.items) do if entry.text == text then return entry end end
end
local function action(detail, text)
    for _, b in ipairs(detail.buttons) do if b:IsShown() and b:GetText() == text then return b end end
end

WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
-- R7/R8 are separate parcels. Exercise their public contracts while their
-- scaffold is present; use the real widget automatically once R7 is merged.
ns.RouteMap = ns.RouteMap or {}
if not ns.RouteMap.MapFor then
    ns.RouteMap.MapFor = function(r) return ns.Geo.CommonMap(r.pts) end
end
if not ns.RouteMap.Create then
    ns.RouteMap.Create = function(parent, width, height)
        local map = CreateFrame("Button", nil, parent)
        map:SetSize(width, height)
        map.pins = {}
        function map:SetRoute(r)
            self.route, self.pins = r, {}
            if not r then self:Hide(); return end
            ns.Routes.Prepare(r)
            self.mapID, self.shown = ns.RouteMap.MapFor(r)
            for _, pt in ipairs(r.pts) do
                if ns.Geo.ProjectToMap(pt.m, pt.x, pt.y, self.mapID) then
                    self.pins[#self.pins + 1] = pt
                end
            end
            self:Show()
        end
        function map:GetMapID() return self.mapID end
        function map:Refresh() end
        map:SetScript("OnClick", function(self)
            if self.route and self.onClick then self.onClick(self.route, self.mapID) end
        end)
        return map
    end
end
ns.RoutePreview = ns.RoutePreview or {}
if not ns.RoutePreview.Show then
    ns.RoutePreview.Show = function()
        return false, ns.InCombat() and "combat" or "nomap"
    end
end
local registered, applied = nil, {}
-- Capture registration, forwarding to the sibling API when it is merged.
local registerSystem, applyPosition = ns.EditMode.RegisterSystem, ns.EditMode.ApplyPosition
ns.EditMode.RegisterSystem = function(spec)
    if spec.key == "recorder" then registered = spec end
    if registerSystem then registerSystem(spec) end
end
ns.EditMode.ApplyPosition = function(key)
    applied[key] = true
    if applyPosition then applyPosition(key) end
end
if not ns.EditMode.IsActive then
    ns.EditMode.IsActive = function() return M.recorderEditActive end
end
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local UI, Routes, WP, L, Window = ns.RoutesUI, ns.Routes, ns.WP, ns.L, ns.Window
local function CheckPanelRefusal(label)
    Window.Hide()
    -- ShowUIPanel can silently refuse while a blocking Blizzard panel is open.
    -- Keep the real Window.Show and page stack so refusal reaches our callers.
    local nativeShow, nativePush = ShowUIPanel, Window.PushPage
    local pushes, beforeFocus = 0, focusCalls
    ShowUIPanel = function() M.uiPanelCalls.show = M.uiPanelCalls.show + 1 end
    Window.PushPage = function(...)
        pushes = pushes + 1
        return nativePush(...)
    end
    for _, request in ipairs({
        { "Editor", function() UI.ShowEditor({ name = "Refused draft", pts = {}, cat = "other", mode = "loop" }) end },
        { "Import", function() UI.ShowText("import", "refused input") end },
        { "Copy", function() UI.ShowText("copy", "refused copy") end },
        { "Help", UI.ShowHelp }, { "Create", UI.ShowCreate },
    }) do
        local ok, err = pcall(request[2])
        check(ok and not Window.IsShown() and not Window.CurrentPage("routes"),
            label .. " " .. request[1] .. " respects panel refusal: " .. tostring(err))
    end
    check(pushes == 0 and focusCalls == beforeFocus, label .. " refusal pushes no pages and focuses no invisible fields")
    -- RoutesUI.Show also stops before its explicit refresh after refusal.
    local nativeAll, refreshes = Routes.All, 0
    Routes.All = function(...) refreshes = refreshes + 1; return nativeAll(...) end
    UI.Show()
    check(not Window.IsShown() and refreshes == 0, label .. " root stops after panel refusal")
    Routes.All, ShowUIPanel, Window.PushPage = nativeAll, nativeShow, nativePush
end
CheckPanelRefusal("Fresh")
ns.Set("routeThisZone", false)
UI.Show()
local w = UI.widgets
check(w.search:GetParent():GetWidth() == 260 and w.source:GetWidth() == 160 and w.zoneOnly.label:GetWidth() == 150,
    "filter row leaves 150 pixels for the translated zone label")
check(w.search:GetParent():GetWidth() + 6 + w.source:GetWidth() + 4 + w.zoneOnly:GetWidth() + 2 + w.zoneOnly.label:GetWidth() <= 618,
    "filter row including label spacing fits the content width")
-- The mock does not resolve anchors into sizes; provide the list's viewport.
w.list:SetHeight(264)
w.list:RunScript("OnSizeChanged")
check(Window.GetTab() == "routes" and UI.IsShown(), "Routes uses the shared window")
check(w.new == Window.tabs.routes.leftButton and w.import == Window.tabs.routes.leftButton2, "Create and Import are shell buttons")
check(not UI.Frames().help and not Window.CurrentPage("routes"), "first open has no help page")
check(w.detail.body:GetText() == L.ROUTES_HELP_TEXT and not w.detail.route, "first-open help is in the detail pane")
check(w.meta2 == w.detail.meta2 and w.detail.meta:GetText() == "" and w.meta2:GetText() == ""
    and not w.detail.meta:IsShown() and not w.meta2:IsShown(), "first-open help clears and hides both metadata lines")
check(w.detail.meta.parcelWordWrap == false and w.meta2.parcelWordWrap == false,
    "metadata lines each truncate without wrapping")
local metaPoint, meta2Point = w.detail.meta.parcelPoints[1], w.meta2.parcelPoints[1]
check(metaPoint[1] == "TOPLEFT" and metaPoint[2] == w.detail and metaPoint[3] == "TOPLEFT"
    and metaPoint[4] == 10 and metaPoint[5] == -30 and meta2Point[1] == "TOPLEFT"
    and meta2Point[2] == w.detail.meta and meta2Point[3] == "BOTTOMLEFT" and meta2Point[4] == 0 and meta2Point[5] == -2,
    "metadata lines stack at the specified top inset and spacing")
check(w.detail.meta.parcelPoints[2][1] == "RIGHT" and w.detail.meta.parcelPoints[2][2] == -10
    and w.meta2.parcelPoints[2][1] == "RIGHT" and w.meta2.parcelPoints[2][2] == -10,
    "each metadata line reserves the right inset")
check(w.help:GetWidth() == 16 and w.help:GetHeight() == 16, "native info button keeps its template size")
local point, relative, relativePoint, x, y = w.help:GetPoint()
check(point == "BOTTOMRIGHT" and relative == Window.tabs.routes.content and relativePoint == "BOTTOMRIGHT" and x == -6 and y == 8, "info button aligns with the footer")
M.tooltip = {}
w.help:RunScript("OnEnter")
check(M.tooltip[2] == L.ROUTES_DESC, "info button tooltip uses the short routes description")
check(w.list:GetParent()._backdrop == ns.Widgets.BACKDROP_BOX and w.list:GetParent():GetWidth() == 300, "routes list has a 300-pixel boxed holder")
check(w.detail.name.parcelFont == "GameFontNormalLarge", "route detail title uses the large native font")
for _, b in ipairs(w.detail.buttons) do
    local fs = b:GetFontString()
    check(fs and fs.parcelPoints[1][1] == "LEFT" and fs.parcelPoints[1][2] == 6 and fs.parcelPoints[2][1] == "RIGHT" and fs.parcelPoints[2][2] == -6 and fs.parcelWordWrap == false, "detail action label stays within the button art")
end
check(not ns.Get("routesHelpShown"), "inline help remains until a route is selected")
check(w.list.items[1] and w.rows[1]:IsShown() and w.rows[1].route == w.list.items[1], "routes render in list rows")
w.list:RunScript("OnMouseWheel", -1)
check(w.list.offset == 3 and w.rows[1].route == w.list.items[4], "list wheel scrolls three rows")
w.list:RunScript("OnMouseWheel", 1)
check(w.list.offset == 0, "list wheel returns to the first route")
w.detail.scroll:SetSize(240, 100)
w.detail.FitBody()
w.detail.scroll:RunScript("OnMouseWheel", -1)
check(w.detail.scroll:GetVerticalScroll() > 0, "long inline help can be scrolled")
local helpOffset = w.detail.scroll:GetVerticalScroll()
M.Tick(0.6)
check(w.detail.scroll:GetVerticalScroll() == helpOffset, "periodic refresh preserves help scroll position")
local openedRoutesSettings
local nativeOptionsOpen = ns.Options and ns.Options.Open
if not nativeOptionsOpen then
    ns.Options = ns.Options or {}
    ns.Options.Open = function(key) openedRoutesSettings = key end
end
w.net:GetParent():Click()
check(nativeOptionsOpen and M.settingsOpened ~= nil or openedRoutesSettings == "routes", "sharing footer opens Routes settings")
if not nativeOptionsOpen then ns.Options.Open = nil end
ns.Set("routeSharing", false)
check(w.net:GetText() == L.ROUTES_SHARING_OFF_LINE, "sharing footer reports sharing off")
ns.Set("routeSharing", true)
check(w.net:GetText() == L.ROUTES_SHARING_LINE:format(ns.RoutesNet.Status().peers), "sharing footer reports peers")
check(w.notice:IsShown() and w.notice.text:GetText() == L.TRAVEL_NEW_WINDOW, "Real routes notice explains the feature without a slash command")
w.notice.enable:Click()
check(ns.Get("realRoutes") and ns.Get("travelNoticeShown") and not w.notice:IsShown(), "notice enables Real routes and acknowledges it in one click")
ns.Set("realRoutes", false)
ns.Set("travelNoticeShown", false)
w.notice.dismiss:Click()
check(ns.Get("travelNoticeShown") and not w.notice:IsShown(), "notice dismissal persists and relayouts")
ns.Set("travelNoticeShown", false)
ns.Set("realRoutes", true)
check(not w.notice:IsShown(), "enabled Real routes hides the notice")
ns.Set("realRoutes", false)
check(w.notice:IsShown(), "notice returns until dismissed")
w.notice.dismiss:Click()

w.source:GenerateMenu()
local sourceMenu = M.lastMenu
check(#sourceMenu.items == 4 and sourceMenu.items[1].text == L.ROUTES_SOURCE_ALL, "Source dropdown has all four sources")
item(sourceMenu, L.ROUTES_TAB_SUGGESTED).fn()
local allSuggested = true
for _, r in ipairs(w.list.items) do allSuggested = allSuggested and r.src == "suggested" end
check(allSuggested and #w.list.items > 0, "Source selection filters ready-made routes")
w.rows[1]:Click()
local chosen = w.detail.route
check(chosen and chosen.id == w.rows[1].route.id and ns.Get("routesHelpShown"), "row selection replaces help and remembers it")
check(w.rows[1].sel:IsShown(), "selected route is marked")
check(w.detail.bodyFrame:GetHeight() > 0, "detail text has a scrollable body")
check(w.rows[1]:GetHeight() == 36 and w.rows[1].sub:GetText() == ns.Geo.GetMapName(ns.RouteMap.MapFor(chosen)) .. " · " .. Routes.CategoryLabel(chosen.cat),
    "route rows have a name and zone/category in 36 pixels")
check(w.rows[1].right:GetText() == "", "unvoted rows have no score or stop count")
check(w.map and w.map:IsShown() and #w.map.pins == #chosen.pts, "selection shows a pane preview with every stop")
local _, voteMap = w.detail.up:GetPoint()
local _, _, _, _, mapTop = w.map:GetPoint()
check(voteMap == w.map and mapTop == -58, "selected-route votes follow the map at its unchanged top inset")
check(#w.detail.buttons == 3 and w.detail.buttons[1]:IsShown() and w.detail.buttons[2]:IsShown() and w.more:IsShown()
    and w.more == w.detail.buttons[3] and w.more:GetText() == L.ROUTE_MORE, "action row has exactly three visible buttons with More last")
check(w.detail.body:GetText():find(L.ROUTE_STOPS_HEADER, 1, true) and w.detail.body:GetText():find("1. ", 1, true), "body lists numbered stops")
w.more:Click()
check(#M.lastMenu.items == 2 and M.lastMenu.items[2].text == L.ROUTE_COPY, "ready-made More menu only offers Copy text")
w.detail.up:Click()
local scoreRow
for _, row in ipairs(w.rows) do if row.route == chosen then scoreRow = row end end
local plainScore = scoreRow and scoreRow.right:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
check(plainScore == "+ 1", "an upvote adds only the vote score with an ASCII marker to the row")
w.detail.down:Click()
local voteUp, voteDown = Routes.Score(chosen.id)
check(voteUp == 0 and voteDown == 1 and Routes.MyVote(chosen.id) == -1,
    "clicking the opposite button replaces the upvote with one downvote")
w.detail.up:Click()
voteUp, voteDown = Routes.Score(chosen.id)
check(voteUp == 1 and voteDown == 0 and w.detail.down:GetText() == "- 0",
    "changing back replaces the downvote with one upvote")
w.detail.up:Click()
check(Routes.MyVote(chosen.id) == 0 and w.detail.up:GetText() == "+ 0", "clicking the same vote removes it")
w.detail.down:Click()
for _, row in ipairs(w.rows) do if row.route == chosen then scoreRow = row end end
plainScore = scoreRow.right:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
check(plainScore == "+ 0 - 1", "negative votes add the down score with an ASCII marker without the stop count")
w.detail.down:Click()
local nativeRefresh, refreshCalls = w.map.Refresh, 0
w.map.Refresh = function(self) refreshCalls = refreshCalls + 1; return nativeRefresh(self) end
M.Tick(0.6)
check(refreshCalls > 0, "tab updates refresh the preview player marker")
w.map.Refresh = nativeRefresh
M.tooltip = {}
GameTooltip:Hide()
w.rows[1]:RunScript("OnEnter")
w.rows[1]:RunScript("OnUpdate", 0.2)
check(not GameTooltip:IsShown(), "row tooltip waits before appearing")
w.rows[1]:RunScript("OnUpdate", 0.2)
check(GameTooltip:IsShown() and M.tooltip[1] == chosen.name, "row tooltip shows the category-coloured name after the delay")
w.rows[1]:RunScript("OnLeave")
check(not GameTooltip:IsShown(), "leaving a row hides its tooltip")
local nativeSetRoute, clearedMap = w.map.SetRoute, false
w.map.SetRoute = function(self, route)
    if route == nil then clearedMap = true end
    return nativeSetRoute(self, route)
end
Window.Hide()
check(clearedMap, "closing the Routes tab clears the preview widget")
UI.Show()
w.map.SetRoute = nativeSetRoute
check(w.detail.route and w.detail.body:GetText() ~= L.ROUTES_HELP_TEXT, "reopening keeps the chosen route")

-- Filtering and scrolling keep the list and detail in sync.
w.search:Type("zz_no_route_matches_zz")
check(#w.list.items == 0 and w.empty:IsShown() and w.detail.body:GetText() == L.ROUTES_PICK, "empty search shows empty state")
check(not w.map:IsShown() and not w.detail.buttons[1]:IsShown() and not w.more:IsShown(), "empty selection hides the preview and actions")
local _, emptyVoteAnchor = w.detail.up:GetPoint()
check(w.detail.meta:GetText() == "" and w.meta2:GetText() == "" and not w.detail.meta:IsShown()
    and not w.meta2:IsShown() and emptyVoteAnchor == w.meta2, "empty selection clears both metadata lines and anchors votes to line two")
w.search.clearButton:Click()
check(w.search:GetText() == "" and #w.list.items > 0, "clearing search restores routes")
w.cat:GenerateMenu()
item(M.lastMenu, Routes.CategoryLabel("mining")).fn()
local mining = #w.list.items > 0
for _, r in ipairs(w.list.items) do mining = mining and r.cat == "mining" end
check(mining, "category menu filters routes")
w.cat:GenerateMenu()
item(M.lastMenu, L.ROUTES_ALL_CATEGORIES).fn()
-- Fitting levels sort before nearby out-of-range routes, then nearest edges,
-- then routes without levels. Distance orders equally fitting routes.
local nativeAll, nativeDistance, nativeLevel, nativeGet = Routes.All, Routes.Distance, UnitLevel, Routes.Get
local function levelRoute(id, name, lv, distance)
    return { id = id, name = name, cat = "mining", src = "suggested", mode = "order", zone = 37,
        pts = { { m = 37, x = 0.4, y = 0.5 } }, lv = lv, faction = "A", distance = distance }
end
local farFit = levelRoute("r9-far", "Far fitting route", { min = 18, max = 22 }, 100)
local nearFit = levelRoute("r9-near", "Near fitting route", { min = 20 }, 50)
local nearEdge = levelRoute("r9-edge", "Near edge route", { min = 21, max = 25 }, 30)
local farEdge = levelRoute("r9-out", "Far edge route", { min = 1, max = 10 }, 1)
local noLevel = levelRoute("r9-any", "Any level route", nil, 0)
Routes.All = function() return { noLevel, farEdge, nearEdge, farFit, nearFit } end
Routes.Distance = function(r) return r.distance end
Routes.Get = function(id)
    for _, r in ipairs(Routes.All()) do if r.id == id then return r end end
    return nativeGet(id)
end
UnitLevel = function() return 20 end
w.sort:GenerateMenu()
check(#M.lastMenu.items == 4 and item(M.lastMenu, L.ROUTES_SORT_LEVEL), "Sort has four choices including For my level")
item(M.lastMenu, L.ROUTES_SORT_LEVEL).fn()
check(w.list.items[1] == nearFit and w.list.items[2] == farFit and w.list.items[3] == nearEdge
    and w.list.items[4] == farEdge and w.list.items[5] == noLevel, "level sort orders fits, distance, closest edges and unknown levels")
UI.Select(nearFit.id)
check(w.meta2:GetText():find(L.ROUTE_LEVELS_UP:format(20), 1, true)
    and w.detail.meta:GetText():find(L.ROUTE_FACTION_A, 1, true), "detail metadata shows structured levels and faction")
local expectedMeta2 = L.ROUTE_LEVELS_UP:format(20) .. " · " .. Routes.ModeLabel(nearFit.mode)
    .. " · " .. L.ROUTES_POINTS:format(1) .. " · " .. L.ROUTES_AWAY:format(ns.Geo.FormatDistance(50))
check(w.meta2:IsShown() and w.detail.meta:IsShown() and w.meta2:GetText() == expectedMeta2
    and not w.detail.meta:GetText():find("\n", 1, true), "line two preserves levels, mode, stops and distance independently")
local nativeMapName = ns.Geo.GetMapName
ns.Geo.GetMapName = function(mapID)
    return mapID == 37 and string.rep("Long zone name ", 20) or nativeMapName(mapID)
end
UI.Refresh()
check(w.detail.meta:GetStringWidth() > 290 and w.meta2:GetText() == expectedMeta2,
    "an overlong first metadata line cannot consume the second line")
ns.Geo.GetMapName = nativeMapName
UI.Refresh()
M.tooltip = {}
w.rows[1]:RunScript("OnEnter")
w.rows[1]:RunScript("OnUpdate", 0.4)
check(M.tooltip[2] == L.ROUTE_LEVELS_UP:format(20) and M.tooltip[3] == L.ROUTE_FACTION_A
    and M.tooltip[4]:find(L.ROUTES_POINTS:format(1), 1, true), "row tooltip includes level, faction, category, zone and stops")
w.rows[1]:RunScript("OnLeave")
w.search:Type(L.ROUTE_LEVELS_UP:format(20))
check(#w.list.items == 1 and w.list.items[1] == nearFit, "search includes the structured level text")
w.search:Type(L.ROUTE_FACTION_A)
check(#w.list.items == 5, "search includes the structured faction text")
w.search.clearButton:Click()
local nativeFits = Routes.FitsLevel
Routes.FitsLevel, UnitLevel = nil, nil
UI.Refresh()
check(w.list.items[1] == noLevel, "level sort without optional helpers or UnitLevel falls back to distance")
Routes.All, Routes.Distance, Routes.FitsLevel, UnitLevel, Routes.Get = nativeAll, nativeDistance, nativeFits, nativeLevel, nativeGet
UI.Refresh()
w.sort:GenerateMenu()
item(M.lastMenu, L.ROUTES_SORT_NEW).fn()
check(w.sort:GetText() == L.ROUTES_SORT_NEW, "Sort selection updates the label")
w.zoneOnly:Click()
local inZone = true
local here = C_Map.GetBestMapForUnit("player")
for _, r in ipairs(w.list.items) do
    local match
    for _, pt in ipairs(r.pts) do if ns.Geo.SameMap(pt.m, here) then match = true end end
    inZone = inZone and match
end
check(ns.Get("routeThisZone") and inZone, "This zone filters routes to the player map")
w.zoneOnly:Click()
UI.Select(chosen.id)

-- Use a generated gathering route entirely on Elwynn Forest for preview clicks.
local gathering
for _, r in ipairs(Routes.All()) do
    if r.src == "suggested" and r.cat == "mining" and r.zone == 37 then gathering = r; break end
end
check(gathering ~= nil, "ready-made gathering fixture is available")
UI.Select(gathering.id)
local gatheringRow
for i, r in ipairs(w.list.items) do if r.id == gathering.id then w.list:ScrollTo(i); break end end
for _, row in ipairs(w.rows) do if row.route == gathering then gatheringRow = row end end
check(gatheringRow and not gatheringRow.text:GetText():find("%d") and gatheringRow.text:GetText() == gathering.name,
    "gathering row name contains no digits, zone or stop count")
local nativePreview, previewCall = ns.RoutePreview.Show
ns.RoutePreview.Show = function(id, mapID) previewCall = { id, mapID }; return true end
w.map:Click()
check(previewCall and previewCall[1] == gathering.id and previewCall[2] == 37, "preview click forwards the selected route ID and map 37")
ns.RoutePreview.Show = function() return false, ns.InCombat() and "combat" or "nomap" end
M.player.combat = true
w.map:Click()
check(w.status:GetText() == L.IN_COMBAT_NO_PANELS and not M.actionBlocked, "combat preview failure appears in the status line without protected calls")
M.player.combat = false
ns.RoutePreview.Show = nil
w.map:Click()
check(w.status:GetText() == L.ROUTE_PREVIEW_UNAVAILABLE, "missing preview module shows a useful status")
ns.RoutePreview.Show = nativePreview
UI.Select(chosen.id)

WP.ClearAll(true)
WP.Add(37, 0.42, 0.5, "Existing")
ns.Set("routeApply", "ask")
M.autoAltPopup = true
ns.Fire("ROUTE_ASK", chosen.id, 1)
check(M.lastPopup == "WAYPOINTTRACKER_ROUTE_ASK" and M.lastPopupArgs[1] == 1 and M.lastPopupArgs[3] == chosen.id, "route question carries count and route ID")
check(WP.Count() == #chosen.pts + 1 and Routes.Run().id == chosen.id, "popup Add keeps the existing waypoint")
check(w.detail.buttons[1]:GetText() == L.ROUTE_STOP and w.detail.buttons[2]:GetText() == L.ROUTE_SKIP
    and w.more:GetText() == L.ROUTE_MORE and not w.detail.share, "running action row offers Stop, Skip and More")
local popup = StaticPopupDialogs.WAYPOINTTRACKER_ROUTE_ASK
check(popup.button1 == L.ROUTE_ASK_REPLACE and popup.button3 == L.ROUTE_ASK_ADD and popup.button2 == (CANCEL or L.NO), "route question uses the three native buttons")
check(popup.text == L.ROUTE_ASK_TITLE:format(chosen.name) .. "\n\n" .. L.ROUTE_ASK_TEXT .. "\n\n" .. L.ROUTE_ASK_FOOTER, "route question names the route and explains the Settings choice")
local originalName = chosen.name
chosen.name = "75% scenic route"
ns.Fire("ROUTE_ASK", chosen.id, 1)
local askOK, askText = pcall(string.format, popup.text, 1)
check(askOK and askText:find(L.ROUTE_ASK_TITLE:format(chosen.name), 1, true), "percent signs in route names are safe in the start popup")
chosen.name = originalName
Routes.Stop(true)
WP.ClearAll(true)
WP.Add(37, 0.42, 0.5, "Existing")
UI.Select(chosen.id)
action(w.detail, L.ROUTE_START):Click()
check(M.lastPopup == "WAYPOINTTRACKER_ROUTE_ASK" and WP.Count() == #chosen.pts + 1, "detail Start invokes the Add popup")
M.autoAltPopup = false
M.autoAcceptPopup = true
ns.Fire("ROUTE_ASK", chosen.id, 1)
check(WP.Count() == #chosen.pts, "popup Replace replaces existing waypoints")
M.autoAcceptPopup = false
Routes.Stop(true)
WP.ClearAll(true)
WP.Add(37, 0.42, 0.5, "Keep")
M.autoCancelPopup = true
ns.Fire("ROUTE_ASK", chosen.id, 1)
check(WP.Count() == 1 and not Routes.Run(), "cancel leaves waypoints alone")
M.autoCancelPopup = false

M.autoAcceptPopup = true
ns.Fire("ROUTE_FEEDBACK", chosen.id, 240)
check(M.lastPopup == "WAYPOINTTRACKER_ROUTE_FEEDBACK" and Routes.MyVote(chosen.id) == 1, "feedback Good votes up")
check(M.sounds[#M.sounds] == ((SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN) or 875), "feedback plays quest-list sound")
M.autoAcceptPopup, M.autoAltPopup = false, true
ns.Fire("ROUTE_FEEDBACK", chosen.id, 240)
check(Routes.MyVote(chosen.id) == -1 and StaticPopupDialogs.WAYPOINTTRACKER_ROUTE_FEEDBACK.text:find(L.ROUTE_FEEDBACK_WAS_UP, 1, true), "feedback Not good changes vote and mentions the previous vote")
M.autoAltPopup, M.autoCancelPopup = false, true
ns.Fire("ROUTE_FEEDBACK", chosen.id, 240)
check(Routes.MyVote(chosen.id) == -1, "feedback Not now leaves the vote unchanged")
local routeName = chosen.name
chosen.name = "75% scenic route"
ns.Fire("ROUTE_FEEDBACK", chosen.id, 240)
local formattedOK, feedbackText = pcall(string.format, StaticPopupDialogs.WAYPOINTTRACKER_ROUTE_FEEDBACK.text)
check(formattedOK and feedbackText:find(chosen.name, 1, true), "percent signs in route names are safe in popup text")
chosen.name = routeName
M.autoCancelPopup = false
Routes.Vote(chosen.id, 0)

UI.ShowHelp()
check(Window.CurrentPage("routes").title == L.ROUTES_HELP_TITLE and UI.Frames().help.text:GetText() == L.ROUTES_HELP_TEXT, "help pushes an in-tab page")
UI.Frames().help.ok:Click()
check(not Window.CurrentPage("routes"), "help Got it returns to the root")
local firstHelpPage = UI.Frames().help
UI.ShowHelp()
check(UI.Frames().help == firstHelpPage and Window.CurrentPage("routes").key == "help", "help reuses its keyed page")
Window.PopPage("routes")
UI.ShowCreate()
local create = UI.Frames().create
check(Window.CurrentPage("routes").title == L.ROUTE_CREATE_TITLE and create.fromWp:GetParent() == create, "Create page has the waypoint choice")
Window.PopPage("routes")
WP.ClearAll(true)
UI.ShowCreate()
check(UI.Frames().create == create and Window.CurrentPage("routes").key == "create", "Create reuses its keyed page")
create = UI.Frames().create
check(not create.fromWp:IsEnabled() and create.fromWpText:GetText() == L.ROUTE_NEW_NONE, "reopened Create refreshes the waypoint choice")
M.tooltip = {}
create.fromWp:Hover(true)
check(M.tooltip[2] == L.ROUTE_NEW_NONE and GameTooltip:IsShown(), "disabled waypoint choice explains why it is unavailable on hover")
create.fromWp:Hover(false)
check(not GameTooltip:IsShown(), "leaving the disabled waypoint choice hides its tooltip")
create.paste:Click()
local text = UI.Frames().text
check(Window.CurrentPage("routes").title == L.ROUTE_IMPORT_TITLE, "Paste choice opens Import page")
text.edit:SetText("not a route")
text.action:Click()
check(text.result:GetText() == L.ROUTE_IMPORT_NOTHING and text:IsVisible(), "invalid import leaves a useful result")
Window.PopPage("routes")
UI.ShowText("import", "fresh input")
check(UI.Frames().text == text and Window.CurrentPage("routes").key == "import", "Import reuses its keyed page")
text = UI.Frames().text
check(text.edit:GetText() == "fresh input" and text.result:GetText() == "", "reopened Import replaces input and clears the previous error")
text.edit:SetText("/way Elwynn Forest 42 50 One\n/way Elwynn Forest 45 55 Two\n/way Elwynn Forest 50 60 Three")
text.action:Click()
local editor = UI.Frames().editor
local importedDraft = editor.draft
w.search:SetText("a filter that hides this draft")
w.cat:GenerateMenu()
item(M.lastMenu, Routes.CategoryLabel("mining")).fn()
check(editor and #editor.draft.pts == 3 and Window.CurrentPage("routes").title == L.ROUTE_NEW_TITLE, "Import parses /way lines into an editor draft")
editor.name.edit:SetText("P7 Test Route")
editor.note.edit:SetText("A helpful note")
editor.public:SetChecked(false)
editor.save:Click()
local saved = w.detail.route
check(saved and saved.name == "P7 Test Route" and saved.note == "A helpful note" and not saved.public and Routes.IsMine(saved), "editor saves the fields")
check(not Window.CurrentPage("routes") and w.source:GetText() == L.ROUTES_TAB_MINE and w.list:GetSelected() == saved, "Save returns to Mine with the route selected")
check(w.status:GetText() == L.ROUTE_SAVED:format(saved.name), "Save sets the status line")
check(w.search:GetText() == "" and w.cat:GetText() == L.ROUTES_ALL_CATEGORIES, "Save clears filters that could hide the saved route")
check(M.lastMenu.items[1].text == L.ROUTE_SHARE_SAVED_TITLE, "Save opens the sharing menu with the saved title")

UI.ShowText("copy", Routes.Serialize(saved))
text = UI.Frames().text
check(text.edit:GetText() == Routes.Serialize(saved) and not text.action:IsShown(), "Copy page contains exactly the serialized route")
text.back:Click()
UI.ShowText("copy", "replacement copy text")
check(UI.Frames().text == text and Window.CurrentPage("routes").key == "copy", "Copy reuses its keyed page")
check(UI.Frames().text.edit:GetText() == "replacement copy text" and not UI.Frames().text.action:IsShown(), "reopened Copy replaces text and keeps Import hidden")
Window.PopPage("routes")
UI.ShowShare(saved)
local menu, channels = M.lastMenu, ns.Share.Channels()
check(menu.items[1].text == L.ROUTE_SHARE_TITLE:format(saved.name) and #menu.items == #channels + 4, "Share menu has a title, every channel, Send and Copy")
local sendTooltip = item(menu, L.ROUTE_SEND_TARGET).tooltip
local tooltipTitle, tooltipBody
local nativeTooltipTitle, nativeTooltipLine = GameTooltip_SetTitle, GameTooltip_AddNormalLine
GameTooltip_SetTitle = function(_, value) tooltipTitle = value end
GameTooltip_AddNormalLine = function(_, value) tooltipBody = value end
if sendTooltip then sendTooltip(GameTooltip) end
check(tooltipTitle == L.ROUTE_SEND_TARGET and tooltipBody == L.ROUTE_SEND_TARGET_DESC, "native Send menu tooltip explains the target requirement")
GameTooltip_SetTitle, GameTooltip_AddNormalLine = nativeTooltipTitle, nativeTooltipLine
for _, ch in ipairs(channels) do
    check(item(menu, L.ROUTE_SHARE_POST:format(ch[1])) ~= nil, "share entry for " .. ch[1])
end
item(menu, L.ROUTE_SHARE_POST:format(channels[1][1])).fn()
local msg = L.ROUTE_CHAT_LINE:format(saved.name, #saved.pts, ns.Geo.GetMapName(saved.zone) or "")
local link = ns.Share.MapPinLink(saved.pts[1])
if link then msg = msg .. " " .. link end
if ns.Get("sharePrefix") then msg = ns.Share.PREFIX .. " " .. msg end
check(M.chatText == channels[1][2] .. " " .. msg, "Post opens chat with channel prefix and route pin")
local sent
local originalSend = ns.RoutesNet.SendTo
ns.RoutesNet.SendTo = function(id, name) sent = { id, name }; return true end
M.units.target = { player = true, name = "Friend" }
item(menu, L.ROUTE_SEND_TARGET).fn()
check(sent and sent[1] == saved.id and sent[2] == "Friend", "Send targets the selected player")
ns.RoutesNet.SendTo = originalSend
M.units.target = nil
item(menu, L.ROUTE_COPY).fn()
check(UI.Frames().text.edit:GetText() == Routes.Serialize(saved), "Share Copy pushes the Copy page")
Window.PopAll("routes")
UI.ShowEditor(saved)
check(UI.Frames().editor == editor and Window.CurrentPage("routes").key == "editor", "Edit and New route reuse one keyed editor")
check(UI.Frames().editor.draft.id == saved.id and UI.Frames().editor.name.edit:GetText() == saved.name, "reopened editor binds the current route")
local currentEditor = UI.Frames().editor
currentEditor.cat:GenerateMenu()
item(M.lastMenu, Routes.CategoryLabel("herbs")).fn()
currentEditor.mode:GenerateMenu()
item(M.lastMenu, Routes.ModeLabel("nearest")).fn()
currentEditor.public:Click()
check(currentEditor.draft.cat == "herbs" and currentEditor.draft.mode == "nearest" and currentEditor.draft.public and importedDraft ~= currentEditor.draft and not importedDraft.public, "reused editor pickers and checkbox modify only the current draft")
UI.Frames().editor.note.edit:SetText("Updated note")
UI.Frames().editor.save:Click()
saved = w.detail.route
check(saved and saved.note == "Updated note" and saved.v == 2 and saved.cat == "herbs" and saved.mode == "nearest" and saved.public, "editing saves the current draft, preserves the route ID and increments its version")

w.more:Click()
local mineMenu = M.lastMenu
check(#mineMenu.items == 5 and mineMenu.items[2].text == L.ROUTE_COPY and mineMenu.items[3].text == L.ROUTE_EDIT
    and mineMenu.items[4].kind == "divider" and mineMenu.items[5].text == L.ROUTE_DELETE,
    "mine More menu offers Copy text, Edit and Delete")
item(mineMenu, L.ROUTE_COPY).fn()
check(UI.Frames().text.edit:GetText() == Routes.Serialize(saved), "More Copy text opens the serialized route")
Window.PopAll("routes")
item(mineMenu, L.ROUTE_EDIT).fn()
check(UI.Frames().editor.draft.id == saved.id, "More Edit opens the selected route")
Window.PopAll("routes")

-- Native delete confirmation must cancel without deleting and use fresh callbacks.
w.more:Click()
item(M.lastMenu, L.ROUTE_DELETE).fn()
check(M.lastPopup == "WAYPOINTTRACKER_ROUTE_DELETE" and Routes.Get(saved.id), "Delete asks before removing a route")
StaticPopupDialogs.WAYPOINTTRACKER_ROUTE_DELETE.OnCancel(M.popups.WAYPOINTTRACKER_ROUTE_DELETE, saved.id)
check(Routes.Get(saved.id) ~= nil, "cancelled Delete keeps the route")
M.autoAcceptPopup = true
w.more:Click()
item(M.lastMenu, L.ROUTE_DELETE).fn()
check(not Routes.Get(saved.id), "confirmed Delete removes the route")
M.autoAcceptPopup = false

local shared = Routes.Keep({ id = "r9shared", name = "Shared trail", author = "Visitor-TestRealm", cat = "travel", mode = "order",
    pts = { { m = 37, x = 0.4, y = 0.5, t = "One" }, { m = 52, x = 0.5, y = 0.6, t = "Two" } } })
UI.SetTab("shared")
UI.Select(shared.id)
w.more:Click()
local sharedMenu = M.lastMenu
check(#sharedMenu.items == 5 and sharedMenu.items[2].text == L.ROUTE_COPY and sharedMenu.items[3].kind == "divider"
    and sharedMenu.items[4].text == L.ROUTE_REMOVE and sharedMenu.items[5].text == L.ROUTE_BLOCK,
    "shared More menu offers Copy text, Remove and Hide This Author")
check(w.detail.meta:GetText():find(L.ROUTE_SPANS:format(ns.Geo.GetMapName(13)), 1, true), "detail names the common continent for a route spanning zones")
check(w.rows[1].sub:GetText() == ns.Geo.GetMapName(13) .. " · " .. Routes.CategoryLabel("travel"), "multi-zone row subtitle uses the common map")
item(sharedMenu, L.ROUTE_REMOVE).fn()
check(not Routes.Get(shared.id), "More Remove removes a shared route")
shared = Routes.Keep({ id = "r9block", name = "Another shared trail", author = "Visitor-TestRealm", cat = "travel", mode = "order",
    pts = { { m = 37, x = 0.4, y = 0.5 } } })
UI.Select(shared.id)
w.more:Click()
item(M.lastMenu, L.ROUTE_BLOCK).fn()
check(not Routes.Get(shared.id) and w.status:GetText() == L.ROUTE_BLOCKED:format(Routes.ShortName(shared.author)), "More Hide This Author removes the author's routes and reports it")
UI.SetTab("suggested")
UI.Select(chosen.id)

Routes.RecordStart()
local recorder = UI.Frames().recorder
check(recorder == ns.Recorder.frame and recorder:IsShown() and recorder:GetWidth() == 430 and recorder:GetHeight() == 78, "recording shows the 430 by 78 HUD")
check(not recorder:GetScript("OnDragStart") and not recorder:IsMouseEnabled(), "HUD cannot be dragged outside Edit Mode")
for _, button in ipairs({ recorder.add, recorder.finish, recorder.cancel }) do
    check(button:GetWidth() >= button:GetFontString():GetStringWidth() + 24, "recorder button fits its label with native padding")
end
check(14 + recorder.add:GetWidth() + 6 + recorder.finish:GetWidth() + 6 + recorder.cancel:GetWidth() + 14 <= recorder:GetWidth(),
    "recorder buttons fit between the strip margins")
check(recorder.auto.label:GetHeight() >= 3 * 12 and recorder.auto.label:GetHeight() <= recorder:GetHeight() - 24 - 8,
    "recorder checkbox has room for three lines above the buttons")
check(not recorder.finish:GetScript("OnEnter"), "Finish does not show an Edit Mode hint tooltip")
check(registered and registered.key == "recorder" and registered.shouldShow() and #registered.settings == 0 and applied.recorder, "recorder registers the Edit Mode system and applies its position")
check(not Window.IsShown(), "starting a recording hides the open window")
UI.Show()
recorder.add:Click()
check(Window.IsShown(), "adding stops permits browsing the window during recording")
recorder.add:Click()
check(#Routes.Recording().pts == 2 and recorder.text:GetText() == L.ROUTE_REC_HUD:format(2), "Add stop increments the recording and HUD count")
recorder.auto:Click()
check(not Routes.Recording().auto, "Auto checkbox controls gathering stops")
recorder.finish:Click()
check(not Routes.Recording() and not recorder:IsShown() and UI.IsShown() and Window.CurrentPage("routes").title == L.ROUTE_NEW_TITLE, "Finish opens Routes with the editor page")
check(#UI.Frames().editor.draft.pts == 2, "Finish passes the recording draft to the editor")
Window.Hide()
UI.Show()
check(not Window.CurrentPage("routes"), "closing discards the editor page")
UI.ShowCreate()
UI.Frames().create.record:Click()
check(not Window.IsShown() and Routes.Recording() and recorder:IsShown(), "Record choice hides the window and shows the HUD")
recorder.cancel:Click()
check(not Routes.Recording() and not recorder:IsShown(), "Cancel hides the recorder")

M.recorderEditActive = true
EditModeManagerFrame:EnterEditMode()
check(recorder:IsShown() and recorder.text:GetText() == L.ROUTE_REC_HUD:format(0), "Edit Mode shows the recorder preview without starting a recording")
M.recorderEditActive = false
EditModeManagerFrame:ExitEditMode()
check(not recorder:IsShown() and not Routes.Recording(), "leaving Edit Mode hides the idle recorder")
Routes.RecordStart()
EditModeManagerFrame:EnterEditMode()
recorder.cancel:Click()
check(recorder:IsShown() and recorder.text:GetText() == L.ROUTE_REC_HUD:format(0), "cancelling during Edit Mode keeps the idle preview")
EditModeManagerFrame:ExitEditMode()
check(not recorder:IsShown(), "exit hides a recorder cancelled during Edit Mode")
EditModeManagerFrame:EnterEditMode()
Routes.RecordStart()
EditModeManagerFrame:ExitEditMode()
check(recorder:IsShown() and Routes.Recording(), "exit retains a recording started during Edit Mode")
Routes.RecordCancel()
check(not recorder:IsShown(), "cancelling after Edit Mode hides the HUD")
Window.Hide()
M.player.combat = true
local panelCalls = M.uiPanelCalls.show + M.uiPanelCalls.hide
UI.ShowEditor(chosen)
Window.Hide()
check(panelCalls == M.uiPanelCalls.show + M.uiPanelCalls.hide and not M.actionBlocked, "Routes pages show and close during combat without protected panel calls")
M.player.combat = false
CheckPanelRefusal("Cached")

-- Optional native menus, templates and popups may all be missing.
local nativeCreate, nativeMenu, nativePopup = CreateFrame, MenuUtil, StaticPopup_Show
CreateFrame = function(kind, name, parent, template)
    if template == "WowStyle1DropdownTemplate" or template == "UIPanelInfoButton" or template == "InputScrollFrameTemplate" then error("missing template") end
    return nativeCreate(kind, name, parent, template)
end
MenuUtil, StaticPopup_Show = nil, nil
UI.Show()
UI.SetTab("suggested")
UI.Select(chosen.id)
ns.Fire("ROUTE_ASK", chosen.id, WP.Count())
check(Routes.Run() and Routes.Run().id == chosen.id, "missing popup API applies the primary action")
Routes.Stop(true)
-- Force new controls for the missing-template branch; the normal path above
-- checks reuse against the actual Window implementation.
Window.PopAll("routes")
if Window.tabs.routes.pageCache then Window.tabs.routes.pageCache.editor = nil; Window.tabs.routes.pageCache.copy = nil end
UI.ShowEditor(chosen)
local fallbackEditor = UI.Frames().editor
local before = fallbackEditor.draft.mode
fallbackEditor.mode.next:Click()
check(fallbackEditor.draft.mode ~= before, "editor dropdown falls back to a cycling picker")
UI.ShowText("copy", "fallback text")
check(UI.Frames().text.edit:GetText() == "fallback text", "text area falls back without the native template")
UI.ShowShare(chosen)
check(ns.Widgets.lastMenu and M.chatOpen, "Share falls back to the first channel action")
Window.PopAll("routes")
UI.Select(chosen.id)
w.more:Click()
check(Window.CurrentPage("routes").key == "copy" and UI.Frames().text.edit:GetText() == Routes.Serialize(chosen), "ready-made More without MenuUtil runs Copy text")
Window.PopAll("routes")
local fallbackMine = Routes.SaveMine({ name = "Fallback editing", pts = { { m = 37, x = 0.4, y = 0.5 } } })
UI.SetTab("mine")
UI.Select(fallbackMine.id)
w.more:Click()
check(Window.CurrentPage("routes").key == "copy" and UI.Frames().text.edit:GetText() == Routes.Serialize(fallbackMine)
    and Routes.Get(fallbackMine.id) == fallbackMine, "mine More without MenuUtil runs Copy text and preserves the route")
Window.PopAll("routes")
Routes.Delete(fallbackMine.id)
CreateFrame, MenuUtil, StaticPopup_Show = nativeCreate, nativeMenu, nativePopup
Window.Hide()

-- Build once without either preview module, as on the scaffold/bare client.
local nativeMap, nativeLevelText, nativeFactionText, nativeStopTitle = ns.RouteMap, Routes.LevelText, Routes.FactionText, Routes.StopTitle
ns.RouteMap, Routes.LevelText, Routes.FactionText, Routes.StopTitle = nil, nil, nil, nil
local fallbackContent = CreateFrame("Frame", nil, Window.tabs.routes.content)
fallbackContent:SetSize(618, 430)
Window.tabs.routes.spec.build(fallbackContent)
w = UI.widgets
UI.SetTab("suggested")
UI.Select(chosen.id)
check(w.map == nil and w.detail.route.id == chosen.id and w.detail.body:GetText():find(L.ROUTE_STOPS_HEADER, 1, true),
    "missing RouteMap and metadata helpers retain the text detail and stops")
local scrollPoint, _, _, _, scrollBottom = w.detail.scroll:GetPoint(1)
local _, voteAnchor = w.detail.up:GetPoint(1)
check(scrollPoint == "BOTTOMRIGHT" and scrollBottom == 44 and voteAnchor == w.meta2,
    "without a map the body follows both metadata lines and votes")
check(w.meta2:GetText() == Routes.ModeLabel(chosen.mode) .. " · " .. L.ROUTES_POINTS:format(#chosen.pts)
    .. (Routes.Distance(chosen) and (" · " .. L.ROUTES_AWAY:format(ns.Geo.FormatDistance(Routes.Distance(chosen)))) or ""),
    "without metadata helpers line two still shows mode, stops and available distance")
ns.RouteMap, Routes.LevelText, Routes.FactionText, Routes.StopTitle = nativeMap, nativeLevelText, nativeFactionText, nativeStopTitle

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("Routes tab tests: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
