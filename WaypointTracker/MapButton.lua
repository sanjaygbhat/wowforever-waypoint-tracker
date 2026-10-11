-- Quick access to this map's waypoints and display settings.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local function Menu(root)
    root:CreateTitle(L.MENU_QUICK_TITLE)
    local mapID = WorldMapFrame:GetMapID()
    if mapID then
        for _, wp in ipairs(WP.List()) do
            if Geo.TranslateToMap(wp.m, wp.x, wp.y, mapID) then
                root:CreateRadio(WP.ShortName(wp), function() return WP.GetActive() == wp end,
                    function() WP.SetActive(wp) end)
            end
        end
    end
    root:CreateDivider()
    root:CreateCheckbox(L.WORLD_PINS, function() return ns.Get("worldPins") end,
        function() ns.Set("worldPins", not ns.Get("worldPins")) end)
    root:CreateCheckbox(L.WORLD_COORDS, function() return ns.Get("worldCoords") end,
        function() ns.Set("worldCoords", not ns.Get("worldCoords")) end)
    root:CreateDivider()
    local clear = root:CreateButton(L.CLEAR_ALL, function()
        if WP.Count() == 0 then return end
        ns.Widgets.Ask("WAYPOINTTRACKER_CLEAR_ALL", WP.Count())
    end)
    if clear and clear.SetEnabled then clear:SetEnabled(WP.Count() > 0) end
end

local button
local function Setup()
    if button or not WorldMapFrame or not ns.Widgets then return end
    local container
    if WorldMapFrame.GetCanvasContainer then
        local ok, frame = pcall(WorldMapFrame.GetCanvasContainer, WorldMapFrame)
        if ok then container = frame end
    end
    container = container or WorldMapFrame.ScrollContainer
    if not container then return end
    button = CreateFrame("Button", "WaypointTrackerMapButton", container)
    button:SetSize(32, 32)
    button:SetFrameLevel(container:GetFrameLevel() + 510)
    if WorldMapFrame.WorldMapTrackingPinButton then
        button:SetPoint("TOP", WorldMapFrame.WorldMapTrackingPinButton, "BOTTOM", 0, 0)
    else
        button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -60)
    end
    button.Background = button:CreateTexture(nil, "BACKGROUND")
    button.Background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.Background:SetSize(25, 25)
    button.Background:SetPoint("TOPLEFT", 3, -4)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetSize(20, 20)
    button.Icon:SetPoint("TOPLEFT", 7, -6)
    button.Icon:SetTexture(ns.MEDIA .. "Pin")
    button.Icon:SetVertexColor(1, 0.82, 0)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", ns.Safe(function(self)
        if ns.Widgets and ns.Widgets.Menu then ns.Widgets.Menu(self, Menu) end
    end))
    ns.Widgets.Tooltip(button, L.MAP_BUTTON_TOOLTIP, L.MAP_BUTTON_CLICK)
    -- The map can be opened before the Waypoints tab registers this popup.
    ns.Widgets.Confirm("WAYPOINTTRACKER_CLEAR_ALL", {
        text = L.CLEAR_ALL_CONFIRM, button1 = L.YES, button2 = L.NO,
        onAccept = function() WP.ClearAll(true) end,
    })
end

ns.On("LOGIN", function()
    if WorldMapFrame then
        Setup()
    elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", ns.Safe(Setup))
    end
end)
