-- Integration test for the review-only source recovery package. No writes.
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')
M.locale='enUS'
-- Add actual client zone geometry, including the new starter isle.
local f=assert(io.open('tools/fixtures/client/UiMapAssignment-1.60.1.70338-enUS.csv'))
local head=f:read('*l');local cols={};local n=0
for key in head:gmatch('[^,]+') do n=n+1;cols[key]=n end
for line in f:lines() do
 local v={};for field in (line..','):gmatch('(.-),') do v[#v+1]=field end
 local mid=tonumber(v[cols.UiMapID])
 if v[cols.UiMin_0]=='0' and v[cols.UiMin_1]=='0' and v[cols.UiMax_0]=='1' and v[cols.UiMax_1]=='1' and mid then
  local top,left,bottom,right=tonumber(v[cols.Region_3]),tonumber(v[cols.Region_4]),tonumber(v[cols.Region_0]),tonumber(v[cols.Region_1])
  M.maps[mid]={mapID=mid,name='Client map '..mid,mapType=3,parentMapID=13,cont=tonumber(v[cols.MapID]),top=top,left=left,w=left-right,h=top-bottom}
 end
end
f:close()
-- Inject only in the mock data-load lifecycle. No TOC or runtime file edits.
local original=C_AddOns.LoadAddOn
C_AddOns.LoadAddOn=function(name,...)
 local a,b=original(name,...)
 if name=='WaypointTracker_Data' and a then dofile('tools/nonroutable_v2/package/SourceRecovery.lua') end
 return a,b
end
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
assert(ns.DB.Load(),'load recovery overlay')
local D=ns.DB
local function count(e) return #D.Points(assert(e,'definition missing')) end
-- Concrete authored coordinates, including two separate Elmpaw sightings.
local croaky=assert(D.units[248278]);assert(croaky.name=='Croaky');assert(count(croaky)==1)
local p=D.Points(croaky)[1];assert(p.m==1429 and math.abs(p.x-.766)<1e-8 and math.abs(p.y-.868)<1e-8)
local elmpaw=assert(D.units[248299]);assert(elmpaw.name=='Elmpaw');assert(count(elmpaw)==2)
assert(count(D.units[251160])==2,'both Al\'Aketh Convert positions retained')
assert(count(D.objects[181672])==1,'Wickerman explicit provider location retained')
-- Real item-source lookup must reach the newly defined source NPC.
local found=false
for _,e in ipairs(D.ItemSources(assert(D.items[247826]))) do if e.id==248278 then found=true end end
assert(found,'Croaky head source must survive collection')
local qcount=0
for _,id in ipairs({82055,82056,82057,82058,85798,86760,86761,86762,86763}) do
 local q=assert(D.quests[id]);assert(q.name~='' and count(q)==0,'quest name must not create a map area');qcount=qcount+1
end
assert(D.items[275985].startsQuest==97267,'unresolved item-start ID preserved')
assert(not D.quests[97267],'unverified quest definition must stay absent')
assert(not D.objects[100000000] and not D.objects[100000001] and not D.objects[668493],'uncertain object identity must stay absent')
-- Names and instance context cannot fabricate spatial targets.
assert(D.units[241334].name=='The Will of the Ashbringer' and count(D.units[241334])==0)
assert(D.units[217996].name=='Aeonas' and count(D.units[217996])==0)
assert(D.objects[15084].name=='The Sparklematic 5200' and count(D.objects[15084])==0)
assert(D.objects[15085].name=='The Sparklematic 5200' and count(D.objects[15085])==0)
assert(D.units[251314].name=='Skyhopper' and count(D.units[251314])==0)
assert(D.units[251247].name=='Shadowgale Manticore' and count(D.units[251247])==0)
assert(D.items[226701].name=='Shadowcraft Belt' and D.items[226702].name=='Shadowcraft Gloves')
assert(D.items[216661].name=='Grime-Encrusted Ring')
assert(D.objects[673399].name=='Stolen Weapon' and count(D.objects[673399])==0)
assert(#M.errors==0,table.concat(M.errors,'\n'))
print('Source recovery v2: integration checks passed; coordinates, source collection, 9 quest titles, namespace exclusions, conflict names and non-location guards.')
