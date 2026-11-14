-- Missing/partial data, source replacement, lazy caching and read-only requests.
package.path='./tests/?.lua;'..package.path
local M=require('wowmock')
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local DB=ns.DB
local function dump(v)
 if type(v)~='table' then return tostring(v) end
 local out={};for k,x in pairs(v)do out[#out+1]=dump(k)..'='..dump(x) end;table.sort(out);return '{'..table.concat(out,',')..'}'
end
local function saved()return dump(WaypointTrackerDB)..dump(WaypointTrackerCharDB)end
M.noDataAddon=true
ns.Set('uiLastTab','find')
local before=saved()
ns.Learn.ScanProgress();ns.Learn.TitleProgress()
assert(saved()==before,'Find progress queries write no SavedVariables')
ns.Window.Show('find');ns.Window.Hide()
assert(saved()==before,'opening Find writes no SavedVariables')
assert(#DB.ServiceEntries('vendor')==0)
assert(DB.Load());assert(saved()==before,'missing-data request writes no SavedVariables')
-- A failed load can leave an initialized global behind. Retry the real loader.
WaypointTrackerData={serviceSupplement=''}
assert(DB.Load());M.noDataAddon=false
assert(DB.Load() and DB.hasShipped,'partially initialized data addon retries')
local raw=WaypointTrackerData.serviceSupplement
assert(type(raw)=='string','cold Load retains supplement text')
local c=ns.Geo.MapToWorld(37,.5,.5)
raw='SN\t994000\tAH\tSynthetic\tvendor\tR\t37:0.5,0.5,'..c
WaypointTrackerData.serviceSupplement=raw
before=saved()
local entries=DB.ServiceEntries('vendor')
assert(WaypointTrackerData.serviceSupplement==raw,'service request retains raw facts for compaction')
local first
for _,e in ipairs(entries)do if e.minedService then first=e;break end end
assert(first)
for i=1,10 do
 local found=false
 for _,e in ipairs(DB.ServiceEntries('vendor'))do if e==first then found=true end end
 assert(found,'warm service requests reuse candidates')
end
ns.Window.Show('find');ns.Window.Hide()
assert(saved()==before,'Find/Nearest queries write no SavedVariables')
WaypointTrackerData.serviceSupplement='SN\t994001\tAH\tSynthetic\tvendor\tR\t37:0.5,0.5,'..c
assert(DB.ServiceEntries('vendor')[1].id==994001,'same-generation source replacement invalidates parsed rows')
local gen=DB.generation
ns.Learn.Import('WTL1\tenUS\t1\nN\t994001\tPersonal\t0\t10\tvendor\t37:900,900\tAH')
DB.Load();assert(DB.generation>gen,'import triggers merge on Load')
assert(DB.Points(DB.ServiceEntries('vendor')[1])[1].x==.9,'import invalidates resolved candidate')
ns.Learn.AddFix('npc',994001,{37,.9,.9},{37,.8,.8});DB.MergeLearned()
assert(DB.Points(DB.ServiceEntries('vendor')[1])[1].x==.8,'correction invalidates resolved candidate')
-- Hostility excludes both the supplement and legacy rows with the toggle off.
local st=ns.Learn.Store()
st.npcs[994001].hostile=true;DB.MergeLearned();ns.Set('findFaction',false)
for _,e in ipairs(DB.ServiceEntries('vendor'))do assert(e.id~=994001,'hostile service never offered')end
-- Faction switching resolves access per request, including an unknown player.
WaypointTrackerData.serviceSupplement='SN\t994002\tH\tHorde\tvendor\tR\t37:0.5,0.5,'..c
for _,side in ipairs({'Alliance','Horde','Unknown'})do
 UnitFactionGroup=function()return side end
 local found=false;for _,e in ipairs(DB.ServiceEntries('vendor'))do if e.id==994002 then found=true end end
 assert(found==(side~='Alliance'),'faction switch: '..side)
end
-- Candidate validation supplies the same world projection Nearest needs.
WaypointTrackerData.serviceSupplement='SN\t994003\tAH\tProjected\tvendor\tR\t37:0.5,0.5,'..c
local project=ns.Geo.MapToWorld;local projections=0
ns.Geo.MapToWorld=function(...)projections=projections+1;return project(...)end
local projected=DB.ServiceEntries('vendor')[1]
DB.NearestOf({projected})
assert(projections==1,'first request reuses the validated world projection')
ns.Geo.MapToWorld=project
-- A native API miss also recovers, without a merge or cache-size reset.
M.maps[994004]={mapID=994004,name='Delayed native map',mapType=3,parentMapID=13,
 cont=c,top=1000,left=1000,w=1000,h=1000}
WaypointTrackerData.serviceSupplement='SN\t994004\tAH\tNative retry\tvendor\tR\t994004:0.61,0.71,'..c
local world=C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos=function(m,...)if m~=994004 then return world(m,...) end end
local generation=DB.generation
assert(#DB.Points(DB.ServiceEntries('vendor')[1])==0,'native miss is unresolved')
C_Map.GetWorldPosFromMapPos=world;M.now=M.now+5.1
assert(#DB.Points(DB.ServiceEntries('vendor')[1])==1 and DB.generation==generation,'native projection retries without a merge')
-- Nearest samples faction once, rather than querying it per candidate.
local reads=0
UnitFactionGroup=function()reads=reads+1;return 'Alliance' end
DB.NearestOf({{kind='npc',id=1,fac='A',points={{m=37,x=.5,y=.5}}},
 {kind='npc',id=2,fac='H',points={{m=37,x=.6,y=.6}}}},{faction=true})
assert(reads==1,'Nearest samples faction once per request')
assert(#M.errors==0,table.concat(M.errors,';'))
print('Service index: load retries, laziness, source/generation invalidation, hostility and faction switching passed')
