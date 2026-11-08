-- Regression: Nearest mailbox / innkeeper / flight master / repair / bank /
-- auction house. 1.1.1 had six one-click buttons; 1.2.0 hid them in a
-- dropdown and players lost the feature. This drives the real entry points
-- (the visible Find buttons and the quick menu) against the shipped database,
-- for both factions, for all six services.
-- Run from repo root: lua5.1 tests/run_nearest.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. message) end
end

local faction = 'Alliance'
local unitFaction = UnitFactionGroup
UnitFactionGroup = function(unit)
    if unit == nil or unit == 'player' then return faction end
    return unitFaction(unit)
end

WaypointTrackerDB = nil
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN'); M.FireEvent('PLAYER_ENTERING_WORLD')
M.Tick(0.1)
local Find, Window, DB, WP, L = ns.Find, ns.Window, ns.DB, ns.WP, ns.L
M.player.wx, M.player.wy, M.player.inst = -9460, 62, 0 -- Goldshire
M.noDataAddon = false

local SERVICES = {
    { 'mailbox', 'SERVICE_MAILBOX' }, { 'innkeeper', 'SERVICE_INNKEEPER' }, { 'flight', 'SERVICE_FLIGHT' },
    { 'repair', 'SERVICE_REPAIR' }, { 'banker', 'SERVICE_BANKER' }, { 'auctioneer', 'SERVICE_AUCTIONEER' },
}
check(Find.SERVICES and #Find.SERVICES == 6, 'Find offers six Nearest services')

-- 1. The buttons are on screen in the Find tab, one per service, in a row.
Find.Show()
M.Tick(0.3)
local fw = Find.widgets
check(Window.IsShown() and Window.GetTab() == 'find', 'Find tab is open')
local right = 0
for i, s in ipairs(SERVICES) do
    local b = fw.nearest and fw.nearest[s[1]]
    check(b ~= nil, 'Nearest button exists: ' .. s[1])
    if b then
        check(b:IsShown() and b:IsVisible(), 'Nearest button is visible: ' .. s[1])
        check(b:GetText() == L[s[2]], 'Nearest button is labelled ' .. L[s[2]])
        check(fw.nearest[i] == b, 'Nearest buttons keep the 1.1.1 order: ' .. s[1])
        local w = b:GetWidth() or 0
        check(w >= 48, 'Nearest button is wide enough to read: ' .. s[1] .. ' (' .. w .. ')')
        right = right + w + 4
    end
end
local frameWidth = (fw.nearest[1] and fw.nearest[1]:GetParent():GetWidth()) or 0
check(frameWidth == 0 or right <= frameWidth, 'the six buttons fit in the Find tab (' .. right .. ' of ' .. frameWidth .. ')')

-- 2. Each button sets the arrow on the nearest entry of that service.
local function OfService(key, wp)
    for _, e in ipairs(DB.ServiceEntries(key)) do
        if wp.title and (wp.title == e.name or wp.title:find(e.name, 1, true)) then return true end
    end
end
local function RunAll(label)
    for _, s in ipairs(SERVICES) do
        WP.ClearAll(true)
        Window.SetStatus('')
        fw.nearest[s[1]]:Click()
        local wp = WP.GetActive()
        check(wp ~= nil, label .. ': Nearest ' .. s[1] .. ' sets the arrow')
        if wp then
            check(OfService(s[1], wp), label .. ': Nearest ' .. s[1] .. ' points at a ' .. s[1] .. ' (got ' .. tostring(wp.title) .. ')')
            check(Window.frame.status:GetText() == L.ADDED:format(WP.Describe(wp)), label .. ': Nearest ' .. s[1] .. ' reports the waypoint below the title')
        end
    end
end
RunAll('Alliance')

-- 3. Horde gets Horde services, never Alliance-only ones. (The mock models
-- only a few zones, so distances in Orgrimmar are not measured here; what
-- matters is that every list and every pick is open to the Horde.)
faction = 'Horde'
M.player.wx, M.player.wy, M.player.inst = 1630, -4373, 1 -- Orgrimmar
local function HordeAllowed(key, e)
    for _, row in ipairs(DB.services[key] or {}) do
        local same = row.entry == e
        if not same and type(row.id) == 'number' then
            same = (row.id < 0 and DB.objects[-row.id] == e) or (row.id >= 0 and DB.units[row.id] == e)
        end
        if same and (row.fac == '' or row.fac:find('H', 1, true)) then return true end
    end
    return false
end
for _, s in ipairs(SERVICES) do
    local list = DB.ServiceEntries(s[1])
    check(#list > 0, 'Horde has ' .. s[1] .. ' entries')
    local bad
    for _, e in ipairs(list) do if not HordeAllowed(s[1], e) then bad = e; break end end
    check(not bad, 'Horde ' .. s[1] .. ' list holds only Horde or neutral entries' .. (bad and (' (got ' .. tostring(bad.name) .. ')') or ''))
    WP.ClearAll(true)
    fw.nearest[s[1]]:Click()
    local wp = WP.GetActive()
    if wp then check(OfService(s[1], wp), 'Horde: Nearest ' .. s[1] .. ' points at a ' .. s[1]) end
end
faction = 'Alliance'
M.player.wx, M.player.wy, M.player.inst = -9460, 62, 0

-- 4. The quick menu (minimap right-click) has Nearest with all six.
Window.Hide()
ns.QuickMenu.Show(UIParent)
local root = M.lastMenu
local nearItem
for _, item in ipairs(root and root.items or {}) do
    if item.text == L.NEAREST_MENU then nearItem = item end
end
check(nearItem ~= nil, 'quick menu has Nearest...')
local children = nearItem and nearItem.items or {}
check(#children == 6, 'quick menu Nearest lists six services (got ' .. #children .. ')')
for i, s in ipairs(SERVICES) do
    local child = children[i]
    check(child and child.text == L[s[2]], 'quick menu Nearest item ' .. i .. ' is ' .. L[s[2]])
    if child then
        WP.ClearAll(true)
        child.fn()
        local wp = WP.GetActive()
        check(wp and OfService(s[1], wp), 'quick menu Nearest ' .. s[1] .. ' sets the arrow')
    end
end

-- 5. Where the menu cannot show submenus, the entry opens Find instead.
Window.Hide()
if nearItem and nearItem.fn then nearItem.fn() end
check(Window.IsShown() and Window.GetTab() == 'find', 'quick menu Nearest opens Find when used directly')

-- 6. Without the database the buttons explain instead of failing silently.
WP.ClearAll(true)
local load = DB.Load
DB.Load = function() return false, 'missing' end
fw.nearest.mailbox:Click()
DB.Load = load
check(WP.GetActive() == nil and Window.frame.status:GetText() == L.DB_BROKEN, 'missing database is explained below the title')

check(#M.errors == 0, 'Nearest has no reported Lua errors')
for _, e in ipairs(M.errors) do print(e) end
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and #M.errors == 0 and 0 or 1)
