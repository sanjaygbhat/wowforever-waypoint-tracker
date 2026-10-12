-- Rerouting must preserve an authored ghost-corridor bend.
package.path='tests/?.lua;'..package.path
local M=require('wowmock')
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local T,G,WP=ns.Travel,ns.Geo,ns.WP
local rows={}
for i,p in ipairs({{.1,.5,1},{.2,.8,1},{.3,.5,1},{.4,.5,2}}) do
    local cont,wx,wy=G.MapToWorld(37,p[1],p[2])
    rows[i]=table.concat({'test',i,p[3],37,p[1]*100,p[2]*100,cont,wx,wy},'\t')
end
ns.TravelData={areas={'approach','body'},indoor={},nodes='',links='',maps='37\t1',
    regions='37\t2\t40\t50\t3',cities='',towns='',levels='',factors='',ghostCorridors=table.concat(rows,'\n')}
T._Reset();ns.Set('realRoutes',true);ns.Set('travelTrails',false);ns.Set('travelHearth',false)
C_Map.GetBestMapForUnit=function() return 37 end
for _, preference in ipairs({'safer', 'fastest'}) do
    T._Reset(); WP.ClearAll(true)
    ns.Set('travelPreference', preference)
    local cont,wx,wy=G.MapToWorld(37,.1,.5)
    M.player.inst,M.player.wx,M.player.wy=cont,wx,wy
    M.player.dead,M.player.ghost=true,true
    local wp=assert(WP.Add(37,.4,.5,{title='Synthetic body',silent=true,source='corpse',persistent=false}))
    local _,candidate=T.Choices(wp);assert(candidate)
    T.Select(wp,candidate)
    assert(T.Current().target.node.id=='test_2','initial search follows the corridor bend')
    for _, seconds in ipairs({3,30,300}) do
        M.now=M.now+seconds
        T.Steer(wp)
        local p=assert(T.Current())
        assert(p.target.node.id=='test_2',preference..' periodic retention preserves bend')
        assert(type(p.target.via)=='table' and p.target.via.corridor=='test' and p.target.via.ghostOnly,
            'repriced observed edge keeps corridor identity and ghost restriction')
        assert(not T.offerButton:IsShown(),'corpse route never offers a living-risk shortcut')
    end
    local _,fresh=T.Choices(wp)
    local found=false
    for _,e in ipairs(fresh.path) do if e.node.id=='test_2' then found=true end end
    assert(found,'a fresh search still retains the authored bend')
    -- A lateral rejoin approaches the projected point, then follows the
    -- authored segment; it must not replace that two-leg path with a chord.
    local points=assert(T.Data().ghostCorridors[1])
    local _,ax,ay=T.Pos(points[1]);local _,bx,by=T.Pos(points[2])
    local dx,dy=bx-ax,by-ay;local length=math.sqrt(dx*dx+dy*dy)
    M.player.wx,M.player.wy=(ax+bx)/2-20*dy/length,(ay+by)/2+20*dx/length
    M.now=M.now+3;T.Steer(wp)
    local retained=assert(T.Current())
    local leg
    for _,e in ipairs(retained.path) do
        if type(e.via)=='table' and e.via.corridor then leg=e.via;break end
    end
    local projection=assert(T.ProjectPolyline({points[1],points[2]},retained.here))
    assert(type(leg)=='table' and leg.corridor=='test', 'lateral rejoin keeps observed onward leg')
    assert(T.Dist(leg.from,projection.point)<1e-6, 'observed leg starts at the projection rather than at the off-trace player')
    assert(T.Dist(retained.path[2].node,projection.point)<1e-6 and retained.path[2].via=='walk', 'rejoin retains the perpendicular approach')
    -- Progress to the bend and then along the onward segment may advance it.
    cont,wx,wy=G.MapToWorld(37,.21,.77)
    M.player.inst,M.player.wx,M.player.wy=cont,wx,wy
    M.now=M.now+.1
    T.Steer(wp)
    assert(T.Current().target.node.id=='test_3','polyline progress advances a passed bend without replan')
    M.now=M.now+3;T.Steer(wp)
    assert(T.Current().target.node.id=='test_3','periodic rejoin retains onward segment')
end
assert(#M.errors==0,tostring(M.errors[1]))
print('PASS: safe/fast ghost bends, edge identity, periodic retention and segment progress')
