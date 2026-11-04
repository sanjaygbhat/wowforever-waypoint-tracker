-- Opt-in sharing, transport isolation and opt-out of pending work.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end
local sent, registered, joined, left = {}, {}, 0, 0
local channel = 0
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) registered[prefix] = true end,
    SendAddonMessage = function(prefix, msg, chat, target)
        sent[#sent + 1] = { prefix, msg, chat, target }
        return 0
    end,
}
GetChannelName = function() return channel end
JoinTemporaryChannel = function() channel = 7; joined = joined + 1 end
LeaveChannelByName = function() channel = 0; left = left + 1 end
M.group = { guild = true, party = true, raid = false }
WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local R, Net, Trails = ns.Routes, ns.RoutesNet, ns.Trails
local function receive(msg, sender)
    M.FireEvent("CHAT_MSG_ADDON", "WPTR", msg, "GUILD", sender or "Peer-TestRealm")
end
check(not ns.Get("routeSharing") and WaypointTrackerDB.version == 4, "fresh profile starts opted out at schema 4")
M.Tick(20, 1)
check(registered.WPTR and joined == 0 and #sent == 0, "shared prefix registers, but route sharing off neither joins nor greets")
local mine = R.SaveMine({ name = "Local route", public = true, pts = {
    { m = 37, x = 0.4, y = 0.5 }, { m = 37, x = 0.5, y = 0.6 },
} })
local localRoute = R.Keep({ id = "rlocal123", v = 1, author = "Friend-TestRealm", name = "Pasted locally", pts = mine.pts })
check(mine and localRoute and R.Vote(localRoute.id, 1) and R.MyVote(localRoute.id) == 1, "local saving and votes work while sharing is off")
local copy = R.Parse(R.Serialize(mine))
check(copy and #copy.pts == 2, "text export and import work while sharing is off")
check(R.Apply(mine.id, "replace") and R.Run().id == mine.id and ns.WP.Count() == 2, "following local routes works while sharing is off")
R.Stop(true)
ns.WP.ClearAll(true)
Net.Announce(mine.id)
check(Net.SendTo(mine.id, "Peer-TestRealm") == 0, "direct route sending is blocked while off")
Net.SelfTest()
local remote = R.Validate({ id = "rpeer123", v = 1, author = "Peer-TestRealm", name = "Remote", pts = mine.pts })
local text = R.Serialize(remote)
for _, msg in ipairs({
    "A^rpeer123^1^Peer-TestRealm^other^2^Remote", "Q^" .. mine.id .. "^1",
    "R^rpeer123^1^1^1^" .. text, "V^" .. localRoute.id .. "^-1", "W^" .. localRoute.id .. ":-1", "H", "P^123",
}) do receive(msg) end
M.Tick(601, 1)
local up, down = R.Score(localRoute.id)
check(not R.Get(remote.id) and up == 1 and down == 0 and Net.Status().got == 0,
    "all incoming route/vote protocol tags are ignored through the registered event while off")
check(#sent == 0 and Net.Status().queued == 0, "local actions, self-test, incoming requests and periodic ticks send nothing while off")

-- Travel uses this prefix/channel independently, including actual path listeners.
ns.Set("realRoutes", true)
check(ns.Get("travelShare") and not ns.Get("routeSharing"), "enabling Real routes leaves route sharing off")
M.Tick(3, 1)
check(joined == 1 and #sent == 0, "travel alone joins the transport without a route hello, list or votes")
local Enc, Key = Trails.Enc, Trails._Key
local path = "TP^0^" .. Enc(Key(500, 500), 4) .. Enc(0, 1)
receive(path)
receive(path, "Second-TestRealm")
check(Trails.Store().shared[0][Key(500, 500)] ~= nil, "walked paths are received and confirmed while route sharing is off")
check(Trails.Share(path), "walked paths can enqueue sends while route sharing is off")
M.Tick(1)
check(#sent == 3 and sent[1][2] == path and sent[1][3] == "CHANNEL" and sent[2][3] == "GUILD" and sent[3][3] == "PARTY",
    "travel sends still reach channel, guild and group while route sharing is off")
local got = Net.Status().got
receive("V^" .. localRoute.id .. "^-1")
receive("Q^" .. mine.id .. "^1")
receive("R^rpeer123^1^1^1^" .. text)
check(Net.Status().got == got and Net.Status().queued == 0 and not R.Get(remote.id),
    "travel opt-in does not enable incoming routes, votes or route requests")

ns.Set("routeSharing", true)
M.Tick(4, 1)
check(#sent > 3, "opting in announces routes and votes over the existing travel channel")
receive("V^" .. localRoute.id .. "^-1")
up, down = R.Score(localRoute.id)
check(up == 1 and down == 1, "opt-in processes remote votes")
receive("R^rpeer123^1^1^1^" .. text)
check(R.Get(remote.id) ~= nil, "opt-in receives a complete shared route")
check(Net.SendTo(mine.id, "Peer-TestRealm") > 0, "opt-in allows direct sends")
ns.Set("travelShare", false)
local unseen = "TP^0^" .. Enc(Key(600, 600), 4) .. Enc(0, 1)
receive(unseen)
receive(unseen, "Second-TestRealm")
check(not Trails.Share(path) and not Trails.Store().shared[0][Key(600, 600)] and ns.Get("routeSharing"),
    "travel opt-out independently blocks path sends and receives while routes stay enabled")
ns.Set("travelShare", true)

-- Queue both kinds, schedule a hello reply and begin a partial route, then opt out.
receive("H")
local fragment = R.Validate({ id = "rpartial", v = 1, author = "Peer-TestRealm", name = "Partial", pts = mine.pts })
local fragmentText = R.Serialize(fragment)
local split = math.floor(#fragmentText / 2)
receive("R^rpartial^1^1^2^" .. fragmentText:sub(1, split))
R.Vote(localRoute.id, -1)
Trails.Share(path)
local before = #sent
ns.Set("routeSharing", false)
check(Net.Status().queued == 3 and left == 0, "opting out purges pending routes/votes but keeps queued travel and its channel")
M.Tick(20, 1)
local onlyTravel = #sent > before
for i = before + 1, #sent do onlyTravel = onlyTravel and sent[i][2]:sub(1, 1) == "T" end
check(onlyTravel, "queued sends and delayed hello replies produce no route/vote traffic after opt-out")
ns.Set("routeSharing", true)
receive("R^rpartial^1^2^2^" .. fragmentText:sub(split + 1))
check(not R.Get(fragment.id), "opting out discards partial routes before a later opt-in")

-- Reset broadcasts a nil setting key, and must also purge pending route sends.
Net.SendTo(mine.id, "Peer-TestRealm")
ns.ResetSettings()
before = #sent
M.Tick(20, 1)
check(not ns.Get("routeSharing") and #sent == before and Net.Status().queued == 0,
    "reset restores opt-out and cancels pending traffic immediately")
check(channel == 0 and left == 1, "transport leaves when neither sharing feature needs it")
check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("Route sharing tests: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
