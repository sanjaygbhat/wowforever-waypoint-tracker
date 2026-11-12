-- Tracked-quest position fallback cost and freshness.
-- Places.QuestPosition(id) (Find, Nearest, Routes, clicks) must behave
-- exactly as in 1.3.1: same answers, same continent scans. Only Follow's
-- automatic update passes "auto": a followed quest no map shows is scanned
-- for once, then again after 30 s or at once when it progresses, completes,
-- a quest is accepted, the zone changes, a loading screen ends or it is
-- clicked; a quest found by the scan is rescanned at most every 10 s.
-- The continent has 45 extra zones so a scan costs what it would in game.
-- Run from repo root: lua5.1 tests/run_follow_scan.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. message) end
end

local FIRST, LAST = 9001, 9045
for id = FIRST, LAST do
    local i = id - FIRST
    M.maps[id] = { mapID = id, name = 'Test Zone ' .. i, mapType = 3, parentMapID = 13, cont = 0,
        top = -20000 - (i % 9) * 1200, left = -20000 - math.floor(i / 9) * 1200, w = 1000, h = 1000 }
end

-- Count every call into the map/quest/taxi/POI/dungeon/vignette families.
local calls, scans = 0, 0
for _, family in ipairs({ 'C_Map', 'C_QuestLog', 'C_TaxiMap', 'C_AreaPoiInfo', 'C_EncounterJournal', 'C_VignetteInfo' }) do
    local t = _G[family]
    for name, fn in pairs(t) do
        if type(fn) == 'function' then
            t[name] = function(...) calls = calls + 1; return fn(...) end
        end
    end
end
-- Only Places asks for dungeon entrances, once per zone per continent scan.
local entrances = C_EncounterJournal.GetDungeonEntrancesForMap
C_EncounterJournal.GetDungeonEntrancesForMap = function(id, ...)
    if id == LAST then scans = scans + 1 end
    return entrances(id, ...)
end

local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
M.Tick(1)
local WP, Follow, Places, Geo = ns.WP, ns.Follow, ns.Places, ns.Geo
Geo.GetZoneList() -- built once per session; not part of a scan

-- Continent scans on any continent: Places.GetAll building a new result.
local rebuilds, lastResult = 0, nil
local getAll = Places.GetAll
Places.GetAll = function(...)
    local out = getAll(...)
    if out ~= lastResult then rebuilds, lastResult = rebuilds + 1, out end
    return out
end

local function Quest(id, fields)
    for i = #M.quests, 1, -1 do if M.quests[i].id == id then table.remove(M.quests, i) end end
    local q = fields or {}
    q.id, q.title = id, q.title or ('Quest ' .. id)
    M.quests[#M.quests + 1] = q
    return q
end
local function Drop(id)
    for i = #M.quests, 1, -1 do if M.quests[i].id == id then table.remove(M.quests, i) end end
end
-- Quest log events at 2 per second; Follow looks at most twice a second.
local function Questing(seconds)
    local before = scans
    for _ = 1, seconds * 2 do
        M.FireEvent('QUEST_LOG_UPDATE')
        M.Tick(0.5, 0.5)
    end
    return scans - before
end
local function Rebuilds(fn)
    local before = rebuilds
    fn()
    return rebuilds - before
end
local function Track(id)
    M.superTracked = id
    M.FireEvent('SUPER_TRACKING_CHANGED')
end
local function Text(m, x, y)
    return m and ('%s %s %s'):format(tostring(m), tostring(x), tostring(y)) or 'nil'
end
local function Arrow()
    local wp = WP.GetActive()
    return wp and Text(wp.m, wp.x, wp.y) or 'nil'
end

-- 1. Cost of one fallback scan.
Quest(999)
local c0, s0 = calls, scans
check(Places.QuestPosition(999) == nil, 'quest with no marker anywhere has no position')
check(scans - s0 == 1, 'a lookup scans the continent once')
local perScan = calls - c0
print(('one fallback scan: %d map/quest/taxi/POI/dungeon/vignette API calls over %d zones'):format(perScan, LAST - FIRST + 2))

-- 2. Automatic following of a quest with no position, 120 s of questing:
-- one scan, then one per 30 s backoff (1.3.1: one per 10 s miss memory).
ns.Set('followQuest', true)
Track(999)
local first = Questing(29)
local rest = Questing(91)
print(('followed quest without a position: %d scans in the first 29 s, %d in 120 s'):format(first, first + rest))
check(first == 1, 'one scan in the first 29 s (got ' .. first .. ')')
check(first + rest <= 5, 'at most one rescan per 30 s backoff over 120 s (got ' .. first + rest .. ')')
check(WP.GetActive() == nil, 'no waypoint for a quest without a position')

-- 3. The quest appears on another zone of the continent after a zone change.
Quest(999, { onMap = { [9010] = { 0.5, 0.25 } } })
M.FireEvent('ZONE_CHANGED_NEW_AREA')
local s1 = scans
Questing(0.5)
local wp = WP.GetActive()
check(wp and wp.m == 9010 and wp.x == 0.5 and wp.y == 0.25, 'zone change finds the new position on the next update')
check(scans - s1 == 1, 'zone change allows one fresh scan')

-- 3b. A loading screen with no zone event (PLAYER_ENTERING_WORLD only).
Quest(999, { onMap = { [9011] = { 0.25, 0.5 } } })
M.FireEvent('PLAYER_ENTERING_WORLD')
Questing(0.5)
wp = WP.GetActive()
check(wp and wp.m == 9011 and wp.x == 0.25 and wp.y == 0.5, 'a loading screen alone finds the new position on the next update')

-- 4. Completing the quest moves its marker; that is looked for at once.
ns.Set('followQuest', false); M.Tick(1)
Quest(998)
M.superTracked = 998
ns.Set('followQuest', true)
M.FireEvent('SUPER_TRACKING_CHANGED')
Questing(15)
local s2 = scans
Quest(998, { complete = true, onMap = { [9020] = { 0.75, 0.5 } } })
Questing(0.5)
wp = WP.GetActive()
check(wp and wp.m == 9020 and wp.x == 0.75 and wp.y == 0.5, 'completed quest turn-in is found on the next update')
check(scans - s2 == 1, 'completion allows one rescan')

-- 4b. Objective progress can move the marker too.
ns.Set('followQuest', false); M.Tick(1)
Quest(995, { objectives = { { numFulfilled = 0, numRequired = 2, finished = false } } })
M.superTracked = 995
ns.Set('followQuest', true)
M.FireEvent('SUPER_TRACKING_CHANGED')
Questing(15)
local s4 = scans
check(WP.GetActive() == nil and Questing(5) == 0, 'no rescans while nothing about the quest changes')
Quest(995, { objectives = { { numFulfilled = 1, numRequired = 2, finished = false } }, onMap = { [9025] = { 0.4, 0.45 } } })
Questing(0.5)
wp = WP.GetActive()
check(wp and wp.m == 9025 and wp.x == 0.4 and wp.y == 0.45, 'objective progress finds the moved marker on the next update')
check(scans - s4 == 1, 'objective progress allows one rescan')

-- 5. Clicks look the quest up as 1.3.1 did: a scan, a miss remembered 10 s.
ns.Set('followQuest', false); M.Tick(1)
Quest(997)
local s3 = scans
check(Follow.TrackQuest(997) == nil and scans - s3 == 1, 'first click on a quest without a position scans once and finds nothing')
check(Follow.TrackQuest(997) == nil and scans - s3 == 1, 'a second click within 10 s of the miss does not rescan (as 1.3.1)')
Quest(997, { onMap = { [9030] = { 0.125, 0.875 } } })
M.Tick(10.05, 0.05)
wp = Follow.TrackQuest(997)
check(wp and wp.m == 9030 and wp.x == 0.125 and wp.y == 0.875 and WP.GetActive() == wp and scans - s3 == 2,
    'a click 10 s after a miss scans again and finds a position that has appeared')

-- 6. Positions are unchanged: current map, the game's next waypoint, and a
-- marker on another zone of the continent.
wp = Follow.TrackQuest(101)
check(wp and wp.m == 37 and wp.x == 0.39 and wp.y == 0.82, 'current-map quest position unchanged')
wp = Follow.TrackQuest(102)
check(wp and wp.m == 52 and wp.x == 0.56 and wp.y == 0.47, 'next-waypoint quest position unchanged')
Quest(996, { onMap = { [9040] = { 0.3, 0.6 } } })
local m, x, y = Places.QuestPosition(996)
check(m == 9040 and x == 0.3 and y == 0.6, 'other-zone quest position unchanged')

-- 7. A followed quest found only on another zone: the arrow keeps it while
-- the continent is rescanned at most once per cache lifetime (10 s).
ns.Set('followQuest', true)
M.superTracked = 996
M.FireEvent('SUPER_TRACKING_CHANGED')
local found = Questing(30)
wp = WP.GetActive()
print(('followed quest on another zone: %d scans in 30 s'):format(found))
check(wp and wp.m == 9040 and wp.x == 0.3 and wp.y == 0.6, 'followed other-zone quest keeps its position')
check(found <= 4, 'other-zone quest rescans at most every 10 s (got ' .. found .. ')')

-- Back to a quiet state: nothing followed, nothing clicked.
local function Quiet()
    ns.Set('followQuest', false)
    Track(0)
    if WP.GetActive() then WP.Remove(WP.GetActive(), true) end
    M.Tick(15, 0.5)
end
Quiet()

-- 8. Reviewer cases. A quest accepted right after a scan is found by the
-- next lookup on both paths.
Places.GetAll() -- Find tab open: a shared scan built now
M.Tick(1)
Quest(960, { objectives = { { numFulfilled = 0, numRequired = 3, finished = false } }, onMap = { [52] = { 0.33, 0.44 } } })
m, x, y = Places.QuestPosition(960)
check(Text(m, x, y) == Text(52, 0.33, 0.44), 'lookup right after accepting finds the new quest')
Places.GetAll()
M.Tick(1)
Quest(961, { objectives = { { numFulfilled = 0, numRequired = 3, finished = false } }, onMap = { [9041] = { 0.2, 0.7 } } })
ns.Set('followQuest', true)
Track(961)
Questing(0.5)
check(Arrow() == Text(9041, 0.2, 0.7), 'automatic update right after accepting finds the new quest')
Quiet()

-- 8b. A FOUND followed quest completes and its marker moves: the arrow moves
-- on the next automatic update, and a lookup right after returns the turn-in.
Quest(990, { objectives = { { numFulfilled = 0, numRequired = 1, finished = false } }, onMap = { [52] = { 0.2, 0.3 } } })
ns.Set('followQuest', true)
Track(990)
Questing(1)
check(Arrow() == Text(52, 0.2, 0.3), 'followed quest found by the scan')
Questing(3)
Quest(990, { complete = true, objectives = { { numFulfilled = 1, numRequired = 1, finished = true } }, onMap = { [84] = { 0.6, 0.7 } } })
M.FireEvent('QUEST_LOG_UPDATE')
M.Tick(0.6, 0.05)
check(Arrow() == Text(84, 0.6, 0.7), 'completion moves the arrow on the next automatic update')
check(Text(Places.QuestPosition(990)) == Text(84, 0.6, 0.7), 'lookup right after completion returns the turn-in')
Quiet()

-- 8c. Lookups after a completion with the shared scan young (Find typing).
Quest(980, { onMap = { [52] = { 0.2, 0.3 } } })
Places.Search('quest')
check(Text(Places.QuestPosition(980)) == Text(52, 0.2, 0.3), 'lookup before completion')
M.Tick(2)
Quest(980, { complete = true, onMap = { [84] = { 0.6, 0.7 } } })
check(Text(Places.QuestPosition(980)) == Text(84, 0.6, 0.7), 'lookup 2 s after completion returns the turn-in')

-- 8d. A lookup's miss is retried after 10 s exactly as 1.3.1.
M.Tick(20)
Quest(970)
check(Places.QuestPosition(970) == nil, 'quest without a marker: no position')
M.Tick(1)
Quest(970, { onMap = { [52] = { 0.45, 0.55 } } })
local r = rebuilds
M.Tick(8.9, 0.05)
check(Places.QuestPosition(970) == nil and rebuilds == r, 'within 10 s of the miss: no rescan, no position (as 1.3.1)')
M.Tick(0.2, 0.05)
check(Text(Places.QuestPosition(970)) == Text(52, 0.45, 0.55) and rebuilds == r + 1, '10 s after the miss: rescanned and found')

-- 9. One quest-icon click: exactly one continent scan in the next 2 s, with
-- the game's super-tracking event before or after our click hook.
Quiet()
Quest(7010, { onMap = { [9035] = { 0.6, 0.4 } } })
ns.Set('followQuest', true)
M.Tick(1)
local n = Rebuilds(function()
    Track(7010)                -- the game super-tracks on the icon click
    Follow.TrackQuest(7010)    -- our post-hook
    Questing(2)
end)
check(n == 1 and Arrow() == Text(9035, 0.6, 0.4), 'icon click: one scan in 2 s (got ' .. n .. ')')
Quest(7011, { onMap = { [9036] = { 0.3, 0.3 } } })
n = Rebuilds(function()
    Follow.TrackQuest(7011)
    Track(7011)                -- event dispatched after the hook
    Questing(2)
end)
check(n == 1 and Arrow() == Text(9036, 0.3, 0.3), 'icon click, late event: one scan in 2 s (got ' .. n .. ')')
ns.Set('followQuest', false); M.Tick(1)
Quest(7012, { onMap = { [9037] = { 0.7, 0.2 } } })
n = Rebuilds(function()
    Follow.TrackQuest(7012)    -- overlay click; following off
    Questing(2)
end)
check(n == 1 and Arrow() == Text(9037, 0.7, 0.2), 'overlay click: one scan in 2 s (got ' .. n .. ')')

-- 9b. A super-tracking change that is not our click gets a fresh lookup,
-- even back to the same quest; the shared scan is young here.
Quiet()
ns.Set('followQuest', true)
Quest(7013)
Track(7013)
Questing(2)
Quest(7013, { onMap = { [9038] = { 0.15, 0.85 } } }) -- marker appears, nothing else
Places.GetAll(true)
n = Rebuilds(function()
    M.superTracked = 0; M.FireEvent('SUPER_TRACKING_CHANGED')
    M.superTracked = 7013; M.FireEvent('SUPER_TRACKING_CHANGED')
    Questing(0.5)
end)
check(n == 1 and Arrow() == Text(9038, 0.15, 0.85), 'untrack and retrack: fresh lookup finds the quest (got ' .. n .. ' scans)')
Quest(7014, { onMap = { [9039] = { 0.35, 0.65 } } })
Places.GetAll(true)
n = Rebuilds(function() Track(7014); Questing(0.5) end)
check(n == 1 and Arrow() == Text(9039, 0.35, 0.65), 'another super-tracked quest: one fresh scan')

-- 10. A scripted 300 s of play. Events at fixed times; lookups at random
-- times. Positions only move with an event.
local A, B, C, D = 7001, 7002, 7003, 7004
local OBJ = function(done, need) return { { numFulfilled = done, numRequired = need, finished = done >= need } } end
local function Move(cont, wx, wy) M.player.inst, M.player.wx, M.player.wy = cont, wx, wy end
local base
local function Reset()
    Quiet()
    Move(0, -600, -1200) -- Elwynn Forest
    M.FireEvent('PLAYER_ENTERING_WORLD')
    M.FireEvent('ZONE_CHANGED_NEW_AREA')
    for _, id in ipairs({ A, B, C, D }) do Drop(id) end
    Quest(C, { objectives = OBJ(0, 1), onMap = { [9010] = { 0.5, 0.25 } } })
    Quest(B, { objectives = OBJ(0, 1) })
    M.Tick(15, 0.5)
end
local function Accepted(id)
    M.FireEvent('QUEST_ACCEPTED', id)
    M.FireEvent('QUEST_LOG_UPDATE')
end
-- super: the quest the player tracks after this event (followed runs)
local EVENTS = {
    { 5, 'accept A (other zone)', function() Quest(A, { objectives = OBJ(0, 3), onMap = { [52] = { 0.33, 0.44 } } }); Accepted(A) end, { [A] = A } },
    { 40, 'A progresses, marker moves', function() Quest(A, { objectives = OBJ(1, 3), onMap = { [52] = { 0.35, 0.5 } } }); M.FireEvent('QUEST_LOG_UPDATE') end },
    { 80, 'A completes, turn-in elsewhere', function() Quest(A, { complete = true, objectives = OBJ(3, 3), onMap = { [84] = { 0.6, 0.7 } } }); M.FireEvent('QUEST_LOG_UPDATE') end },
    { 100, 'B progresses, still no position', function() Quest(B, { objectives = OBJ(1, 1), complete = true }); M.FireEvent('QUEST_LOG_UPDATE') end },
    { 120, 'zone change to Westfall', function() Move(0, -3000, -500); M.FireEvent('ZONE_CHANGED_NEW_AREA') end },
    { 150, 'abandon C', function() Drop(C); M.FireEvent('QUEST_LOG_UPDATE') end, { [C] = 0 } },
    { 170, 're-accept C (marker elsewhere)', function() Quest(C, { objectives = OBJ(0, 1), onMap = { [9020] = { 0.75, 0.5 } } }); Accepted(C) end, { [C] = C } },
    { 190, 'teleport to Durotar (loading screen only)', function() Move(1, -1000, -4500); M.FireEvent('PLAYER_ENTERING_WORLD') end },
    { 200, 'accept D (Kalimdor, other zone)', function() Quest(D, { objectives = OBJ(0, 2), onMap = { [1411] = { 0.4, 0.6 } } }); Accepted(D) end, { [D] = D } },
    { 230, 'D progresses onto the current map', function() Quest(D, { objectives = OBJ(1, 2), onMap = { [1] = { 0.2, 0.3 } } }); M.FireEvent('QUEST_LOG_UPDATE') end },
    { 250, 'teleport back to Elwynn (loading screen only)', function() Move(0, -600, -1200); M.FireEvent('PLAYER_ENTERING_WORLD') end },
    { 270, 'abandon A', function() Drop(A); M.FireEvent('QUEST_LOG_UPDATE') end, { [A] = 0 } },
    { 285, 're-accept A', function() Quest(A, { objectives = OBJ(0, 3), onMap = { [52] = { 0.33, 0.44 } } }); Accepted(A) end, { [A] = A } },
}
local QUESTS = { A, B, C, D, 101, 102 }
math.randomseed(1311)
local SCHEDULE, t = {}, 0
while true do
    t = t + math.random(1, 12) * 0.25
    if t >= 300 then break end
    SCHEDULE[#SCHEDULE + 1] = { t = t, q = QUESTS[math.random(1, #QUESTS)] }
end

-- Runs the script; every 0.25 s step applies due events, then calls
-- each(t, events applied this step).
local function Play(each, followed)
    Reset()
    local e, start = 1, M.now
    if followed and followed ~= A and followed ~= D then ns.Set('followQuest', true); Track(followed) end
    for step = 1, 1200 do
        local now = step * 0.25
        while EVENTS[e] and EVENTS[e][1] <= now do
            EVENTS[e][3]()
            local super = followed and EVENTS[e][4] and EVENTS[e][4][followed]
            if super then ns.Set('followQuest', true); Track(super) end
            e = e + 1
        end
        M.Tick(0.25, 0.25)
        each(now, M.now - start)
    end
end

-- The 1.3.1 Places.QuestPosition, verbatim apart from its own Call.
local function Released()
    local questMiss = {}
    local function Call(fn, ...)
        if type(fn) ~= "function" then
            return nil
        end
        local ok, a, b, c, d = pcall(fn, ...)
        if ok then
            return a, b, c, d
        end
    end
    return function(questID)
        if not questID or questID == 0 then
            return nil
        end
        local current = C_Map.GetBestMapForUnit("player")
        if current and C_QuestLog and C_QuestLog.GetQuestsOnMap then
            local quests = Call(C_QuestLog.GetQuestsOnMap, current)
            if type(quests) == "table" then
                for _, q in ipairs(quests) do
                    if q.questID == questID and ns.Num(q.x) and ns.Num(q.y) then
                        return current, q.x, q.y
                    end
                end
            end
        end
        local m, x, y = Call(C_QuestLog and C_QuestLog.GetNextWaypoint, questID)
        if m and ns.Num(x) and ns.Num(y) then
            return m, x, y
        end
        if (questMiss[questID] or 0) > GetTime() then
            return nil
        end
        for _, p in ipairs(Places.GetAll(true)) do
            if p.questID == questID then
                return p.m, p.x, p.y
            end
        end
        questMiss[questID] = GetTime() + 10
    end
end

-- 10a. Default lookups: same answer and same scan count at every call.
local function Transcript(lookup)
    local out, i, r0 = {}, 1, rebuilds
    Play(function(now)
        while SCHEDULE[i] and SCHEDULE[i].t <= now do
            out[#out + 1] = ('%6.2f %d %s scans=%d'):format(SCHEDULE[i].t, SCHEDULE[i].q, Text(lookup(SCHEDULE[i].q)), rebuilds - r0)
            i = i + 1
        end
    end)
    return out
end
local want = Transcript(Released())
local got = Transcript(function(id) return Places.QuestPosition(id) end)
local same, firstDiff = #want == #got, nil
for k = 1, math.max(#want, #got) do
    if want[k] ~= got[k] then same, firstDiff = false, firstDiff or k end
end
print(('scripted 300 s, default lookups: %d calls, %s positions, released %s, now %s')
    :format(#got, (function() local c = 0; for _, l in ipairs(got) do if not l:find(' nil ') then c = c + 1 end end; return c end)(),
        want[#want] and want[#want]:match('scans=%d+') or '-', got[#got] and got[#got]:match('scans=%d+') or '-'))
check(same, 'default lookups match 1.3.1 call for call' .. (firstDiff and (' (first difference: ' .. tostring(want[firstDiff]) .. ' / ' .. tostring(got[firstDiff]) .. ')') or ''))
if os.getenv('WT_TRANSCRIPT') then for _, l in ipairs(got) do print(l) end end

-- 10b. Automatic following of each quest through the same script: every
-- automatic lookup answers what the game shows at that moment, so the
-- arrow is right no later than the next update after each event.
local function Truth(id)
    local q
    for _, entry in ipairs(M.quests) do if entry.id == id then q = entry end end
    if not q then return nil end
    local current = C_Map.GetBestMapForUnit('player')
    local onMap = q.onMap or {}
    if current and onMap[current] then return current, onMap[current][1], onMap[current][2] end
    if q.next then return q.next[1], q.next[2], q.next[3] end
    local cont = current and Geo.ContinentOf(current)
    for _, z in ipairs(Geo.GetZoneList()) do
        if cont and z.continent == cont and z.mapType == 3 and onMap[z.id] then return z.id, onMap[z.id][1], onMap[z.id][2] end
    end
end
local lookup = Places.QuestPosition
local watching, wrong, asked, firstWrong
Places.QuestPosition = function(id, ...)
    local fromFollow = false
    for level = 2, 4 do
        local info = debug.getinfo(level, 'S')
        if info and info.source:find('Follow.lua', 1, true) then fromFollow = true end
    end
    local m, x, y = lookup(id, ...)
    if watching and fromFollow and id == watching then
        asked = asked + 1
        if Text(m, x, y) ~= Text(Truth(id)) then
            wrong = wrong + 1
            firstWrong = firstWrong or ('%s got %s, game shows %s'):format(id, Text(m, x, y), Text(Truth(id)))
        end
    end
    return m, x, y
end
for _, id in ipairs({ A, B, C, D }) do
    watching, wrong, asked, firstWrong = id, 0, 0, nil
    local r0 = rebuilds
    Play(function() M.FireEvent('QUEST_LOG_UPDATE') end, id)
    print(('followed %d through the script: %d automatic lookups, %d continent scans, %d stale answers')
        :format(id, asked, rebuilds - r0, wrong))
    check(asked > 100 and wrong == 0, ('followed %d: every automatic lookup matches the game (%s)'):format(id, firstWrong or 'ok'))
end
watching = nil
Places.QuestPosition = lookup
Quiet()

check(#M.errors == 0, 'no reported Lua errors')
for _, message in ipairs(M.errors) do print(message) end
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and #M.errors == 0 and 0 or 1)
