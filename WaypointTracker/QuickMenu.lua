local _, ns = ...
local L = ns.L
local WP, Geo = ns.WP, ns.Geo

local QuickMenu = {}
ns.QuickMenu = QuickMenu

local function Checkbox(root, label, key)
    root:CreateCheckbox(label, function() return ns.Get(key) end, ns.Safe(function()
        ns.Set(key, not ns.Get(key))
    end))
end

function QuickMenu.Build(root)
    root:CreateTitle(L.MENU_QUICK_TITLE)
    Checkbox(root, L.SHOW_ARROW, "arrowShown")
    Checkbox(root, L.TREASURE_HUNT, "treasureHunt")
    Checkbox(root, L.REAL_ROUTES, "realRoutes")
    root:CreateDivider()
    root:CreateButton(L.BINDING_HERE, ns.Safe(function() WP.AddHere() end))
    root:CreateButton(L.BINDING_SHARE, ns.Safe(function()
        if WaypointTracker_ShareHere then WaypointTracker_ShareHere() end
    end))
    local clear = root:CreateButton(L.BINDING_CLEAR, ns.Safe(function()
        if WaypointTracker_ClearActive then WaypointTracker_ClearActive() end
    end))
    if clear and clear.SetEnabled then clear:SetEnabled(WP.GetActive() ~= nil) end
    root:CreateDivider()
    root:CreateButton(L.OPEN_EDIT_MODE, ns.Safe(function()
        if ns.EditMode and ns.EditMode.Enter then
            local ok, why = ns.EditMode.Enter()
            if not ok and why == "combat" then
                ns.Print(L.IN_COMBAT_NO_PANELS, true)
            end
        end
    end))
    root:CreateButton(L.SETTINGS, ns.Safe(function()
        if ns.Options and ns.Options.Open then ns.Options.Open() end
    end))
end

function QuickMenu.Show(owner)
    if ns.Widgets and ns.Widgets.Menu then
        return ns.Widgets.Menu(owner, QuickMenu.Build)
    end
end

function QuickMenu.Tooltip(owner, withDrag)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.ADDON_TITLE)
    local wp = WP.GetActive()
    if wp then
        local text = L.POINTING_TO:format(WP.ShortName(wp))
        local dist = Geo.FormatDistance(Geo.GetVector(wp))
        if dist ~= "" then text = text .. " · " .. dist end
        GameTooltip:AddLine(text)
    end
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_LEFT, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_RIGHT, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_SHIFT, 0.8, 0.8, 0.8)
    if withDrag then
        GameTooltip:AddLine(L.MINIMAP_TOOLTIP_DRAG, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end
