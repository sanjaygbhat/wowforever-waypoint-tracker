-- Trails: the walked-path search spread over frames (sliced). Trails.Steer
-- is asked every frame on a walking leg; a search there may only take a
-- small slice of a frame, must answer as the search all at once does, and
-- must not leave anything behind. Run from the repository root with Lua 5.1:
--     lua5.1 tests/run_trails_sliced.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local speed = 0 -- standing: the ticker writes nothing down unless a test walks
function GetUnitSpeed() return speed, 7, 7, 4.7 end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end

WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local Trails, Travel = ns.Trails, ns.Travel
Travel.Data()
local Key = Trails._Key
local S = Trails._Search -- the search pieces (nil before slicing existed)
local CAP = S and S.SQUARES or 100
local POPS = S and S.POPS or 400
local LIMIT = 3000
local SNAP = 50 -- squares read by the two Snaps when a search starts
local MAX_FRAMES = math.ceil((LIMIT + 1) / CAP) + 1 -- a search's frames, start to answer
check(S ~= nil and Trails._SetSliced ~= nil and Trails._Job ~= nil and Trails._Cache ~= nil,
    "the sliced search and its test switches exist")
check(debugprofilestop == nil, "the mock has no frame clock: searches are all at once unless a test says")
check(CAP <= 100 and POPS <= 400, ("slice limits: %d squares, %d entries"):format(CAP, POPS))
local function SetSliced(on)
    if Trails._SetSliced then Trails._SetSliced(on) end
end
local function Job() return Trails._Job and Trails._Job() end
local function Cache() return Trails._Cache and Trails._Cache() end
local function Errors() return #M.errors end

local CELL = 20
local OFFSET = 2048
local function Unkey(k) return math.floor(k / 4096) - OFFSET, k % 4096 - OFFSET end
local DIRS = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }

-- Squares read from the own grid (black box: one per square searched from,
-- 25 per Snap), the same on the code before and after slicing.
local reads = 0
local function Counted(real)
    return setmetatable({}, {
        __index = function(_, k)
            reads = reads + 1
            return real[k]
        end,
        __newindex = real,
    })
end

-- Entries taken off the search's list (Pop's table.remove), while counting.
local pops, countPops = 0, false
local realRemove = table.remove
table.remove = function(t, ...)
    if countPops then pops = pops + 1 end
    return realRemove(t, ...)
end

-- a set of squares; Linked turns it into grid bits (each square linked to
-- its neighbours in the set, both ways, as walking writes them)
local function Rect(set, x0, x1, y0, y1)
    for x = x0, x1 do
        for y = y0, y1 do set[Key(x, y)] = true end
    end
    return set
end
local function Cut(set, x0, x1, y0, y1)
    for x = x0, x1 do
        for y = y0, y1 do set[Key(x, y)] = nil end
    end
    return set
end
local function Linked(set)
    local g = {}
    for k in pairs(set) do
        local x, y = Unkey(k)
        local bits = 0
        for i, d in ipairs(DIRS) do
            if set[Key(x + d[1], y + d[2])] then bits = bits + 2 ^ (i - 1) end
        end
        g[k] = bits
    end
    return g
end

local st
local function Ground(own, shared, cont)
    cont = cont or 0
    st = Trails.Store()
    st.own, st.shared, st.pending = {}, {}, {}
    st.own[cont] = own and Counted(own) or nil
    st.shared[cont] = shared
end
local function Center(cx, cy, cont) return { cont = cont or 0, wx = (cx + .5) * CELL, wy = (cy + .5) * CELL } end

-- One frame of Steer: its bearing, the own-grid reads, whether it raised.
local DT = 1 / 60
local function Frame(here, target)
    M.now = M.now + DT
    local r0 = reads
    local ok, bearing = pcall(Trails.Steer, here, target)
    return bearing, reads - r0, ok
end

local function SamePath(a, b)
    if a == nil or b == nil then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- The search all at once as released in 1.3.1 (Trails.lua FindPath,
-- verbatim but for the grids passed in): the reference answers.
-- ---------------------------------------------------------------------------
local floor, sqrt = math.floor, math.sqrt
local BITS = {}
for i = 1, 8 do BITS[i] = 2 ^ (i - 1) end
local function HasBit(bits, b) return bits % (b + b) >= b end
local function Or(a, b)
    local out = 0
    for i = 1, 8 do
        local bit = BITS[i]
        if HasBit(a, bit) or HasBit(b, bit) then out = out + bit end
    end
    return out
end
local SEARCH_LIMIT = LIMIT
local function ReferencePath(own, shared, sx, sy, gx, gy)
    local function Bits(k)
        local a, b = own[k] or 0, shared[k] or 0
        if a == 0 then
            return b
        elseif b == 0 then
            return a
        end
        return Or(a, b)
    end
    local start, goal = Key(sx, sy), Key(gx, gy)
    local function H(k)
        local x, y = Unkey(k)
        local dx, dy = x - gx, y - gy
        return sqrt(dx * dx + dy * dy)
    end
    local heap = { { H(start), start } }
    local function Push(f, k)
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
    local function Pop()
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
    local g, prev, closed, n = { [start] = 0 }, {}, {}, 0
    while heap[1] do
        local k = Pop()[2]
        if k == goal then
            local out = {}
            while k do
                table.insert(out, 1, k)
                k = prev[k]
            end
            return out
        end
        if not closed[k] then
            closed[k] = true
            n = n + 1
            if n > SEARCH_LIMIT then
                return nil
            end
            local bits = Bits(k)
            local x, y = Unkey(k)
            for i = 1, 8 do
                if HasBit(bits, BITS[i]) then
                    local d = DIRS[i]
                    local nk = Key(x + d[1], y + d[2])
                    if not closed[nk] then
                        local cost = g[k] + ((d[1] ~= 0 and d[2] ~= 0) and 1.414 or 1)
                        if not g[nk] or cost < g[nk] then
                            g[nk], prev[nk] = cost, k
                            Push(cost + H(nk), nk)
                        end
                    end
                end
            end
        end
    end
end

-- Steer every frame from `here` (or here(frame)) until a job started there
-- has answered: the frames it took, the worst reads in one frame, the
-- bearings seen meanwhile.
local function UntilAnswer(here, target, maxFrames)
    local worst, frames, bearings, answered = 0, 0, {}, false
    local cache0 = Cache()
    for f = 1, maxFrames do
        local h = type(here) == "function" and here(f) or here
        local bearing, used = Frame(h, target)
        bearings[f] = bearing or false
        if used > worst then worst = used end
        frames = f
        if Cache() ~= cache0 and not Job() then
            answered = true
            break
        end
    end
    return answered, frames, worst, bearings
end

-- ---------------------------------------------------------------------------
-- (a) No frame looks around from more than CAP squares
-- ---------------------------------------------------------------------------
SetSliced(true)
do
    -- a 100 x 100 walked block, the goal's block cut off: fails after LIMIT squares
    local own = Linked(Rect(Rect({}, 0, 99, 0, 99), 200, 205, 0, 5))
    Ground(own)
    local goal = Center(202, 2)
    local here = Center(50, 50)
    local answered, frames, worst = UntilAnswer(here, goal, 400)
    local c = Cache()
    check(answered, "(a) the failing 3000-square search answers")
    check(worst <= CAP + SNAP, ("(a) failing 3000-square search: at most %d squares a frame (+%d Snap reads): worst %d")
        :format(CAP, SNAP, worst))
    check(frames >= math.ceil((LIMIT + 1) / CAP) and frames <= MAX_FRAMES,
        ("(a) failing search: answered in %d frames (%d..%d)"):format(frames, math.ceil((LIMIT + 1) / CAP), MAX_FRAMES))
    check(c and c.path == nil and c.searched == true, "(a) the answer is 'no way', as all at once")
    check(Frame(here, goal) == nil, "(a) no bearing")

    -- a > LIMIT component with a wall: the way round is found after many squares
    local set = Cut(Rect({}, 0, 69, 0, 69), 35, 35, 0, 40)
    own = Linked(set)
    Ground(own)
    local from, to = Center(20, 10), Center(60, 10)
    local ref = ReferencePath(own, {}, 20, 10, 60, 10)
    answered, frames, worst = UntilAnswer(from, to, 400)
    c = Cache()
    check(answered and frames >= 3, ("(a) the way round a wall in a 4,859-square component takes %d frames"):format(frames))
    check(worst <= CAP + SNAP, ("(a) way round a wall: at most %d squares a frame (+%d): worst %d"):format(CAP, SNAP, worst))
    check(ref ~= nil and c and SamePath(c.path, ref), "(a) the way round a wall is the one found all at once")

    -- the slice limits counted inside the search: squares and list entries
    if S then
        for _, case in ipairs({ { 50, 50, 300, 300, Linked(Rect({}, 0, 99, 0, 99)) }, { 20, 10, 60, 10, own } }) do
            Ground(case[5])
            local s = S.New(0, case[1], case[2], case[3], case[4])
            local worstN, worstPops, slices = 0, 0, 0
            while not s.done do
                local n0 = s.n
                pops, countPops = 0, true
                S.Expand(s, CAP, POPS, nil)
                countPops = false
                slices = slices + 1
                worstN = math.max(worstN, s.n - n0)
                worstPops = math.max(worstPops, pops)
            end
            check(worstN <= CAP and worstPops <= POPS and slices > 1,
                ("(a) inside the search: worst slice %d squares (cap %d), %d entries (cap %d), %d slices")
                :format(worstN, CAP, worstPops, POPS, slices))
        end
    end
end

-- ---------------------------------------------------------------------------
-- (b) Sliced, the answer is the same as all at once (and as 1.3.1)
-- ---------------------------------------------------------------------------
do
    local seed = 12345
    local function rand(n) -- 1..n, the same on every machine
        seed = (seed * 1103515245 + 12345) % 2147483648
        return 1 + math.floor(seed / 2147483648 * n)
    end
    local function chance(p) return rand(1000) <= p * 1000 end
    local function RandomGrid(w, h, density, mode)
        local set = {}
        for x = 0, w - 1 do
            for y = 0, h - 1 do
                if chance(density) then set[Key(x, y)] = true end
            end
        end
        if mode == "linked" then return Linked(set) end
        local g = {}
        for k in pairs(set) do g[k] = rand(256) - 1 end -- links any way, one way or both
        return g
    end
    local CASES = 300
    local same, sameSync, mismatch, sizes, found, notFound, bigs = 0, 0, nil, 0, 0, 0, 0
    local sizesKinds = { { 1, 4 }, { 5, 15 }, { 20, 40 }, { 56, 72 } }
    for case = 1, CASES do
        local kind = sizesKinds[(case % 4) + 1]
        if kind[1] == 56 and case % 12 ~= 3 then kind = sizesKinds[3] end -- a big one in every twelve
        local w, h = kind[1] + rand(kind[2] - kind[1] + 1) - 1, kind[1] + rand(kind[2] - kind[1] + 1) - 1
        local densities = { 1, 0.9, 0.7, 0.5 }
        local density = densities[rand(4)]
        local own = RandomGrid(w, h, density, chance(0.5) and "linked" or "random")
        local shared = chance(0.3) and RandomGrid(w, h, 0.5, chance(0.5) and "linked" or "random") or {}
        if chance(0.3) then -- split it in two
            local cx = rand(w) - 1
            for y = -1, h do own[Key(cx, y)], shared[Key(cx, y)] = nil, nil end
        end
        local n = 0
        for _ in pairs(own) do n = n + 1 end
        if n > LIMIT then bigs = bigs + 1 end
        local sx, sy, gx, gy = rand(w) - 1, rand(h) - 1, rand(w) - 1, rand(h) - 1
        if chance(0.1) then sx, sy = w + rand(5), h + rand(5) end -- the start off the walked squares
        if chance(0.15) then gx, gy = w + rand(50), -rand(50) end -- the goal off them
        local ref = ReferencePath(own, shared, sx, sy, gx, gy)
        if ref then found = found + 1 else notFound = notFound + 1 end
        Ground(own, shared)
        local sync = Trails._FindPath(0, sx, sy, gx, gy)
        if SamePath(sync, ref) then sameSync = sameSync + 1 end
        if S then
            -- sliced with small, changing limits and a clock that may say "spent"
            local s = S.New(0, sx, sy, gx, gy)
            local clockNow = 0
            debugprofilestop = function()
                clockNow = clockNow + (rand(10) == 1 and -5 or rand(3) * 0.1)
                return clockNow
            end
            local guard = 0
            while not s.done and guard < 100000 do
                S.Expand(s, rand(7), rand(3) == 1 and rand(10) or POPS, rand(2) == 1 and debugprofilestop() or nil)
                guard = guard + 1
            end
            debugprofilestop = nil
            if s.done and SamePath(s.path, ref) then
                same = same + 1
            elseif not mismatch then
                mismatch = ("case %d: %dx%d start %d,%d goal %d,%d"):format(case, w, h, sx, sy, gx, gy)
            end
        end
        sizes = sizes + n
    end
    check(sameSync == CASES, ("(b) all at once: the same answers as 1.3.1 in %d of %d cases"):format(sameSync, CASES))
    check(same == CASES, ("(b) sliced: the same answers as 1.3.1 in %d of %d cases (%s)")
        :format(same, CASES, tostring(mismatch)))
    check(found > 30 and notFound > 30 and bigs >= 10,
        ("(b) the cases cover ways found (%d), none (%d), components over %d squares (%d)"):format(found, notFound, LIMIT, bigs))
end
debugprofilestop = nil

-- ---------------------------------------------------------------------------
-- (c) No flicker: while a search is under way Steer answers from the path
-- it had (the same key), or as with no path (another stop)
-- ---------------------------------------------------------------------------
do
    -- a walked corridor north along x = 0 to the stop, and beside it (from
    -- x = 3) a big walked block not joined to it
    local set = Rect(Rect({}, 0, 0, 0, 80), 3, 62, 0, 59)
    local own = Linked(set)
    Ground(own)
    local stop = Center(0, 80)
    M.now = M.now + 100
    local onPath = Center(0, 10)
    local answered = UntilAnswer(onPath, stop, 10)
    local c1 = Cache()
    local b1 = Frame(onPath, stop)
    check(answered and c1 and c1.path and b1 ~= nil, "(c) on the corridor: a way, a bearing")
    -- into the block, 60 yards off the corridor: a re-search starts (big: the
    -- block is 3,600 squares and has no way to the stop)
    local off = Center(3, 10)
    M.now = M.now + 1
    local b, used = Frame(off, stop)
    local j = Job()
    check(j ~= nil and Cache() == c1, ("(c) off the path: a search is under way, the path kept (%d reads)"):format(used))
    check(b == nil, "(c) 60 yards off the path: no bearing, as before the search")
    -- back on the corridor while it runs: the bearing from the path kept
    local frames, back, changed, worst = 0, {}, false, 0
    while Job() == j and frames < 200 do
        local h = (frames % 2 == 0) and onPath or off
        local bearing, n = Frame(h, stop)
        frames = frames + 1
        if Job() == j then
            if Cache() ~= c1 then changed = true end
            back[#back + 1] = { h == onPath, bearing }
        end
        if n > worst then worst = n end
    end
    local ok = #back > 2
    for _, r in ipairs(back) do
        if r[1] and r[2] ~= b1 then ok = false end
        if not r[1] and r[2] ~= nil then ok = false end
    end
    check(ok and not changed, ("(c) while the search runs (%d frames): on the old path its bearing, off it none, never a part path")
        :format(#back))
    check(worst <= CAP + SNAP, ("(c) at most %d squares a frame: worst %d"):format(CAP, worst))
    local c2 = Cache()
    local ref = ReferencePath(own, {}, 3, 10, 0, 80)
    check(c2 ~= c1 and SamePath(c2.path, ref) and c2.pcx == 3 and c2.pcy == 10,
        "(c) then the search's answer (from where it started), as all at once")

    -- another stop: as with no path until the answer
    local stop2 = Center(62, 59)
    Ground(Linked(Cut(set, 30, 30, 0, 58)))
    local here = Center(5, 5)
    M.now = M.now + 100
    UntilAnswer(here, Center(5, 40), 60) -- a way to a first stop
    local before = Cache()
    check(before and before.path and Frame(here, Center(5, 40)) ~= nil, "(c) a way to the first stop")
    local bearings
    answered, frames, worst, bearings = UntilAnswer(here, stop2, 400)
    local none = true
    for f = 1, frames - 1 do
        if bearings[f] then none = false end
    end
    check(answered and frames > 1 and none, ("(c) a new stop: no bearing for the %d frames until the answer"):format(frames - 1))
    check(worst <= CAP + SNAP, ("(c) new stop: at most %d squares a frame: worst %d"):format(CAP, worst))
end

-- ---------------------------------------------------------------------------
-- (d) What changes while a search runs
-- ---------------------------------------------------------------------------
do
    local big = Rect({}, 0, 99, 0, 99)
    Rect(big, 200, 205, 0, 5)
    local own = Linked(big)
    Ground(own)
    local goal, goal2 = Center(202, 2), Center(203, 4)
    local here = Center(50, 50)
    M.now = M.now + 100
    -- another stop: let go, a search for the new one
    Frame(here, goal)
    local j1 = Job()
    Frame(here, goal2)
    local j2 = Job()
    check(j1 and j2 and j1 ~= j2 and j2.key ~= j1.key, "(d) another stop: the search is let go, one for the new stop starts")
    -- the player moves on: the same search goes on, then answers from where it began
    local x = 50
    local answered, frames = UntilAnswer(function(f)
        if f % 3 == 0 then x = x + 1 end
        return Center(x, 50)
    end, goal2, 400)
    local c = Cache()
    check(answered and frames <= MAX_FRAMES and c.pcx == 50 and c.pcy == 50,
        ("(d) moving on: the search goes on (%d frames) and answers for its start square"):format(frames))
    -- squares replaced (a reset of the store's tables): started again on the new ones
    M.now = M.now + 100
    Frame(here, goal)
    j1 = Job()
    Ground(own)
    Frame(here, goal)
    j2 = Job()
    check(j1 and j2 and j1 ~= j2 and j2.search.own == st.own[0], "(d) squares replaced: the search starts again on them")
    -- forgetting everything (Trails.Clear): no search left
    Trails.Clear()
    check(Job() == nil and Cache() == nil, "(d) Trails.Clear: no search, no path left")
    -- another continent: the stop there is another search
    Ground(own)
    M.now = M.now + 100
    Frame(here, goal)
    j1 = Job()
    st.own[1] = Counted(own)
    Frame(Center(50, 50, 1), Center(202, 2, 1))
    j2 = Job()
    check(j1 and j2 and j2 ~= j1 and j2.cont == 1, "(d) another continent: the search there replaces the one here")
    -- the stop on another continent than the player (Steer answers nothing):
    -- the search is let go within SLICE_IDLE (and the half-second ticker)
    Frame(Center(50, 50, 0), Center(202, 2, 1))
    M.Tick(2, 0.5)
    check(Job() == nil, "(d) not carried on: let go after SLICE_IDLE")
    st.own[1] = nil

    -- newly walked squares join while it runs: it goes on, then the re-search
    -- rules follow it up and find the way. Elwynn in the mock: world x =
    -- -2000 * map y, world y = -3000 * map x.
    local set = Rect({}, -90, -11, -80, -36) -- 3,600 squares
    Rect(set, -60, -41, -14, -5) -- the stop's block
    Rect(set, -50, -50, -35, -16) -- a corridor north to a dead end at -16
    local g = Linked(set)
    Ground(g)
    local stop = Center(-50, -8)
    local from = Center(-50, -40)
    M.now = M.now + 100
    Frame(from, stop)
    local j = Job()
    speed = 7
    local function Walk(at)
        M.player.inst, M.player.wx, M.player.wy = 0, at.wx, at.wy
        Trails._Record()
        M.now = M.now + 0.7 -- (a step at walking pace) the search is carried on between
        Frame(from, stop)
    end
    Walk(Center(-50, -16))
    Walk(Center(-50, -15)) -- a dead end
    Walk(Center(-50, -14)) -- joins the dead end to the stop's block
    speed = 0
    check(j and Job() == j, "(d) squares joined while it runs: the same search goes on")
    check(j and j.search.closed[Key(-50, -16)], "(d) (the search had passed the dead end before the squares joined)")
    local bearing
    local answers, seenCache, answeredAt = {}, Cache(), {}
    for _ = 1, 300 do
        bearing = Frame(from, stop)
        if Cache() ~= seenCache then
            seenCache = Cache()
            answers[#answers + 1] = seenCache
            answeredAt[#answers] = M.now
        end
        if bearing then break end
    end
    local first, second = answers[1], answers[2]
    check(#answers == 2 and first.at == j.at and first.path == nil and first.joins == j.joins,
        ("(d) squares joined: the search under way finishes with its own answer, no way (%d answers)"):format(#answers))
    local gap = second and (second.at - answeredAt[1]) or -1
    check(second and second.path ~= nil and second.joins ~= j.joins and bearing ~= nil and gap > 0 and gap < 2 * DT,
        ("(d) then the re-search rules follow it up the next frame (%.3f s later, not NO_PATH_AGAIN) and find the way")
        :format(gap))

    -- progress: a player moving one square every N frames, on and off a way,
    -- shorter and longer than a search: every search started answers
    for _, N in ipairs({ 2, 60 }) do
        local field = Rect({}, 0, 79, 0, 79)
        Cut(field, 0, 79, 40, 40) -- the north half isn't joined: no way to the stop from there
        Rect(field, 40, 40, 40, 40) -- but for one square in the middle
        Ground(Linked(field))
        local target = Center(40, 79)
        M.now = M.now + 100
        local started, answered, worstFrames, restarts = 0, 0, 0, 0
        local cur, startFrame
        local px, py, dir = 5, 5, 1
        for f = 1, 3600 do
            if f % N == 0 then
                px = px + dir
                if px > 74 or px < 5 then
                    dir = -dir
                    py = py + 3
                    if py > 35 then py = 5 end
                end
            end
            local c0 = Cache()
            Frame(Center(px, py), target)
            local now = Job()
            if cur and now ~= cur then
                if Cache() ~= c0 and Cache().at == cur.at then
                    answered = answered + 1
                    worstFrames = math.max(worstFrames, f - startFrame)
                else
                    restarts = restarts + 1
                end
                cur = nil
            end
            if now and now ~= cur then
                cur, startFrame, started = now, f, started + 1
            end
        end
        check(started >= 3 and answered >= started - 1 and restarts == 0 and worstFrames <= MAX_FRAMES,
            ("(d) moving one square every %d frames: %d searches, %d answered, %d let go, worst %d frames (<= %d)")
            :format(N, started, answered, restarts, worstFrames, MAX_FRAMES))
    end
end

-- ---------------------------------------------------------------------------
-- (e) The frame clock: a slice ends when it says SLICE_MS have passed, and at
-- once when it went back (debugprofilestart) or stops answering
-- ---------------------------------------------------------------------------
do
    local own = Linked(Rect(Rect({}, 0, 99, 0, 99), 200, 205, 0, 5))
    local ref = ReferencePath(own, {}, 50, 50, 202, 2)
    local CLOCK_EVERY = S and S.CLOCK_EVERY or 16
    local clocks = {
        { "advancing 0.3 ms a reading", function(t) return t + 0.3 end, 4 * CLOCK_EVERY },
        { "going back (debugprofilestart)", function(t) return t - 50 end, CLOCK_EVERY },
        { "no number", function() return nil end, CLOCK_EVERY },
    }
    for _, case in ipairs(clocks) do
        Ground(own)
        SetSliced(nil)
        local t = 1000
        local readings = 0
        debugprofilestop = function()
            readings = readings + 1
            if readings == 1 then return t end -- each slice's first reading is good
            local v = case[2](t)
            if type(v) == "number" then t = v end
            return v == nil and "x" or v
        end
        M.now = M.now + 100
        local worstPops, frames, done = 0, 0, false
        while frames < 1000 do
            readings = 0
            pops, countPops = 0, true
            Frame(Center(50, 50), Center(202, 2))
            countPops = false
            frames = frames + 1
            if Job() then
                worstPops = math.max(worstPops, pops)
            elseif frames > 1 then
                done = true
                break
            end
        end
        debugprofilestop = nil
        SetSliced(true)
        local c = Cache()
        check(done and worstPops <= case[3] and worstPops > 0 and c and SamePath(c.path, ref),
            ("(e) clock %s: slices end by %d entries (worst %d), %d frames, same answer")
            :format(case[1], case[3], worstPops, frames))
    end
end

-- ---------------------------------------------------------------------------
-- (f) An error inside the search: reported once, the search let go, tried
-- again only at the usual pace
-- ---------------------------------------------------------------------------
do
    local own = Linked(Rect(Rect({}, 0, 49, 0, 49), 200, 205, 0, 5))
    own[Key(0, 49)] = {} -- a broken square (not a number), searched late
    Ground(own)
    local here, stop = Center(30, 30), Center(202, 2)
    M.now = M.now + 100
    local e0 = Errors()
    local raised, jobsAfter, framesWithJob = 0, 0, 0
    local errFrame
    for f = 1, 60 * 9 do -- nine seconds
        local _, _, ok = Frame(here, stop)
        if not ok then raised = raised + 1 end
        if Job() then framesWithJob = framesWithJob + 1 end
        if not errFrame and Errors() > e0 then errFrame = f end
        if errFrame and f > errFrame and Job() then jobsAfter = jobsAfter + 1 end
    end
    check(raised == 0, ("(f) Steer itself never raises (%d)"):format(raised))
    check(Errors() == e0 + 1, ("(f) reported once (%d)"):format(Errors() - e0))
    check(errFrame and Job() == nil and jobsAfter == 0, "(f) the search is let go and not started again within NO_PATH_AGAIN")
    check(framesWithJob >= 1, "(f) the search ran in slices before the error")
    for _ = 1, 60 * 2 do Frame(here, stop) end -- past NO_PATH_AGAIN: tried again, the same error, not reported again
    check(Errors() == e0 + 1 and Job() == nil, "(f) tried again later: still reported once, nothing left running")
    if Errors() == e0 + 1 then M.errors[#M.errors] = nil end -- the one expected
end

-- ---------------------------------------------------------------------------
-- (g) Nothing kept: settings off, the waypoint gone, another zone; and no
-- more garbage a frame than all at once when no search runs
-- ---------------------------------------------------------------------------
do
    local own = Linked(Rect(Rect({}, 0, 99, 0, 99), 200, 205, 0, 5))
    local function Running()
        -- a path followed to one stop, then a search for another
        local set = Rect(Rect(Rect({}, 0, 99, 0, 99), 200, 205, 0, 5), 0, 0, 100, 180)
        Ground(Linked(set))
        M.now = M.now + 100
        UntilAnswer(Center(0, 120), Center(0, 180), 10)
        local kept = Cache() and Cache().path
        Frame(Center(50, 50), Center(202, 2))
        Frame(Center(50, 50), Center(202, 2))
        return Job() ~= nil and kept ~= nil
    end
    for _, setting in ipairs({ "travelTrails", "realRoutes" }) do
        local running = Running()
        ns.Set(setting, false)
        M.Tick(0.5, 0.5)
        check(running and Job() == nil and Cache() == nil, "(g) " .. setting .. " off: no search, no path kept")
        ns.Set(setting, true)
    end
    -- the waypoint cleared (Steer not asked any more)
    local running = Running()
    M.Tick(1.5, 0.5)
    check(running and Job() == nil, "(g) Steer no longer asked: the search let go after SLICE_IDLE")
    M.Tick((S and S.KEEP or 10) + 1, 0.5)
    check(Cache() == nil, "(g) and the path after KEEP_IDLE")
    -- a path in use is kept while it is used
    Ground(Linked(Rect({}, 0, 0, 0, 80)))
    local stop, on = Center(0, 80), Center(0, 10)
    UntilAnswer(on, stop, 10)
    for _ = 1, 30 do
        M.Tick(0.5, 0.5)
        Frame(on, stop)
    end
    check(Cache() ~= nil and Cache().path ~= nil and Frame(on, stop) ~= nil, "(g) a path still followed is kept")
    -- garbage a frame while following (no search): sliced as all at once
    local function Garbage(sliced)
        SetSliced(sliced)
        Ground(Linked(Rect({}, 0, 0, 0, 80)))
        M.now = M.now + 100
        UntilAnswer(on, stop, 10)
        Frame(on, stop)
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 2000 do Frame(on, stop) end
        local kb = collectgarbage("count") - before
        collectgarbage("restart")
        return kb
    end
    local syncKB, slicedKB = Garbage(false), Garbage(true)
    check(Job() == nil and slicedKB <= syncKB + 1,
        ("(g) following a path, no search: %.1f KB per 2000 frames sliced, %.1f all at once"):format(slicedKB, syncKB))
end

-- ---------------------------------------------------------------------------
-- Without a frame clock nothing changes: all at once, as before
-- ---------------------------------------------------------------------------
SetSliced(nil)
do
    Ground(Linked(Rect(Rect({}, 0, 99, 0, 99), 200, 205, 0, 5)))
    M.now = M.now + 100
    local _, used = Frame(Center(50, 50), Center(202, 2))
    check(Job() == nil and used > LIMIT and Cache() and Cache().searched, ("no clock: the search all at once (%d reads)"):format(used))
end

table.remove = realRemove
check(#M.errors == 0, "no other Lua errors: " .. tostring(M.errors[1]))
print(("Trails sliced: %d passed, %d failed"):format(passed, failed))
os.exit((failed == 0 and #M.errors == 0) and 0 or 1)
