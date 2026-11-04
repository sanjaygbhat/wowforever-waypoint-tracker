-- Character identities, echoed messages and saved vote repair in WoW Forever.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end

local first, full = "TestPlayer", "TestPlayer TestSurname"
UnitName = function() return first end
GetUnitName = function() return full end
WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local R, Net = ns.Routes, ns.RoutesNet
ns.DB.Load()
local id = R.Suggested()[1].id
local me, legacy = R.FullName(full), R.FullName(first)
local function score(up, down, message)
    local u, d = R.Score(id)
    check(u == up and d == down, message)
end

check(R.Me() == me, "local identity includes the surname used by addon messages")
check(R.Vote(id, 1), "cast an upvote")
score(1, 0, "one local upvote counts once")
Net.OnMessage("WPTR", "V^" .. id .. "^1", "GUILD", full)
Net.OnMessage("WPTR", "W^" .. id .. ":1", "CHANNEL", me)
score(1, 0, "echoes on multiple channels do not double the upvote")
R.Vote(id, -1)
Net.OnMessage("WPTR", "V^" .. id .. "^1", "GUILD", me)
score(0, 1, "changing direction replaces the vote and ignores a stale echo")
R.Vote(id, 0)
Net.OnMessage("WPTR", "W^" .. id .. ":1", "CHANNEL", me)
score(0, 0, "taking back a vote clears it and ignores a stale echo")

local st = R.Store()
st.votes[id] = { by = legacy, v = 1, at = time() }
st.tally[id] = { [legacy] = 1, [me] = 1, ["Other Person-TestRealm"] = -1 }
ns.Fire("INIT")
score(1, 1, "loading an old double tally merges only the current character")
check(st.votes[id].by == me and st.tally[id][legacy] == nil and R.MyVote(id) == 1,
    "legacy ownership migrates to the full identity")
check(R.MyVotes()[id] == 1, "migrated vote is shared under the full identity")
R.Vote(id, 0)
score(0, 1, "taking back a migrated vote removes both old identities")

st.votes[id] = { by = legacy, v = -1, at = time() }
st.tally[id] = { [legacy] = -1, [me] = 1 }
ns.Fire("INIT")
score(0, 1, "the saved local choice wins over a stale opposite echo")
ns.Fire("INIT")
score(0, 1, "repair is idempotent")

first, full = "Other", "Other Alt"
check(R.MyVote(id) == 0 and R.MyVotes()[id] == nil, "another character has no inherited vote")
R.Vote(id, 1)
score(1, 1, "different characters can each cast one vote")
first, full = "TestPlayer", "TestPlayer TestSurname"
check(R.MyVote(id) == -1 and R.MyVotes()[id] == -1, "returning to a character restores its own vote")
R.Vote(id, 0)
score(1, 0, "removing one character's vote preserves the other character's vote")

st.votes[id], st.tally[id] = nil, nil
Net.OnMessage("WPTR", "V^" .. id .. "^1", "GUILD", "Peer Surname")
Net.OnMessage("WPTR", "W^" .. id .. ":1", "CHANNEL", R.FullName("Peer Surname"))
score(1, 0, "repeated remote votes count once")
Net.OnMessage("WPTR", "V^" .. id .. "^-1", "GUILD", "Peer Surname")
score(0, 1, "a remote vote replaces its previous direction")
Net.OnMessage("WPTR", "V^" .. id .. "^0", "GUILD", "Peer Surname")
score(0, 0, "a remote vote can be taken back")

GetUnitName = nil
check(R.Me() == R.FullName(first), "clients without GetUnitName retain the UnitName fallback")
GetUnitName = function() return "" end
check(R.Me() == R.FullName(first), "an unavailable full name falls back to UnitName")
check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
