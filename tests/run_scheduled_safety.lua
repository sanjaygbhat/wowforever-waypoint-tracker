-- A safer search must keep elapsed/risk alternatives before timed departures.
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker'); M.FireEvent('PLAYER_LOGIN')
local T,G = ns.Travel,ns.Geo
local function row(id,kind,area,map,x)
    local cont,wx,wy = G.MapToWorld(map,x,.5)
    return table.concat({id,kind,area,cont,wx,wy,map,x*100,50},'\t')
end
ns.TravelData = {areas={'S','A','B','C','P','D'},indoor={},maps='37\t1',regions='',
    nodes=table.concat({row('S','pass',1,37,.1),row('A','pass',2,52,.2),
        row('B','pass',3,52,.3),row('C','pass',4,37,.4),
        row('P','dock',5,37,.6),row('D','dock',6,37,.9)},'\n'),
    links=table.concat({'S\tA\twalk\t70\t\t\t1','A\tP\tportal\t40\t\t\t1',
        'S\tB\twalk\t100\t\t\t1','B\tP\tportal\t0\t\t\t1',
        'S\tC\twalk\t150\t\t\t1','C\tP\tportal\t0\t\t\t1',
        'P\tD\tship\t10\t10\t0\t1'},'\n'),
    cities='',towns='',levels='52\t60\t63',factors=''}
T._Reset(); local d=T.Data()
ns.Trails.NextDeparture=function(key,at)
    if key ~= 'P>D' then return nil end
    return 120 + math.max(0,math.ceil((at-120)/300))*300-at
end
local function place(node)
    local cont,wx,wy=G.MapToWorld(node.m,node.x,node.y)
    return {m=node.m,x=node.x,y=node.y,cont=cont,wx=wx,wy=wy,area=node.area}
end
local start,goal=place(d.nodes.S),place(d.nodes.D)
local c={faction='Horde',level=30,run=7,ground=7,flights=false,boats=true,flightFactor=1,jumps={}}
local function ids(path)
    local out={};for _,e in ipairs(path) do out[#out+1]=e.node.id or 'position' end
    return table.concat(out,',')
end
local choices,selected=T.Routes(start,goal,c,'safer')
assert(selected.total==130 and selected.risk==42 and selected.preference=='safer', 'safe route catches early departure with lowest feasible risk')
assert(choices[1].total==130 and choices[1].risk==60, 'fastest arrival remains distinct')
assert(not T.CanOffer(choices[1],selected), 'same-ETA riskier route has no faster offer')
print('Full graph selected: ETA='..selected.total..' risk='..selected.risk..' '..ids(selected.path))
c.preference='safer';c.measureDanger=true
local path,eta,risk=T.Search(start,goal,c)
print('Full graph safer search: ETA='..eta..' risk='..risk..' '..ids(path))
-- Removing a competitor reveals an already feasible lower-risk, equal-ETA path.
local saved=d.out.S
d.out.S={saved[1],saved[2]}
local better,beta,brisk=T.Search(start,goal,c)
d.out.S=saved
print('Feasible alternative: ETA='..beta..' risk='..brisk..' '..ids(better))
for _, order in ipairs({{1,2,3},{1,3,2},{2,1,3},{2,3,1},{3,1,2},{3,2,1}}) do
    d.out.S={saved[order[1]],saved[order[2]],saved[order[3]]}
    local _, route=T.Routes(start,goal,c,'safer')
    assert(route.total==130 and route.risk==42, 'nondominated labels survive every approach enumeration order')
end
d.out.S=saved
local ok=selected.total==beta and selected.risk<=brisk
print((ok and 'PASS: ' or 'FAIL: ')..'Safer must not choose a dominated itinerary')
assert(#M.errors==0,tostring(M.errors[1]))
os.exit(ok and 0 or 1)
