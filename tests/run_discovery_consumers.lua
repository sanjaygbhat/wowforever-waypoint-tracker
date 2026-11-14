-- Compaction compares outputs before/after removal, including cold tickers.
package.path='./tests/?.lua;'..package.path
local M=require('wowmock')
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN');assert(ns.DB.Load())
local DB,Learn=ns.DB,ns.Learn
UnitFactionGroup=function()return 'Alliance'end
-- Empty query lists own mutable caches; immutable empty shipped facts do not.
local first={kind='npc',id=995901,name='First empty service',fac='A',points={{m=37,x=.4,y=.4}}}
local second={kind='npc',id=995902,name='Second empty service',fac='A',points={{m=37,x=.6,y=.6}}}
DB.services.empty_first={{entry=first,fac='A'}}
DB.services.empty_second={{entry=second,fac='A'}}
assert(DB.ServiceEntries('empty_first')[1]==first)
assert(DB.ServiceEntries('empty_second')[1]==second,'empty services must not share query results')
local snapshot=DB.Snapshot({kind='npc',id=995903,name='No services',fac='A'})
assert(not next(snapshot.services),'query cache metadata must never become shipped service evidence')
DB.services.empty_first,DB.services.empty_second=nil,nil
local id=995000
local function candidate(coords,spots)
    id=id+1
    local e={kind='npc',id=id,name='Consumer '..id,key='consumer '..id,fac='A',coords=coords}
    DB.units[id]=e
    local value={name=e.name,hostile=false,fac='A',spots={[37]=spots}}
    return e,value
end
local e,v=candidate('12:500,500',{.6,.5})
assert(DB.AddsSomething('npc',id,v,true),'a new coordinate changes navigation')
v.spots[37][1]=.5
assert(not DB.AddsSomething('npc',id,v,true),'in-place position updates invalidate the comparison cache')
v.spots[37][1]=.6
assert(DB.AddsSomething('npc',id,v,true),'a second in-place update is also checked')
e,v=candidate('12:500,500,800,800',{.5,.5})
assert(DB.AddsSomething('npc',id,v,true),'one observation suppresses the second static spawn')
e,v=candidate('12:500,500,800,800,900,900',{.5,.5})
assert(not DB.AddsSomething('npc',id,v,true),'an identical first spawn with no suppression is redundant')
for _,service in ipairs({'trainer_weapon','trainer_riding','trainer_class_priest','trainer_profession_alchemy','trainer_pet_hunter'}) do
    e,v=candidate('12:500,500',{.5,.5})
    WaypointTrackerData.trainers=service..'\t'..id..':A'
    WaypointTrackerData.trainerLocations=id..'\tTeacher\t37:0.8,0.8\tobserved'
    assert(DB.AddsSomething('npc',id,v,true),service..' passive override must survive')
    WaypointTrackerData.trainerLocations=id..'\tTeacher\t37:0.501,0.5\tobserved'
    assert(DB.AddsSomething('npc',id,v,true),service..' a nearby trainer override still changes navigation')
    WaypointTrackerData.trainerLocations=id..'\tTeacher\t37:0.5,0.5\tobserved'
    assert(not DB.AddsSomething('npc',id,v,true),service..' unchanged effective position is redundant')
    e.fixes={{wrong={37,.5,.5}}}
    assert(not DB.AddsSomething('npc',id,v,true),'a removed point is absent on both paths')
end
-- Unavailable roster maps are uncertainty, never proof of redundancy.
e,v=candidate('12:500,500',{.5,.5})
WaypointTrackerData.trainers='trainer_weapon\t'..id..':A'
WaypointTrackerData.trainerLocations=id..'\tDelayed teacher\t37:0.5,0.5\tobserved'
local valid=ns.Geo.IsValidMap
ns.Geo.IsValidMap=function()return false end
local adds,deferred=DB.AddsSomething('npc',id,v,true)
assert(adds and deferred,'unresolved trainer comparison must stay queued')
ns.Geo.IsValidMap=valid
assert(not DB.AddsSomething('npc',id,v,true),'resolved equal trainer points can compact without new learning')
-- A passive flight sighting suppresses a distinct nearby client taxi label,
-- even when its normal and supplemental positions are otherwise identical.
local supplement,flights=WaypointTrackerData.serviceSupplement,DB.services.flight
e,v=candidate('12:500,500',{.5,.5})
local c,wx,wy=ns.Geo.MapToWorld(37,.501,.5)
local alias={kind='place',id=-995000,name='Nearby taxi label',fac='A',world={{c,37,wx,wy}}}
DB.services.flight={{id=e.id,fac='A'},{entry=alias,fac='A'}}
WaypointTrackerData.serviceSupplement=table.concat({'SN',e.id,'A',e.name,'flight','R','37:0.5,0.5,0'},'\t')
assert(DB.AddsSomething('npc',e.id,v,true),'taxi-label suppression is a consumer output too')
Learn.Store().npcs[e.id]=v
DB.MergeLearned()
assert(Learn.Store().npcs[e.id],'passive flight observation must stay saved')
for _,entry in ipairs(DB.ServiceEntries('flight'))do assert(entry~=alias,'observation suppresses taxi alias')end
Learn.Store().npcs[e.id]=nil;DB.MergeLearned()
local restored=false
for _,entry in ipairs(DB.ServiceEntries('flight'))do if entry==alias then restored=true end end
assert(restored,'removing the observation really changes the flight candidates')
WaypointTrackerData.serviceSupplement,DB.services.flight=supplement,flights
-- Queries must merge new observations, while compaction stays on the ticker.
local compact=Learn.Compact
Learn.Compact=function(all)assert(not all,'navigation must never force full compaction');return compact(all)end
M.units.npc={guid='Creature-0-1-2-3-995999-ABC',name='Queued merchant',reaction=5,level=10,faction='Alliance'}
Learn.Unit('npc','vendor');M.Tick(5.1,5.1)
assert(ns.Find.GoToNearest('vendor'))
Learn.Compact=compact
-- The client's millisecond clock can shorten a slice further than its
-- record cap, including an unreadable or reset clock.
local adds=DB.AddsSomething
local checked=0
DB.AddsSomething=function(...)checked=checked+1;return adds(...)end
for i=1,5 do
    local e,value=candidate('12:500,500',{.5,.5})
    M.units.npc={guid='Creature-0-1-2-3-'..e.id..'-ABC',name=e.name,reaction=5,level=10,faction='Alliance'}
    M.player.inst,M.player.wx,M.player.wy=ns.Geo.MapToWorld(37,.5,.5)
    Learn.Unit('npc')
end
local clock=debugprofilestop
local ms=0;debugprofilestop=function()ms=ms+1;return ms end
Learn.Compact();assert(checked==2,'client clock stops the slice at two milliseconds')
checked=0;debugprofilestop=function()ms=ms-1;return ms end
Learn.Compact();assert(checked==1,'a reset clock ends the slice')
checked=0;debugprofilestop=function()return nil end
Learn.Compact();assert(checked==2,'an unavailable clock keeps the record cap and drains the remainder')
debugprofilestop=clock;DB.AddsSomething=adds
assert(#M.errors==0,table.concat(M.errors,'\n'))
print('Discovery consumers: position changes, suppression, mutable cache, all trainer paths, bounded query merge passed')
