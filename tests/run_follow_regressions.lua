-- Clicked quest updates, abandonment and resurrection regression scenarios.
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
M.Tick(1)
local WP, T = ns.WP, ns.Travel
local mode = arg[1] or 'preference'
local failed = 0
local function check(ok, why)
    print((ok and 'PASS: ' or 'FAIL: ') .. why)
    if not ok then failed = failed + 1 end
end
local wp = assert(ns.Follow.TrackQuest(101))
if mode == 'preference' then
    ns.TravelData = { areas = {'test'}, indoor = {}, nodes = '', links = '',
        maps = '37\t1', regions = '', cities = '', towns = '', levels = '', factors = '' }
    T._Reset()
    ns.Set('realRoutes', true)
    ns.Set('travelHearth', false)
    local choices, chosen = T.Choices(wp)
    assert(chosen and #choices == 2 and #chosen.path == 2, 'safe/fast direct walking candidates required')
    chosen.preference = 'fastest'
    T.Select(wp, chosen)
    assert(wp.travelPreference == 'fastest' and wp.travelChosen)
    M.quests[1].onMap[37] = {.44, .82}
    M.FireEvent('QUEST_LOG_UPDATE')
    M.Tick(.7)
    local nextWP = WP.GetActive()
    assert(nextWP and nextWP.x == .44, 'quest position must update')
    check(nextWP.travelPreference == 'fastest' and nextWP.travelChosen,
        'quest location update preserves explicit travel preference (actual: ' .. tostring(nextWP.travelPreference) .. ')')
elseif mode == 'abandon' then
    table.remove(M.quests, 1)
    assert(C_QuestLog.GetLogIndexForQuestID(101) == nil)
    M.FireEvent('QUEST_LOG_UPDATE')
    M.Tick(.7)
    check(not WP.IsValid(wp) and ns.Follow.GetTrackedQuestID() == nil,
        'abandoning clicked quest removes its stale waypoint (actual tracked: ' .. tostring(ns.Follow.GetTrackedQuestID()) .. ')')
elseif mode == 'ghost' or mode == 'ghost_arrival' or mode == 'ghost_arrival_selection' then
    local m, x, y = ns.Geo.GetPlayerMapPosition()
    local other = assert(WP.Add(m, x, y, {title='Near death', silent=true, setActive=false}))
    M.player.dead = true
    M.FireEvent('PLAYER_DEAD')
    assert(WP.GetActive().source == 'corpse', 'corpse owns arrow')
    M.player.ghost = true
    M.quests[1].onMap[37] = {.44, .82}
    M.FireEvent('QUEST_LOG_UPDATE')
    M.Tick(.7)
    assert(not WP.IsValid(wp), 'quest update replaced beforeDeath object')
    assert(WP.GetActive().source == 'corpse', 'corpse still owns arrow')
    if mode ~= 'ghost' then
        local corpse = WP.GetActive()
        WP.CheckArrival(corpse, 100)
        assert(WP.CheckArrival(corpse, 0) and not WP.IsValid(corpse), 'arrival auto-clears the corpse pin')
        check(WP.GetActive() and WP.GetActive().source == 'quest', 'corpse arrival restores the updated quest before automatic nearest selection')
        if mode == 'ghost_arrival_selection' then WP.SetActive(other, true) end
    end
    M.player.dead, M.player.ghost = false, false
    M.FireEvent('PLAYER_UNGHOST')
    if mode == 'ghost_arrival_selection' then
        check(WP.GetActive() == other, 'resurrection preserves a deliberate selection after corpse arrival')
    else
        check(WP.GetActive() and WP.GetActive().source == 'quest',
            'resurrection restores updated clicked quest (actual: ' .. tostring(WP.GetActive() and WP.GetActive().title) .. ')')
    end
else
    error('unknown scenario')
end
check(#M.errors == 0, 'no unrelated Lua errors: ' .. tostring(M.errors[1]))
os.exit(failed == 0 and 0 or 1)
