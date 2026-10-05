-- Treasure hunt: notices chests, rare spawns and other things the game
-- marks around you, pings you the moment one appears, points the arrow at
-- it, and lets it go once it's taken, killed or gone.
--
-- Where it looks:
--   * the game's minimap markers (vignettes) for treasure, rares and events:
--     exact positions, and they disappear when taken
--   * nameplates, your target and what you point at: rare and rare elite
--     enemies, placed at their nearest known spawn
--   * the chest in front of you (the soft-interact target)
--   * if you like, known chest spawn spots from the database, nearest first
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
    return type(name) == "string" and CHEST_NAMES[name] == true
end

local SCAN_EVERY = 1 -- seconds between looks around
local SPOTS_EVERY = 5 -- seconds between picking a known chest spot
local RARE_MEMORY = 120 -- a rare seen only on nameplates is let go this long after it was last seen
local HERE_MEMORY = 60 -- a chest in front of you
local DONE_MEMORY = 600 -- something taken or killed isn't announced again for this long
local KNOWN_RANGE = 300 -- yards: known chest spots worth walking to
local VISIT_DIST = 15 -- yards: close enough to have checked a known spot
local ALERT_GAP = 1.5 -- seconds: at most one ping this often
local NEAR_SPAWN = 200 -- yards: a rare's known spawn this close is where it is

local RARE_CLASS = { rare = true, rareelite = true, worldboss = true }

local targets = {} -- key (GUID, or "spot") -> { kind, name, m, x, y, wp, seen, vig, here, dismissed }
local done = {} -- key -> when it was taken, killed or let go
local visited = {} -- known spot -> when you checked it
local lastAlert = -100
local chestEntries -- database objects that are chests, once it's loaded

local function Now()
    return GetTime and GetTime() or 0
end

local function On()
    return ns.Get("treasureHunt")
end

local WANTED = { chest = "treasureChests", rare = "treasureRares", other = "treasureOther", spot = "treasureKnownSpots" }
local function Wanted(kind)
    return On() and ns.Get(WANTED[kind] or "treasureOther")
end

local LABEL = { chest = "TREASURE_KIND_CHEST", rare = "TREASURE_KIND_RARE", other = "TREASURE_KIND_OTHER", spot = "TREASURE_KIND_SPOT" }
local function Label(t)
    return L[LABEL[t.kind] or "TREASURE_KIND_OTHER"]
end

local function Title(t)
    return L.TREASURE_TITLE:format(Label(t), t.name or "?")
end

-- ---------------------------------------------------------------------------
-- Pinging you
-- ---------------------------------------------------------------------------
local function Alert(t)
    if t.kind == "spot" or not ns.Get("treasurePing") then
        return
    end
    local dist = t.m and Geo.GetVector(t)
    local text
    if dist then
        text = L.TREASURE_FOUND_DIST:format(Label(t), t.name or "?", Geo.FormatDistance(dist))
    else
        text = L.TREASURE_FOUND:format(Label(t), t.name or "?")
    end
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
    if t.dismissed or not (t.m and t.x and t.y) then
        return
    end
    if t.wp then
        if WP.IsValid(t.wp) then
            if t.wp.m ~= t.m or math.abs(t.wp.x - t.x) > 0.001 or math.abs(t.wp.y - t.y) > 0.001 then
                WP.Move(t.wp, t.m, t.x, t.y)
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
        setActive = ns.Get("treasureFocus") and true or false,
    })
end

local function Forget(key, quiet)
    local t = targets[key]
    if not t then
        return
    end
    targets[key] = nil
    if t.wp and WP.IsValid(t.wp) then
        WP.Remove(t.wp, true)
    end
    if not quiet and t.kind ~= "spot" and t.announced and ns.Get("chatMessages") then
        ns.Print(L.TREASURE_GONE:format(t.name or "?"))
    end
end

-- Something was taken or killed: let it go and don't announce it again.
local function Done(key)
    done[key] = Now()
    Forget(key)
end

-- Seen (again): remember it, ping the first time, and keep its waypoint
-- where it is.
local function Seen(key, kind, name, m, x, y)
    local now = Now()
    if done[key] and now - done[key] < DONE_MEMORY then
        return
    end
    if not Wanted(kind) then
        return
    end
    local t = targets[key]
    if not t then
        t = { kind = kind, name = name }
        targets[key] = t
        if m and x and y then
            t.m, t.x, t.y = m, x, y
        end
        t.announced = kind ~= "spot"
        Alert(t)
    end
    t.seen = now
    t.name = name or t.name
    if m and x and y then
        t.m, t.x, t.y = m, x, y
    end
    Place(t)
    return t
end

-- ---------------------------------------------------------------------------
-- The game's minimap markers
-- ---------------------------------------------------------------------------
local function VignetteKind(info)
    local atlas = Plain(info.atlasName)
    atlas = type(atlas) == "string" and atlas:lower() or ""
    if atlas:find("loot", 1, true) or atlas:find("treasure", 1, true) or atlas:find("chest", 1, true) then
        return "chest"
    end
    if atlas:find("kill", 1, true) or atlas:find("rare", 1, true) then
        return "rare"
    end
    local obj = Plain(info.objectGUID)
    if type(obj) == "string" then
        if obj:find("^GameObject") then
            return "chest"
        elseif obj:find("^Creature") or obj:find("^Vehicle") then
            return "rare"
        end
    end
    return "other"
end

local function ScanVignettes()
    if not (C_VignetteInfo and C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignetteInfo) then
        return
    end
    local ok, guids = pcall(C_VignetteInfo.GetVignettes)
    if not ok or type(guids) ~= "table" then
        return
    end
    local m = Plain(C_Map.GetBestMapForUnit("player"))
    local now = Now()
    local seenNow = {}
    for _, vguid in ipairs(guids) do
        vguid = Plain(vguid)
        local okInfo, info = pcall(C_VignetteInfo.GetVignetteInfo, vguid)
        if vguid and okInfo and type(info) == "table" and Plain(info.onMinimap) then
            local key = Plain(info.objectGUID)
            key = (type(key) == "string" and key ~= "") and key or ("vignette:" .. tostring(vguid))
            if Plain(info.isDead) then
                if targets[key] then
                    Done(key)
                end
            else
                local name = ns.CleanText(Plain(info.name), 60)
                local x, y
                if m and C_VignetteInfo.GetVignettePosition then
                    local okPos, pos = pcall(C_VignetteInfo.GetVignettePosition, vguid, m)
                    if okPos and pos then
                        x, y = ns.XY(pos)
                    end
                end
                x, y = ns.Num(x), ns.Num(y)
                if not (x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (x > 0 or y > 0)) then
                    x, y = nil, nil
                end
                if name and name ~= "" then
                    local t = Seen(key, VignetteKind(info), name, x and m, x, y)
                    if t then
                        t.vig = true
                        seenNow[key] = true
                    end
                end
            end
        end
    end
    -- markers that went away: taken, killed, or you walked off
    for key, t in pairs(targets) do
        if t.vig and not seenNow[key] then
            if t.kind == "rare" and t.unitSeen and now - t.unitSeen < 10 then
                t.vig = nil -- still on a nameplate
            else
                Forget(key)
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
    local kind, id = ns.Learn.ParseGUID(guid)
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
    if not On() or not UnitExists(unit) or Plain(UnitIsPlayer(unit)) then
        return
    end
    if UnitPlayerControlled and Plain(UnitPlayerControlled(unit)) then
        return
    end
    local class = UnitClassification and Plain(UnitClassification(unit))
    if not RARE_CLASS[class] then
        return
    end
    local guid = Plain(UnitGUID(unit))
    if type(guid) ~= "string" then
        return
    end
    if Plain(UnitIsDead(unit)) then
        if targets[guid] or not done[guid] then
            Done(guid)
        end
        return
    end
    -- someone else is already fighting it: it isn't yours to loot
    if UnitIsTapDenied and Plain(UnitIsTapDenied(unit)) then
        return
    end
    local t = targets[guid]
    local m, x, y
    if not (t and t.m) then
        m, x, y = KnownSpawn(guid)
    end
    t = Seen(guid, "rare", ns.CleanText(Plain(UnitName(unit)), 60), m, x, y)
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
    local guid = Plain(UnitGUID("softinteract"))
    local kind, id = ns.Learn.ParseGUID(guid)
    if kind ~= "object" then
        return
    end
    local name = ns.CleanText(Plain(UnitName("softinteract")), 60)
    if IsChest(id, name) then
        local t = Seen(guid, "chest", name or "?")
        if t then
            t.here = true
        end
    end
end

-- ---------------------------------------------------------------------------
-- Known chest spots from the database
-- ---------------------------------------------------------------------------
local function SpotKey(p)
    return ("%d:%.3f:%.3f"):format(p.m, p.x, p.y)
end

local function ChestEntries()
    local DB = ns.DB
    if not (DB and DB.ready) then
        return nil
    end
    if not chestEntries then
        chestEntries = {}
        for id, e in pairs(DB.objects) do
            if id > 0 and e.chest then
                chestEntries[#chestEntries + 1] = e
            end
        end
    end
    return chestEntries
end

local function KnownSpots()
    local cur = targets.spot
    if not Wanted("spot") then
        if cur then
            Forget("spot", true)
        end
        return
    end
    local now = Now()
    if cur then
        local dist = Geo.GetVector(cur)
        local checked = (dist and dist <= VISIT_DIST) or cur.dismissed or (cur.wp and not WP.IsValid(cur.wp))
        if not checked then
            return
        end
        visited[SpotKey(cur)] = now
        Forget("spot", true)
    end
    -- something live comes first
    for _, t in pairs(targets) do
        if t.wp then
            return
        end
    end
    local best, bestDist, bestName
    for _, e in ipairs(ChestEntries() or {}) do
        for _, p in ipairs(ns.DB.Points(e)) do
            local key = SpotKey(p)
            if not visited[key] or now - visited[key] > DONE_MEMORY then
                local dist = Geo.GetVector(p)
                if dist and dist <= KNOWN_RANGE and dist > VISIT_DIST and (not bestDist or dist < bestDist) then
                    best, bestDist, bestName = p, dist, e.name
                end
            end
        end
    end
    if best then
        Seen("spot", "spot", bestName, best.m, best.x, best.y)
    end
end

-- ---------------------------------------------------------------------------
-- Keeping the list tidy
-- ---------------------------------------------------------------------------
local function Expire()
    local now = Now()
    for key, t in pairs(targets) do
        if t.here and not t.vig and now - (t.seen or 0) > HERE_MEMORY then
            Forget(key, true)
        elseif t.kind == "rare" and not t.vig and now - (t.unitSeen or t.seen or 0) > RARE_MEMORY then
            Forget(key)
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
    ScanVignettes()
    for _, unit in ipairs(LOOK_UNITS) do
        Treasure.LookAt(unit)
    end
    Treasure.CheckInFront()
    Expire()
end

local function Start()
    -- the database knows the chests and the rares' spawns
    if ns.DB and ns.DB.Load then
        ns.Call(ns.DB.Load)
    end
    chestEntries = nil
    Treasure.Scan()
    KnownSpots()
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
ns.On("SETTING_CHANGED", function(key, value)
    if key == nil or key == "treasureHunt" then
        if On() then
            Start()
        else
            Treasure.Clear()
        end
        return
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
    if key == "treasureKnownSpots" then
        KnownSpots()
    end
end)

ns.On("LOGIN", function()
    if On() then
        C_Timer.After(2, function()
            ns.Call(Start)
        end)
    end
end)

local pending = false
local function Soon()
    if pending or not On() then
        return
    end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        ns.Call(ScanVignettes)
    end)
end
ns.RegisterEvent("VIGNETTE_MINIMAP_UPDATED", Soon)
ns.RegisterEvent("VIGNETTES_UPDATED", Soon)
ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit)
    Treasure.LookAt(unit)
end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    Treasure.LookAt("target")
end)
ns.RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", function()
    Treasure.CheckInFront()
end)
-- you looted it: it's taken
local function Looted()
    local n = GetNumLootItems and Plain(GetNumLootItems()) or 0
    for slot = 1, n do
        local guid = GetLootSourceInfo and Plain((GetLootSourceInfo(slot)))
        if type(guid) == "string" and targets[guid] then
            Done(guid)
        end
    end
    -- the chest you were standing at, if the game didn't say where the loot came from
    local front = Plain(UnitGUID("softinteract"))
    if type(front) == "string" and targets[front] and targets[front].here then
        Done(front)
    end
end
ns.RegisterEvent("LOOT_OPENED", function()
    if On() then
        Looted()
    end
end)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    Treasure.Clear()
end)

local ticker = CreateFrame("Frame")
local acc, spotAcc = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
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
end)
