-- Chat commands: /wp and /waypoint always, plus /way, /wayb and /cway
-- unless another arrow addon already owns them.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local function Help()
    ns.Print(L.HELP_HEADER, true)
    -- when another addon owns /way, /wp does the same job
    local wayTaken = ns.IsOtherArrowAddonPresent()
    for _, key in ipairs({ "HELP_OPEN", "HELP_WAY", "HELP_WAY_SEARCH", "HELP_FIND", "HELP_HERE", "HELP_SHARE", "HELP_CLEAR", "HELP_LIST", "HELP_ARROW", "HELP_CLOSEST", "HELP_HELP" }) do
        local line = L[key]
        if wayTaken then
            line = line:gsub("/way ", "/wp ")
        end
        DEFAULT_CHAT_FRAME:AddMessage("   " .. line)
    end
end

local function List()
    local list = WP.List()
    if #list == 0 then
        ns.Print(L.NO_WAYPOINTS, true)
        return
    end
    ns.Print(L.LIST_HEADER, true)
    local activeWp = WP.GetActive()
    for i, wp in ipairs(list) do
        local dist = Geo.GetVector(wp)
        local line = ("   %d. %s%s"):format(i, WP.Describe(wp), dist and (" - " .. Geo.FormatDistance(dist)) or "")
        if wp == activeWp then
            line = "|cffffd100" .. line .. "|r"
        end
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
end

-- The map for "[zone] x y": the zone typed, or the one you're in. Prints
-- what's wrong and returns nil when it can't tell.
local function ResolveZone(zoneText)
    local mapID
    if zoneText == "" then
        mapID = C_Map.GetBestMapForUnit("player")
        if not mapID then
            ns.Print(L.NO_POSITION, true)
            return
        end
    elseif zoneText:match("^#%d+$") then
        mapID = tonumber(zoneText:sub(2))
        if not Geo.IsValidMap(mapID) then
            ns.Print(L.UNKNOWN_ZONE:format(zoneText), true)
            return
        end
    else
        local extra
        mapID, extra = Geo.FindZone(zoneText)
        local suggestions = type(extra) == "table" and extra or nil
        if mapID and extra == true then
            -- typo fixed for you ("trisifal" -> Tirisfal Glades)
            ns.Print(L.USING_ZONE:format(Geo.GetMapName(mapID)), true)
        end
        if not mapID then
            ns.Print(L.UNKNOWN_ZONE:format(zoneText), true)
            if suggestions and #suggestions > 0 then
                ns.Print(L.DID_YOU_MEAN:format(table.concat(suggestions, ", ")), true)
            end
            return
        end
    end
    return mapID
end

-- "/way [zone] x y [name]"
local function AddFromText(msg)
    local zoneText, x, y, title = Geo.ParseWayArgs(msg)
    if not x then
        -- no coordinates, just a name: "/way hogger" goes to Hogger, or
        -- opens Find when the name isn't exact or matches several things
        if msg:find("%a") or msg:find("[\128-\255]") then
            return ns.Find.Way(msg)
        end
        ns.Print(L.INVALID_COORDS, true)
        return
    end
    local mapID = ResolveZone(zoneText)
    if not mapID then
        return
    end
    local wp = WP.Add(mapID, x / 100, y / 100, { title = title })
    if not wp then
        ns.Print(L.INVALID_COORDS, true)
    end
    return wp
end
ns.AddFromText = AddFromText

-- "/wp share [zone] x y [name]" puts a spot in the chat box without setting
-- a waypoint; "/wp share [name]" shares where you stand.
local function ShareFromText(msg)
    local zoneText, x, y, title = Geo.ParseWayArgs(msg)
    local spot
    if not x then
        spot = ns.Share.MySpot(msg)
        if not spot then
            ns.Print(L.NO_POSITION, true)
            return
        end
    else
        local mapID = ResolveZone(zoneText)
        if not mapID then
            return
        end
        spot = ns.Share.Spot(mapID, x / 100, y / 100, title)
        if not spot then
            ns.Print(L.INVALID_COORDS, true)
            return
        end
    end
    -- the chat box you typed this in is emptied and closed once the command
    -- finishes, so open it again a moment later with the message in it
    C_Timer.After(0, function()
        ns.Call(ns.Share.ToChatBox, spot)
    end)
    return spot
end
ns.ShareFromText = ShareFromText

local function Clear(rest)
    rest = Geo.Lower(ns.Trim(rest))
    if rest == "all" then
        WP.ClearAll()
    else
        WaypointTracker_ClearActive()
    end
end

local function Handle(msg, isWayCommand)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and Geo.Lower(cmd) or ""

    if cmd == "" then
        if isWayCommand then
            Help()
        else
            WaypointTracker_ToggleWindow()
        end
    elseif cmd == "help" or cmd == "?" then
        Help()
    elseif cmd == "list" then
        List()
    elseif cmd == "clear" or cmd == "reset" or cmd == "remove" then
        Clear(rest)
    elseif cmd == "here" then
        WP.AddHere(rest)
    elseif cmd == "arrow" then
        WaypointTracker_ToggleArrow()
    elseif cmd == "closest" then
        if not WP.SetClosest() then
            ns.Print(L.NO_WAYPOINT_ACTIVE, true)
        end
    elseif cmd == "share" then
        ShareFromText(rest)
    elseif cmd == "find" or cmd == "search" then
        ns.Find.Show(rest)
    elseif cmd == "options" or cmd == "config" or cmd == "show" then
        ns.UI.Show()
    else
        AddFromText(msg)
    end
end

SLASH_WAYPOINTTRACKER1 = "/wp"
SLASH_WAYPOINTTRACKER2 = "/waypoint"
SLASH_WAYPOINTTRACKER3 = "/waypointtracker"
SlashCmdList.WAYPOINTTRACKER = ns.Safe(function(msg)
    Handle(msg, false)
end)

-- True when another addon has already registered this slash command.
local function SlashTaken(cmd)
    for key in pairs(SlashCmdList) do
        if type(key) == "string" and not key:find("^WAYPOINTTRACKER") then
            local i = 1
            local name = _G["SLASH_" .. key .. i]
            while name do
                if type(name) == "string" and name:lower() == cmd then
                    return true
                end
                i = i + 1
                name = _G["SLASH_" .. key .. i]
            end
        end
    end
    return false
end

-- Registers a short command unless another addon already has it.
local function Claim(key, cmd, fn)
    if SlashTaken(cmd) then
        return false
    end
    _G["SLASH_" .. key .. "1"] = cmd
    SlashCmdList[key] = ns.Safe(fn)
    return true
end

ns.On("LOGIN", function()
    -- one hello on the very first login, so new players know where to start
    if not ns.settings.welcomeShown then
        ns.settings.welcomeShown = true
        ns.Print(L.WELCOME, true)
    end
    local ours = not ns.IsOtherArrowAddonPresent()
        and Claim("WAYPOINTTRACKERWAY", "/way", function(msg)
            Handle(msg, true)
        end)
    if not ours then
        -- tell people once why /way isn't ours; /wayb and /cway go with it
        if not ns.settings.wayNoticeShown then
            ns.settings.wayNoticeShown = true
            ns.Print(L.WAY_IN_USE, true)
        end
        return
    end
    Claim("WAYPOINTTRACKERWAYB", "/wayb", function(msg)
        WP.AddHere(ns.Trim(msg))
    end)
    Claim("WAYPOINTTRACKERCWAY", "/cway", function()
        if not WP.SetClosest() then
            ns.Print(L.NO_WAYPOINT_ACTIVE, true)
        end
    end)
end)
