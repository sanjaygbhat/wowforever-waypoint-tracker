-- Every service source, access shape, hostility and correction source.
package.path='./tests/?.lua;'..package.path
local M=require('wowmock')
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local DB,Learn=ns.DB,ns.Learn
assert(DB.Load())
local passed,failed=0,0
local function check(ok,label)
 if ok then passed=passed+1 else failed=failed+1;if failed<30 then print('FAIL '..label) end end
end
local side='Alliance';UnitFactionGroup=function()return side end
local function empty()return {npcs={},objects={},items={},quests={},mailboxes={},fixes={}} end
local mapForArea=DB.MapForArea
DB.MapForArea=function(area)if area==12 then return 37 end return mapForArea(area) end
local cont=ns.Geo.MapToWorld(37,.5,.5)
local id=993000
local function contains(fac,letter)return fac:find(letter,1,true)~=nil end
local function find(service,id,kind)
 for _,e in ipairs(DB.ServiceEntries(service))do if e.id==id and e.kind==kind and #DB.Points(e)>0 then return e end end
end
for _,kind in ipairs({'npc','object'})do
 for _,source in ipairs({'base','supplement','personal','imported','correction-add','correction-remove'})do
  for _,shipFac in ipairs({'','A','H','AH'})do
   for _,observedFac in ipairs({'','A','H','AH'})do
    for _,hostility in ipairs({'unknown','friendly','hostile'})do
     id=id+1;side='Alliance'
     DB.curated,DB.community=empty(),empty();WaypointTrackerDB.learned=empty()
     local st=Learn.Store();local group=kind=='npc' and 'npcs' or 'objects'
     local tbl=kind=='npc' and DB.units or DB.objects
     local hostile=hostility=='hostile' and true or nil
     if hostility=='friendly' then hostile=false end
     tbl[id]={kind=kind,id=id,name='Localized base',fac=shipFac,coords='12:100,100',hostile=kind=='npc' and hostile or nil}
     DB.services.vendor={{id=kind=='npc' and id or -id,fac=shipFac}}
     WaypointTrackerData.serviceSupplement=source=='base' and '' or table.concat({kind=='npc' and 'SN' or 'SO',id,shipFac,'Supplement','vendor','R','37:0.5,0.5,'..cont},'\t')
     local personal=source=='personal' or source=='imported'
     if personal then
      st[group][id]={name='Observed',fac=observedFac~='' and observedFac or nil,hostile=kind=='npc' and hostile or nil,
       shared=source=='imported' or nil,services={vendor=true},spots={[37]={.8,.8}}}
     elseif source=='correction-add' or source=='correction-remove' then
      st.fixes[(kind=='npc' and 'N' or 'O')..id]={{wrong={37,.5,.5},right=source=='correction-add' and {37,.9,.9} or nil}}
     end
     DB.MergeLearned()
     for _,faction in ipairs({'Alliance','Horde'})do
      side=faction;local letter=side:sub(1,1)
      local expected=source=='base' and (shipFac=='' or contains(shipFac,letter)) or contains(shipFac,letter)
      if personal then expected=expected or contains(observedFac=='' and (kind=='object' and 'AH' or 'A') or observedFac,letter) end
      expected=expected and not(kind=='npc' and hostility=='hostile') and source~='correction-remove'
      local e=find('vendor',id,kind)
      local label=table.concat({kind,source,shipFac,observedFac,hostility,faction},'/')
      check((e~=nil)==expected,label..' availability')
      if e then
       local wanted=personal and .8 or source=='base' and .1 or source=='correction-add' and .9 or .5
       local pts=DB.Points(e)
       check(#pts==1 and pts[1].x==wanted,label..' points')
       check(DB.ForMyFaction(e),label..' effective faction')
      end
     end
     tbl[id]=nil
    end
   end
  end
 end
end
-- Corrections apply to supplement-only identities from all three overlays.
for _,kind in ipairs({'npc','object'})do
 for _,source in ipairs({'curated','community','personal'})do
  for _,replacement in ipairs({false,true})do
   id=id+1;side='Alliance'
   DB.curated,DB.community=empty(),empty();WaypointTrackerDB.learned=empty()
   local st=Learn.Store();local target=source=='personal' and st or DB[source]
   target.fixes[(kind=='npc' and 'N' or 'O')..id]={{wrong={37,.5,.5},right=replacement and {37,.9,.9} or nil}}
   WaypointTrackerData.serviceSupplement=table.concat({kind=='npc' and 'SN' or 'SO',id,'AH','Only supplement','vendor','R','37:0.5,0.5,'..cont},'\t')
   DB.services.vendor={};DB.MergeLearned()
   local e=find('vendor',id,kind)
   check((e~=nil)==replacement,kind..'/'..source..' correction without base')
   if e then check(DB.Points(e)[1].x==.9,kind..'/'..source..' replacement') end
  end
 end
end
-- Snapshot facts must never absorb personal or imported service/position data.
for _,shared in ipairs({false,true})do
 id=id+1;DB.curated,DB.community=empty(),empty();WaypointTrackerDB.learned=empty()
 local st=Learn.Store();DB.services.vendor={};WaypointTrackerData.serviceSupplement=''
 st.npcs[id]={name='Discovery',fac='AH',shared=shared or nil,services={vendor=true},spots={[37]={.8,.8}}}
 DB.MergeLearned()
 check(st.npcs[id] and DB.AddsSomething('npc',id,st.npcs[id]),'discovery never becomes shipped '..tostring(shared))
end
-- Supplement hostility/access deltas survive compaction and a fresh identity.
for _,hostile in ipairs({false,true})do
 id=id+1;side='Horde';DB.curated,DB.community=empty(),empty();WaypointTrackerDB.learned=empty()
 local st=Learn.Store();DB.services.vendor={}
 WaypointTrackerData.serviceSupplement=table.concat({'SN',id,'A','Shipped','vendor','R','37:0.5,0.5,'..cont},'\t')
 st.npcs[id]={name='Live',fac='H',hostile=hostile,services={vendor=true},spots={[37]={.5,.5}}}
 DB.MergeLearned();Learn.Compact(true)
 check(st.npcs[id]~=nil,'positive access/hostility persists')
 DB.units[id]=nil;DB.MergeLearned()
 check((find('vendor',id,'npc')~=nil)==not hostile,'access/hostility after reconstruction')
end
-- A missing-addon discovery snapshot must learn about later shipped facts.
id=id+1;side='Alliance';DB.curated,DB.community=empty(),empty();WaypointTrackerDB.learned=empty()
local st=Learn.Store();DB.services.vendor={};WaypointTrackerData.serviceSupplement=''
st.npcs[id]={name='Later shipped',fac='A',hostile=false,services={vendor=true},spots={[37]={.5,.5}}}
DB.MergeLearned();check(st.npcs[id]~=nil,'discovery retained before shipped data arrives')
WaypointTrackerData.serviceSupplement=table.concat({'SN',id,'A','Later shipped','vendor','R','37:0.5,0.5,'..cont},'\t')
DB.MergeLearned();check(st.npcs[id]==nil,'existing snapshot gains later shipped facts without absorbing discovery')
-- English supplement names are not evidence of a localized/renamed sighting.
for _,name in ipairs({'Shipped name','Nom observe'})do
 id=id+1;DB.curated,DB.community=empty(),empty();WaypointTrackerDB.learned=empty()
 local st=Learn.Store();DB.services.vendor={}
 WaypointTrackerData.serviceSupplement=table.concat({'SN',id,'AH','Shipped name','vendor','R','37:0.5,0.5,'..cont},'\t')
 st.npcs[id]={name=name,fac='AH',hostile=false,services={vendor=true},spots={[37]={.5,.5}}}
 DB.MergeLearned()
 check((st.npcs[id]~=nil)==(name~='Shipped name'),'only unshipped/localized names retained')
 local e=find('vendor',id,'npc')
 check(e and e.name==name,'localized name survives compaction')
end
-- Raw service rows also need explicit hostility after a fresh reconstruction.
id=id+1;side='Alliance';DB.curated,DB.community=empty(),empty();WaypointTrackerDB.learned=empty()
local st=Learn.Store();WaypointTrackerData.serviceSupplement=''
DB.units[id]={kind='npc',id=id,name='Raw neutral vendor',fac='',coords='12:500,500',svc={vendor=true}}
DB.services.vendor={{id=id,fac='AH'}}
st.npcs[id]={name='Raw neutral vendor',hostile=true,spots={[37]={.5,.5}}}
DB.MergeLearned();check(st.npcs[id] and st.npcs[id].hostile,'raw service hostility survives compaction')
DB.units[id]={kind='npc',id=id,name='Raw neutral vendor',fac='',coords='12:500,500',svc={vendor=true}}
DB.MergeLearned();check(not find('vendor',id,'npc'),'raw service hostility survives reconstruction')
-- An explicit shipped hostility flag outranks inferred supplement friendliness.
for _,source in ipairs({'curated','community'})do
 for _,lowerHostile in ipairs({false,true})do
  for _,liveHostile in ipairs({false,true})do
   id=id+1;side='Alliance';DB.curated,DB.community=empty(),empty();WaypointTrackerDB.learned=empty()
   local st=Learn.Store();DB.services.vendor={}
   DB[source].npcs[id]={name='Same vendor',fac='A',hostile=lowerHostile,services={vendor=true},spots={[37]={.5,.5}}}
   st.npcs[id]={name='Same vendor',fac='A',hostile=liveHostile,services={vendor=true},spots={[37]={.5,.5}}}
   WaypointTrackerData.serviceSupplement=table.concat({'SN',id,'A','Same vendor','vendor','R','37:0.5,0.5,'..cont},'\t')
   DB.MergeLearned()
   check((st.npcs[id]~=nil)==(lowerHostile~=liveHostile),'only a new hostility flag is retained')
   DB.units[id]=nil;DB.MergeLearned()
   check((find('vendor',id,'npc')~=nil)==not liveHostile,'personal friendliness/hostility survives reconstruction over '..source)
  end
 end
end
check(#M.errors==0,table.concat(M.errors,';'))
print(('Service precedence: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
