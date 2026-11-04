-- Live Forever API regressions. Run: lua5.1 tests/run_forever_api.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local passed, failed = 0, 0
local function check(ok, label)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end
WOW_PROJECT_CAMELOT, WOW_PROJECT_ID = 18, 18
GetBuildInfo = function() return "1.60.1", "70755", "Nov 3 2026", 16001 end
WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
check(ns.Travel and ns.Learn and ns.EditMode and #M.errors == 0, "Forever project 18 loads all runtime modules")

-- Blizzard_PTRFeedback_Tooltips.lua on forever extracts field six without
-- converting the other GUID fields. Full GUIDs remain session-local identities:
-- https://github.com/Gethe/wow-ui-source/blob/17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c/Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Tooltips.lua#L124
for _, kind in ipairs({ "Creature", "Vehicle", "GameObject" }) do
    for _, fields in ipairs({ "0-1-2-3", "0-opaque-0-0", "0-ABCD-hex-zone", "0-0-0-0", "---" }) do
        local guid = kind .. "-" .. fields .. "-471-obfuscated"
        local k, id = ns.Learn.ParseGUID(guid)
        check(k == (kind == "GameObject" and "object" or "npc") and id == 471, "entry survives opaque fields: " .. guid)
    end
end
for _, guid in ipairs({ false, 42, {}, "", "Player-0-471", "Pet-0-x-0-0-471-y", "Creature-0-x-0-0-nope-y",
    "Creature-0-x-0-0-0-y", "Creature-0-x-0-0-471", "Creature-0-x-0-0-471-y-extra", "Creature-0-x-0-0-999999999999999999999-y" }) do
    local ok, kind = pcall(ns.Learn.ParseGUID, guid)
    check(ok and kind == nil, "invalid GUID is safely ignored: " .. tostring(guid))
end
check(ns.Learn.ParseGUID(nil) == nil, "nil GUID is ignored")
local secret, wasSecret = {}, issecretvalue
issecretvalue = function(v) return rawequal(v, secret) or wasSecret(v) end
check(ns.Learn.ParseGUID(secret) == nil, "restricted GUID is ignored before parsing")
issecretvalue = wasSecret

-- Treasure deduplicates by the whole opaque GUID within this session. It
-- neither interprets server/spawn fields nor persists them as entity identity.
ns.Set("treasureHunt", true)
local chest = "GameObject-0-opaque-0-0-2843-spawnToken"
M.units.softinteract = { guid = chest, name = "Battered Chest" }
ns.Treasure.CheckInFront()
local target = ns.Treasure.Targets()[chest]
check(target and target.kind == "chest", "treasure recognizes an object with opaque GUID fields")
ns.Treasure.CheckInFront()
check(ns.Treasure.Targets()[chest] == target, "opaque GUID repeats reuse the same treasure target")
M.units.softinteract = nil
ns.Set("treasureHunt", false)

-- Old name-only positions seed both styles independently and remain intact.
local edit = ns.EditMode
local legacy = { "CENTER", "CENTER", 101, -27 }
ns.Set("arrowLayouts", { Shared = legacy })
local style = 0
local oldInfo = EditModeManagerFrame.GetActiveLayoutInfo
EditModeManagerFrame.GetActiveLayoutInfo = function() return { layoutName = "Shared", interfaceStyle = style } end
local function Switch()
    M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    M.Tick(0.1)
end
Switch()
local mkbKey = edit.layout
local mkb = edit.SavedPosition("arrow")
check(mkbKey ~= "Shared" and mkb[3] == 101 and mkb ~= legacy, "style zero migrates the old position by copy")
edit.SavePosition("arrow", { "CENTER", "CENTER", 202, -28 })
style = 1
Switch()
local gamepadKey = edit.layout
check(gamepadKey ~= mkbKey and edit.SavedPosition("arrow")[3] == 101, "second style starts from the preserved legacy position")
edit.SavePosition("arrow", { "CENTER", "CENTER", 303, -29 })
style = 0
Switch()
check(edit.layout == mkbKey and edit.SavedPosition("arrow")[3] == 202, "style switches restore independent positions")
edit.SavePosition("arrow", nil)
check(edit.SavedPosition("arrow") == nil and ns.Get("arrowLayouts")[mkbKey] == false,
    "reset marks the styled position cleared instead of reimporting legacy data")
style = 1
Switch()
check(edit.SavedPosition("arrow")[3] == 303, "reset leaves the other style's position intact")
style = 0
Switch()
check(edit.SavedPosition("arrow") == nil, "reset survives switching away and back")
style = nil
Switch()
check(edit.layout == "Shared" and edit.SavedPosition("arrow")[3] == 101, "missing interfaceStyle retains name-only behavior")
check(ns.Get("arrowLayouts")[gamepadKey][3] == 303 and legacy[3] == 101, "migration preserves all saved styles and legacy data")
EditModeManagerFrame.GetActiveLayoutInfo = oldInfo

-- Isolate each networking scenario with a fresh module and mock OnUpdate.
local function Network(results, send)
    Enum.SendAddonMessageResult = results
    C_ChatInfo = { SendAddonMessage = send }
    M.group = { guild = true, party = false, raid = false }
    GetChannelName = function() return 0 end
    local notices = {}
    local netNS = { L = ns.L, Get = function() return true end,
        On = function() end, RegisterEvent = function() end,
        Print = function(text) notices[#notices + 1] = text end }
    assert(loadfile("WaypointTracker/RoutesNet.lua"))("WaypointTracker", netNS)
    local pump = M.frames[#M.frames]
    local function Tick(seconds)
        M.now = M.now + seconds
        pump:RunScript("OnUpdate", seconds)
    end
    return netNS.RoutesNet, Tick, notices
end
local named = { Success = 100, AddonMessageThrottle = 103, ChannelThrottle = 108, AddOnMessageLockdown = 111 }
for _, code in ipairs({ 103, 108, 111 }) do
    local calls, messages, blocked = 0, {}, true
    local net, tick, notices = Network(named, function(_, msg)
        calls = calls + 1; messages[calls] = msg
        return blocked and code or named.Success
    end)
    net.Share("first"); net.Share("second")
    tick(0.1)
    check(calls == 1 and net.Status().queued == 2 and net.Status().sent == 0, "transient result pauses the whole queue: " .. code)
    tick(1)
    check(calls == 1, "queue does not send during backoff: " .. code)
    blocked = false
    tick(5)
    check(calls == 3 and net.Status().queued == 0 and net.Status().sent == 2, "queue resumes after transient restriction: " .. code)
    check(messages[1] == "first" and messages[2] == "first" and messages[3] == "second", "retry preserves message order: " .. code)
    check(#notices == 0, "temporary restriction stays quiet: " .. code)
end
for _, code in ipairs({ 3, 8, 11 }) do
    local calls = 0
    local net, tick, notices = Network(nil, function() calls = calls + 1; return code end)
    net.Share("first"); net.Share("second")
    for _ = 1, 20 do tick(5.1) end
    check(calls == 6 and net.Status().queued == 0, "numeric fallback retries are bounded for the whole batch: " .. code)
    check(#notices == 1 and notices[1] == ns.L.ROUTE_SEND_FAILED, "persistent restriction surfaces once: " .. code)
    net.Share("later")
    for _ = 1, 10 do tick(5.1) end
    check(#notices == 1, "repeated persistent failures do not spam chat: " .. code)
end
for _, code in ipairs({ 1, 2, 4, 5, 6, 7, 9, 10, 12, false, "unknown" }) do
    local calls = 0
    local net, tick, notices = Network(nil, function() calls = calls + 1; return code end)
    net.Share("bad"); net.Share("bad2")
    tick(1)
    check(calls == 2 and net.Status().queued == 0 and net.Status().sent == 0 and #notices == 1,
        "permanent failure is dropped and reported once: " .. tostring(code))
end
for _, result in ipairs({ "nil", true, 0 }) do
    local net, tick, notices = Network(nil, function() if result ~= "nil" then return result end end)
    net.Share("ok"); tick(1)
    check(net.Status().sent == 1 and #notices == 0, "legacy success result is accepted: " .. tostring(result))
end
local net, tick, notices = Network(nil, function() error("blocked send") end)
net.Share("bad"); tick(1)
check(net.Status().queued == 0 and #notices == 1, "throwing send fails safely and surfaces once")
net, tick, notices = Network(nil, nil)
net.Share("bad"); tick(1)
check(net.Status().queued == 0 and #notices == 1, "missing send API fails safely and surfaces once")
check(#M.errors == 0, "Forever regression suite reports no runtime errors")
print(("Forever API: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
