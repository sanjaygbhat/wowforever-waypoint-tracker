-- Geo: player position, distances, directions, the zone list and parsing of
-- typed coordinates. Only uses map APIs that return plain numbers.
local _, ns = ...
local L = ns.L
local Num = ns.Num

local Geo = {}
ns.Geo = Geo

local sqrt, atan2, pi, floor = math.sqrt, math.atan2, math.pi, math.floor
local TWO_PI = pi * 2

-- the game's 2D point (a plain table does the same job if it's missing)
local Vector = CreateVector2D or function(x, y)
    return { x = x, y = y }
end

local MAPTYPE_CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
local MAPTYPE_ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

-- ---------------------------------------------------------------------------
-- Map helpers
-- ---------------------------------------------------------------------------
local mapInfoCache = {}
function Geo.GetMapInfo(mapID)
    if type(mapID) ~= "number" then
        return nil
    end
    local info = mapInfoCache[mapID]
    if info == nil then
        info = C_Map.GetMapInfo(mapID) or false
        mapInfoCache[mapID] = info
    end
    return info or nil
end

function Geo.GetMapName(mapID)
    local info = Geo.GetMapInfo(mapID)
    return info and info.name or ("#" .. tostring(mapID))
end

function Geo.IsValidMap(mapID)
    return Geo.GetMapInfo(mapID) ~= nil
end

-- World position (continent/instance id, x, y) of a point on a map.
-- Results are cached because map geometry never changes.
local worldCache = {}
function Geo.MapToWorld(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end
    local key = mapID .. ":" .. floor(x * 1e6) .. ":" .. floor(y * 1e6)
    local c = worldCache[key]
    if c == nil then
        c = false
        local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, Vector(x, y))
        if ok and cont and pos then
            local wx, wy = ns.XY(pos)
            wx, wy = Num(wx), Num(wy)
            if wx and wy then
                c = { cont, wx, wy }
            end
        end
        worldCache[key] = c
    end
    if c then
        return c[1], c[2], c[3]
    end
end

-- Two map IDs for the same ground: the game has a few (phased copies, and
-- WoW Forever's Zephras Isle is both 2521 and 2665).
local sameCache = {}
function Geo.SameMap(a, b)
    if a == b then
        return a ~= nil
    end
    if type(a) ~= "number" or type(b) ~= "number" then
        return false
    end
    local key = a < b and (a .. ":" .. b) or (b .. ":" .. a)
    local same = sameCache[key]
    if same == nil then
        local ca, ax0, ay0 = Geo.MapToWorld(a, 0, 0)
        local cb, bx0, by0 = Geo.MapToWorld(b, 0, 0)
        local _, ax1, ay1 = Geo.MapToWorld(a, 1, 1)
        local _, bx1, by1 = Geo.MapToWorld(b, 1, 1)
        same = ca ~= nil and ca == cb and ax1 ~= nil and bx1 ~= nil
            and math.abs(ax0 - bx0) < 1 and math.abs(ay0 - by0) < 1
            and math.abs(ax1 - bx1) < 1 and math.abs(ay1 - by1) < 1
        sameCache[key] = same
    end
    return same
end

-- Position of a world point on a given map (may be outside 0..1).
function Geo.WorldToMap(cont, wx, wy, mapID)
    local ok, resultMap, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, Vector(wx, wy), mapID)
    if ok and resultMap and pos then
        local x, y = ns.XY(pos)
        x, y = Num(x), Num(y)
        -- both or nothing: a half-filled spot can't be compared or drawn
        if x and y then
            return x, y, resultMap
        end
    end
end

-- Position of a map point translated onto another map (for showing pins on
-- continent maps). Returns nil when it isn't on that map.
function Geo.TranslateToMap(fromMap, x, y, toMap)
    if fromMap == toMap then
        return x, y
    end
    local cont, wx, wy = Geo.MapToWorld(fromMap, x, y)
    if not cont then
        return nil
    end
    -- the target map must be on the same continent
    local tcont = Geo.MapToWorld(toMap, 0.5, 0.5)
    if tcont ~= cont then
        return nil
    end
    local mx, my = Geo.WorldToMap(cont, wx, wy, toMap)
    if mx and my and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
        return mx, my
    end
end

-- If a point was picked on a continent/world map, turn it into a zone point
-- so it reads nicely ("Elwynn Forest 42, 65").
function Geo.NormalizeToZone(mapID, x, y)
    local info = Geo.GetMapInfo(mapID)
    if not info or (info.mapType or MAPTYPE_ZONE) >= MAPTYPE_ZONE then
        return mapID, x, y
    end
    local ok, sub = pcall(C_Map.GetMapInfoAtPosition, mapID, x, y)
    if not ok or not sub or not sub.mapID or sub.mapID == mapID then
        return mapID, x, y
    end
    if (sub.mapType or 0) < MAPTYPE_ZONE then
        return mapID, x, y
    end
    local cont, wx, wy = Geo.MapToWorld(mapID, x, y)
    if not cont then
        return mapID, x, y
    end
    local zx, zy = Geo.WorldToMap(cont, wx, wy, sub.mapID)
    if zx and zy and zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 then
        return sub.mapID, zx, zy
    end
    return mapID, x, y
end

-- ---------------------------------------------------------------------------
-- Player position
-- ---------------------------------------------------------------------------
function Geo.GetPlayerMapPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        return nil
    end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then
        return nil
    end
    local x, y = ns.XY(pos)
    x, y = Num(x), Num(y)
    if not x or not y or (x == 0 and y == 0) then
        return nil
    end
    return mapID, x, y
end

-- Player world position via the map (works everywhere the map shows you).
local function PlayerWorldFromMap()
    local mapID, x, y = Geo.GetPlayerMapPosition()
    if not mapID then
        return nil
    end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, Vector(x, y))
    if ok and cont and pos then
        local wx, wy = ns.XY(pos)
        wx, wy = Num(wx), Num(wy)
        if wx and wy then
            return cont, wx, wy
        end
    end
end

-- Returns cont, wx, wy for the player. `wantCont` lets us fall back to the
-- map-based position when UnitPosition reports a different instance id
-- (phased copies of a continent can do that).
-- (the answer is cached for the current frame: the Find window may ask for
-- hundreds of distances at once)
local posCacheTime, posCacheCont, posCache = nil, nil, nil
local GetPlayerWorldUncached

function Geo.GetPlayerWorld(wantCont)
    local now = GetTime()
    if posCacheTime == now and posCacheCont == wantCont and posCache then
        return posCache[1], posCache[2], posCache[3]
    end
    local c, x, y = GetPlayerWorldUncached(wantCont)
    posCacheTime, posCacheCont = now, wantCont
    posCache = c and { c, x, y } or nil
    return c, x, y
end

GetPlayerWorldUncached = function(wantCont)
    local a, b, _, inst = UnitPosition("player")
    a, b, inst = Num(a), Num(b), Num(inst)
    if a and b and inst and (not wantCont or inst == wantCont) then
        return inst, a, b
    end
    local cont, wx, wy = PlayerWorldFromMap()
    if cont then
        return cont, wx, wy
    end
    if a and b and inst then
        return inst, a, b
    end
end

function Geo.GetFacing()
    return Num(GetPlayerFacing())
end

-- Distance (yards) and absolute bearing (radians, counter-clockwise from
-- north, the same convention as GetPlayerFacing) from the player to a
-- waypoint. Returns nil, reason when it can't be worked out.
function Geo.GetVector(wp)
    local cont, wx, wy = Geo.MapToWorld(wp.m, wp.x, wp.y)
    if not cont then
        return nil, "nomap"
    end
    local pcont, px, py = Geo.GetPlayerWorld(cont)
    if not pcont then
        return nil, "noplayer"
    end
    if pcont ~= cont then
        return nil, "continent"
    end
    -- world x grows to the north, world y grows to the west
    local dNorth, dWest = wx - px, wy - py
    local dist = sqrt(dNorth * dNorth + dWest * dWest)
    local bearing = atan2(dWest, dNorth)
    return dist, bearing, dNorth, dWest
end

-- Angle the arrow should turn, 0..2pi counter-clockwise (0 = straight ahead).
function Geo.RelativeAngle(bearing, facing)
    local a = (bearing - facing) % TWO_PI
    if a < 0 then
        a = a + TWO_PI
    end
    return a
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------
function Geo.FormatDistance(yards)
    if not yards then
        return ""
    end
    if ns.Get("useMetres") then
        local m = yards * 0.9144
        if m >= 1000 then
            return L.DISTANCE_KM:format(m / 1000)
        end
        return L.DISTANCE_METRES:format(floor(m + 0.5))
    end
    return L.DISTANCE_YARDS:format(floor(yards + 0.5))
end

function Geo.FormatTime(seconds)
    seconds = floor(seconds + 0.5)
    if seconds >= 3600 then
        return ("%d:%02d:%02d"):format(floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60)
    end
    return ("%d:%02d"):format(floor(seconds / 60), seconds % 60)
end

function Geo.FormatCoords(x, y)
    return ("%.1f, %.1f"):format(x * 100, y * 100)
end

-- ---------------------------------------------------------------------------
-- Zone list (built from the game's own map data, so it is always correct
-- for WoW Forever and already translated into the player's language)
-- ---------------------------------------------------------------------------
local zoneList

-- Lower-case ASCII, accented Latin (Ä, É, ...) and Cyrillic letters so
-- searching works the same in every client language.
local function Lower(s)
    s = s:lower()
    s = s:gsub("\195([\128-\158])", function(c)
        local b = c:byte()
        if b == 151 then
            return "\195" .. c
        end
        return "\195" .. string.char(b + 32)
    end)
    s = s:gsub("\208([\144-\175])", function(c)
        local b = c:byte()
        if b < 160 then
            return "\208" .. string.char(b + 32)
        end
        return "\209" .. string.char(b - 32)
    end)
    s = s:gsub("\208\129", "\209\145")
    return s
end
Geo.Lower = Lower

local function Squash(s)
    s = Lower(tostring(s or ""))
    -- drop spaces and common punctuation so "elwynnforest" and "Elwynn Forest" match
    s = s:gsub("[%s%p]", "")
    return s
end
Geo.Squash = Squash

local MAPTYPE_MICRO = (Enum and Enum.UIMapType and Enum.UIMapType.Micro) or 5
local MAPTYPE_ORPHAN = (Enum and Enum.UIMapType and Enum.UIMapType.Orphan) or 6

-- Every kind of map that has its own coordinates you can walk around in:
-- zones and cities, plus smaller areas with their own map (caves, towns).
local PICKABLE = { [MAPTYPE_ZONE] = true, [MAPTYPE_MICRO] = true, [MAPTYPE_ORPHAN] = true }

-- How far the scan of map IDs goes. The game's IDs are well below this.
local MAX_MAP_ID = 12000

local function ParentOfType(mapID, wanted)
    local info = Geo.GetMapInfo(mapID)
    local guard = 0
    info = info and info.parentMapID and Geo.GetMapInfo(info.parentMapID)
    while info and guard < 12 do
        if wanted[info.mapType] then
            return info
        end
        if not info.parentMapID or info.parentMapID == 0 then
            break
        end
        info = Geo.GetMapInfo(info.parentMapID)
        guard = guard + 1
    end
end

local function ContinentOf(mapID)
    local info = Geo.GetMapInfo(mapID)
    if info and info.mapType == MAPTYPE_CONTINENT then
        return info.name
    end
    local c = ParentOfType(mapID, { [MAPTYPE_CONTINENT] = true })
    return c and c.name or ""
end
Geo.ContinentOf = ContinentOf

local function MakeEntry(info)
    local entry = {
        id = info.mapID,
        name = info.name,
        continent = ContinentOf(info.mapID),
        key = Squash(info.name),
        words = {},
        mapType = info.mapType,
    }
    -- small maps show the zone they belong to ("Deathknell - Tirisfal Glades")
    if info.mapType ~= MAPTYPE_ZONE then
        local parent = ParentOfType(info.mapID, { [MAPTYPE_ZONE] = true })
        entry.parent = parent and parent.name
    end
    for word in Lower(info.name):gmatch("[^%s%-]+") do
        entry.words[#entry.words + 1] = word:gsub("%p", "")
    end
    return entry
end

-- All maps a player can put a waypoint on, straight from the game's own map
-- data (so it is right for WoW Forever and already in the client's
-- language). We look at every map ID the client knows instead of only
-- following the map tree, so nothing is missed.
function Geo.GetZoneList()
    if zoneList and #zoneList > 0 then
        return zoneList
    end
    local candidates = {}
    local function consider(info)
        if not info or not info.mapID or candidates[info.mapID] ~= nil then
            return
        end
        local ok = PICKABLE[info.mapType] and info.name and info.name ~= "" and Geo.MapToWorld(info.mapID, 0.5, 0.5) ~= nil
        candidates[info.mapID] = ok and info or false
    end

    for id = 1, MAX_MAP_ID do
        local info = C_Map.GetMapInfo(id)
        if info then
            mapInfoCache[id] = info
            consider(info)
        end
    end
    -- anything the scan couldn't reach (very high IDs) through the map tree
    local ok, fallback = pcall(C_Map.GetFallbackWorldMapID)
    local current = C_Map.GetBestMapForUnit("player")
    for _, root in ipairs({ ok and fallback or nil, current }) do
        if root then
            local top = Geo.GetMapInfo(root)
            local guard = 0
            while top and top.parentMapID and top.parentMapID ~= 0 and guard < 12 do
                top = Geo.GetMapInfo(top.parentMapID) or top
                guard = guard + 1
                if not top.parentMapID then
                    break
                end
            end
            if top then
                local okc, children = pcall(C_Map.GetMapChildrenInfo, top.mapID, nil, true)
                if okc and type(children) == "table" then
                    for _, info in ipairs(children) do
                        consider(info)
                    end
                end
            end
        end
    end
    -- the map you're standing on is always pickable (even inside a dungeon)
    if current then
        local info = Geo.GetMapInfo(current)
        if info and info.name and Geo.MapToWorld(current, 0.5, 0.5) then
            candidates[current] = info
        end
    end

    -- Some maps exist more than once (phased copies). Keep one per name and
    -- continent: the one you're on, else the one that sits on a continent.
    local byName = {}
    for id, info in pairs(candidates) do
        if info then
            local entry = MakeEntry(info)
            local groupKey = entry.key .. "|" .. entry.continent .. "|" .. (entry.parent or "")
            local have = byName[groupKey]
            local function rank(e)
                if e.id == current then
                    return 0
                end
                local i = Geo.GetMapInfo(e.id)
                local p = i and i.parentMapID and Geo.GetMapInfo(i.parentMapID)
                if p and p.mapType == MAPTYPE_CONTINENT then
                    return 1
                end
                return 2
            end
            if not have or rank(entry) < rank(have) or (rank(entry) == rank(have) and entry.id < have.id) then
                byName[groupKey] = entry
            end
        end
    end
    local list = {}
    for _, entry in pairs(byName) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        if a.name == b.name then
            return a.id < b.id
        end
        return a.name < b.name
    end)
    zoneList = list
    return list
end

-- Text under a zone's name in the picker.
function Geo.ZoneSubtitle(z)
    if z.parent and z.parent ~= z.name then
        return z.parent
    end
    return z.continent or ""
end

-- Typo-tolerant distance between two short strings (with swapped letters
-- counting as one mistake, so "trisifal" is close to "tirisfal").
-- The three rows are reused between calls: search runs this thousands of
-- times per keystroke, so it must not create garbage.
local rowA, rowB, rowC = {}, {}, {}
local min = math.min

-- Letters to change, add, remove or swap to turn a into b. With a limit,
-- it gives up (returning limit + 1) as soon as the answer must be larger.
local function EditDistance(a, b, limit)
    local la, lb = #a, #b
    if la == 0 then
        return lb
    end
    if lb == 0 then
        return la
    end
    limit = limit or math.huge
    if math.abs(la - lb) > limit then
        return limit + 1
    end
    local prev2, prev, cur = rowA, rowB, rowC
    for j = 0, lb do
        prev[j] = j
    end
    for i = 1, la do
        cur[0] = i
        local rowMin = i
        local ca = a:byte(i)
        for j = 1, lb do
            local cb = b:byte(j)
            local cost = (ca == cb) and 0 or 1
            local v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            if i > 1 and j > 1 and ca == b:byte(j - 1) and a:byte(i - 1) == cb then
                v = min(v, prev2[j - 2] + 1)
            end
            cur[j] = v
            if v < rowMin then
                rowMin = v
            end
        end
        if rowMin > limit then
            return limit + 1
        end
        prev2, prev, cur = prev, cur, prev2
    end
    return prev[lb]
end
Geo.EditDistance = EditDistance

-- How well a zone matches what was typed. Lower is better, nil = no match.
local function MatchScore(z, q, qWords)
    if q == "" then
        return 5
    end
    if z.key == q then
        return 0
    end
    if z.key:sub(1, #q) == q then
        return 1
    end
    -- every typed word starts a word of the name ("west plague")
    if #qWords > 0 then
        local all = true
        for _, qw in ipairs(qWords) do
            local found = false
            for _, w in ipairs(z.words) do
                if w:sub(1, #qw) == qw then
                    found = true
                    break
                end
            end
            if not found then
                all = false
                break
            end
        end
        if all then
            return 2
        end
    end
    if z.key:find(q, 1, true) then
        return 3
    end
    -- typos: compare with the start of the name, allowing about one mistake
    -- per four letters
    if #q >= 3 then
        local allowed = math.max(1, math.floor(#q / 4))
        -- compare with the start of the name (and of each word), allowing
        -- for one letter too many or too few
        local function best(target)
            -- too short to be the word with a typo or two
            if #target < #q - allowed - 1 then
                return allowed + 1
            end
            return math.min(
                EditDistance(q, target:sub(1, #q), allowed),
                EditDistance(q, target:sub(1, #q + 1), allowed),
                EditDistance(q, target:sub(1, #q - 1), allowed)
            )
        end
        local d = best(z.key)
        for _, w in ipairs(z.words) do
            if d == 0 then
                break
            end
            d = math.min(d, best(w))
        end
        if d <= allowed then
            return 10 + d
        end
    end
end

-- Search zones by (part of) their name. Best matches first. The second
-- result says whether the matches are only typo guesses.
function Geo.PrepareQuery(text)
    local q = Squash(text)
    local qWords = {}
    for word in Lower(tostring(text or "")):gmatch("[^%s%-]+") do
        word = word:gsub("%p", "")
        if word ~= "" then
            qWords[#qWords + 1] = word
        end
    end
    return q, qWords
end

-- Search helpers for other kinds of entries (quests, flight masters...).
-- An entry needs .key (Squash(name)) and .words (see Geo.Words).
Geo.MatchScore = MatchScore

function Geo.Words(name)
    local words = {}
    for word in Lower(tostring(name or "")):gmatch("[^%s%-]+") do
        words[#words + 1] = (word:gsub("%p", ""))
    end
    return words
end

function Geo.SearchZones(text, limit)
    local list = Geo.GetZoneList()
    local q, qWords = Geo.PrepareQuery(text)
    local scored = {}
    for _, z in ipairs(list) do
        local score = MatchScore(z, q, qWords)
        if score then
            scored[#scored + 1] = { z = z, s = score }
        end
    end
    table.sort(scored, function(a, b)
        if a.s ~= b.s then
            return a.s < b.s
        end
        -- zones before the small maps inside them
        if (a.z.mapType == MAPTYPE_ZONE) ~= (b.z.mapType == MAPTYPE_ZONE) then
            return a.z.mapType == MAPTYPE_ZONE
        end
        return a.z.name < b.z.name
    end)
    local results = {}
    local onlyGuesses = #scored > 0
    for i = 1, #scored do
        if limit and #results >= limit then
            break
        end
        scored[i].z.score = scored[i].s
        results[#results + 1] = scored[i].z
        if scored[i].s < 10 then
            onlyGuesses = false
        end
    end
    return results, onlyGuesses and q ~= ""
end

-- Pick the best zone for a typed name; prefers your own continent when two
-- zones share a name. Returns mapID (plus true when it was a typo guess),
-- or nil plus a few suggestions.
function Geo.FindZone(text)
    local results, guessed = Geo.SearchZones(text)
    if #results == 0 then
        return nil, {}
    end
    local q = Squash(text)
    local current = C_Map.GetBestMapForUnit("player")
    local myCont = current and ContinentOf(current)

    local exact, prefix = {}, {}
    for _, z in ipairs(results) do
        if z.key == q then
            exact[#exact + 1] = z
        elseif z.key:sub(1, #q) == q then
            prefix[#prefix + 1] = z
        end
    end

    local function pick(t)
        for _, z in ipairs(t) do
            if z.id == current then
                return z
            end
        end
        for _, z in ipairs(t) do
            if z.continent == myCont and z.mapType == MAPTYPE_ZONE then
                return z
            end
        end
        for _, z in ipairs(t) do
            if z.continent == myCont then
                return z
            end
        end
        return t[1]
    end

    local function sameName(t)
        for i = 2, #t do
            if t[i].name ~= t[1].name then
                return false
            end
        end
        return #t > 0
    end

    local best
    if #exact > 0 then
        best = pick(exact)
    elseif sameName(prefix) then
        best = pick(prefix)
    elseif #prefix == 0 and sameName(results) then
        best = pick(results)
    end
    if best then
        return best.id, guessed
    end

    local names, seenName = {}, {}
    for _, z in ipairs(#prefix > 0 and prefix or results) do
        if not seenName[z.name] then
            seenName[z.name] = true
            names[#names + 1] = z.name
            if #names >= 5 then
                break
            end
        end
    end
    return nil, names
end

-- ---------------------------------------------------------------------------
-- Coordinate parsing: understands "45.2 67.8", "45.2, 67.8", "45,2 67,8"
-- (European decimals) and "45,67".
-- ---------------------------------------------------------------------------
function Geo.ParseNumber(s)
    if type(s) == "number" then
        return s
    end
    s = ns.Trim(s):gsub(",", ".")
    if not s:match("^%-?%d*%.?%d+$") and not s:match("^%-?%d+%.?$") then
        return nil
    end
    return tonumber(s)
end

local function IsCoord(n)
    return n and n >= 0 and n <= 100
end

-- Splits a message into zone text, x, y (0..100) and the rest (name).
function Geo.ParseWayArgs(msg)
    msg = ns.Trim(msg)
    local tokens = {}
    for tok in msg:gmatch("%S+") do
        tokens[#tokens + 1] = tok
    end
    -- "45,67" or "45.2,67.8" as one token: split it
    local expanded = {}
    for _, tok in ipairs(tokens) do
        local a, b = tok:match("^(%d+%.?%d*),(%d+%.?%d*),?$")
        local isPairWithDots = a and (a:find("%.") or b:find("%."))
        local isIntPair = a and not a:find("%.") and not b:find("%.") and #tokens == 1
        if a and (isPairWithDots or isIntPair) then
            expanded[#expanded + 1] = a
            expanded[#expanded + 1] = b
        else
            -- "45.2," -> "45.2"
            expanded[#expanded + 1] = (tok:gsub(",$", ""))
        end
    end
    tokens = expanded

    for i = 1, #tokens - 1 do
        local x = Geo.ParseNumber(tokens[i])
        local y = Geo.ParseNumber(tokens[i + 1])
        if IsCoord(x) and IsCoord(y) then
            local zone = table.concat(tokens, " ", 1, i - 1)
            local rest = table.concat(tokens, " ", i + 2)
            return ns.Trim(zone), x, y, ns.Trim(rest)
        end
    end
    return nil
end
