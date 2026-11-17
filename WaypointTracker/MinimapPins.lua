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
        pin.size, pin.on = PIN_SIZE, true -- as made: that size, shown
        pool[i] = pin
    end
    return pin
end

-- What each pin was last given (its place, size, colour, see-through and
-- whether it shows) is kept on it, so a pin that hasn't changed since the
-- last look is left alone. Only this file touches the pins.
local shown = 0 -- pins showing since the last update (the first `shown` of the pool)
local function HideFrom(n)
    shown = n - 1
    for i = n, #pool do
        local pin = pool[i]
        if pin.on then
            pin.on = false
            pin:Hide()
        end
        pin.wp = nil
    end
end

local function IsSquare()
    return GetMinimapShape and GetMinimapShape() == "SQUARE"
end

-- the player's position on each continent asked about in one update (the
-- same fallback rules as the arrow); the three lists are emptied each time
local askedCont, contX, contY = {}, {}, {}

-- (the driver below asks whether the minimap shows before it calls this)
local function Update()
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
    wipe(askedCont)
    wipe(contX)
    wipe(contY)

    local rotate = GetCVar("rotateMinimap") == "1"
    if rotate and C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then
        rotate = false
    end
    local facing = rotate and Geo.GetFacing() or 0
    local cf, sf = cos(facing or 0), sin(facing or 0)
    local half = Minimap:GetWidth() / 2
    local square = IsSquare()
    local activeWp = WP.GetActive()
    local activeR, activeG, activeB

    local n = 0
    for i = 1, #list do
        local wp = list[i]
        local isActive = wp == activeWp
        if showPins or isActive then
            local wcont, wx, wy = Geo.GetVectorWorld(wp)
            local px, py
            if wcont then
                if not askedCont[wcont] then
                    askedCont[wcont] = true
                    local cont, x, y = Geo.GetPlayerWorld(wcont)
                    if cont == wcont then
                        contX[wcont], contY[wcont] = x, y
                    end
                end
                px, py = contX[wcont], contY[wcont]
            end
            if px then
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
                    if pin.size ~= size then
                        pin.size = size
                        pin:SetSize(size, size)
                    end
                    if pin.sx ~= sx or pin.sy ~= sy then
                        pin.sx, pin.sy = sx, sy
                        pin:ClearAllPoints()
                        -- the pin's tip marks the spot
                        pin:SetPoint("BOTTOM", Minimap, "CENTER", sx, sy)
                    end
                    local r, g, b = 0.55, 0.8, 1
                    if isActive then
                        if not activeR then
                            activeR, activeG, activeB = ns.PinColour()
                        end
                        r, g, b = activeR, activeG, activeB
                    end
                    if pin.r ~= r or pin.g ~= g or pin.b ~= b then
                        pin.r, pin.g, pin.b = r, g, b
                        pin.icon:SetVertexColor(r, g, b)
                    end
                    local alpha = onEdge and 0.75 or 1
                    if pin.alpha ~= alpha then
                        pin.alpha = alpha
                        pin:SetAlpha(alpha)
                    end
                    if not pin.on then
                        pin.on = true
                        pin:Show()
                    end
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
    -- no waypoints and no pin showing, or the minimap hidden (the pins
    -- stay as they are until it shows again): nothing to do
    if (shown == 0 and WP.Count() == 0) or not Minimap:IsVisible() then
        return
    end
    safeUpdate()
end)
driver:Hide()

ns.On("LOGIN", function()
    if Minimap then
        driver:Show()
    end
end)
