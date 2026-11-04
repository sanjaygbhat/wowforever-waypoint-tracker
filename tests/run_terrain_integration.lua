-- Production evidence, planner and automatic ground recording under Lua 5.1.
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')
local moving, mode, height = 7, nil, 0
local secret=setmetatable({},{__tostring=function() error('secret conversion') end,__sub=function() error('secret arithmetic') end})
local originalSecret=issecretvalue
issecretvalue=function(v) return rawequal(v,secret) or originalSecret(v) end
function GetUnitSpeed() return moving,7,7,4.7 end
function IsSwimming() return mode == 'swim' end
function IsFlying() return mode == 'fly' end
function IsFalling() return mode == 'fall' end
function UnitInVehicle() return mode == 'vehicle' end
function GetInstanceInfo() return '', 'none', 0, '', 0, 0, false, 0 end
function GetServerTime() return 1700000000 + math.floor(M.now) end
local realPosition = UnitPosition
function UnitPosition() local x,y,_,c = realPosition(); return x,y,height,c end
local ns = M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker'); M.FireEvent('PLAYER_LOGIN')
local T,E = ns.Travel,ns.Terrain
local passed = 0
local function check(v,label) assert(v,label);passed=passed+1 end
local d=T.Data()
local crossingA=d.nodes.BORDER_THOUSAND_NEEDLES_TO_FERALAS
local crossingB=d.nodes.BORDER_FERALAS_TO_THOUSAND_NEEDLES
local cont,wx,wy=T.Pos(crossingA)
local clone={cont=cont,wx=wx,wy=wy,m=crossingA.m,area=crossingA.area,city=crossingA.city}
check(E.Evidence(clone,crossingB)==E.Evidence(crossingA,crossingB),
    'coordinate clone preserves map/area identity at overlapping border anchors')
local seen,clear,uncertain,blocked = {},0,0,0
for _,e in pairs(d.walkEvidence) do
    if not seen[e] then
        seen[e]=true
        check(e.provenance:find('terrain-static',1,true) or e.provenance:find('unmeasured',1,true),'provenance retained')
        if e.state == 'TERRAIN_BLOCKED' then
            blocked=blocked+1
            check(not T.CanWalk(e.a.node,e.b.node),'blocked chord rejected in both representations')
            local ac,ax,ay=T.Pos(e.a.node);local bc,bx,by=T.Pos(e.b.node)
            if T.Dist(e.a.node,e.b.node)>0 then
                check(not T.CanWalk({cont=ac,wx=ax,wy=ay},{cont=bc,wx=bx,wy=by}),'coordinate clones cannot bypass verdict')
            end
            if T.Dist(e.a.node,e.b.node)>60 then
                check(not T.CanWalk({cont=ac,wx=(ax+bx)/2,wy=(ay+by)/2},{cont=bc,wx=bx,wy=by}),'partial blocked chord over 30 yards cannot bypass verdict')
            end
        elseif e.state == 'TERRAIN_CLEAR' then clear=clear+1
        else uncertain=uncertain+1 end
    end
end
check(clear>300 and blocked>60 and uncertain>0,'verified connections, refuted shortcuts and labelled necessary passages loaded')
local activeCount,pendingCount=0,0
for _,n in pairs(d.nodes) do if n.terrainOnly then activeCount=activeCount+1 end end
check(activeCount>0 and ns.TravelData.walkCandidates:match('^%s*$') and ns.TravelData.walkCandidateEdges:match('^%s*$'),'only usable verified positions remain isolated from inference')

-- Small real-map fixture: the shortest chord is blocked; the connected
-- candidate has an uncertain gap and a static-clear bend, without shortcuts.
local function row(id,x,y,kind)
    local c,wx,wy=ns.Geo.MapToWorld(37,x,y)
    return table.concat({id,kind or 'border',1,c,wx,wy,37,x*100,y*100},'\t')
end
local rows={row('A',.10,.50),row('B',.12,.50),row('TERRAIN_C',.11,.49,'pass')}
local function fields(s) local a={};for v in s:gmatch('[^\t]+') do a[#a+1]=v end;return a end
local def={};for _,r in ipairs(rows) do local f=fields(r);def[f[1]]=f end
local function ev(a,b,state)
    local f={a,b,state,'terrain-static,unverified-collision','1.60.1.70338',a..b,'source','chain'}
    for _,id in ipairs({a,b}) do for j=4,9 do f[#f+1]=def[id][j] end end
    return table.concat(f,'\t')
end
local function fixture(extra)
    ns.TravelData={buildKey='fixture-70338',areas={'test'},indoor={},nodes=table.concat(rows,'\n'),
        links='TERRAIN_C\tB\twalk\t0' .. (extra and '\nA\tB\tgate\t100' or ''),maps='37\t1',
        walkEvidence=table.concat({ev('A','B','TERRAIN_BLOCKED'),ev('A','TERRAIN_C','UNCERTAIN'),ev('TERRAIN_C','B','TERRAIN_CLEAR')},'\n'),
        walkCandidateEdges='A\tTERRAIN_C'}
    T._Reset();d=T.Data();WaypointTrackerDB.terrain=nil
    return d.nodes.A,d.nodes.B,d.nodes.TERRAIN_C
end
local c={faction='Alliance',level=60,run=7,ground=7,flights=false,boats=false,flightFactor=1,jumps={}}
local a,b,bend=fixture(false)
for _,policy in ipairs({'fastest','safer'}) do
    local _,route=T.Routes(a,b,c,policy)
    check(route and #route.path==3 and route.path[2].node==bend,'detour preserves ordered bend under '..policy)
    check(route.terrainPenalty>120 and route.risk==0,'geometry penalty is separate from ETA/danger')
    for i=2,#route.path do local e=E.Evidence(route.path[i-1].node,route.path[i].node);check(e and e.state~='TERRAIN_BLOCKED','no blocked walk produced') end
end
check(T.CanWalk(a,bend),'indexed uncertain gap remains separately available')
local arbitrary={m=37,x=.105,y=.505,area=1}
check(not T.CanWalk(arbitrary,bend),'new point cannot infer unchecked all-to-all shortcut')
local before=T.Current()
-- Normal movement at 5 Hz, near the exact endpoints, driven through the
-- production ticker. No recorder/test hook confirms a leg directly.
ns.Set('realRoutes',true);ns.Set('travelTrails',true)
local function resetMovement()
    moving,mode,height=7,nil,0;M.player.ghost,M.player.dead,M.player.taxi,M.player.combat=false,false,false,false
    M.FireEvent('PLAYER_ENTERING_WORLD')
end
local function walk(from,to,walkMode,curve)
    resetMovement();mode=walkMode
    if walkMode=='ghost' then M.player.ghost=true end
    if walkMode=='taxi' then M.player.taxi=true end
    local cont,x,y=T.Pos(from);local _,tx,ty=T.Pos(to)
    local distance=math.sqrt((tx-x)^2+(ty-y)^2);local steps=math.ceil(distance/1.2)
    M.player.inst=cont
    for i=0,steps do
        local t=i/steps;local offset=curve and 8*math.sin(t*math.pi) or 0
        M.player.wx,M.player.wy=x+t*(tx-x)-(ty-y)/distance*offset,y+t*(ty-y)+(tx-x)/distance*offset
        M.Tick(.2)
    end
end
local proof=E.Evidence(a,bend)
for _,bad in ipairs({'ghost','taxi','swim','fly','fall','vehicle'}) do
    walk(a,bend,bad)
    check(not E.Record(proof),'excluded '..bad..' never confirms living segment')
end
-- Sparse endpoint visits and teleport cannot confirm.
resetMovement();local cont,x,y=T.Pos(a);M.player.inst,M.player.wx,M.player.wy=cont,x,y;M.Tick(.2)
local _,tx,ty=T.Pos(bend);M.player.wx,M.player.wy=tx,ty;M.Tick(.2)
check(not E.Record(proof),'teleport endpoint visits rejected')
walk(a,bend)
check(E.Record(proof) and E.Record(proof).state=='confirmed','continuous ground traversal confirms')
local _,route=T.Routes(a,b,c,'fastest')
check(route and route.terrainPenalty<120,'confirmation changes planner surcharge')
check(E.Store().version==1 and WaypointTrackerDB.terrain.records[proof.key],'account-wide bounded persistence')
-- Force schema reload as on another character/account login.
local saved=WaypointTrackerDB.terrain;local priorDB=WaypointTrackerDB
local liveBuild=GetBuildInfo;GetBuildInfo=function() return 'new','99999' end
check(not E.Record(proof),'build change invalidates observation');GetBuildInfo=liveBuild
local actualScope=GetInstanceInfo;GetInstanceInfo=function() return '', '', 0, '', 0, 0, false, 99 end
check(not E.Record(proof),'instance change invalidates observation');GetInstanceInfo=actualScope
height=50;E.Refresh();check(not E.Record(proof),'different endpoint floor never inherits ground proof');height=0;E.Refresh()
WaypointTrackerDB={terrain=saved};check(E.Store().records[proof.key],'persisted exact proof migrates')
WaypointTrackerDB={terrain={version=999,records=saved.records}};check(next(E.Store().records)==nil,'future schema never grants proof')
WaypointTrackerDB={terrain={version=1,records={bad={state='confirmed',build='fixture-70338',when=0,scope=0,points={{0/0,0},{0,0}}}}}};
check(next(E.Store().records)==nil,'malformed numeric proof discarded')
WaypointTrackerDB={terrain={version=1,records={secret={state='confirmed',build='fixture-70338',scope=0,when=secret,points={{0,0},{1,1}}}}}}
check(next(E.Store().records)==nil,'secret SavedVariables never become proof')
local many={};for i=1,200 do many['entry'..i]={state='refuted',build='fixture-70338',scope=0,when=GetServerTime(),expires=GetServerTime()+100} end
WaypointTrackerDB={terrain={version=1,records=many}}
local count=0;for _ in pairs(E.Store().records) do count=count+1 end;check(count==128,'oversized saves migrate to bounded record limit')
WaypointTrackerDB=priorDB;E.Store()
resetMovement();moving=secret;local ok=pcall(E.Sample);check(ok,'secret movement speed is rejected safely');moving=7
local positionAPI=UnitPosition;UnitPosition=function() return secret,secret,secret,secret end
ok=pcall(E.Sample);check(ok,'secret position components are rejected safely');UnitPosition=positionAPI
-- A curve is retained as actual steering points, rather than approving its
-- original straight chord. The blocked chord itself always stays blocked.
walk(a,b,nil,true)
local blockedProof=E.Evidence(a,b)
check(E.Record(blockedProof) and not T.CanWalk(a,b),'curved traversal never certifies blocked straight chord')
local path=T.Search(a,b,c)
check(path and #path>3,'observed ground polyline preserves bends in returned plan')
for i=2,#path do check(type(path[i].via)=='table' and path[i].via.terrain or path[i].via=='walk' and T.Dist(path[i-1].node,path[i].node)<=3,'learned vertices retain exact segments and short endpoint connectors') end

local walked=E.Record(blockedProof).points
local middle={cont=0,wx=walked[3][1],wy=walked[3][2],m=37,area=1}
for _,policy in ipairs({'fastest','safer'}) do
    local _,joined=T.Routes(middle,b,c,policy)
    check(joined and joined.path[2].node~=a,'replanning rejoins learned polyline under '..policy)
    for i=2,#joined.path do check(joined.path[i].node~=a,'learned corridor does not point back to origin') end
end
-- Repeated moving turnbacks cause a temporary refutation and a new route.
a,b,bend=fixture(false);proof=E.Evidence(a,bend)
walk(a,bend);walk(bend,b)
local alternate={id='D',kind='border',m=37,x=.11,y=.53,area=1}
d.nodes.D=alternate;d.byArea[1][#d.byArea[1]+1]=alternate
local confirmed=T.Search(a,b,c)
check(confirmed and confirmed[2].node==bend,'confirmed detour beats longer ordinary alternative')
resetMovement();cont,x,y=T.Pos(a);local _,cx,cy=T.Pos(bend)
local len=math.sqrt((cx-x)^2+(cy-y)^2)
local function at(distance)
    M.player.inst,M.player.wx,M.player.wy=cont,x+distance/len*(cx-x),y+distance/len*(cy-y);M.Tick(.2)
end
at(0)
for attempt=1,3 do for i=(attempt==1 and 1 or 10),22 do at(i) end;for i=21,10,-1 do at(i) end end
check(E.Record(proof) and E.Record(proof).state=='refuted','three moving turnbacks refute temporarily')
check(select(2,E.Decide(a,bend))==2,'refutation raises fallback cost')
local refuted=T.Search(a,b,c);check(refuted and refuted[2].node==alternate,'refutation changes routing to available alternative')
local st=E.Store();st.records[proof.key].expires=GetServerTime()-1
check(not E.Record(proof),'refutation expires without permanently poisoning network')
resetMovement();moving=0;at(0);for i=1,100 do M.Tick(.2) end
check(not E.Record(proof),'stationary player never refutes')
check(#M.errors==0,tostring(M.errors[1]))
print('Terrain integration: '..passed..' passed, 0 failed')
