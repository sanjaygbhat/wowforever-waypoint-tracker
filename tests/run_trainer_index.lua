-- Trainer supplements are indexed once on demand and invalidated by merges.
package.path='./tests/?.lua;'..package.path
local M=require('wowmock')
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local DB=ns.DB
local original=ns.Trainers.Index
local calls=0
ns.Trainers.Index=function(...) calls=calls+1;return original(...) end
assert(calls==0 and not DB.loaded,'login never indexes or loads trainer data')
assert(#DB.TrainerEntries('invented')==0 and calls==0,'invalid services do not parse')
assert(DB.Load());assert(calls==0,'data load itself does not parse trainers')
local roster,locations=WaypointTrackerData.trainers,WaypointTrackerData.trainerLocations
WaypointTrackerData.trainers='trainer_weapon\t991001:AH,991002:,991003:H\ntrainer_profession_alchemy\t991004:A'
WaypointTrackerData.trainerLocations='991001\tTeacher\t37:0.5,0.5\n991004\tAlchemist\t37:0.4,0.4'
UnitFactionGroup=function()return 'Alliance'end
local first=DB.TrainerEntries('trainer_weapon');assert(#first==1 and first[1].id==991001)
local index=ns.Trainers.Index(DB.generation)
assert(#index.services.trainer_weapon==3 and index.positions[991001])
assert(index.members[991001] and index.members[991004] and not index.members[991099],
    "discovery comparisons reuse exact roster membership")
for i=1,100 do
 local entries=DB.TrainerEntries('trainer_weapon')
 assert(entries[1]==first[1] and ns.Trainers.Index(DB.generation)==index,'warm requests reuse parsed text and resolved fallback')
end
assert(#DB.TrainerEntries('trainer_profession_alchemy')==1,'per-service index is complete')
WaypointTrackerData.trainerLocations='991001\tChanged\t37:0.8,0.8'
assert(ns.Trainers.Index(DB.generation)~=index,'replaced source strings invalidate same generation')
local index2=ns.Trainers.Index(DB.generation)
DB.MergeLearned()
assert(ns.Trainers.Index(DB.generation)~=index2,'merge generation invalidates derived entries')
ns.Learn.Import('WTL1\tenUS\t1\nN\t991001\tPersonal teacher\t0\t60\ttrainer_weapon\t37:900,900\tA')
DB.MergeLearned()
local learned=DB.TrainerEntries('trainer_weapon')[1]
assert(learned.name=='Personal teacher' and DB.Points(learned)[1].x==.9,'new learning supersedes cached fallback')
-- Newest shipped observations can replace a raw point without changing Find's
-- database identity. All correction sources and actual learned spots still win.
for _,source in ipairs({'curated','community','learned'}) do
 local id=991101
 DB.curated={npcs={},objects={},quests={},items={},mailboxes={},fixes={}}
 DB.community={npcs={},objects={},quests={},items={},mailboxes={},fixes={}}
 WaypointTrackerDB.learned={npcs={},objects={},quests={},items={},mailboxes={},fixes={}}
 local store=ns.Learn.Store()
 DB.units[id]={kind='npc',id=id,fac='A',name='Raw',points={{m=37,x=.1,y=.1}}}
 WaypointTrackerData.trainers='trainer_weapon\t'..id..':A'
 WaypointTrackerData.trainerLocations=id..'\tObserved\t37:0.8,0.8\tobserved'
 DB.MergeLearned()
 local entry=DB.TrainerEntries('trainer_weapon')[1]
 assert(DB.Points(entry)[1].x==.8,'newest position replaces raw trainer coordinates')
 assert(DB.Points(DB.units[id])[1].x==.1,'trainer overrides do not mutate general Find positions')
 local target=source=='learned' and store or DB[source]
 target.fixes['N'..id]={{wrong={37,.8,.8},right={37,.9,.9}}}
 DB.MergeLearned()
 entry=DB.TrainerEntries('trainer_weapon')[1]
 assert(#DB.Points(entry)==1 and DB.Points(entry)[1].x==.9,source..' replacement survives observed override')
 target.fixes['N'..id]={{wrong={37,.8,.8}}}
 DB.MergeLearned()
 assert(#DB.TrainerEntries('trainer_weapon')==0,source..' removed observation is never revived')
 target.fixes['N'..id]=nil
 store.npcs[id]={name='Personal',fac='A',spots={[37]={.6,.6}}}
 DB.MergeLearned()
 entry=DB.TrainerEntries('trainer_weapon')[1]
 assert(entry==DB.units[id] and entry.name=='Personal' and DB.Points(entry)[1].x==.6,'actual learned position retains normal precedence')
 store.npcs[id].hostile=true;DB.MergeLearned()
 assert(#DB.TrainerEntries('trainer_weapon')==0,'hostility still excludes observed coordinates')
 DB.units[id]=nil
end
-- Pet trainers are shipped and indexed for database consumers, without a TOC
-- addition or mixing them into the hunter class-trainer button.
WaypointTrackerData.trainers='trainer_pet_hunter\t991500:AH'
WaypointTrackerData.trainerLocations='991500\tPet teacher\t37:0.5,0.5'
assert(ns.Trainers.IsService('trainer_pet_hunter'))
assert(DB.TrainerEntries('trainer_pet_hunter')[1].id==991500)
assert(#DB.TrainerEntries('trainer_class_hunter')==0)
-- Separately pinned player coordinates use the same observation precedence.
WaypointTrackerData.trainers='trainer_weapon\t991600:AH'
WaypointTrackerData.trainerLocations='991600\tPlayer observation\t37:0.8,0.8\tplayer'
DB.units[991600]={kind='npc',id=991600,fac='AH',name='Raw',points={{m=37,x=.1,y=.1}}}
DB.MergeLearned()
assert(DB.Points(DB.TrainerEntries('trainer_weapon')[1])[1].x==.8)
ns.Learn.Store().npcs[991600]={name='Personal',fac='AH',spots={[37]={.6,.6}}}
DB.MergeLearned()
assert(DB.Points(DB.TrainerEntries('trainer_weapon')[1])[1].x==.6)
DB.units[991600]=nil
-- A temporarily unavailable client map must recover without reparsing text or
-- waiting for an unrelated learned-data generation change.
WaypointTrackerData.trainers='trainer_weapon\t991700:AH'
WaypointTrackerData.trainerLocations='991700\tDelayed map\t37:0.7,0.7'
local validMap=ns.Geo.IsValidMap
local mapReady=false
ns.Geo.IsValidMap=function(m)return mapReady and validMap(m)end
assert(#DB.TrainerEntries('trainer_weapon')==0)
local delayedIndex=ns.Trainers.Index(DB.generation)
mapReady=true
assert(#DB.TrainerEntries('trainer_weapon')==1,'map-info recovery resolves pending fallback')
assert(ns.Trainers.Index(DB.generation)==delayedIndex,'map recovery reuses parsed index')
ns.Geo.IsValidMap=validMap
WaypointTrackerData.trainers,WaypointTrackerData.trainerLocations=roster,locations
assert(#M.errors==0)
print('Trainer index: lazy parsing, reuse, source replacement and generation invalidation passed')
