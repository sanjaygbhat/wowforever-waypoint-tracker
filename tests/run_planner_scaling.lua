-- Finite offline timing probes. Results are CPU timings, not client FPS.
package.path='tests/?.lua;'..package.path
local M=require('wowmock')
for _,f in ipairs({
    {1416,0,1500,783.33331298828,2799.99993896488,1866.66665649414},
    {1424,0,400,1066.6666259766,3199.9998779297,2133.3332519531},
    {1420,0,3837.4997558594,3033.3332519531,4518.7498779297,3012.49981689456},
    {1458,0,1877.9453125,873.19262695313,959.37503051758,640.1041259766},
    {1411,1,1808.3332519531,-1962.4998779297,5287.4996337891,3524.9998779297},
    {1454,1,2273.8771972656,-3680.6010742188,1402.6044921874,935.4166259765},
}) do
    M.maps[f[1]]={mapID=f[1],name=tostring(f[1]),cont=f[2],top=f[3],left=f[4],w=f[5],h=f[6],
        mapType=3,parentMapID=f[2]==0 and 13 or 12}
end
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local T,G=ns.Travel,ns.Geo
local d=T.Data();for id in pairs(d.byTaxi) do T.Know().flights[id]=true end
local biggest=0;for _,nodes in pairs(d.byArea) do biggest=math.max(biggest,#nodes) end
local count=0;for _ in pairs(d.nodes) do count=count+1 end
print('Shipped graph nodes='..count..' maximum nodes/area='..biggest..' towns='..#d.towns)
local function place(m,x,y)
    local cont,wx,wy=G.MapToWorld(m,x,y);local area,city=T.AreaAt(m,x,y)
    return {m=m,x=x,y=y,cont=cont,wx=wx,wy=wy,area=area,city=city}
end
local start,goal=place(1424,.5552,.2685),place(1454,.32,.378)
local c={faction='Horde',level=30,run=7,ground=7,flightFactor=1,flights=true,boats=true,jumps={}}
for _,policy in ipairs({'fastest','safer'}) do
    collectgarbage('collect')
    local before=collectgarbage('count');local began=os.clock()
    local _,route=T.Routes(start,goal,c,policy)
    print(string.format('Thrall %s Routes CPU=%.4fs heap delta=%.1f KiB ETA=%.1f',policy,
        os.clock()-began,collectgarbage('count')-before,assert(route).total))
end
-- Learned crossings have no runtime limit per area; stress a finite small set.
local rows={}
for i=1,200 do
    local cont,wx,wy=G.MapToWorld(37,.1+i/10000,.5)
    rows[i]=table.concat({'N'..i,'border',1,cont,wx,wy,37,(.1+i/10000)*100,50},'\t')
end
ns.TravelData={areas={'dense'},indoor={},nodes=table.concat(rows,'\n'),links='',maps='37\t1',
    regions='',cities='',towns='',levels='',factors=''}
T._Reset();d=T.Data()
for i=1,100 do d.towns[i]={area=i,fac='Alliance',inn=d.nodes['N'..i]} end
start,goal=place(37,.1,.5),place(37,.8,.5)
c.flights,c.boats=false,false
collectgarbage('collect');local began=os.clock()
local _, route = T.Routes(start,goal,c,'safer')
assert(route and route.total > 0 and route.risk >= 0 and route.path[#route.path].node == goal, 'dense planner still reaches the goal')
assert(#M.errors == 0, tostring(M.errors[1]))
print(string.format('Synthetic 200 same-area nodes + 100 enemy towns Routes CPU=%.4fs',os.clock()-began))
