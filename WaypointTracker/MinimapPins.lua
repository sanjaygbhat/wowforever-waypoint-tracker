-- Minimap: pins for nearby waypoints, and the arrow's waypoint kept on the
-- minimap's edge when it is further away.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local sqrt, sin, cos, abs, max = math.sqrt, math.sin, math.cos, math.abs, math.max

local PIN_SIZE = 14
local ACTIVE_SIZE = 18

local pool = {}

local function OnPinEnter(self)
    local wp = self.wp
    if not wp then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(WP.ShortName(wp), 1, 0.82, 0)
    local dist = Geo.GetVector(wp)
    if dist then
        GameTooltip:AddLine(Geo.FormatDistance(dist), 1, 1, 1)
    end
    GameTooltip:AddLine(L.PIN_CLICK, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function OnPinLeave()
    GameTooltip:Hide()
end

local function OnPinClick(self)
    if self.wp then
        WP.SetActive(self.wp)
    end
end

local function GetPin(i)
    local pin = pool[i]
    if not pin then
        pin = CreateFrame("Button", nil, Minimap)
        pin:SetSize(PIN_SIZE, PIN_SIZE)
        pin:SetFrameStrata("MEDIUM")
        pin:SetFrameLevel(Minimap:GetFrameLevel() + 6)
        pin.icon = pin:CreateTexture(nil, "OVERLAY")
        pin.icon:SetTexture(ns.MEDIA .. "Pin")
        pin.icon:SetAllPoints()
        pin:SetScript("OnEnter", OnPinEnter)
        pin:SetScript("OnLeave", OnPinLeave)
        pin:SetScript("OnClick", OnPinClick)
        pin:RegisterForClicks("LeftButtonUp")
        pool[i] = pin
    end
    return pin
end

local function HideFrom(n)
    for i = n, #pool do
        pool[i]:Hide()
        pool[i].wp = nil
    end
end

local function IsSquare()
    return GetMinimapShape and GetMinimapShape() == "SQUARE"
end

local function Update()
    if not Minimap:IsVisible() then
        return
    end
    local showPins, showEdge = ns.Get("minimapPins"), ns.Get("minimapEdge")
    local list = WP.List()
    if (not showPins and not showEdge) or #list == 0 then
        HideFrom(1)
        return
    end
    local radius = C_Minimap and C_Minimap.GetViewRadius and ns.Num(C_Minimap.GetViewRadius())
    if not radius or radius <= 0 then
        HideFrom(1)
        return
    end
    -- player position per continent (same fallback rules as the arrow)
    local playerPos = {}
    local function PlayerOn(wcont)
        local p = playerPos[wcont]
        if p == nil then
            local cont, x, y = Geo.GetPlayerWorld(wcont)
            p = (cont == wcont) and { x, y } or false
            playerPos[wcont] = p
        end
        return p
    end

    local rotate = GetCVar("rotateMinimap") == "1"
    if rotate and C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then
        rotate = false
    end
    local facing = rotate and Geo.GetFacing() or 0
    local cf, sf = cos(facing or 0), sin(facing or 0)
    local half = Minimap:GetWidth() / 2
    local square = IsSquare()
    local activeWp = WP.GetActive()

    local n = 0
    for _, wp in ipairs(list) do
        local isActive = wp == activeWp
        if showPins or isActive then
            local wcont, wx, wy = Geo.MapToWorld(wp.m, wp.x, wp.y)
            local pp = wcont and PlayerOn(wcont)
            if pp then
                local px, py = pp[1], pp[2]
                -- screen offset: right = east (-west), up = north
                local sx = -(wy - py) / radius * half
                local sy = (wx - px) / radius * half
                if rotate then
                    sx, sy = sx * cf + sy * sf, -sx * sf + sy * cf
                end
                local limit = half - 6
                local d = square and max(abs(sx), abs(sy)) or sqrt(sx * sx + sy * sy)
                local onEdge = d > limit
                if onEdge and isActive and showEdge then
                    sx, sy = sx / d * limit, sy / d * limit
                end
                if (not onEdge and showPins) or (onEdge and isActive and showEdge) then
                    n = n + 1
                    local pin = GetPin(n)
                    pin.wp = wp
                    local size = isActive and ACTIVE_SIZE or PIN_SIZE
                    pin:SetSize(size, size)
                    pin:ClearAllPoints()
                    -- the pin's tip marks the spot
                    pin:SetPoint("BOTTOM", Minimap, "CENTER", sx, sy)
                    if isActive then
                        pin.icon:SetVertexColor(1, 0.82, 0)
                    else
                        pin.icon:SetVertexColor(0.55, 0.8, 1)
                    end
                    pin:SetAlpha(onEdge and 0.75 or 1)
                    pin:Show()
                end
            end
        end
    end
    HideFrom(n + 1)
end

local driver = CreateFrame("Frame")
local acc = 0
local safeUpdate = ns.Safe(Update)
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.05 then
        return
    end
    acc = 0
    safeUpdate()
end)
driver:Hide()

ns.On("LOGIN", function()
    if Minimap then
        driver:Show()
    end
end)
