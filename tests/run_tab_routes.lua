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

-- Model the native info-button size and button FontString so the reviewed
-- geometry runs through the same controls as FrameXML.
local originalCreate = CreateFrame
CreateFrame = function(kind, name, parent, template)
    local f = originalCreate(kind, name, parent, template)
    local createFontString = f.CreateFontString
    function f:CreateFontString(name, layer, font)
        local fs = createFontString(self, name, layer, font)
        fs.parcelFont = font
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
        local setPoint = fs.SetPoint
        function fs:SetPoint(...)
            self.parcelPoints = self.parcelPoints or {}
            self.parcelPoints[#self.parcelPoints + 1] = { ... }
            setPoint(self, ...)
        end
        function fs:SetWordWrap(on) self.parcelWordWrap = on end
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
Window.Hide()
UI.Show()
check(w.detail.route and w.detail.body:GetText() ~= L.ROUTES_HELP_TEXT, "reopening keeps the chosen route")

-- Filtering and scrolling keep the list and detail in sync.
w.search:Type("zz_no_route_matches_zz")
check(#w.list.items == 0 and w.empty:IsShown() and w.detail.body:GetText() == L.ROUTES_PICK, "empty search shows empty state")
w.search.clearButton:Click()
check(w.search:GetText() == "" and #w.list.items > 0, "clearing search restores routes")
w.cat:GenerateMenu()
item(M.lastMenu, Routes.CategoryLabel("mining")).fn()
local mining = #w.list.items > 0
for _, r in ipairs(w.list.items) do mining = mining and r.cat == "mining" end
check(mining, "category menu filters routes")
w.cat:GenerateMenu()
item(M.lastMenu, L.ROUTES_ALL_CATEGORIES).fn()
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

WP.ClearAll(true)
WP.Add(37, 0.42, 0.5, "Existing")
ns.Set("routeApply", "ask")
M.autoAltPopup = true
ns.Fire("ROUTE_ASK", chosen.id, 1)
check(M.lastPopup == "WAYPOINTTRACKER_ROUTE_ASK" and M.lastPopupArgs[1] == 1 and M.lastPopupArgs[3] == chosen.id, "route question carries count and route ID")
check(WP.Count() == #chosen.pts + 1 and Routes.Run().id == chosen.id, "popup Add keeps the existing waypoint")
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

-- Native delete confirmation must cancel without deleting and use fresh callbacks.
action(w.detail, L.ROUTE_DELETE):Click()
check(M.lastPopup == "WAYPOINTTRACKER_ROUTE_DELETE" and Routes.Get(saved.id), "Delete asks before removing a route")
StaticPopupDialogs.WAYPOINTTRACKER_ROUTE_DELETE.OnCancel(M.popups.WAYPOINTTRACKER_ROUTE_DELETE, saved.id)
check(Routes.Get(saved.id) ~= nil, "cancelled Delete keeps the route")
M.autoAcceptPopup = true
action(w.detail, L.ROUTE_DELETE):Click()
check(not Routes.Get(saved.id), "confirmed Delete removes the route")
M.autoAcceptPopup = false

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
CreateFrame, MenuUtil, StaticPopup_Show = nativeCreate, nativeMenu, nativePopup
Window.Hide()

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("Routes tab tests: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
