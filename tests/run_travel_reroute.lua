-- Following must join the remaining route from today's position, not revisit
-- an optional approach stop. Synthetic geometry keeps gains below hysteresis.
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')
function UnitFactionGroup() return 'Horde' end
function UnitLevel() return 30 end
function GetUnitSpeed() return 7, 7 end
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN')
local T, G, WP = ns.Travel, ns.Geo, ns.WP
local shipped=ns.TravelData
local passed, failed = 0, 0
local function check(v, why)
    if v then passed=passed+1 else failed=failed+1; print('FAIL: '..why) end
end
local function place(x,y,area)
    local cont,wx,wy=G.MapToWorld(37,x,y)
    return {m=37,x=x,y=y,cont=cont,wx=wx,wy=wy,area=area or 1,player=true}
end
local function row(id,kind,x,y,area,taxi)
    local p=place(x,y,area)
    return table.concat({id,kind,area or 1,p.cont,p.wx,p.wy,37,x*100,y*100,'','',taxi or '',taxi and 'Horde' or ''},'\t')
end
ns.TravelData={areas={'approach','landing'},indoor={},maps='37\t1',regions='37\t2\t80\t50\t2',
    nodes=table.concat({row('P','pass',.3,.5),row('Q','pass',.3,.502),row('FM','taxi',.4,.5,1,1),row('LAND','taxi',.8,.5,2,2)},'\n'),
    links='P\tFM\twalk\t47\t\t\t1\nQ\tFM\twalk\t47\t\t\t1\nFM\tLAND\ttaxi\t900\tHorde\t\t1',cities='',towns='',levels='',factors=''}
T._Reset();local d=T.Data()
T.Know().flights[1],T.Know().flights[2]=true,true
ns.Set('realRoutes',true);ns.Set('travelHearth',false);ns.Set('travelTrails',false);ns.Set('travelFlights',true)
C_Map.GetBestMapForUnit=function() return 37 end
local start=place(.2,.5)
local function move(p,dt)
    M.player.inst,M.player.wx,M.player.wy=p.cont,p.wx,p.wy;M.now=M.now+(dt or 0)
end
local function choose(preference,explicit)
    WP.ClearAll(true)
    move(start)
    local wp=WP.Add(37,.8,.5,{title='Reroute destination'})
    ns.Set('travelPreference',preference)
    if explicit then
        local _,candidate=T.Routes(start,place(.8,.5,2),
            {faction='Horde',level=30,run=7,ground=7,flights=true,boats=true,flightFactor=1,jumps={}},preference)
        T.Select(wp,candidate)
    else
        T.Steer(wp)
    end
    return wp
end
for _,preference in ipairs({'fastest','safer'}) do
    for _,explicit in ipairs({false,true}) do
        local label=preference..(explicit and ' chosen' or ' automatic')
        local wp=choose(preference,explicit)
        check(T.Current().target.node.id=='P',label..' begins with optional approach')
        move(place(.3005,.51),2.1);T.Steer(wp)
        check(T.Current().target.node.id=='FM',label..' lateral parallel movement bypasses P outside 15 yards')
        check(T.Current().path[1].node.wx==M.player.wx,label..' route is anchored at current position')
        wp=choose(preference,explicit)
        move(place(.315,.5),2.1);T.Steer(wp)
        check(T.Current().target.node.id=='FM',label..' passed P is skipped outside arrival radius')
        -- A flight master is an action point, even if the player passes it.
        move(place(.415,.51),2.1);T.Steer(wp)
        check(T.Current().target.node.id=='FM',label..' never bypasses mandatory flight origin')
        T.Know().flights[1]=false;T.Invalidate();T.Steer(wp)
        check(T.Current().target.node.id=='FM',label..' unknown FM stays mandatory')
        move(place(.4,.5),2.1);local s=T.Steer(wp)
        check(s and s.pin and T.Current().target.via.kind=='discover',label..' unlock remains pending until confirmed')
        T.Know().flights[1]=true
    end
end
-- Alternate the best approach by a few hundredths of a second. Retention
-- must stay stable while the hint is still useful and ahead of the player.
for _,preference in ipairs({'fastest','safer'}) do
    local wp=choose(preference,false)
    for i=1,6 do
        move(place(.2,i%2==1 and .502 or .5),2.1);T.Steer(wp)
        check(T.Current().target.node.id=='P',preference..' near-tie approaches do not flip '..i)
    end
end
-- Meaningful movement may search early, with a half-second lower bound.
local wp=choose('fastest',false)
local count=0;ns.On('TRAVEL_PLANNED',function() count=count+1 end)
move(place(.3005,.51),.2);T.Steer(wp)
check(count==0,'movement search throttled within half a second')
M.now=M.now+.31;T.Steer(wp)
check(count==1 and T.Current().target.node.id=='FM','10-yard movement triggers early search after half a second')
for i=1,10 do M.now=M.now+.01;T.Steer(wp) end
check(count==1,'no per-frame planner search')
-- Known terrain and doorways protect otherwise optional points.
wp=choose('fastest',true)
d.nodes.P.kind='entrance'
move(place(.3005,.51),2.1);T.Steer(wp)
check(T.Current().target.node.id=='P','doorway cannot be trimmed out of a chosen approach')
d.nodes.P.kind='pass'
-- Barrier between the lateral player and FM, but not P->FM (around its end).
d.barriers={{place(.32,.505),place(.32,.52)}}
wp=choose('fastest',true);move(place(.3005,.515),2.1);T.Steer(wp)
check(T.Current().target.node.id=='P','barrier-avoidance road stop cannot be skipped through terrain')
d.barriers={}
-- A boarding stop stays mandatory for every transport type.
for _,method in ipairs({'ship','zeppelin','portal','tram'}) do
    wp=choose('fastest',true);d.out.FM[1].method=method
    for i=1,8 do M.now=M.now+.3;T.Steer(wp) end
    move(place(.415,.51),40);T.Steer(wp)
    check(T.Current() and T.Current().target.node.id=='FM',method..' boarding point stays mandatory')
end
d.out.FM[1].method='taxi'
-- A known departure absorbs walking savings into extra waiting. An optional
-- hint must still be dropped even though the final arrival times are equal.
for _,preference in ipairs({'fastest','safer'}) do
    wp=choose(preference,true)
    local departure=ns.Trails.NextDeparture
    d.out.FM[1].method,d.out.FM[1].ride='ship',900
    ns.Trails.NextDeparture=function(_,at) return math.max(0,200-at) end
    for i=1,8 do M.now=M.now+.3;T.Steer(wp) end
    move(place(.3005,.51),40);T.Steer(wp)
    check(T.Current().target.node.id=='FM',preference..' equal arrival ETA drops redundant approach before a timed departure')
    ns.Trails.NextDeparture=departure
    d.out.FM[1].method,d.out.FM[1].ride='taxi',nil
end
-- Real quest 557: replans follow the current eligible western approach.
-- The old approximate Darrow road chord is uncertain in the static review;
-- an available Southshore approach takes precedence without crossing barriers.
M.maps[1416]={mapID=1416,name='Alterac',mapType=3,parentMapID=13,cont=0,top=1500,left=783.33331298828,w=2799.99993896488,h=1866.66665649414}
M.maps[1424]={mapID=1424,name='Hillsbrad',mapType=3,parentMapID=13,cont=0,top=400,left=1066.6666259766,w=3199.9998779297,h=2133.3332519531}
ns.TravelData=shipped;T._Reset();d=T.Data()
local function actual(m,x,y)
    local cont,wx,wy=G.MapToWorld(m,x,y)
    return {m=m,x=x,y=y,cont=cont,wx=wx,wy=wy,area=T.AreaAt(m,x,y)}
end
for _,preference in ipairs({'fastest','safer'}) do
    WP.ClearAll(true);ns.Set('travelPreference',preference)
    ns.Set('travelFlights',false);ns.Set('travelBoats',false)
    move(actual(1424,.615,.209),3)
    C_Map.GetBestMapForUnit=function() return 1424 end
    wp=WP.Add(1416,.231,.604,{title='Bracers of Binding'})
    T.Steer(wp)
    check(T.Current() and T.CanWalk(T.Current().path[1].node,T.Current().target.node),preference..' quest 557 begins on a barrier-safe approach')
    move(actual(1424,.545,.35),3);T.Steer(wp)
    check(T.Current() and T.CanWalk(T.Current().path[1].node,T.Current().target.node),preference..' quest 557 joins an eligible approach after movement')
    local p=T.Current()
    check(p.path[1].node.wx==M.player.wx and p.path[1].node.wy==M.player.wy,preference..' quest 557 reanchors remaining route')
    move(actual(1424,.53,.32),3);T.Steer(wp)
    local route=T.Current()
    local blocked=false
    for i=2,#route.path do
        local a,b=route.path[i-1].node,route.path[i].node;local proof=ns.Terrain.Evidence(a,b)
        blocked=blocked or proof and proof.state=='TERRAIN_BLOCKED'
        if route.path[i].via=='walk' then blocked=blocked or not T.CanWalk(a,b) end
    end
    check(not blocked and T.CanWalk(route.path[1].node,route.target.node),preference..' quest 557 retains barriers and never steers a blocked chord')
end
print(('Reroute: %d passed, %d failed'):format(passed,failed))
if failed>0 then os.exit(1) end
