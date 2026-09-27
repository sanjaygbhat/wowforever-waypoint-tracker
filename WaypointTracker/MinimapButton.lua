-- Minimap button (same idea as WoW Translate's): left-click opens the
-- window, right-click shows/hides the arrow, drag to move it around.
local _, ns = ...
local L = ns.L

local button

local function UpdatePosition()
    if not button then
        return
    end
    local angle = math.rad(tonumber(ns.Get("minimapAngle")) or 200)
    local radius = (Minimap:GetWidth() / 2) + 8
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.ADDON_TITLE)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_LEFT, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_RIGHT, 0.8, 0.8, 0.8)
    if owner == button then
        GameTooltip:AddLine(L.MINIMAP_TOOLTIP_DRAG, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

local function Create()
    button = CreateFrame("Button", "WaypointTrackerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "Icon")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
            ns.settings.minimapAngle = angle
            UpdatePosition()
        end)
        GameTooltip:Hide()
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            WaypointTracker_ToggleArrow()
        else
            WaypointTracker_ToggleWindow()
        end
    end)

    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function Refresh()
    if ns.Get("minimapButton") then
        if not button then
            Create()
        end
        UpdatePosition()
        button:Show()
    elseif button then
        button:Hide()
    end
end

ns.On("LOGIN", function()
    if Minimap then
        Refresh()
    end
end)

ns.On("SETTING_CHANGED", function(key)
    if (key == "minimapButton" or key == nil) and Minimap then
        Refresh()
    end
end)

-- Addon compartment (the addon list button on the minimap)
function WaypointTracker_OnAddonCompartmentClick(_, mouse)
    if mouse == "RightButton" then
        WaypointTracker_ToggleArrow()
    else
        WaypointTracker_ToggleWindow()
    end
end

function WaypointTracker_OnAddonCompartmentEnter(_, frame)
    ShowTooltip(frame or UIParent)
end

function WaypointTracker_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
