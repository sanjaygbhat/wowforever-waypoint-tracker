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
check(ns.defaults.routeSharing == false and ns.Get("routeSharing") == false, "route sharing beta defaults off before initialization")
local fresh = init({})
check(fresh.routeSharing == false and WaypointTrackerDB.version == 5, "fresh sparse profile starts with sharing off at version 5")
for _, settings in ipairs({ {}, { routeSharing = true }, { routeSharing = false } }) do
    local migrated = init(settings, 3)
    check(migrated.routeSharing == false, "1.2.0 account profile opts out, whether defaults were saved or omitted")
    ns.Set("routeSharing", true)
    -- Simulate another character loading the same account-wide settings.
    WaypointTrackerCharDB = { waypoints = {} }
    ns.eventFrame:RunScript("OnEvent", "ADDON_LOADED", "WaypointTracker")
    check(ns.Get("routeSharing") == true and ns.settings == WaypointTrackerDB.settings,
        "version 5 keeps a later opt-in across reloads and characters")
    check(WaypointTrackerCharDB.settings == nil, "character state has no separate sharing profile")
end
check(init({ routeSharing = true }, 4).routeSharing == true, "existing version 4 opt-in is preserved")
check(init({}, 4).routeSharing == false, "version 4 sparse profile still defaults off")
-- 1.3.0: Real routes is a standard feature, on by default. Version 4 saved
-- false both for the old default and for a choice, so 4 -> 5 turns it on
-- once for everyone; a later choice to turn it off is kept.
check(ns.defaults.realRoutes == true, "Real routes is on by default")
check(init({}).realRoutes == true, "fresh profile has Real routes on")
for _, version in ipairs({ 1, 2, 3, 4 }) do
    for _, saved in ipairs({ false, true }) do
        local migrated = init({ realRoutes = saved, travelNoticeShown = true, travelShare = false,
            routeSharing = false, treasureHunt = false }, version)
        check(migrated.realRoutes == true, ("version %d profile with realRoutes=%s turns Real routes on once"):format(version, tostring(saved)))
        check(migrated.travelNoticeShown == nil, "the opt-in notice flag is dropped by the migration")
        check(migrated.travelShare == false and migrated.routeSharing == false and migrated.treasureHunt == false,
            "the migration leaves the other betas and walked-path sharing alone")
        check(WaypointTrackerDB.version == 5, "migrated to settings version 5")
    end
end
-- Walked-path sharing only ever ran with Real routes on: it stays opt-in.
check(ns.defaults.travelShare == false and init({}).travelShare == false, "fresh profile does not share walked paths")
check(init({ realRoutes = true, travelShare = true }, 4).travelShare == true, "a Real routes user's walked-path sharing is kept")
check(init({ realRoutes = true, travelShare = false }, 4).travelShare == false, "a Real routes user's sharing opt-out is kept")
check(init({ realRoutes = false, travelShare = true }, 4).travelShare == false, "a player who never had Real routes on does not start sharing")
check(init({ realRoutes = true, travelShare = true }, 5).travelShare == true, "version 5 keeps a sharing opt-in")
init({ realRoutes = false }, 4)
ns.Set("realRoutes", false)
ns.eventFrame:RunScript("OnEvent", "ADDON_LOADED", "WaypointTracker")
check(ns.Get("realRoutes") == false, "turning Real routes off after the migration is kept across reloads")
check(init({ realRoutes = false }, 5).realRoutes == false, "a version 5 opt-out is not turned back on")
check(init({}, 5).realRoutes == true, "a version 5 sparse profile gets the default on")
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
    check(WaypointTrackerDB.version == 5, "settings version 5")
end

local st = init({ arrowAlpha = 1, fadeOnCourse = false, arrowLocked = true,
    arrowPos = { "CENTER", "CENTER", 0, 230 }, routeAsk = false, routeApply = "add", coordsLocked = true })
check(st.arrowAlpha == 0.8 and st.fadeOnCourse == true, "version 1 arrow look still migrates")
check(st.arrowPos == nil and st.arrowLocked == nil, "version 1 arrow position still resets")
check(st.coordsLocked == nil, "version 1 also retires the coordinates lock")
check(st.routeApply == "add" and WaypointTrackerDB.version == 5, "version 1 advances through all migrations")

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
check(st.routesHelpShown == false and st.welcomeShown == false and st.wayNoticeShown == false, "notice flags declared")
check(st.travelNoticeShown == nil and ns.defaults.travelNoticeShown == nil, "the Real routes opt-in notice flag is retired")

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
