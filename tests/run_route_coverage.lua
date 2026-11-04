-- Fixed restored origin/destination profiles; new graphs cannot resample away losses.
package.path='tests/?.lua;'..package.path
local M=require('wowmock')
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
ns.Geo.MapToWorld=function()return nil end
local T=ns.Travel;T._Reset();local d=T.Data()
local function fields(line)
    local out={};for v in (line..'\t'):gmatch('(.-)\t')do out[#out+1]=v end;return out
end
local blocked={}
local f=assert(io.open('tests/fixtures/removed-blocked-walks.tsv'))
for line in f:lines()do local r=fields(line);blocked[r[1]..'>'..r[2]]=true;blocked[r[2]..'>'..r[1]]=true end
f:close()
local function position(id)
    local n=assert(d.nodes[id],'coverage endpoint removed: '..id)
    return {m=n.m,x=n.x,y=n.y,cont=n.cont0,wx=n.wx0,wy=n.wy0,area=n.area,city=n.city}
end
local cases,before,after,lost,gained,unexplained=0,0,0,0,0,0
local logPath=os.getenv('WT_COVERAGE_OUTPUT')
local log=logPath and assert(io.open(logPath,'w'))
if log then log:write('profile_pair\tbaseline\troutable\texplanation\n')end
f=assert(io.open('tests/fixtures/route-coverage-baseline.tsv'));f:read('*l')
for line in f:lines()do
    local r=fields(line);local faction,profile,a,b=r[1]:match('^(%w+)/([%w%-]+) ([^>]+)>(.+)$')
    assert(faction and a and b,'invalid fixed coverage profile')
    local known=T.Know().flights;wipe(known)
    for _,n in pairs(d.nodes)do
        if n.taxi then
            if profile=='all' or profile=='fast-flights' or profile=='ground-only' or profile=='least-actual-time'
                or profile=='alternating' and n.taxi%2==0 or profile=='sparse' and n.taxi%7==0 then known[n.taxi]=true
            elseif profile=='explicit-false' then known[n.taxi]=false end
        end
    end
    local ground=profile=='fast-flights' or profile=='ground-only' or profile=='least-actual-time'
    local c={faction=faction,class=profile=='druid-flight-dialogue' and 'DRUID' or 'WARRIOR',race='Human',level=60,
        run=7,ground=ground and 7 or 14,flightFactor=profile=='fast-flights' and 1/1.2 or 1,
        flights=profile~='ground-only',boats=profile~='ground-only',jumps={}}
    local path=T.Search(position(a),position(b),c)
    local was,now=r[2]=='1',path~=nil
    cases=cases+1;before=before+(was and 1 or 0);after=after+(now and 1 or 0)
    local reasons={}
    if was and not now then
        lost=lost+1;local previous
        for id in r[3]:gmatch('[^,]+')do
            if previous and blocked[previous..'>'..id]then reasons[#reasons+1]=previous..'>'..id end
            previous=id
        end
        if #reasons==0 then unexplained=unexplained+1;print('FAIL unexplained lost route: '..r[1])end
    elseif now and not was then gained=gained+1 end
    if log then log:write(table.concat({r[1],r[2],now and '1' or '0',table.concat(reasons,',')},'\t')..'\n');log:flush()end
end
f:close();if log then log:close()end
assert(cases==2658,'fixed baseline inventory changed')
print(('Coverage: %d profiles; baseline %d, current %d, delta %+d; %d lost, %d gained, %d unexplained'):
    format(cases,before,after,after-before,lost,gained,unexplained))
assert(unexplained==0,'lost routes must be explained by removed BLOCKED walking links')
