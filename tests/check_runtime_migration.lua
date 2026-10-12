-- Saved short identities survive load, replay, vote removal and blocking.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
UnitName = function() return "TestPlayer", "TestSurname" end
GetUnitName = function() return "TestPlayer TestSurname" end
GetNormalizedRealmName = function() return "TestRealm" end
local function route(id, author, src)
    return { id = id, author = author, src = src, name = id, pts = { { m = 37, x = .4, y = .6 } } }
end
WaypointTrackerDB = { routes = {
    list = {
        own = route("own", "TestPlayer", "mine"),
        alt = route("alt", "Other Alt", "mine"),
        peer = route("peer", "Peer Surname", "shared"),
        seed = route("seed", "Waypoint Tracker", "suggested"),
    },
    votes = { peer = { by = "TestPlayer", v = -1, at = 10 } },
    tally = { peer = {
        TestPlayer = 1, ["TestPlayer-TestRealm"] = 1, ["TestPlayer TestSurname"] = 1,
        ["TestPlayer TestSurname-TestRealm"] = 1, ["Peer Surname"] = -1,
        ["Peer Surname-TestRealm"] = 1, ["Peer Surname-OtherRealm"] = -1,
        ["Other Alt"] = 1,
    } },
    blocked = { ["Blocked Surname"] = true },
} }
WaypointTrackerCharDB = { routeRun = { id = "own" }, waypoints = {
    { m = 37, x = .4, y = .6, routeID = "own", routeIndex = 1, source = "route", active = true },
} }
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
local R, st = ns.Routes, ns.Routes.Store()
local passed, failed = 0, 0
local function check(ok, msg)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function migrated()
    check(st.list.own.author == R.Me(), "own route keeps ownership under the full surname identity")
    check(st.list.alt.author == "Other Alt-TestRealm", "another character's route remains theirs")
    check(st.list.peer.author == "Peer Surname-TestRealm", "saved shared author gets its local realm")
    check(st.list.seed.author == R.SUGGESTED_AUTHOR, "suggested author remains a system label")
    check(ns.charDB.routeRun and ns.charDB.routeRun.id == "own", "following a saved route survives load")
    check(st.votes.peer.by == R.Me() and R.MyVote("peer") == -1, "saved local choice wins over old echoes")
    local up, down = R.Score("peer")
    check(up == 2 and down == 2, "aliases merge without dropping alt and cross-realm votes")
    check(st.tally.peer.TestPlayer == nil and st.tally.peer["TestPlayer-TestRealm"] == nil and st.tally.peer["TestPlayer TestSurname"] == nil,
        "short local tally aliases are removed")
    check(st.tally.peer["Peer Surname"] == nil and st.tally.peer["Peer Surname-TestRealm"] == 1,
        "existing canonical remote vote wins over a conflicting short echo")
    check(st.blocked["Blocked Surname-TestRealm"] and not st.blocked["Blocked Surname"], "saved block key gets its realm")
end
migrated()
ns.Fire("INIT")
migrated()
check(R.Vote("peer", 0) and st.tally.peer[R.Me()] == nil, "removal clears the migrated local vote")
R.HeardVote("peer", "Peer Surname", 0)
check(st.tally.peer["Peer Surname-TestRealm"] == nil and st.tally.peer["Peer Surname-OtherRealm"] == -1,
    "short-form remote removal preserves the other realm")
check(R.Keep(route("blocked", "Blocked Surname", "shared")) == nil, "short author cannot bypass a migrated block")
local kept = R.Keep(route("newpeer", "New Surname", "shared"))
check(kept and kept.author == "New Surname-TestRealm", "incoming routes use the same key as blocking")
R.Block("New Surname")
check(st.list.newpeer == nil, "blocking the short author removes its saved full-identity route")
R.Block(R.ShortName(R.Me()))
R.Block(R.SUGGESTED_AUTHOR)
check(not st.blocked[R.Me()] and not st.blocked[R.SUGGESTED_AUTHOR], "self and suggested routes cannot be blocked")
GetUnitName = nil
check(R.Me() == "TestPlayer TestSurname-TestRealm", "Forever fallback combines first name and surname")
GetUnitName = function() error("restricted helper") end
check(R.Me() == "TestPlayer TestSurname-TestRealm", "failed helper uses guarded native name returns")
local secret = {}
issecretvalue = function(v) return rawequal(v, secret) end
GetUnitName = function() return secret end
UnitName = function() return secret, secret end
check(R.UnitIdentity("target") == nil and R.Me() == "?", "unreadable identities do not reach string operations")
check(#M.errors == 0, "no runtime errors: " .. tostring(M.errors[1]))
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
