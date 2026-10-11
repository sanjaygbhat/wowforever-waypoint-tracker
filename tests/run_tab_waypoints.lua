-- The Waypoints home and the legacy UI entry points, with Lua 5.1.
-- Run from the repo root: lua5.1 tests/run_tab_waypoints.lua [--bare]
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local bare = arg and arg[1] == "--bare"
if bare then
    MenuUtil, HelpTip, StaticPopup_Show, StaticPopupDialogs = nil, nil, nil, nil
    RegisterUIPanel, ShowUIPanel, HideUIPanel = nil, nil, nil
    PanelTemplates_SetNumTabs, PanelTemplates_SetTab, PanelTemplates_TabResize = nil, nil, nil
    local createFrame = CreateFrame
    function CreateFrame(kind, name, parent, template)
        if template == "ButtonFrameTemplate" or template == "SearchBoxTemplate"
            or template == "InputBoxTemplate" or template == "MagicButtonTemplate" then
            error("missing template: " .. template)
        end
        return createFrame(kind, name, parent, template)
    end
end

-- The shared mock does not gate disabled-button input. Model that path here
-- so the tooltip check requires the same opt-in as a real Blizzard button.
local createFrame = CreateFrame
function CreateFrame(kind, name, parent, template)
    local frame = createFrame(kind, name, parent, template)
    if kind == "Button" then
        function frame:SetMotionScriptsWhileDisabled(enabled)
            self.motionWhileDisabled = enabled
        end
        local runScript, click = frame.RunScript, frame.Click
        function frame:RunScript(event, ...)
            if (event == "OnEnter" or event == "OnLeave")
                and not self:IsEnabled() and not self.motionWhileDisabled then return end
            return runScript(self, event, ...)
        end
        function frame:Click(...)
            if self:IsEnabled() then return click(self, ...) end
        end
    end
    return frame
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function near(a, b) return a and math.abs(a - b) < 0.00001 end
local function findItem(menu, text)
    for _, item in ipairs(menu and menu.items or {}) do
        if item.text == text then return item end
    end
end

WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local WP, L, Window = ns.WP, ns.L, ns.Window
local setStatus, statusMode = Window.SetStatus
Window.SetStatus = function(text, mode)
    statusMode = mode
    return setStatus(text, mode)
end

ns.UI.Show()
CreateFrame = createFrame
local w = ns.TabWaypoints.widgets
check(ns.UI.IsShown() and Window.GetTab() == "waypoints", "UI.Show opens home")
check(ns.UI.W == ns.Widgets and ns.UI.widgets == w, "compat shares widgets")
check(w.add and w.name and w.set and w.here and w.zoneList and w.list and w.status and w.clearAll,
    "public test widgets are present")
check(w.status == Window.frame.status, "Add feedback uses the shared window status")
check(not w.clearAll:IsEnabled(), "Remove All starts disabled with no waypoints")
M.lastPopup = nil
w.clearAll:Click()
check(WP.Count() == 0 and M.lastPopup == nil, "disabled Remove All ignores clicks")
for _, button in ipairs({ w.here, w.set }) do
    check(button:GetWidth() >= button:GetFontString():GetStringWidth() + 24 and button:GetHeight() == 24,
        button:GetText() .. " fits its translated label with padding")
end
local point, relative, relativePoint, offset = w.set:GetPoint()
check(point == "LEFT" and relative == w.here and relativePoint == "RIGHT" and offset == 6,
    "Set follows Here's width with a six-pixel gap")
M.tooltip = {}
w.clearAll:RunScript("OnEnter")
check(#M.tooltip == 2 and M.tooltip[1] == L.CLEAR_ALL and M.tooltip[2] == L.CLEAR_ALL_DESC,
    "disabled Remove All still explains that every waypoint is removed")
w.clearAll:RunScript("OnLeave")
check(w.list.emptyText:GetText() == L.NO_WAYPOINTS_LONG and w.list.emptyText:IsShown(), "empty list explains how to add")
check(w.pointing:GetText() == L.ACTIVE_NONE, "empty active status")
if bare then
    check(w.status:GetText() == L.TIP_ADD_BOX and ns.settings.tipsShown.add, "missing HelpTip uses status once")
    check(statusMode == "info", "fallback Add tip requests neutral status")
    check(w.add:GetParent()._template == "BackdropTemplate", "search field uses fallback")
else
    check(#M.helpTips == 1, "first open shows one HelpTip")
end
ns.UI.Hide()
check(not ns.UI.IsShown(), "UI.Hide closes window")
ns.UI.Show()
check(bare or #M.helpTips == 1, "two opens show the HelpTip once")
if not bare then
    M.helpTips[1].info.onAcknowledgeCallback()
    check(ns.settings.tipsShown.add, "acknowledgement persists")
end

w.add:SetFocus()
w.add:Type("west")
check(w.zoneList:IsShown(), "typing west shows dropdown")
check(w.zoneList.buttons[1].result.zone.id == 52, "Westfall comes first")
w.add:RunScript("OnEnterPressed")
check(w.add:GetText() == "Westfall " and w.add:HasFocus(), "Enter picks zone with trailing space and focus")
check(not w.zoneList:IsShown() and w.status:GetText() == L.ZONE_PICKED_HINT:format("Westfall"), "zone hint replaces dropdown")
check(statusMode == "info", "zone selection hint requests neutral status")
w.add:Type("Westfall 45.5 60.25")
w.name:Type("Sentinel Hill")
local chatBefore = #M.printed
w.add:RunScript("OnEnterPressed")
local wp = WP.GetActive()
check(WP.Count() == 1 and wp.title == "Sentinel Hill", "Enter adds waypoint from Name field")
check(wp.m == 52 and near(wp.x, 0.455) and near(wp.y, 0.6025), "coordinates become fractions")
check(#M.printed == chatBefore, "click result stays in status, without chat")
check(w.status:GetText() == L.ADDED:format(WP.Describe(wp)), "success status")
check(statusMode == true and w.clearAll:IsEnabled(), "adding enables Remove All and keeps success status")
check(w.add:GetText() == "" and w.name:GetText() == "", "successful entry clears fields")

w.add:Type("45.5 60.25")
w.name:Type("Current zone")
w.add:RunScript("OnEnterPressed")
check(WP.GetActive().m == 37 and near(WP.GetActive().x, 0.455) and near(WP.GetActive().y, 0.6025),
    "coordinate-only entry uses current map")
local count = WP.Count()
for _, text in ipairs({ "150 20", "-1 20", "Westfall 150 20", "45 101" }) do
    w.add:Type(text)
    w.add:RunScript("OnEnterPressed")
    check(WP.Count() == count and w.status:GetText() == L.INVALID_COORDS, "rejects " .. text)
end
check(statusMode == nil, "invalid coordinates retain error status")
w.add:Type("")
w.set:Click()
check(w.status:GetText() == L.NO_COORDS, "blank input requests coordinates")
w.add:Type("#999999 20 30")
w.set:Click()
check(WP.Count() == count and w.status:GetText() == L.UNKNOWN_ZONE:format("#999999"), "invalid map ID rejected")
w.add:Type("nosuchzone 20 30")
w.set:Click()
check(w.status:GetText() == L.UNKNOWN_ZONE:format("nosuchzone"), "unknown zone status")
local findZone = ns.Geo.FindZone
ns.Geo.FindZone = function() return nil, { "Westfall", "Western Plaguelands" } end
w.add:Type("west 20 30")
w.set:Click()
check(w.status:GetText() == L.DID_YOU_MEAN:format("Westfall, Western Plaguelands"), "ambiguous zone gives suggestions")
ns.Geo.FindZone = findZone
w.add:Type("/way #52 45,5 20 Named in text")
w.set:Click()
check(WP.GetActive().m == 52 and near(WP.GetActive().x, 0.455)
    and WP.GetActive().title == "Named in text", "slash paste, map ID, decimal comma, and inline name")
w.add:Type("trisifal 40 50 Typo fixed")
w.set:Click()
check(WP.GetActive().m == 18, "zone typo resolved quietly")

w.here:Click()
check(w.add:GetText() == "Elwynn Forest 40.0 30.0", "Here fills zone and coordinates")
check(not w.zoneList:IsShown(), "Here closes dropdown")
M.player.noPosition = true
w.here:Click()
check(w.status:GetText() == L.NO_POSITION, "Here reports missing player position")
M.player.noPosition = false
w.add:RunScript("OnTabPressed")
check(w.name:HasFocus(), "Tab moves Add to Name")
w.name:RunScript("OnTabPressed")
check(w.add:HasFocus(), "Tab moves Name to Add")
w.add:Type("")
check(w.zoneList.buttons[1].result.here and w.zoneList.buttons[1].result.zone.id == 37, "empty dropdown begins at current zone")
w.add:RunScript("OnArrowPressed", "DOWN")
check(w.zoneList.buttons[2].cursor:IsShown(), "Down moves dropdown cursor")
w.add:RunScript("OnArrowPressed", "UP")
check(w.zoneList.buttons[1].cursor:IsShown(), "Up returns dropdown cursor")
w.add:RunScript("OnEscapePressed")
check(not w.add:HasFocus() and not w.zoneList:IsShown(), "Escape clears focus and dropdown")

w.add:SetFocus()
w.add:Type("goldsh")
local place
for _, button in ipairs(w.zoneList.buttons) do
    if button.result and button.result.place and button.result.place.name == "Goldshire, Elwynn" then
        place = button
    end
end
check(place ~= nil, "typing also finds live places")
if place then
    local before = WP.Count()
    place:Click()
    check(WP.Count() == before + 1 and WP.GetActive().title == "Goldshire, Elwynn"
        and not w.zoneList:IsShown(), "picking a place sets waypoint immediately")
end

WP.ClearAll(true)
check(not w.clearAll:IsEnabled(), "external clear disables Remove All immediately")
local first = WP.Add(52, 0.1, 0.2, { title = "First", silent = true })
local second = WP.Add(52, 0.3, 0.4, { title = "Second", silent = true })
local third = WP.Add(52, 0.5, 0.6, { title = "Third", silent = true })
check(w.list.rows[1].item == third and w.list.rows[2].item == second and w.list.rows[3].item == first, "newest first")
check(w.list.rows[1].selected and w.list.rows[1].activeBg:IsShown(), "active row marked")
check(w.count:GetText() == L.WAYPOINT_COUNT:format(3), "waypoint count in header")
check(w.list.rows[1].zone:GetText():find("Westfall", 1, true) and w.list.rows[1].dist:GetText() ~= "", "row zone and live distance")
w.list.rows[3]:Click()
check(WP.GetActive() == first and w.list.rows[3].activeBg:IsShown() and not w.list.rows[1].activeBg:IsShown(), "left click points arrow")
M.shift = true
w.list.rows[2]:Click()
M.shift = false
check(WP.GetActive() == first and M.chatText:find("Second", 1, true), "shift click shares without changing active")
w.list.rows[2]:RunScript("OnEnter")
local tooltip = table.concat(M.tooltip, "\n")
check(tooltip:find(L.ROW_TOOLTIP_CLICK, 1, true) and tooltip:find(L.ROW_TOOLTIP_SHARE, 1, true)
    and tooltip:find(L.ROW_TOOLTIP_MENU, 1, true), "row tooltip gives all three inputs")
w.list.rows[2]:Click("RightButton")
local menu = bare and ns.Widgets.lastMenu or M.lastMenu
check(findItem(menu, L.ROW_MENU_POINT) and findItem(menu, L.SHARE) and findItem(menu, L.REMOVE), "right menu has Point, Share, Remove")
local share = findItem(menu, L.SHARE)
check(share.fn == nil, "Share parent has no second-menu callback")
if not bare then
    local menuCount = #M.menus
    if share.fn then share.fn() end
    check(M.lastMenu == menu and #M.menus == menuCount, "opening Share keeps the original context menu")
end
local shareMenu = bare and menu or share
check(findItem(shareMenu, L.SHARE_CHATBOX) ~= nil, "chat-box share action available")
local say = findItem(shareMenu, bare and L.ROUTE_SHARE_POST:format(L.SHARE_SAY) or L.SHARE_SAY)
say.fn()
check(M.chatText:find("/say", 1, true) == 1 and M.chatText:find("Second", 1, true), "share submenu uses chosen channel")
findItem(menu, L.REMOVE).fn()
check(WP.Count() == 2 and not WP.IsValid(second), "Remove deletes selected row")
WP.Add(52, 0.7, 0.8, { title = "Fourth", silent = true })
w.clearAll:Click()
if bare then
    check(WP.Count() == 0, "missing popup clears directly")
else
    check(M.lastPopup == "WAYPOINTTRACKER_CLEAR_ALL" and M.lastPopupArgs[1] == 3 and WP.Count() == 3, "three waypoints ask before clear")
    StaticPopupDialogs.WAYPOINTTRACKER_CLEAR_ALL.OnCancel()
    check(WP.Count() == 3, "cancel keeps waypoints")
    StaticPopupDialogs.WAYPOINTTRACKER_CLEAR_ALL.OnAccept()
    check(WP.Count() == 0, "accept clears all")
end
check(not w.clearAll:IsEnabled(), "clearing all waypoints disables Remove All")
WP.Add(52, 0.1, 0.2, { silent = true })
check(w.clearAll:IsEnabled(), "external add re-enables Remove All immediately")
M.lastPopup = nil
w.clearAll:Click()
check(WP.Count() == 0 and M.lastPopup == nil, "single waypoint clears without popup")
check(not w.clearAll:IsEnabled(), "removing the last waypoint disables Remove All")

w.add:Type("#52 25 35 Typed spot")
w.name:SetText("")
w.set:Click("RightButton")
check(WP.Count() == 0, "right-click Set shares without adding")
if not bare then findItem(M.lastMenu, L.SHARE_CHATBOX).fn() end
check(M.chatText:find("Typed spot", 1, true), "typed coordinates shared")
w.add:Type("")
w.name:Type("Standing here")
w.set:Click("RightButton")
if not bare then findItem(M.lastMenu, L.SHARE_CHATBOX).fn() end
check(M.chatText:find("Standing here", 1, true), "blank right-click Set shares current position and name")

-- Sibling parcels are absent here; exercise their published contracts.
local oldFind = ns.Find
local found, findShown
ns.Find = {
    Way = function(text) found = text; findShown = true end,
    IsShown = function() return findShown end,
}
Window.RegisterTab { key = "find", order = 2, title = L.TAB_ALL }
w.add:Type("unmatched place name")
w.set:Click()
check(found == "unmatched place name" and Window.GetTab() == "find", "name-only input delegates to Find and shows its tab")
check(not w.zoneList:IsShown(), "tab change hides dropdown")
Window.ShowTab("waypoints")
ns.Find.Way = function(text) found = text; findShown = false; return WP.Add(52, 0.1, 0.1, { silent = true }) end
w.add:Type("exact place name")
w.set:Click()
check(Window.GetTab() == "waypoints" and WP.Count() == 1, "exact Find match keeps home")
ns.Find = oldFind

local oldRoutes = ns.Routes
local run = { id = "test", mode = "order", done = 1, total = 3 }
local skipped, stopped = 0, 0
ns.Routes = {
    Run = function() return run end,
    Get = function() return { name = "Test route" } end,
    Skip = function() skipped = skipped + 1 end,
    Stop = function() stopped = stopped + 1; run = nil; ns.Fire("ROUTES_CHANGED") end,
}
ns.Fire("ROUTES_CHANGED")
check(w.route:IsShown() and w.skip:IsShown() and w.stop:IsShown(), "running route shows second status and buttons")
check(w.skip:GetWidth() >= 150 and w.stop:GetWidth() >= 110, "route buttons reserve room for translated labels")
M.tooltip = {}
w.skip:RunScript("OnEnter")
check(#M.tooltip == 2 and M.tooltip[1] == L.ROUTE_SKIP and M.tooltip[2] == L.BINDING_ROUTE_NEXT,
    "Skip tooltip explains the next-point action")
w.skip:RunScript("OnLeave")
M.tooltip = {}
w.stop:RunScript("OnEnter")
check(#M.tooltip == 0 and not GameTooltip:IsShown(), "Stop has no redundant tooltip")
check(w.route:GetText() == L.FOLLOWING_ROUTE:format("Test route", 2, 3), "ordered route progress")
run.mode, run.lap = "loop", 2
M.Tick(0.6)
check(w.route:GetText() == L.FOLLOWING_LOOP:format("Test route", 3), "loop progress refreshes on tick")
w.skip:Click()
w.stop:Click()
check(skipped == 1 and stopped == 1 and not w.route:IsShown() and not w.skip:IsShown() and not w.stop:IsShown(), "Skip and Stop use Routes and strip hides afterward")
ns.Routes = oldRoutes

WP.ClearAll(true)
for i = 1, 30 do WP.Add(52, i / 100, 0.5, { title = "Point " .. i, silent = true }) end
check(w.list.scrollbar:IsShown(), "long list has scrollbar")
w.list:RunScript("OnMouseWheel", -1)
check(w.list.offset == 3 and w.list.rows[1].item.title == "Point 27", "list scrolls newest-first")
w.add:SetFocus()
w.add:Type("west")
ns.UI.Hide()
check(not w.zoneList:IsShown() and not w.add:HasFocus(), "window hide closes dropdown and clears focus")
local calls = M.uiPanelCalls.show + M.uiPanelCalls.hide
M.player.combat = true
ns.UI.Show()
ns.UI.Hide()
M.player.combat = false
check(calls == M.uiPanelCalls.show + M.uiPanelCalls.hide and not M.actionBlocked, "compat show/hide avoids protected calls in combat")
check(#M.errors == 0, "no reported errors: " .. tostring(M.errors[1]))
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
