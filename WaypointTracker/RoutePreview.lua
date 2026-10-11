-- A temporary route on Blizzard's map, independent of the active waypoints.
local _, ns = ...
local L, Geo, Widgets = ns.L, ns.Geo, ns.Widgets
local Preview = {}
ns.RoutePreview = Preview

local TEMPLATE = "WaypointTrackerRoutePinTemplate"
local current, provider, layer
local lines = {}
WaypointTrackerRoutePinMixin = WaypointTrackerRoutePinMixin or {}
local PinMethods = {}

local function InCombat()
    return ns.InCombat and ns.InCombat() or (InCombatLockdown and InCombatLockdown()) or false
end

local function Method(object, key, ...)
    if object and type(object[key]) == "function" then
        local ok, value = pcall(object[key], object, ...)
        if ok then return value end
    end
end

-- MapCanvas invokes this on every acquisition, including during combat.
-- Set the native passthrough once on creation, like our waypoint pins.
function PinMethods:SetPassThroughButtons() end
function PinMethods:OnLoad()
    if not InCombat() then
        local mt = getmetatable(self)
        local methods = mt and mt.__index
        local real = type(methods) == "table" and methods.SetPassThroughButtons
        if real then pcall(real, self, "RightButton") end
    end
    if self.UseFrameLevelType then
        if not pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION") then
            pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI")
        end
    end
    Method(self, "SetScalingLimits", 1, 1.0, 1.2)
end

function PinMethods:OnAcquired(r, i, x, y)
    self.route, self.index = r, i
    Method(self, "SetPosition", x, y)
    local title = ns.Routes.StopTitle(r, i)
    local prefix = L.ROUTE_STOP_END:match("^(.-)%%")
    local handIn = i ~= 1 and prefix and title:sub(1, #prefix) == prefix
    local texture = "Interface\\COMMON\\Indicator-" .. (i == 1 and "Green" or handIn and "Gray" or "Yellow")
    self.Icon:SetTexture(texture)
    self.Highlight:SetTexture(texture)
    self.Number:SetText(tostring(i))
    self.Number:SetTextColor(handIn and 1 or 0, handIn and 1 or 0, handIn and 1 or 0)
    self.Number:SetShown(#r.pts <= 60)
end

function PinMethods:OnMouseEnter()
    local r, i = self.route, self.index
    local p = r and r.pts[i]
    if not p or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.ROUTE_STOP_N:format(i, ns.Routes.StopTitle(r, i)), 1, 0.82, 0)
    GameTooltip:AddLine(Geo.GetMapName(p.m) .. "  " .. Geo.FormatCoords(p.x, p.y), 0.8, 0.8, 0.8)
    local distance = Geo.GetVector(p)
    if distance then GameTooltip:AddLine(Geo.FormatDistance(distance), 0.8, 0.8, 0.8) end
    if i == 1 then GameTooltip:AddLine(L.ROUTE_PREVIEW_START, 0.3, 1, 0.3) end
    GameTooltip:Show()
end
function PinMethods:OnMouseLeave()
    if GameTooltip then GameTooltip:Hide() end
end
function PinMethods:OnClick() end -- only the bar sets the route

local function RefreshBar(r, shown)
    local bar = Preview.bar
    if not bar then return end
    if not current or not r then bar:Hide(); return end
    bar.text:SetText(shown == 0 and L.ROUTE_PREVIEW_OFFMAP:format(Geo.GetMapName(current.map))
        or L.ROUTE_PREVIEW_BAR:format(r.name, shown))
    bar.set:SetShown(shown > 0)
    bar.showThem:SetShown(shown == 0)
    -- Reserve the buttons, and truncate long names on the small map.
    local available = Method(bar:GetParent(), "GetWidth") or 0
    local button = shown == 0 and bar.showThem or bar.set
    local reserved = button:GetWidth() + bar.back:GetWidth() + bar.close:GetWidth() + 24
    local width = bar.text:GetStringWidth() + reserved
    if available > 0 then width = math.min(width, math.max(reserved + 10, 300, available - 16)) end
    bar:SetWidth(width)
    bar.text:SetWidth(math.max(10, width - reserved))
    bar:Show()
end

local function Scale(map)
    local scroll = map and map.ScrollContainer
    local scale = Method(scroll, "GetCanvasScale") or Method(map, "GetCanvasScale") or 1
    return type(scale) == "number" and scale > 0 and scale or 1
end

local function DrawLines(map, r, points)
    if r.mode == "nearest" then return end
    if not layer then
        local canvas = Method(map, "GetCanvas")
        if not canvas or not canvas.CreateLine then return end
        layer = CreateFrame("Frame", nil, canvas)
        layer:SetAllPoints(canvas)
        layer:SetFrameLevel((Method(canvas, "GetFrameLevel") or 1) + 20)
    end
    if not layer.CreateLine then return end
    local w, h = layer:GetWidth(), layer:GetHeight()
    if w <= 0 or h <= 0 then return end
    local count, scale = 0, Scale(map)
    local function Segment(a, b, alpha)
        if not a or not b or count >= 200 then return end
        count = count + 1
        local line = lines[count]
        if not line then
            line = Method(layer, "CreateLine", nil, "OVERLAY")
            if not line then return end
            lines[count] = line
        end
        line:SetThickness(3 / scale)
        line:SetColorTexture(1, 0.82, 0, alpha)
        line:SetStartPoint("TOPLEFT", layer, a.x * w, -a.y * h)
        line:SetEndPoint("TOPLEFT", layer, b.x * w, -b.y * h)
        line:Show()
    end
    for i = 2, #r.pts do Segment(points[i - 1], points[i], 0.9) end
    if r.mode == "loop" and #r.pts > 1 then Segment(points[#r.pts], points[1], 0.45) end
end

local function CreateProvider()
    local p = CreateFromMixins(MapCanvasDataProviderMixin)
    p.lines = lines
    function p:RemoveAllData()
        Method(self:GetMap(), "RemoveAllPinsByTemplate", TEMPLATE)
        for _, line in ipairs(lines) do line:Hide() end
    end
    function p:RefreshAllData()
        self:RemoveAllData()
        if not current then return end
        local r = ns.Routes.Get(current.id)
        if not r then Preview.End("gone"); return end
        r = ns.Routes.Prepare(r)
        local map = self:GetMap()
        local mapID = Method(map, "GetMapID")
        local points, shown = {}, 0
        for i, stop in ipairs(r.pts) do
            local x, y = Geo.ProjectToMap(stop.m, stop.x, stop.y, mapID)
            if x and y then
                points[i], shown = { x = x, y = y }, shown + 1
                Method(map, "AcquirePin", TEMPLATE, r, i, x, y)
            end
        end
        DrawLines(map, r, points)
        RefreshBar(r, shown)
    end
    function p:OnCanvasScaleChanged()
        local scale = Scale(self:GetMap())
        for _, line in ipairs(lines) do line:SetThickness(3 / scale) end
    end
    function p:OnCanvasSizeChanged() self:RefreshAllData() end
    function p:OnHide() Preview.End("mapClosed") end
    return p
end

local function CreateBar(map, container)
    local ok, bar = pcall(CreateFrame, "Frame", "WaypointTrackerRoutePreviewBar", container, "BackdropTemplate")
    if not ok then bar = CreateFrame("Frame", "WaypointTrackerRoutePreviewBar", container) end
    bar:EnableMouse(true)
    bar:Hide()
    bar:SetHeight(30)
    bar:SetPoint("TOP", container, "TOP", 0, -8)
    bar:SetFrameLevel((Method(container, "GetFrameLevel") or 1) + 510)
    if bar.SetBackdrop then
        bar:SetBackdrop(Widgets.BACKDROP_BOX)
        bar:SetBackdropColor(0, 0, 0, 0.75)
    end
    bar.text = Widgets.Label(bar, "", "GameFontNormal")
    bar.text:SetPoint("LEFT", 8, 0)
    bar.text:SetWordWrap(false)
    bar.set = Widgets.Button(bar, L.ROUTE_PREVIEW_SET)
    bar.back = Widgets.Button(bar, L.ROUTE_PREVIEW_BACK)
    bar.showThem = Widgets.Button(bar, L.ROUTE_PREVIEW_SHOW)
    for _, button in ipairs({ bar.set, bar.back, bar.showThem }) do
        local text = button:GetFontString()
        if text then
            text:ClearAllPoints()
            text:SetPoint("LEFT", button, "LEFT", 6, 0)
            text:SetPoint("RIGHT", button, "RIGHT", -6, 0)
            text:SetWordWrap(false)
        end
    end
    local success, close = pcall(CreateFrame, "Button", nil, bar, "UIPanelCloseButton")
    bar.close = success and close or Widgets.Button(bar, "x", 24, 24)
    bar.close:SetSize(24, 24)
    bar.close:SetPoint("RIGHT", -4, 0)
    bar.back:SetPoint("RIGHT", bar.close, "LEFT", -4, 0)
    bar.set:SetPoint("RIGHT", bar.back, "LEFT", -4, 0)
    bar.showThem:SetPoint("RIGHT", bar.back, "LEFT", -4, 0)
    bar.set:SetScript("OnClick", ns.Safe(function()
        if not current then return end
        local id = current.id
        ns.Routes.Start(id)
        -- Start can synchronously fire ROUTES_CHANGED, or open a popup.
        local run = ns.Routes.Run()
        if run and run.id == id then Preview.End("set") end
    end))
    bar.showThem:SetScript("OnClick", ns.Safe(function()
        if current then Method(map, "SetMapID", current.map) end
    end))
    bar.back:SetScript("OnClick", ns.Safe(function() Preview.End("back") end))
    bar.close:SetScript("OnClick", ns.Safe(function() Preview.End("close") end))
    Widgets.Tooltip(bar.close, L.ROUTE_PREVIEW_CLOSE, L.ROUTE_PREVIEW_CLOSE)
    return bar
end

local function Setup()
    if provider then return true end
    local map = WorldMapFrame
    if not map or not MapCanvasDataProviderMixin or not MapCanvasPinMixin
        or not CreateFromMixins or not Mixin or not map.AddDataProvider
        or not map.AcquirePin or not map.RemoveAllPinsByTemplate or not map.SetMapID then return false end
    local container = Method(map, "GetCanvasContainer") or map.ScrollContainer
    if not container then return false end
    Mixin(WaypointTrackerRoutePinMixin, MapCanvasPinMixin, PinMethods)
    local p = CreateProvider()
    local ok = pcall(map.AddDataProvider, map, p)
    if not ok then return false end
    provider, Preview.provider = p, p
    return true
end

function Preview.Current() return current and current.id end

function Preview.End(reason)
    if not current then return end
    local previous = current
    current = nil
    if provider then provider:RefreshAllData() end
    if Preview.bar then Preview.bar:Hide() end
    if reason == "back" and not InCombat() then
        local map = provider and provider:GetMap() or WorldMapFrame
        if HideUIPanel then pcall(HideUIPanel, map) else Method(map, "Hide") end
        if ns.Window and ns.Window.Show then ns.Window.Show("routes") end
        if ns.RoutesUI and ns.RoutesUI.Select then ns.RoutesUI.Select(previous.id) end
    end
    ns.Fire("ROUTE_PREVIEW", nil)
end

function Preview.Show(id, mapID)
    if InCombat() then
        if ns.Window and ns.Window.SetStatus then ns.Window.SetStatus(L.IN_COMBAT_NO_PANELS, false) end
        return false, "combat"
    end
    if not WorldMapFrame or not Setup() then return false, "nomap" end
    local r = ns.Routes.Get(id)
    if not r then return false, "gone" end
    mapID = mapID or (Geo.CommonMap and Geo.CommonMap(r.pts)) or r.zone
    if not mapID then return false, "nomap" end
    if not Preview.bar then
        local map = provider:GetMap()
        local container = Method(map, "GetCanvasContainer") or map.ScrollContainer
        Preview.bar = CreateBar(map, container)
    end
    Preview.End("replaced")
    local returnTo = ns.Window and ns.Window.IsShown and ns.Window.IsShown()
    local returnTab = ns.Window and ns.Window.GetTab and ns.Window.GetTab()
    if ns.Window and ns.Window.Hide then ns.Window.Hide() end
    current = { id = id, map = mapID }
    local map = WorldMapFrame
    local ok
    if OpenWorldMap then
        ok = pcall(OpenWorldMap, mapID)
    else
        if ShowUIPanel then ok = pcall(ShowUIPanel, map) else ok = pcall(map.Show, map) end
    end
    -- OnShow resets the map; choose the requested map after it runs.
    if ok and Method(map, "IsShown") and Method(map, "GetMapID") ~= mapID then
        ok = pcall(map.SetMapID, map, mapID)
    end
    if not ok or not current or not Method(map, "IsShown") or Method(map, "GetMapID") ~= mapID then
        Preview.End("close")
        if returnTo and ns.Window and ns.Window.Show then ns.Window.Show(returnTab) end
        return false, "refused"
    end
    provider:RefreshAllData()
    ns.Fire("ROUTE_PREVIEW", id)
    return true
end

ns.On("LOGIN", function()
    if not Setup() and EventUtil and EventUtil.ContinueOnAddOnLoaded then
        pcall(EventUtil.ContinueOnAddOnLoaded, "Blizzard_WorldMap", ns.Safe(Setup))
    end
end)
ns.On("ROUTES_CHANGED", function()
    if current then
        if not ns.Routes.Get(current.id) then Preview.End("gone")
        elseif ns.Routes.Run() and ns.Routes.Run().id == current.id then Preview.End("set")
        elseif provider then provider:RefreshAllData() end
    end
end)
