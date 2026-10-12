-- Replay the ordered corpse-run positions shipped with their provenance.
package.path='tests/?.lua;'..package.path
local M=require('wowmock')
M.maps[1416]={mapID=1416,name='Alterac',mapType=3,parentMapID=13,cont=0,top=1500,left=783.33331298828,w=2799.99993896488,h=1866.66665649414}
M.maps[1424]={mapID=1424,name='Hillsbrad',mapType=3,parentMapID=13,cont=0,top=400,left=1066.6666259766,w=3199.9998779297,h=2133.3332519531}
function UnitFactionGroup() return 'Horde' end
function UnitLevel() return 30 end
function GetUnitSpeed() return 7,7 end
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local T,G,WP=ns.Travel,ns.Geo,ns.WP
local d=T.Data();local points=d.ghostCorridors[1]
local shipped=points~=nil
if not points then
    points={}
    local f=assert(io.open('tests/fixtures/corpse-replay.tsv'))
    for line in f:lines() do
        local r={};for v in (line..'\t'):gmatch('(.-)\t') do r[#r+1]=v end
        points[#points+1]={m=tonumber(r[4]),x=tonumber(r[5])/100,y=tonumber(r[6])/100,
            cont0=tonumber(r[7]),wx0=tonumber(r[8]),wy0=tonumber(r[9])}
    end
    f:close()
end
local pass,fail=0,0
local function check(ok,why)
    if ok then pass=pass+1 else fail=fail+1;print('FAIL: '..why) end
end
local function place(node)
    local c,wx,wy=T.Pos(node);local area,city=T.AreaAt(node.m,node.x,node.y)
    return {m=node.m,x=node.x,y=node.y,cont=c,wx=wx,wy=wy,area=area,city=city}
end
local start,goal=place(points[1]),place(points[#points])
local c={faction='Horde',level=30,run=7,ground=7,dead=true,ghost=true,flights=false,boats=false,flightFactor=1,jumps={}}
local saved=d.ghostCorridors;d.ghostCorridors={}
local terrain=ns.Terrain;ns.Terrain=nil
local _,old=T.Routes(start,goal,c,'fastest');d.ghostCorridors=saved;ns.Terrain=terrain
check(old and old.path and old.path[#old.path].node==goal,'general graph completes the corpse route')
for _,pref in ipairs({'fastest','safer'}) do
    local _,route=T.Routes(start,goal,c,pref)
    check(route and route.path[#route.path].node==goal,pref..' complete corpse route')
    if shipped then check(route and route.total<198 and route.total>196,pref..' observed ghost corridor replaces detour (~197 seconds)') end
    check(route.risk==0,pref..' living danger penalty excluded from ghost costs')
    local observed=0
    for _,e in ipairs(route.path) do if e.node.corridor then observed=observed+1 end end
    check(shipped and observed>=#points or not shipped and observed==0,pref..' ordered corridor or general planner, no disconnected trace')
    for i=2,#route.path do
        local e=route.path[i];local via=e.via
        if via=='walk' or type(via)=='table' and (via.method=='walk' or via.method=='gate' or via.method=='lift') then
            check(T.CanWalk(route.path[i-1].node,e.node),pref..' no blocked straight ground leg '..i)
        end
    end
    c.ghost=false;c.dead=false
    local _,alive=T.Routes(start,goal,c,pref)
    for _,e in ipairs(alive.path) do check(not e.node.corridor,pref..' alive cannot use ghost-only leg') end
    c.ghost=true;c.dead=true
    -- Rejoining from a point already on the trace must not visit its start.
    for i=2,#points-1 do
        local here=place(points[i]);local _,remaining=T.Routes(here,goal,c,pref)
        check(remaining and remaining.path[#remaining.path].node==goal,pref..' current-position ghost rejoin '..i)
        if shipped then check(remaining and remaining.total<route.total,pref..' corridor rejoin reduces remaining cost '..i) end
    end
    WP.ClearAll(true);M.player.ghost=true;T.Know().mountSpeed=14
    M.player.inst,M.player.wx,M.player.wy=start.cont,start.wx,start.wy
    C_Map.GetBestMapForUnit=function() return 1424 end
    ns.Set('realRoutes',true);ns.Set('travelTrails',true);ns.Set('travelPreference',pref)
    local wp=WP.Add(goal.m,goal.x,goal.y,{title='Provisional corpse endpoint'})
    T.Steer(wp)
    check(T.Current().c.ground==7,pref..' ghost ignores remembered mount speed')
    check(T.Current().path[#T.Current().path].node.goal,pref..' live planner completes corpse route')
    if shipped then check(T.Current().total>196 and T.Current().total<198,pref..' live planner uses ghost travel time') end
    local steeringPoints=points
    if not shipped then
        steeringPoints={}
        for _,e in ipairs(T.Current().path) do steeringPoints[#steeringPoints+1]=e.node end
    end
    for i=2,#steeringPoints-1 do
        local p=place(steeringPoints[i]);local q=place(steeringPoints[i+1])
        -- Move 5 yards beyond the sample, 20 yards to the side of its next
        -- segment. Core arrow must face ahead without waiting for replan.
        local dx,dy=q.wx-p.wx,q.wy-p.wy;local length=math.sqrt(dx*dx+dy*dy)
        M.player.inst,M.player.wx,M.player.wy=p.cont,p.wx+5*dx/length-20*dy/length,p.wy+5*dy/length+20*dx/length
        C_Map.GetBestMapForUnit=function() return p.m end
        M.now=M.now+.1
        local s=T.Steer(wp)
        local forward=s and s.aim and ((s.aim.wx-M.player.wx)*dx+(s.aim.wy-M.player.wy)*dy)/length
        check(forward and forward>0,pref..' laterally passed trace vertex points ahead '..i)
    end
end
-- Direction/mode are evidence restrictions, not arbitrary graph connectors.
local _,reverse=T.Routes(goal,start,c,'fastest')
for _,e in ipairs(reverse.path) do check(not e.node.corridor,'forward observation is not a reverse edge') end
local far=place(points[1]);far.wx=far.wx+100
local _,farRoute=T.Routes(far,goal,c,'fastest')
check(farRoute and not farRoute.path[2].node.corridor,'joins beyond 40 yards cannot attach to corridor')
check(#M.errors==0,'mock event handlers have no errors')
print(('Ghost replay: %d passed, %d failed'):format(pass,fail))
if fail>0 then os.exit(1) end
