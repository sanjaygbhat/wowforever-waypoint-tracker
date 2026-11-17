-- Minimap pins when there is nothing to do: no waypoints and no pin
-- showing, or the minimap hidden. The 20-a-second update is not run then
-- (it would leave at once); the pins stay as they are while the minimap is
-- hidden and are put right when it shows again.
-- Run from the repository root: lua5.1 tests/run_minimap_idle.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")

local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end

-- every run of the pins' update (it is called through ns.Call's xpcall)
local updates = 0
local protected = xpcall
function xpcall(fn, ...)
    if debug.getinfo(fn, "S").source:find("MinimapPins", 1, true) then updates = updates + 1 end
    return protected(fn, ...)
end
-- the pins showing (each holds its waypoint while it shows)
local function Pins()
    local shown = 0
    for _, f in ipairs(M.frames) do
        if f.icon and f.wp and f:GetParent() == Minimap and f:IsShown() then shown = shown + 1 end
    end
    return shown
end

M.Tick(1)
check(updates == 0, "no waypoints: the update is not run (" .. updates .. ")")

ns.WP.Add(37, 0.41, 0.31, { title = "Near" })
ns.WP.Add(37, 0.42, 0.32, { title = "Nearer" })
M.Tick(1)
check(updates >= 15, "waypoints: the update runs 20 times a second (" .. updates .. ")")
check(Pins() == 2, "two waypoints nearby: two pins")

Minimap:Hide()
updates = 0
M.Tick(2)
check(updates == 0, "minimap hidden: the update is not run (" .. updates .. ")")
check(Pins() == 2, "minimap hidden: the pins stay as they are")

-- all waypoints cleared while it is hidden: still nothing run, and the pins
-- go when the minimap shows again
ns.WP.ClearAll(true)
M.Tick(2)
check(updates == 0 and Pins() == 2, "cleared while hidden: nothing run, pins as they were")
Minimap:Show()
M.Tick(0.2)
check(Pins() == 0, "minimap shown again: the pins of cleared waypoints are hidden")
updates = 0
M.Tick(2)
check(updates == 0, "and the update rests again (" .. updates .. ")")

ns.WP.Add(37, 0.41, 0.31, { title = "Back" })
M.Tick(0.2)
check(Pins() == 1, "a new waypoint: its pin shows")

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("Minimap idle: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
