-- Routes: lists of waypoints followed one after another (a mining loop, a
-- tour of quest givers), kept, shared with other players and voted on.
--
--   * a route is { id, v, name, cat, mode, note, author, made, pts }, pts
--     being { m, x, y, t } with x/y from 0 to 1 and an optional title
--   * mode "order" visits the points one by one, "loop" goes round and
--     round, "nearest" always takes the closest point left
--   * routes are kept for the account (WaypointTrackerDB.routes): yours,
--     the ones other players shared, and the suggested ones you used
--   * votes: one per character, counted from what each player says about
--     their own vote (RoutesNet.lua carries them)
--   * the route you're following is kept per character, with how long
--     you've followed it: after a while, finishing or stopping it asks how
--     it was
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local Routes = {}
ns.Routes = Routes

Routes.CATEGORIES = { "mining", "herbs", "skinning", "fishing", "farming", "treasure", "quests", "travel", "dungeons", "other" }
Routes.MODES = { "order", "loop", "nearest" }
local CAT_LABEL = {
    mining = "ROUTE_CAT_MINING", herbs = "ROUTE_CAT_HERBS", skinning = "ROUTE_CAT_SKINNING",
    fishing = "ROUTE_CAT_FISHING", farming = "ROUTE_CAT_FARMING",
    treasure = "ROUTE_CAT_TREASURE", quests = "ROUTE_CAT_QUESTS", travel = "ROUTE_CAT_TRAVEL",
    dungeons = "ROUTE_CAT_DUNGEONS", other = "ROUTE_CAT_OTHER",
}
local MODE_LABEL = { order = "ROUTE_MODE_ORDER", loop = "ROUTE_MODE_LOOP", nearest = "ROUTE_MODE_NEAREST" }
local IS_CAT, IS_MODE = {}, {}
for _, c in ipairs(Routes.CATEGORIES) do
    IS_CAT[c] = true
end
for _, m in ipairs(Routes.MODES) do
    IS_MODE[m] = true
end

Routes.MAX_POINTS = 200
Routes.MAX_NAME = 48
Routes.MAX_NOTE = 140
local MAX_TITLE = 30
local MAX_LIBRARY = 400 -- routes from other players kept at most
local MAX_TALLIES = 3000 -- routes whose votes are counted at most
local MAX_VOTERS = 1000 -- votes counted per route at most
Routes.TAG = "WTR1"
Routes.SUGGESTED_AUTHOR = "Waypoint Tracker"
-- how long (seconds) you follow a route before finishing or stopping it
-- asks how it was; /wp routes fast makes it 20 seconds for trying it out
Routes.feedbackAfter = 300

function Routes.CategoryLabel(c)
    return L[CAT_LABEL[c] or "ROUTE_CAT_OTHER"]
end

function Routes.ModeLabel(m)
    return L[MODE_LABEL[m] or "ROUTE_MODE_ORDER"]
end

-- ---------------------------------------------------------------------------
-- Who you are, and where routes are kept
-- ---------------------------------------------------------------------------
local function Realm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(r) ~= "string" or r == "" then
        r = (GetRealmName and GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return r
end

-- "Name-Realm", the way addon messages name their sender
function Routes.FullName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if name:find("-", 1, true) then
        return name
    end
    local realm = Realm()
    return realm ~= "" and (name .. "-" .. realm) or name
end

function Routes.Me()
    return Routes.FullName(UnitName("player")) or "?"
end

-- the name without the realm when it's yours, for showing
function Routes.ShortName(name)
    if type(name) ~= "string" then
        return "?"
    end
    local realm = Realm()
    if realm ~= "" and name:sub(-#realm - 1) == "-" .. realm then
        return name:sub(1, -#realm - 2)
    end
    return name
end

local function Store()
    local db = WaypointTrackerDB
    if type(db) ~= "table" then
        return nil
    end
    local r = db.routes
    if type(r) ~= "table" then
        r = {}
        db.routes = r
    end
    for _, k in ipairs({ "list", "votes", "tally", "blocked" }) do
        if type(r[k]) ~= "table" then
            r[k] = {}
        end
    end
    return r
end
Routes.Store = Store

local function Run()
    local c = ns.charDB
    local run = c and c.routeRun
    return type(run) == "table" and run or nil
end
Routes.Run = Run

-- ---------------------------------------------------------------------------
-- Checking a route (from your saved file, a paste, or another player)
-- ---------------------------------------------------------------------------
-- text fields never hold what the share format uses to split them
local function Clean(s, max)
    s = ns.CleanText(s, max)
    if not s then
        return nil
    end
    s = ns.Trim(s:gsub("[%^\t]", " "))
    return s ~= "" and s or nil
end

local function CleanTitle(s)
    s = Clean(s, MAX_TITLE)
    if not s then
        return nil
    end
    s = ns.Trim(s:gsub("[,;]", " "))
    return s ~= "" and s or nil
end

function Routes.ValidID(id)
    return type(id) == "string" and #id >= 3 and #id <= 24 and id:match("^[%w%-]+$") ~= nil
end

-- The map most of its points are on.
local function MainMap(pts)
    local count, best, bestN = {}, nil, 0
    for _, p in ipairs(pts) do
        count[p.m] = (count[p.m] or 0) + 1
        if count[p.m] > bestN then
            best, bestN = p.m, count[p.m]
        end
    end
    return best
end

-- A clean copy, or nil when it isn't a usable route. Drafts (no id yet)
-- pass with allowDraft.
function Routes.Validate(r, allowDraft)
    if type(r) ~= "table" or type(r.pts) ~= "table" then
        return nil
    end
    local out = {
        id = Routes.ValidID(r.id) and r.id or nil,
        v = ns.Int(r.v) or 1,
        name = Clean(r.name, Routes.MAX_NAME) or L.ROUTE_UNNAMED,
        cat = IS_CAT[r.cat] and r.cat or "other",
        mode = IS_MODE[r.mode] and r.mode or "order",
        note = Clean(r.note, Routes.MAX_NOTE),
        author = Clean(r.author, 60),
        made = ns.Int(r.made) or 0,
        pts = {},
    }
    if not out.id and not allowDraft then
        return nil
    end
    for _, p in ipairs(r.pts) do
        if #out.pts >= Routes.MAX_POINTS then
            break
        end
        local m, x, y = ns.Int(type(p) == "table" and p.m), tonumber(type(p) == "table" and p.x), tonumber(type(p) == "table" and p.y)
        if m and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 and Geo.IsValidMap(m) then
            out.pts[#out.pts + 1] = { m = m, x = x, y = y, t = CleanTitle(p.t) }
        end
    end
    if #out.pts == 0 then
        return nil
    end
    out.zone = MainMap(out.pts)
    return out
end

-- ---------------------------------------------------------------------------
-- Text: "WTR1^id^v^cat^mode^made^author^name^note^m,x,y,title;..." on one
-- line (x/y from 0 to 10000), the same for copying and for addon messages.
-- Pasting plain /way lines works too.
-- ---------------------------------------------------------------------------
function Routes.Serialize(r)
    Routes.Prepare(r)
    local pts = {}
    for _, p in ipairs(r.pts) do
        local s = ("%d,%d,%d"):format(p.m, math.floor(p.x * 10000 + 0.5), math.floor(p.y * 10000 + 0.5))
        if p.t then
            s = s .. "," .. p.t
        end
        pts[#pts + 1] = s
    end
    return table.concat({
        Routes.TAG, r.id or "", tostring(r.v or 1), r.cat or "other", r.mode or "order", tostring(r.made or 0),
        r.author or "", r.name or "", r.note or "", table.concat(pts, ";"),
    }, "^")
end

local function SplitKeep(s, sep)
    local out, from = {}, 1
    while true do
        local i = s:find(sep, from, true)
        if not i then
            out[#out + 1] = s:sub(from)
            return out
        end
        out[#out + 1] = s:sub(from, i - 1)
        from = i + 1
    end
end

local function ParseTagged(text)
    local f = SplitKeep(text, "^")
    if #f < 10 or f[1] ~= Routes.TAG then
        return nil
    end
    local r = {
        id = f[2] ~= "" and f[2] or nil, v = tonumber(f[3]), cat = f[4], mode = f[5], made = tonumber(f[6]),
        author = f[7], name = f[8], note = f[9], pts = {},
    }
    -- a note can't hold "^", but be kind to text cut in odd places
    local ptsText = table.concat(f, "^", 10)
    for item in ptsText:gmatch("[^;]+") do
        local m, x, y, t = item:match("^%s*(%d+),(%d+),(%d+),?(.*)$")
        if m then
            r.pts[#r.pts + 1] = { m = tonumber(m), x = tonumber(x) / 10000, y = tonumber(y) / 10000, t = t ~= "" and t or nil }
        end
    end
    return Routes.Validate(r, true)
end

-- the map for a /way line's zone part ("", "#1429" or a name)
local function ZoneOf(zoneText)
    if zoneText == "" then
        return C_Map.GetBestMapForUnit("player")
    elseif zoneText:match("^#%d+$") then
        local m = tonumber(zoneText:sub(2))
        return Geo.IsValidMap(m) and m or nil
    end
    return (Geo.FindZone(zoneText))
end

-- Plain lines like "/way Hillsbrad Foothills 55.4 33.2 1", "55.4 33.2" or
-- "/way #1424 55.4 33.2 Iron": a draft route, plus how many lines were skipped.
local function ParseWayLines(text)
    local pts, skipped = {}, 0
    for line in text:gmatch("[^\r\n]+") do
        line = ns.Trim(line)
        if line ~= "" then
            line = line:gsub("^/[%a]+%s*", "")
            local zoneText, x, y, title = Geo.ParseWayArgs(line)
            local m = x and ZoneOf(zoneText or "")
            if m then
                pts[#pts + 1] = { m = m, x = x / 100, y = y / 100, t = title ~= "" and title or nil }
            else
                skipped = skipped + 1
            end
        end
    end
    if #pts == 0 then
        return nil, skipped
    end
    return Routes.Validate({ name = L.ROUTE_IMPORTED_NAME, pts = pts }, true), skipped
end

-- A route from pasted text: returns route (maybe a draft without id), skipped lines.
function Routes.Parse(text)
    if type(text) ~= "string" then
        return nil, 0
    end
    text = ns.Trim(text)
    if text:sub(1, #Routes.TAG + 1) == Routes.TAG .. "^" then
        return ParseTagged(text:match("^[^\r\n]+")), 0
    end
    return ParseWayLines(text)
end

-- ---------------------------------------------------------------------------
-- Keeping routes
-- ---------------------------------------------------------------------------
local ALPHA = "0123456789abcdefghijklmnopqrstuvwxyz"
function Routes.NewID()
    local t, n = {}, time()
    for _ = 1, 6 do
        local d = n % 36
        t[#t + 1] = ALPHA:sub(d + 1, d + 1)
        n = math.floor(n / 36)
    end
    for _ = 1, 4 do
        local d = math.random(0, 35)
        t[#t + 1] = ALPHA:sub(d + 1, d + 1)
    end
    return table.concat(t)
end

function Routes.Get(id)
    local st = Store()
    local r = st and st.list[id]
    if r then
        return r
    end
    return Routes.GetSuggested and Routes.GetSuggested(id)
end

function Routes.IsMine(r)
    return r ~= nil and r.src == "mine"
end

local function Changed()
    ns.Fire("ROUTES_CHANGED")
end

-- Saves a route you made or changed. Returns the saved route.
function Routes.SaveMine(draft)
    local st = Store()
    local r = Routes.Validate(draft, true)
    if not (st and r) then
        return nil
    end
    local old = draft.id and st.list[draft.id]
    if old and old.src == "mine" then
        r.id, r.v, r.made = old.id, (old.v or 1) + 1, old.made
    else
        r.id, r.v, r.made = Routes.NewID(), 1, time()
    end
    r.author = Routes.Me()
    r.src = "mine"
    r.public = draft.public ~= false
    st.list[r.id] = r
    Changed()
    ns.Fire("ROUTE_SAVED", r.id)
    return r
end

-- A copy someone shared (or pasted text with an id). fromAuthor: it came
-- from the player who made it. Returns the kept route, and whether it's new.
function Routes.Keep(r, via, fromAuthor)
    local st = Store()
    r = Routes.Validate(r)
    if not (st and r and r.author) then
        return nil
    end
    -- suggested routes are made on your own computer, never taken from others
    if st.blocked[r.author] or r.author == Routes.SUGGESTED_AUTHOR or r.id:find("-", 1, true) then
        return nil
    end
    if r.author == Routes.Me() then
        return st.list[r.id], false -- your own route coming back
    end
    local have = st.list[r.id]
    if have then
        if have.src == "mine" then
            return have, false
        end
        -- newer versions replace older ones; a copy from its author beats a relayed one
        if (r.v < have.v) or (r.v == have.v and (have.fromAuthor or not fromAuthor)) then
            return have, false
        end
    end
    r.src = "shared"
    r.via = via and Clean(via, 60) or nil
    r.fromAuthor = fromAuthor or nil
    r.got = time()
    st.list[r.id] = r
    -- too many: let go of the oldest ones you never used or voted on
    local count, oldest, oldestAt = 0, nil, nil
    local runID = Run() and Run().id
    for id, x in pairs(st.list) do
        if x.src == "shared" then
            count = count + 1
            if not st.votes[id] and id ~= runID and (not oldestAt or (x.got or 0) < oldestAt) then
                oldest, oldestAt = id, x.got or 0
            end
        end
    end
    if count > MAX_LIBRARY and oldest then
        st.list[oldest] = nil
    end
    Changed()
    return r, have == nil
end

function Routes.Delete(id)
    local st = Store()
    if not (st and st.list[id]) then
        return
    end
    local run = Run()
    if run and run.id == id then
        Routes.Stop(true)
    end
    st.list[id] = nil
    Changed()
end

-- Stop seeing routes from this player.
function Routes.Block(author)
    local st = Store()
    if not (st and type(author) == "string") or author == Routes.Me() or author == Routes.SUGGESTED_AUTHOR then
        return
    end
    st.blocked[author] = true
    for id, r in pairs(st.list) do
        if r.author == author then
            st.list[id] = nil
        end
    end
    Changed()
end

-- A route from your waypoints, in the order they are in your list.
function Routes.FromWaypoints()
    local pts = {}
    for _, wp in ipairs(WP.List()) do
        local t = wp.title
        if wp.routeIndex then
            t = t and t:gsub("^%d+/%d+%s*", "") or nil
        end
        pts[#pts + 1] = { m = wp.m, x = wp.x, y = wp.y, t = t }
    end
    return Routes.Validate({ name = L.ROUTE_NEW_NAME, pts = pts }, true)
end

-- ---------------------------------------------------------------------------
-- Votes: one per character. Yours goes out to other players (RoutesNet);
-- theirs come in through Routes.HeardVote.
-- ---------------------------------------------------------------------------
local function Tally(id, create)
    local st = Store()
    if not st then
        return nil
    end
    local t = st.tally[id]
    if not t and create then
        local n = 0
        for _ in pairs(st.tally) do
            n = n + 1
            if n >= MAX_TALLIES then
                return nil
            end
        end
        t = {}
        st.tally[id] = t
    end
    return t
end

function Routes.Score(id)
    local up, down = 0, 0
    for _, v in pairs(Tally(id) or {}) do
        if v > 0 then
            up = up + 1
        elseif v < 0 then
            down = down + 1
        end
    end
    return up, down
end

function Routes.MyVote(id)
    local st = Store()
    local v = st and st.votes[id]
    return type(v) == "table" and v.v or 0
end

-- v: 1 (up), -1 (down) or 0 (take it back)
function Routes.Vote(id, v)
    local st = Store()
    local r = Routes.Get(id)
    if not (st and r) or Routes.IsMine(r) then
        return false
    end
    v = (v == 1 or v == -1) and v or 0
    local me = Routes.Me()
    if v == 0 then
        st.votes[id] = nil
    else
        st.votes[id] = { v = v, by = me, at = time() }
        -- a suggested route you vote on is kept, so its votes have a home
        if not st.list[id] then
            st.list[id] = Routes.Prepare(r)
        end
    end
    local t = Tally(id, v ~= 0)
    if t then
        t[me] = v ~= 0 and v or nil
    end
    ns.Fire("ROUTE_VOTED", id, v)
    Changed()
    return true
end

-- what another player said about their own vote
function Routes.HeardVote(id, voter, v)
    if not Routes.ValidID(id) or type(voter) ~= "string" then
        return
    end
    v = tonumber(v)
    if v ~= 1 and v ~= -1 and v ~= 0 then
        return
    end
    local t = Tally(id, v ~= 0)
    if not t then
        return
    end
    if v ~= 0 and t[voter] == nil then
        local n = 0
        for _ in pairs(t) do
            n = n + 1
        end
        if n >= MAX_VOTERS then
            return
        end
    end
    if t[voter] ~= (v ~= 0 and v or nil) then
        t[voter] = v ~= 0 and v or nil
        Changed()
    end
end

-- Your votes this character cast, for telling players who come online.
function Routes.MyVotes()
    local st, me, out = Store(), Routes.Me(), {}
    for id, v in pairs(st and st.votes or {}) do
        if type(v) == "table" and v.by == me then
            out[id] = v.v
        end
    end
    return out
end

-- Ranking: how sure we are it's good (Wilson lower bound, 95%), so 3 up
-- and none down doesn't beat 40 up and 2 down.
function Routes.Rating(up, down)
    local n = up + down
    if n == 0 then
        return 0
    end
    local z = 1.96
    local p = up / n
    return (p + z * z / (2 * n) - z * math.sqrt((p * (1 - p) + z * z / (4 * n)) / n)) / (1 + z * z / n)
end

-- Clearly disliked: hidden while browsing unless you ask to see them.
function Routes.IsLowRated(up, down)
    return down >= 3 and down >= up * 2
end

-- ---------------------------------------------------------------------------
-- Ready-made routes, made on your own computer from Find's database, for
-- every zone at once:
--   * a loop through every known spot of each ore, herb and fishing pool
--   * the treasure chests and the rare spawns of each zone
--   * hand-picked routes (WaypointTracker_Data/RouteSeeds.lua): skinning
--     and farming spots, quests and chains, dungeons, flight paths, tours
-- ---------------------------------------------------------------------------
local GATHER = {}
for _, n in ipairs({
    "Copper Vein", "Tin Vein", "Silver Vein", "Iron Deposit", "Gold Vein", "Mithril Deposit", "Truesilver Deposit",
    "Dark Iron Deposit", "Small Thorium Vein", "Rich Thorium Vein", "Incendicite Mineral Vein", "Lesser Bloodstone Deposit",
    "Indurium Mineral Vein", "Ooze Covered Silver Vein", "Ooze Covered Gold Vein", "Ooze Covered Mithril Deposit",
    "Ooze Covered Truesilver Deposit", "Ooze Covered Thorium Vein", "Ooze Covered Rich Thorium Vein",
}) do
    GATHER[n] = "mining"
end
for _, n in ipairs({
    "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp", "Bruiseweed", "Wild Steelbloom",
    "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker", "Wintersbite", "Firebloom",
    "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom", "Gromsblood", "Golden Sansam",
    "Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
}) do
    GATHER[n] = "herbs"
end
for _, n in ipairs({
    "Floating Wreckage", "Floating Debris", "Oil Spill", "Patch of Elemental Water", "Schooner Wreckage",
    "Waterlogged Wreckage", "Bloodsail Wreckage", "Stonescale Eel Swarm",
}) do
    GATHER[n] = "fishing"
end

-- "mining", "herbs" or "fishing" for a gathering node's English name
function Routes.GatherKind(englishName)
    if type(englishName) ~= "string" then
        return nil
    end
    return GATHER[englishName] or (englishName:find(" School$") and "fishing") or nil
end

local MIN_SUGGESTED = 4 -- spots a gathering route needs
local MIN_STOPS = 3 -- stops any other ready-made route needs
local SAME_SPOT = 0.01

-- shortest-ish loop: nearest neighbour, then untangle crossings (2-opt)
local function OrderLoop(pts)
    local n = #pts
    if n < 3 then
        return pts
    end
    local wx, wy = {}, {}
    for i, p in ipairs(pts) do
        local _, x, y = Geo.MapToWorld(p.m, p.x, p.y)
        wx[i], wy[i] = x or p.x * 1000, y or p.y * 1000
    end
    local function d(a, b)
        local dx, dy = wx[a] - wx[b], wy[a] - wy[b]
        return math.sqrt(dx * dx + dy * dy)
    end
    -- start in the west-most spot, so everyone gets the same loop
    local start = 1
    for i = 2, n do
        if pts[i].x < pts[start].x then
            start = i
        end
    end
    local order, used = { start }, { [start] = true }
    for _ = 2, n do
        local last, best, bestD = order[#order], nil, nil
        for j = 1, n do
            if not used[j] then
                local dj = d(last, j)
                if not bestD or dj < bestD then
                    best, bestD = j, dj
                end
            end
        end
        order[#order + 1], used[best] = best, true
    end
    local improved, rounds = true, 0
    while improved and rounds < 20 do
        improved, rounds = false, rounds + 1
        for i = 1, n - 2 do
            for k = i + 2, n do
                local a, b, c = order[i], order[i + 1], order[k]
                local e = order[k % n + 1]
                if e ~= a and d(a, c) + d(b, e) < d(a, b) + d(c, e) - 1e-6 then
                    -- reverse i+1 .. k
                    local lo, hi = i + 1, k
                    while lo < hi do
                        order[lo], order[hi] = order[hi], order[lo]
                        lo, hi = lo + 1, hi - 1
                    end
                    improved = true
                end
            end
        end
    end
    local out = {}
    for i, idx in ipairs(order) do
        out[i] = pts[idx]
    end
    return out
end

-- A ready-made loop is put in order only when it's needed (started, voted
-- on, copied): working out hundreds of loops up front would stall the game.
function Routes.Prepare(r)
    if r and r.unordered then
        r.pts = OrderLoop(r.pts)
        r.unordered = nil
    end
    return r
end

-- Spots closer than `cell` (part of the map) become one stop, in the middle
-- of them, keeping the first one's title. Order is kept.
local function Cluster(pts, cell)
    local buckets, out = {}, {}
    for _, p in ipairs(pts) do
        local key = p.m .. ":" .. math.floor(p.x / cell) .. ":" .. math.floor(p.y / cell)
        local b = buckets[key]
        if b then
            b.n = b.n + 1
            b.sx, b.sy = b.sx + p.x, b.sy + p.y
        else
            b = { m = p.m, t = p.t, n = 1, sx = p.x, sy = p.y }
            buckets[key] = b
            out[#out + 1] = b
        end
    end
    for i, b in ipairs(out) do
        out[i] = { m = b.m, x = b.sx / b.n, y = b.sy / b.n, t = b.t }
    end
    return out
end

-- a stable id from a route's text, so votes stay with it across versions
local function Hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 2147483647
    end
    local t = {}
    for _ = 1, 7 do
        local d = h % 36
        t[#t + 1] = ALPHA:sub(d + 1, d + 1)
        h = math.floor(h / 36)
    end
    return table.concat(t)
end

local function MyFactionLetter()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Horde" and "H") or (f == "Alliance" and "A") or nil
end

local function Make(out, id, name, cat, mode, note, pts, min, ordered)
    if #pts < (min or MIN_STOPS) then
        return
    end
    while #pts > Routes.MAX_POINTS do
        table.remove(pts)
    end
    local r = Routes.Validate({
        id = id, v = 1, name = name, cat = cat, mode = mode, note = note,
        author = Routes.SUGGESTED_AUTHOR, pts = pts,
    })
    if r then
        r.src = "suggested"
        r.unordered = (mode == "loop" and not ordered) or nil
        out[#out + 1] = r
    end
end

-- Every known spot of the gathering nodes and chests, per map; plus the
-- rare spawns of each map.
local function FromDatabase(DB, out)
    local groups, order = {}, {}
    for id, e in pairs(DB.objects) do
        local kind = e.gather or (e.chest and "treasure")
        if kind and e.name ~= "" and id > 0 then
            local name = kind == "treasure" and "" or e.name
            for _, p in ipairs(DB.Points(e)) do
                local key = kind .. "|" .. name .. "|" .. p.m
                local g = groups[key]
                if not g then
                    g = { kind = kind, name = e.name, m = p.m, minID = id, pts = {}, seen = {} }
                    groups[key] = g
                    order[#order + 1] = key
                end
                g.minID = math.min(g.minID, id)
                local spot = math.floor(p.x / SAME_SPOT) .. ":" .. math.floor(p.y / SAME_SPOT)
                if not g.seen[spot] then
                    g.seen[spot] = true
                    g.pts[#g.pts + 1] = { m = p.m, x = p.x, y = p.y, t = kind ~= "treasure" and e.name or nil }
                end
            end
        end
    end
    table.sort(order)
    for _, key in ipairs(order) do
        local g = groups[key]
        local zone = Geo.GetMapName(g.m)
        if zone then
            if g.kind == "treasure" then
                Make(out, "c-" .. g.m, L.ROUTE_SUGGESTED_CHESTS:format(zone), "treasure", "loop", L.ROUTE_SUGGESTED_NOTE, g.pts, MIN_SUGGESTED)
            elseif g.kind == "fishing" then
                Make(out, "f" .. g.minID .. "-" .. g.m, L.ROUTE_SUGGESTED_NAME:format(g.name, zone), "fishing", "loop", L.ROUTE_FISHING_NOTE, g.pts, MIN_SUGGESTED)
            else
                Make(out, "g" .. g.minID .. "-" .. g.m, L.ROUTE_SUGGESTED_NAME:format(g.name, zone), g.kind, "loop", L.ROUTE_SUGGESTED_NOTE, g.pts, MIN_SUGGESTED)
            end
        end
    end
    -- rare spawns: each one's known spots, a zone at a time
    local rares, rareMaps = {}, {}
    for id, e in pairs(DB.units) do
        if id > 0 and (e.rank == "2" or e.rank == "4") and e.name ~= "" and DB.IsEnemy(e) then
            for _, p in ipairs(Cluster(DB.Points(e), 0.03)) do
                local list = rares[p.m]
                if not list then
                    list = {}
                    rares[p.m] = list
                    rareMaps[#rareMaps + 1] = p.m
                end
                list[#list + 1] = { m = p.m, x = p.x, y = p.y, t = e.name }
            end
        end
    end
    table.sort(rareMaps)
    for _, m in ipairs(rareMaps) do
        local zone = Geo.GetMapName(m)
        if zone then
            Make(out, "r-" .. m, L.ROUTE_SUGGESTED_RARES:format(zone), "treasure", "loop", L.ROUTE_RARES_NOTE, rares[m])
        end
    end
end

-- ---------------------------------------------------------------------------
-- Hand-picked routes: "category, mode, name, note, spec" lines. The spec is
-- ";"-separated stops, resolved against the database:
--   U12,34@1413   every spawn of these NPCs on that map (nearby ones merged)
--   O56@1413      the same for objects
--   N78           that NPC (its closest spawn)
--   Q90           a quest: who gives it, its objectives, who takes it
--   P1413:52.1,30.5,Title   a spot (map percentages)
-- Names starting "(A) " or "(H) " are for that faction only.
-- ---------------------------------------------------------------------------
local seedLines

local function NearestPoint(DB, entries, faction)
    local best, bestD, first
    for _, e in ipairs(entries) do
        if not faction or e.kind ~= "npc" or DB.ForMyFaction(e) then
            for _, p in ipairs(DB.Points(e)) do
                first = first or { p = p, e = e }
                local d = Geo.GetVector(p)
                if d and (not bestD or d < bestD) then
                    best, bestD = { p = p, e = e }, d
                end
            end
        end
    end
    return best or first
end

local function Spawns(DB, tbl, ids, m, cell, pts)
    local all = {}
    for id in ids:gmatch("%d+") do
        local e = tbl[tonumber(id)]
        if e then
            for _, p in ipairs(DB.Points(e)) do
                if Geo.SameMap(p.m, m) then
                    all[#all + 1] = { m = p.m, x = p.x, y = p.y, t = e.name ~= "" and e.name or nil }
                end
            end
        end
    end
    for _, p in ipairs(Cluster(all, cell)) do
        pts[#pts + 1] = p
    end
end

local function QuestStops(DB, id, pts)
    local q = DB.quests[id]
    if not q or not DB.ForMyFaction(q) then
        return
    end
    local start = NearestPoint(DB, DB.QuestTargets(q, "start"), true)
    if start then
        pts[#pts + 1] = { m = start.p.m, x = start.p.x, y = start.p.y, t = L.ROUTE_STOP_START:format(start.e.name ~= "" and start.e.name or q.name) }
    end
    for _, e in ipairs(DB.QuestTargets(q, "objective")) do
        local own = {}
        for _, p in ipairs(DB.Points(e)) do
            own[#own + 1] = { m = p.m, x = p.x, y = p.y, t = e.name ~= "" and e.name or q.name }
        end
        own = Cluster(own, 0.03)
        for i = 1, math.min(#own, 12) do
            pts[#pts + 1] = own[i]
        end
    end
    local finish = NearestPoint(DB, DB.QuestTargets(q, "end"), true)
    if finish then
        pts[#pts + 1] = { m = finish.p.m, x = finish.p.x, y = finish.p.y, t = L.ROUTE_STOP_END:format(finish.e.name ~= "" and finish.e.name or q.name) }
    end
end

local function FromSeeds(DB, out)
    if WaypointTrackerData and type(WaypointTrackerData.routeSeeds) == "string" then
        seedLines = {}
        for line in WaypointTrackerData.routeSeeds:gmatch("[^\n]+") do
            seedLines[#seedLines + 1] = line
        end
        WaypointTrackerData.routeSeeds = nil
    end
    local letter = MyFactionLetter()
    for _, line in ipairs(seedLines or {}) do
        local cat, mode, name, note, spec = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        local only = name and name:match("^%(([AH])%) ")
        if spec and not (only and letter and only ~= letter) then
            if only then
                name = name:sub(5)
            end
            local pts = {}
            for token in spec:gmatch("[^;]+") do
                local kind, rest = token:sub(1, 1), token:sub(2)
                if kind == "U" or kind == "O" then
                    local ids, m = rest:match("^([%d,]+)@(%d+)$")
                    if ids then
                        Spawns(DB, kind == "U" and DB.units or DB.objects, ids, tonumber(m), kind == "U" and 0.03 or 0.012, pts)
                    end
                elseif kind == "N" then
                    local e = DB.units[tonumber(rest) or 0]
                    local near = e and NearestPoint(DB, { e }, true)
                    if near then
                        pts[#pts + 1] = { m = near.p.m, x = near.p.x, y = near.p.y, t = e.name }
                    end
                elseif kind == "Q" then
                    QuestStops(DB, tonumber(rest) or 0, pts)
                elseif kind == "P" then
                    local m, x, y, t = rest:match("^(%d+):([%d%.]+),([%d%.]+),(.*)$")
                    m, x, y = tonumber(m), tonumber(x), tonumber(y)
                    if m and x and y and Geo.IsValidMap(m) then
                        pts[#pts + 1] = { m = m, x = x / 100, y = y / 100, t = t }
                    end
                end
            end
            Make(out, "s-" .. Hash(name .. spec), name, cat, mode, note ~= "" and note or nil, pts, MIN_STOPS, mode ~= "loop")
        end
    end
end

local suggested -- { routes, gen, byID }

-- Every ready-made route, for every zone.
function Routes.Suggested()
    local DB = ns.DB
    if not (DB and DB.ready) then
        return {}
    end
    if suggested and suggested.gen == DB.generation then
        return suggested.routes
    end
    local out = {}
    ns.Call(FromDatabase, DB, out)
    ns.Call(FromSeeds, DB, out)
    local byID = {}
    for _, r in ipairs(out) do
        byID[r.id] = r
    end
    suggested = { gen = DB.generation, routes = out, byID = byID }
    return out
end

function Routes.GetSuggested(id)
    return suggested and suggested.byID[id]
end

-- Every route there is to browse: kept ones plus the ready-made ones.
function Routes.All()
    local st = Store()
    local out, seen = {}, {}
    for id, r in pairs(st and st.list or {}) do
        out[#out + 1] = r
        seen[id] = true
    end
    for _, r in ipairs(Routes.Suggested()) do
        if not seen[r.id] then
            out[#out + 1] = r
        end
    end
    return out
end

-- yards to its closest point, when it's on your continent
local worldOf = setmetatable({}, { __mode = "k" })
function Routes.Distance(r)
    local w = worldOf[r]
    if not w then
        w = {}
        for _, p in ipairs(r.pts) do
            local cont, wx, wy = Geo.MapToWorld(p.m, p.x, p.y)
            if cont then
                w[#w + 1] = { cont, wx, wy }
            end
        end
        worldOf[r] = w
    end
    local best, pcont, px, py
    for _, q in ipairs(w) do
        if q[1] ~= pcont then
            pcont, px, py = Geo.GetPlayerWorld(q[1])
            if pcont ~= q[1] then
                px = nil
            end
            pcont = q[1]
        end
        if px then
            local dx, dy = q[2] - px, q[3] - py
            local d = math.sqrt(dx * dx + dy * dy)
            if not best or d < best then
                best = d
            end
        end
    end
    return best
end
-- ---------------------------------------------------------------------------
-- Following a route
-- ---------------------------------------------------------------------------
local function RoutePoints(id)
    local out = {}
    for _, wp in ipairs(WP.List()) do
        if wp.routeID == id then
            out[#out + 1] = wp
        end
    end
    return out
end
Routes.RoutePoints = RoutePoints

-- the point after wp: the next one in order (round again for a loop), or
-- the closest one left for "nearest"
local function NextPoint(wp, run)
    local pts = RoutePoints(run.id)
    local best
    if run.mode == "nearest" then
        local bestD
        for _, p in ipairs(pts) do
            if p ~= wp then
                local d = Geo.GetVector(p)
                if d and (not bestD or d < bestD) then
                    best, bestD = p, d
                end
            end
        end
        return best or (pts[1] ~= wp and pts[1]) or pts[2]
    end
    local i = wp.routeIndex or 0
    local lowest
    for _, p in ipairs(pts) do
        if p ~= wp and p.routeIndex then
            if p.routeIndex > i and (not best or p.routeIndex < best.routeIndex) then
                best = p
            end
            if not lowest or p.routeIndex < lowest.routeIndex then
                lowest = p
            end
        end
    end
    return best or lowest
end

local function Feedback(r, run)
    if run.asked or (run.secs or 0) < Routes.feedbackAfter or Routes.IsMine(r) then
        return
    end
    run.asked = true
    ns.Fire("ROUTE_FEEDBACK", r.id, run.secs)
end

local function Finish(reason)
    local run = Run()
    if not run then
        return
    end
    ns.charDB.routeRun = nil
    local r = Routes.Get(run.id)
    if r then
        ns.Print(L[reason == "complete" and "ROUTE_COMPLETE" or "ROUTE_STOPPED"]:format(r.name))
        Feedback(r, run)
    end
    Changed()
end

-- Start a route. how: "replace" your waypoints, or "add" to them.
function Routes.Apply(id, how)
    local r = Routes.Prepare(Routes.Get(id))
    if not r then
        return false
    end
    local st = Store()
    if how == "replace" then
        WP.ClearAll(true) -- also ends the route you were on
    elseif Run() then
        Routes.Stop(true)
    end
    -- kept from now on, so following it survives a reload
    if st and not st.list[id] then
        st.list[id] = r
    end
    local run = { id = id, mode = r.mode, total = #r.pts, done = 0, secs = 0, lap = 0, seen = {} }
    ns.charDB.routeRun = run
    local total = #r.pts
    WP.Batch(function()
        for i, p in ipairs(r.pts) do
            local wp = WP.Add(p.m, p.x, p.y, {
                title = ("%d/%d %s"):format(i, total, p.t or r.name),
                silent = true, setActive = false, source = "route",
            })
            if wp then
                wp.routeID, wp.routeIndex = id, i
            end
        end
    end)
    -- where to begin: the first point, or the closest one for a loop or "nearest"
    local pts = RoutePoints(id)
    local first
    if r.mode == "order" then
        for _, p in ipairs(pts) do
            if not first or p.routeIndex < first.routeIndex then
                first = p
            end
        end
    else
        local bestD
        for _, p in ipairs(pts) do
            local d = Geo.GetVector(p)
            if d and (not bestD or d < bestD) then
                first, bestD = p, d
            end
        end
        first = first or pts[1]
    end
    if first then
        WP.SetActive(first, true)
        run.start = first.routeIndex
    end
    ns.Print(L.ROUTE_STARTED:format(r.name, total))
    Changed()
    return true
end

-- Start, asking first whether to replace your waypoints when you have some.
function Routes.Start(id)
    if not Routes.Get(id) then
        return false
    end
    local others = 0
    local run = Run()
    for _, wp in ipairs(WP.List()) do
        if not (run and wp.routeID == run.id) then
            others = others + 1
        end
    end
    if others == 0 then
        return Routes.Apply(id, "add")
    elseif ns.Get("routeApply") ~= "ask" then
        return Routes.Apply(id, ns.Get("routeApply") == "add" and "add" or "replace")
    end
    ns.Fire("ROUTE_ASK", id, others)
    return true
end

-- Take the route's points away (ends it; it may ask how it was).
function Routes.Stop(quiet)
    local run = Run()
    if not run then
        if not quiet then
            ns.Print(L.ROUTE_NONE, true)
        end
        return
    end
    WP.Batch(function()
        for _, wp in ipairs(RoutePoints(run.id)) do
            WP.Remove(wp, true, true)
        end
    end)
    -- nothing was left to remove: end it here
    if Run() then
        Finish("cleared")
    end
end

-- Skip the point the arrow is on.
function Routes.Skip()
    local run = Run()
    local wp = WP.GetActive()
    if not run or not wp or wp.routeID ~= run.id then
        ns.Print(L.ROUTE_NONE, true)
        return
    end
    if run.mode == "loop" then
        local nxt = NextPoint(wp, run)
        if nxt then
            WP.SetActive(nxt)
        end
    else
        WP.Remove(wp, true) -- the next point comes from WP.nextHook
    end
end

-- Arrived at one of the route's points (from WP.CheckArrival).
function Routes.Arrived(wp)
    local run = Run()
    if not run or wp.routeID ~= run.id then
        return false
    end
    local r = Routes.Get(run.id)
    if run.mode == "loop" then
        run.seen = type(run.seen) == "table" and run.seen or {}
        run.seen[wp.routeIndex or 0] = true
        local n = 0
        for _ in pairs(run.seen) do
            n = n + 1
        end
        if n >= #RoutePoints(run.id) then
            -- a whole lap
            run.lap = (run.lap or 0) + 1
            run.seen = {}
            if r then
                ns.Print(L.ROUTE_LAP:format(r.name, run.lap))
                Feedback(r, run)
            end
        end
        local nxt = NextPoint(wp, run)
        if nxt then
            WP.SetActive(nxt, true)
        end
        return true
    end
    run.done = (run.done or 0) + 1
    local nxt = NextPoint(wp, run)
    run.arriving = true -- the last point gone this way: the route is complete
    WP.Remove(wp, true, true)
    run.arriving = nil
    if nxt and WP.IsValid(nxt) then
        WP.SetActive(nxt, true)
    end
    return true
end

-- Removing the arrow's point by hand: go on to the route's next point.
WP.nextHook = function(wp)
    local run = Run()
    if run and wp.routeID == run.id then
        return NextPoint(wp, run)
    end
end

-- The route ends when none of its points are left (all done, or cleared).
ns.On("WAYPOINTS_CHANGED", function()
    local run = Run()
    if run and #RoutePoints(run.id) == 0 then
        Finish(run.arriving and "complete" or "cleared")
    end
end)

-- How long you've followed it, counting only time in the game.
local clock = CreateFrame("Frame")
clock:SetScript("OnUpdate", function(_, elapsed)
    local run = Run()
    if run then
        run.secs = (run.secs or 0) + math.min(elapsed, 1)
    end
end)

-- ---------------------------------------------------------------------------
-- Recording a route as you go: a stop where you press Add stop, and (when
-- on) wherever you gather a herb, ore or pelt, or fish. Finish turns it into
-- a route to name and share.
-- ---------------------------------------------------------------------------
local REC_MIN_YARDS = 15 -- a new stop this close to the last one is skipped
local GATHER_SPELLS = { herbs = 2366, mining = 2575, skinning = 8613, fishing = 7620 }
local gatherNames

local function SpellName(id)
    local ok, name
    if C_Spell and C_Spell.GetSpellName then
        ok, name = pcall(C_Spell.GetSpellName, id)
    elseif GetSpellInfo then
        ok, name = pcall(GetSpellInfo, id)
    end
    return ok and type(name) == "string" and name or nil
end

function Routes.Recording()
    return Routes.rec
end

function Routes.RecordStart()
    Routes.rec = { pts = {}, kinds = {}, auto = true }
    ns.Print(L.ROUTE_REC_STARTED)
    ns.Fire("ROUTE_RECORDING")
end

-- Adds a stop where you stand. kind: what you gathered (nil: by hand).
function Routes.RecordAdd(title, kind)
    local rec = Routes.rec
    if not rec then
        return false
    end
    local m, x, y = Geo.GetPlayerMapPosition()
    if not m then
        ns.Print(L.NO_POSITION, true)
        return false
    end
    local last = rec.pts[#rec.pts]
    if last and kind then
        local d = Geo.GetVector(last)
        if d and d < REC_MIN_YARDS then
            return false
        end
    end
    if #rec.pts >= Routes.MAX_POINTS then
        return false
    end
    rec.pts[#rec.pts + 1] = { m = m, x = x, y = y, t = title }
    if kind then
        rec.kinds[kind] = (rec.kinds[kind] or 0) + 1
    end
    ns.Fire("ROUTE_RECORDING")
    return true
end

function Routes.RecordSetAuto(on)
    if Routes.rec then
        Routes.rec.auto = on and true or false
    end
end

-- The draft to name and save (nil when nothing was recorded).
function Routes.RecordFinish()
    local rec = Routes.rec
    Routes.rec = nil
    ns.Fire("ROUTE_RECORDING")
    if not rec or #rec.pts == 0 then
        return nil
    end
    -- mostly gathering: a loop in that category; otherwise stops in order
    local cat, most = "other", 0
    for kind, n in pairs(rec.kinds) do
        if n > most then
            cat, most = kind, n
        end
    end
    local draft = Routes.Validate({ name = L.ROUTE_NEW_NAME, cat = cat, mode = most * 2 >= #rec.pts and "loop" or "order", pts = rec.pts }, true)
    return draft
end

function Routes.RecordCancel()
    Routes.rec = nil
    ns.Fire("ROUTE_RECORDING")
end

ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    local rec = Routes.rec
    if unit ~= "player" or not rec or not rec.auto or not spellID then
        return
    end
    if not gatherNames then
        gatherNames = {}
        for kind, id in pairs(GATHER_SPELLS) do
            local name = SpellName(id)
            if name then
                gatherNames[name] = kind
            end
        end
    end
    local name = SpellName(spellID)
    local kind = name and gatherNames[name]
    if kind then
        local title = kind == "skinning" and UnitName and UnitName("target") or Routes.CategoryLabel(kind)
        Routes.RecordAdd(title, kind)
    end
end)

function WaypointTracker_RouteRecordAdd()
    if not Routes.RecordAdd() then
        if not Routes.rec then
            ns.Print(L.ROUTE_REC_NONE, true)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------
ns.On("INIT", function()
    local st = Store()
    if not st then
        return
    end
    for id, r in pairs(st.list) do
        local ok = type(r) == "table" and Routes.Validate(r)
        if ok and ok.id == id then
            local src, public, via, fromAuthor, got = r.src, r.public, r.via, r.fromAuthor, r.got
            ok.src = (src == "mine" or src == "suggested") and src or "shared"
            ok.public = src == "mine" and public ~= false or nil
            ok.via, ok.fromAuthor, ok.got = Clean(via, 60), fromAuthor and true or nil, ns.Int(got)
            st.list[id] = ok
        else
            st.list[id] = nil
        end
    end
    for id, v in pairs(st.votes) do
        if not (Routes.ValidID(id) and type(v) == "table" and (v.v == 1 or v.v == -1)) then
            st.votes[id] = nil
        end
    end
    for id, t in pairs(st.tally) do
        if not (Routes.ValidID(id) and type(t) == "table") then
            st.tally[id] = nil
        end
    end
end)

ns.On("LOGIN", function()
    -- a route that's gone (deleted on another character) isn't followed
    local run = Run()
    if run and not Routes.Get(run.id) then
        ns.charDB.routeRun = nil
    end
end)

function WaypointTracker_RouteNext()
    Routes.Skip()
end
