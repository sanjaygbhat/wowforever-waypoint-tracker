-- Exercise the arrow between planner ticks: a laterally passed vertex must
-- advance by segment progress even while that vertex is still the nearest.
package.path='tests/?.lua;'..package.path
local M=require('wowmock')
function UnitFactionGroup() return 'Horde' end
function GetUnitSpeed() return 7,7 end
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local T,G,WP=ns.Travel,ns.Geo,ns.WP
local pass,fail=0,0
local function check(ok,why)
    if ok then pass=pass+1 else fail=fail+1;print('FAIL: '..why) end
end
local function point(x,y,area)
    local c,wx,wy=G.MapToWorld(37,x,y)
    return {m=37,x=x,y=y,cont=c,wx=wx,wy=wy,area=area or 1}
end
local function row(id,kind,x,area,taxi)
    local p=point(x,.5,area)
    return table.concat({id,kind,p.area,p.cont,p.wx,p.wy,37,x*100,50,'','',taxi or '',taxi and 'Horde' or ''},'\t')
end
ns.TravelData={areas={'road','landing'},indoor={},maps='37\t1',regions='',cities='',towns='',levels='',factors='',
    nodes=table.concat({row('P','pass',.3),row('Q','pass',.6),row('FM','taxi',.7,1,1),row('LAND','taxi',.9,2,2)},'\n'),
    links='FM\tLAND\ttaxi\t60\tHorde\t\t1'}
T._Reset();local d=T.Data();T.Know().flights[1]=true;T.Know().flights[2]=true
ns.Set('realRoutes',true);ns.Set('travelTrails',false);ns.Set('travelHearth',false)
C_Map.GetBestMapForUnit=function() return 37 end
local start=point(.2,.5)
local function move(p,dt)
    M.player.inst,M.player.wx,M.player.wy=p.cont,p.wx,p.wy;M.now=M.now+dt
end
local function choose(pref)
    WP.ClearAll(true);move(start,3)
    local wp=WP.Add(37,.9,.5,{title='Segment destination'})
    local path={{node=start,at=0,risk=0},{node=d.nodes.P,via='walk',at=60,risk=0},
        {node=d.nodes.Q,via='walk',at=180,risk=0},{node=d.nodes.FM,via='walk',at=240,risk=0},
        {node=d.nodes.LAND,via=d.out.FM[1],at=300,risk=0}}
    T.Select(wp,{path=path,total=300,risk=0,preference=pref})
    return wp
end
for _,pref in ipairs({'fastest','safer'}) do
    local wp=choose(pref)
    local beyond=point(.305,.51)
    move(beyond,.1)
    local s=T.Steer(wp)
    check(T.Dist(beyond,d.nodes.P)<T.Dist(beyond,d.nodes.Q),pref..' old vertex remains nearest')
    check(T.Current().target.node.id=='Q',pref..' projection advances beyond old vertex before replan')
    local _,px,py=T.Pos(d.nodes.P);local _,qx,qy=T.Pos(d.nodes.Q)
    local length=math.sqrt((qx-px)^2+(qy-py)^2)
    local forward=((s.aim.wx-beyond.wx)*(qx-px)+(s.aim.wy-beyond.wy)*(qy-py))/length
    check(forward>44.9 and forward<45.1,pref..' arrow looks 45 yards forward, never backwards')
    local progress=s.progress
    move(point(.303,.51),.1);s=T.Steer(wp)
    check(s.progress>=progress,pref..' projected progress cannot retreat between plans')
    move(point(.32,.51),.31);T.Steer(wp)
    check(T.Current().path[1].node.wx==M.player.wx,pref..' movement replans from current position')
    wp=choose(pref);d.nodes.P.kind='entrance';move(beyond,.1);s=T.Steer(wp)
    check(T.Current().target.node.id=='P',pref..' unreached doorway caps projection')
    check(T.Dist(s.aim,d.nodes.P)<.001,pref..' lookahead cannot pass doorway gate')
    d.nodes.P.kind='pass'
    wp=choose(pref);move(point(.73,.53),.1);s=T.Steer(wp)
    check(T.Current().target.node.id=='FM',pref..' projection cannot pass flight origin')
    check(T.Dist(s.aim,d.nodes.FM)<.001,pref..' lookahead stops at flight boarding gate')
    wp=choose(pref)
    d.barriers={{point(.4,.505),point(.4,.52)}}
    move(beyond,.1);s=T.Steer(wp)
    check(T.Current().target.node.id=='P',pref..' road bend protected when shortcut crosses barrier')
    d.barriers={}
end
-- A chosen preview may begin away from its old first segment. Deviation
-- triggers a search even without ten yards of movement since selection.
local wp=choose('fastest')
local current=T.Current()
local off=point(.205,.54)
move(off,0);T.Select(wp,current)
local planned=0;ns.On('TRAVEL_PLANNED',function() planned=planned+1 end)
M.now=M.now+.51;T.Steer(wp)
check(planned==1,'40-yard lateral deviation triggers current-position search after half a second')
check(T.Current().path[1].node.wx==off.wx,'deviation search reanchors the route')
-- The learned-grid follower uses the same segment projection rather than
-- scanning the last nearby cell vertex. Feed a directed straight walked path.
local st=WaypointTrackerDB.trails;st.own[0]={}
for x=0,20 do st.own[0][ns.Trails._Key(x,0)]=1 end
local target={cont=0,wx=410,wy=10}
local bearing=ns.Trails.Steer({cont=0,wx=55,wy=30},target)
check(bearing and math.abs(bearing-math.atan2(-20,45))<1e-6,'grid arrow uses segment projection and exact lookahead')
M.now=M.now+.1
bearing=ns.Trails.Steer({cont=0,wx=75,wy=30},target)
check(bearing and math.abs(bearing-math.atan2(-20,45))<1e-6,'grid progress advances between cached searches')
check(#M.errors==0,'mock event handlers have no errors')
print(('Projection: %d passed, %d failed'):format(pass,fail))
if fail>0 then os.exit(1) end
