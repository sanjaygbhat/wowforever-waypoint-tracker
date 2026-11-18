-- Waypoints: the list of waypoints, which one the arrow points at, saving
-- them per character and what happens when you arrive.
local _, ns = ...
local L = ns.L
local Geo = ns.Geo

local WP = {}
ns.WP = WP

local list = {} -- ordered, newest last
local active -- the waypoint the arrow points at
local nextId = 1
local loaded = false -- nothing is written until the saved list has been read

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
function WP.Describe(wp)
    local zone = Geo.GetMapName(wp.m)
    local coords = Geo.FormatCoords(wp.x, wp.y)
    if wp.title and wp.title ~= "" then
        return ("%s (%s %s)"):format(wp.title, zone, coords)
    end
    return ("%s %s"):format(zone, coords)
end

function WP.ShortName(wp)
    if wp.title and wp.title ~= "" then
        return wp.title
    end
    return ("%s %s"):format(Geo.GetMapName(wp.m), Geo.FormatCoords(wp.x, wp.y))
end

function WP.List()
    return list
end

function WP.Count()
    return #list
end

function WP.GetActive()
    return active
end

-- How often you yourself have said where the arrow should point: a
-- waypoint you added (typed, clicked on the map, picked in Find), a click
-- on a waypoint or its pin, a quest's icon, "closest". Not the addon moving
-- it: an arrival, a quest's next stage, a route's next stop, your corpse,
-- another addon. What waits to move the arrow (Nearest asked for while the
-- database loads) gives way to a choice of yours made since, and to
-- nothing else.
local userChoices = 0
function WP.UserChose()
    userChoices = userChoices + 1
end
function WP.UserChoices()
    return userChoices
end

function WP.IsValid(wp)
    if not wp then
        return false
    end
    for i = 1, #list do
        if list[i] == wp then
            return true
        end
    end
    return false
end

local function IndexOf(wp)
    for i = 1, #list do
        if list[i] == wp then
            return i
        end
    end
end

-- ---------------------------------------------------------------------------
-- Saving (only waypoints marked persistent are written to disk)
-- ---------------------------------------------------------------------------
local function Save()
    if not ns.charDB or not loaded then
        return
    end
    local out = {}
    if ns.Get("persist") then
        for _, wp in ipairs(list) do
            if wp.persistent then
                out[#out + 1] = {
                    m = wp.m,
                    x = wp.x,
                    y = wp.y,
                    title = wp.title,
                    startDist = wp.startDist,
                    source = wp.source ~= "user" and wp.source or nil,
                    active = (wp == active) or nil,
                    routeID = wp.routeID,
                    routeIndex = wp.routeIndex,
                }
            end
        end
    end
    ns.charDB.waypoints = out
end
WP.Save = Save

-- Many waypoints at once (a route): saved and announced once at the end.
local batching = false
local function Changed()
    if batching then
        return
    end
    Save()
    ns.Fire("WAYPOINTS_CHANGED")
end

function WP.Batch(fn)
    batching = true
    local ok, err = pcall(fn)
    batching = false
    Changed()
    if not ok then
        error(err, 0)
    end
end

-- Who picks the next waypoint when the arrow's one goes: a route wants the
-- next of its points, not the closest one. Returns a waypoint or nil.
WP.nextHook = nil

-- A route followed in steps: returns its id, the stop it is on, and which
-- of its other stops may come next (true: any; a set; nil: none). Choices
-- made for you (the closest waypoint, the one after a waypoint that goes)
-- leave its other stops alone, so the arrow never jumps ahead to whichever
-- of them is nearest; after loading it is on the stop the route is on.
WP.heldHook = nil

-- false for a waypoint choices made for you must leave alone
local function Free(wp, heldID, cur, allow)
    return not heldID or wp.routeID ~= heldID or wp == cur or allow == true or (allow ~= nil and allow[wp] == true)
end

-- ---------------------------------------------------------------------------
-- Blizzard map pin (optional): mirrors the arrow's waypoint
-- ---------------------------------------------------------------------------
local ourPin -- { m, x, y } of the Blizzard user waypoint we placed

-- The game's map pin as we last left it. "Follow map pins" only picks up a
-- pin that differs from this, so our own changes (and the pin Share borrows
-- for a moment) are never taken for a new waypoint.
local knownPin

local function PinKey()
    local p = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint()
    if not p or not p.uiMapID or not p.position then
        return "none"
    end
    local x, y = ns.XY(p.position)
    return ("%s:%.4f:%.4f"):format(tostring(p.uiMapID), tonumber(x) or 0, tonumber(y) or 0)
end

-- call after changing the game's pin ourselves
function WP.NotePin()
    knownPin = PinKey()
end

-- true when the game's pin was placed by someone else since we last looked
function WP.IsNewPin()
    local key = PinKey()
    if key == knownPin then
        return false
    end
    knownPin = key
    return key ~= "none"
end

function WP.IsOurBlizzardPin(m, x, y)
    return ourPin and ourPin.m == m and math.abs(ourPin.x - x) < 0.001 and math.abs(ourPin.y - y) < 0.001
end

local function ClearBlizzardPin()
    if not ourPin then
        return
    end
    if C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
        local cur = C_Map.GetUserWaypoint()
        if cur and cur.uiMapID == ourPin.m and cur.position then
            local x, y = ns.XY(cur.position)
            if math.abs((x or 0) - ourPin.x) < 0.001 and math.abs((y or 0) - ourPin.y) < 0.001 then
                C_Map.ClearUserWaypoint()
            end
        end
    end
    ourPin = nil
    WP.NotePin()
end

local function UpdateBlizzardPin()
    if not C_Map.SetUserWaypoint or not (UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return
    end
    if not ns.Get("blizzardPin") or not active then
        ClearBlizzardPin()
        return
    end
    if ourPin and ourPin.m == active.m and ourPin.x == active.x and ourPin.y == active.y then
        return
    end
    ClearBlizzardPin()
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(active.m) then
        return
    end
    local point = UiMapPoint.CreateFromCoordinates(active.m, active.x, active.y)
    if not pcall(C_Map.SetUserWaypoint, point) then
        WP.NotePin()
        return
    end
    ourPin = { m = active.m, x = active.x, y = active.y }
    WP.NotePin()
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

-- ---------------------------------------------------------------------------
-- Changing the list
-- ---------------------------------------------------------------------------
-- Points the arrow at a waypoint you picked yourself (a click on it or on
-- its pin): WP.SetActive, counted as a choice of yours.
function WP.Choose(wp, silent)
    WP.UserChose()
    return WP.SetActive(wp, silent)
end

function WP.SetActive(wp, silent)
    if wp and not WP.IsValid(wp) then
        return
    end
    if active == wp then
        return
    end
    active = wp
    if wp then
        wp.arrivedAt = nil
    end
    ns.Safe(UpdateBlizzardPin)()
    Save()
    ns.Fire("ACTIVE_CHANGED", wp)
    if wp and not silent and ns.Get("chatMessages") and #list > 1 then
        ns.Print(L.NOW_POINTING:format(WP.ShortName(wp)))
    end
end

-- Add a waypoint. mapID + x/y from 0 to 1.
-- opts: title, persistent, silent, setActive (default true), source, noReuse,
--       arrivalDistance, callbacks (used by the addon bridge)
function WP.Add(mapID, x, y, opts)
    opts = opts or {}
    mapID = ns.Int(mapID)
    x, y = tonumber(x), tonumber(y)
    if not mapID or not x or not y or not Geo.IsValidMap(mapID) then
        return nil
    end
    -- written this way round so NaN (which fails every comparison) is refused
    if not (x >= 0 and x <= 1 and y >= 0 and y <= 1) then
        return nil
    end
    -- titles can come from other addons: no escape codes, sensible length
    local title = ns.CleanText(opts.title, 100)
    -- yours: typed or clicked ("user"), a place picked, something from Find
    local source = opts.source or "user"
    if source == "user" or source == "place" or source == "find" then
        WP.UserChose()
    end

    -- same spot twice? reuse the existing one
    for _, wp in ipairs(list) do
        if not opts.noReuse and wp.m == mapID and math.abs(wp.x - x) < 0.0005 and math.abs(wp.y - y) < 0.0005 and wp.title == title then
            if opts.setActive ~= false then
                WP.SetActive(wp, true)
            end
            return wp
        end
    end

    local persistent = opts.persistent
    if persistent == nil then
        persistent = true
    end
    local wp = {
        id = nextId,
        m = mapID,
        x = x,
        y = y,
        title = title,
        persistent = persistent and true or false,
        source = opts.source or "user",
        arrivalDistance = ns.Num(tonumber(opts.arrivalDistance)),
        callbacks = opts.callbacks,
        startDist = opts.startDist,
    }
    nextId = nextId + 1
    list[#list + 1] = wp

    if opts.setActive ~= false or not active then
        active = wp
        ns.Safe(UpdateBlizzardPin)()
        ns.Fire("ACTIVE_CHANGED", wp)
    end
    Changed()
    if not opts.silent then
        ns.Print(L.ADDED:format(WP.Describe(wp)))
    end
    return wp
end

-- Moves a waypoint (something that wanders, like a rare). x/y from 0 to 1.
function WP.Move(wp, mapID, x, y)
    mapID, x, y = ns.Int(mapID), tonumber(x), tonumber(y)
    if not WP.IsValid(wp) or not mapID or not x or not y or not Geo.IsValidMap(mapID) then
        return false
    end
    if not (x >= 0 and x <= 1 and y >= 0 and y <= 1) then
        return false
    end
    wp.m, wp.x, wp.y = mapID, x, y
    if wp == active then
        ns.Safe(UpdateBlizzardPin)()
    end
    Changed()
    return true
end

-- noAdvance: don't move the arrow on to another waypoint
function WP.Remove(wp, silent, noAdvance)
    local i = IndexOf(wp)
    if not i then
        return false
    end
    table.remove(list, i)
    -- a waypoint that came from the game's map pin takes that pin with it,
    -- so it doesn't come back next time you log in
    if wp.source == "mappin" and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
        local cur = C_Map.GetUserWaypoint()
        local cx, cy
        if cur and cur.position then
            cx, cy = ns.XY(cur.position)
        end
        if cur and cur.uiMapID == wp.m and cx and cy and math.abs(cx - wp.x) < 0.001 and math.abs(cy - wp.y) < 0.001 then
            C_Map.ClearUserWaypoint()
            WP.NotePin()
        end
    end
    if wp == active then
        active = nil
        -- move on to the next of a route's points, or the closest remaining
        -- waypoint, if there is one (a route counts by the stop it is on)
        if #list > 0 and not noAdvance then
            active = (WP.nextHook and WP.nextHook(wp)) or WP.Closest(nil, true)
        end
        ns.Safe(UpdateBlizzardPin)()
        ns.Fire("ACTIVE_CHANGED", active)
    end
    Changed()
    if not silent then
        ns.Print(L.REMOVED:format(WP.ShortName(wp)))
    end
    return true
end

function WP.ClearAll(silent)
    if #list == 0 then
        if not silent then
            ns.Print(L.NO_WAYPOINTS, true)
        end
        return
    end
    wipe(list)
    active = nil
    ns.Safe(UpdateBlizzardPin)()
    ns.Fire("ACTIVE_CHANGED", nil)
    Changed()
    if not silent then
        ns.Print(L.CLEARED_ALL)
    end
end

-- Closest waypoint you can actually walk to (same continent), else the
-- newest. auto: a choice made for you (see WP.heldHook).
function WP.Closest(exclude, auto)
    local heldID, cur, allow
    if auto and WP.heldHook then
        heldID, cur, allow = WP.heldHook()
    end
    local best, bestDist
    for _, wp in ipairs(list) do
        if wp ~= exclude and Free(wp, heldID, cur, allow) then
            local dist = Geo.GetVector(wp)
            if dist and (not bestDist or dist < bestDist) then
                best, bestDist = wp, dist
            end
        end
    end
    if not best then
        for i = #list, 1, -1 do
            if list[i] ~= exclude and Free(list[i], heldID, cur, allow) then
                return list[i]
            end
        end
    end
    return best, bestDist
end

-- auto: asked for by another addon, not by you (see WP.heldHook)
function WP.SetClosest(silent, auto)
    local wp = WP.Closest(nil, auto)
    if wp then
        if not auto then
            WP.UserChose()
        end
        WP.SetActive(wp, silent)
    end
    return wp
end

-- Waypoint where you're standing.
function WP.AddHere(title)
    local mapID, x, y = Geo.GetPlayerMapPosition()
    if not mapID then
        ns.Print(L.NO_POSITION, true)
        return nil
    end
    return WP.Add(mapID, x, y, { title = title and title ~= "" and title or L.MY_POSITION_NAME })
end

-- ---------------------------------------------------------------------------
-- Arrival (called by the arrow's update loop)
-- ---------------------------------------------------------------------------
-- Set on you and not walked away from yet: the arrow says "You're here".
function WP.IsWaiting(wp)
    return wp ~= nil and wp.armed == false
end

function WP.CheckArrival(wp, dist)
    if not wp or not dist then
        return false
    end
    -- let other addons know about distance changes (callbacks from the addon bridge)
    if type(wp.callbacks) == "table" and type(wp.callbacks.distance) == "table" then
        for range, fn in pairs(wp.callbacks.distance) do
            if type(range) == "number" and type(fn) == "function" then
                local inside = dist <= range
                wp.cbState = wp.cbState or {}
                if inside and not wp.cbState[range] then
                    wp.cbState[range] = true
                    pcall(fn, "distance", wp, range, dist, wp.lastDist)
                elseif not inside then
                    wp.cbState[range] = nil
                end
            end
        end
    end
    wp.lastDist = dist

    local arriveAt = wp.arrivalDistance or ns.Get("arrivalDistance")
    local leaveAt = arriveAt * 1.5 + 5
    -- a waypoint set where you stand (or right next to you) isn't reached
    -- the moment it's made: it waits until you've walked away from it once
    if wp.armed == nil then
        wp.armed = dist > arriveAt
    end
    if not wp.armed then
        if dist > leaveAt then
            wp.armed = true
        end
        return false
    end
    if wp.arrivedAt and dist > leaveAt then
        wp.arrivedAt = nil -- walked away again: arriving can trigger again
    end
    if dist > arriveAt or wp.arrivedAt then
        return false
    end
    wp.arrivedAt = GetTime()
    if ns.Get("arrivalSound") then
        PlaySound((SOUNDKIT and SOUNDKIT.MAP_PING) or 3175, "Master")
    end
    ns.Print(L.REACHED:format(WP.ShortName(wp)))
    ns.Fire("ARRIVED", wp)
    if wp.callbacks and type(wp.callbacks.arrived) == "function" then
        pcall(wp.callbacks.arrived, "arrived", wp, dist)
    end
    -- a route's point: the route says where to go next
    if wp.routeID and ns.Routes and ns.Routes.Arrived(wp) then
        return true
    end
    if ns.Get("autoClear") then
        WP.Remove(wp, true, not ns.Get("autoNext"))
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------
local function Load()
    -- other addons may already have sent waypoints before login: keep them
    local early = {}
    for i = 1, #list do
        early[i] = list[i]
    end
    local earlyActive = active
    wipe(list)
    active = nil
    local saved = ns.charDB and ns.charDB.waypoints
    if type(saved) ~= "table" or not ns.Get("persist") then
        saved = {}
    end
    local toActivate
    for _, s in ipairs(saved) do
        if type(s) == "table" and ns.Int(s.m) and Geo.IsValidMap(s.m) and type(s.x) == "number" and type(s.y) == "number"
            and s.x >= 0 and s.x <= 1 and s.y >= 0 and s.y <= 1 then
            local wp = {
                id = nextId,
                m = s.m,
                x = s.x,
                y = s.y,
                title = ns.CleanText(s.title, 100),
                startDist = type(s.startDist) == "number" and s.startDist or nil,
                persistent = true,
                source = type(s.source) == "string" and s.source or "user",
                routeID = type(s.routeID) == "string" and s.routeID or nil,
                routeIndex = ns.Int(s.routeIndex),
            }
            nextId = nextId + 1
            list[#list + 1] = wp
            if s.active then
                toActivate = wp
            end
        end
    end
    for _, wp in ipairs(early) do
        local dup = false
        for _, have in ipairs(list) do
            if have.m == wp.m and math.abs(have.x - wp.x) < 0.0005 and math.abs(have.y - wp.y) < 0.0005 and have.title == wp.title then
                dup = true
                break
            end
        end
        if not dup then
            list[#list + 1] = wp
        end
    end
    -- the waypoint you had before logging out wins
    if not toActivate and earlyActive and WP.IsValid(earlyActive) then
        toActivate = earlyActive
    end
    -- else the newest one, a route's by the stop it is on (not its last)
    if not toActivate and WP.heldHook then
        local heldID, cur = WP.heldHook()
        for i = #list, 1, -1 do
            if Free(list[i], heldID, cur) then
                toActivate = list[i]
                break
            end
        end
    end
    active = toActivate or list[#list]
    loaded = true
end

ns.On("LOGIN", function()
    Load()
    ns.Safe(UpdateBlizzardPin)()
    ns.Fire("ACTIVE_CHANGED", active)
    ns.Fire("WAYPOINTS_CHANGED")
end)

-- remember how far away each waypoint started (used for the arrow colour)
ns.RegisterEvent("PLAYER_LOGOUT", Save)

ns.On("SETTING_CHANGED", function(key)
    if key == "persist" then
        Save()
    elseif key == "blizzardPin" or key == nil then
        ns.Safe(UpdateBlizzardPin)()
    end
end)

-- Global helpers for key bindings
function WaypointTracker_ClearActive()
    local wp = WP.GetActive()
    if wp then
        WP.Remove(wp)
    else
        ns.Print(L.NO_WAYPOINT_ACTIVE, true)
    end
end

function WaypointTracker_AddHere()
    WP.AddHere()
end

function WaypointTracker_SetClosest()
    WP.SetClosest()
end
