-- Slash dispatch and the Real routes binding, against the fake WoW API.
-- Run from the repository root: lua5.1 tests/run_slash.lua
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

WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local L, WP, W = ns.L, ns.WP, ns.Window

local function command(msg, handler)
    M.TypeSlash(handler or SlashCmdList.WAYPOINTTRACKER, msg)
    M.Tick(0.2)
end
local function Printed(text)
    for _, line in ipairs(M.printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
local function Spy(owner, key)
    local original, calls = owner[key], {}
    owner[key] = function(...)
        calls[#calls + 1] = { ... }
    end
    return calls, function() owner[key] = original end
end

ns.Set("chatMessages", false)
W.Hide()
command("")
check(WaypointTrackerFrame and WaypointTrackerFrame:IsShown(), "/wp opens the single window")
check(W.GetTab() == "waypoints", "/wp defaults to Waypoints")
command("")
check(not WaypointTrackerFrame:IsShown(), "/wp again closes the window")
command("show")
check(W.IsShown(), "show aliases the window toggle")
command("show")
check(not W.IsShown(), "show closes an open window")

local findCalls, restoreFind = Spy(ns.Find, "Show")
for _, msg in ipairs({ "find", "search", "find kobold", "search Kobold worker" }) do
    command(msg)
    local rest = msg:match("^%S+%s*(.*)$")
    check(findCalls[#findCalls][1] == rest, msg .. " forwards the search text, including empty text")
end
restoreFind()
command("find kobold")
check(W.IsShown() and W.GetTab() == "find", "find kobold opens the Find tab")
check(ns.Find.widgets.search:GetText() == "kobold", "find fills the search box")
W.Hide()
command("")
check(W.IsShown() and W.GetTab() == "find", "/wp remembers the last tab")
for _, msg in ipairs({ "routes", "route", "lists" }) do
    W.Show("waypoints")
    command(msg)
    check(W.IsShown() and W.GetTab() == "routes", msg .. " switches to Routes")
    command(msg)
    check(not W.IsShown(), msg .. " toggles Routes closed")
end

for _, msg in ipairs({ "settings", "options", "config", "  SeTTings  " }) do
    M.settingsOpened = nil
    command(msg)
    check(M.settingsOpened == ns.Options.categoryID, msg .. " opens Blizzard Settings")
end
M.printed = {}
M.settingsOpened = nil
M.player.combat = true
local panelShow, panelHide, blocked = M.uiPanelCalls.show, M.uiPanelCalls.hide, M.actionBlocked or 0
command("settings")
check(M.settingsOpened == nil and Printed(L.IN_COMBAT_NO_PANELS), "settings refuses combat with a direct reply")
W.Hide()
command("")
check(W.IsShown(), "/wp opens directly in combat")
command("")
check(not W.IsShown(), "/wp closes directly in combat")
local entered = M.editModeEntered
M.printed = {}
command("editmode")
check(M.editModeEntered == entered and Printed(L.IN_COMBAT_NO_PANELS), "editmode refuses combat with a direct reply")
check(M.uiPanelCalls.show == panelShow and M.uiPanelCalls.hide == panelHide and (M.actionBlocked or 0) == blocked,
    "combat commands never attempt protected panel calls")
M.player.combat = false
command("editmode")
check(M.editModeEntered == entered + 1, "editmode enters Blizzard Edit Mode")
EditModeManagerFrame:ExitEditMode()
local enter = ns.EditMode.Enter
ns.EditMode.Enter = function() return false, "unavailable" end
M.printed = {}
command("editmode")
check(Printed(L.EDIT_MODE_HINT), "editmode failure gives the existing hint")
ns.EditMode.Enter = enter

-- Help has a header and all 18 command lines, even with chat turned off.
local helpKeys = { "HELP_OPEN", "HELP_OPTIONS", "HELP_EDITMODE", "HELP_WAY", "HELP_WAY_SEARCH", "HELP_FIND", "HELP_HERE",
    "HELP_SHARE", "HELP_CLEAR", "HELP_LIST", "HELP_ARROW", "HELP_CLOSEST", "HELP_TREASURE", "HELP_TREASURE_STATUS",
    "HELP_ROUTES", "HELP_ROUTES_MORE", "HELP_TRAVEL", "HELP_HELP" }
for _, msg in ipairs({ "help", "?" }) do
    M.printed = {}
    command(msg)
    check(#M.printed == 19 and Printed(L.HELP_HEADER), msg .. " prints a header and 18 lines")
    for i, key in ipairs(helpKeys) do
        check(M.printed[i + 1] == "   " .. L[key], msg .. " includes " .. key .. " in order")
    end
end
local otherAddon = ns.IsOtherArrowAddonPresent
ns.IsOtherArrowAddonPresent = function() return true end
M.printed = {}
command("help")
check(M.printed[5] == "   " .. L.HELP_WAY:gsub("/way ", "/wp "), "help uses /wp when another addon owns /way")
ns.IsOtherArrowAddonPresent = otherAddon

wipe(ns.Travel.Know().flights)
ns.Set("realRoutes", false)
M.printed = {}
WaypointTracker_ToggleTravel()
check(ns.Get("realRoutes") and Printed(L.TRAVEL_NOW_ON) and Printed(L.TRAVEL_OPEN_FLIGHT_MAP), "travel binding enables routes and gives the flight-map hint")
local bindingReply = table.concat(M.printed, "\n")
WaypointTracker_ToggleTravel()
check(not ns.Get("realRoutes") and Printed(L.TRAVEL_NOW_OFF), "travel binding disables routes")
M.printed = {}
command("travel")
check(ns.Get("realRoutes") and table.concat(M.printed, "\n") == bindingReply, "travel command and binding share the same reply")
for _, alias in ipairs({ "travel", "realroutes", "rr" }) do
    command(alias .. " off")
    check(not ns.Get("realRoutes"), alias .. " off disables routes")
    command(alias .. " off")
    check(not ns.Get("realRoutes"), alias .. " off is idempotent")
    command(alias .. " on")
    check(ns.Get("realRoutes"), alias .. " on enables routes")
    command(alias .. " on")
    check(ns.Get("realRoutes"), alias .. " on is idempotent")
    command(alias)
    check(not ns.Get("realRoutes"), alias .. " without an argument toggles routes")
end
ns.Travel.Know().flights[1] = true
M.printed = {}
WaypointTracker_ToggleTravel()
check(Printed(L.TRAVEL_NOW_ON) and not Printed(L.TRAVEL_OPEN_FLIGHT_MAP), "known flights suppress the flight-map hint")
local describe = ns.Travel.Describe
ns.Travel.Describe = function() return { "Walk to Goldshire", "Fly to Westfall" } end
for _, sub in ipairs({ "steps", "route" }) do
    M.printed = {}
    command("travel " .. sub)
    check(#M.printed == 2 and Printed("1. Walk to Goldshire") and Printed("2. Fly to Westfall"), "travel " .. sub .. " lists numbered steps")
end
ns.Travel.Describe = function() return {} end
M.printed = {}
command("travel steps")
check(Printed(L.TRAVEL_NO_PLAN), "travel steps explains an empty plan")
command("travel off")
M.printed = {}
command("travel steps")
check(Printed(L.TRAVEL_OFF), "travel steps explains disabled routes")
ns.Travel.Describe = describe
M.printed = {}
command("travel status")
check(#M.printed == 1 and Printed(L.TRAVEL_STATUS:format(L.NO, 1, "-", ns.Trails.Stats())), "travel status reports route knowledge")

-- Port the bare-client slash loop with checks of each command's result.
WP.ClearAll(true)
command("here Home")
check(WP.Count() == 1 and WP.GetActive().title == "Home", "here adds a named waypoint")
for _, msg in ipairs({ "share", "share Here!", "share Westfall 40 50 Camp" }) do
    local count = WP.Count()
    command(msg)
    check(M.chatOpen and M.chatText and M.chatText:find("[Waypoint Tracker]", 1, true) and WP.Count() == count, msg .. " fills chat without adding a waypoint")
end
M.printed = {}
command("share 150 20")
check(M.chatOpen and M.chatText and M.chatText:find("150 20", 1, true), "share keeps non-coordinate text as the current location's name")
command("find")
check(W.IsShown() and W.GetTab() == "find", "find without text opens Find")
command("find hogger")
check(ns.Find.widgets.search:GetText() == "hogger", "find hogger fills the search")
local arrow = ns.Get("arrowShown")
command("arrow")
check(ns.Get("arrowShown") ~= arrow, "arrow toggles its setting")
command("arrow")
check(ns.Get("arrowShown") == arrow, "arrow toggles back")
command("closest")
check(WP.GetActive() ~= nil, "closest selects a waypoint")
M.printed = {}
command("list")
check(Printed(L.LIST_HEADER) and Printed("Home"), "list describes saved waypoints")
command("clear")
check(WP.Count() == 0, "clear removes the active waypoint")
command("here First")
command("here Second")
command("clear all")
check(WP.Count() == 0, "clear all removes every waypoint")
for _, alias in ipairs({ "reset", "remove" }) do
    command("here " .. alias)
    command(alias)
    check(WP.Count() == 0, alias .. " removes the active waypoint")
end
M.printed = {}
command("closest")
check(Printed(L.NO_WAYPOINT_ACTIVE), "closest explains an empty list")
M.printed = {}
command("list")
check(Printed(L.NO_WAYPOINTS), "list explains an empty list")

local way = SlashCmdList.WAYPOINTTRACKERWAY
check(type(way) == "function", "/way is claimed when available")
if way then
    for _, msg in ipairs({ "Westfall 40 50 Camp", "40 50", "tirisfl 60 50", "#52 10 10" }) do
        command(msg, way)
        local wp = WP.GetActive()
        check(wp and wp.x >= 0 and wp.x <= 1 and wp.y >= 0 and wp.y <= 1, "/way " .. msg .. " sets valid coordinates")
    end
    local calls, restore = Spy(ns.Find, "Way")
    for _, msg in ipairs({ "hogger", "abc 50" }) do
        command(msg, way)
        check(calls[#calls][1] == msg, "/way " .. msg .. " searches by name")
    end
    restore()
    M.printed = {}
    command("120 50", way)
    check(Printed(L.INVALID_COORDS), "/way rejects coordinates out of range")
    M.printed = {}
    command("", way)
    check(#M.printed == 19, "/way without arguments retains help")
end
command("#52 20 30 Direct")
check(WP.GetActive().m == 52 and WP.GetActive().title == "Direct", "/wp accepts coordinates directly")
command("Camp", SlashCmdList.WAYPOINTTRACKERWAYB)
check(WP.GetActive().title == "Camp", "/wayb adds a named waypoint here")
command("", SlashCmdList.WAYPOINTTRACKERCWAY)
check(WP.GetActive() ~= nil, "/cway selects the closest waypoint")
check(SLASH_WAYPOINTTRACKER1 == "/wp" and SLASH_WAYPOINTTRACKER2 == "/waypoint" and SLASH_WAYPOINTTRACKER3 == "/waypointtracker", "long slash aliases remain registered")

for _, alias in ipairs({ "treasure", "hunt", "treasures" }) do
    local before = ns.Get("treasureHunt")
    command(alias)
    check(ns.Get("treasureHunt") ~= before, alias .. " toggles treasure hunt")
    M.printed = {}
    command(alias .. " status")
    check(Printed(ns.Get("treasureHunt") and L.TREASURE_ON or L.TREASURE_OFF), alias .. " status reports without toggling")
end

-- Route core tests cover execution; here verify every retained subcommand.
for _, alias in ipairs({ "routes", "route", "lists" }) do
    for _, sub in ipairs({ "next", "skip", "stop", "test" }) do
        local owner = sub == "test" and ns.RoutesNet or ns.Routes
        local key = sub == "test" and "SelfTest" or (sub == "stop" and "Stop" or "Skip")
        local calls, restore = Spy(owner, key)
        command(alias .. " " .. sub)
        check(#calls == 1, alias .. " " .. sub .. " dispatches once")
        restore()
    end
    for _, sub in ipairs({ "record", "new", "create" }) do
        local recording, finish = ns.Routes.Recording, ns.Routes.RecordFinish
        local starts, restoreStart = Spy(ns.Routes, "RecordStart")
        ns.Routes.Recording = function() return nil end
        command(alias .. " " .. sub)
        check(#starts == 1, alias .. " " .. sub .. " starts recording")
        local draft = { name = "Recorded route" }
        ns.Routes.Recording = function() return true end
        ns.Routes.RecordFinish = function() return draft end
        local editors, restoreEditor = Spy(ns.RoutesUI, "ShowEditor")
        command(alias .. " " .. sub)
        check(#editors == 1 and editors[1][1] == draft, alias .. " " .. sub .. " finishes into the editor")
        restoreStart()
        restoreEditor()
        ns.Routes.Recording, ns.Routes.RecordFinish = recording, finish
    end
    local adds, restoreAdd = Spy(_G, "WaypointTracker_RouteRecordAdd")
    command(alias .. " add")
    check(#adds == 1, alias .. " add dispatches the record binding")
    restoreAdd()
    ns.Routes.feedbackAfter = 300
    command(alias .. " fast")
    check(ns.Routes.feedbackAfter == 20, alias .. " fast shortens feedback delay")
    command(alias .. " fast")
    check(ns.Routes.feedbackAfter == 300, alias .. " fast restores feedback delay")
    local status = ns.RoutesNet.Status
    local statusCalls = 0
    ns.RoutesNet.Status = function()
        statusCalls = statusCalls + 1
        return { sharing = false, guild = false, peers = 0, sent = 0, got = 0, routes = 0, votes = 0 }
    end
    M.printed = {}
    command(alias .. " status")
    check(statusCalls == 1 and #M.printed == 1, alias .. " status dispatches and prints")
    ns.RoutesNet.Status = status
end

local options, editMode, find, window = ns.Options, ns.EditMode, ns.Find, ns.Window
ns.Options, ns.EditMode, ns.Find, ns.Window = nil, nil, nil, nil
for _, msg in ipairs({ "", "show", "routes", "find", "settings", "editmode" }) do command(msg) end
ns.Options, ns.EditMode, ns.Find, ns.Window = options, editMode, find, window
check(#M.errors == 0, "no Lua errors, including missing sibling modules")
for _, err in ipairs(M.errors) do print("ERROR: " .. tostring(err)) end
print(("Slash tests: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
