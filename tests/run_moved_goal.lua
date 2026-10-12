-- Independent review: explicit itinerary retention must honor waypoint moves.
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN')
ns.TravelData = { areas={'test'}, indoor={}, nodes='', links='', maps='37\t1',
    regions='', cities='', towns='', levels='', factors='' }
local T, WP = ns.Travel, ns.WP
T._Reset(); ns.Set('realRoutes',true); ns.Set('travelHearth',false)
local failed = 0
for _, preference in ipairs({'safer','fastest'}) do
    WP.ClearAll(true);ns.Set('travelPreference',preference)
    local wp = assert(WP.Add(37,.8,.5,{title='Moving destination',silent=true}))
    local _, choice = T.Choices(wp)
    assert(choice); T.Select(wp,choice)
    assert(T.Current().path[#T.Current().path].node.x == .8)
    assert(WP.Move(wp,37,.9,.5))
    for _, seconds in ipairs({3,30,300}) do
        M.now = M.now + seconds
        T.Steer(wp)
        local p = assert(T.Current())
        local target = p.path[#p.path].node.x
        if target ~= wp.x then
            failed = failed + 1
            print('FAIL: '..preference..' after ' .. seconds .. 's, planner goal=' .. target .. ', waypoint=' .. wp.x)
        end
    end
end
assert(#M.errors == 0, tostring(M.errors[1]))
os.exit(failed == 0 and 0 or 1)
