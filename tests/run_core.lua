-- Settings migrations and shared helpers, against the fake WoW API.
-- Run from the repository root: lua5.1 tests/run_core.lua
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

local ns = {}
assert(loadfile("WaypointTracker/Locales/enUS.lua"))("WaypointTracker", ns)
assert(loadfile("WaypointTracker/Core.lua"))("WaypointTracker", ns)

local function init(settings, version)
    WaypointTrackerDB = { version = version, settings = settings }
    WaypointTrackerCharDB = nil
    ns.eventFrame:RunScript("OnEvent", "ADDON_LOADED", "WaypointTracker")
    return ns.settings
end

check(ns.defaults.routeApply == "ask", "routes ask by default")
check(ns.defaults.routeAsk == nil and ns.defaults.showAdvanced == nil and ns.defaults.windowPos == nil and ns.defaults.coordsLocked == nil, "retired defaults are gone")

for _, case in ipairs({
    { settings = { routeAsk = false, routeApply = "add" }, want = "add" },
    { settings = { routeAsk = false, routeApply = "replace" }, want = "replace" },
    { settings = { routeAsk = false, routeApply = "invalid" }, want = "replace" },
    { settings = { routeAsk = false }, want = "replace" },
    { settings = { routeAsk = true, routeApply = "add" }, want = "ask" },
    { settings = { routeAsk = true }, want = "ask" },
    { settings = { routeApply = "add" }, want = "ask" },
    { settings = {}, want = "ask" },
}) do
    case.settings.showAdvanced = true
    case.settings.windowPos = { "CENTER", "CENTER", 10, 20 }
    case.settings.coordsLocked = false
    local st = init(case.settings, 2)
    check(st.routeApply == case.want, "old route choice becomes " .. case.want)
    check(st.routeAsk == nil and st.showAdvanced == nil and st.windowPos == nil and st.coordsLocked == nil, "retired settings deleted")
    check(WaypointTrackerDB.version == 3, "settings version 3")
end

local st = init({ arrowAlpha = 1, fadeOnCourse = false, arrowLocked = true,
    arrowPos = { "CENTER", "CENTER", 0, 230 }, routeAsk = false, routeApply = "add", coordsLocked = true })
check(st.arrowAlpha == 0.8 and st.fadeOnCourse == true, "version 1 arrow look still migrates")
check(st.arrowPos == nil and st.arrowLocked == nil, "version 1 arrow position still resets")
check(st.coordsLocked == nil, "version 1 also retires the coordinates lock")
check(st.routeApply == "add" and WaypointTrackerDB.version == 3, "version 1 advances through both migrations")

for _, choice in ipairs({ "ask", "replace", "add" }) do
    st = init({ routeApply = choice }, 3)
    check(st.routeApply == choice, "version 3 preserves route choice " .. choice)
    ns.eventFrame:RunScript("OnEvent", "ADDON_LOADED", "WaypointTracker")
    check(ns.settings.routeApply == choice, "reloading preserves route choice " .. choice)
end

local firstTips = init({}).tipsShown
firstTips.add = true
st = init({ tipsShown = false, singleColor = "broken", uiLastTab = false }, 2)
check(type(st.tipsShown) == "table" and next(st.tipsShown) == nil, "damaged tips table repaired")
check(st.tipsShown ~= firstTips and next(ns.defaults.tipsShown) == nil, "tips defaults copied independently")
check(type(st.singleColor) == "table" and st.singleColor.r == 1, "existing table type repair retained")
check(st.uiLastTab == "waypoints", "damaged tab setting repaired")
check(st.routesHelpShown == false and st.travelNoticeShown == false and st.welcomeShown == false and st.wayNoticeShown == false, "notice flags declared")

st = init({ arrowShown = false, routeApply = "add", uiLastTab = "routes", minimapAngle = 123,
    tipsShown = { add = true }, routesHelpShown = true, welcomeShown = true,
    arrowPos = { "CENTER", "CENTER", 12, 34 }, textPos = { "TOP", "TOP", 5, -20 },
    coordsPos = { "TOP", "TOP", 20, -30 }, recorderPos = { "TOP", "TOP", 0, -160 },
    arrowLayouts = { Modern = { "TOP", "TOP", 0, -50 } },
    textLayouts = { Modern = { "TOP", "TOP", 0, -60 } },
    coordsLayouts = { Modern = { "TOP", "TOP", 0, -70 } },
    recorderLayouts = { Modern = { "TOP", "TOP", 0, -80 } },
}, 3)
st.windowPos = { "CENTER", "CENTER", 99, 99 }
WaypointTrackerCharDB.waypoints = { { title = "Kept" } }
WaypointTrackerDB.routes = { example = { name = "Kept route" } }
local changes, changedKey, changedValue = 0
ns.On("SETTING_CHANGED", function(key, value)
    changes, changedKey, changedValue = changes + 1, key, value
end)
ns.ResetSettings()
check(ns.settings == WaypointTrackerDB.settings and ns.settings ~= st, "reset replaces saved settings")
check(ns.Get("arrowShown") == true and ns.Get("routeApply") == "ask", "reset restores settings defaults")
for _, key in ipairs({ "uiLastTab", "minimapAngle", "tipsShown", "arrowPos", "textPos", "coordsPos", "recorderPos",
    "arrowLayouts", "textLayouts", "coordsLayouts", "recorderLayouts" }) do
    check(ns.settings[key] == st[key], "reset keeps " .. key)
end
check(ns.settings.windowPos == nil, "reset drops old window position")
check(ns.settings.routesHelpShown == false and ns.settings.welcomeShown == false, "reset restores notice flags")
check(WaypointTrackerCharDB.waypoints[1].title == "Kept" and WaypointTrackerDB.routes.example.name == "Kept route", "reset keeps waypoints and routes")
check(changes == 1 and changedKey == nil and changedValue == nil, "reset notifies all settings once")

M.player.combat = false
check(ns.InCombat() == false, "combat helper is false out of combat")
M.player.combat = true
check(ns.InCombat() == true, "combat helper detects combat")
M.player.combat = false
local combat = InCombatLockdown
InCombatLockdown = nil
check(ns.InCombat() == false, "combat helper handles missing API")
InCombatLockdown = combat
check(BINDING_NAME_WAYPOINTTRACKER_TRAVEL == ns.L.BINDING_TRAVEL, "travel binding label declared")

check(#M.errors == 0, "no reported Lua errors")
print(("%d passed, %d failed"):format(passed, failed))
os.exit((failed == 0 and #M.errors == 0) and 0 or 1)
