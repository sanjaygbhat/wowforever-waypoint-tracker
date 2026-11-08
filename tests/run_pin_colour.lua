-- Regression: the active waypoint's pin colour is a setting (players asked
-- for one that stands out from quest ! and ? icons). It must reach the world
-- map pin and the minimap pin, update live, and fall back to gold.
-- Run from repo root: lua5.1 tests/run_pin_colour.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. message) end
end
local function same(r, g, b, want)
    return r and g and b and math.abs(r - want[1]) < 0.01 and math.abs(g - want[2]) < 0.01 and math.abs(b - want[3]) < 0.01
end

WaypointTrackerDB = nil
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN'); M.FireEvent('PLAYER_ENTERING_WORLD')
M.Tick(0.1)
local WP = ns.WP
local GOLD, BLUE = { 1, 0.82, 0 }, { 0.55, 0.8, 1 }
local palette = {}
for _, c in ipairs(ns.PIN_COLOURS) do palette[c.key] = c.rgb end

check(ns.Get('pinColour') == 'gold', 'default pin colour is gold')
check(#ns.PIN_COLOURS >= 6, 'several pin colours are offered')
for _, c in ipairs(ns.PIN_COLOURS) do
    check(type(ns.L[c.label]) == 'string' and ns.L[c.label] ~= '', 'pin colour ' .. c.key .. ' has a label')
    check(not same(c.rgb[1], c.rgb[2], c.rgb[3], BLUE), 'pin colour ' .. c.key .. ' differs from other waypoints\' blue')
end

-- Two waypoints near the player: the active one and another.
local px, py = 0.5, 0.5
local m = C_Map.GetBestMapForUnit('player')
local other = WP.Add(m, px + 0.002, py, { title = 'Other', setActive = false })
local active = WP.Add(m, px - 0.002, py, { title = 'Active', setActive = true })
check(WP.GetActive() == active, 'second waypoint is active')

local function WorldPins()
    local found = {}
    for _, pin in ipairs(WorldMapFrame.pins or {}) do
        if pin.template == 'WaypointTrackerMapPinTemplate' and pin.wp then found[pin.wp] = pin end
    end
    return found
end
local function MinimapActivePin()
    for _, f in ipairs(M.frames) do
        if f.icon and f.wp == active and f:GetParent() == Minimap and f:IsShown() then return f end
    end
end

OpenWorldMap(m)
M.Tick(0.2)
local pins = WorldPins()
check(pins[active] and pins[other], 'both waypoints have world map pins')
local sr, sg, sb
if pins[active] then sr, sg, sb = pins[active].Icon:GetVertexColor() end
check(same(sr, sg, sb, GOLD), 'active world pin starts gold')

for _, key in ipairs({ 'green', 'pink', 'white' }) do
    ns.Set('pinColour', key)
    M.Tick(0.2)
    pins = WorldPins()
    local r, g, b = pins[active].Icon:GetVertexColor()
    check(same(r, g, b, palette[key]), 'world map active pin turns ' .. key .. ' without reopening the map')
    local hr, hg, hb = pins[active].Highlight:GetVertexColor()
    check(same(hr, hg, hb, palette[key]), 'world map highlight follows ' .. key)
    local or_, og, ob = pins[other].Icon:GetVertexColor()
    check(same(or_, og, ob, BLUE), 'other waypoints stay blue with ' .. key)
    local mini = MinimapActivePin()
    local mr, mg, mb
    if mini then mr, mg, mb = mini.icon:GetVertexColor() end
    check(mini and same(mr, mg, mb, palette[key]), 'minimap active pin turns ' .. key)
end

ns.Set('pinColour', 'not-a-colour')
M.Tick(0.2)
local r, g, b = ns.PinColour()
check(same(r, g, b, GOLD), 'unknown saved colour falls back to gold')

check(#M.errors == 0, 'pin colour has no reported Lua errors')
for _, e in ipairs(M.errors) do print(e) end
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and #M.errors == 0 and 0 or 1)
