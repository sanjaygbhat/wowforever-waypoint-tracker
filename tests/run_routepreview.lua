-- World-map preview lifecycle, pins, geometry and protected-panel fallbacks.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local bare = arg and arg[1] == "--bare"
local passed, failed = 0, 0
local function check(condition, message)
    if condition then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end
local function eq(actual, expected, message)
    check(actual == expected, message .. " (got " .. tostring(actual) .. ", expected " .. tostring(expected) .. ")")
end
local map = WorldMapFrame
-- The mock records anchors but does not compute SetAllPoints geometry.
-- Model just this parcel's canvas layer, without changing the shared mock.
local createFrame = CreateFrame
local canvas = map:GetCanvas()
local container = map:GetCanvasContainer()
canvas:SetSize(1002, 668)
container:SetSize(700, 468)
local lineLayer
CreateFrame = function(kind, name, parent, template)
    local frame = createFrame(kind, name, parent, template)
    if parent == canvas and kind == "Frame" and not name then
        local setAllPoints = frame.SetAllPoints
        function frame:SetAllPoints(relative)
            setAllPoints(self, relative)
            self:SetSize(relative:GetSize())
        end
        lineLayer = frame
        if bare then frame.CreateLine = false end
    end
    return frame
end
-- Forever's scroll container notifies the map, which dispatches the resize
-- to pins and data providers. Model that path locally in this suite.
function map:OnCanvasSizeChanged()
    for _, p in ipairs(self.providers) do
        if p.OnCanvasSizeChanged then p:OnCanvasSizeChanged() end
    end
end
container:SetScript("OnSizeChanged", function() map:OnCanvasSizeChanged() end)
local function resize(width, height, canvasWidth, canvasHeight)
    container:SetSize(width, height)
    canvas:SetSize(canvasWidth, canvasHeight)
    if lineLayer then lineLayer:SetSize(canvasWidth, canvasHeight) end
    container:RunScript("OnSizeChanged", width, height)
end

WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
-- Load-on-demand maps may be absent at login. Capture the continuation and
-- deliver it only after the map and its mixins become available.
local eventUtil, continuations = EventUtil, {}
EventUtil = { ContinueOnAddOnLoaded = function(addon, fn)
    if addon == "Blizzard_WorldMap" then continuations[#continuations + 1] = fn end
end }
WorldMapFrame = nil
M.FireEvent("PLAYER_LOGIN")
eq(ns.RoutePreview.provider, nil, "absent map skips setup at login")
local unavailable, reason = ns.RoutePreview.Show("missing", 37)
eq(unavailable, false, "pre-load Show refuses")
eq(reason, "nomap", "pre-load Show reason")
check(#continuations > 0, "login registers map-load continuation")
WorldMapFrame = map
local providerMixin, pinMixin, fromMixins = MapCanvasDataProviderMixin, MapCanvasPinMixin, CreateFromMixins
MapCanvasDataProviderMixin, MapCanvasPinMixin, CreateFromMixins = nil, nil, nil
unavailable, reason = ns.RoutePreview.Show("missing", 37)
eq(unavailable, false, "absent map mixins skip setup")
eq(reason, "nomap", "absent map mixins reason")
MapCanvasDataProviderMixin, MapCanvasPinMixin, CreateFromMixins = providerMixin, pinMixin, fromMixins
for _, continuation in ipairs(continuations) do continuation() end
EventUtil = eventUtil
M.FireEvent("PLAYER_ENTERING_WORLD")
local P, R, W, L = ns.RoutePreview, ns.Routes, ns.Window, ns.L
local providerCount = #map.providers
ns.Fire("LOGIN")
eq(#map.providers, providerCount, "repeated login does not duplicate providers")
local template = "WaypointTrackerRoutePinTemplate"
local function pins()
    local out = {}
    for _, pin in ipairs(map.pins) do
        if pin.template == template then out[#out + 1] = pin end
    end
    return out
end
local function visibleLines()
    local out = {}
    for _, line in ipairs(P.provider.lines) do if line:IsShown() then out[#out + 1] = line end end
    return out
end
local events = {}
ns.On("ROUTE_PREVIEW", function(id) events[#events + 1] = id or false end)
ns.WP.ClearAll(true)
ns.Set("routesHelpShown", true)
local route = assert(R.SaveMine({ name = "Forest tour", cat = "travel", mode = "order", pts = {
    { m = 37, x = 0.2, y = 0.3, t = "Camp" },
    { m = 37, x = 0.5, y = 0.5, t = "Tower" },
    { m = 37, x = 0.8, y = 0.7, t = L.ROUTE_STOP_END:format("Inn") },
} }))
local id = route.id
W.Show("routes")
check(P.provider ~= nil, "provider set up on login")
eq(P.bar, nil, "bar created only when a preview is requested")
check(P.Show(id, 37), "preview opens")
eq(P.bar:GetParent(), map:GetCanvasContainer(), "bar inside map container")
eq(P.bar:GetHeight(), 30, "compact bar height")
check(P.bar:IsMouseEnabled(), "bar consumes clicks over its text and background")
for _, button in ipairs({ P.bar.set, P.bar.back, P.bar.showThem }) do
    check(button:GetWidth() >= button:GetFontString():GetStringWidth() + 24,
        "translated button label fits with padding: " .. button:GetText())
    eq(button:GetHeight(), 24, "auto-width button keeps compact height")
end
local function checkBarWidth(button, message)
    local reserved = button:GetWidth() + P.bar.back:GetWidth() + P.bar.close:GetWidth() + 24
    check(P.bar:GetWidth() >= reserved + 10, message .. " leaves room for buttons and text")
    eq(P.bar.text:GetWidth(), P.bar:GetWidth() - reserved, message .. " reserves the visible buttons")
end
checkBarWidth(P.bar.set, "on-map bar")
check(not WaypointTrackerFrame:IsShown(), "window hidden before map opens")
eq(M.worldMapOpened, 37, "OpenWorldMap requested zone")
eq(map:GetMapID(), 37, "map displays requested zone")
eq(P.Current(), id, "current preview id")
eq(#map.pins, #route.pts, "one pin per stop with no waypoints")
eq(pins()[1].Icon._texture, "Interface\\COMMON\\Indicator-Green", "start green")
eq(pins()[2].Icon._texture, "Interface\\COMMON\\Indicator-Yellow", "regular stop yellow")
eq(pins()[3].Icon._texture, "Interface\\COMMON\\Indicator-Gray", "hand-in gray")
eq(pins()[1].Number:GetText(), "1", "pin number")
eq(pins()[1].normalizedX, 0.2, "pin x")
eq(pins()[1].normalizedY, 0.3, "pin y")
eq(P.bar.text:GetText(), L.ROUTE_PREVIEW_BAR:format(route.name, #route.pts), "bar names route and shown stops")
check(P.bar.set:IsShown() and not P.bar.showThem:IsShown(), "set shown on route map")
eq(events[#events], id, "Show fires preview event")
local pin = pins()[1]
pin:OnMouseEnter()
eq(M.tooltip[1], L.ROUTE_STOP_N:format(1, "Camp"), "pin tooltip title")
check(M.tooltip[2]:find("Elwynn Forest", 1, true) ~= nil, "pin tooltip zone")
eq(M.tooltip[#M.tooltip], L.ROUTE_PREVIEW_START, "start tooltip hint")
pin:OnClick("LeftButton")
eq(R.Run(), nil, "pin click does not start route")
pin:OnMouseLeave()
check(not GameTooltip:IsShown(), "tooltip hidden on leave")
if not bare then
    eq(#visibleLines(), 2, "order draws consecutive segments")
    local first = visibleLines()[1]
    eq(first._start[3], 0.2 * 1002, "line start x")
    eq(first._end[4], -0.5 * 668, "line end y")
    eq(first:GetThickness(), 3, "base line thickness")
    local scale = map.ScrollContainer.GetCanvasScale
    map.ScrollContainer.GetCanvasScale = function() return 2 end
    P.provider:OnCanvasScaleChanged()
    eq(first:GetThickness(), 1.5, "zoom compensates line thickness")
    map.ScrollContainer.GetCanvasScale = scale
else
    eq(#visibleLines(), 0, "missing CreateLine keeps pins only")
end
local refresh, refreshCount = P.provider.RefreshAllData, 0
P.provider.RefreshAllData = function(self, ...)
    refreshCount = refreshCount + 1
    return refresh(self, ...)
end
resize(350, 234, 501, 334)
eq(refreshCount, 1, "native resize path refreshes preview once")
eq(#pins(), 3, "native resize path preserves pins")
if not bare then eq(visibleLines()[1]._end[3], 0.5 * 501, "resize repositions lines") end
checkBarWidth(P.bar.set, "small on-map bar")
resize(700, 468, 1002, 668)
eq(refreshCount, 2, "next native resize refreshes once")
P.provider.RefreshAllData = refresh

map:SetMapID(1)
eq(#pins(), 0, "browsing other continent clears pins")
eq(#visibleLines(), 0, "off-map clears lines")
eq(P.bar.text:GetText(), L.ROUTE_PREVIEW_OFFMAP:format("Elwynn Forest"), "off-map bar")
check(P.bar.showThem:IsShown() and not P.bar.set:IsShown(), "Show Them replaces Set")
checkBarWidth(P.bar.showThem, "off-map bar")
resize(350, 234, 501, 334)
checkBarWidth(P.bar.showThem, "small off-map bar")
resize(700, 468, 1002, 668)
P.bar.showThem:Click()
eq(map:GetMapID(), 37, "Show Them returns to original map")
eq(#pins(), 3, "Show Them restores pins")

-- The usual route-start question must appear over the map when there are waypoints.
ns.WP.Add(37, 0.1, 0.1, { title = "Keep me", silent = true })
ns.Set("routeApply", "ask")
local beforeCancel = #events
M.autoCancelPopup = true
P.bar.set:Click()
M.autoCancelPopup = false
eq(M.lastPopup, "WAYPOINTTRACKER_ROUTE_ASK", "Cancel uses real route-start popup")
eq(R.Run(), nil, "Cancel does not start route")
eq(P.Current(), id, "Cancel keeps preview")
eq(#pins(), 3, "Cancel keeps preview pins")
eq(#visibleLines(), bare and 0 or 2, "Cancel keeps preview lines")
check(P.bar:IsShown() and map:IsShown(), "Cancel keeps preview bar and map")
eq(#ns.WP.List(), 1, "Cancel preserves existing waypoint")
eq(#events, beforeCancel, "Cancel does not end preview event")

P.bar.set:Click()
local popup = M.popups.WAYPOINTTRACKER_ROUTE_ASK
check(popup:IsShown(), "unanswered route-start popup stays open")
eq(R.Run(), nil, "unanswered popup does not start route")
eq(P.Current(), id, "unanswered popup keeps preview")
eq(#pins(), 3, "unanswered popup keeps pins")
ns.Fire("ROUTES_CHANGED")
eq(P.Current(), id, "unrelated route change keeps pending preview")
StaticPopupDialogs.WAYPOINTTRACKER_ROUTE_ASK.OnAccept(popup, popup.data)
popup:Hide()
eq(R.Run() and R.Run().id, id, "delayed Replace starts route")
eq(P.Current(), nil, "delayed Replace ends preview through route change")
eq(#pins(), 0, "delayed Replace removes preview pins")
eq(#ns.WP.List(), #route.pts, "delayed Replace replaces existing waypoint")
check(not P.bar:IsShown() and map:IsShown(), "delayed Replace hides bar and keeps map")

R.Stop(true)
ns.WP.Add(37, 0.1, 0.1, { title = "Keep me", silent = true })
check(P.Show(id, 37), "open before delayed Add")
P.bar.set:Click()
popup = M.popups.WAYPOINTTRACKER_ROUTE_ASK
eq(P.Current(), id, "delayed Add waits for answer")
StaticPopupDialogs.WAYPOINTTRACKER_ROUTE_ASK.OnAlt(popup, popup.data)
popup:Hide()
eq(R.Run() and R.Run().id, id, "delayed Add starts route")
eq(P.Current(), nil, "delayed Add ends preview through route change")
eq(#pins(), 0, "delayed Add removes preview pins")
eq(#ns.WP.List(), #route.pts + 1, "delayed Add preserves existing waypoint")

R.Stop(true)
check(P.Show(id, 37), "open before automatic Add")
M.autoAltPopup = true
P.bar.set:Click()
M.autoAltPopup = false
eq(M.lastPopup, "WAYPOINTTRACKER_ROUTE_ASK", "set uses replace-or-add popup")
eq(R.Run() and R.Run().id, id, "Set This Route starts route")
eq(P.Current(), nil, "set ends preview")
eq(#pins(), 0, "set removes preview pins")
check(#map.pins > 0, "normal waypoint pins remain")
check(map:IsShown(), "set keeps map open")
check(not P.bar:IsShown(), "set hides bar")
eq(events[#events], false, "End fires nil preview event")
R.Stop(true)
ns.WP.ClearAll(true)
check(P.Show(id, 37), "open before immediate start")
M.lastPopup = nil
P.bar.set:Click()
eq(M.lastPopup, nil, "empty waypoints start without popup")
eq(R.Run() and R.Run().id, id, "empty waypoints start route immediately")
eq(P.Current(), nil, "immediate start ends preview")
eq(#pins(), 0, "immediate start removes preview pins")
check(P.Show(id, 37), "preview running route again")
P.bar.back:Click()
check(not map:IsShown(), "Back closes map")
check(W.IsShown(), "Back restores window")
eq(W.GetTab(), "routes", "Back returns to routes tab")
eq(ns.RoutesUI.widgets.detail.route.id, id, "Back restores selection through public API")
check(P.Show(id, 37), "preview again before map close")
map:Hide()
eq(P.Current(), nil, "closing map ends preview")
eq(#pins(), 0, "closing map clears pins")
check(not W.IsShown(), "closing map does not reopen window")

W.Show("routes")
local blocked, panelShow, panelHide = M.actionBlocked or 0, M.uiPanelCalls.show, M.uiPanelCalls.hide
M.player.combat = true
local ok, why = P.Show(id, 37)
eq(ok, false, "combat refuses preview")
eq(why, "combat", "combat reason")
eq(M.actionBlocked or 0, blocked, "no blocked action in combat")
eq(M.uiPanelCalls.show, panelShow, "combat no protected show")
eq(M.uiPanelCalls.hide, panelHide, "combat no protected hide")
check(W.IsShown(), "combat preserves window")
eq(W.frame.status:GetText(), L.IN_COMBAT_NO_PANELS, "combat status line")
M.player.combat = false

WorldMapFrame = nil
ok, why = P.Show(id, 37)
eq(ok, false, "absent map refuses")
eq(why, "nomap", "absent map reason")
check(W.IsShown(), "absent map preserves window")
WorldMapFrame = map
local open = OpenWorldMap
OpenWorldMap = nil
map:SetScript("OnShow", function() map:SetMapID(1) end)
check(P.Show(id, 37), "fallback opens preview")
eq(map:GetMapID(), 37, "fallback sets map after OnShow reset")
map:SetScript("OnShow", nil)
P.bar.close:Click()
eq(P.Current(), nil, "close button ends preview")
check(map:IsShown() and not W.IsShown(), "close leaves map open and window hidden")
OpenWorldMap = open
map:Hide()
W.Show("find")
OpenWorldMap = function() end
ok, why = P.Show(id, 37)
eq(ok, false, "refused open returns false")
eq(why, "refused", "refused reason")
eq(P.Current(), nil, "refused open clears state")
check(W.IsShown() and W.GetTab() == "find", "refused open restores previous window tab")
OpenWorldMap = open

check(P.Show(id, 37), "open before combat Back")
M.player.combat = true
map:SetMapID(13) -- refresh acquisitions in combat must not call protected passthrough
P.bar.back:Click()
eq(P.Current(), nil, "combat Back ends preview")
check(map:IsShown() and not W.IsShown(), "combat Back leaves panels alone")
eq(M.actionBlocked or 0, blocked, "combat Back has no blocked panels")
M.player.combat = false

local loop = assert(R.SaveMine({ name = "Forest loop", cat = "travel", mode = "loop", pts = route.pts }))
check(P.Show(loop.id, 37), "loop preview opens")
if not bare then
    eq(#visibleLines(), 3, "loop closes path")
    eq(visibleLines()[3]._colorTexture[4], 0.45, "loop return leg faint")
end
local eventCount = #events
check(P.Show(id, 37), "new preview replaces old")
eq(events[eventCount + 1], false, "replacement ends old preview first")
eq(events[eventCount + 2], id, "replacement announces new preview")
eq(#pins(), 3, "replacement has no duplicate pins")
P.End("close")
local nearest = assert(R.SaveMine({ name = "Nearby camps", cat = "travel", mode = "nearest", pts = route.pts }))
check(P.Show(nearest.id, 37), "nearest preview opens")
eq(#visibleLines(), 0, "nearest has no implied path")
P.End("close")

local many = {}
for i = 1, 61 do many[i] = { m = 37, x = i / 100, y = 0.5, t = "Camp" } end
local large = assert(R.SaveMine({ name = "Many camps", cat = "travel", mode = "order", pts = many }))
check(P.Show(large.id, 37), "large preview opens")
eq(#pins(), 61, "large preview draws every stop")
check(not pins()[1].Number:IsShown(), "large preview hides numbers")
P.End("close")
local mixed = assert(R.SaveMine({ name = "Two coasts", cat = "travel", mode = "order", pts = {
    { m = 37, x = 0.5, y = 0.5 }, { m = 1, x = 0.5, y = 0.5 },
} }))
check(P.Show(mixed.id), "default map uses CommonMap")
eq(map:GetMapID(), 947, "cross-continent chooses world")
eq(#pins(), 2, "world projection draws both continents")
map:SetMapID(37)
eq(#pins(), 1, "partial projection only draws visible stop")
eq(P.bar.text:GetText(), L.ROUTE_PREVIEW_BAR:format(mixed.name, 1), "bar counts visible stops")
P.End("close")
local dungeon = assert(R.SaveMine({ name = "Cave visit", cat = "travel", mode = "order", pts = {
    { m = 52, x = 0.2, y = 0.3 }, { m = 291, x = 0.5, y = 0.5 }, { m = 52, x = 0.8, y = 0.7 },
} }))
check(P.Show(dungeon.id, 52), "mixed dungeon preview opens")
eq(#pins(), 2, "dungeon stop omitted from outdoor map")
eq(#visibleLines(), 0, "no line bridges an invisible stop")
eq(pins()[2].Number:GetText(), "3", "visible pins retain original numbering")
P.End("close")
check(P.Show(nearest.id, 37), "open before combat Set")
M.player.combat, M.autoAltPopup = true, true
P.bar.set:Click()
M.player.combat, M.autoAltPopup = false, false
eq(R.Run() and R.Run().id, nearest.id, "combat Set starts route")
eq(P.Current(), nil, "combat Set ends preview")
check(map:IsShown(), "combat Set keeps map open")
eq(M.actionBlocked or 0, blocked, "combat Set has no blocked panels")
local window, ui = ns.Window, ns.RoutesUI
ns.Window, ns.RoutesUI = nil, nil
check(P.Show(id, 37), "Show tolerates missing window module")
P.End("back")
eq(P.Current(), nil, "Back tolerates missing UI module")
ns.Window, ns.RoutesUI = window, ui
check(P.Show(id, 37), "open before deletion")
R.Delete(id)
eq(P.Current(), nil, "deleted route ends preview")
eq(#pins(), 0, "deleted route clears pins")
check(not P.bar:IsShown(), "deleted route hides bar")
local endedEvents = #events
P.End("close")
eq(#events, endedEvents, "End is idempotent")
eq(#M.errors, 0, "no Lua or protected-action errors")

print(("Route preview tests: %d passed, %d failed%s"):format(passed, failed, bare and " (bare lines)" or ""))
if failed > 0 then os.exit(1) end
