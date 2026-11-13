-- Treasure hunt: notices chests, rare spawns and other things the game
-- marks around you, pings you the moment one appears, points the arrow at
-- it, and lets it go once it's taken, killed or gone.
--
-- Where it looks:
--   * the game's minimap markers (vignettes) for treasure, rares and events:
--     exact positions, and they disappear when taken
--   * nameplates, your target and what you point at: rare and rare elite
--     enemies, placed at a nearby known spawn or where you first saw them
--   * the chest in front of you (the soft-interact target)
--   * if you like, known chest and rare spawn spots in this zone, nearest first
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP
local Plain = ns.Plain

local Treasure = {}
ns.Treasure = Treasure

-- The world's lootable chests, by their English names (the database has
-- every object's English name, so this works in every client language).
local CHEST_NAMES = {}
for _, name in ipairs({
    "Battered Chest", "Solid Chest", "Large Solid Chest", "Large Battered Chest",
    "Large Iron Bound Chest", "Large Mithril Bound Chest", "Worn Wooden Chest",
    "Worn Chest", "Ornate Chest", "Ancient Chest", "Damaged Chest", "Sunken Chest",
    "Waterlogged Chest", "Locked Chest", "Small Lockbox", "Strange Lockbox",
    "Battered Footlocker", "Dented Footlocker", "Mossy Footlocker", "Old Footlocker",
    "Scarlet Footlocker", "Waterlogged Footlocker", "Buccaneer's Strongbox",
    "Alliance Strongbox", "Venture Co. Strongbox", "Defias Strongbox",
}) do
    CHEST_NAMES[name] = true
end

function Treasure.IsChestName(name)
    name = ns.Str(name)
    return name and CHEST_NAMES[name] == true or false
end

local SCAN_EVERY = 1 -- seconds between looks around
local SPOTS_EVERY = 5 -- seconds between picking a known chest spot
local RARE_MEMORY = 120 -- a rare seen only on nameplates is let go this long after it was last seen
local HERE_MEMORY = 60 -- a chest in front of you
local DONE_MEMORY = 600 -- something taken or killed isn't announced again for this long
local VISIT_DIST = 15 -- yards: close enough to have checked a known spot
local ALERT_GAP = 1.5 -- seconds: at most one ping this often
local NEAR_SPAWN = 200 -- yards: a rare's known spawn this close is where it is

local RARE_CLASS = { rare = true, rareelite = true, worldboss = true }

local targets = {} -- key (GUID, or "spot") -> { kind, name, m, x, y, wp, seen, vig, here, dismissed }
local done = {} -- key -> when it was taken, killed or let go
local friendly = {} -- GUID -> true: an NPC you can't attack (your own side's rares and bosses)
local visited = {} -- known spot -> when you checked it
local lastAlert = -100
local history = {} -- validated per-character finds, newest first
local logLoaded = false
local focusEnabled = false
local HISTORY_SIZE = 50
local spotIndex, indexGeneration
local empty = {}
local scanMap
local quiet = false -- UI setting changes never print alerts
local scanSerial = 0
-- Bound raw bytes before CleanText's patterns (malformed links can otherwise
-- take quadratic time). All names enter live/log/index state through here.
local function Name(raw, old)
    raw = ns.Str(raw)
    if not raw then return end
    if old and old.name == raw then return raw end
    if #raw > 128 then
        raw = raw:sub(1, 128):gsub("[\192-\255][\128-\191]*$", "")
    end
    return ns.CleanText(raw, 60)
end
local function GUID(raw)
    raw = ns.Str(raw)
    return raw and #raw <= 160 and raw ~= "" and raw or nil
end
Treasure.Name = Name

local function Now()
    return GetTime and ns.Num(GetTime()) or 0
end

local function On()
    return ns.Get("treasureHunt")
end

local function Dead()
    if UnitIsDeadOrGhost then return Plain(UnitIsDeadOrGhost("player")) end
    return (UnitIsDead and Plain(UnitIsDead("player"))) or (UnitIsGhost and Plain(UnitIsGhost("player")))
end

local WANTED = { chest = "treasureChests", rare = "treasureRares", other = "treasureOther", spot = "treasureKnownSpots", spawn = "treasureKnownRares" }
local function Wanted(kind)
    return On() and ns.Get(WANTED[kind] or "treasureOther")
end

local LABEL = { chest = "TREASURE_KIND_CHEST", rare = "TREASURE_KIND_RARE", other = "TREASURE_KIND_OTHER", spot = "TREASURE_KIND_SPOT", spawn = "TREASURE_KIND_SPAWN" }
local function Label(t)
    return L[LABEL[t and t.kind] or "TREASURE_KIND_OTHER"] or "?"
end
Treasure.Label = Label
local function Known(t) return t.kind == "spot" or t.kind == "spawn" end
local function Title(t) return L.TREASURE_TITLE:format(Label(t), Name(t and t.name) or "?") end
local function Map()
    return C_Map and C_Map.GetBestMapForUnit and ns.Int(ns.Num(C_Map.GetBestMapForUnit("player")))
end
local function Position(m, x, y)
    m, x, y = ns.Int(ns.Num(m)), ns.Num(x), ns.Num(y)
    if m and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (x > 0 or y > 0) then return m, x, y end
end
local function Timestamp(value)
    value = ns.Num(value)
    return value and value >= 0 and value < 1e12 and math.floor(value) or nil
end
local function Stamp()
    local stamp = GetServerTime and ns.Num(GetServerTime())
    if not stamp then stamp = time and ns.Num(time()) end
    return Timestamp(stamp) or 0
end
Treasure.Time = Stamp
local function Identity(guid)
    if ns.Learn and ns.Learn.ParseGUID then
        local kind, id = ns.Learn.ParseGUID(GUID(guid))
        return ns.Int(ns.Num(id)), kind
    end
end

-- SavedVariables are untrusted. Copy only a bounded, plain whitelist on demand;
-- runtime code reads this private validated list, never the raw saved records.
function Treasure.LoadLog()
    history, logLoaded = {}, true
    local raw = ns.charDB and Plain(ns.charDB.treasureLog)
    if type(raw) == "table" and getmetatable(raw) == nil then
        for i = 1, HISTORY_SIZE do
            local h = Plain(rawget(raw, i))
            if type(h) == "table" and getmetatable(h) == nil then
                local kind, at = ns.Str(h.kind), ns.Num(h.at)
                local name = Name(h.name)
                if (kind == "rare" or kind == "chest" or kind == "other") and name and at and at >= 0 and at < 1e12 then
                    local m, x, y = Position(h.m, h.x, h.y)
                    local outcome, via = ns.Str(h.outcome), ns.Str(h.via)
                    history[#history + 1] = { at = math.floor(at), kind = kind, name = name, loadOrder = i,
                        m = m or ns.Int(ns.Num(h.m)), x = x, y = y, id = ns.Int(ns.Num(h.id)), lastSeen = Timestamp(h.lastSeen),
                        outcome = (outcome == "looted" or outcome == "killed" or outcome == "gone") and outcome or nil,
                        via = (via == "marker" or via == "unit" or via == "front") and via or nil }
                end
            end
        end
    end
    table.sort(history, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.loadOrder < b.loadOrder
    end)
    for _, h in ipairs(history) do h.loadOrder = nil end
    if ns.charDB then ns.charDB.treasureLog = history end
end
ns.On("INIT", function()
    history, logLoaded = {}, false
    focusEnabled = ns.Get("treasureFocus") and true or false
    if On() then Treasure.LoadLog() end
end)
local function EnsureLog()
    if not logLoaded then Treasure.LoadLog() end
end
function Treasure.Recent() EnsureLog(); return history end
function Treasure.LastSeen(id)
    id = ns.Int(ns.Num(id))
    if not id then return end
    EnsureLog()
    local latest
    for _, h in ipairs(history) do
        if h.kind == "rare" and h.id == id then
            local at = h.lastSeen or h.at
            if not latest or at > latest then latest = at end
        end
    end
    return latest
end

local function Log(t, via, at)
    local h = { at = at, kind = t.kind, name = t.name, m = t.m, x = t.x, y = t.y, id = t.id, via = via }
    table.insert(history, 1, h)
    history[HISTORY_SIZE + 1] = nil
    t.log = h
    if ns.charDB then ns.charDB.treasureLog = history end
end

-- ---------------------------------------------------------------------------
-- Pinging you
-- ---------------------------------------------------------------------------
local function Alert(t)
    if quiet or Known(t) or not ns.Get("treasurePing") then
        return
    end
    local dist
    if t.m then
        local ok, value = pcall(Geo.GetVector, t)
        if ok then dist = ns.Num(value) end
    end
    local text
    if dist then
        text = L.TREASURE_FOUND_DIST:format(Label(t), t.name or "?", Geo.FormatDistance(dist))
    else
        text = L.TREASURE_FOUND:format(Label(t), t.name or "?")
    end
    if t.class then
        local class = L[({ rare = "TREASURE_CLASS_RARE", rareelite = "TREASURE_CLASS_ELITE", worldboss = "TREASURE_CLASS_BOSS" })[t.class]]
        text = text .. " - " .. class
        if t.level then text = text .. " " .. L.TREASURE_LEVEL:format(t.level == -1 and "??" or tostring(t.level)) end
    end
    if t.near then text = text .. " - " .. L.TREASURE_SEEN_NEAR end
    ns.Print(text, true)
    local now = Now()
    if now - lastAlert < ALERT_GAP then
        return
    end
    lastAlert = now
    if PlaySound then
        PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, (ChatTypeInfo and ChatTypeInfo.RAID_WARNING) or { r = 1, g = 0.82, b = 0 })
    end
    -- in another window? the taskbar blinks
    if FlashClientIcon then
        pcall(FlashClientIcon)
    end
end

-- ---------------------------------------------------------------------------
-- Waypoints
-- ---------------------------------------------------------------------------
local function Place(t)
    if t.dismissed or Dead() or not (t.m and t.x and t.y) then
        return
    end
    if t.wp then
        if WP.IsValid(t.wp) then
            if t.wp.m ~= t.m or math.abs(t.wp.x - t.x) > 0.001 or math.abs(t.wp.y - t.y) > 0.001 then
                if not WP.Move(t.wp, t.m, t.x, t.y) then return false end
            end
            if t.wpName ~= t.name then
                t.wpName = t.name
                local title = Title(t)
                if t.wp.title ~= title then
                    t.wp.title = title
                    ns.Fire("WAYPOINTS_CHANGED")
                end
            end
            return
        end
        -- you arrived, or removed it yourself: leave it be
        t.wp, t.dismissed = nil, true
        return
    end
    t.wp = WP.Add(t.m, t.x, t.y, {
        title = Title(t),
        persistent = false,
        silent = true,
        source = "treasure",
        noReuse = true, -- separate GUIDs must never share waypoint lifetime
        -- while you're dead the arrow stays on your body
        setActive = ns.Get("treasureFocus") and true or false,
    })
    if t.wp then t.wpName = t.name; return true end
    return false -- unavailable map metadata: retry discovery, without logging it
end

local function Forget(key, silent, outcome)
    local t = targets[key]
    if not t then
        return
    end
    if t.wp and WP.IsValid(t.wp) then
        pcall(WP.Remove, t.wp, true)
        if WP.IsValid(t.wp) then return end
    end
    targets[key] = nil
    if t.log and outcome then t.log.outcome = outcome end
    if not silent and not quiet and not Known(t) and t.announced and ns.Get("chatMessages") then
        pcall(ns.Print, L.TREASURE_GONE:format(t.name or "?"))
    end
    return true
end

-- Something was taken or killed: let it go and don't announce it again.
local function Done(key, outcome, silent)
    local now = Now()
    if not targets[key] or Forget(key, silent, outcome) then done[key] = done[key] or now end
end
function Treasure.Ignore(t)
    if not (t and t.key and targets[t.key] == t) then return end
    if Known(t) then
        local now = Now()
        if Forget(t.key, true) and t.visitKey then visited[t.visitKey] = now end
    else
        Done(t.key, nil, true)
    end
end
function Treasure.Point(t)
    if not t or not Position(t.m, t.x, t.y) then return end
    if t.wp and WP.IsValid(t.wp) then WP.SetActive(t.wp, true); return t.wp end
    local wp = WP.Add(t.m, t.x, t.y, { title = Title(t), silent = true,
        persistent = not t.key, noReuse = true, source = t.key and "treasure" or "user" })
    if t.key then t.wp, t.dismissed = wp, nil end
    return wp
end
function Treasure.SetOption(key, value)
    local wasQuiet = quiet
    quiet = true
    local ok, err = pcall(ns.Set, key, value)
    quiet = wasQuiet
    if not ok then error(err) end
end

-- Seen (again): remember it, ping the first time, and keep its waypoint
-- where it is. via says how it was found ("marker", "unit", "front").
local function Seen(key, kind, name, m, x, y, via, class, level, near)
    key = GUID(key)
    name = Name(name, key and targets[key])
    m, x, y = Position(m, x, y)
    if not key then return end
    local now = Now()
    if done[key] and now - done[key] < DONE_MEMORY then
        return
    end
    if not Wanted(kind) then
        return
    end
    local old = targets[key]
    local t = old
    local changed = not old or (name and name ~= old.name and (name ~= "?" or old.name == "?"))
        or (m and (m ~= old.m or x ~= old.x or y ~= old.y)) or (via == "marker" and m and old.near)
    if changed then
        -- Stage changing fields. A failed placement must preserve the old live
        -- record and log; first discoveries are committed only after placement.
        t = {}
        if old then for k, v in pairs(old) do t[k] = v end
        else
            t.key, t.kind, t.name, t.id = key, kind, name or "?", Identity(key)
            t.class, t.level, t.near = class, level, near
            t.announced = not Known(t)
            if not Known(t) then EnsureLog() end
        end
        if name and (name ~= "?" or t.name == "?") then t.name = name end
        if m then t.m, t.x, t.y = m, x, y end
        if via == "marker" and m then t.near = nil end
    end
    local stamp = not Known(t) and Stamp()
    local ok, placed = pcall(Place, t)
    if not ok or placed == false then return old end
    t.seen = now
    if not old and not Known(t) then Log(t, via, stamp) end
    if old and changed then
        -- Retain target identity for tab rows and outside references.
        for k, v in pairs(t) do old[k] = v end
        old.near, old.wp = t.near, t.wp
        t = old
    end
    targets[key] = t
    if t.log then
        t.log.name = t.name
        t.log.m, t.log.x, t.log.y = t.m, t.x, t.y
        t.log.lastSeen = stamp
    end
    -- Optional presentation can fail without interrupting discovery or later
    -- targets. All live state, history and waypoint state are complete here.
    if not old then pcall(Alert, t) end
    return t
end

-- ---------------------------------------------------------------------------
-- The game's minimap markers
-- ---------------------------------------------------------------------------
local function VignetteKind(info)
    local atlas = ns.Str(info.atlasName)
    atlas = atlas and atlas:sub(1, 128):lower() or ""
    if atlas:find("loot", 1, true) or atlas:find("treasure", 1, true) or atlas:find("chest", 1, true) then
        return "chest"
    end
    if atlas:find("kill", 1, true) or atlas:find("rare", 1, true) then
        return "rare"
    end
    local obj = GUID(info.objectGUID)
    if type(obj) == "string" then
        if obj:find("^GameObject") then
            return "chest"
        elseif obj:find("^Creature") or obj:find("^Vehicle") then
            return "rare"
        end
    end
    return "other"
end

-- An NPC the database knows is on your side (or never hostile): not yours to hunt.
local function FriendlyNPC(guid)
    local DB = ns.DB
    if not (DB and DB.ready and ns.Learn) then
        return false
    end
    local kind, id = ns.Learn.ParseGUID(GUID(guid))
    local e = kind == "npc" and DB.units[id]
    if not e then
        return false
    end
    if (e.fac or "") ~= "" then
        return not e.hostile and DB.ForMyFaction(e)
    end
    return e.hostile == false
end

local function VignettePosition(guid, map)
    if not (map and C_VignetteInfo.GetVignettePosition) then return end
    local ok, pos = pcall(C_VignetteInfo.GetVignettePosition, guid, map)
    pos = Plain(pos)
    if ok and pos then
        local x, y = ns.XY(pos)
        return Position(map, x, y)
    end
end
local function ScanVignettes(map)
    if not On() or not (C_VignetteInfo and C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignetteInfo) then return end
    local ok, guids = pcall(C_VignetteInfo.GetVignettes)
    guids = Plain(guids)
    if not ok or type(guids) ~= "table" then return end
    local now = Now()
    scanSerial = scanSerial + 1
    for _, rawGUID in ipairs(guids) do
        local vguid = GUID(rawGUID)
        if vguid then
            local okInfo, info = pcall(C_VignetteInfo.GetVignetteInfo, vguid)
            info = Plain(info)
            if okInfo and type(info) == "table" and Plain(info.onMinimap) then
                local key = GUID(info.objectGUID)
                key = key and key ~= "" and key or ("vignette:" .. vguid)
                if Plain(info.isDead) then
                    Done(key, "killed")
                elseif friendly[key] or FriendlyNPC(key) then
                    Forget(key, true)
                else
                    local old = targets[key]
                    local name = Name(info.name, old)
                    local m, x, y = VignettePosition(vguid, map)
                    -- Position is expressed in the map requested, never in an
                    -- invented map from the facing return. Keep the old map if
                    -- a best-map transition cannot yet project this vignette.
                    if not m and old and old.m ~= map then m, x, y = VignettePosition(vguid, old.m) end
                    if name or old then
                        local t = Seen(key, VignetteKind(info), name, m, x, y, "marker")
                        if t then t.vig, t.serial = true, scanSerial end
                    end
                end
            end
        end
    end
    for key, t in pairs(targets) do
        if t.vig and t.serial ~= scanSerial then
            if t.kind == "rare" and t.unitSeen and now - t.unitSeen < 10 then
                t.vig = nil
            else
                -- Leaving minimap range is not proof of death/loot. Log 'gone'
                -- but do not poison the ten-minute killed/looted/ignore memory.
                Forget(key, false, "gone")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Rares on nameplates, your target and what you point at
-- ---------------------------------------------------------------------------
local LOOK_UNITS = { "target", "mouseover", "focus" }
for i = 1, 40 do
    LOOK_UNITS[#LOOK_UNITS + 1] = "nameplate" .. i
end

-- the closest spawn the database knows, if it's close enough to be this one
local function KnownSpawn(guid)
    local DB = ns.DB
    if not (DB and DB.ready and ns.Learn) then
        return nil
    end
    local kind, id = ns.Learn.ParseGUID(GUID(guid))
    local e = kind == "npc" and DB.units[id]
    if not e then
        return nil
    end
    local p, dist = DB.Nearest(DB.Points(e))
    if p and dist and dist <= NEAR_SPAWN then
        return p.m, p.x, p.y
    end
end

function Treasure.LookAt(unit)
    if not On() then return end
    unit = ns.Str(unit)
    if not unit then return end
    if not UnitExists or not Plain(UnitExists(unit)) then
        return
    end
    local guid = UnitGUID and GUID(ns.Str(UnitGUID(unit)))
    if type(guid) ~= "string" then
        return
    end
    -- your own side's rares and bosses (Varimathras next to Sylvanas): you can't fight them
    if (UnitIsPlayer and Plain(UnitIsPlayer(unit)))
        or (UnitPlayerControlled and Plain(UnitPlayerControlled(unit)))
        or (UnitCanAttack and not Plain(UnitCanAttack("player", unit))) then
        friendly[guid] = true
        Forget(guid, true)
        return
    end
    if UnitIsDead and Plain(UnitIsDead(unit)) then
        if targets[guid] or not done[guid] then
            Done(guid, "killed")
        end
        return
    end
    -- someone else is already fighting it: it isn't yours to loot
    if UnitIsTapDenied and Plain(UnitIsTapDenied(unit)) then
        friendly[guid] = true
        Forget(guid, true)
        return
    end
    friendly[guid] = nil
    local class = UnitClassification and ns.Str(UnitClassification(unit))
    if not RARE_CLASS[class] then return end
    local t = targets[guid]
    local m, x, y, near
    if not (t and t.m) then
        m, x, y = KnownSpawn(guid)
        if not m then
            m, x, y = Geo.GetPlayerMapPosition()
            near = true
        end
        m, x, y = Position(m, x, y)
    end
    local level = not t and UnitLevel and ns.Num(UnitLevel(unit)) or nil
    if level and (level < -1 or level > 1000 or level % 1 ~= 0) then level = nil end
    t = Seen(guid, "rare", Name(UnitName and ns.Str(UnitName(unit)), t), m, x, y, "unit", class, level, near)
    if t then
        t.unitSeen = Now()
    end
end

-- ---------------------------------------------------------------------------
-- The chest right in front of you
-- ---------------------------------------------------------------------------
local function IsChest(id, name)
    local DB = ns.DB
    local e = DB and DB.ready and DB.objects[id]
    if e and e.chest then
        return true
    end
    return Treasure.IsChestName(name)
end

function Treasure.CheckInFront()
    if not On() or not ns.Learn then
        return
    end
    local guid = UnitGUID and GUID(ns.Str(UnitGUID("softinteract")))
    local kind, id = ns.Learn.ParseGUID(GUID(guid))
    if kind ~= "object" then
        return
    end
    local name = Name(UnitName and ns.Str(UnitName("softinteract")))
    if IsChest(id, name) then
        local old = targets[guid]
        local m, x, y
        if not (old and old.m) then m, x, y = Geo.GetPlayerMapPosition() end
        m, x, y = Position(m, x, y)
        local t = Seen(guid, "chest", name, m, x, y, "front", nil, nil, true)
        if t then
            t.here = true
        end
    end
end

-- ---------------------------------------------------------------------------
-- Known chest spots from the database
-- ---------------------------------------------------------------------------
local function SpotKey(p)
    return ("%s:%d:%.5f:%.5f"):format(p.kind, p.m, p.x, p.y)
end

-- Database work is done once per generation. No cross-zone vectors in a pick,
-- no DB.Points allocations or formatted keys in the steady-state scan.
local zoneMaps, zoneRetry = {}, {}
local function ZoneMap(map)
    map = ns.Int(ns.Num(map))
    if not map then return end
    if zoneMaps[map] then return zoneMaps[map] end
    local now = Now()
    if zoneRetry[map] and now < zoneRetry[map] then return end
    local current, containing = map, map
    for hop = 1, 12 do
        local info = Geo.GetMapInfo(current)
        if not info then zoneRetry[map] = now + 5; return end
        local kind, parent = info.mapType, info.parentMapID
        if kind == 3 or kind == 4 then containing = current; break end
        if kind ~= 5 and kind ~= 6 then break end
        if parent == 0 or parent == current then break end
        if hop == 12 then break end
        current = parent
    end
    zoneMaps[map], zoneRetry[map] = containing, nil
    return containing
end
Treasure.ZoneMap = ZoneMap
local pendingMaps, pendingCursor, pendingAt
local function IndexMap(map, spots)
    local zone = ZoneMap(map)
    if not zone then return false end
    local list = spotIndex[zone]
    if not list then list = {}; spotIndex[zone] = list end
    for _, spot in ipairs(spots) do list[#list + 1] = spot end
    return true
end
function Treasure.ZoneSpots(map)
    map = ns.Int(ns.Num(map))
    local DB = ns.DB
    if not (map and DB and DB.ready and C_Map and type(C_Map.GetMapInfo) == "function") then return empty end
    if not spotIndex or indexGeneration ~= DB.generation then
        spotIndex, zoneMaps, zoneRetry = {}, {}, {}
        pendingMaps, pendingCursor, pendingAt = {}, 1, 0
        local byMap = {}
        local function Add(e, kind, id)
            local name = Name(e.name) or "?"
            for _, p in ipairs(DB.Points(e)) do
                local m, x, y = Position(p.m, p.x, p.y)
                if m then
                    local list = byMap[m]
                    if not list then list = {}; byMap[m] = list end
                    local spot = { m = m, x = x, y = y, kind = kind, id = id, name = name }
                    spot.visitKey = SpotKey(spot)
                    list[#list + 1] = spot
                end
            end
        end
        for id, e in pairs(DB.objects) do
            local validID = ns.Int(ns.Num(id))
            if validID and e.chest then Add(e, "spot", validID) end
        end
        for id, e in pairs(DB.units) do
            local validID = ns.Int(ns.Num(id))
            if validID and (e.rank == "2" or e.rank == "4") and DB.IsEnemy(e) then Add(e, "spawn", validID) end
        end
        for m, spots in pairs(byMap) do
            if not IndexMap(m, spots) then pendingMaps[#pendingMaps + 1] = { map = m, spots = spots } end
        end
        indexGeneration = DB.generation
    end
    -- Fixed work bound, independent of DB size. Unresolved source buckets are
    -- retained and attached exactly once on recovery, without another Points scan.
    local now = Now()
    if #pendingMaps > 0 and now >= pendingAt then
        local count = math.min(8, #pendingMaps)
        for _ = 1, count do
            if pendingCursor > #pendingMaps then pendingCursor = 1 end
            local entry = pendingMaps[pendingCursor]
            if IndexMap(entry.map, entry.spots) then
                pendingMaps[pendingCursor] = pendingMaps[#pendingMaps]
                pendingMaps[#pendingMaps] = nil
            else pendingCursor = pendingCursor + 1 end
        end
        pendingAt = now + 5
    end
    local zone = ZoneMap(map)
    return zone and spotIndex[zone] or empty
end

local function KnownSpots()
    if Dead() then return end
    local cur, now, map = targets.spot, Now(), Map()
    if cur and (not Wanted(cur.kind) or ZoneMap(cur.m) ~= ZoneMap(map)) then Forget("spot", true); cur = nil end
    if not (Wanted("spot") or Wanted("spawn")) then return end
    if cur then
        local dist = Geo.GetVector(cur)
        if (dist and dist <= VISIT_DIST) or cur.dismissed or (cur.wp and not WP.IsValid(cur.wp)) then
            if not Forget("spot", true) then return end
            visited[cur.visitKey] = now
            cur = nil
        end
    end
    -- A live detection always wins, including when focus is disabled.
    for key in pairs(targets) do if key ~= "spot" then return end end
    local active = WP.GetActive()
    if active and active.source ~= "treasure" and not ns.Get("treasureFocus") then return end
    if cur then return end
    local best, bestDist
    for _, p in ipairs(Treasure.ZoneSpots(map)) do
        if Wanted(p.kind) and (not visited[p.visitKey] or now - visited[p.visitKey] >= DONE_MEMORY) then
            local dist = Geo.GetVector(p)
            if dist and dist <= VISIT_DIST then
                visited[p.visitKey] = now
            elseif dist and (not bestDist or dist < bestDist) then
                best, bestDist = p, dist
            end
        end
    end
    if best then
        local t = Seen("spot", best.kind, best.name, best.m, best.x, best.y)
        if t then t.visitKey, t.id = best.visitKey, best.id end
    end
end
Treasure.PickKnown = KnownSpots

-- ---------------------------------------------------------------------------
-- Keeping the list tidy
-- ---------------------------------------------------------------------------
local function Expire()
    local now = Now()
    for key, t in pairs(targets) do
        if t.here and not t.vig and now - (t.seen or 0) > HERE_MEMORY then
            Forget(key, true, "gone")
        elseif t.kind == "rare" and not t.vig and now - (t.unitSeen or t.seen or 0) > RARE_MEMORY then
            Forget(key, false, "gone")
        end
    end
    for key, at in pairs(done) do
        if now - at > DONE_MEMORY then
            done[key] = nil
        end
    end
end

-- Lets everything go (treasure hunt turned off, or a new zone).
function Treasure.Clear()
    for key in pairs(targets) do
        Forget(key, true)
    end
end

function Treasure.Targets()
    return targets
end

function Treasure.Scan()
    if not On() then
        return
    end
    focusEnabled = ns.Get("treasureFocus") and true or false
    local map = Map()
    if scanMap and map ~= scanMap then
        for key, t in pairs(targets) do
            if not t.vig and ZoneMap(t.m) ~= ZoneMap(map) then Forget(key, true, not Known(t) and "gone" or nil) end
        end
        wipe(friendly)
    end
    scanMap = map
    for _, unit in ipairs(LOOK_UNITS) do
        Treasure.LookAt(unit)
    end
    ScanVignettes(map)
    Treasure.CheckInFront()
    Expire()
end

local function Start()
    if not On() then return end
    -- the database knows the chests and the rares' spawns
    if ns.DB and ns.DB.Load then
        ns.Call(ns.DB.Load)
    end
    Treasure.Scan()
    KnownSpots()
end

-- What treasure hunt sees right now (/wp treasure status).
local VIA = { marker = "TREASURE_VIA_MARKER", unit = "TREASURE_VIA_UNIT", front = "TREASURE_VIA_FRONT" }
function Treasure.Status()
    ns.Print(On() and L.TREASURE_ON or L.TREASURE_OFF, true)
    local guids
    if C_VignetteInfo and C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignetteInfo then
        local ok, list = pcall(C_VignetteInfo.GetVignettes)
        list = Plain(list)
        guids = ok and type(list) == "table" and list or nil
    end
    if not guids then
        ns.Print(L.TREASURE_STATUS_NO_MARKERS, true)
    else
        local shown, mapOnly = {}, 0
        for _, vguid in ipairs(guids) do
            vguid = GUID(vguid)
            local ok, info
            if vguid then ok, info = pcall(C_VignetteInfo.GetVignetteInfo, vguid) end
            info = Plain(info)
            if ok and type(info) == "table" then
                if Plain(info.onMinimap) then
                    local name = Name(info.name) or "?"
                    shown[#shown + 1] = ("%s (%s)"):format(name, L[LABEL[VignetteKind(info)]])
                else
                    mapOnly = mapOnly + 1
                end
            end
        end
        ns.Print(L.TREASURE_STATUS_MARKERS:format(#shown), true)
        for _, line in ipairs(shown) do
            ns.Print("  " .. line, true)
        end
        if mapOnly > 0 then
            ns.Print("  " .. L.TREASURE_STATUS_MAP_ONLY:format(mapOnly), true)
        end
    end
    local tracking = 0
    for _ in pairs(targets) do
        tracking = tracking + 1
    end
    ns.Print(L.TREASURE_STATUS_TRACKING:format(tracking), true)
    EnsureLog()
    if not history[1] then
        ns.Print(L.TREASURE_STATUS_NONE, true)
        return
    end
    ns.Print(L.TREASURE_STATUS_RECENT, true)
    local now = Stamp()
    for _, h in ipairs(history) do
        ns.Print(("  %s (%s, %s)"):format(Title(h), L[VIA[h.via] or "TREASURE_VIA_MARKER"], L.TREASURE_STATUS_AGO:format(math.max(0, math.floor((now - h.at) / 60)))), true)
    end
end

function Treasure.Toggle()
    local on = not On()
    ns.Set("treasureHunt", on)
    ns.Print(on and L.TREASURE_ON or L.TREASURE_OFF, true)
    return on
end

function WaypointTracker_ToggleTreasure()
    ns.Call(Treasure.Toggle)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local UpdateTicker
ns.On("SETTING_CHANGED", function(key, value)
    local wasFocus = focusEnabled
    if key == nil or key == "treasureFocus" then focusEnabled = ns.Get("treasureFocus") and true or false end
    if key == nil or key == "treasureHunt" then
        UpdateTicker()
        if On() then
            local wasQuiet = quiet
            quiet = true
            local ok, err = pcall(Start)
            quiet = wasQuiet
            if not ok then error(err) end
        else
            Treasure.Clear()
        end
        return
    end
    if key == "treasureFocus" and value and not wasFocus and On()
        and not Dead() then
        local best, bestDist
        for _, t in pairs(targets) do
            if not Known(t) and Position(t.m, t.x, t.y) then
                local dist = Geo.GetVector(t)
                if dist and (not bestDist or dist < bestDist
                    or (dist == bestDist and t.key < best.key)) then best, bestDist = t, dist end
            end
        end
        if best then Treasure.Point(best) end
    end
    for kind, setting in pairs(WANTED) do
        if key == setting and not value then
            for k, t in pairs(targets) do
                if t.kind == kind then
                    Forget(k, true)
                end
            end
        end
    end
    if key == "treasureKnownSpots" or key == "treasureKnownRares" then
        KnownSpots()
    end
end)

ns.On("LOGIN", function()
    UpdateTicker()
    if On() then
        C_Timer.After(2, function()
            ns.Call(Start)
        end)
    end
end)

local pending = false
local function Soon()
    if not On() then return end
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if On() then ns.Call(Treasure.Scan) end
    end)
end
ns.RegisterEvent("VIGNETTE_MINIMAP_UPDATED", Soon)
ns.RegisterEvent("VIGNETTES_UPDATED", Soon)
ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit)
    if not On() then return end
    Treasure.LookAt(unit)
end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if not On() then return end
    Treasure.LookAt("target")
end)
ns.RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", function()
    if not On() then return end
    Treasure.CheckInFront()
end)
-- you looted it: it's taken
local function Looted()
    local n = GetNumLootItems and ns.Num(GetNumLootItems()) or 0
    n = math.min(100, math.max(0, n))
    if not GetLootSourceInfo then return end
    local function Sources(...)
        -- Event-local varargs, no retained tables. The client returns alternating
        -- GUID/count pairs; a secret pair cannot hide a later valid source.
        for i = 1, select("#", ...), 2 do
            local guid, count = GUID(select(i, ...)), ns.Num(select(i + 1, ...))
            local t = guid and targets[guid]
            -- Loot can be pickpocketing. Creature completion comes from the
            -- death/disappearance observers, never from loot alone.
            local creature = t and (t.kind == "rare" or guid:find("^Creature") or guid:find("^Vehicle"))
            if t and not creature and count and count > 0 then Done(guid, "looted") end
        end
    end
    for slot = 1, n do Sources(GetLootSourceInfo(slot)) end
    -- No soft-interact inference: a current target supplies no evidence that
    -- this loot window belongs to that chest. Wait for an identified source.
end

ns.RegisterEvent("LOOT_OPENED", function()
    if On() then
        Looted()
    end
end)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    if not On() then return end
    -- Instances/layers can reuse a map ID. Unit-only sightings from the old
    -- area must not survive that transition; confirmed done memory still does.
    for key, t in pairs(targets) do
        if not t.vig then Forget(key, true, not Known(t) and "gone" or nil) end
    end
    wipe(friendly)
    Treasure.Scan()
    KnownSpots()
end)

local ticker = CreateFrame("Frame")
local acc, spotAcc = 0, 0
local function Tick(_, elapsed)
    if not On() then
        return
    end
    acc = acc + elapsed
    spotAcc = spotAcc + elapsed
    if acc >= SCAN_EVERY then
        acc = 0
        ns.Call(Treasure.Scan)
    end
    if spotAcc >= SPOTS_EVERY then
        spotAcc = 0
        ns.Call(KnownSpots)
    end
end
UpdateTicker = function()
    acc, spotAcc = 0, 0
    if On() then
        ticker:SetScript("OnUpdate", Tick)
        ticker:Show()
    else
        ticker:Hide()
        ticker:SetScript("OnUpdate", nil)
    end
end
UpdateTicker()
