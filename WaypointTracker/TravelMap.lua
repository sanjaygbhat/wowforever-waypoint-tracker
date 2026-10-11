-- TravelMap: Real routes on the world map (a line along the way you're
-- going) and, at a flight master, a button that flies you where the route
-- goes next.
local _, ns = ...
local L, Geo = ns.L, ns.Geo

local TravelMap = {}
ns.TravelMap = TravelMap

local COLOURS = {
    walk = { 1.0, 0.82, 0.0, 0.9 },
    taxi = { 0.45, 0.85, 1.0, 0.9 },
    ship = { 0.35, 0.65, 1.0, 0.9 },
    zeppelin = { 0.35, 0.65, 1.0, 0.9 },
    tram = { 0.75, 0.75, 0.75, 0.9 },
}
local THICKNESS = 3

local layer -- a frame over the map's canvas
local lines = {}

local function Layer()
    if layer then
        return layer
    end
    local ok, canvas = pcall(function()
        return WorldMapFrame:GetCanvas()
    end)
    if not ok or type(canvas) ~= "table" or not canvas.CreateLine then
        return nil
    end
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel((canvas:GetFrameLevel() or 1) + 20)
    return layer
end

local function Clear()
    for _, l in ipairs(lines) do
        l:Hide()
    end
end

local function Line(i)
    local l = lines[i]
    if not l then
        l = layer:CreateLine(nil, "OVERLAY")
        lines[i] = l
    end
    return l
end

-- every stop of the plan as world positions, with how you get to each
local function Points(plan)
    local T = ns.Travel
    local out = {}
    for _, e in ipairs(plan.path) do
        local cont, wx, wy = T.Pos(e.node)
        local how = e.via
        local method = type(how) == "table" and (how.method or how.kind) or how
        out[#out + 1] = { cont = cont, wx = wx, wy = wy, method = method }
    end
    return out
end

function TravelMap.Draw()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then
        return
    end
    if not Layer() then
        return
    end
    Clear()
    local T = ns.Travel
    local plan = T and T.Enabled() and ns.Get("travelMapLine") and T.Current()
    if not plan or #plan.path < 3 then
        return
    end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not mapID then
        return
    end
    local w, h = layer:GetWidth(), layer:GetHeight()
    if not w or w <= 0 then
        return
    end
    local scale = 1
    local scroll = WorldMapFrame.ScrollContainer
    if scroll and scroll.GetCanvasScale then
        scale = scroll:GetCanvasScale() or 1
    end
    local pts, n = Points(plan), 0
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        local colour = COLOURS[b.method]
        if colour and a.cont and a.cont == b.cont then
            local ax, ay = Geo.WorldToMap(a.cont, a.wx, a.wy, mapID)
            local bx, by = Geo.WorldToMap(b.cont, b.wx, b.wy, mapID)
            if ax and bx then
                n = n + 1
                local l = Line(n)
                l:SetThickness(THICKNESS / scale)
                l:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
                l:SetStartPoint("TOPLEFT", layer, ax * w, -ay * h)
                l:SetEndPoint("TOPLEFT", layer, bx * w, -by * h)
                l:Show()
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- At the flight master
-- ---------------------------------------------------------------------------
local flyButton

local function FlightTarget()
    local T = ns.Travel
    local plan = T and T.Enabled() and T.Current()
    local t = plan and plan.target
    local how = t and type(t.via) == "table" and t.via
    if not (how and how.method == "taxi") then
        return nil
    end
    return (T.RideEnd(plan.path, plan.index))
end

local function SlotFor(nodeID, nodes)
    for _, node in ipairs(nodes or {}) do
        if node.nodeID == nodeID then
            return node.slotIndex
        end
    end
end

function TravelMap.OnFlightMap(nodes)
    if flyButton then
        flyButton:Hide()
    end
    local dest = FlightTarget()
    local parent = TaxiFrame
    if not (dest and dest.taxi and parent) then
        return
    end
    local slot = SlotFor(dest.taxi, nodes)
    if not slot then
        return
    end
    local name = ns.Travel.PlaceName(dest)
    if not flyButton then
        flyButton = CreateFrame("Button", "WaypointTrackerFlyButton", parent, "UIPanelButtonTemplate")
        flyButton:SetSize(220, 24)
        flyButton:SetPoint("TOP", parent, "BOTTOM", 0, 4)
        flyButton:SetScript("OnClick", function(self)
            if self.slot and TakeTaxiNode then
                pcall(TakeTaxiNode, self.slot)
            end
        end)
    end
    flyButton.slot = slot
    flyButton:SetText(L.TRAVEL_FLY_BUTTON:format(name))
    flyButton:Show()
    ns.Print(L.TRAVEL_FLY_HINT:format(name))
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
ns.On("TRAVEL_PLANNED", function()
    TravelMap.Draw()
end)

ns.RegisterEvent("TAXIMAP_OPENED", function()
    local T = ns.Travel
    if not (T and T.Enabled()) then
        return
    end
    -- Travel.lua has read the map and planned again (its handler runs first)
    TravelMap.OnFlightMap(T.flightNodes)
end)

ns.RegisterEvent("TAXIMAP_CLOSED", function()
    if flyButton then
        flyButton:Hide()
    end
end)

ns.On("LOGIN", function()
    if WorldMapFrame and hooksecurefunc then
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
                ns.Call(TravelMap.Draw)
            end)
        end
        WorldMapFrame:HookScript("OnShow", function()
            ns.Call(TravelMap.Draw)
        end)
    end
end)

ns.On("SETTING_CHANGED", function(key)
    if key == "travelMapLine" or key == "realRoutes" then
        if layer then
            Clear()
        end
        TravelMap.Draw()
    end
end)
