-- Second-review boundaries: cold alerts, recoverable map metadata, idle beta,
-- living loot and transactional discovery failures. Run with real Lua 5.1.
package.path='./tests/?.lua;'..package.path
local M=require('wowmock')
local secret=setmetatable({}, {__index=function()error('secret indexed')end,__tostring=function()error('secret formatted')end})
local prior=issecretvalue
issecretvalue=function(v)return rawequal(v,secret)or prior(v)end
local frames,events={},{}
local load=loadfile
loadfile=function(path)
 local chunk,err=load(path);if not chunk then return nil,err end
 if path~='WaypointTracker/Treasure.lua'then return chunk end
 return function(name,ns)
  local create,reg=CreateFrame,ns.RegisterEvent
  CreateFrame=function(...)local f=create(...);frames[#frames+1]=f;return f end
  ns.RegisterEvent=function(e,f)events[e]=f;return reg(e,f)end
  chunk(name,ns);CreateFrame,ns.RegisterEvent=create,reg
 end
end
local ns=M.LoadAddon('WaypointTracker','WaypointTracker');loadfile=load
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local T,G,WP=ns.Treasure,ns.Geo,ns.WP
local passed,failed=0,0
local function ck(v,s)if v then passed=passed+1 else failed=failed+1;print('FAIL: '..s)end end
local ticker=frames[1]
local look,front,scan=T.LookAt,T.CheckInFront,T.Scan
local calls=0
T.LookAt=function(...)calls=calls+1;return look(...)end
T.CheckInFront=function(...)calls=calls+1;return front(...)end
T.Scan=function(...)calls=calls+1;return scan(...)end
for i=1,1000 do if ticker:IsShown()and ticker:GetScript('OnUpdate')then ticker:RunScript('OnUpdate',1/60)end end
local get,checks,eventCount=ns.Get,0,0
ns.Get=function(k)checks=checks+1;return get(k)end
for _,f in pairs(events)do f('nameplate1');eventCount=eventCount+1 end
ns.Get=get
ck(checks==eventCount,'each disabled event makes exactly one setting check')
ck(not ticker:IsShown()and ticker:GetScript('OnUpdate')==nil,'disabled ticker hidden and detached')
ck(calls==0,'1000 frames and all disabled events never enter Treasure consumers')
T.LookAt,T.CheckInFront,T.Scan=look,front,scan
ns.settings.realRoutes=false;ns.settings.treasureKnownSpots=false;ns.settings.treasureKnownRares=false
for i=1,2 do
 ns.Set('treasureHunt',true);ck(ticker:IsShown()and ticker:GetScript('OnUpdate')~=nil,'enable arms ticker '..i)
 local count=0;T.Scan=function()count=count+1 end;ticker:RunScript('OnUpdate',1.1);T.Scan=scan
 ck(count==1 and #frames==1,'one scan from one ticker '..i)
 ns.Set('treasureHunt',false);ck(not ticker:IsShown()and ticker:GetScript('OnUpdate')==nil,'disable disarms ticker '..i)
end
ns.Set('treasureHunt',true);ns.settings.treasurePing=true
local serial=0
local function rare()
 T.Clear();WP.ClearAll(true);M.units={};M.vignettes={};serial=serial+1
 local key='Creature-0-1-0-0-999987-review'..serial
 M.units.target={guid=key,name='Unknown rare',class='rare',reaction=2,dead=false}
 return key
end
local world=C_Map.GetWorldPosFromMapPos
for _,fixture in ipairs({'object','continent','x','y'})do
 local key=rare();C_Map.GetPlayerMapPosition=function()return {x=.57771+serial*.001,y=.62349}end
 C_Map.GetWorldPosFromMapPos=function()
  if fixture=='object'then return 0,secret elseif fixture=='continent'then return secret,{x=1,y=2} elseif fixture=='x'then return 0,{x=secret,y=2} else return 0,{x=1,y=secret}end
 end
 local ok=pcall(T.Scan);local t=T.Targets()[key]
 ck(ok and t and t.seen and WP.IsValid(t.wp),'cold ping survives secret world '..fixture)
end
C_Map.GetWorldPosFromMapPos=world
local vector=G.GetVector
local key=rare();G.GetVector=function()error('injected distance failure')end
local ok=pcall(T.Scan);local t=T.Targets()[key]
ck(ok and t and t.seen and WP.IsValid(t.wp)and t.log,'distance exception leaves complete discovery')
G.GetVector=vector
key=rare();local add=WP.Add;local logCount=#T.Recent()
WP.Add=function()error('injected placement failure')end
pcall(T.Scan)
ck(not T.Targets()[key]and #T.Recent()==logCount,'placement exception installs neither target nor history')
WP.Add=add;T.Scan();ck(T.Targets()[key]and WP.IsValid(T.Targets()[key].wp),'failed placement retries next scan')
key=rare();WP.Add=function()return nil end;logCount=#T.Recent();T.Scan()
ck(not T.Targets()[key]and #T.Recent()==logCount,'unavailable waypoint defers complete installation')
WP.Add=add;T.Scan();ck(T.Targets()[key]and T.Targets()[key].seen,'nil placement retries')
key=rare();T.Scan();t=T.Targets()[key];local record=t.log
GetNumLootItems=function()return 1 end;GetLootSourceInfo=function()return key,1 end
M.FireEvent('LOOT_OPENED');ck(T.Targets()[key]==t and WP.IsValid(t.wp)and not record.outcome,'own living rare loot preserves waypoint and log')
UnitIsDead=function()return secret end
M.FireEvent('LOOT_OPENED');ck(T.Targets()[key]==t and not record.outcome,'unknown life state is presumed alive for loot')
-- Even a loot-atlas marker cannot turn a creature source into a chest.
T.Clear();M.units={};M.vignettes={}
local creatureKey='Creature-0-1-0-0-999986-lootAtlas'
M.vignettes.lootAtlas={objectGUID=creatureKey,name='Creature marker',onMinimap=true,atlasName='VignetteLoot',pos={.6,.5}}
T.Scan();local creature=T.Targets()[creatureKey]
GetLootSourceInfo=function()return creatureKey,1 end
M.FireEvent('LOOT_OPENED')
ck(creature and T.Targets()[creatureKey]==creature and not creature.log.outcome,'creature GUID remains alive even with a loot atlas')
key,t,record=creatureKey,creature,creature.log
-- A failed removal must leave the live target and its waypoint together,
-- without marking completion; the following notification can retry.
local remove=WP.Remove
WP.Remove=function()error('injected removal failure')end
pcall(T.Ignore,t)
ck(T.Targets()[key]==t and WP.IsValid(t.wp)and not record.outcome,'removal exception preserves live target')
WP.Remove=function()return false end
pcall(T.Ignore,t)
ck(T.Targets()[key]==t and WP.IsValid(t.wp),'declined removal preserves live target')
WP.Remove=remove;T.Ignore(t);ck(not T.Targets()[key]and not WP.IsValid(t.wp),'removal retries successfully')
-- Existing moved/renamed targets keep their previous record on failed moves.
key=rare();T.Scan();t=T.Targets()[key];record=t.log
local oldX,oldName,move=t.x,t.name,WP.Move
M.vignettes.update={objectGUID=key,name='Changed name',onMinimap=true,atlasName='VignetteKill',pos={.9,.6}}
WP.Move=function()error('injected move failure')end
pcall(T.Scan);ck(T.Targets()[key]==t and t.x==oldX and t.name==oldName and record.x==oldX and record.name==oldName,'failed move preserves old target/log')
WP.Move=move;T.Scan();ck(t.x==.9 and t.name=='Changed name'and record.name==t.name and t.wp.x==t.x,'later move commits live and log together')
-- A presentation exception is after commitment and cannot block later units.
key=rare();local printFn=ns.Print
ns.Print=function()error('injected print failure')end
pcall(T.Scan);ns.Print=printFn;t=T.Targets()[key]
ck(t and t.seen and t.log and WP.IsValid(t.wp),'presentation exception preserves complete discovery')
-- Setting failures restore the quiet flag. A later alert still prints.
local setting=ns.Set
ns.Set=function()error('injected setting failure')end
ck(not pcall(T.SetOption,'treasureFocus',true),'setting failure propagates after cleanup')
ns.Set=setting;key=rare();local printed=#M.printed;T.Scan()
ck(#M.printed>printed,'quiet restored after failed SetOption')
-- Timestamp errors happen before any new waypoint or live/history commit.
key=rare();local stamp=GetServerTime;local count=#T.Recent()
GetServerTime=function()error('injected timestamp failure')end
pcall(T.Scan);GetServerTime=stamp
ck(not T.Targets()[key]and WP.Count()==0 and #T.Recent()==count,'timestamp exception installs no partial discovery')
T.Scan();ck(T.Targets()[key]and WP.IsValid(T.Targets()[key].wp),'timestamp failure retries')
-- All world/map result objects are sanitized before shared readers index them.
local worldToMap=C_Map.GetMapPosFromWorldPos
for _,which in ipairs({'object','map','coordinate'})do
 C_Map.GetMapPosFromWorldPos=function()
  if which=='object'then return 37,secret elseif which=='map'then return secret,{x=.5,y=.5} else return 37,{x=secret,y=.5}end
 end
 local good,value=pcall(G.WorldToMap,0,1,2,37)
 ck(good and value==nil,'inverse world boundary '..which)
end
C_Map.GetMapPosFromWorldPos=worldToMap
local unitPosition,worldPosition=UnitPosition,C_Map.GetWorldPosFromMapPos
UnitPosition=function()return nil end
C_Map.GetWorldPosFromMapPos=function()return 0,secret end
M.now=M.now+1
local good,value=pcall(G.GetPlayerWorld,0)
ck(good and value==nil,'player map-to-world fallback sanitizes secret vector')
UnitPosition,C_Map.GetWorldPosFromMapPos=unitPosition,worldPosition
-- Both index directions recover: child points attach to the containing
-- zone, and child queries eventually see parent points.
local mapInfo=C_Map.GetMapInfo
for n,variant in ipairs({'nil','object','parent','type','name','id'})do
 T.Clear();local child,parent=8500+n*2,8501+n*2
 M.maps[child]={mapID=child,name='Child',mapType=5,parentMapID=parent}
 M.maps[parent]={mapID=parent,name='Parent',mapType=3,parentMapID=13}
 ns.DB={ready=true,generation=n+90000,objects={
  [1]={name='Parent chest',chest=true,points={{m=parent,x=.7,y=.5}}},
  [2]={name='Child chest',chest=true,points={{m=child,x=.7,y=.5}}}},units={},Points=function(e)return e.points end,IsEnemy=function()return true end}
 local api=0
 C_Map.GetMapInfo=function(id)
  api=api+1
  if id~=child then return mapInfo(id)end
  if variant=='nil'then return nil elseif variant=='object'then return secret elseif variant=='name'then return {mapID=child,name=secret,mapType=5,parentMapID=parent} elseif variant=='id'then return {mapID=secret,name='Child',mapType=5,parentMapID=parent} elseif variant=='parent'then return {mapID=child,mapType=5,parentMapID=secret} else return {mapID=child,mapType=secret,parentMapID=parent}end
 end
 pcall(G.ParentChain,child)
 local available,rows=pcall(T.ZoneSpots,child)
 local infoOK,info=pcall(G.GetMapInfo,child)
 ck(available and #rows==0 and infoOK and info==nil,'unavailable metadata is never resolved/cached '..variant)
 local before=api
 for i=1,1000 do pcall(T.ZoneSpots,child);pcall(G.ParentChain,child)end
 ck(api==before,'unresolved map retry bounded '..variant)
 C_Map.GetMapInfo=function(id)api=api+1;return mapInfo(id)end
 M.now=M.now+6
 ck(T.ZoneMap(child)==parent and #T.ZoneSpots(child)==2 and #T.ZoneSpots(parent)==2,'metadata and both affected buckets recover '..variant)
 local good,chain=pcall(G.ParentChain,child);ck(good and chain[2]==parent,'partial shared parent chain recovers '..variant)
 before=api;for i=1,1000 do T.ZoneSpots(child)end;ck(api==before,'resolved zone stays cached '..variant)
end
-- Failed index construction must not mark a partial DB generation complete.
ns.DB.generation=ns.DB.generation+1
local points=ns.DB.Points
ns.DB.Points=function()error('injected Points failure')end
ck(not pcall(T.ZoneSpots,37),'index construction failure observed')
ns.DB.Points=points
ck(#T.ZoneSpots(8513)==2,'index construction retries same generation')
C_Map.GetMapInfo=mapInfo
-- Sibling API readers: map-info-at-position, the children array and each
-- child object must be plain. Successful metadata recovery invalidates a
-- derived list, without periodic rescans in warm Follow/arrow callers.
local atPosition,childrenAPI=C_Map.GetMapInfoAtPosition,C_Map.GetMapChildrenInfo
C_Map.GetMapInfoAtPosition=function()return secret end
local normalized,map=pcall(G.NormalizeToZone,13,.5,.5)
ck(normalized and map==13,'normalization rejects a secret submap object')
C_Map.GetMapInfoAtPosition=atPosition
local function freshGeo()
 local isolated={L=ns.L,Num=ns.Num,Int=ns.Int,Plain=ns.Plain,Str=ns.Str,XY=ns.XY}
 assert(loadfile('WaypointTracker/Geo.lua'))('WaypointTracker',isolated)
 return isolated.Geo
end
local recoverID=8995
M.maps[recoverID]={mapID=recoverID,name='Recovered zone',mapType=3,parentMapID=13,cont=0,top=0,left=0,w=4000,h=4000}
C_Map.GetMapInfo=function(id)if id==recoverID then return nil end;return mapInfo(id)end
C_Map.GetMapChildrenInfo=function()return secret end
local catalog=freshGeo()
local listed,zones=pcall(catalog.GetZoneList)
ck(listed and #zones>0,'zone list rejects secret children array')
C_Map.GetMapChildrenInfo=function()return {secret,{mapID=secret,mapType=3,parentMapID=13,name='Invalid'}}end
ck(pcall(freshGeo().GetZoneList),'zone list rejects secret child objects and fields')
C_Map.GetMapInfo,C_Map.GetMapChildrenInfo=mapInfo,childrenAPI
M.now=M.now+6
ck(catalog.GetMapInfo(recoverID)~=nil,'missing catalogue metadata resolves after bounded retry')
local found=false
for _,z in ipairs(catalog.GetZoneList())do if z.id==recoverID then found=true end end
ck(found,'partial zone list recovers when metadata becomes available')
local mapCalls=0
C_Map.GetMapInfo=function(id)mapCalls=mapCalls+1;return mapInfo(id)end
M.now=M.now+1000
catalog.GetZoneList()
ck(mapCalls==0,'warm catalogue never rescans map IDs after time passes')
C_Map.GetMapInfo=mapInfo
-- Visiting a known spot commits visit memory only after removal succeeds.
T.Clear();WP.ClearAll(true);M.units={};M.vignettes={}
ns.DB={ready=true,generation=990001,objects={[1]={name='Known chest',chest=true,points={{m=37,x=.8,y=.5}}}},units={},Points=function(e)return e.points end,IsEnemy=function()return true end}
ns.settings.treasureKnownSpots=true
local measure=G.GetVector
G.GetVector=function()return 100 end
T.PickKnown();local known=T.Targets().spot
ck(known and WP.IsValid(known.wp),'known-spot failure fixture has live waypoint')
G.GetVector=function()return 0 end
WP.Remove=function()error('injected visit removal failure')end
pcall(T.PickKnown)
ck(T.Targets().spot==known and WP.IsValid(known.wp),'failed visit removal retains known target')
WP.Remove=remove;T.Clear();G.GetVector=function()return 100 end
T.PickKnown();ck(T.Targets().spot and WP.IsValid(T.Targets().spot.wp),'failed visit does not suppress subsequent guidance')
G.GetVector=measure
ck(#M.errors==0,'no captured addon errors: '..tostring(M.errors[1]))
print(('%d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
