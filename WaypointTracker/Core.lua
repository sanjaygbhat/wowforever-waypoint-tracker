-- Core: saved settings, a tiny event/callback system and shared helpers.
local ADDON_NAME, ns = ...
local L = ns.L

ns.name = ADDON_NAME
ns.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"

-- ---------------------------------------------------------------------------
-- Defaults. Simple things are on, extras are off.
-- ---------------------------------------------------------------------------
ns.defaults = {
    -- arrow
    arrowShown = true,
    arrowScale = 1.0,
    arrowAlpha = 0.8, -- a little see-through, so it feels part of the world
    arrowPos = nil, -- { point, relativePoint, x, y }; nil = over your character
    -- the name / distance / time lines under the arrow
    textScale = 1.0,
    textAlpha = 0.9,
    textSeparate = false, -- false: the text stays under the arrow and moves with it
    textPos = nil, -- where the text goes when it moves on its own
    colorMode = "distance", -- "distance" | "direction" | "single"
    singleColor = { r = 1.0, g = 0.82, b = 0.0 },
    showTitle = true,
    showDistance = true,
    showETA = false,
    fadeOnCourse = true,
    hideInCombat = false,
    hideOnTaxi = false,
    -- arrival
    arrivalDistance = 10,
    autoClear = true,
    arrivalSound = true,
    autoNext = true,
    -- maps
    worldPins = true,
    minimapPins = true,
    minimapEdge = true,
    worldCoords = true,
    mapClick = true,
    coordsBox = false,
    coordsLocked = false,
    coordsPos = nil,
    -- general
    autoClosest = false,
    persist = true,
    minimapButton = true,
    minimapAngle = 200,
    chatMessages = true,
    sharePrefix = true, -- shared spots start with "[Waypoint Tracker]"
    useMetres = false,
    addonWaypoints = true,
    blizzardPin = false,
    followMapPins = true, -- the game's own map pin (and map pin links) move the arrow
    followQuest = false, -- point at the quest you track when you have no waypoint
    corpseWaypoint = true, -- dying points the arrow at your body
    -- write down NPCs, quests and objects met in Forever (see Learn.lua)
    learn = true,
    -- treasure hunt (see Treasure.lua): off until you turn it on
    treasureHunt = false,
    treasureChests = true,
    treasureRares = true,
    treasureOther = true,
    treasureKnownSpots = false,
    treasurePing = true,
    treasureFocus = true,
    -- Find window
    findTab = "all",
    findFaction = true,
    findThisZone = false,
    -- window state
    showAdvanced = false,
    windowPos = nil,
}

local function CopyTable(src)
    if type(src) ~= "table" then
        return src
    end
    local t = {}
    for k, v in pairs(src) do
        t[k] = CopyTable(v)
    end
    return t
end
ns.CopyTable = CopyTable

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------
local callbacks = {}

function ns.On(event, fn)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end

-- Errors are reported once per unique message, so a bug can never flood the
-- screen with popups (important for code that runs every frame). The report
-- carries the stack where it happened, so bug reports can be acted on.
local reported = {}
function ns.ReportError(err)
    err = tostring(err)
    local message = err:match("^[^\n]*")
    if reported[message] then
        return
    end
    reported[message] = true
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(err)
    end
end

local function WithStack(err)
    local stack = debugstack and debugstack(2)
    return stack and (tostring(err) .. "\n" .. stack) or err
end

-- Calls fn(...) and reports an error (once) instead of breaking the UI.
function ns.Call(fn, ...)
    local ok, err
    if select("#", ...) == 0 then
        ok, err = xpcall(fn, WithStack)
    else
        local args, n = { ... }, select("#", ...)
        ok, err = xpcall(function()
            return fn(unpack(args, 1, n))
        end, WithStack)
    end
    if not ok then
        ns.ReportError(err)
    end
    return ok
end

function ns.Fire(event, ...)
    local list = callbacks[event]
    if not list then
        return
    end
    for i = 1, #list do
        ns.Call(list[i], ...)
    end
end

-- Wrap a function so errors are reported (once) instead of breaking the UI.
function ns.Safe(fn)
    return function(...)
        ns.Call(fn, ...)
    end
end

-- ---------------------------------------------------------------------------
-- Settings access
-- ---------------------------------------------------------------------------
function ns.Get(key)
    local db = ns.settings
    if db and db[key] ~= nil then
        return db[key]
    end
    return ns.defaults[key]
end

function ns.Set(key, value)
    if not ns.settings then
        return
    end
    ns.settings[key] = value
    ns.Fire("SETTING_CHANGED", key, value)
end

function ns.ResetSettings()
    local keepWindow = ns.settings and ns.settings.windowPos
    WaypointTrackerDB.settings = CopyTable(ns.defaults)
    ns.settings = WaypointTrackerDB.settings
    ns.settings.windowPos = keepWindow
    ns.Fire("SETTING_CHANGED", nil, nil)
end

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------
local PREFIX = "|cff33ff99" .. L.ADDON_TITLE .. "|r: "

function ns.Print(msg, force)
    if not force and not ns.Get("chatMessages") then
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
-- Returns v if it is a normal number we are allowed to do maths with.
-- (Newer clients can hand addons "secret" values in some situations.)
local issecretvalue = issecretvalue
function ns.Num(v)
    if v == nil then
        return nil
    end
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    if type(v) ~= "number" or v ~= v then
        return nil
    end
    return v
end

-- x, y of a position the game hands back. Usually it has :GetXY(), but
-- some (the map pin's, in WoW Forever) are plain { x = , y = } tables.
function ns.XY(pos)
    if type(pos) ~= "table" then
        return nil, nil
    end
    if type(pos.GetXY) == "function" then
        return pos:GetXY()
    end
    return pos.x, pos.y
end

-- Returns v unless it is one of those secret values (then nil).
function ns.Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then
        return nil
    end
    return v
end

-- Text from outside the addon (imports, other addons) made safe to show:
-- no colour codes, links, textures or control characters, and not too long.
function ns.CleanText(s, maxLen)
    if type(s) ~= "string" then
        return nil
    end
    s = s:gsub("[%c]", " ")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", "")
    s = s:gsub("|", "")
    maxLen = maxLen or 200
    if #s > maxLen then
        -- cut, and drop a character the cut may have split in half
        s = s:sub(1, maxLen):gsub("[\192-\255][\128-\191]*$", "")
    end
    s = ns.Trim(s)
    return s ~= "" and s or nil
end

-- A whole number from 1 to 2^31 (ids, map ids, levels), or nil.
function ns.Int(v)
    v = tonumber(v)
    if v and v == v and v >= 1 and v < 2147483648 and v % 1 == 0 then
        return v
    end
end

local POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
-- A saved frame position { point, relPoint, x, y } checked before it goes
-- to SetPoint. Returns point, relPoint, x, y, or nil if it's damaged.
function ns.SavedPoint(pos)
    if type(pos) ~= "table" or not POINTS[pos[1]] then
        return nil
    end
    local rel = POINTS[pos[2]] and pos[2] or pos[1]
    local x, y = ns.Num(tonumber(pos[3])) or 0, ns.Num(tonumber(pos[4])) or 0
    if math.abs(x) > 10000 or math.abs(y) > 10000 then
        return nil
    end
    return pos[1], rel, x, y
end

function ns.Clamp(v, lo, hi)
    if v < lo then
        return lo
    elseif v > hi then
        return hi
    end
    return v
end

function ns.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function ns.IsAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    elseif IsAddOnLoaded then
        return IsAddOnLoaded(name)
    end
    return false
end

-- True when another arrow addon that owns /way and the shared waypoint API
-- (TomTom) is installed and will load, or already has.
function ns.IsOtherArrowAddonPresent()
    if ns.IsAddOnLoaded("TomTom") then
        return true
    end
    if C_AddOns and C_AddOns.GetAddOnEnableState then
        local ok, state = pcall(C_AddOns.GetAddOnEnableState, "TomTom", UnitName("player"))
        if ok and type(state) == "number" and state > 0 then
            local ok2, loadable = pcall(C_AddOns.IsAddOnLoadable, "TomTom")
            if not ok2 or loadable ~= false then
                return true
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
local events = CreateFrame("Frame")
ns.eventFrame = events
local handlers = {}

-- Returns false when this client doesn't know the event (the feature then
-- just stays quiet instead of stopping the rest of the file from loading).
function ns.RegisterEvent(event, fn)
    if not handlers[event] then
        if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
            return false
        end
        if not pcall(events.RegisterEvent, events, event) then
            return false
        end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        ns.Call(list[i], ...)
    end
end)

local function InitDatabase()
    if type(WaypointTrackerDB) ~= "table" then
        WaypointTrackerDB = {}
    end
    local db = WaypointTrackerDB
    if type(db.settings) ~= "table" then
        db.settings = {}
    end
    -- settings saved under their earlier names keep their value
    for old, new in pairs({ tomtomCompat = "addonWaypoints", tomtomNoticeShown = "wayNoticeShown" }) do
        if db.settings[old] ~= nil then
            if db.settings[new] == nil then
                db.settings[new] = db.settings[old]
            end
            db.settings[old] = nil
        end
    end
    -- fill in anything new, drop values of the wrong type
    for k, v in pairs(ns.defaults) do
        local cur = db.settings[k]
        if cur == nil then
            db.settings[k] = CopyTable(v)
        elseif v ~= nil and type(cur) ~= type(v) then
            db.settings[k] = CopyTable(v)
        end
    end
    -- 1 -> 2: new arrow look. Move it back over the character and use the
    -- softer defaults, unless someone had already changed them.
    if (db.version or 1) < 2 then
        local st = db.settings
        st.arrowPos = nil
        if st.arrowAlpha == 1.0 then
            st.arrowAlpha = ns.defaults.arrowAlpha
        end
        if st.fadeOnCourse == false then
            st.fadeOnCourse = true
        end
        st.arrowLocked = nil
    end
    db.version = 2
    ns.settings = db.settings

    if type(WaypointTrackerCharDB) ~= "table" then
        WaypointTrackerCharDB = {}
    end
    if type(WaypointTrackerCharDB.waypoints) ~= "table" then
        WaypointTrackerCharDB.waypoints = {}
    end
    ns.charDB = WaypointTrackerCharDB
end

ns.RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then
        return
    end
    InitDatabase()
    ns.Fire("INIT")
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    ns.Fire("LOGIN")
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ns.Fire("ENTERING_WORLD")
end)

-- Key binding labels
BINDING_HEADER_WAYPOINTTRACKER = L.ADDON_TITLE
BINDING_NAME_WAYPOINTTRACKER_TOGGLE = L.BINDING_TOGGLE
BINDING_NAME_WAYPOINTTRACKER_CLEAR = L.BINDING_CLEAR
BINDING_NAME_WAYPOINTTRACKER_HERE = L.BINDING_HERE
BINDING_NAME_WAYPOINTTRACKER_ARROW = L.BINDING_ARROW
BINDING_NAME_WAYPOINTTRACKER_CLOSEST = L.BINDING_CLOSEST
BINDING_NAME_WAYPOINTTRACKER_FIND = L.BINDING_FIND
BINDING_NAME_WAYPOINTTRACKER_SHARE = L.BINDING_SHARE
BINDING_NAME_WAYPOINTTRACKER_TREASURE = L.BINDING_TREASURE
