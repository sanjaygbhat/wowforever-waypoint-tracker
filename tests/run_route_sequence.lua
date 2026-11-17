-- Quest-chain routes go one step after another. Owner report (1.4.1): in
-- the Defias Brotherhood chain the arrow went from 1/17 to 6/17 on its own.
-- Every choice made for the player (a waypoint that took the arrow going
-- away, "always point to the closest", loading) used to take the nearest
-- of all waypoints, so the nearest of the route's stops. These scenarios
-- walk a Defias-like 17-step chain with the player standing next to later
-- stops and check the step only moves in order; the quest log can prove
-- steps done (then the route goes on to the next stop in order), and a
-- followed quest keeps the objective area it was given until an objective
-- is finished.
--     lua5.1 tests/run_route_sequence.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function check(ok, message)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. message)
    end
end

-- Map percentages to the mock's world yards (see wowmock M.maps).
local function Here(m, x, y)
    local map = M.maps[m]
    M.player.inst = map.cont
    M.player.wx, M.player.wy = map.top - y * map.h, map.left - x * map.w
end

-- A Defias-like chain: Sentinel Hill (Westfall, 52), Stormwind (84), a
-- Lakeshire stand-in (Elwynn, 37), messenger spots, back to Sentinel Hill.
local GRYAN, SHAW, SHAW_B, WILEY = { 52, .563, .475 }, { 84, .758, .598 }, { 84, .760, .600 }, { 37, .80, .60 }
local STOPS = {
    { GRYAN, "Start: Gryan", 65, "start" },
    { SHAW, "Hand in: Shaw", 65, "end" },
    { SHAW, "Start: Shaw", 132, "start" },
    { WILEY, "Hand in: Wiley", 132, "end" },
    { WILEY, "Start: Wiley", 135, "start" },
    { SHAW_B, "Hand in: Shaw", 135, "end" }, -- a few yards off: the nearest
    { SHAW, "Start: Shaw", 141, "start" },
    { GRYAN, "Hand in: Gryan", 141, "end" },
    { GRYAN, "Start: Gryan", 142, "start" },
    { { 52, .30, .30 }, "Defias Messenger", 142, "goal" },
    { { 52, .35, .45 }, "Defias Messenger", 142, "goal" },
    { { 52, .40, .60 }, "Defias Messenger", 142, "goal" },
    { { 52, .45, .70 }, "Defias Messenger", 142, "goal" },
    { GRYAN, "Hand in: Gryan", 142, "end" },
    { { 52, .557, .475 }, "Start: Defias Traitor", 155, "start" },
    { GRYAN, "Hand in: Gryan", 155, "end" },
    { GRYAN, "Start: Gryan", 166, "start" },
}
local N = #STOPS
local ID = "chaintest01"
local pts = {}
for i, s in ipairs(STOPS) do
    pts[i] = { m = s[1][1], x = s[1][2], y = s[1][3], t = s[2], q = s[3], role = s[4] }
end
local function Route(id, mode, list)
    return { id = id, v = 1, name = "Defias test chain", cat = "quests", mode = mode, author = "Tester-Realm",
        src = "mine", made = 1, pts = list }
end

-- ---------------------------------------------------------------------------
-- 1. Loading. A route followed at step 3 when the arrow was on something
-- that isn't kept (a followed quest): after a reload the arrow is on step 3,
-- not on the newest waypoint (the route's last stop, 17/17).
-- ---------------------------------------------------------------------------
local saved = {}
for i = 3, N do
    local p = pts[i]
    saved[#saved + 1] = { m = p.m, x = p.x, y = p.y, title = ("%d/%d %s"):format(i, N, p.t),
        source = "route", routeID = ID, routeIndex = i }
end
WaypointTrackerDB = { routes = { list = { [ID] = Route(ID, "order", pts) } } }
WaypointTrackerCharDB = {
    routeRun = { id = ID, mode = "order", total = N, done = 2, secs = 0, lap = 0, seen = {}, cur = 3 },
    waypoints = saved,
}
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local WP, Routes, Follow, L = ns.WP, ns.Routes, ns.Follow, ns.L
ns.Set("realRoutes", false)
M.Tick(1)

local function Step()
    local wp = WP.GetActive()
    return wp and wp.routeID and wp.routeIndex or nil
end
local function Stop(i)
    for _, wp in ipairs(WP.List()) do
        if wp.routeIndex == i then
            return wp
        end
    end
end

check(Routes.Run() and Routes.Run().id == ID, "a saved route is still followed after loading")
check(Step() == 3, "after loading the arrow is on the step the route was on (got " .. tostring(Step()) .. ", was " .. N .. ")")
check(Routes._ProvenDone(pts[1]) == false, "a quest stop is not done without proof from the quest log")
-- a run kept by 1.4.1 has no step of its own: it is on its lowest stop left
Routes.Run().cur = nil
check(WP.Closest(nil, true) == Stop(3), "a route without a remembered step counts by its lowest stop")
Routes.Run().cur = 3

-- ---------------------------------------------------------------------------
-- 2. The reported bug. Step 1, the player in Stormwind right on step 6.
-- Whatever takes the arrow for a moment and then goes, the arrow comes
-- back to step 1 (1.4.1: the nearest waypoint, 6/17).
-- ---------------------------------------------------------------------------
local function Start(mode, list)
    WP.ClearAll(true)
    local st = Routes.Store()
    st.list[ID] = Route(ID, mode or "order", list or pts)
    check(Routes.Apply(ID, "replace"), "the chain starts")
    return Routes.Run()
end
Here(SHAW_B[1], SHAW_B[2], SHAW_B[3])
local run = Start()
check(Step() == 1 and run.cur == 1, "a chain starts at its first step even with later stops next to you")

-- a clicked quest takes the arrow and is handed in
check(Follow.TrackQuest(101) and WP.GetActive().source == "quest", "a clicked quest takes the arrow")
M.FireEvent("QUEST_TURNED_IN", 101)
check(Step() == 1, "handing in a clicked quest gives the arrow back to step 1 (got " .. tostring(Step()) .. ")")
M.Tick(1)

-- a looked-up spot is reached and cleared (auto-clear, then next)
local spot = WP.Add(84, .5, .5, { title = "Innkeeper", silent = true, source = "find" })
check(WP.GetActive() == spot, "a looked-up spot takes the arrow")
WP.CheckArrival(spot, 100)
check(WP.CheckArrival(spot, 0) and not WP.IsValid(spot), "reaching it clears it")
check(Step() == 1, "after reaching it the arrow is back on step 1 (got " .. tostring(Step()) .. ")")

-- a treasure (or anything else) taking the arrow goes away
local chest = WP.Add(84, .7, .6, { title = "Chest", silent = true, source = "treasure", persistent = false, noReuse = true })
check(WP.GetActive() == chest, "a treasure takes the arrow")
WP.Remove(chest, true)
check(Step() == 1, "when the treasure goes the arrow is back on step 1 (got " .. tostring(Step()) .. ")")

-- dying and coming back
M.player.dead = true
M.FireEvent("PLAYER_DEAD")
check(WP.GetActive() and WP.GetActive().source == "corpse", "dying points at your body")
M.player.dead = false
M.FireEvent("PLAYER_ALIVE")
check(Step() == 1, "coming back to life the arrow is back on step 1 (got " .. tostring(Step()) .. ")")

-- removing a stop that isn't the arrow's by hand changes nothing; removing
-- the route's step while something else has the arrow: the next in order
WP.Remove(Stop(6), true)
check(Step() == 1, "removing another stop keeps step 1")
local find = WP.Add(84, .5, .5, { title = "Bank", silent = true, source = "find" })
WP.Remove(Stop(1), true)
WP.Remove(find, true)
check(Step() == 2, "the route's step removed meanwhile: the arrow goes on to the next step in order (got " .. tostring(Step()) .. ")")

-- "Always point to the closest waypoint": the route counts by its step only
run = Start()
ns.Set("autoClosest", true)
M.Tick(3)
check(Step() == 1, "always-closest leaves the chain on step 1 next to step 6 (got " .. tostring(Step()) .. ")")
local mine = WP.Add(84, SHAW_B[2] + .01, SHAW_B[3], { title = "My spot", silent = true, setActive = false })
M.Tick(3)
check(WP.GetActive() == mine, "always-closest still takes a nearer waypoint of your own")
WP.Remove(mine, true)
check(Step() == 1, "and gives the arrow back to the chain's step 1 (got " .. tostring(Step()) .. ")")
ns.Set("autoClosest", false)
-- another addon asking for "the closest waypoint" (TomTom API)
check(TomTom and TomTom.isWaypointTrackerBridge, "the TomTom-compatible bridge is in place")
TomTom:SetClosestWaypoint()
check(Step() == 1, "another addon setting the closest waypoint leaves the chain on step 1 (got " .. tostring(Step()) .. ")")
WP.SetClosest(true)
check(Step() == 6, "your own 'closest waypoint' key still picks the nearest stop (got " .. tostring(Step()) .. ")")
check(Routes.Run().cur == 6, "and the chain goes on from there")

-- ---------------------------------------------------------------------------
-- 3. Walking the chain with always-closest on: before each step the player
-- stands next to a later stop; the step stays, then is reached in order.
-- ---------------------------------------------------------------------------
local function Far(a, b)
    return a[1] ~= b[1] or math.abs(a[2] - b[2]) > .05 or math.abs(a[3] - b[3]) > .05
end
run = Start()
ns.Set("autoClosest", true)
local order, jumped = {}, nil
for i = 1, N do
    local at = STOPS[i][1]
    -- a later stop somewhere else (else Stormwind)
    local decoy = SHAW
    for j = N, i + 1, -1 do
        if Far(STOPS[j][1], at) then
            decoy = STOPS[j][1]
            break
        end
    end
    Here(decoy[1], decoy[2], decoy[3])
    M.Tick(2.5)
    if Step() ~= i and not jumped then
        jumped = ("step %d became %s next to a later stop"):format(i, tostring(Step()))
    end
    Here(at[1], at[2], at[3])
    M.Tick(2.5)
    order[#order + 1] = i
end
check(not jumped, "the step never moves on its own: " .. tostring(jumped))
check(#order == N and Routes.Run() == nil, "every step reached in order completes the chain")
ns.Set("autoClosest", false)

-- ---------------------------------------------------------------------------
-- 4. The quest log. Quest 65 handed in, 132 in the log: the chain starts at
-- 4/17. A later quest handed in does not move it on; each proof moves it to
-- the next step in order. A followed quest keeps the arrow meanwhile.
-- ---------------------------------------------------------------------------
local function Log(id, fields)
    for k = #M.quests, 1, -1 do
        if M.quests[k].id == id then table.remove(M.quests, k) end
    end
    if fields then
        fields.id, fields.title = id, fields.title or ("Quest " .. id)
        M.quests[#M.quests + 1] = fields
    end
end
local function Settle()
    M.FireEvent("QUEST_LOG_UPDATE")
    M.Tick(0.7)
end
M.completedQuests = { [65] = true }
Log(132, { objectives = {} })
Here(SHAW_B[1], SHAW_B[2], SHAW_B[3])
ns.Window.Show("waypoints")
run = Start()
check(Step() == 4 and run.done == 3, "a chain starts at the first step the quest log doesn't show done (got " .. tostring(Step()) .. ")")
check(ns.Window.frame.status:GetText() == L.ROUTE_QUEST_DONE:format(WP.ShortName(Stop(4))),
    "the status line says the quest log moved it on")
M.completedQuests[141] = true -- later quest done (another way): not a reason to skip ahead
Settle()
check(Step() == 4, "a later step proven done does not move the chain past step 4 (got " .. tostring(Step()) .. ")")
Log(132, nil)
M.FireEvent("QUEST_TURNED_IN", 132)
Settle()
check(Step() == 5, "handing in 132 goes on to step 5 (got " .. tostring(Step()) .. ")")
Log(135, { objectives = {} })
M.FireEvent("QUEST_ACCEPTED", 135)
Settle()
check(Step() == 6, "accepting 135 goes on to step 6 (got " .. tostring(Step()) .. ")")
Log(135, nil)
M.FireEvent("QUEST_TURNED_IN", 135)
Settle()
check(Step() == 9, "handing in 135 goes on past 7 and 8 (141 is done) to step 9 (got " .. tostring(Step()) .. ")")
local messenger = { objectives = { { numFulfilled = 0, numRequired = 1, finished = false } } }
Log(142, messenger)
M.FireEvent("QUEST_ACCEPTED", 142)
Settle()
check(Step() == 10, "accepting 142 goes on to its first objective, step 10 (got " .. tostring(Step()) .. ")")
-- the arrow is on a clicked quest when 142's objectives complete
Follow.TrackQuest(101)
messenger.complete, messenger.objectives[1].finished, messenger.objectives[1].numFulfilled = true, true, 1
Settle()
check(WP.GetActive() and WP.GetActive().source == "quest", "the quest log moving the chain on leaves the arrow where you put it")
check(run.cur == 14 and Stop(10) == nil and Stop(13) == nil, "objectives done: the chain waits at its hand-in, step 14")
M.FireEvent("QUEST_TURNED_IN", 101)
check(Step() == 14, "the clicked quest handed in: the arrow goes to step 14 (got " .. tostring(Step()) .. ")")
Routes.Stop(true)
M.completedQuests = nil
Log(142, nil)
M.Tick(1)

-- ---------------------------------------------------------------------------
-- 5. "Nearest next" quest routes: a quest giver who also takes it back.
-- Picked up first, then its objectives, the hand-in last, though the
-- hand-in is where you stand.
-- ---------------------------------------------------------------------------
local WILLEM = { 37, .40, .30 }
local near = {
    { m = 37, x = .40, y = .30, t = "Start: Willem", q = 18, role = "start" },
    { m = 37, x = .45, y = .35, t = "Defias Thug", q = 18, role = "goal" },
    { m = 37, x = .52, y = .40, t = "Defias Thug", q = 18, role = "goal" },
    { m = 37, x = .40, y = .30, t = "Hand in: Willem", q = 18, role = "end" },
    { m = 37, x = .70, y = .70, t = "Defias Thug" },
}
Here(WILLEM[1], WILLEM[2], WILLEM[3])
Start("nearest", near)
check(Step() == 1, "nearest next begins with picking the quest up (got " .. tostring(Step()) .. ")")
local function Reach(i)
    local wp = Stop(i)
    WP.CheckArrival(wp, 100)
    WP.CheckArrival(wp, 0)
end
Reach(1)
check(Step() == 2, "then its nearest objective, not the hand-in at the same spot (got " .. tostring(Step()) .. ")")
Reach(2)
check(Step() == 3, "then the next objective (got " .. tostring(Step()) .. ")")
Reach(3)
check(Step() == 4, "the hand-in once the objectives are behind you (got " .. tostring(Step()) .. ")")
Routes.Stop(true)

-- ---------------------------------------------------------------------------
-- 6. A followed quest with objectives in several areas. The game's marker
-- hops to whichever area is nearest (and to another zone's); the arrow
-- keeps the area it was given until an objective is finished.
-- ---------------------------------------------------------------------------
WP.ClearAll(true)
Here(37, .40, .30)
local quest = { title = "Kobold Camps", objectives = {
    { numFulfilled = 0, numRequired = 8, finished = false },
    { numFulfilled = 0, numRequired = 4, finished = false },
}, onMap = { [37] = { .50, .40 }, [52] = { .30, .20 } } }
Log(301, quest)
local followed = Follow.TrackQuest(301)
check(followed and followed.x == .50 and followed.y == .40, "a click takes the marker's area")
local hops = 0
for k = 1, 6 do
    quest.onMap[37] = k % 2 == 1 and { .42, .32 } or { .50, .40 }
    quest.objectives[1].numFulfilled = k -- counting up is not finishing
    Settle()
    if WP.GetActive() ~= followed or followed.x ~= .50 then hops = hops + 1 end
end
check(hops == 0 and WP.IsValid(followed), "the marker hopping between areas does not move the arrow (" .. hops .. " hops)")
Here(52, .50, .10) -- into Westfall: the marker shows that zone's area
M.FireEvent("ZONE_CHANGED_NEW_AREA")
Settle()
check(WP.GetActive() == followed and followed.m == 37 and followed.x == .50, "crossing into another zone keeps the area")
Here(37, .40, .30)
M.FireEvent("ZONE_CHANGED_NEW_AREA")
quest.onMap[37] = { .42, .32 }
quest.objectives[1].numFulfilled, quest.objectives[1].finished = 8, true
Settle()
local moved = WP.GetActive()
check(moved and moved.source == "quest" and moved.x == .42 and moved.y == .32, "a finished objective takes the marker's new area")
quest.onMap[37] = { .50, .40 }
Settle()
check(WP.GetActive() == moved and moved.x == .42, "and keeps that one again")
quest.complete, quest.onMap[37] = true, { .20, .20 }
quest.objectives[2].numFulfilled, quest.objectives[2].finished = 4, true
Settle()
check(WP.GetActive() and WP.GetActive().x == .20 and WP.GetActive().y == .20, "the quest done: on to its hand-in")
quest.complete, quest.objectives[2].finished = false, false
quest.onMap[37] = { .50, .40 }
Settle()
local before = WP.GetActive()
quest.onMap[37] = { .42, .32 }
check(Follow.TrackQuest(301) and WP.GetActive().x == .42, "a click picks the marker's area again at once")
check(before ~= WP.GetActive(), "(the click replaced the waypoint)")
-- the quest tracked automatically ("Point to the quest I'm tracking")
Follow.StopQuest(301)
ns.Set("followQuest", true)
M.superTracked = 301
M.FireEvent("SUPER_TRACKING_CHANGED")
M.Tick(1)
local auto = WP.GetActive()
check(auto and auto.source == "quest" and auto.x == .42, "the tracked quest is followed")
quest.onMap[37] = { .50, .40 }
Settle()
Settle()
check(WP.GetActive() == auto and auto.x == .42, "the tracked quest keeps its area while the marker hops")
ns.Set("followQuest", false)
M.superTracked = 0
M.FireEvent("SUPER_TRACKING_CHANGED")
Log(301, nil)
M.Tick(1)

-- ---------------------------------------------------------------------------
-- 7. The ready-made Defias Brotherhood chain knows each stop's quest; the
-- quest tags never go out with a shared route.
-- ---------------------------------------------------------------------------
check(ns.DB.Load(), "database loads")
local defias
for _, r in ipairs(Routes.Suggested()) do
    if r.name == "The Defias Brotherhood chain" then defias = r end
end
check(defias and defias.mode == "order" and #defias.pts >= 10, "the Defias Brotherhood chain is a ready-made route in order")
local tagged = 0
for _, p in ipairs(defias and defias.pts or {}) do
    if p.q and p.role then tagged = tagged + 1 end
end
check(defias and tagged == #defias.pts and defias.pts[1].role == "start" and defias.pts[1].q == 65,
    "every stop knows its quest and what it is for")
local copy = defias and Routes.Parse(Routes.Serialize(defias))
check(copy and copy.pts[1].q == nil and copy.pts[1].role == nil, "sharing does not carry quest tags")
check(Routes.Validate({ id = "abc", pts = { { m = 37, x = .1, y = .1, q = 5, role = "steal" } } }).pts[1].q == nil,
    "an unknown stop role is dropped")
-- a chain kept before quest tags existed starts as it is made now
local st = Routes.Store()
local old = Route(defias.id, "order", { { m = defias.pts[1].m, x = defias.pts[1].x, y = defias.pts[1].y, t = "old" } })
old.src = "suggested"
st.list[defias.id] = old
WP.ClearAll(true)
check(Routes.Apply(defias.id, "replace") and Routes.Get(defias.id).pts[1].q == 65 and Routes.Run().total == #defias.pts,
    "starting a ready-made chain kept by 1.4.1 uses the route as made now")
Routes.Stop(true)

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
