-- Route preview geometry, against the fake WoW API. Run from the
-- repository root with Lua 5.1; WT_PLAIN_VECTORS=1 is supported too.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

-- Wave 1: R2 owns the shared mock. These guarded shims can disappear after
-- its map rectangles land; they never replace the shared implementation.
M.worldRects = M.worldRects or {
    [13] = { 0.55, 0.95, 0.10, 0.90 },
    [12] = { 0.05, 0.45, 0.10, 0.90 },
}
if not C_Map.GetMapRectOnMap then
    function C_Map.GetMapRectOnMap(child, top)
        local rect = top == 947 and M.worldRects[child]
        if rect then return unpack(rect) end
    end
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end
local function close(a, b)
    return a and b and math.abs(a - b) < 1e-8
end
local function point(m, x, y)
    return { m = m, x = x or 0.5, y = y or 0.5 }
end

local ns = {}
assert(loadfile("WaypointTracker/Locales/enUS.lua"))("WaypointTracker", ns)
assert(loadfile("WaypointTracker/Core.lua"))("WaypointTracker", ns)
assert(loadfile("WaypointTracker/Geo.lua"))("WaypointTracker", ns)
local Geo = ns.Geo

local function common(pts, wantMap, wantShown, msg)
    local map, shown = Geo.CommonMap(pts)
    check(map == wantMap and shown == wantShown,
        msg .. " (got " .. tostring(map) .. ", " .. tostring(shown) .. ")")
end

common({ point(37, 0.1, 0.2), point(37, 0.8, 0.9) }, 37, 2, "one zone stays on its area map")
common({ point(37), point(52) }, 13, 2, "two Eastern Kingdoms zones use their continent")
common({ point(37), point(1) }, 947, 2, "two continents use the world map")
common({ point(52), point(291) }, 52, 1, "Westfall plus Deadmines stays on Westfall")
common({ point(5001), point(18) }, 18, 2, "Deathknell plus Tirisfal uses Tirisfal")
common({ point(291), point(291, 0.2, 0.8) }, 291, 2, "one dungeon floor stays on that floor")
common({ point(5001), point(5001, 0.2, 0.8) }, 5001, 2, "one micro map stays on that map")
common({ point(18), point(2070) }, 18, 2, "phased copies fold to the first area map")
common({ point(2070), point(18) }, 2070, 2, "phased copies preserve the selected map's ID")
common({ point(37), point(1), point(291) }, 947, 2, "world preview counts only outdoor stops")
common({}, nil, 0, "empty stops have no preview map")
common(nil, nil, 0, "missing stops have no preview map")

local chain = Geo.ParentChain(5001)
check(#chain == 4 and chain[1] == 5001 and chain[2] == 18 and chain[3] == 13 and chain[4] == 947,
    "parent chain runs from the micro map to the world")
check(Geo.ParentChain(5001) == chain, "parent chains are cached")
check(#Geo.ParentChain(947) == 1, "world root has no parent")
check(#Geo.ParentChain(nil) == 0 and #Geo.ParentChain(0) == 0 and #Geo.ParentChain("37") == 0,
    "invalid map IDs have no parent chain")
check(Geo.ContinentID(37) == 13 and Geo.ContinentID(1) == 12, "continent IDs come from the map tree")
check(Geo.ContinentID(5001) == 13 and Geo.ContinentID(291) == 13, "continent ancestors include micro and dungeon maps")
check(Geo.ContinentID(12) == 12, "a continent is its own nearest continent")
check(Geo.ContinentID(947) == nil and Geo.ContinentID(7777) == nil, "world and orphan maps have no continent ancestor")
check(Geo.WorldMapID() == 947, "fallback world map ID is used")
check(Geo.IsWorldMap(947) and not Geo.IsWorldMap(13) and not Geo.IsWorldMap(291), "world type and yard maps are distinguished")
check(not Geo.IsWorldMap(nil), "missing map ID is not a world map")

local x, y = Geo.ProjectToMap(37, 0.5, 0.5, 947)
local rect = M.worldRects[13]
check(x and y and x >= rect[1] and x <= rect[2] and y >= rect[3] and y <= rect[4],
    "Elwynn projects within the Eastern Kingdoms world rectangle")
local cx, cy = Geo.TranslateToMap(37, 0.5, 0.5, 13)
check(close(x, rect[1] + cx * (rect[2] - rect[1])) and close(y, rect[3] + cy * (rect[4] - rect[3])),
    "world projection uses minX, maxX, minY, maxY in the verified API order")
x, y = Geo.ProjectToMap(1, 0.5, 0.5, 947)
rect = M.worldRects[12]
check(x and y and x >= rect[1] and x <= rect[2] and y >= rect[3] and y <= rect[4],
    "Durotar projects within the Kalimdor world rectangle")
x, y = Geo.ProjectToMap(13, 0, 1, 947)
rect = M.worldRects[13]
check(close(x, rect[1]) and close(y, rect[4]), "continent coordinates project to rectangle edges")
x, y = Geo.ProjectToMap(37, 0.5, 0.5, 13)
check(close(x, cx) and close(y, cy), "normal projection preserves TranslateToMap's result")
x, y = Geo.ProjectToMap(2070, 0.25, 0.75, 18)
check(close(x, 0.25) and close(y, 0.75), "phased copies preserve coordinates")
x, y = Geo.ProjectToMap(947, 0.25, 0.75, 947)
check(close(x, 0.25) and close(y, 0.75), "points already on the world map preserve coordinates")
check(Geo.ProjectToMap(291, 0.5, 0.5, 52) == nil and Geo.ProjectToMap(291, 0.5, 0.5, 947) == nil,
    "dungeon instance coordinates never become outdoor or world pins")
check(Geo.ProjectToMap(37, 0.5, 0.5, 12) == nil, "projection refuses another continent")
check(Geo.ProjectToMap(7777, 0.5, 0.5, 947) == nil, "orphan without a continent cannot project onto the world")
check(Geo.ProjectToMap(37, -0.1, 0.5, 37) == nil and Geo.ProjectToMap(37, 0.5, 1.1, 13) == nil,
    "out-of-range source coordinates are refused")
check(Geo.ProjectToMap(37, nil, 0.5, 37) == nil and Geo.ProjectToMap(37, 0/0, 0.5, 37) == nil,
    "missing and NaN coordinates are refused")
check(Geo.ProjectToMap(nil, 0.5, 0.5, 37) == nil and Geo.ProjectToMap(37, 0.5, 0.5, nil) == nil,
    "missing map IDs are refused")

-- A geometrically unsuitable ancestor must not win just because it is in
-- the tree; advance to the next ancestor where all stops actually fit.
M.maps[11100] = { mapID = 11100, name = "Outside Elwynn", mapType = 5, parentMapID = 37,
    cont = 0, top = 800, left = 800, w = 100, h = 100 }
common({ point(37), point(11100) }, 13, 2, "a too-small common ancestor advances to the continent")
M.maps[11101] = { mapID = 11101, name = "Positionless map", mapType = 3, parentMapID = 0 }
check(Geo.IsWorldMap(11101), "missing yard geometry also identifies world-style maps")

-- Malformed map trees must terminate, including a chain longer than the cap.
M.maps[11200] = { mapID = 11200, mapType = 5, parentMapID = 11201 }
M.maps[11201] = { mapID = 11201, mapType = 5, parentMapID = 11200 }
chain = Geo.ParentChain(11200)
check(#chain == 2 and chain[1] == 11200 and chain[2] == 11201, "parent cycles terminate without repeated IDs")
for id = 11300, 11320 do
    M.maps[id] = { mapID = id, mapType = 5, parentMapID = id + 1 }
end
chain = Geo.ParentChain(11300)
check(#chain == 13 and chain[13] == 11312, "parent traversal stops after twelve hops")

local getRect = C_Map.GetMapRectOnMap
C_Map.GetMapRectOnMap = nil
common({ point(37), point(1) }, 37, 1, "missing rectangles fall back to MainMap on a tie")
common({ point(1), point(37), point(1, 0.2, 0.8) }, 1, 2, "missing rectangles count stops on the most-used map")
common({ point(37), point(52) }, 13, 2, "missing rectangles do not affect continent previews")
check(Geo.ProjectToMap(37, 0.5, 0.5, 947) == nil, "missing rectangle API refuses world projection")
C_Map.GetMapRectOnMap = function() error("rectangle unavailable") end
common({ point(37), point(1) }, 37, 1, "throwing rectangles are caught and fall back")
check(Geo.ProjectToMap(37, 0.5, 0.5, 947) == nil, "throwing rectangle API returns nil")
C_Map.GetMapRectOnMap = function() return 0.55, nil, 0.10, 0.90 end
check(Geo.ProjectToMap(37, 0.5, 0.5, 947) == nil, "incomplete rectangles are refused")
C_Map.GetMapRectOnMap = function() return 0.55, "bad", 0.10, 0.90 end
check(Geo.ProjectToMap(37, 0.5, 0.5, 947) == nil, "nonnumeric rectangles are refused")
C_Map.GetMapRectOnMap = function() return 0.95, 0.55, 0.10, 0.90 end
check(Geo.ProjectToMap(37, 0.5, 0.5, 947) == nil, "inverted rectangles are refused")
C_Map.GetMapRectOnMap = function() return 0.55, 0.55, 0.10, 0.90 end
check(Geo.ProjectToMap(37, 0.5, 0.5, 947) == nil, "zero-width rectangles are refused")
C_Map.GetMapRectOnMap = function() return 2, 3, 2, 3 end
check(Geo.ProjectToMap(37, 0.5, 0.5, 947) == nil, "off-map world projections are refused")
C_Map.GetMapRectOnMap = function(child, top)
    if child == 13 then return getRect(child, top) end
end
common({ point(37), point(1) }, 37, 1, "partial world coverage stays on MainMap when it shows no extra stops")
C_Map.GetMapRectOnMap = getRect

local fallback = C_Map.GetFallbackWorldMapID
C_Map.GetFallbackWorldMapID = nil
check(Geo.WorldMapID() == 947, "missing fallback API uses 947")
C_Map.GetFallbackWorldMapID = function() error("world unavailable") end
check(Geo.WorldMapID() == 947, "throwing fallback API uses 947")
C_Map.GetFallbackWorldMapID = function() return 0 end
check(Geo.WorldMapID() == 947, "invalid fallback ID uses 947")
C_Map.GetFallbackWorldMapID = function() return 900 end
check(Geo.WorldMapID() == 900, "valid fallback ID is not hard-coded")
C_Map.GetFallbackWorldMapID = fallback

local worldPos, mapPos, mapInfo = C_Map.GetWorldPosFromMapPos, C_Map.GetMapPosFromWorldPos, C_Map.GetMapInfo
C_Map.GetWorldPosFromMapPos = nil
check(Geo.ProjectToMap(37, 0.5, 0.5, 13) == nil, "missing world position API refuses translation")
common({ point(37), point(1) }, 37, 1, "missing world geometry still gives a main area preview")
C_Map.GetWorldPosFromMapPos = worldPos
C_Map.GetMapPosFromWorldPos = nil
check(Geo.ProjectToMap(37, 0.5, 0.5, 947) == nil, "missing inverse position API refuses world projection")
C_Map.GetMapPosFromWorldPos = mapPos
C_Map.GetMapInfo = nil
check(#Geo.ParentChain(11400) == 1 and Geo.ContinentID(11400) == nil, "missing map info API has a finite fallback")
C_Map.GetMapInfo = function() error("info unavailable") end
check(#Geo.ParentChain(11401) == 1, "throwing map info API has a finite fallback")
C_Map.GetMapInfo = mapInfo

-- Load a fresh Geo without Enum or the vector constructor. Restore the mock's
-- constructor afterwards because its API returns vectors through that global.
local enum, vector = Enum, CreateVector2D
Enum, CreateVector2D = nil, nil
local bareNS = { L = ns.L, Num = ns.Num, XY = ns.XY }
assert(loadfile("WaypointTracker/Geo.lua"))("WaypointTracker", bareNS)
Enum, CreateVector2D = enum, vector
local bareMap, bareShown = bareNS.Geo.CommonMap({ point(37), point(1) })
check(bareMap == 947 and bareShown == 2, "enum and plain-table vector fallbacks support world previews")
check(#M.errors == 0, "no reported Lua errors")
print(("%d passed, %d failed"):format(passed, failed))
os.exit((failed == 0 and #M.errors == 0) and 0 or 1)
