-- Complete verified objective geometry, with both coordinate representations.
package.path='tests/?.lua;'..package.path
local M=require('wowmock')
M.maps[1416]={mapID=1416,name='Alterac Mountains',mapType=3,parentMapID=13,cont=0,top=1500,left=783.33331298828,w=2799.99993896488,h=1866.66665649414}
M.maps[1424]={mapID=1424,name='Hillsbrad Foothills',mapType=3,parentMapID=13,cont=0,top=400,left=1066.6666259766,w=3199.9998779297,h=2133.3332519531}
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
assert(ns.DB.Load())
local T=ns.Travel
local c={faction='Horde',level=30,run=7,ground=7,flightFactor=1,flights=false,boats=false,jumps={}}
local function place(m,x,y)
    local cont,wx,wy=ns.Geo.MapToWorld(m,x,y)
    local area,city=T.AreaAt(m,x,y)
    return {m=m,x=x,y=y,cont=cont,wx=wx,wy=wy,area=area,city=city}
end
local function run()
    local d=T.Data();local start=d.byTaxi[13]
    local goal=place(1416,.229,.595)
    M.player.inst,M.player.wx,M.player.wy=T.Pos(start)
    local selected,point=ns.DB.NearestOf(ns.DB.QuestTargets(ns.DB.quests[557],'objective'))
    assert(selected and selected.id==2359 and point.m==1416 and math.abs(point.x-.229)<1e-9
        and math.abs(point.y-.595)<1e-9,'Find selects the verified reachable quest objective')
    local found=false
    for _,entry in ipairs(ns.DB.QuestTargets(ns.DB.quests[557],'objective'))do
        if entry.id==2359 then
            for _,p in ipairs(ns.DB.Points(entry))do
                if p.m==1416 and math.abs(p.x-.229)<1e-9 and math.abs(p.y-.595)<1e-9 then found=true end
            end
        end
    end
    assert(found,'verified target is a genuine quest 557 objective spawn')
    for _,preference in ipairs({'fastest','safer'})do
        local _,route=T.Routes(start,goal,c,preference)
        assert(route and route.path[#route.path].node==goal,'complete Tarren Mill -> quest 557 ground route')
        for i=2,#route.path do
            local e=route.path[i];local via=e.via
            assert(via=='walk' or type(via)=='table' and (via.method=='walk' or via.method=='gate'),'ground travel only')
            assert(T.CanWalk(route.path[i-1].node,e.node),'no blocked objective shortcut')
        end
    end
end
run()
ns.Geo.MapToWorld=function()return nil end;T._Reset()
-- Use the shipped fallback position for the same verified objective.
local worldToMap=ns.Geo.MapToWorld
ns.Geo.MapToWorld=function(m,x,y)
    if m==1416 and x==.229 and y==.595 then return 0,389.33333938598685,142.13332696532245 end
    return worldToMap(m,x,y)
end
run()
print('PASS: quest 557 complete ground route, verified target, both preferences and coordinate representations')
