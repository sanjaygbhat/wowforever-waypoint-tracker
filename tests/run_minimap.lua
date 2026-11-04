-- Minimap and compartment entry points, their menu and shared tooltip.
-- Run from the repository root: lua5.1 tests/run_minimap.lua [--bare]
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end

if arg[1] == "--bare" then
    local loadAddon, ns = M.LoadAddon
    M.LoadAddon = function(...)
        ns = loadAddon(...)
        return ns
    end
    dofile("tests/run_bare.lua")
    M.LoadAddon = loadAddon
    check(MenuUtil == nil, "bare harness removes MenuUtil before loading")
    ns.WP.ClearAll(true)
    local button = WaypointTrackerMinimapButton
    button:GetScript("OnClick")(button, "RightButton")
    check(ns.WP.Count() == 1 and ns.Widgets.lastMenu and #ns.Widgets.lastMenu.items == 11, "bare minimap right-click falls back to Add here")
    ns.WP.ClearAll(true)
    WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "RightButton")
    check(ns.WP.Count() == 1, "bare compartment right-click falls back to Add here")
    check(#M.errors == 0, "bare entry points report no errors")
    print(("%d passed, %d failed"):format(passed, failed))
    if failed > 0 then os.exit(1) end
    return
end

WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local WP, Geo, L = ns.WP, ns.Geo, ns.L

-- The feature tabs are implemented by sibling parcels. Use empty tabs only
-- while they are absent, so the real shell can still exercise minimap clicks.
for i, key in ipairs({ "waypoints", "find", "routes" }) do
    if not ns.Window.tabs[key] then
        ns.Window.RegisterTab({ key = key, order = i, title = key })
    end
end

local button = WaypointTrackerMinimapButton
check(button and button:IsShown(), "minimap button shown after login")
local function click(mouse)
    button:GetScript("OnClick")(button, mouse)
end
ns.Window.Hide()
ns.Window.ShowTab("routes")
click("LeftButton")
check(WaypointTrackerFrame:IsShown() and ns.Window.GetTab() == "routes", "left-click opens window on last tab")
click("LeftButton")
check(not WaypointTrackerFrame:IsShown(), "left-click closes window")

WP.ClearAll(true)
M.shift = true
click("LeftButton")
M.shift = false
check(WP.Count() == 1 and WP.GetActive(), "shift-left adds and selects a waypoint here")
check(not ns.Window.IsShown(), "shift-left leaves closed window closed")
ns.Window.Show()
M.shift = true
click("LeftButton")
M.shift = false
check(ns.Window.IsShown(), "shift-left leaves open window open")
ns.Window.Hide()

-- Record ownership and enabled state at the native menu-generator boundary.
-- The shared mock's menu descriptions expose SetEnabled but do not record it.
local menuOwner
local createMenu = MenuUtil.CreateContextMenu
MenuUtil.CreateContextMenu = function(owner, generator)
    menuOwner = owner
    return createMenu(owner, function(menuOwner, root)
        local createButton = root.CreateButton
        function root:CreateButton(...)
            local item = createButton(self, ...)
            local setEnabled = item.SetEnabled
            function item:SetEnabled(enabled)
                self.enabled = enabled
                setEnabled(self, enabled)
            end
            return item
        end
        generator(menuOwner, root)
    end)
end
click("RightButton")
local root = M.lastMenu
check(root and menuOwner == button, "right-click opens menu owned by minimap button")
check(not ns.Window.IsShown(), "right-click leaves window closed")
check(root.items[1].kind == "title" and root.items[1].text == L.MENU_QUICK_TITLE, "quick menu title")
local counts, items = {}, {}
for _, item in ipairs(root.items) do
    counts[item.kind] = (counts[item.kind] or 0) + 1
    if item.text then items[item.text] = item end
end
check(counts.checkbox == 3, "menu has three checkboxes")
check(counts.button == 5 and items[L.BINDING_HERE] and items[L.BINDING_SHARE] and items[L.BINDING_CLEAR], "menu has three waypoint actions")
check(items[L.OPEN_EDIT_MODE] and items[L.SETTINGS], "menu has Edit Mode and Settings")
check(counts.divider == 2 and #root.items == 11, "menu groups separated by two dividers")
check(items[L.BINDING_CLEAR].enabled == true, "clear active is enabled with an active waypoint")

local changes = {}
ns.On("SETTING_CHANGED", function(key) changes[key or "all"] = (changes[key or "all"] or 0) + 1 end)
for _, option in ipairs({
    { L.SHOW_ARROW, "arrowShown" }, { L.TREASURE_HUNT, "treasureHunt" }, { L.REAL_ROUTES, "realRoutes" },
}) do
    local item, key = items[option[1]], option[2]
    local before = ns.Get(key)
    check(item.isSelected() == before, key .. " reads setting")
    item.fn()
    check(ns.Get(key) == not before and changes[key] == 1, key .. " toggles through ns.Set")
    check(item.isSelected() == not before, key .. " selection reflects changes immediately")
    item.fn()
    check(ns.Get(key) == before, key .. " toggles off again")
end

WP.ClearAll(true)
click("RightButton")
local function ClearItem(menu)
    for _, item in ipairs(menu.items) do
        if item.text == L.BINDING_CLEAR then return item end
    end
end
check(ClearItem(M.lastMenu).enabled == false, "clear active is disabled with no waypoints")
WP.Add(37, 0.4, 0.5, { setActive = false, silent = true })
WP.SetActive(nil, true)
click("RightButton")
check(WP.Count() == 1 and not WP.GetActive() and ClearItem(M.lastMenu).enabled == false,
    "clear active stays disabled when saved waypoints have no active waypoint")
WP.ClearAll(true)
items[L.BINDING_HERE].fn()
check(WP.Count() == 1 and WP.GetActive(), "Add here menu action adds waypoint")
click("RightButton")
check(ClearItem(M.lastMenu).enabled == true, "rebuilt menu enables clear active after adding here")
local before = WP.Count()
M.chatText = nil
items[L.BINDING_SHARE].fn()
check(M.chatText and M.chatText:find(Geo.GetMapName(WP.GetActive().m), 1, true), "Share here opens location in chat")
check(WP.Count() == before, "Share here keeps waypoint list")
items[L.BINDING_CLEAR].fn()
check(WP.Count() == 0 and not WP.GetActive(), "Clear active menu action removes waypoint")

-- Navigation APIs are provided by sibling parcels; verify calls and combat
-- feedback using their contract without depending on their UI implementation.
local editMode, options = ns.EditMode, ns.Options
local editCalls, optionsCalls = 0, 0
ns.EditMode = { Enter = function()
    if ns.InCombat() then return false, "combat" end
    editCalls = editCalls + 1
    return true
end }
ns.Options = { Open = function() optionsCalls = optionsCalls + 1 end }
items[L.OPEN_EDIT_MODE].fn()
items[L.SETTINGS].fn()
check(editCalls == 1 and optionsCalls == 1, "navigation buttons delegate to Enter and Open")
M.player.combat = true
local messages = #M.printed
ns.Set("chatMessages", false)
items[L.OPEN_EDIT_MODE].fn()
check(editCalls == 1 and #M.printed == messages + 1 and M.printed[#M.printed]:find(L.IN_COMBAT_NO_PANELS, 1, true), "Edit Mode combat refusal prints even with chat disabled")
M.player.combat = false
ns.Set("chatMessages", true)
ns.EditMode, ns.Options = nil, nil
items[L.OPEN_EDIT_MODE].fn()
items[L.SETTINGS].fn()
check(#M.errors == 0, "missing navigation modules are guarded")
ns.EditMode, ns.Options = editMode, options

local tooltipOwner
local setOwner = GameTooltip.SetOwner
GameTooltip.SetOwner = function(self, owner, anchor)
    tooltipOwner = owner
    setOwner(self, owner, anchor)
end
local function hover()
    M.tooltip = {}
    button:GetScript("OnEnter")(button)
end
hover()
check(tooltipOwner == button and #M.tooltip == 5, "inactive minimap tooltip has title and four hints")
check(M.tooltip[1] == L.ADDON_TITLE and M.tooltip[2] == L.MINIMAP_TOOLTIP_LEFT and M.tooltip[3] == L.MINIMAP_TOOLTIP_RIGHT and M.tooltip[4] == L.MINIMAP_TOOLTIP_SHIFT and M.tooltip[5] == L.MINIMAP_TOOLTIP_DRAG, "minimap tooltip wording and order")
local wp = WP.Add(52, 0.45, 0.65, { title = "Sentinel Hill", silent = true })
hover()
check(M.tooltip[2] == L.POINTING_TO:format(WP.ShortName(wp)) .. " · " .. Geo.FormatDistance(Geo.GetVector(wp)), "active tooltip has waypoint name and distance")
ns.Set("useMetres", true)
hover()
check(M.tooltip[2] == L.POINTING_TO:format(WP.ShortName(wp)) .. " · " .. Geo.FormatDistance(Geo.GetVector(wp)), "active tooltip honours distance units")
ns.Set("useMetres", false)
M.player.noPosition = true
hover()
check(M.tooltip[2] == L.POINTING_TO:format(WP.ShortName(wp)), "unknown distance keeps waypoint name without empty separator")
M.player.noPosition = false
button:GetScript("OnLeave")(button)
check(not GameTooltip:IsShown(), "leaving minimap hides tooltip")

WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "RightButton")
check(menuOwner == UIParent and #M.lastMenu.items == #root.items, "compartment right-click uses UIParent before hover")
local compartment = CreateFrame("Button", nil, UIParent)
WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "RightButton", compartment)
check(menuOwner == compartment, "compartment right-click uses its supplied frame before any hover")
M.tooltip = {}
WaypointTracker_OnAddonCompartmentEnter("WaypointTracker", compartment)
check(tooltipOwner == compartment and #M.tooltip == 5 and M.tooltip[5] == L.MINIMAP_TOOLTIP_SHIFT, "compartment tooltip omits drag hint")
WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "RightButton")
check(menuOwner == compartment and #M.lastMenu.items == #root.items, "compartment right-click uses cached owner")
local nextCompartment = CreateFrame("Button", nil, UIParent)
WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "RightButton", nextCompartment)
check(menuOwner == nextCompartment, "supplied compartment frame replaces the cached hover owner")
WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "RightButton")
check(menuOwner == nextCompartment, "two-argument compartment click retains the latest supplied owner")
for i, item in ipairs(root.items) do
    check(M.lastMenu.items[i].kind == item.kind and M.lastMenu.items[i].text == item.text, "compartment menu matches item " .. i)
end
WaypointTracker_OnAddonCompartmentLeave()
check(not GameTooltip:IsShown(), "leaving compartment hides tooltip")
WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "LeftButton")
check(ns.Window.IsShown(), "compartment left-click opens window")
WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "LeftButton")
check(not ns.Window.IsShown(), "compartment left-click closes window")

M.player.combat = true
local shows, hides = M.uiPanelCalls.show, M.uiPanelCalls.hide
click("LeftButton")
check(ns.Window.IsShown(), "minimap opens window during combat")
click("LeftButton")
WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "LeftButton")
WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "LeftButton")
check(not ns.Window.IsShown() and M.uiPanelCalls.show == shows and M.uiPanelCalls.hide == hides and not M.actionBlocked, "combat entry points avoid protected panel calls")
M.player.combat = false

ns.Set("minimapButton", false)
check(not button:IsShown(), "minimapButton=false hides button")
WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "LeftButton")
check(ns.Window.IsShown(), "compartment works while minimap button hidden")
ns.Window.Hide()
ns.Set("minimapButton", true)
check(WaypointTrackerMinimapButton == button and button:IsShown(), "setting shows the same minimap button")
ns.Set("minimapAngle", 37)
ns.Set("minimapButton", true)
local _, relative, _, x, y = button:GetPoint()
local radius = Minimap:GetWidth() / 2 + 8
check(relative == Minimap and math.abs(x - math.cos(math.rad(37)) * radius) < 0.0001 and math.abs(y - math.sin(math.rad(37)) * radius) < 0.0001, "saved minimap angle controls button position")
button:GetScript("OnDragStart")(button)
check(button:GetScript("OnUpdate") and not GameTooltip:IsShown(), "drag starts tracking cursor and hides tooltip")
button:GetScript("OnUpdate")(button, 0.1)
check(ns.Get("minimapAngle") >= 0 and ns.Get("minimapAngle") < 360, "drag saves angle")
button:GetScript("OnDragStop")(button)
check(not button:GetScript("OnUpdate"), "drag stop removes cursor tracking")

-- The shared widget fallback performs the first action, which is Add here.
for _, unavailable in ipairs({ "absent", "missing method", "throwing method" }) do
    if unavailable == "absent" then
        MenuUtil = nil
    elseif unavailable == "missing method" then
        MenuUtil = {}
    else
        MenuUtil = { CreateContextMenu = function() error("unavailable") end }
    end
    WP.ClearAll(true)
    click("RightButton")
    check(WP.Count() == 1 and ns.Widgets.lastMenu and #ns.Widgets.lastMenu.items == 11, "minimap menu fallback: " .. unavailable)
    WP.ClearAll(true)
    WaypointTracker_OnAddonCompartmentClick("WaypointTracker", "RightButton")
    check(WP.Count() == 1, "compartment menu fallback: " .. unavailable)
end
MenuUtil = { CreateContextMenu = createMenu }
GameTooltip.SetOwner = setOwner
check(#M.errors == 0, "no reported Lua errors")
for _, err in ipairs(M.errors) do print(tostring(err):match("^[^\n]*")) end
print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
