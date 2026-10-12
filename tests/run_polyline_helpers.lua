-- Correct projection check: Geo.WorldToMap returns x,y, not continent,x,y.
package.path='tests/?.lua;'..package.path
local M=require('wowmock')
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local T,G=ns.Travel,ns.Geo
local rows={}
for i,x in ipairs({.1,.2,.3}) do
    local cont,wx,wy=G.MapToWorld(37,x,.5)
    rows[i]=table.concat({'test',i,1,37,x*100,50,cont,wx,wy},'\t')
end
ns.TravelData={areas={'test'},indoor={},nodes='',links='',maps='37\t1',regions='',cities='',towns='',levels='',factors='',ghostCorridors=table.concat(rows,'\n')}
T._Reset();local points=assert(T.Data().ghostCorridors[1])
local cont,wx,wy=G.MapToWorld(37,.15,.5)
local projection=assert(T.ProjectPolyline(points,{cont=cont,wx=wx,wy=wy}))
local length=T.Dist(points[1],points[2])
local target=T.LookAhead(points,projection,length*.8)
local x,y=G.WorldToMap(target.cont,target.wx,target.wy,37)
assert(math.abs(x-.23)<1e-6 and math.abs(y-.5)<1e-6,'continue into next segment')
local advanced=assert(T.ProjectPolyline(points,{cont=cont,wx=wx,wy=wy},1,3,length*1.2))
assert(advanced.progress>=length*1.2,'projection cannot retreat below the floor')
local final=T.LookAhead(points,advanced,length*10)
local fx=G.WorldToMap(final.cont,final.wx,final.wy,37)
assert(math.abs(fx-.3)<1e-6,'lookahead clamps to the final point')
assert(#M.errors==0,tostring(M.errors[1]))
print('PASS: parsed ghost nodes, lookahead across a vertex, monotonic floor, endpoint clamp')
