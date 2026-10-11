-- The window shell, independently of the three feature parcels.
-- Run from the repository root: lua5.1 tests/run_window.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

-- Local fixtures supply Blizzard behavior that the shared mock omits.
SOUNDKIT.IG_CHARACTER_INFO_OPEN = 839
SOUNDKIT.IG_CHARACTER_INFO_CLOSE = 840
SOUNDKIT.IG_CHARACTER_INFO_TAB = 841
local setNumTabs = PanelTemplates_SetNumTabs
function PanelTemplates_SetNumTabs(f, n)
    setNumTabs(f, n)
    -- forever: SetNumTabs calls AnchorTabs; it does not clear old points.
    for i = 2, n do
        f.Tabs[i]:SetPoint("TOPLEFT", f.Tabs[i - 1], "TOPRIGHT", 3, 0)
    end
end
function ButtonFrameTemplate_HideAttic(f)
    f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -24)
end
function ButtonFrameTemplate_ShowButtonBar(f)
    f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 26)
end

local createFrame = CreateFrame
local missingFields = {
    TitleText = true, TitleContainer = true, PortraitContainer = true,
    CloseButton = true, Inset = true, Tabs = true, SetTitle = true, SetPortraitToAsset = true,
}
local function RealFields(f)
    -- The old mock treats every unknown capitalised key as a method. These
    -- missing fields must instead behave like real absent template children.
    local mt = getmetatable(f)
    if not mt then return end
    setmetatable(f, { __index = function(t, k)
        if missingFields[k] then return nil end
        if type(mt.__index) == "function" then return mt.__index(t, k) end
        return mt.__index and mt.__index[k]
    end })
end
local function TrackPoints(f)
    local setPoint = f.SetPoint
    function f:SetPoint(...)
        local points = {}
        for i, point in ipairs(self._points) do points[i] = point end
        setPoint(self, ...)
        local point = self._points[1]
        local replaced = false
        for i, old in ipairs(points) do
            if old[1] == point[1] then points[i] = point; replaced = true; break end
        end
        if not replaced then points[#points + 1] = point end
        self._points = points
    end
end
function CreateFrame(kind, name, parent, template)
    local f = createFrame(kind, name, parent, template)
    RealFields(f)
    TrackPoints(f)
    local createFontString = f.CreateFontString
    function f:CreateFontString(...)
        local fs = createFontString(self, ...)
        TrackPoints(fs)
        return fs
    end
    if template == "ButtonFrameTemplate" then
        TrackPoints(f.Inset)
        f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -60)
        f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 26)
    end
    return f
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end

local function PointIs(region, index, point, relative, relativePoint, x, y)
    local p, r, rp, px, py = region:GetPoint(index)
    return p == point and r == relative and rp == relativePoint and px == x and py == y
end

local function StatusColorIs(status, r, g, b)
    local actualR, actualG, actualB = status:GetTextColor()
    return actualR == r and actualG == g and actualB == b
end

local function LoadShell()
    local ns = {}
    assert(loadfile("WaypointTracker/Locales/enUS.lua"))("WaypointTracker", ns)
    assert(loadfile("WaypointTracker/Core.lua"))("WaypointTracker", ns)
    -- P1 provides these at merge; the isolated suite also works before then.
    if not rawget(ns.L, "BACK") then ns.L.BACK = "Back" end
    if not rawget(ns.L, "SETTINGS") then ns.L.SETTINGS = "Settings" end
    if not rawget(ns.L, "SETTINGS_UNAVAILABLE") then ns.L.SETTINGS_UNAVAILABLE = "Settings unavailable" end
    ns.settings = { uiLastTab = "waypoints" }
    ns.Arrow = { SetPreview = function(on) ns.preview = on end }
    assert(loadfile("WaypointTracker/Window.lua"))("WaypointTracker", ns)
    return ns, ns.Window
end

local ns, W = LoadShell()
local built, shown, hidden, updates, leftClicks = {}, {}, {}, {}, 0
local events = { shown = 0, hidden = 0, tab = 0, settings = 0 }
ns.On("UI_SHOWN", function() events.shown = events.shown + 1 end)
ns.On("UI_HIDDEN", function() events.hidden = events.hidden + 1 end)
ns.On("UI_TAB_SHOWN", function(key) events.tab = events.tab + 1; events.lastTab = key end)
ns.On("SETTING_CHANGED", function() events.settings = events.settings + 1 end)

local function Register(key, order)
    W.RegisterTab{
        key = key, order = order, title = key,
        build = function(content) built[key] = (built[key] or 0) + 1; content.marker = key end,
        onShow = function() shown[key] = (shown[key] or 0) + 1 end,
        onHide = function() hidden[key] = (hidden[key] or 0) + 1 end,
        onUpdate = function(dt) updates[key] = (updates[key] or 0) + 1; updates.dt = dt end,
        leftButton = key ~= "find" and {
            text = "First", tooltip = "First action", onClick = function() leftClicks = leftClicks + 1 end,
        } or nil,
        leftButton2 = key == "routes" and {
            text = "Import", onClick = function() leftClicks = leftClicks + 10 end,
        } or nil,
    }
end
-- Registration order must not affect the bottom tabs.
Register("routes", 3)
Register("waypoints", 1)
Register("find", 2)
check(not W.frame and not W.IsShown() and not next(built), "shell and roots are lazy")
W.Hide()
check(not W.frame, "hiding before first open does not build")
W.Toggle()
local f = W.frame
check(W.IsShown() and f:IsShown(), "Toggle shows the frame")
check(f:GetName() == "WaypointTrackerFrame" and f:GetWidth() == 640 and f:GetHeight() == 540, "named 640 by 540 panel")
check(#f.Tabs == 3 and f.Tabs[1].key == "waypoints" and f.Tabs[2].key == "find" and f.Tabs[3].key == "routes", "three sorted tab buttons")
check(f.Tabs[1]:GetName() == "WaypointTrackerFrameTab1" and f.Tabs[3]:GetID() == 3, "tab names and IDs")
check(f.selectedTab == 1 and f.numTabs == 3, "Blizzard tab state")
check(#f.Tabs[1]._points == 1 and PointIs(f.Tabs[1], 1, "TOPLEFT", f, "BOTTOMLEFT", 11, 2), "first native tab has one shell anchor")
for i = 2, 3 do
    check(#f.Tabs[i]._points == 1 and PointIs(f.Tabs[i], 1, "TOPLEFT", f.Tabs[i - 1], "TOPRIGHT", 3, 0), "native tab has only Blizzard's +3 anchor: " .. i)
end
check(PointIs(f.Inset, 1, "TOPLEFT", f, "TOPLEFT", 4, -60), "native attic leaves content below the portrait")
check(PointIs(W.tabs.waypoints.content, 2, "BOTTOMRIGHT", f.Inset, "BOTTOMRIGHT", -6, 6), "content uses the full inset below the attic")
check(PointIs(f.status, 1, "TOPLEFT", f, "TOPLEFT", 62, -32) and PointIs(f.status, 2, "RIGHT", f, "RIGHT", -34, 0), "status occupies the attic band")
check(PointIs(f.settings, 1, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4), "Settings matches native MagicButton placement")
check(M.sounds[#M.sounds] == SOUNDKIT.IG_CHARACTER_INFO_OPEN, "opening plays the native panel sound")
check(f.TitleText:GetText() == ns.L.ADDON_TITLE and f.portrait:GetTexture() == ns.MEDIA .. "Icon", "native title and portrait")
check(f.CloseButton and f.Inset and f:IsMouseEnabled(), "consistent chrome and mouse capture")
check(built.waypoints == 1 and not built.find and not built.routes, "only selected root builds")
check(shown.waypoints == 1 and events.shown == 1 and ns.preview, "opening refreshes the root and previews the arrow")
local special = false
for _, name in ipairs(UISpecialFrames) do if name == "WaypointTrackerFrame" then special = true end end
check(special, "Esc registration")
local attrs = UIPanelWindows.WaypointTrackerFrame
check(attrs and attrs.area == "left" and attrs.pushable == 5 and attrs.whileDead == 1 and attrs.width == 640 and attrs.checkFit == 1, "panel registration attributes")
check(not f.settings:IsEnabled(), "Settings disabled before Options exists")
f.settings:RunScript("OnEnter")
check(M.tooltip[#M.tooltip] == ns.L.SETTINGS_UNAVAILABLE, "disabled Settings explains availability")
W.tabs.waypoints.leftButton:Click()
check(leftClicks == 1 and W.tabs.waypoints.leftButton:IsShown() and not W.tabs.routes.leftButton:IsShown(), "active tab's left button only")

W.SetStatus("Saved", true)
check(f.status:GetText() == "Saved" and StatusColorIs(f.status, 0.3, 1, 0.3), "success status is green")
W.SetStatus("Type coordinates next", "info")
check(f.status:GetText() == "Type coordinates next" and StatusColorIs(f.status, 1, 1, 1), "informational status is neutral white")
W.SetStatus("Invalid coordinates", false)
check(f.status:GetText() == "Invalid coordinates" and StatusColorIs(f.status, 1, 0.35, 0.3), "error status is red after an informational status")
W.SetStatus("Saved", true)
check(StatusColorIs(f.status, 0.3, 1, 0.3), "success status restores green after another state")
W.Toggle("find")
check(W.IsShown() and W.GetTab() == "find" and events.hidden == 0, "Toggle find switches without closing")
check(ns.settings.uiLastTab == "find" and events.settings == 0, "last tab saved without setting events")
check(events.lastTab == "find" and f.selectedTab == 2 and not ns.preview, "tab event, native selection and preview update")
check(f.status:GetText() == "" and hidden.waypoints == 1 and shown.find == 1, "switch clears status and runs lifecycle callbacks")
check(not W.tabs.waypoints.content:IsShown() and W.tabs.find.content:IsShown(), "only current root shown")
check(not W.tabs.waypoints.leftButton:IsShown(), "Find has no left button")
W.ShowTab("find")
check(built.find == 1 and events.tab == 2 and shown.find == 1, "reselect does not rebuild or churn callbacks")
f:RunScript("OnUpdate", 0.25)
check(not updates.find, "update waits for half a second")
f:RunScript("OnUpdate", 0.25)
check(updates.find == 1 and updates.dt == 0.5 and not updates.waypoints, "only current tab updates with accumulated elapsed")

local pageShown, pageHidden, pageBuilt = 0, 0, 0
local page = {
    title = "Correct the spot",
    build = function(body) pageBuilt = pageBuilt + 1; body.field = body:CreateFontString() end,
    onShow = function() pageShown = pageShown + 1 end,
    onHide = function() pageHidden = pageHidden + 1 end,
}
local p = W.PushPage("find", page)
check(p and p:IsVisible() and not W.tabs.find.content:IsShown(), "page replaces root content")
check(p.header:IsVisible() and p.back:GetText() == "< Back" and p.title:GetText() == page.title, "page header has Back and title")
check(W.CurrentPage("find") == page and pageBuilt == 1 and pageShown == 1, "CurrentPage returns descriptor and page builds once")
local _, _, _, _, bodyY = p:GetPoint()
check(bodyY == -36, "page controls start below the header")
W.Toggle("routes")
check(W.CurrentPage("find") == page and not p:IsVisible() and pageHidden == 1, "tab switch retains the hidden page stack")
check(W.tabs.routes.leftButton:IsShown() and W.tabs.routes.leftButton2:IsShown(), "Routes supports two left buttons")
W.tabs.routes.leftButton2:Click()
check(leftClicks == 11, "second left action dispatches")
W.ShowTab("find")
check(p:IsVisible() and pageShown == 2 and pageBuilt == 1, "returning to tab restores the page without rebuilding")
local second = { title = "Second page", onShow = function() pageShown = pageShown + 1 end,
    onHide = function() pageHidden = pageHidden + 1 end }
local p2 = W.PushPage("find", second)
check(p2:IsVisible() and not p:IsVisible() and W.CurrentPage("find") == second, "nested page replaces previous page")
p2.back:Click()
check(p:IsVisible() and not p2:IsVisible() and W.CurrentPage("find") == page, "Back restores previous page")
W.PopPage("find")
check(not W.CurrentPage("find") and W.tabs.find.content:IsShown() and not p:IsVisible(), "pop restores root")
W.PopPage("find")
check(W.tabs.find.content:IsShown(), "pop empty stack is harmless")

local cachedBuilt, reused, cachedShown, cachedHidden = 0, 0, 0, 0
local cachedSpec = {
    key = "fix", title = "First correction",
    build = function(body) cachedBuilt = cachedBuilt + 1; body.draft = "first" end,
    onShow = function() cachedShown = cachedShown + 1 end,
    onHide = function() cachedHidden = cachedHidden + 1 end,
}
local cached = W.PushPage("find", cachedSpec)
W.PopPage("find")
local frameCount = #M.frames
local updatedSpec = {
    key = "fix", title = "Next correction",
    build = function() error("cached page rebuilt") end,
    onReuse = function(body) reused = reused + 1; body.draft = "next" end,
    onShow = function() cachedShown = cachedShown + 10 end,
    onHide = function() cachedHidden = cachedHidden + 10 end,
}
local cachedAgain = W.PushPage("find", updatedSpec)
check(cachedAgain == cached and cachedBuilt == 1 and #M.frames == frameCount, "keyed page reuses its entire frame tree")
check(cached.title:GetText() == updatedSpec.title and cached.draft == "next" and reused == 1, "reuse updates the title and invokes onReuse")
check(W.CurrentPage() == updatedSpec and cachedShown == 11 and cachedHidden == 1, "cached page uses current lifecycle callbacks")
W.PushPage("find", { title = "Nested" })
local nestedSpec = {
    key = "fix", title = "Nested correction",
    build = function(body) body.draft = "nested" end,
    onHide = updatedSpec.onHide,
}
local nested = W.PushPage("find", nestedSpec)
check(#W.tabs.find.pages == 3 and nested ~= cached and W.CurrentPage() == nestedSpec,
    "pushing a stacked key builds an independent page without removing its ancestor")
check(cached.draft == "next" and nested.draft == "nested" and W.tabs.find.pageCache.fix.frame == cached,
    "nested keyed pages preserve the ancestor draft and reusable cache")
W.PopPage("find")
W.PopPage("find")
check(W.CurrentPage() == updatedSpec and cached:IsVisible() and cached.draft == "next",
    "Back restores the stacked ancestor and its state")
W.PopAll("find")
check(cachedHidden == 31, "each cached or nested activation is hidden once")
W.PushPage("routes", { key = "fix", title = "Route correction" })
check(W.tabs.routes.pageCache.fix.frame ~= cached, "page caches belong to individual tabs")
W.PopAll("routes")
W.Hide()
W.Show("find")
check(W.PushPage("find", updatedSpec) == cached and cachedBuilt == 1, "closing clears stacks but retains cached frames")
W.PopAll("find")
local uncached = W.PushPage("find", page)
W.PopPage("find")
check(W.PushPage("find", page) ~= uncached, "unkeyed pages keep their existing allocation behavior")
W.PopAll("find")

W.PushPage("find", page)
W.ShowTab("routes")
local rpage = W.PushPage("routes", { title = "Edit route" })
W.Toggle()
check(not W.IsShown() and not W.CurrentPage("find") and not W.CurrentPage("routes"), "closing clears all tab page stacks")
check(not rpage:IsVisible() and not ns.preview and not GameTooltip:IsShown(), "closing hides page, preview and tooltip")
local hideEvents = events.hidden
W.Toggle()
check(W.GetTab() == "routes" and W.tabs.routes.content:IsVisible() and events.hidden == hideEvents, "reopening uses saved tab at root")
f.CloseButton:Click()
check(not W.IsShown() and events.hidden == hideEvents + 1, "Close uses shell hide lifecycle")
check(M.sounds[#M.sounds] == SOUNDKIT.IG_CHARACTER_INFO_CLOSE, "Close plays the native panel sound")

local showCalls, hideCalls = M.uiPanelCalls.show, M.uiPanelCalls.hide
local blocked = M.actionBlocked or 0
M.player.combat = true
W.Show("waypoints")
check(f:IsShown() and ns.preview, "direct show works during combat")
local point, relative, relativePoint, x, y = f:GetPoint()
check(point == "TOPLEFT" and relative == UIParent and relativePoint == "TOPLEFT" and x == 16 and y == -116, "combat placement matches left panel")
f.CloseButton:Click()
check(not f:IsShown(), "Close hides directly during combat")
WaypointTracker_ToggleFind()
check(f:IsShown() and W.GetTab() == "find", "Find binding uses shell during combat")
WaypointTracker_ToggleRoutes()
check(f:IsShown() and W.GetTab() == "routes", "Routes binding switches without closing")
WaypointTracker_ToggleWindow()
check(not f:IsShown() and M.uiPanelCalls.show == showCalls and M.uiPanelCalls.hide == hideCalls, "combat never calls ShowUIPanel or HideUIPanel")
check((M.actionBlocked or 0) == blocked, "combat never attempts a blocked panel action")
M.player.combat = false
check(M.uiPanelCalls.show > 0 and M.uiPanelCalls.hide > 0, "out of combat uses Blizzard's panel manager")

-- The manager may silently refuse a panel while Edit Mode or Game Menu owns
-- the center slot. Such a refusal must also be respected after combat.
local managerShow = ShowUIPanel
ShowUIPanel = function() M.uiPanelCalls.show = M.uiPanelCalls.show + 1 end
local openingEvents = events.shown
check(W.Show("find") == false and not W.IsShown() and events.shown == openingEvents, "silent manager refusal never force-shows")
M.player.combat = true
W.Show("find")
check(f.shownDirectly and W.IsShown(), "combat fallback records direct ownership")
local refusedPageHidden = 0
local refusedPage = W.PushPage("find", {
    title = "Combat correction", onHide = function() refusedPageHidden = refusedPageHidden + 1 end,
})
W.PushPage("routes", { title = "Hidden combat draft" })
GameTooltip:Show()
local rehomeShown, rehomeHidden, rehomeSounds = events.shown, events.hidden, #M.sounds
local refusedTabHidden = hidden.find or 0
M.player.combat = false
M.FireEvent("PLAYER_REGEN_ENABLED")
check(not W.IsShown() and not f.shownDirectly and not f.rehoming, "combat re-home respects manager refusal and clears handoff state")
check(not W.CurrentPage("find") and not W.CurrentPage("routes") and not refusedPage:IsVisible(), "refused re-home clears every page stack")
check(refusedPageHidden == 1 and hidden.find == refusedTabHidden + 1 and not W.tabs.find.active, "refused re-home deactivates page and tab once")
check(events.hidden == rehomeHidden + 1 and events.shown == rehomeShown and not ns.preview and not GameTooltip:IsShown(), "refused re-home performs the normal close cleanup once")
check(#M.sounds == rehomeSounds + 1 and M.sounds[#M.sounds] == SOUNDKIT.IG_CHARACTER_INFO_CLOSE, "refused re-home plays only the close sound")
ShowUIPanel = managerShow
local regenCalls = M.uiPanelCalls.show
M.FireEvent("PLAYER_REGEN_ENABLED")
check(M.uiPanelCalls.show == regenCalls, "hidden window does not reopen after combat")
M.player.combat = true
W.Show("waypoints")
local combatPageHidden, combatPageShown = 0, 0
local combatSpec = {
    key = "combatEditor", title = "Combat page",
    build = function(body)
        body.name = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
        body.name:SetText("Unsaved route")
    end,
    onShow = function() combatPageShown = combatPageShown + 1 end,
    onHide = function() combatPageHidden = combatPageHidden + 1 end,
}
local combatPage = W.PushPage("waypoints", combatSpec)
local hiddenCombatSpec = { title = "Other tab draft" }
W.PushPage("routes", hiddenCombatSpec)
W.SetStatus("Keep editing", "info")
GameTooltip:Show()
rehomeShown, rehomeHidden, rehomeSounds = events.shown, events.hidden, #M.sounds
local combatTabHidden = hidden.waypoints
M.player.combat = false
M.FireEvent("PLAYER_REGEN_ENABLED")
check(W.IsShown() and not f.shownDirectly and M.uiPanelCalls.show == regenCalls + 1, "combat window returns to panel-manager ownership")
check(W.CurrentPage() == combatSpec and combatPage:IsVisible() and combatPage.name:GetText() == "Unsaved route", "successful re-home retains the active editor and its draft")
check(W.CurrentPage("routes") == hiddenCombatSpec and not W.tabs.waypoints.content:IsShown(), "successful re-home preserves other tab stacks and shows only the active page")
check(combatPageShown == 1 and combatPageHidden == 0 and hidden.waypoints == combatTabHidden and not f.rehoming, "successful re-home avoids page lifecycle churn and tab cleanup")
check(events.shown == rehomeShown and events.hidden == rehomeHidden and #M.sounds == rehomeSounds, "successful re-home emits no window lifecycle events or sounds")
check(ns.preview and GameTooltip:IsShown() and f.status:GetText() == "Keep editing", "successful re-home retains preview, tooltip and status")
regenCalls = M.uiPanelCalls.show
M.FireEvent("PLAYER_REGEN_ENABLED")
check(M.uiPanelCalls.show == regenCalls, "managed window is not repeatedly re-homed")
W.Hide()
check(not W.CurrentPage() and not W.CurrentPage("routes") and combatPageHidden == 1, "normal close after re-home still discards all drafts once")
check(events.hidden == rehomeHidden + 1 and #M.sounds == rehomeSounds + 1, "normal close after re-home restores the close event and sound")

-- A panel-manager error also leaves the frame hidden and needs deferred cleanup.
ShowUIPanel = function() error("Panel manager unavailable during re-home") end
M.player.combat = true
W.Show("waypoints")
W.PushPage("waypoints", combatSpec)
rehomeShown, rehomeHidden, rehomeSounds = events.shown, events.hidden, #M.sounds
M.player.combat = false
M.FireEvent("PLAYER_REGEN_ENABLED")
check(not W.IsShown() and not f.rehoming and not f.shownDirectly and not W.CurrentPage(), "failed re-home clears pages and handoff state")
check(combatPageHidden == 2 and events.hidden == rehomeHidden + 1 and events.shown == rehomeShown and #M.sounds == rehomeSounds + 1, "failed re-home runs normal close lifecycle once")
ShowUIPanel = managerShow

M.player.combat = true
W.Show("find")
f:Hide()
M.player.combat = false
M.FireEvent("PLAYER_REGEN_ENABLED")
check(not W.IsShown() and M.uiPanelCalls.show == regenCalls, "Esc during combat clears direct ownership without reopening")

local settingsOpens, available = 0, true
ns.Options = { IsAvailable = function() return available end, Open = function() settingsOpens = settingsOpens + 1 end }
W.Show("waypoints")
check(f.settings:IsEnabled(), "Settings available on reopen")
M.tooltip = {}
f.settings:RunScript("OnEnter")
check(#M.tooltip == 1 and M.tooltip[1] == ns.L.SETTINGS, "available Settings tooltip contains only text")
f.settings:Click()
check(settingsOpens == 1, "Settings opens Options")
available = false
f:RunScript("OnUpdate", 0.5)
f.settings:Click()
check(not f.settings:IsEnabled() and settingsOpens == 1, "availability refresh disables Settings and prevents dispatch")
W.SetStatus("Error", false)
check(f.status:GetText() == "Error" and StatusColorIs(f.status, 1, 0.35, 0.3), "status accepts error text with its original color")
W.SetStatus(nil)
check(f.status:GetText() == "" and StatusColorIs(f.status, 1, 0.35, 0.3), "nil status still clears text with the default error color")
W.Hide()
local tickCount = updates.waypoints
f:RunScript("OnUpdate", 1)
check(updates.waypoints == tickCount, "hidden window never refreshes the tab")

local panelShow, panelHide = ShowUIPanel, HideUIPanel
ShowUIPanel = function() error("Panel manager unavailable") end
W.Show("find")
check(not W.IsShown() and not W.Show("find"), "panel show error never forces a direct show")
ShowUIPanel = nil
check(W.Show("find") and f.shownDirectly, "missing panel manager permits direct show")
HideUIPanel = function() error("Panel manager unavailable") end
W.Hide()
check(not W.IsShown(), "panel hide failure falls back to direct hide")
ShowUIPanel, HideUIPanel = panelShow, panelHide

local setTab = PanelTemplates_SetTab
PanelTemplates_SetTab = nil
local _, H = LoadShell()
H.RegisterTab{ key = "waypoints", order = 1, title = "Waypoints" }
H.RegisterTab{ key = "find", order = 2, title = "Find" }
H.Show()
check(H.frame.Tabs[1].bar and H.frame.Tabs[1].bar:IsShown(), "missing tab helper uses selectable plain tabs")
check(#H.frame.Tabs[2]._points == 1 and PointIs(H.frame.Tabs[2], 1, "LEFT", H.frame.Tabs[1], "RIGHT", 2, 0), "fallback art keeps only its manual anchor despite Blizzard's helper")
H.frame.Tabs[2]:Click()
check(M.sounds[#M.sounds] == SOUNDKIT.IG_CHARACTER_INFO_TAB, "tab click plays the native tab sound")
H.Hide()
PanelTemplates_SetTab = setTab

-- Exercise actual template failures, not just absent optional globals.
local nativeCreate = CreateFrame
local nativeRegister, nativeShow, nativeHide = RegisterUIPanel, ShowUIPanel, HideUIPanel
local nativeNumTabs, nativeSetTab, nativeResize = PanelTemplates_SetNumTabs, PanelTemplates_SetTab, PanelTemplates_TabResize
RegisterUIPanel, ShowUIPanel, HideUIPanel = nil, nil, nil
PanelTemplates_SetNumTabs, PanelTemplates_SetTab, PanelTemplates_TabResize = nil, nil, nil
CreateFrame = function(kind, name, parent, template)
    if template == "ButtonFrameTemplate" or template == "PanelTabButtonTemplate" or template == "MagicButtonTemplate" then
        error("Template unavailable: " .. template)
    end
    local created = nativeCreate(kind, name, parent, template)
    RealFields(created)
    return created
end
local bare, B = LoadShell()
bare.settings.uiLastTab = "invalid"
B.RegisterTab{ key = "waypoints", order = 1, title = "Waypoints" }
B.RegisterTab{ key = "find", order = 2, title = "Find" }
B.RegisterTab{ key = "routes", order = 3, title = "Routes", leftButton = { text = "Create route" } }
B.Toggle()
local bf = B.frame
check(B.IsShown() and B.GetTab() == "waypoints", "bare shell opens and invalid saved tab falls back to home")
check(bf._template == "BackdropTemplate" and bf._backdrop and bf.Inset._backdrop, "bare shell uses dialog and inset backdrops")
check(bf.TitleText:GetText() == bare.L.ADDON_TITLE and bf.CloseButton and bf.portrait:GetTexture() == bare.MEDIA .. "Icon", "bare chrome keeps child keys, title and icon")
check(UIPanelWindows.WaypointTrackerFrame.width == 640, "legacy panel registry fallback")
check(#bf.Tabs == 3 and bf.Tabs[1].bar:IsShown() and not bf.Tabs[2].bar:IsShown(), "bare tabs have selected gold underline")
bf.Tabs[2]:Click()
check(B.GetTab() == "find" and bf.Tabs[2].bar:IsShown() and not bf.Tabs[1].bar:IsShown(), "bare tab click switches underline")
local barePage = B.PushPage("find", { title = "Share discoveries" })
check(barePage.back:GetText() == "< Back" and barePage:IsVisible(), "bare page header")
bf:Hide() -- Esc closes by the registered frame's Hide method.
check(not B.IsShown() and not B.CurrentPage("find"), "direct Esc hide clears pages")
UIPanelWindows = nil
local _, N = LoadShell()
N.RegisterTab{ key = "waypoints", order = 1, title = "Waypoints" }
M.player.combat = true
N.Toggle()
N.Toggle()
check(not N.IsShown(), "bare shell toggles in combat without any panel manager")
M.player.combat = false
CreateFrame = nativeCreate
RegisterUIPanel, ShowUIPanel, HideUIPanel = nativeRegister, nativeShow, nativeHide
PanelTemplates_SetNumTabs, PanelTemplates_SetTab, PanelTemplates_TabResize = nativeNumTabs, nativeSetTab, nativeResize

check(#M.errors == 0, "no reported Lua errors")
for _, err in ipairs(M.errors) do print("ERROR: " .. tostring(err)) end
print(("Window tests: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
