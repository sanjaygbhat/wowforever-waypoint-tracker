-- Owner report: "a random player name comes and it says it's not found in
-- chat". A WHISPER addon message to a player the server can't reach makes the
-- game print ERR_CHAT_PLAYER_NOT_FOUND_S ("No player named 'X' is currently
-- playing."). Route sharing used to whisper a request to anyone who advertised
-- a route on the shared channel, and kept whispering route pieces after the
-- server said the player was gone. This checks that it doesn't any more,
-- that the addon hides only the lines its own whispers caused, and that
-- sharing off sends nothing at all.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end

local sent, joined = {}, 0
local offline = {} -- whisper targets SendAddonMessage reports as TargetOffline
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(prefix, msg, chat, target)
        sent[#sent + 1] = { prefix = prefix, msg = msg, chat = chat, target = target }
        if chat == "WHISPER" and offline[target] then return 12 end
        return 0
    end,
}
local channel = 0
GetChannelName = function() return channel end
JoinTemporaryChannel = function() joined = joined + 1; channel = 7 end
LeaveChannelByName = function() channel = 0 end
M.group = { guild = true, party = false, raid = false }
WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local R, Net = ns.Routes, ns.RoutesNet

local function receive(msg, chat, sender)
    M.FireEvent("CHAT_MSG_ADDON", "WPTR", msg, chat, sender)
end
local function whispersTo(name, from)
    local n = 0
    for i = (from or 1), #sent do
        if sent[i].chat == "WHISPER" and sent[i].target == name then n = n + 1 end
    end
    return n
end
local function notFound(name)
    return M.SystemMessage(ERR_CHAT_PLAYER_NOT_FOUND_S:format(name))
end

-- A route long enough to need several whispered pieces.
local pts = {}
for i = 1, 60 do pts[i] = { m = 37, x = 0.2 + i * 0.01, y = 0.2 + i * 0.01, t = "A stop with a fairly long name, number " .. i } end
local mine = R.SaveMine({ name = "Long public route", public = true, pts = pts })
check(mine and #R.Serialize(mine) > 2000, "test route needs more pieces than one burst")
local advert = "A^rstrange1^1^Stranger-TestRealm^other^2^Stranger's route"

-- 1. Sharing off (the default): nothing is sent, no channel, no filter.
M.Tick(20, 1)
check(not ns.Get("routeSharing") and not ns.Get("travelShare"), "sharing features are off by default")
receive(advert, "CHANNEL", "Stranger-TestRealm")
receive("A^rguild001^1^Guildie-TestRealm^other^2^Guild route", "GUILD", "Guildie-TestRealm")
receive("Q^" .. mine.id .. "^1", "WHISPER", "Guildie-TestRealm")
M.Tick(30, 1)
check(#sent == 0 and joined == 0, "sharing off: zero addon messages and no channel join")
check(#(M.chatFilters.CHAT_MSG_SYSTEM or {}) == 0, "sharing off: no chat filter installed")
check(notFound("Stranger-TestRealm"), "sharing off: a 'not found' line (the player's own whisper) is shown")

-- 2. Sharing on: a stranger's advert on the shared channel is not answered
-- by whisper (this is the reported bug: the old code whispered "Q" back).
ns.Set("routeSharing", true)
M.Tick(5, 1)
check(joined == 1 and #sent > 0, "opting in joins the channel and greets")
local mark = #sent
receive(advert, "CHANNEL", "Stranger-TestRealm")
M.Tick(30, 1)
check(whispersTo("Stranger-TestRealm", mark + 1) == 0, "a channel advert from a stranger never makes the addon whisper them")
for _, s in ipairs(sent) do
    check(s.chat ~= "WHISPER" or s.target ~= "Stranger-TestRealm", "no whisper of any kind to the stranger")
end

-- 3. A guild member's advert is answered (they reached us directly a moment ago).
mark = #sent
receive("A^rguild001^1^Guildie-TestRealm^other^2^Guild route", "GUILD", "Guildie-TestRealm")
M.Tick(3, 1)
check(whispersTo("Guildie-TestRealm", mark + 1) == 1 and sent[#sent].msg == "Q^rguild001^1",
    "a guild member's advert is requested by whisper")

-- 4. A requester logs out while the route's pieces go out: the server's
-- "not found" stops the rest, and that line (ours) is hidden.
mark = #sent
receive("Q^" .. mine.id .. "^1", "WHISPER", "Leaver-TestRealm")
M.Tick(1.1, 1.1)
local first = whispersTo("Leaver-TestRealm", mark + 1)
check(first >= 1 and Net.Status().queued > 0, "route pieces start going to the requester")
check(not notFound("Leaver-TestRealm"), "the 'not found' line our whisper caused is hidden in every chat window")
check(Net.Status().queued == 0, "pending pieces to the gone player are dropped")
M.Tick(30, 1)
check(whispersTo("Leaver-TestRealm", mark + 1) == first, "no more whispers to a player the server reported gone")
receive("Q^" .. mine.id .. "^1", "WHISPER", "Leaver-TestRealm")
M.Tick(30, 1)
check(whispersTo("Leaver-TestRealm", mark + 1) == first, "a gone player is left alone for a while")

-- 5. The player's own whispers: their "not found" lines always show.
check(notFound("Typed-TestRealm"), "a 'not found' for a name the addon never whispered is shown")
check(notFound("Typed"), "short names the addon never whispered are shown too")
-- More "not found" lines than addon whispers: the extra one is the player's.
mark = #sent
receive("A^rtwice001^1^Twice-TestRealm^other^2^Twice's route", "GUILD", "Twice-TestRealm")
M.Tick(1.1, 1.1)
check(whispersTo("Twice-TestRealm", mark + 1) == 1, "one request went out before the server answered")
check(not notFound("Twice"), "realm-less 'not found' for our whisper is hidden")
check(notFound("Twice"), "a second 'not found' (the player's own whisper) is shown")
check(#(M.chatFilters.CHAT_MSG_SYSTEM or {}) == 1, "one chat filter, installed once")

-- 6. Delay: a request that waits too long in the queue is not sent to someone
-- not heard from since.
mark = #sent
receive("Q^" .. mine.id .. "^1", "WHISPER", "Late-TestRealm")
M.now = M.now + 300
M.Tick(30, 1)
check(whispersTo("Late-TestRealm", mark + 1) == 0, "stale whispers are dropped, not sent")

-- 7. The game says the target is offline: stop at once, print no retries.
mark = #sent
offline["Offline-TestRealm"] = true
check(Net.SendTo(mine.id, "Offline-TestRealm") > 1, "a direct send to a chosen player is queued")
M.Tick(30, 1)
check(whispersTo("Offline-TestRealm", mark + 1) == 1 and Net.Status().queued == 0,
    "TargetOffline stops the remaining pieces after one attempt")

-- 8. The player's own choice of target still works, and a later choice
-- retries a name the server once reported gone.
mark = #sent
check(Net.SendTo(mine.id, "Leaver-TestRealm") > 1, "the player can send to a name again")
M.Tick(60, 1)
check(whispersTo("Leaver-TestRealm", mark + 1) > 1, "an explicit send goes out in full")

-- 8b. "Send to my target" refuses targets the server can't whisper.
local targetOnline = true
M.units.target = { name = "Peer", faction = "Horde" }
UnitExists = function(unit) return unit == "target" or unit == "player" end
UnitIsPlayer = function() return true end
UnitIsConnected = function(unit) return unit ~= "target" or targetOnline end
GetUnitName = function(unit) return unit == "target" and "Peer-OtherRealm" or "Me" end
local function sendToTarget()
    M.lastMenu = nil
    ns.RoutesUI.ShowShare(R.Get(mine.id))
    for _, item in ipairs(M.lastMenu and M.lastMenu.items or {}) do
        if item.text == ns.L.ROUTE_SEND_TARGET then item.fn(); return true end
    end
end
mark = #sent
check(sendToTarget(), "the route share menu offers Send to my target")
M.Tick(30, 1)
check(whispersTo("Peer-OtherRealm", mark + 1) == 0 and Net.Status().queued == 0, "an other-faction target is not whispered")
M.units.target.faction = "Alliance"
targetOnline = false
sendToTarget()
M.Tick(30, 1)
check(whispersTo("Peer-OtherRealm", mark + 1) == 0, "an offline target is not whispered")
targetOnline = true
sendToTarget()
M.Tick(60, 1)
check(whispersTo("Peer-OtherRealm", mark + 1) > 1, "an online same-faction target gets the route")
UnitIsConnected = nil

-- 9. Opting out sends nothing more, and the filter stays harmless.
ns.Set("routeSharing", false)
mark = #sent
receive(advert, "CHANNEL", "Stranger-TestRealm")
receive("Q^" .. mine.id .. "^1", "WHISPER", "Guildie-TestRealm")
M.Tick(60, 1)
check(#sent == mark, "after opting out nothing is sent")
check(notFound("Someone-TestRealm"), "after opting out unrelated 'not found' lines are shown")
check(channel == 0, "after opting out the channel is left")

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("Chat not-found tests: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
