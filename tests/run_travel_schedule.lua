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
local _,selected=T.Routes(start,goal,c,'safer')
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
local ok=selected.total==beta and selected.risk<=brisk
print((ok and 'PASS: ' or 'FAIL: ')..'Safer must not choose a dominated itinerary')
assert(#M.errors==0,tostring(M.errors[1]))
os.exit(ok and 0 or 1)
