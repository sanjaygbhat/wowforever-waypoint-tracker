-- The arrow at rest (no waypoint, both frames hidden): its update runs once
-- a second instead of every frame, at any frame rate, and at once when there
-- is something to show. Above 62 frames a second a frame is shorter than the
-- update's own 0.016 s step, which must not put the second's look off.
-- Run from the repository root: lua5.1 tests/run_arrow_rest.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")

local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end

local frame, text = ns.Arrow.frame, ns.Arrow.textFrame
local F = M.FrameMethods
-- every SetShown the arrow gives its frame
local calls = 0
rawset(frame, "SetShown", function(self, ...)
    calls = calls + 1
    return F.SetShown(self, ...)
end)

for _, fps in ipairs({ 144, 240, 60, 30 }) do
    local step, label = 1 / fps, fps .. " fps: "
    ns.WP.ClearAll(true)
    M.Tick(1.5, step)
    check(not frame:IsShown() and not text:IsShown(), label .. "no waypoint: the arrow and its text are hidden")

    -- at rest the update runs about once a second, not every frame
    calls = 0
    M.Tick(3, step)
    check(calls >= 2 and calls <= 4, label .. "at rest the update runs once a second (" .. calls .. " in 3 s)")

    -- shown by something else: hidden again within about a second
    frame:Show()
    text:Show()
    M.Tick(1.1, step)
    check(not frame:IsShown() and not text:IsShown(), label .. "shown from outside at rest, hidden again within a second")

    -- something to show ends the rest at once (the update's 0.016 s step)
    local wp = ns.WP.Add(37, 0.62, 0.55, { title = "Rest" })
    M.Tick(0.05, step)
    check(ns.WP.GetActive() == wp and frame:IsShown() and text:IsShown(), label .. "a waypoint shows the arrow at once")
    calls = 0
    M.Tick(1, step)
    -- (every frame up to 62 a second; above, every 0.016 s and a frame at most)
    check(calls >= math.min(fps - 1, 40), label .. "with a waypoint the update runs at the frame rate (" .. calls .. " in 1 s)")
    ns.WP.ClearAll(true)
    M.Tick(0.05, step)
    check(not frame:IsShown(), label .. "cleared: hidden at once")

    -- the preview (the window open on the Waypoints tab) is not rest
    ns.Arrow.SetPreview(true)
    M.Tick(0.05, step)
    check(frame:IsShown(), label .. "the preview shows the arrow at once")
    ns.Arrow.SetPreview(false)
    M.Tick(0.05, step)
    check(not frame:IsShown(), label .. "preview over: hidden at once")
end

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("Arrow at rest: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
