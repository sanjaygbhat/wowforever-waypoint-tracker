-- Addon bridge: many addons (quest guides, treasure maps, ...) send
-- waypoints through the shared TomTom:AddWaypoint() API. When no addon
-- providing that API is installed, we answer those calls, so their
-- waypoints show up on this arrow. If one is installed, we stay out of its
-- way completely.
local _, ns = ...
local WP, Geo = ns.WP, ns.Geo

local Bridge = {}

-- a finite number above 0, or nil
local function PositiveNumber(v)
    v = tonumber(v)
    if v and v > 0 and v < math.huge then
        return v
    end
end

-- TomTom:AddWaypoint(mapID, x, y, opts) with x/y from 0 to 1
function Bridge:AddWaypoint(mapID, x, y, opts)
    opts = type(opts) == "table" and opts or {}
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end
    local title = opts.title or opts.desc
    local persistent = opts.persistent
    if persistent == nil then
        persistent = true
    end
    return WP.Add(mapID, x, y, {
        title = type(title) == "string" and title or nil,
        persistent = persistent and ns.Get("persist"),
        silent = opts.silent ~= false,
        setActive = opts.crazy ~= false,
        source = type(opts.from) == "string" and opts.from:sub(1, 40) or "addon",
        arrivalDistance = PositiveNumber(opts.arrivaldistance) or PositiveNumber(opts.cleardistance),
        callbacks = type(opts.callbacks) == "table" and opts.callbacks or nil,
    })
end

-- Old style: TomTom:AddMFWaypoint(mapID, floor, x, y, opts)
function Bridge:AddMFWaypoint(mapID, _, x, y, opts)
    return self:AddWaypoint(mapID, x, y, opts)
end

function Bridge:RemoveWaypoint(uid)
    if type(uid) == "table" then
        return WP.Remove(uid, true)
    end
end

function Bridge:ClearAllWaypoints()
    WP.ClearAll(true)
end

function Bridge:IsValidWaypoint(uid)
    return WP.IsValid(uid)
end

function Bridge:WaypointExists(mapID, x, y, desc)
    for _, wp in ipairs(WP.List()) do
        if wp.m == mapID and math.abs(wp.x - x) < 0.0005 and math.abs(wp.y - y) < 0.0005 and (desc == nil or wp.title == desc) then
            return true
        end
    end
    return false
end

function Bridge:SetCrazyArrow(uid)
    if WP.IsValid(uid) then
        WP.SetActive(uid, true)
    end
end

function Bridge:SetClosestWaypoint()
    return WP.SetClosest(true)
end

function Bridge:GetDistanceToWaypoint(uid)
    if WP.IsValid(uid) then
        return (Geo.GetVector(uid))
    end
end

function Bridge:GetDirectionToWaypoint(uid)
    if WP.IsValid(uid) then
        local dist, bearing = Geo.GetVector(uid)
        if dist then
            return bearing
        end
    end
end

function Bridge:ShowHideCrazyArrow()
    ns.Set("arrowShown", not ns.Get("arrowShown"))
end

function Bridge:HideCrazyArrow()
    ns.Set("arrowShown", false)
end

function Bridge:ShowCrazyArrow()
    ns.Set("arrowShown", true)
end

function Bridge:GetClosestWaypoint()
    return (WP.Closest())
end

function Bridge:GetKey(wp)
    if type(wp) == "table" then
        return ("%s:%d:%d:%s"):format(wp.m, math.floor(wp.x * 1e4), math.floor(wp.y * 1e4), wp.title or "")
    end
end

-- Old-style call: TomTom:AddZWaypoint(continent, zone, x, y, desc) with x/y
-- from 0 to 100. Only works when "zone" is already a map ID.
function Bridge:AddZWaypoint(_, zone, x, y, desc)
    if type(zone) == "number" and type(x) == "number" and type(y) == "number" then
        return self:AddWaypoint(zone, x / 100, y / 100, { title = desc })
    end
end

function Bridge:GetCZWFromMapID(mapID)
    return nil, nil, mapID
end

-- A few addons peek at the API's settings table; give them something harmless.
Bridge.db = { profile = { arrow = { enable = true }, persistence = {}, minimap = {}, worldmap = {} } }
Bridge.profile = Bridge.db.profile
Bridge.isWaypointTrackerBridge = true

-- Any other function of the API an addon might call does nothing instead of
-- raising an error inside that addon.
setmetatable(Bridge, {
    __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then
            return function() end
        end
    end,
})

-- Put the bridge in place straight away, so addons that look for the API
-- while they load can find it...
if TomTom == nil and not ns.IsOtherArrowAddonPresent() then
    TomTom = Bridge
    ns.bridgeActive = true
end

-- ...and take it away again once settings are known, if it isn't wanted.
ns.On("INIT", function()
    if ns.bridgeActive and TomTom == Bridge and (not ns.Get("addonWaypoints") or ns.IsOtherArrowAddonPresent()) then
        TomTom = nil
        ns.bridgeActive = false
    end
end)
