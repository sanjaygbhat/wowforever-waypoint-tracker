-- A small movable box that shows where you are (off by default).
local _, ns = ...
local Geo = ns.Geo

local box

local function Create()
    box = CreateFrame("Frame", "WaypointTrackerCoordsBox", UIParent, "BackdropTemplate")
    box:SetSize(110, 28)
    box:SetFrameStrata("MEDIUM")
    box:SetClampedToScreen(true)
    box:SetMovable(true)
    box:EnableMouse(true)
    box:RegisterForDrag("LeftButton")
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.7)
    box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.text:SetPoint("CENTER")

    local point, rel, x, y = ns.SavedPoint(ns.Get("coordsPos"))
    if point then
        box:SetPoint(point, UIParent, rel, x, y)
    elseif Minimap then
        box:SetPoint("TOP", Minimap, "BOTTOM", 0, -24)
    else
        box:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -240)
    end

    box:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    box:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if point then
            ns.settings.coordsPos = { point, relPoint, x, y }
        end
    end)

    local acc = 0
    local update = ns.Safe(function()
        local _, x, y = Geo.GetPlayerMapPosition()
        box.text:SetText(x and Geo.FormatCoords(x, y) or "--, --")
    end)
    box:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.2 then
            acc = 0
            update()
        end
    end)
end

local function Refresh()
    if ns.Get("coordsBox") then
        if not box then
            Create()
        end
        box:Show()
    elseif box then
        box:Hide()
    end
end

ns.On("LOGIN", Refresh)
ns.On("SETTING_CHANGED", function(key)
    if key == "coordsBox" or key == nil then
        Refresh()
    end
end)
