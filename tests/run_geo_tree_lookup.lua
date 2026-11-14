-- Area-name lookup can use the native tree without narrowing the full picker.
package.path='./tests/?.lua;'..package.path
local M=require('wowmock')
M.maps={
    [947]={mapID=947,name='World',mapType=1,parentMapID=0},
    [1415]={mapID=1415,name='Tree continent',mapType=2,parentMapID=947,cont=0,top=1000,left=1000,w=1000,h=1000},
    [1429]={mapID=1429,name='Tree zone',mapType=3,parentMapID=1415,cont=0,top=900,left=900,w=100,h=100},
    [9901]={mapID=9901,name='Orphan zone',mapType=3,parentMapID=0,cont=0,top=800,left=800,w=100,h=100},
}
C_Map.GetBestMapForUnit=function()return 1429 end
C_Map.GetAreaInfo=function(id)
    if id==91001 then return 'Tree zone' end
    if id==91002 or id==91003 then return 'Orphan zone' end
end
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
ns.DB.zoneNames={[91003]='Tree zone'}
M.maps[13001]={mapID=13001,name='Known high orphan',mapType=3,parentMapID=0,cont=0,top=600,left=600,w=100,h=100}
assert(ns.Geo.GetMapInfo(13001))
local calls=0
local get=C_Map.GetMapInfo
C_Map.GetMapInfo=function(id)calls=calls+1;return get(id)end
assert(ns.DB.MapForArea(91001)==1429,'tree-backed area resolves')
assert(calls<100,'area lookup must not scan 12000 IDs when the native tree resolves it: '..calls)
-- Native area names outrank Classic fallback names even when orphaned.
assert(ns.DB.MapForArea(91003)==9901,'native orphan name must beat a tree-only Classic fallback')
assert(calls>=11990,'an orphaned name retains the complete catalogue fallback')
assert(ns.DB.MapForArea(91002)==9901,'ordinary orphan lookup resolves')
local function contains(list,id)
    for _,z in ipairs(list)do if z.id==id then return true end end
end
assert(contains(ns.Geo.GetZoneList(),9901),'full picker retains unparented maps')
assert(contains(ns.Geo.GetZoneList(),13001),'full picker retains known high orphan maps from the tree catalogue')
local before=calls
M.maps[9902]={mapID=9902,name='Recovered orphan',mapType=3,parentMapID=0,cont=0,top=700,left=700,w=100,h=100}
M.now=M.now+5.1
assert(ns.Geo.GetMapInfo(9902),'metadata retry recovers')
assert(contains(ns.Geo.GetZoneList(true),9902),'recovery invalidates derived tree catalogue too')
assert(contains(ns.Geo.GetZoneList(),9902),'recovery retains complete picker')
assert(calls-before<100,'recovery must not repeat the blind scan')
assert(#M.errors==0,table.concat(M.errors,'\n'))
print('Tree lookup: fast area matching, native-name priority, orphan fallback and recovery passed')
