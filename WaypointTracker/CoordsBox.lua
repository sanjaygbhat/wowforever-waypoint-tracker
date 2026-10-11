-- A small, click-through coordinates box, placed in Edit Mode.
local _, ns = ...
local Geo, L = ns.Geo, ns.L

local box

local function DefaultAnchor(f)
    if Minimap then
        f:SetPoint("TOP", Minimap, "BOTTOM", 0, -24)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -240)
    end
end

local function Refresh()
    if not box then return end
    local editing = ns.EditMode and ns.EditMode.IsActive and ns.EditMode.IsActive()
    local on = ns.Get("coordsBox")
    box:SetAlpha(editing and not on and 0.5 or 1)
    box:SetShown(on or editing)
end

local function Create()
    local ok
    ok, box = pcall(CreateFrame, "Frame", "WaypointTrackerCoordsBox", UIParent, "BackdropTemplate")
    if not ok then box = CreateFrame("Frame", "WaypointTrackerCoordsBox", UIParent) end
    box:SetSize(110, 28)
    box:SetFrameStrata("MEDIUM")
    box:SetClampedToScreen(true)
    box:SetMovable(true)
    box:EnableMouse(false)
    if box.SetBackdrop then
        box:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        box:SetBackdropColor(0, 0, 0, 0.7)
        box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.text:SetPoint("CENTER")
    box.text:SetText("--, --")
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
    local edit = ns.EditMode
    if edit and edit.RegisterSystem then
        edit.RegisterSystem({
            key = "coords", frame = box, name = L.COORDS_EDIT_NAME,
            settings = { { type = "checkbox", key = "coordsBox", label = L.COORDS_BOX, tooltip = L.COORDS_BOX_DESC } },
            defaultPoint = { "TOP", "BOTTOM", 0, -24 }, defaultAnchor = DefaultAnchor,
            shouldShow = function() return true end,
            onEnter = Refresh, onExit = Refresh,
            onReset = function()
                edit.SavePosition("coords", nil)
                edit.ApplyPosition("coords")
            end,
        })
    else
        local point, rel, x, y = ns.SavedPoint(ns.Get("coordsPos"))
        if point then box:SetPoint(point, UIParent, rel, x, y) else DefaultAnchor(box) end
    end
    Refresh()
end

ns.On("LOGIN", Create)
ns.On("SETTING_CHANGED", function(key)
    if key == "coordsBox" or key == nil then Refresh() end
end)
