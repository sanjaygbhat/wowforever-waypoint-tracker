package.path='./tests/?.lua;'..package.path
local M=require('wowmock')
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
assert(ns.DB.Load())
local supplement={WaypointTrackerData.serviceSupplement or ""}
for i=1,1000 do
    local id=992000+i
    local name='Budget '..i
    ns.DB.units[id]={kind='npc',id=id,name=name,key=ns.Geo.Squash(name),fac='A',coords='12:500,500',svc={vendor=true}}
    supplement[#supplement+1]=table.concat({'SN',id,'A',name,'vendor','R','37:0.5,0.5,0'},'\t')
    M.units.npc={guid='Creature-0-1-2-3-'..id..'-ABC',name='Budget '..i,reaction=5,level=10}
    ns.Learn.Unit('npc','vendor')
end
WaypointTrackerData.serviceSupplement=table.concat(supplement,'\n')
local mapForArea=ns.DB.MapForArea
ns.DB.MapForArea=function(area,treeOnly)
    if treeOnly and area==12 then return nil end
    return mapForArea(area,treeOnly)
end
local adds=ns.DB.AddsSomething
local checked,total,worst,ticks=0,0,0,0
ns.DB.AddsSomething=function(...)
    checked=checked+1;total=total+1
    return adds(...)
end
local compact=ns.Learn.Compact
ns.Learn.Compact=function(all)
    checked=0
    local start=os.clock()
    local n=compact(all)
    worst=math.max(worst,(os.clock()-start)*1000)
    assert(not all and checked<=20,'ticker compaction must process at most 20 records')
    ticks=ticks+1
    return n
end
for i=1,72 do M.Tick(5.1,5.1) end
assert(total==1080 and ticks==72,'unresolved records stay queued and retry within the same budget: '..total..' / '..ticks)
assert(worst<=5,'compaction tick exceeded 5 ms: '..worst)
assert(#M.errors==0,table.concat(M.errors,'\n'))
print(('Compaction cold budget: 1000 NPCs, %d ticks, max %.3f ms'):format(ticks,worst))
ns.DB.MapForArea=mapForArea
for i=1,1000 do
    local id=992000+i
    assert(ns.Learn.Store().npcs[id],'cold ticker must keep deferred observations')
    assert(not ns.DB.units[id].ship,'cold ticker must not build shipped facts')
    ns.DB.Points(ns.DB.units[id]) -- explicit query warms geography outside the ticker
end
total,ticks,worst=0,0,0
for i=1,72 do M.Tick(5.1,5.1) end
assert(total==1000 and ticks==67,'deferred records must drain without another observation; no idle compaction')
assert(worst<=5,'warm compaction tick exceeded 5 ms: '..worst)
assert(#M.errors==0,table.concat(M.errors,'\n'))
print(('Compaction warm budget: 1000 NPCs, %d ticks, max %.3f ms'):format(ticks,worst))

-- An entry point-cache may be cleared by a merge while its map stays warm.
-- Known raw sightings must still compact on the normal five-second ticker.
ns.DB.AddsSomething=adds;ns.Learn.Compact=compact
local e=assert(ns.DB.units[60])
e.points=nil;e.ship=ns.DB.Snapshot(e,false)
M.player.inst,M.player.wx,M.player.wy=ns.Geo.MapToWorld(37,.646,.567)
M.units.npc={guid='Creature-0-1-2-3-60-ABC',name='Ruklar the Trapper',reaction=2,level=10}
ns.Learn.Unit('npc')
assert(ns.Learn.Store().npcs[60],'known sighting starts in SavedVariables')
M.Tick(5.1)
assert(not ns.Learn.Store().npcs[60],'warm-map sightings compact even without entry.points')
assert(#M.errors==0,table.concat(M.errors,'\n'))
print('Warm-map reconciliation keeps the existing five-second behavior')

-- Explicit compaction must also preserve deferred work for a later ticker.
local id=994001
ns.DB.units[id]={kind='npc',id=id,name='Deferred full',key='deferred full',fac='A',coords='12:500,500'}
M.player.inst,M.player.wx,M.player.wy=ns.Geo.MapToWorld(37,.5,.5)
M.units.npc={guid='Creature-0-1-2-3-'..id..'-ABC',name='Deferred full',reaction=5,level=10,faction='Alliance'}
ns.Learn.Unit('npc')
ns.DB.MapForArea=function(area,treeOnly)if area~=12 then return mapForArea(area,treeOnly)end end
ns.Learn.Compact(true)
assert(ns.Learn.Store().npcs[id],'full compaction must keep unavailable areas')
ns.DB.MapForArea=mapForArea
for i=1,72 do M.Tick(5.1,5.1) end
assert(not ns.Learn.Store().npcs[id],'full-compaction deferrals must retry without a new observation')
assert(#M.errors==0,table.concat(M.errors,'\n'))
print('Explicit compaction deferrals also reconcile on the bounded ticker')
