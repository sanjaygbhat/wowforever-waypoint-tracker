-- Launch boats, hostile Dalaran access and unmeasured new stop approaches.
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
ns.Geo.MapToWorld = function() return nil end
local T = ns.Travel
T._Reset()
local d = T.Data()
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL ' .. message) end
end
local function place(id)
    local n = assert(d.nodes[id], id)
    return {id=n.id, m=n.m, x=n.x, y=n.y, cont=n.cont0, wx=n.wx0, wy=n.wy0,
        area=n.area, city=n.city}
end
local function context(faction)
    return {faction=faction, class='WARRIOR', race='Skyborne', level=60,
        run=7, ground=7, flightFactor=1, flights=false, boats=true, jumps={}}
end
local function uses(path, a, b, method)
    for _, e in ipairs(path or {}) do
        local l = e.via
        if type(l) == 'table' and l.method == method and l.from.id == a and l.to.id == b then return true end
    end
    return false
end
for _, faction in ipairs({'Alliance', 'Horde'}) do
    local c = context(faction)
    for _, pair in ipairs({{'DOCK_STORMWIND','DOCK_AUBERDINE_STORMWIND'},
        {'DOCK_STEAMWHEEDLE_CLIENT_STOP','DOCK_POWDERFUSE_CLIENT_STOP'}}) do
        for direction=1,2 do
            local a,b = pair[direction],pair[3-direction]
            local path = T.Search(place(a),place(b),c)
            check(uses(path,a,b,'ship'), faction .. ' boards ' .. a .. '>' .. b)
        end
    end
    local a,b = 'DOCK_ZEPHRAS_ALLIANCE','DOCK_DALARAN'
    for direction=1,2 do
        local from,to = direction==1 and a or b,direction==1 and b or a
        local path = T.Search(place(from),place(to),c)
        check((uses(path,from,to,'ship') or false) == (faction=='Alliance'), faction .. ' Dalaran skyship access')
    end
    a,b = 'PORTAL_DALARAN_STORMWIND','PORTAL_STORMWIND_DALARAN'
    local path = T.Search(place(a),place(b),c)
    check((uses(path,a,b,'portal') or false) == (faction=='Alliance'), faction .. ' Dalaran portal access')
    local town = place('CITY_DALARAN')
    local risk = T.Danger(town,town,c,100)
    check((risk>0) == (faction=='Horde'), faction .. ' Dalaran guard exposure')
end
local a,b = 'DOCK_STEAMWHEEDLE_CLIENT_STOP','DOCK_POWDERFUSE_CLIENT_STOP'
local ride
for _, l in ipairs(d.out[a]) do if l.to.id==b and l.method=='ship' then ride=l end end
check(ride and ride.confidence=='unmeasured-traversal', 'placeholder boat timing remains explicitly unmeasured')
check(d.nodes.DOCK_POWDERFUSE.kind=='pass' and d.nodes.DOCK_STEAMWHEEDLE.kind=='pass',
    'superseded dock locations are terrain anchors only')
local fakeInn = false
for _, town in ipairs(d.towns) do if town.inn.accessFaction then fakeInn=true end end
check(not fakeInn, 'guard anchors must not be exposed as hearthstone inns')
check(#M.errors==0, 'no mock runtime errors')
print(('RESULT %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
