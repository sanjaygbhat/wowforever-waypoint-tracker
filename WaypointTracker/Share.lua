-- Share: send a waypoint to other players. We never send anything by
-- ourselves: the chat box opens with the message ready (and the right
-- channel), you just press Enter. The message carries the game's own map
-- pin link, which anyone can click, even without this addon.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local Share = {}
ns.Share = Share

local Plain = ns.Plain

-- The game's clickable map pin link for a spot (nil if the map can't hold
-- a pin). We borrow the map pin for a moment and put yours back.
function Share.MapPinLink(wp)
    if not (C_Map.SetUserWaypoint and C_Map.GetUserWaypointHyperlink and C_Map.HasUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return nil
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(wp.m) then
        return nil
    end
    local previous = C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint() or nil
    if previous then
        -- put it back as a proper map point, whatever shape the game gave us
        local px, py = ns.XY(previous.position)
        px, py = ns.Num(px), ns.Num(py)
        previous = previous.uiMapID and px and py and UiMapPoint.CreateFromCoordinates(previous.uiMapID, px, py) or nil
    end
    local tracked = previous and C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
    local ok, link = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(wp.m, wp.x, wp.y))
        return C_Map.GetUserWaypointHyperlink()
    end)
    if previous then
        pcall(C_Map.SetUserWaypoint, previous)
        if tracked then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    else
        pcall(C_Map.ClearUserWaypoint)
    end
    -- the borrowed pin is gone again: not a new waypoint
    WP.NotePin()
    if ok and type(link) == "string" and link ~= "" then
        return link
    end
end

-- "Sentinel Hill: [Map Pin] Westfall (56.3, 47.1)"
function Share.Message(wp)
    local where = ("%s (%s)"):format(Geo.GetMapName(wp.m), Geo.FormatCoords(wp.x, wp.y))
    local link = Share.MapPinLink(wp)
    local text = link and (link .. " " .. where) or where
    if wp.title and wp.title ~= "" then
        text = wp.title .. ": " .. text
    end
    return text
end

local function OpenChat(text)
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(text)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(text)
    end
end

-- Put the waypoint into the chat box (added to what you're typing, if the
-- chat box is already open).
function Share.ToChatBox(wp)
    local text = Share.Message(wp)
    if ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.InsertLink(text) then
        return
    end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(text) then
        return
    end
    OpenChat(text)
end

function Share.ToChannel(wp, command)
    OpenChat(command .. " " .. Share.Message(wp))
end

-- Channels you can use right now: { text, command }
function Share.Channels()
    local list = {}
    if IsInRaid and IsInRaid() then
        list[#list + 1] = { L.SHARE_RAID, "/raid" }
    end
    if IsInGroup and IsInGroup() then
        list[#list + 1] = { L.SHARE_PARTY, "/party" }
    end
    if IsInGuild and IsInGuild() then
        list[#list + 1] = { L.SHARE_GUILD, "/guild" }
    end
    list[#list + 1] = { L.SHARE_SAY, "/say" }
    -- whisper your target (skipped wherever the game hides unit names)
    pcall(function()
        if Plain(UnitExists("target")) and Plain(UnitIsPlayer("target")) and not Plain(UnitIsUnit("target", "player")) then
            local name, realm = UnitName("target")
            name, realm = Plain(name), Plain(realm)
            if name then
                local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
                list[#list + 1] = { L.SHARE_WHISPER:format(name), "/w " .. full }
            end
        end
    end)
    return list
end

-- A spot to share that isn't a waypoint: { m, x, y, title }, x/y from 0 to 1.
function Share.Spot(mapID, x, y, title)
    mapID, x, y = ns.Int(mapID), tonumber(x), tonumber(y)
    if not (mapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
        return nil
    end
    return { m = mapID, x = x, y = y, title = ns.CleanText(title, 100) }
end

-- Where you stand, ready to share (nil where the game hides your position).
function Share.MySpot(title)
    local mapID, x, y = Geo.GetPlayerMapPosition()
    return mapID and Share.Spot(mapID, x, y, title)
end

-- Puts where you stand into the chat box, nothing else needed.
function WaypointTracker_ShareHere()
    local spot = Share.MySpot()
    if spot then
        Share.ToChatBox(spot)
    else
        ns.Print(L.NO_POSITION, true)
    end
end

-- Small menu under the Share button.
function Share.ShowMenu(owner, wp)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        Share.ToChatBox(wp)
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L.SHARE_TITLE)
        for _, ch in ipairs(Share.Channels()) do
            local command = ch[2]
            root:CreateButton(ch[1], function()
                Share.ToChannel(wp, command)
            end)
        end
        root:CreateButton(L.SHARE_CHATBOX, function()
            Share.ToChatBox(wp)
        end)
    end)
end
