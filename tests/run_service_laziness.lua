-- Requesting one service must not materialize another service's positions.
package.path='./tests/?.lua;'..package.path
local M=require('wowmock')
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
assert(ns.DB.Load())
local c=ns.Geo.MapToWorld(37,.5,.5)
local positions=string.rep('37:0.5,0.5,'..c..';',20000)
WaypointTrackerData.serviceSupplement='SN\t995001\tAH\tUnrequested vendor\tvendor\tR\t'..positions..'\nSN\t995002\tAH\tBanker\tbanker\tR\t37:0.5,0.5,'..c
collectgarbage('collect');local memory=collectgarbage('count')
local entries=ns.DB.ServiceEntries('banker');assert(entries[1].id==995002)
collectgarbage('collect');local growth=collectgarbage('count')-memory
assert(growth<256,'request retained unrequested service positions: '..growth..' KiB')
assert(WaypointTrackerData.serviceSupplement,'raw facts remain available for compaction')
local first=entries[1]
local t=os.clock()
for i=1,100 do assert(ns.DB.ServiceEntries('banker')[1]==first) end
assert((os.clock()-t)*10<3,'warm service requests exceed 3 ms')
assert(#M.errors==0)
print(('Service laziness: unrelated positions remain raw (%.1f KiB retained)'):format(growth))
