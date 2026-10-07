-- Plays through the addon on a client that lacks the optional parts of the
-- game's API, and hands back positions as plain { x, y } tables. Features may
-- switch themselves off, but nothing may throw a Lua error. Run from the
-- repository root:
--     WT_PLAIN_VECTORS=1 lua5.1 tests/run_bare.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

-- everything the addon only uses when it's there
for _, name in ipairs({
    "C_SuperTrack", "C_DeathInfo", "C_AreaPoiInfo", "C_VignetteInfo", "C_EncounterJournal", "C_TaxiMap",
    "C_Secrets", "C_Item", "C_Minimap", "MenuUtil", "ChatFrameUtil", "ChatEdit_InsertLink", "ChatFrame_OpenChat",
    "EventRegistry", "EventUtil", "EditModeManagerFrame", "TooltipDataProcessor", "Settings", "SettingsPanel",
    "ColorPickerFrame", "UiMapPoint", "UnitIsGhost", "UnitIsDeadOrGhost", "issecretvalue", "GetMinimapShape",
    "GetItemClassInfo", "GetItemSubClassInfo", "GetLootSourceInfo", "CanMerchantRepair", "WorldMapFrame",
    "MapCanvasDataProviderMixin", "MapCanvasMixin", "MapCanvasPinMixin", "C_ChatInfo", "JoinTemporaryChannel",
    "LeaveChannelByName", "GetChannelName", "ChatFrame_RemoveChannel", "GetNormalizedRealmName", "IsInGuild", "IsInGroup",
    "IsInRaid",
}) do
    _G[name] = nil
end
for _, name in ipairs({
    "SetUserWaypoint", "GetUserWaypointHyperlink", "CanSetUserWaypointOnMap", "HasUserWaypoint", "GetUserWaypoint",
    "ClearUserWaypoint", "GetMapLinkInfo",
}) do
    C_Map[name] = nil
end
for _, name in ipairs({ "GetNextWaypoint", "GetQuestsOnMap", "GetTitleForQuestID", "GetInfo", "IsComplete", "ReadyForTurnIn" }) do
    C_QuestLog[name] = nil
end

-- newer events an older client may not have
for _, event in ipairs({
    "EDIT_MODE_LAYOUTS_UPDATED", "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "QUEST_TURNED_IN",
    "QUEST_ACCEPTED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "QUEST_DATA_LOAD_RESULT",
}) do
    M.unknownEvents[event] = true
end

local problems = {}
local function step(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        problems[#problems + 1] = name .. ": " .. tostring(err)
    end
end

local ns
step("load", function()
    ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
end)
-- what comes after an unknown event in the same file still loads
for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "QUEST_LOG_UPDATE", "PLAYER_LOGOUT" }) do
    if not M.eventFrames[event] then
        problems[#problems + 1] = "load: " .. event .. " not registered after an unknown event"
    end
end
step("login", function()
    M.FireEvent("ADDON_LOADED", "WaypointTracker")
    M.FireEvent("PLAYER_LOGIN")
    M.FireEvent("PLAYER_ENTERING_WORLD")
    M.Tick(1)
end)

local slash = SlashCmdList.WAYPOINTTRACKER
for _, msg in ipairs({
    "", "", "help", "list", "here Home", "share", "share Here!", "share Westfall 40 50 Camp", "share 150 20",
    "find", "find hogger", "arrow", "arrow", "closest", "list", "clear", "clear all",
}) do
    step("/wp " .. msg, function()
        slash(msg)
        M.Tick(0.2)
    end)
end
local way = SlashCmdList.WAYPOINTTRACKERWAY
if way then
    for _, msg in ipairs({ "Westfall 40 50 Camp", "40 50", "tirisfl 60 50", "#52 10 10", "hogger", "abc 50", "120 50" }) do
        step("/way " .. msg, function()
            way(msg)
            M.Tick(0.2)
        end)
    end
end

-- walk around with waypoints set, then arrive
step("walking", function()
    ns.WP.AddHere("Here")
    ns.WP.Add(52, 0.5, 0.5, { title = "Far" })
    for _ = 1, 20 do
        M.player.wx = M.player.wx + 30
        M.player.facing = (M.player.facing + 0.3) % 6.28
        M.Tick(0.25)
    end
end)

-- every option on and off again
step("options", function()
    local keys = {}
    for key, value in pairs(ns.defaults) do
        if type(value) == "boolean" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local before = ns.Get(key)
        ns.Set(key, not before)
        M.Tick(0.6)
        ns.Set(key, before)
        M.Tick(0.1)
    end
end)

-- the game's events the addon listens to
for _, event in ipairs({
    "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "TAXIMAP_OPENED", "LOOT_OPENED", "MERCHANT_SHOW", "GOSSIP_SHOW", "QUEST_DETAIL",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_LOGOUT",
}) do
    step(event, function()
        M.FireEvent(event)
        M.Tick(0.7)
    end)
end

-- the window, Find, sharing and the arrow's own controls
step("window", function()
    WaypointTracker_ToggleWindow()
    WaypointTracker_ToggleWindow()
end)
step("find", function()
    ns.Find.Show()
    ns.Find.Show("quests")
    M.Tick(0.5)
end)
-- routes: make one, follow it, vote, share, the window
step("routes", function()
    for _, msg in ipairs({ "routes", "routes", "routes status", "routes test", "routes next", "routes stop", "routes fast" }) do
        slash(msg)
        M.Tick(0.5)
    end
    local R = ns.Routes
    local draft = R.Parse("/way 40 50 a\n/way 41 51 b")
    local r = draft and R.SaveMine(draft)
    if r then
        R.Start(r.id)
        M.Tick(1)
        R.Skip()
        R.Stop()
    end
    for _, s in ipairs(R.Suggested(C_Map.GetBestMapForUnit("player"))) do
        R.Vote(s.id, 1)
        break
    end
    ns.RoutesUI.Show()
    M.Tick(3)
    M.FireEvent("CHAT_MSG_ADDON", "WPTR", "A^abcdefgh12^1^X-Y^mining^2^Test", "CHANNEL", "X-Y")
    M.Tick(16)
    ns.RoutesUI.Toggle()
end)
step("share menu", function()
    local wp = ns.WP.Add(52, 0.3, 0.3, { title = "Share me" })
    ns.Share.ShowMenu(UIParent, wp)
    ns.Share.ToChatBox(wp)
    WaypointTracker_ShareHere()
end)
step("arrow", function()
    ns.Arrow.Reset()
    ns.Set("textSeparate", true)
    ns.Arrow.SetMoving(true)
    ns.Arrow.SetMoving(false)
    ns.Set("textSeparate", false)
end)
step("key bindings", function()
    WaypointTracker_ToggleArrow()
    WaypointTracker_ToggleArrow()
    WaypointTracker_SetClosest()
    WaypointTracker_AddHere()
    WaypointTracker_ClearActive()
    WaypointTracker_ToggleFind()
end)
step("reload", function()
    M.FireEvent("PLAYER_LOGOUT")
end)

for _, err in ipairs(M.errors) do
    problems[#problems + 1] = "reported: " .. tostring(err):match("^[^\n]*")
end
if #problems > 0 then
    print("Lua errors on a client without the optional API:")
    for _, p in ipairs(problems) do
        print("  " .. p)
    end
    os.exit(1)
end
print("No Lua errors on a client without the optional API.")
