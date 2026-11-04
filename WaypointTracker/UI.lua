-- Compatibility for callers that still use the old UI entry points.
local _, ns = ...

local UI = {}
ns.UI = UI
UI.W = ns.Widgets
UI.widgets = ns.TabWaypoints.widgets

function UI.Show()
    ns.Window.Show("waypoints")
end

UI.Hide = ns.Window.Hide
UI.IsShown = ns.Window.IsShown
UI.RefreshWidgets = ns.Widgets.Refresh

function UI.Toggle()
    ns.Window.Toggle("waypoints")
end

function UI.Refresh()
    ns.TabWaypoints.Refresh()
    ns.Widgets.Refresh()
end

ns.On("SETTING_CHANGED", function(key)
    if key == "addonWaypoints" then
        ns.Print(ns.L.RELOAD_NEEDED, true)
    end
end)
