-- Local, exact terrain evidence. Static ADT clearance is provisional collision
-- evidence. Old grid cells and shared votes never promote an exact chord.
local _, ns = ...
local Terrain = {}
ns.Terrain = Terrain
local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor
local LIMIT, POINTS, SAMPLE, TTL = 128, 128, .2, 600
local evidence, endpoints, buckets, active, blocked = {}, {}, {}, {}, {}
-- the same buckets by number, grid[cont][ix][iy] (no key strings to build)
local grid = {}
local loaded, database, last, elapsed, floorPosition = nil, nil, nil, 0, nil

local function Number(v)
    v = ns.Num(v)
    return v and v == v and abs(v) < 1e12 and v or nil
end
local function Plain(v) return ns.Plain and ns.Plain(v) or (not issecretvalue or not issecretvalue(v)) and v end
local function Flag(fn)
    if not fn then return false end
    local v = Plain(fn("player"))
    return v == nil or v and true or false
end
local function Clock() return Number(GetServerTime and GetServerTime()) or Number(time and time()) or 0 end
local function Scope()
    local id = 0
    if GetInstanceInfo then
        local _, _, _, _, _, _, _, value = GetInstanceInfo()
        id = Number(value)
        if not id then return nil end
    end
    return id
end
local NONE = {} -- an empty bucket (never written)
local function Bucket(cont, x, y) return cont .. ":" .. floor(x/64) .. ":" .. floor(y/64) end
local function Position(n)
    local c, x, y = ns.Geo.MapToWorld(n.m, n.x, n.y)
    if not c then c, x, y = n.cont0, n.wx0, n.wy0 end
    return c, x, y
end
local function Distance(a, b) return sqrt((a.wx-b.wx)^2 + (a.wy-b.wy)^2) end
local function Projection(a, b, x, y)
    local dx, dy = b.wx-a.wx, b.wy-a.wy
    local length2 = dx*dx+dy*dy
    local t = length2 > 0 and ((x-a.wx)*dx+(y-a.wy)*dy)/length2 or 0
    local q = min(1, max(0, t))
    return t, sqrt((x-a.wx-q*dx)^2+(y-a.wy-q*dy)^2)
end
local function Store()
    local db = Plain(WaypointTrackerDB)
    if type(db) ~= "table" then return nil end
    if database == db and type(db.terrain) == "table" then return db.terrain end
    database = db
    local old = Plain(db.terrain)
    local st = { version = 1, records = {} }
    -- Whitelist the schema and every persisted value. No legacy cells/logs
    -- migrate into proof, and unknown future versions cannot be misread.
    if type(old) == "table" and Plain(old.version) == 1 and type(Plain(old.records)) == "table" then
        local count = 0
        for key, value in pairs(old.records) do
            key, value = Plain(key), Plain(value)
            if count < LIMIT and type(key) == "string" and #key <= 256 and type(value) == "table" then
                local state, build, scope = Plain(value.state), Plain(value.build), Number(value.scope)
                local when, expires = Number(value.when), Number(value.expires)
                if (state == "confirmed" or state == "refuted") and type(build) == "string" and #build <= 128 and scope and when then
                    local r = { state = state, build = build, scope = scope, when = when, expires = expires,
                        count = min(99, max(1, Number(value.count) or 1)) }
                    local points = Plain(value.points)
                    if state == "confirmed" and type(points) == "table" and #points >= 2 and #points <= POINTS then
                        r.points = {}
                        for i = 1, #points do
                            local p = Plain(points[i])
                            local x, y, z
                            if type(p) == "table" then x, y, z = Number(p[1]), Number(p[2]), Number(p[3]) end
                            if not x or not y then r.points = nil; break end
                            r.points[i] = { x, y, z }
                        end
                    end
                    if state == "refuted" and expires and expires > Clock() or r.points then
                        st.records[key], count = r, count + 1
                    end
                end
            end
        end
    end
    db.terrain = st
    return st
end
Terrain.Store = Store

local function Save(e, state, points)
    local st, scope = Store(), Scope()
    if not st or not scope then return end
    local old = st.records[e.key]
    local count, oldest, oldestTime = 0, nil, math.huge
    for key, r in pairs(st.records) do
        count = count + 1
        if r.when < oldestTime then oldest, oldestTime = key, r.when end
    end
    if not old and count >= LIMIT then st.records[oldest] = nil end
    st.records[e.key] = { state = state, points = points, build = loaded.buildKey,
        scope = scope, when = Clock(), expires = state == "refuted" and Clock()+TTL or nil,
        count = min(99, (old and old.count or 0)+1) }
    if ns.Travel then ns.Travel.Invalidate() end
end

function Terrain.Load(T, d, rows)
    evidence, endpoints, buckets, active, blocked, last, loaded = {}, {}, {}, {}, {}, nil, d
    grid = {}
    rows(T.walkCandidates, function(f)
        if not d.nodes[f[1]] then
            d.nodes[f[1]] = { id = f[1], kind = "pass", area = tonumber(f[3]), cont0 = tonumber(f[4]),
                wx0 = tonumber(f[5]), wy0 = tonumber(f[6]), m = tonumber(f[7]),
                x = tonumber(f[8])/100, y = tonumber(f[9])/100, terrainOnly = true }
        end
    end)
    for id, n in pairs(d.nodes) do
        if id:find("^TERRAIN_") then n.terrainOnly = true end
    end
    local function Endpoint(n)
        if endpoints[n.id] then return endpoints[n.id] end
        local cont, x, y = Position(n)
        if not cont or not x or not y then return nil end
        local p = { id = n.id, cont = cont, wx = x, wy = y, node = n, edges = {} }
        endpoints[n.id] = p
        local key = Bucket(cont,x,y); buckets[key] = buckets[key] or {}
        buckets[key][#buckets[key]+1] = p
        -- the same list by number; a "-0" key (x or y exactly -0) is never
        -- asked for by its string, so it isn't found by number either
        local ix, iy = floor(x/64), floor(y/64)
        if not (ix == 0 and 1/ix < 0) and not (iy == 0 and 1/iy < 0) then
            local byX = grid[cont] or {}; grid[cont] = byX
            local byY = byX[ix] or {}; byX[ix] = byY
            byY[iy] = buckets[key]
        end
        return p
    end
    d.walkEvidence = evidence
    rows(T.walkEvidence, function(f)
        local a, b = d.nodes[f[1]], d.nodes[f[2]]
        if not a or not b then return end
        local function Matches(n, offset)
            return n.cont0 == tonumber(f[offset]) and n.wx0 == tonumber(f[offset+1]) and n.wy0 == tonumber(f[offset+2])
                and n.m == tonumber(f[offset+3]) and abs(n.x-tonumber(f[offset+4])/100) < 1e-9
                and abs(n.y-tonumber(f[offset+5])/100) < 1e-9
        end
        if not Matches(a,9) or not Matches(b,15) then return end
        local pa, pb = Endpoint(a), Endpoint(b)
        if not pa or not pb or pa.cont ~= pb.cont then return end
        local ids = a.id < b.id and a.id .. ">" .. b.id or b.id .. ">" .. a.id
        local e = { a = pa, b = pb, state = f[3], provenance = f[4], chain = f[8],
            key = ids .. ":" .. f[6], fingerprint = f[6] }
        -- Map API and generated fallback coordinates have distinct scopes.
        e.key = e.key .. ":" .. string.format("%.3f,%.3f,%.3f,%.3f",pa.wx,pa.wy,pb.wx,pb.wy)
        e.key = e.key .. ":" .. (pa.wx == a.wx0 and pa.wy == a.wy0 and pb.wx == b.wx0 and pb.wy == b.wy0 and "fallback" or "native")
        evidence[a.id .. ">" .. b.id], evidence[b.id .. ">" .. a.id] = e, e
        pa.edges[#pa.edges+1], pb.edges[#pb.edges+1] = e, e
        if e.state == "TERRAIN_BLOCKED" then blocked[#blocked+1] = e end
    end)
    rows(T.walkCandidateEdges, function(f)
        local a, b = d.nodes[f[1]], d.nodes[f[2]]
        local e = evidence[f[1] .. ">" .. f[2]]
        if not a or not b or not e or e.state ~= "UNCERTAIN" then return end
        for _, pair in ipairs({{a,b},{b,a}}) do
            local list = d.out[pair[1].id] or {}; d.out[pair[1].id] = list
            list[#list+1] = { from = pair[1], to = pair[2], method = "walk", cost = 0,
                key = pair[1].id .. ">" .. pair[2].id, terrain = true, candidate = true }
        end
    end)
end

-- The nine buckets around a point. Resolve and Sample read the same ones
-- in this order by number (grid), which is what runs; this is the lookup
-- they mirror.
local function Nearby(cont, x, y, visit)
    local ix, iy = floor(x/64), floor(y/64)
    for dx = -1,1 do for dy = -1,1 do
        for _, p in ipairs(buckets[cont .. ":" .. (ix+dx) .. ":" .. (iy+dy)] or {}) do visit(p) end
    end end
end
local function Resolve(n)
    if n.id then return endpoints[n.id] end
    if n.terrainEndpoint ~= nil then return n.terrainEndpoint or nil end
    -- a place that carries its world position (the player's) is never looked
    -- up on the map: that lookup's answer went unused, and kept a moving
    -- position in Geo's cache of fixed points
    local cont, x, y
    if n.cont ~= nil then cont, x, y = n.cont, n.wx, n.wy else cont, x, y = Position(n) end
    if not cont or not x or not y then return nil end
    local best, dd = nil, 1.1
    -- Nearby's nine buckets in Nearby's order, without a key string or a
    -- function per call (this runs every frame for the player)
    local byX = grid[cont]
    if byX then
        local ix, iy = floor(x/64), floor(y/64)
        for gx = ix-1, ix+1 do
            local byY = byX[gx]
            if byY then
                for gy = iy-1, iy+1 do
                    for _, p in ipairs(byY[gy] or NONE) do
                        local distance = sqrt((p.wx-x)^2+(p.wy-y)^2)
                        if distance < dd and (not n.area or p.node.area == n.area)
                            and (not n.m or p.node.m == n.m) then best,dd = p,distance end
                    end
                end
            end
        end
    end
    n.terrainEndpoint = best or false
    return best
end
function Terrain.Evidence(a,b)
    if not loaded then return nil end
    local pa,pb = Resolve(a),Resolve(b)
    return pa and pb and evidence[pa.id .. ">" .. pb.id] or nil
end
function Terrain.At(n)
    local p = Resolve(n)
    return p and p.edges or {}
end
-- A route search spread over frames (a coroutine, Travel's sliced planning)
-- reads the floor position it began with, never one Terrain.Sample wrote
-- between its slices: each search's own, by the coroutine it runs in (false:
-- none). Searches in the main thread read floorPosition, as always.
local searchFloor = setmetatable({}, { __mode = "k" })
local function Thread()
    local running = type(coroutine) == "table" and coroutine.running
    if not running then return nil end
    local co, main = running()
    if co and not main then return co end
end
function Terrain.Refresh()
    floorPosition=nil
    if UnitPosition then
        local x,y,z,c=UnitPosition("player")
        x,y,z,c=ns.Num(x),ns.Num(y),ns.Num(z),ns.Num(c)
        if x and y and z and c then floorPosition={wx=x,wy=y,z=z,cont=c} end
    end
    local co = Thread()
    if co then searchFloor[co] = floorPosition or false end
end
-- Records are applied only on the client build they were surveyed for. On
-- any other build Terrain.Record answers nil whatever is stored, so nothing
-- the sampler writes (traces, the floor position) is ever read there.
local function RecordsApply()
    if GetBuildInfo then
        local _,build = GetBuildInfo();build=ns.Str(build)
        if build and tostring(build) ~= "70338" then return false end
    end
    return true
end
Terrain.RecordsApply = RecordsApply
function Terrain.Record(e)
    local st = Store()
    local r = st and st.records[e.key]
    if not r or r.build ~= loaded.buildKey or r.scope ~= Scope() then return nil end
    if not RecordsApply() then return nil end
    local floorAt = floorPosition
    local co = Thread()
    if co and searchFloor[co] ~= nil then floorAt = searchFloor[co] or nil end
    if r.points and floorAt and floorAt.cont==e.a.cont then
        for _,index in ipairs({1,#r.points}) do
            local p=r.points[index]
            if p[3] and (floorAt.wx-p[1])^2+(floorAt.wy-p[2])^2 <= 36
                and abs(floorAt.z-p[3]) > 3 then return nil end
        end
    end
    if r.state == "refuted" and (r.expires or 0) <= Clock() then st.records[e.key] = nil; return nil end
    return r
end
-- Return a separate geometry surcharge; ETA and danger retain their meanings.
local function Bent(e,r)
    if not r or not r.points or #r.points<3 then return false end
    for _,p in ipairs(r.points) do
        local _,deviation=Projection(e.a,e.b,p[1],p[2])
        if deviation > (e.state=="TERRAIN_BLOCKED" and 4 or .5) then return true end
    end
    return false
end
function Terrain.Corridors()
    local list,seen={},{}
    for _,e in pairs(evidence) do
        if not seen[e] then
            seen[e]=true;local r=Terrain.Record(e)
            if r and r.state=="confirmed" and Bent(e,r) then list[#list+1]={e=e,r=r} end
        end
    end
    table.sort(list,function(a,b) return a.e.key<b.e.key end)
    return list
end
-- The reviewed blocked chords a point lies on (within 3 yards), with its
-- projection on each, in `blocked` order: Decide's test for a place
-- without a node ID. Kept for the last point asked about, since the answer
-- depends only on where the point is and the player's place is tested
-- against several stops every frame. A chord's box (its ends, 3 yards and a
-- little more around) rules it out without the projection: a point outside
-- it is further than 3 yards from every point of the chord. The boxes are
-- also listed by the squares they touch (chordGrid[cont][ix][iy], chords in
-- `blocked` order; big squares, as these chords run for miles), so only
-- the chords around the point are looked at.
local CHORD_SQUARE = 1024
local chordList, chordT, chordCount = {}, {}, 0
local chordFor, chordC, chordX, chordY
local boxFor, boxMinX, boxMaxX, boxMinY, boxMaxY, chordGrid
local function Boxes()
    boxFor, boxMinX, boxMaxX, boxMinY, boxMaxY, chordGrid = blocked, {}, {}, {}, {}, {}
    for i = 1, #blocked do
        local pa, pb = blocked[i].a, blocked[i].b
        local x0, x1 = min(pa.wx, pb.wx) - 3.01, max(pa.wx, pb.wx) + 3.01
        local y0, y1 = min(pa.wy, pb.wy) - 3.01, max(pa.wy, pb.wy) + 3.01
        boxMinX[i], boxMaxX[i], boxMinY[i], boxMaxY[i] = x0, x1, y0, y1
        local byX = chordGrid[pa.cont]
        if byX == nil then byX = {}; chordGrid[pa.cont] = byX end
        local ix0, ix1 = floor(x0/CHORD_SQUARE), floor(x1/CHORD_SQUARE)
        local iy0, iy1 = floor(y0/CHORD_SQUARE), floor(y1/CHORD_SQUARE)
        if byX and (ix1-ix0+1)*(iy1-iy0+1) <= 1024 then
            for ix = ix0, ix1 do
                local byY = byX[ix] or {}
                byX[ix] = byY
                for iy = iy0, iy1 do
                    local list = byY[iy] or {}
                    byY[iy] = list
                    list[#list+1] = i
                end
            end
        else
            -- a chord too long to list by square (or not a finite one): this
            -- continent's chords are all looked at, as before
            chordGrid[pa.cont] = false
        end
    end
end
local function ChordsAt(c, x, y)
    if chordFor == blocked and chordC == c and chordX == x and chordY == y then return chordCount end
    if boxFor ~= blocked then Boxes() end
    chordFor = nil -- until the list is whole
    local count = 0
    local byX = chordGrid[c]
    if not y or byX == false then
        -- every chord of the continent (a missing y goes to Projection, as
        -- it always did)
        for i = 1, #blocked do
            local proof = blocked[i]
            if c == proof.a.cont and (not y or not (x < boxMinX[i] or x > boxMaxX[i] or y < boxMinY[i] or y > boxMaxY[i])) then
                local t, d = Projection(proof.a, proof.b, x, y)
                if d <= 3 then
                    count = count + 1
                    chordList[count], chordT[count] = proof, t
                end
            end
        end
    else
        local byY = byX and byX[floor(x/CHORD_SQUARE)]
        local near = byY and byY[floor(y/CHORD_SQUARE)]
        if near then
            for k = 1, #near do
                local i = near[k]
                if not (x < boxMinX[i] or x > boxMaxX[i] or y < boxMinY[i] or y > boxMaxY[i]) then
                    local proof = blocked[i]
                    local t, d = Projection(proof.a, proof.b, x, y)
                    if d <= 3 then
                        count = count + 1
                        chordList[count], chordT[count] = proof, t
                    end
                end
            end
        end
    end
    for i = count + 1, chordCount do chordList[i], chordT[i] = nil, nil end
    chordFor, chordC, chordX, chordY, chordCount = blocked, c, x, y, count
    return count
end

function Terrain.Decide(a,b,explicit)
    local pa,pb = Resolve(a),Resolve(b)
    if pa and pa.node.terrainOnly then a.terrainOnly = true end
    if pb and pb.node.terrainOnly then b.terrainOnly = true end
    local e = pa and pb and evidence[pa.id .. ">" .. pb.id]
    if e then
        local r = Terrain.Record(e)
        if e.state == "UNAVAILABLE" then return false, 0, e end
        if e.state == "TERRAIN_BLOCKED" then
            if explicit == "polyline" and Bent(e,r) then return true,0,e,r end
            return false, 0, e
        end
        if r and r.state == "confirmed" then
            if not explicit and Bent(e,r) then return false,0,e end
            return true,0,e,r
        end
        if r and r.state == "refuted" then return true, 2, e end
        return true, e.state == "UNCERTAIN" and 1 or .25, e
    end
    -- A player/goal in the interior of a reviewed chord cannot bypass its
    -- verdict by losing the original node IDs. Crossing the chord is allowed;
    -- following a substantial portion of it is not.
    if not a.id or not b.id then
        local c,ax,ay = ns.Travel.Pos(a); local bc,bx,by = ns.Travel.Pos(b)
        if c and c == bc and ax and bx then
            -- b's projection only matters when a lies on the chord
            for i = 1, ChordsAt(c, ax, ay) do
                local proof, ta = chordList[i], chordT[i]
                local tb,db = Projection(proof.a,proof.b,bx,by)
                if db <= 3 and abs(min(1,max(0,ta))-min(1,max(0,tb)))*Distance(proof.a,proof.b) > 30 then
                    return false,0,proof
                end
            end
        end
    end
    if a.terrainOnly or b.terrainOnly then
        -- New points authorize only their indexed adjacent segments. A tiny
        -- endpoint connector lets a player standing at a node start the chain.
        local c,ax,ay = ns.Travel.Pos(a); local bc,bx,by = ns.Travel.Pos(b)
        return c and c == bc and ax and bx and (ax-bx)^2+(ay-by)^2 <= 9 or false, 0
    end
    return true, 0
end

local function Append(trace,x,y,z)
    local pts = trace.points
    if #pts >= 2 then
        local a,b = pts[#pts-1],pts[#pts]
        local t,dd = Projection({wx=a[1],wy=a[2]}, {wx=x,wy=y}, b[1],b[2])
        if t >= 0 and t <= 1 and dd <= .25 and (trace.error or 0)+dd <= .5 and (not z or not b[3] or not a[3]
            or abs(b[3]-(a[3]+t*(z-a[3]))) <= .25) then
            trace.error=(trace.error or 0)+dd;pts[#pts] = {x,y,z}; return true
        end
    end
    if #pts >= POINTS then return false end
    trace.error=0;pts[#pts+1] = {x,y,z}; return true
end

-- Sampling runs five times a second for as long as you play, so it makes
-- nothing it can keep: the traces' table is replaced only when it holds
-- some, the last sample is one record written over (only Sample reads it),
-- and the floor position is a new table only when it has changed (a search
-- may hold the one it began with: searchFloor).
local lastSample = {}
local function Forget()
    last = nil
    if next(active) ~= nil then active = {} end
end
function Terrain.Sample()
    if not loaded and ns.Get("realRoutes") and ns.Travel then ns.Travel.Data() end
    if not loaded or not ns.Get("realRoutes") or not ns.Get("travelTrails") then return Forget() end
    if Flag(UnitIsDeadOrGhost) or Flag(UnitIsGhost) or Flag(UnitOnTaxi) or Flag(IsFlying)
        or Flag(IsSwimming) or Flag(IsFalling) or Flag(UnitInVehicle)
        or Flag(UnitAffectingCombat) or ns.Travel.Riding() then return Forget() end
    local speed = GetUnitSpeed and Number(ns.Num(GetUnitSpeed("player")))
    local m,x,y = ns.Geo.GetPlayerMapPosition()
    m,x,y = Number(m),Number(x),Number(y)
    if not speed or not m or not x or not y then return Forget() end
    local cont,wx,wy = ns.Geo.MapToWorldLive(m,x,y)
    cont,wx,wy = Number(cont),Number(wx),Number(wy)
    local z,positionInstance
    if UnitPosition then
        local px,py,pz,instance = UnitPosition("player")
        px,py,z,positionInstance = Number(ns.Num(px)),Number(ns.Num(py)),Number(ns.Num(pz)),Number(ns.Num(instance))
        if not px or not py or not z or not positionInstance then return Forget() end
    end
    if not z then floorPosition = nil
    else
        local f = floorPosition
        if not (f and f.wx == wx and f.wy == wy and f.z == z and f.cont == cont) then
            floorPosition = {wx=wx,wy=wy,z=z,cont=cont}
        end
    end
    local now,scope = Number(GetTime()),Scope()
    if not cont or not wx or not wy or not now or not scope then return Forget() end
    local continuous = last and last.cont == cont and last.m == m and last.scope == scope
        and last.instance == positionInstance and now-last.t > 0 and now-last.t <= .8
    if continuous then
        local dd = sqrt((wx-last.wx)^2+(wy-last.wy)^2)
        continuous = dd <= 12 and dd <= max(speed,last.speed)* (now-last.t)*1.35+.5
            and (not z or not last.z or abs(z-last.z) <= 6)
        if speed <= .1 and dd > .5 then continuous = false end -- moving deck
    end
    if not continuous and next(active) ~= nil then active={} end
    last = lastSample
    last.m,last.cont,last.wx,last.wy,last.z,last.t = m,cont,wx,wy,z,now
    last.scope,last.instance,last.speed = scope,positionInstance,speed
    if speed <= .1 then -- pauses are not refutation
        if next(active) ~= nil then active={} end
        return
    end
    for key,trace in pairs(active) do
        local _,deviation = Projection(trace.from,trace.to,wx,wy)
        if deviation > 40 or now-trace.started > 1200 or not Append(trace,wx,wy,z) then active[key]=nil
        else
            trace.samples = trace.samples+1
            local progress = Distance(trace.from,last)
            if progress > (trace.previous or 0)+1 then
                if trace.retreat then trace.peak = progress end
                trace.peak,trace.retreat = max(trace.peak,progress),false
            elseif progress < trace.peak-8 and not trace.retreat then
                trace.turns,trace.retreat = trace.turns+1,true
            end
            trace.previous = progress
            if trace.turns >= 3 and trace.peak >= 12 then Save(trace.e,"refuted");active[key]=nil
            elseif Distance(trace.to,last) <= 3 and trace.samples >= 3 and trace.peak >= Distance(trace.from,trace.to)-6 then
                Save(trace.e,"confirmed",trace.points);active[key]=nil
            end
        end
    end
    local count=0;for _ in pairs(active) do count=count+1 end
    -- Nearby's nine buckets in Nearby's order, by number (as Resolve reads
    -- them): no key strings and no function made per sample
    local byX = grid[cont]
    if not byX then return end
    local ix, iy = floor(wx/64), floor(wy/64)
    for gx = ix-1, ix+1 do
        local byY = byX[gx]
        if byY then
            for gy = iy-1, iy+1 do
                for _,p in ipairs(byY[gy] or NONE) do
                    if sqrt((p.wx-wx)^2+(p.wy-wy)^2) <= 3 then
                        for _,e in ipairs(p.edges) do
                            if count < 8 and not active[e.key] then
                                local to = e.a == p and e.b or e.a
                                if Distance(p,to) > 8 then
                                    active[e.key] = {e=e,from=p,to=to,started=now,points={{wx,wy,z}},peak=0,turns=0,samples=1}
                                    count=count+1
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- One inexpensive accumulator per frame; sampling/allocations run at 5 Hz.
-- On a client build where records are never applied (RecordsApply) there is
-- nothing to sample for. What sampling did besides still happens: with Real
-- routes on, the travel network is read at the first tick (not at your
-- first step or waypoint). Then the ticker stops, until a setting changes.
local ticker = CreateFrame("Frame")
Terrain._ticker = ticker -- tests
local function Unused()
    if not loaded and ns.Get("realRoutes") and ns.Travel then ns.Travel.Data() end
    Forget()
    ticker:Hide()
end
ticker:SetScript("OnUpdate", function(_,dt)
    dt=Number(dt);if not dt then return end
    elapsed=elapsed+dt
    if elapsed < SAMPLE then return end
    elapsed=0
    if RecordsApply() then ns.Call(Terrain.Sample) else ns.Call(Unused) end
end)
-- (Real routes turned on later reads the network at the next tick, as before)
ns.On("SETTING_CHANGED", function(key)
    if key == nil or key == "realRoutes" then ticker:Show() end
end)
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_DEAD","PLAYER_ALIVE","PLAYER_UNGHOST","ZONE_CHANGED_NEW_AREA"}) do
    ns.RegisterEvent(event,function() last=nil;active={};floorPosition=nil end)
end
