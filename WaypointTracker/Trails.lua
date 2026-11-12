-- Trails: Real routes learns from where players actually go.
--   * Paths: while Real routes is on, the ground you walk or ride over is
--     written down as a coarse grid of 20-yard squares and the steps between
--     them. Walking inside a zone, the arrow follows a path players have
--     walked when there is one, instead of the straight line (which can run
--     into a cliff).
--   * Crossings: where you walk from one zone into another becomes a way
--     between the two, even where the shipped data has none.
--   * Boats and zeppelins: when you sail, the time it left is written down,
--     so routes can say when the next one leaves.
-- It is shared with other players of the addon through the Routes channel
-- (Settings: "Share paths"), and what they share is used too. Paths are
-- shared well after you walked them, in no particular order, so they don't
-- say where you are now. What others send is untrusted: it is checked, a
-- path or crossing counts only once two players have sent it, and how much
-- one player can add is capped.
local _, ns = ...
local Geo = ns.Geo

local Trails = {}
ns.Trails = Trails

local floor, sqrt, abs, max, min = math.floor, math.sqrt, math.abs, math.max, math.min

local CELL = 20 -- yards a side
local OFFSET = 2048 -- cell numbers are kept positive in the key
local SAMPLE_EVERY = 0.5
local MAX_CELLS = 80000 -- per continent, for each of own, shared and unconfirmed
local MAX_CELLS_A_DAY = 3000 -- squares taken from one player a day
local MAX_CROSSINGS = 1500 -- crossings kept in all
local MAX_OWN_CROSSINGS = 300
local MAX_CROSSINGS_A_DAY = 30 -- crossings taken from one player a day
local SHARE_EVERY = 20 -- seconds between path messages
local SHARE_AFTER = 600 -- seconds before a path you walked is shared
local CELLS_PER_MESSAGE = 30
local LOOKAHEAD = 45 -- yards along a path the arrow points to
local MAX_DETOUR = 2.2 -- a path this much longer than the straight line isn't the way
local SEARCH_LIMIT = 3000
local SEARCH_AGAIN = 3 -- seconds before looking for a path to the same place again
local NO_PATH_AGAIN = 10 -- and after finding none
-- A search spread over frames (Trails.Steer, when the client has a frame
-- clock) does at most this much in one frame:
local SLICE_MS = 1 -- milliseconds by the frame clock,
-- (100 squares: 0.4 ms typical, 1.3 ms worst measured with Lua 5.1 on a busy machine)
local SLICE_SQUARES = 100 -- and squares looked around from, clock or not,
local SLICE_POPS = 400 -- and entries taken off the search's list (about 2 a square)
local CLOCK_EVERY = 16 -- (the clock is read every this many taken off)
local SLICE_IDLE = 1 -- seconds a search not carried on is kept
local KEEP_IDLE = 10 -- seconds the path found is kept unused
local DOCK_WAIT = 60 -- seconds a boat or zeppelin stays at each end
local TIMETABLE_HOURS = 8 -- how long a seen departure is trusted

-- the eight neighbours of a square, and the bit for each
local DIRS = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local BIT, BITS = {}, {}
for i, d in ipairs(DIRS) do
    BIT[d[1] .. "," .. d[2]] = 2 ^ (i - 1)
    BITS[i] = 2 ^ (i - 1)
end

local function HasBit(bits, b)
    return bits % (b + b) >= b
end

local function Or(a, b)
    local out = 0
    for i = 1, 8 do
        local bit = BITS[i]
        if HasBit(a, bit) or HasBit(b, bit) then
            out = out + bit
        end
    end
    return out
end

local function Key(cx, cy)
    return (cx + OFFSET) * 4096 + (cy + OFFSET)
end

local function Unkey(k)
    return floor(k / 4096) - OFFSET, k % 4096 - OFFSET
end

local function Store()
    local db = WaypointTrackerDB
    if type(db) ~= "table" then
        return nil
    end
    if type(db.trails) ~= "table" then
        db.trails = {}
    end
    local t = db.trails
    for _, k in ipairs({ "own", "shared", "pending", "crossings", "boats", "senders" }) do
        if type(t[k]) ~= "table" then
            t[k] = {}
        end
    end
    t.version = 2
    return t
end
Trails.Store = Store

local function Grid(which, cont, make)
    local st = Store()
    local all = st and st[which]
    if not all then
        return nil
    end
    local g = all[cont]
    if not g and make then
        g = {}
        all[cont] = g
    end
    return g
end

local counts = {} -- which .. cont -> squares
local function Count(which, cont, g)
    local k = which .. cont
    if not counts[k] then
        local n = 0
        for _ in pairs(g) do
            n = n + 1
        end
        counts[k] = n
    end
    return counts[k]
end

local function Room(which, cont, g)
    return Count(which, cont, g) < MAX_CELLS
end

local function Added(which, cont)
    counts[which .. cont] = (counts[which .. cont] or 0) + 1
end

-- Counts the changes to the walked squares that can turn a failed path
-- search (Trails.Steer) into a found one: a step between two squares
-- already walked, a square taken from other players, or a new square near
-- the square Steer is looking for a way to (its nearest walked square may
-- change). A new square at the end of a path you walk is only a dead end.
local joins = 0
local watchCont, watchX, watchY -- the square Steer last looked for a way to

local function Walked(st, cont, k)
    local own, shared = st.own[cont], st.shared[cont]
    return ((own and own[k]) or 0) > 0 or ((shared and shared[k]) or 0) > 0
end

local function NearWatched(cont, x, y)
    return cont == watchCont and abs(x - watchX) <= 2 and abs(y - watchY) <= 2
end

-- a step from one square to the next, in both
local function Link(g, which, cont, ax, ay, bx, by)
    local b1 = BIT[(bx - ax) .. "," .. (by - ay)]
    local b2 = BIT[(ax - bx) .. "," .. (ay - by)]
    if not (b1 and b2) then
        return false
    end
    local st = Store()
    local joined = st and Walked(st, cont, Key(ax, ay)) and Walked(st, cont, Key(bx, by))
    local added = false
    for _, s in ipairs({ { Key(ax, ay), b1 }, { Key(bx, by), b2 } }) do
        local old = g[s[1]]
        if not old then
            if not Room(which, cont, g) then
                break
            end
            Added(which, cont)
            old = 0
        end
        if not HasBit(old, s[2]) then
            g[s[1]] = old + s[2]
            added = true
        end
    end
    if added and (joined or NearWatched(cont, ax, ay) or NearWatched(cont, bx, by)) then
        joins = joins + 1
    end
    return added
end

local function Enabled()
    return ns.Get("realRoutes") and ns.Get("travelTrails")
end

local function Network()
    local T = ns.Travel
    return T and T.Data()
end

-- the continents the travel network knows (and so paths can be on)
local continents
local function KnownContinent(cont)
    if not continents then
        local d = Network()
        if not d then
            return false
        end
        continents = {}
        for _, n in pairs(d.nodes) do
            if n.cont0 then
                continents[n.cont0] = true
            end
        end
    end
    return continents[cont] == true
end

-- the player's world position, worked out from the map like the network's
local function Here()
    local m, x, y = Geo.GetPlayerMapPosition()
    if not m then
        return nil
    end
    local cont, wx, wy = Geo.MapToWorldLive(m, x, y)
    if not cont then
        return nil
    end
    return cont, wx, wy, m, x, y
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------
local last -- { cont, cx, cy, wx, wy, area, m, x, y, t }
local fresh = {} -- own steps not shared yet: { cont, ax, ay, bx, by, t }

local function OnBoard()
    if UnitOnTaxi and UnitOnTaxi("player") then
        return true
    end
    local T = ns.Travel
    return T and T.Riding and T.Riding() ~= nil
end

-- only ground you cover yourself: not a boat, a flight or the water
local function Walking()
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        return false
    end
    if IsSwimming and IsSwimming() then
        return false
    end
    if not GetUnitSpeed or (ns.Num(GetUnitSpeed("player")) or 0) <= 0 then
        return false
    end
    return not OnBoard()
end

-- the squares on the line between two (both ends included)
local function Line(ax, ay, bx, by)
    local out = {}
    local n = max(abs(bx - ax), abs(by - ay))
    for i = 0, n do
        local t = n == 0 and 0 or i / n
        local x, y = floor(ax + (bx - ax) * t + 0.5), floor(ay + (by - ay) * t + 0.5)
        local p = out[#out]
        if not p or p[1] ~= x or p[2] ~= y then
            out[#out + 1] = { x, y }
        end
    end
    return out
end

local function NoteCrossing(a, b)
    local d = Network()
    if not d or not a.area or not b.area or a.area == b.area or a.city ~= b.city then
        return
    end
    local nameA, nameB = d.areas[a.area], d.areas[b.area]
    if not (nameA and nameB) then
        return
    end
    -- the last spot on the side you came from
    Trails.AddCrossing(nameA, nameB, a.m, a.x, a.y, true)
end

local function Record()
    if not Enabled() then
        last = nil
        return
    end
    local cont, wx, wy, m, x, y = Here()
    if not cont or not Walking() then
        last = nil
        return
    end
    local cx, cy = floor(wx / CELL), floor(wy / CELL)
    local T = ns.Travel
    local area, city
    if Network() then
        area, city = T.AreaAt(m, x, y, nil, true) -- live: the player's position
    end
    local now = GetTime()
    local here = { cont = cont, cx = cx, cy = cy, wx = wx, wy = wy, m = m, x = x, y = y, area = area, city = city, t = now }
    if last and last.cont == cont then
        local dx, dy = wx - last.wx, wy - last.wy
        local moved = sqrt(dx * dx + dy * dy)
        local speed = moved / max(0.1, now - last.t)
        -- a jump (a teleport, a loading screen) or faster than any mount: not a path
        if moved < 80 and speed < 30 and (cx ~= last.cx or cy ~= last.cy) then
            local g = Grid("own", cont, true)
            local cells = Line(last.cx, last.cy, cx, cy)
            -- steps are kept for sharing only while sharing is on
            local share = ns.Get("travelShare")
            for i = 2, #cells do
                local a, b = cells[i - 1], cells[i]
                if Link(g, "own", cont, a[1], a[2], b[1], b[2]) and share then
                    fresh[#fresh + 1] = { cont, a[1], a[2], b[1], b[2], now }
                end
            end
            if area and last.area and area ~= last.area and moved < 40 then
                NoteCrossing(last, here)
            end
        end
    end
    last = here
end

-- ---------------------------------------------------------------------------
-- Zone crossings players walked
-- ---------------------------------------------------------------------------
local function CrossingKey(nameA, nameB, m, x, y)
    return ("%s|%s|%d|%d|%d"):format(nameA, nameB, m, floor(x * 50), floor(y * 50)) -- 2% squares
end

local function AreaIndex(d, name)
    if not d.areaIndex then
        d.areaIndex = {}
        for i, n in ipairs(d.areas) do
            d.areaIndex[n] = i
        end
    end
    return d.areaIndex[name]
end

-- is there a crossing between these two areas this close already?
local function Known(d, a, b, m, x, y)
    local spot = { m = m, x = x, y = y }
    for _, n in ipairs(d.byArea[a] or {}) do
        if n.kind == "border" then
            for _, l in ipairs(d.out[n.id] or {}) do
                if l.to.area == b then
                    local dist = ns.Travel.Dist(spot, n)
                    if dist and dist < 150 then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function UseCrossing(c)
    local T = ns.Travel
    local d = Network()
    if not d or c.used then
        return
    end
    local a, b = AreaIndex(d, c.a), AreaIndex(d, c.b)
    if not (a and b) or Known(d, a, b, c.m, c.x, c.y) then
        return
    end
    c.used = true
    T.AddCrossing("X" .. (tostring(c.key):gsub("[^%w]", "")), a, b, c.m, c.x, c.y)
    T.Invalidate()
end

local function CountKeys(t)
    local n = 0
    for _ in pairs(t or {}) do
        n = n + 1
    end
    return n
end

-- mine: you walked it. Others': two players have to have sent it.
function Trails.AddCrossing(nameA, nameB, m, x, y, mine, sender)
    local st = Store()
    local d = Network()
    if not (st and d) then
        return
    end
    -- one record for both directions
    if nameA > nameB then
        nameA, nameB = nameB, nameA
    end
    local a, b = AreaIndex(d, nameA), AreaIndex(d, nameB)
    if not (a and b) or a == b then
        return
    end
    local key = CrossingKey(nameA, nameB, m, x, y)
    local c = st.crossings[key]
    if not c then
        if CountKeys(st.crossings) >= MAX_CROSSINGS then
            return
        end
        if mine then
            -- only ones the shipped data doesn't have, and not too many
            local own = 0
            for _, other in pairs(st.crossings) do
                if other.mine then
                    own = own + 1
                end
            end
            if own >= MAX_OWN_CROSSINGS or Known(d, a, b, m, x, y) then
                return
            end
        end
        c = { a = nameA, b = nameB, m = m, x = floor(x * 1000) / 1000, y = floor(y * 1000) / 1000, by = {} }
        st.crossings[key] = c
    end
    c.key = key
    if mine then
        c.mine = true
    elseif sender and not c.by[sender] and CountKeys(c.by) < 4 then
        c.by[sender] = true
    end
    if c.mine or CountKeys(c.by) >= 2 then
        UseCrossing(c)
    end
end

-- ---------------------------------------------------------------------------
-- Following a path inside an area
-- ---------------------------------------------------------------------------
-- A* over the walked squares, own and confirmed shared, as a search that can
-- stop and go on later: NewSearch sets it up, Expand carries it on (all of
-- it, or a slice). Stopped or not, it takes the same steps in the same
-- order, so it ends with the same answer: search.path, the list of squares,
-- or nil once search.done.
local function Heuristic(k, gx, gy)
    local x, y = Unkey(k)
    local dx, dy = x - gx, y - gy
    return sqrt(dx * dx + dy * dy)
end

-- a binary heap of { f, key }
local function Push(heap, f, k)
    local i = #heap + 1
    heap[i] = { f, k }
    while i > 1 do
        local p = floor(i / 2)
        if heap[p][1] <= heap[i][1] then
            break
        end
        heap[p], heap[i] = heap[i], heap[p]
        i = p
    end
end

local function Pop(heap)
    local top = heap[1]
    local lastItem = table.remove(heap)
    local n = #heap
    if n > 0 then
        heap[1] = lastItem
        local i = 1
        while true do
            local l, r, s = i * 2, i * 2 + 1, i
            if l <= n and heap[l][1] < heap[s][1] then
                s = l
            end
            if r <= n and heap[r][1] < heap[s][1] then
                s = r
            end
            if s == i then
                break
            end
            heap[s], heap[i] = heap[i], heap[s]
            i = s
        end
    end
    return top
end

-- the squares from the start to `k`, start first
local function Trace(prev, k)
    local out = {}
    while k do
        out[#out + 1] = k
        k = prev[k]
    end
    local i, j = 1, #out
    while i < j do
        out[i], out[j] = out[j], out[i]
        i, j = i + 1, j - 1
    end
    return out
end

-- The frame clock in milliseconds, or nil (no clock, or an unreadable answer).
local function Clock()
    local clock = debugprofilestop
    if type(clock) ~= "function" then
        return nil
    end
    return ns.Num(clock())
end

-- Has the slice begun at `started` (frame clock) used its time? A clock
-- that went back (debugprofilestart from anyone) or stopped answering: yes.
local function Spent(started)
    if not started then
        return false
    end
    local now = Clock()
    return not now or now < started or now - started >= SLICE_MS
end

local function NewSearch(cont, sx, sy, gx, gy)
    local start = Key(sx, sy)
    return { own = Grid("own", cont) or {}, shared = Grid("shared", cont) or {}, gx = gx, gy = gy, goal = Key(gx, gy),
        heap = { { Heuristic(start, gx, gy), start } }, g = { [start] = 0 }, prev = {}, closed = {}, n = 0,
        done = false, path = nil }
end

-- Carries the search on: to the end, or (with `squares`) until it has looked
-- around from that many squares, taken `pops` off its list, or (begun at
-- frame-clock time `started`) used SLICE_MS.
local function Expand(s, squares, pops, started)
    local heap, g, prev, closed, own, shared = s.heap, s.g, s.prev, s.closed, s.own, s.shared
    local goal, gx, gy = s.goal, s.gx, s.gy
    local expanded, popped = 0, 0
    while heap[1] do
        if squares and (expanded >= squares or popped >= pops
            or (popped % CLOCK_EVERY == 0 and popped > 0 and Spent(started))) then
            return
        end
        local k = Pop(heap)[2]
        popped = popped + 1
        if k == goal then
            s.done, s.path = true, Trace(prev, k)
            return
        end
        if not closed[k] then
            closed[k] = true
            s.n = s.n + 1
            if s.n > SEARCH_LIMIT then
                s.done = true
                return
            end
            expanded = expanded + 1
            local a, b = own[k] or 0, shared[k] or 0
            local bits
            if a == 0 then
                bits = b
            elseif b == 0 then
                bits = a
            else
                bits = Or(a, b)
            end
            local x, y = Unkey(k)
            for i = 1, 8 do
                if HasBit(bits, BITS[i]) then
                    local d = DIRS[i]
                    local nk = Key(x + d[1], y + d[2])
                    if not closed[nk] then
                        local cost = g[k] + ((d[1] ~= 0 and d[2] ~= 0) and 1.414 or 1)
                        if not g[nk] or cost < g[nk] then
                            g[nk], prev[nk] = cost, k
                            Push(heap, cost + Heuristic(nk, gx, gy), nk)
                        end
                    end
                end
            end
        end
    end
    s.done = true
end

-- All at once: the list of squares or nil.
local function FindPath(cont, sx, sy, gx, gy)
    local s = NewSearch(cont, sx, sy, gx, gy)
    Expand(s)
    return s.path
end

-- the nearest walked square within two of this one
local function Snap(cont, cx, cy)
    local own, shared = Grid("own", cont) or {}, Grid("shared", cont) or {}
    local best, bd
    for dx = -2, 2 do
        for dy = -2, 2 do
            local k = Key(cx + dx, cy + dy)
            if (own[k] or 0) > 0 or (shared[k] or 0) > 0 then
                local d = dx * dx + dy * dy
                if not bd or d < bd then
                    best, bd = { cx + dx, cy + dy }, d
                end
            end
        end
    end
    if best then
        return best[1], best[2]
    end
end

local cache -- { key = target square, path, at, pcx, pcy, points, progress, searched, joins }

local function NewCache(key, cont, path, at, pcx, pcy, searched, joinsAt)
    local c = { key = key, path = path, at = at, pcx = pcx, pcy = pcy, points = {}, searched = searched, joins = joinsAt }
    for _, k in ipairs(path or {}) do
        local x, y = Unkey(k)
        c.points[#c.points + 1] = { cont = cont, wx = (x + .5) * CELL, wy = (y + .5) * CELL }
    end
    return c
end

-- A search can take tens of milliseconds, and Steer is asked every frame.
-- When the client has a frame clock (debugprofilestop) a search is a job,
-- carried on a slice a frame (SLICE_MS, SLICE_SQUARES, SLICE_POPS) until it
-- answers; meanwhile Steer answers from the path it had, as it would without
-- a search. The answer is the search's as of its start (`at`, the player's
-- square `pcx`/`pcy`, `joins`), so the usual re-search rules follow it up.
-- Without a clock a search is done all at once, as before.
-- job: { key, cont, search, at, pcx, pcy, straight, joins, pumped, trails, own, shared }
local job
local used -- when Steer last used the cache or the job (sliced)
local forceSliced -- tests: true/false, or nil to decide from the client

local function Sliced()
    if forceSliced ~= nil then
        return forceSliced
    end
    return type(debugprofilestop) == "function"
end

-- the walked squares the job's search reads are still the stored ones (a
-- reset or a first square on its continent replaces them)
local function Current(j)
    local db = WaypointTrackerDB
    local st = type(db) == "table" and db.trails
    if type(st) ~= "table" or st ~= j.trails or type(st.own) ~= "table" or type(st.shared) ~= "table" then
        return false
    end
    return st.own[j.cont] == j.own and st.shared[j.cont] == j.shared
end

local pumping, sliceStarted -- the job Slice carries on, and the frame clock then
local function Slice()
    Expand(pumping.search, SLICE_SQUARES, SLICE_POPS, sliceStarted)
end

local function WithStack(err)
    local stack = type(debugstack) == "function" and debugstack(2)
    return type(stack) == "string" and (tostring(err) .. "\n" .. stack) or err
end

-- One slice of the job. Returns true when its search is done, or false and
-- the error it stopped with (reported once; the job is let go).
local function Pump(j, now)
    j.pumped = now
    pumping, sliceStarted = j, Clock()
    local ok, err = xpcall(Slice, WithStack)
    pumping, sliceStarted = nil, nil
    if not ok then
        job = nil
        ns.ReportError(err)
        return false, true
    end
    return j.search.done
end

-- The way to face to follow a walked path to `target` (a node), or nil
function Trails.Steer(here, target)
    local T = ns.Travel
    if not (T and here and target) then
        return nil
    end
    local tc, tx, ty = T.Pos(target)
    if tc ~= here.cont or not tx then
        return nil
    end
    local straight = sqrt((tx - here.wx) ^ 2 + (ty - here.wy) ^ 2)
    if straight < LOOKAHEAD * 1.5 then
        return nil
    end
    local cont = here.cont
    local pcx, pcy = floor(here.wx / CELL), floor(here.wy / CELL)
    local tcx, tcy = floor(tx / CELL), floor(ty / CELL)
    local key = cont .. ":" .. tcx .. ":" .. tcy
    local now = GetTime()
    local same = cache and cache.key == key
    local path = same and cache.path
    local projection = path and T.ProjectPolyline(cache.points, here, nil, nil, cache.progress)
    local moved = same and (pcx ~= cache.pcx or pcy ~= cache.pcy)
    local wait = same and (cache.path and SEARCH_AGAIN or NO_PATH_AGAIN) or 0
    -- After a search that found no way, a new square alone doesn't search
    -- again (it would find none again): only the time, or the walked squares
    -- joining up (see `joins`).
    local again = moved
    if same and cache.searched and not cache.path then
        again = joins ~= cache.joins
    end
    local due = not same or ((not projection or projection.distance > CELL * 2)
        and (now - cache.at >= wait or (again and now - cache.at >= SAMPLE_EVERY)))
    if Sliced() then
        used = now
        -- Another stop, a search not carried on lately, or the squares
        -- replaced: let it go (one is started below when due). A new square
        -- of yours or newly walked squares don't: the search goes on and
        -- the re-search rules follow it up.
        if job and (job.key ~= key or now - job.pumped > SLICE_IDLE or not Current(job)) then
            job = nil
        end
        if not job and due then
            local sx, sy = Snap(cont, pcx, pcy)
            local gx, gy = Snap(cont, tcx, tcy)
            watchCont, watchX, watchY = cont, tcx, tcy
            local st = sx and gx and Store()
            if st then
                job = { key = key, cont = cont, search = NewSearch(cont, sx, sy, gx, gy), at = now, pcx = pcx,
                    pcy = pcy, straight = straight, joins = joins, pumped = now, trails = st,
                    own = st.own[cont], shared = st.shared[cont] }
            else
                cache = NewCache(key, cont, nil, now, pcx, pcy, nil, joins)
                projection = nil
            end
        end
        if job then
            local j = job
            local done, failed = Pump(j, now)
            if done then
                job = nil
                path = j.search.path
                if path and #path * CELL > j.straight * MAX_DETOUR + CELL * 4 then
                    path = nil -- a long way round: the straight line may well be fine
                end
                cache = NewCache(key, cont, path, j.at, j.pcx, j.pcy, true, j.joins)
                projection = path and T.ProjectPolyline(cache.points, here)
            elseif failed then
                -- as a search that found no way: tried again at that pace
                cache = NewCache(key, cont, nil, now, pcx, pcy, true, joins)
                projection = nil
            end
        end
    elseif due then
        path = nil
        local sx, sy = Snap(cont, pcx, pcy)
        local gx, gy = Snap(cont, tcx, tcy)
        if sx and gx then
            path = FindPath(cont, sx, sy, gx, gy)
            if path and #path * CELL > straight * MAX_DETOUR + CELL * 4 then
                path = nil -- a long way round: the straight line may well be fine
            end
        end
        watchCont, watchX, watchY = cont, tcx, tcy
        cache = NewCache(key, cont, path, now, pcx, pcy, (sx and gx) and true or nil, joins)
        projection = path and T.ProjectPolyline(cache.points, here)
    end
    if not projection or projection.distance > CELL * 2 then
        return nil
    end
    cache.progress = projection.progress
    local aim = T.LookAhead(cache.points, projection, LOOKAHEAD)
    if not T.CanWalk(here, aim) then return nil end
    local dNorth, dWest = aim.wx - here.wx, aim.wy - here.wy
    return math.atan2(dWest, dNorth)
end

-- ---------------------------------------------------------------------------
-- Boat and zeppelin timetables
-- ---------------------------------------------------------------------------
local function ServerTime()
    return (GetServerTime and GetServerTime()) or floor(time and time() or 0)
end

-- a boat that goes back and forth (not one of the one-way loops)
local function Shuttle(key)
    local d = Network()
    if not d or type(key) ~= "string" then
        return nil
    end
    local from = key:match("^(.-)>")
    for _, l in ipairs(from and d.out[from] or {}) do
        if l.key == key then
            if l.oneway or not l.ride then
                return nil
            end
            return l
        end
    end
end

-- one round trip: the time aboard each way and the stop at each end
local function Cycle(l, seen)
    if seen and seen.cycle then
        return seen.cycle
    end
    return 2 * (l.ride + DOCK_WAIT)
end

local function NoteDeparture(key, when, mine)
    local st = Store()
    local l = Shuttle(key)
    if not (st and l) then
        return
    end
    local seen = st.boats[key]
    if seen and seen.t and when > seen.t + 60 then
        -- two departures: the round trip, measured
        local c = Cycle(l, seen)
        local n = floor((when - seen.t) / c + 0.5)
        if n >= 1 and n <= 20 then
            local measured = (when - seen.t) / n
            if abs(measured - c) < c * 0.15 then
                seen.cycle = floor(measured * 10 + 0.5) / 10
            end
        end
    end
    if not seen or when > (seen.t or 0) then
        st.boats[key] = { t = when, cycle = seen and seen.cycle, mine = mine or nil }
    end
    if mine then
        Trails.Share(("TB^%s^%d"):format(key, when))
    end
end

-- Seconds you'd wait for this boat if you got to its dock `at` seconds from
-- now, or nil when nobody has seen it leave lately.
function Trails.NextDeparture(key, at)
    local st = Store()
    local l = Shuttle(key)
    if not (st and l) then
        return nil
    end
    local now = ServerTime()
    local arrive = now + (at or 0)
    local back = key:match(">(.*)$") .. ">" .. key:match("^(.-)>")
    local best
    for _, k in ipairs({ key, back }) do
        local seen = st.boats[k]
        if seen and seen.t and now - seen.t < TIMETABLE_HOURS * 3600 then
            local c = Cycle(l, seen)
            -- a departure the other way means one from here half a trip later
            local t0 = seen.t + (k == key and 0 or (l.ride + DOCK_WAIT))
            local wait = (t0 - arrive) % c
            if not best or seen.t > best[2] then
                best = { wait, seen.t }
            end
        end
    end
    return best and best[1] or nil
end

-- ---------------------------------------------------------------------------
-- Sharing
-- ---------------------------------------------------------------------------
local B64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
local function Enc(n, width)
    local s = ""
    for _ = 1, width do
        local d = n % 64
        s = B64:sub(d + 1, d + 1) .. s
        n = floor(n / 64)
    end
    return s
end
local DEC = {}
for i = 1, 64 do
    DEC[B64:sub(i, i)] = i - 1
end
local function Dec(s)
    local n = 0
    for i = 1, #s do
        local d = DEC[s:sub(i, i)]
        if not d then
            return nil
        end
        n = n * 64 + d
    end
    return n
end
Trails.Enc, Trails.Dec = Enc, Dec

function Trails.Share(msg)
    local Net = ns.RoutesNet
    return Net and Net.Share and Net.Share(msg)
end

-- Paths walked a while ago, picked at random: a step is a square (4
-- characters) and a direction (1)
local function SharePaths()
    local now = GetTime()
    local ready = {}
    for i, s in ipairs(fresh) do
        if now - s[6] >= SHARE_AFTER then
            ready[#ready + 1] = i
        end
    end
    if #ready == 0 then
        return
    end
    local cont = fresh[ready[math.random(#ready)]][1]
    local parts, used = {}, {}
    while #parts < CELLS_PER_MESSAGE and #ready > 0 do
        local pick = table.remove(ready, math.random(#ready))
        local s = fresh[pick]
        if s[1] == cont then
            local dir = BIT[(s[4] - s[2]) .. "," .. (s[5] - s[3])]
            if dir then
                local di = floor(math.log(dir) / math.log(2) + 0.5)
                parts[#parts + 1] = Enc(Key(s[2], s[3]), 4) .. Enc(di, 1)
            end
            used[#used + 1] = pick
        end
    end
    if #parts > 0 and Trails.Share(("TP^%d^%s"):format(cont, table.concat(parts))) then
        table.sort(used, function(a, b)
            return a > b
        end)
        for _, i in ipairs(used) do
            table.remove(fresh, i)
        end
    end
    while #fresh > 2000 do
        table.remove(fresh, 1)
    end
end

-- how much one player has added today (kept between sessions)
local function Allowance(sender, kind, limit)
    local st = Store()
    if not st then
        return false
    end
    local day = floor(ServerTime() / 86400)
    local s = st.senders[sender]
    if not s or s.day ~= day then
        s = { day = day, cells = 0, crossings = 0 }
        st.senders[sender] = s
    end
    if (s[kind] or 0) >= limit then
        return false
    end
    s[kind] = (s[kind] or 0) + 1
    return true
end

-- A square another player walked counts once a second player has sent it
-- too (it waits in "pending" until then).
local function TakeShared(cont, sender, x, y, d)
    local shared = Grid("shared", cont, true)
    local pending = Grid("pending", cont, true)
    local b1 = BIT[d[1] .. "," .. d[2]]
    local k = Key(x, y)
    if shared[k] then
        if not HasBit(shared[k], b1) then
            Link(shared, "shared", cont, x, y, x + d[1], y + d[2])
        end
        return
    end
    local p = pending[k]
    if p and p.by ~= sender then
        pending[k] = nil
        counts["pending" .. cont] = (counts["pending" .. cont] or 1) - 1
        if Room("shared", cont, shared) then
            Added("shared", cont)
            shared[k] = p.bits
            joins = joins + 1
            Link(shared, "shared", cont, x, y, x + d[1], y + d[2])
        end
    elseif not p and Room("pending", cont, pending) then
        Added("pending", cont)
        pending[k] = { bits = b1, by = sender }
    elseif p then
        p.bits = Or(p.bits, b1)
    end
end

local function GotPaths(f, sender)
    local cont, body = tonumber(f[2]), f[3]
    if not (cont and body) or cont ~= floor(cont) or not KnownContinent(cont) then
        return
    end
    if #body % 5 ~= 0 or #body > 5 * CELLS_PER_MESSAGE * 2 then
        return
    end
    for i = 1, #body, 5 do
        local k, di = Dec(body:sub(i, i + 3)), Dec(body:sub(i + 4, i + 4))
        local d = di and DIRS[di + 1]
        if k and d then
            if not Allowance(sender, "cells", MAX_CELLS_A_DAY) then
                break
            end
            local x, y = Unkey(k)
            TakeShared(cont, sender, x, y, d)
        end
    end
end

local function GotCrossing(f, sender)
    local d = Network()
    local m, x, y = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
    local a, b = f[5], f[6]
    if not (d and m and x and y and a and b) or m ~= floor(m) or not d.mapArea[m] then
        return
    end
    if not (x >= 0 and x <= 1 and y >= 0 and y <= 1) then
        return
    end
    local ia, ib = AreaIndex(d, a), AreaIndex(d, b)
    -- it has to be on one side of that border
    local here = ns.Travel.AreaAt(m, x, y)
    if not (ia and ib and (here == ia or here == ib)) then
        return
    end
    if Allowance(sender, "crossings", MAX_CROSSINGS_A_DAY) then
        Trails.AddCrossing(a, b, m, x, y, false, sender)
    end
end

local function GotDeparture(f)
    local key, when = f[2], tonumber(f[3])
    local now = ServerTime()
    if key and when and when == floor(when) and when <= now + 60 and when > now - TIMETABLE_HOURS * 3600 then
        NoteDeparture(key, when, false)
    end
end

-- your crossings, once a session each, so players who came later get them
local sharedThisSession = {}
local function ShareCrossings()
    local st = Store()
    if not st then
        return
    end
    for key, c in pairs(st.crossings) do
        if c.mine and not sharedThisSession[key] then
            if Trails.Share(("TX^%d^%.3f^%.3f^%s^%s"):format(c.m, c.x, c.y, c.a, c.b)) then
                sharedThisSession[key] = true
            end
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
-- Sliced: a search Steer no longer carries on, and a path it no longer
-- follows (the waypoint cleared, another kind of step, another zone, the
-- setting off) are let go.
local function Tidy()
    local now, on = GetTime(), Enabled()
    if job and (not on or now - job.pumped > SLICE_IDLE) then
        job = nil
    end
    if used and (not on or now - used > KEEP_IDLE) then
        cache, used = nil, nil
    end
end

local ticker = CreateFrame("Frame")
local acc, shareAcc = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < SAMPLE_EVERY then
        return
    end
    shareAcc = shareAcc + acc
    acc = 0
    if job or used then
        ns.Call(Tidy)
    end
    ns.Call(Record)
    if shareAcc >= SHARE_EVERY then
        shareAcc = 0
        if not ns.Get("travelShare") then
            -- not sharing: steps kept from before are never sent
            for i = #fresh, 1, -1 do
                fresh[i] = nil
            end
        elseif Enabled() then
            ns.Call(SharePaths)
            ns.Call(ShareCrossings)
        end
    end
end)

ns.On("LOGIN", function()
    local Net = ns.RoutesNet
    if Net and Net.Listen then
        Net.Listen("TP", GotPaths)
        Net.Listen("TX", GotCrossing)
        Net.Listen("TB", GotDeparture)
    end
end)

-- the travel network is ready: add the crossings already known
ns.On("TRAVEL_LOADED", function()
    continents = nil
    local st = Store()
    for _, c in pairs(st and st.crossings or {}) do
        c.used = nil
        if c.mine or CountKeys(c.by) >= 2 then
            UseCrossing(c)
        end
    end
end)

-- you got on a boat or zeppelin: it left at `left` (game time)
ns.On("TRAVEL_BOARDED", function(key, left)
    local ago = left and (GetTime() - left) or 0
    NoteDeparture(key, floor(ServerTime() - max(0, ago) + 0.5), true)
end)

-- the number of squares known (for the settings and tests)
function Trails.Stats()
    local own, shared, crossings = 0, 0, 0
    local st = Store()
    if st then
        for _, g in pairs(st.own) do
            own = own + CountKeys(g)
        end
        for _, g in pairs(st.shared) do
            shared = shared + CountKeys(g)
        end
        for _, c in pairs(st.crossings) do
            if c.used then
                crossings = crossings + 1
            end
        end
    end
    return own, shared, crossings
end

function Trails.Clear()
    local db = WaypointTrackerDB
    if type(db) == "table" then
        db.trails = nil
    end
    counts, fresh, cache, last, continents = {}, {}, nil, nil, nil
    job, used = nil, nil
end

Trails._Record, Trails._FindPath, Trails._Key, Trails._fresh = Record, FindPath, Key, fresh

-- tests: true/false forces searches sliced or all at once; nil decides from the client
function Trails._SetSliced(on)
    forceSliced = on
    job, used = nil, nil
end

-- tests: the search pieces and limits, the job under way, the path kept
Trails._Search = { New = NewSearch, Expand = Expand, SQUARES = SLICE_SQUARES, POPS = SLICE_POPS,
    CLOCK_EVERY = CLOCK_EVERY, MS = SLICE_MS, IDLE = SLICE_IDLE, KEEP = KEEP_IDLE, LIMIT = SEARCH_LIMIT }
function Trails._Job()
    return job
end
function Trails._Cache()
    return cache
end
