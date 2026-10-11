-- World map: waypoint pins, Ctrl + Right-click to add a waypoint, and the
-- coordinates at the bottom of the map.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local TEMPLATE = "WaypointTrackerMapPinTemplate"
local ACTIVE_COLOUR = { 1.0, 0.82, 0.0 }
local OTHER_COLOUR = { 0.55, 0.80, 1.0 }

-- The XML template points at this global; it is completed in Setup() once
-- the map's own pin code is available.
WaypointTrackerMapPinMixin = WaypointTrackerMapPinMixin or {}
local PinMethods = {}

-- The map calls this on every AcquirePin, but it is a protected function:
-- from addon code it gets blocked in combat. We set pass-through once, out
-- of combat, when the pin is created and ignore the per-acquire calls.
function PinMethods:SetPassThroughButtons() end

function PinMethods:OnLoad()
    if not InCombatLockdown() then
        local mt = getmetatable(self)
        local methods = mt and mt.__index
        local real = type(methods) == "table" and methods.SetPassThroughButtons
        if real then
            pcall(real, self, "RightButton") -- right-click still zooms the map out
        end
    end
    self:SetHitRectInsets(0, 0, -11, 11)
    if not pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION") then
        pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI")
    end
    self:SetScalingLimits(1, 1.0, 1.2)
end

function PinMethods:OnAcquired(wp, x, y)
    self.wp = wp
    self:SetPosition(x, y)
    local c = (wp == WP.GetActive()) and ACTIVE_COLOUR or OTHER_COLOUR
    self.Icon:SetVertexColor(c[1], c[2], c[3])
    self.Highlight:SetVertexColor(c[1], c[2], c[3])
end

function PinMethods:OnMouseEnter()
    local wp = self.wp
    if not wp then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(WP.ShortName(wp), 1, 0.82, 0)
    GameTooltip:AddLine(("%s  %s"):format(Geo.GetMapName(wp.m), Geo.FormatCoords(wp.x, wp.y)), 1, 1, 1)
    local dist = Geo.GetVector(wp)
    if dist then
        GameTooltip:AddLine(Geo.FormatDistance(dist), 0.8, 0.8, 0.8)
    end
    -- Real routes: the way there
    local T = ns.Travel
    if wp == WP.GetActive() and T and T.Enabled() then
        local steps = T.Describe()
        if #steps > 0 then
            GameTooltip:AddLine(L.TRAVEL_STEPS_HEADER, 1, 0.82, 0)
            for i = 1, math.min(#steps, 8) do
                GameTooltip:AddLine(("%d. %s"):format(i, steps[i]), 0.9, 0.9, 0.9)
            end
        end
    end
    GameTooltip:AddLine(L.PIN_CLICK, 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L.PIN_ALT_CLICK, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function PinMethods:OnMouseLeave()
    GameTooltip:Hide()
end

function PinMethods:OnClick(button)
    -- let the map's own pin handlers (e.g. its pin-placing mode) go first
    local map = self:GetMap()
    local actions = MapCanvasMixin and MapCanvasMixin.MouseAction
    if map and actions and map.ProcessGlobalPinMouseActionHandlers and map:ProcessGlobalPinMouseActionHandlers(actions.Click, button) then
        return
    end
    if button ~= "LeftButton" or not self.wp then
        return
    end
    if IsAltKeyDown() then
        WP.Remove(self.wp)
    else
        WP.SetActive(self.wp)
    end
end

-- ---------------------------------------------------------------------------
-- Data provider
-- ---------------------------------------------------------------------------
local provider

local function RefreshPins()
    if provider and provider:GetMap() and WorldMapFrame:IsShown() then
        provider:RefreshAllData()
    end
end

local function CreateProvider()
    provider = CreateFromMixins(MapCanvasDataProviderMixin)

    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    end

    function provider:RefreshAllData()
        self:RemoveAllData()
        if not ns.Get("worldPins") then
            return
        end
        local map = self:GetMap()
        local mapID = map:GetMapID()
        if not mapID then
            return
        end
        local activeWp = WP.GetActive()
        for _, wp in ipairs(WP.List()) do
            if wp ~= activeWp then
                local x, y = Geo.TranslateToMap(wp.m, wp.x, wp.y, mapID)
                if x then
                    map:AcquirePin(TEMPLATE, wp, x, y)
                end
            end
        end
        -- draw the arrow's waypoint last so it sits on top
        if activeWp then
            local x, y = Geo.TranslateToMap(activeWp.m, activeWp.x, activeWp.y, mapID)
            if x then
                map:AcquirePin(TEMPLATE, activeWp, x, y)
            end
        end
    end

    return provider
end

-- ---------------------------------------------------------------------------
-- Ctrl + Right-click on the map
-- ---------------------------------------------------------------------------
local function OnCanvasClick(canvas, button, cursorX, cursorY)
    if button ~= "RightButton" or not IsControlKeyDown() or not ns.Get("mapClick") then
        return false
    end
    local mapID = canvas:GetMapID()
    if not mapID or not cursorX or not cursorY then
        return false
    end
    if cursorX < 0 or cursorX > 1 or cursorY < 0 or cursorY > 1 then
        return false
    end
    local m, x, y = Geo.NormalizeToZone(mapID, cursorX, cursorY)
    if not Geo.MapToWorld(m, x, y) then
        return false
    end
    WP.Add(m, x, y)
    return true
end

-- ---------------------------------------------------------------------------
-- Coordinates text on the world map
-- ---------------------------------------------------------------------------
local coords, coordsText

local function HasBlizzardCoords()
    if C_CVar and C_CVar.GetCVarInfo then
        local ok, value = pcall(C_CVar.GetCVarInfo, "worldMapShowPlayerCoords")
        if ok and value ~= nil then return true end
    end
    if GetCVar then
        local ok, value = pcall(GetCVar, "worldMapShowPlayerCoords")
        return ok and value ~= nil
    end
    return false
end

local function UpdateCoords()
    local mapID = WorldMapFrame:GetMapID()
    local parts = {}
    if mapID then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local px, py = ns.XY(pos)
            px, py = ns.Num(px), ns.Num(py)
            if px and py and (px > 0 or py > 0) then
                parts[#parts + 1] = ("%s: %s"):format(L.YOU, Geo.FormatCoords(px, py))
            end
        end
        if WorldMapFrame.GetNormalizedCursorPosition and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer:IsMouseOver() then
            local cx, cy = WorldMapFrame:GetNormalizedCursorPosition()
            if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
                parts[#parts + 1] = ("%s: %s"):format(L.CURSOR, Geo.FormatCoords(cx, cy))
            end
        end
    end
    coordsText:SetText(table.concat(parts, "     "))
end

local function CreateCoords()
    local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
    coords = CreateFrame("Frame", nil, parent)
    coords:SetSize(400, 20)
    coords:SetPoint("BOTTOM", parent, "BOTTOM", 0, 6)
    coords:SetFrameLevel(parent:GetFrameLevel() + 500)
    local bg = coords:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.45)
    bg:SetPoint("TOPLEFT", -4, 2)
    bg:SetPoint("BOTTOMRIGHT", 4, -2)
    coordsText = coords:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    coordsText:SetPoint("CENTER")
    coords.bg = bg
    local acc = 0
    local safe = ns.Safe(UpdateCoords)
    coords:SetShown(ns.Get("worldCoords"))
    coords:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.08 then
            return
        end
        acc = 0
        safe()
        local w = coordsText:GetStringWidth()
        self:SetWidth(math.max(40, (w or 0) + 12))
        bg:SetShown(coordsText:GetText() ~= nil and coordsText:GetText() ~= "")
    end)
end

local function SyncFromCVars()
    if not HasBlizzardCoords() then return end
    local get = GetCVarBool or (C_CVar and C_CVar.GetCVarBool)
    local ok, on = pcall(get, "worldMapShowPlayerCoords")
    -- Mirror Blizzard's choice without firing SETTING_CHANGED (which writes
    -- both CVars). Player and cursor coordinates may be enabled separately.
    if ok and on ~= nil and ns.settings then
        ns.settings.worldCoords = on and true or false
    end
end

local function ApplyCoords(write)
    local on = ns.Get("worldCoords")
    if HasBlizzardCoords() then
        local set = SetCVar or (C_CVar and C_CVar.SetCVar)
        if write and set then
            pcall(set, "worldMapShowPlayerCoords", on and "1" or "0")
            pcall(set, "worldMapShowCursorCoords", on and "1" or "0")
        end
        if coords then coords:Hide() end
    elseif WorldMapFrame then
        if not coords then CreateCoords() end
        coords:SetShown(on)
    end
end

-- ---------------------------------------------------------------------------
-- Setup (after the world map exists)
-- ---------------------------------------------------------------------------
local setupDone = false
local function Setup()
    ApplyCoords(false)
    if setupDone or not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin then
        return
    end
    setupDone = true
    Mixin(WaypointTrackerMapPinMixin, MapCanvasPinMixin, PinMethods)
    WorldMapFrame:AddDataProvider(CreateProvider())
    if WorldMapFrame.AddCanvasClickHandler then
        WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, 100)
    end
end

if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
    CVarCallbackRegistry:RegisterCallback("worldMapShowPlayerCoords", function()
        SyncFromCVars()
        if Settings and Settings.NotifyUpdate then
            pcall(Settings.NotifyUpdate, "WAYPOINTTRACKER_worldCoords")
        end
    end, ns)
end

ns.On("LOGIN", function()
    SyncFromCVars()
    Setup()
    if not WorldMapFrame and EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", ns.Safe(Setup))
    end
end)

ns.On("WAYPOINTS_CHANGED", RefreshPins)
ns.On("ACTIVE_CHANGED", RefreshPins)
ns.On("SETTING_CHANGED", function(key)
    if key == "worldPins" or key == nil then
        RefreshPins()
    end
    if key == "worldCoords" or key == nil then
        ApplyCoords(true)
    end
end)
