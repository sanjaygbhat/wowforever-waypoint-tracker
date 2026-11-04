-- Detail-pane route maps. Run from the repository root with Lua 5.1.
-- --bare removes optional art, clipping and line APIs; plain vectors work too.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local bare = arg and arg[1] == "--bare"
if bare then
    C_MapExplorationInfo = nil
    local create = CreateFrame
    function CreateFrame(...)
        local frame = create(...)
        -- The mock turns unknown method names into no-ops. False makes these
        -- two absent methods detectable without changing the shared mock.
        frame.CreateLine, frame.SetClipsChildren = false, false
        return frame
    end
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function close(a, b) return a and b and math.abs(a - b) < 1e-8 end
local function point(m, x, y, t) return { m = m, x = x or 0.5, y = y or 0.5, t = t } end
local function route(pts, mode) return { name = "A route", pts = pts, mode = mode or "order" } end
local function move(m, x, y)
    local info = M.maps[m]
    M.player.inst = info.cont
    M.player.wx = info.top - (y or 0.5) * info.h
    M.player.wy = info.left - (x or 0.5) * info.w
end

local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local RM, L = ns.RouteMap, ns.L

local art = RM.Art(37)
check(art and art.w == 1002 and art.h == 668, "art keeps the layer's pixel dimensions")
check(art and #art.tiles == (bare and 12 or 16), "base tiles plus explored tiles")
for row = 1, 3 do
    for col = 1, 4 do
        local i = (row - 1) * 4 + col
        local tile = art.tiles[i]
        check(tile.file == 37000 + i and tile.x == (col - 1) * 256 and tile.y == (row - 1) * 256
            and tile.w == 256 and tile.h == 256 and tile.tcx == 1 and tile.tcy == 1,
            "base tile " .. i .. " is row-major and retains its overhang")
    end
end
check(RM.Art(37) == art, "art is cached")
local retainedArt = setmetatable({ RM.Art(1) }, { __mode = "v" })
collectgarbage("collect")
check(retainedArt[1] and RM.Art(1) == retainedArt[1], "art cache survives garbage collection without a caller reference")
if not bare then
    local a, b, c, d = unpack(art.tiles, 13, 16)
    check(a.file == 9001 and a.x == 100 and a.y == 50 and a.w == 256 and a.h == 256,
        "explored first tile has the correct file and offset")
    check(b.file == 9002 and b.x == 356 and b.y == 50 and b.w == 44 and close(b.tcx, 44 / 64),
        "explored last column crops its padded file")
    check(c.file == 9003 and c.y == 306 and c.h == 14 and close(c.tcy, 14 / 16),
        "explored last row crops its padded file")
    check(d.file == 9004 and d.x == 356 and d.y == 306 and d.w == 44 and d.h == 14,
        "explored corner uses row-major order")
    M.explored[52] = {
        { textureWidth = 256, textureHeight = 256, offsetX = 0, offsetY = 0,
          fileDataIDs = { 9101 }, isDrawOnTopLayer = true },
        { textureWidth = 20, textureHeight = 20, fileDataIDs = { 9102 }, isShownByMouseOver = true },
    }
    local westfall = RM.Art(52)
    check(#westfall.tiles == 13 and westfall.tiles[13].top and westfall.tiles[13].tcx == 1
        and westfall.tiles[13].tcy == 1, "full overlay tile has no crop; top layer and mouseover are respected")
end
M.maps[291].noArt = true
check(RM.Art(291) == nil, "noArt uses the fallback")
M.maps[291].noArt = nil
check(RM.Art(nil) == nil and RM.Art(99999) == nil, "missing maps have no art")
local artID = C_Map.GetMapArtID
C_Map.GetMapArtID = function(id) return artID(id) + 1 end
check(RM.Art(37) ~= art, "phased art ID is part of the cache key")
C_Map.GetMapArtID = artID

local pts = { point(37, 0.2, 0.2, "First"), point(37, 0.6, 0.4, "Second"),
    point(37, 0.8, 0.7, L.ROUTE_STOP_END:format("Farmer")) }
local r = route(pts)
local parent = CreateFrame("Frame", nil, UIParent)
local map = RM.Create(parent, 290, 160)
check(not map:IsShown() and #map.pins == 0 and #map.lines == 0, "new widget is empty and hidden")
check(not map.captionBg:IsShown(), "empty widget hides the caption backing")
check(map.art.Tiles:GetParent() == map.art and map.art.Tiles:GetFrameLevel() == map.art:GetFrameLevel(),
    "tile child keeps background art below grid, name and route lines")
map:SetRoute(r)
check(map:IsShown() and map:GetMapID() == 37 and map.shown == #pts and #map.pins == #pts,
    "area route has one pin per stop")
check(map.pins[1].Icon:GetTexture() == "Interface\\COMMON\\Indicator-Green", "start pin is green")
check(map.pins[2].Icon:GetTexture() == "Interface\\COMMON\\Indicator-Yellow", "ordinary stop is yellow")
check(map.pins[3].Icon:GetTexture() == "Interface\\COMMON\\Indicator-Gray", "hand-in stop is grey")
check(map.pins[1].Number:GetText() == "1" and map.pins[1].Number:IsShown(), "start pin has its number")
check(map.pins[1].Number._drawLayer and map.pins[1].Number._drawLayer[2] > 2,
    "numbers render above their pin textures")
check(map.pins[3].Number._textColor[1] == 1 and map.pins[1].Number._textColor[1] == 0,
    "numbers contrast with their indicators")
check(close(map.art:GetWidth(), 240) and close(map.art:GetHeight(), 160),
    "art fills the height while preserving its aspect")
check(#map.lines == (bare and 0 or #pts - 1), "ordered route draws adjacent legs when lines are supported")
check(not map.elsewhere:IsShown(), "fully shown route has no elsewhere line")
check(map.caption:GetText() == (bare and L.ROUTE_PREVIEW_NO_ART:format("Elwynn Forest")
    or "Elwynn Forest \194\183 " .. L.ROUTE_PREVIEW_OPEN), "caption follows the art availability")
check(map.captionBg:IsShown() and map.captionBg:GetParent() == map.caption:GetParent()
    and map.captionBg:GetHeight() == 16 and map.captionBg._colorTexture[1] == 0
    and map.captionBg._colorTexture[2] == 0 and map.captionBg._colorTexture[3] == 0
    and map.captionBg._colorTexture[4] == 0.55, "caption has a translucent black strip on its overlay")
local _, backingAnchor, backingPoint = map.captionBg:GetPoint()
local _, captionAnchor, captionPoint = map.caption:GetPoint()
check(backingAnchor == map.art and backingPoint == "BOTTOMRIGHT"
    and captionAnchor == map.art and captionPoint == "BOTTOMRIGHT", "caption and backing follow the letterboxed art")
local tileTextures, tileBackground = {}, nil
for _, tex in ipairs(M.frames) do
    if tex:IsObjectType("Texture") and tex:GetParent() == map.art.Tiles then
        if tex:GetTexture() then tileTextures[#tileTextures + 1] = tex else tileBackground = tex end
    end
end
check(tileBackground and tileBackground._colorTexture[1] == 0.08
    and tileBackground._colorTexture[4] == 1, "base background belongs to the clipped tile child")
check(#tileTextures == (bare and 0 or #map.artData.tiles), "all base and explored textures belong to the tile child")
if not bare then
    check(map.art._clipsChildren == true, "art frame clips the child containing its tile textures")
    for i, tex in ipairs(tileTextures) do
        check(tex:GetParent() == map.art.Tiles and tex:GetTexture() == map.artData.tiles[i].file,
            "tile texture " .. i .. " is on the clipped child")
    end
    local line = map.lines[1]
    check(close(line._start[3], 0.2 * map.art:GetWidth()) and close(line._end[4], -0.4 * map.art:GetHeight())
        and line:GetThickness() == 2 and line:GetAlpha() == 0.85, "lines use scaled pixel anchors and gold opacity")
end

r.mode = "loop"
map:SetRoute(r)
check(#map.lines == (bare and 0 or #pts), "loop includes the closing leg")
if not bare then check(map.lines[#map.lines]:GetAlpha() == 0.4, "closing leg is fainter") end
for i, tex in ipairs(tileTextures) do
    check(tex:IsShown() and tex:GetParent() == map.art.Tiles, "tile texture " .. i .. " is reused on the clipped child")
end
local oldPins, oldLines = {}, {}
for i, pin in ipairs(map.pins) do oldPins[i] = pin end
for i, line in ipairs(map.lines) do oldLines[i] = line end
r.mode = "nearest"
map:SetRoute(r)
check(#map.lines == 0, "nearest has no implied ordering")
for i, pin in ipairs(map.pins) do check(pin == oldPins[i], "pin " .. i .. " is pooled") end
for i, line in ipairs(oldLines) do check(not line:IsShown(), "unused line " .. i .. " is hidden") end

local clickRoute, clickMap
map.onClick = function(clicked, id) clickRoute, clickMap = clicked, id end
map:GetScript("OnClick")(map, "LeftButton")
check(clickRoute == r and clickMap == 37, "box click forwards route and map")
clickRoute = nil
map.pins[2]:GetScript("OnClick")(map.pins[2], "LeftButton")
check(clickRoute == r and clickMap == 37, "pin click forwards route and map")
clickRoute = nil
map:GetScript("OnClick")(map, "RightButton")
check(clickRoute == nil, "right click does not activate the preview")
map.pins[1]:GetScript("OnEnter")(map.pins[1])
check(M.tooltip[1] == L.ROUTE_STOP_N:format(1, "First") and M.tooltip[2] == L.ROUTE_PREVIEW_START,
    "start tooltip names the stop and explains the green pin")
M.tooltip = {}
map.pins[2]:GetScript("OnEnter")(map.pins[2])
check(M.tooltip[2] == "Elwynn Forest  60.0, 40.0", "stop tooltip has its original area and coordinates")
M.tooltip = {}
map:GetScript("OnEnter")(map)
check(M.tooltip[1] == L.ROUTE_PREVIEW_TOOLTIP, "box tooltip explains the action")
map:GetScript("OnLeave")(map)

move(37)
M.player.facing = 0.7
map:Refresh()
check(map.player:IsShown() and map.player._rotation == 0.7, "player arrow appears and rotates on this map")
move(1)
map:Refresh()
check(not map.player:IsShown(), "player on Durotar is absent from Elwynn preview")
M.player.noPosition = true
map:Refresh()
check(not map.player:IsShown(), "unavailable player position hides the arrow")
M.player.noPosition = false

local world = route({ point(37), point(1) })
map:SetRoute(world)
check(map:GetMapID() == 947 and #map.pins == 2 and not map.elsewhere:IsShown(),
    "two continents show on the world map without an elsewhere warning")
move(37)
map:Refresh()
check(map.player:IsShown(), "player projects onto the world map")
map:SetRoute(route({ point(37), point(52) }))
check(map:GetMapID() == 13 and #map.pins == 2, "two zones share their continent map")
map:SetRoute(route({ point(52), point(291) }))
check(map:GetMapID() == 52 and #map.pins == 1 and map.shown == 1 and map.elsewhere:IsShown()
    and map.elsewhere:GetText():find("1", 1, true) and map.elsewhere:GetText():find("The Deadmines", 1, true),
    "mixed dungeon route reports its unshown stop")
check(#map.lines == 0, "lines never connect across an unprojected stop")
map:SetRoute(route({ point(52, 0.2, 0.2), point(291), point(52, 0.7, 0.7) }))
check(#map.lines == 0, "ordered route does not bridge an unshown middle stop")

local overlap = route({ point(37, 0.5, 0.5), point(37, 0.501, 0.501), point(37, 0.9, 0.9) })
map:SetRoute(overlap)
check(map.pins[1].Number:IsShown() and not map.pins[2].Number:IsShown() and map.pins[3].Number:IsShown(),
    "nearby later labels hide while separated labels remain")
local many = {}
for i = 1, 201 do many[i] = point(37, (i % 20) / 20, math.floor(i / 20) / 20) end
map:SetRoute(route(many, "loop"))
check(#map.pins == 201 and #map.lines == (bare and 0 or 200), "large routes pool pins and cap line segments")
check(not map.pins[1].Number:IsShown() and not map.pins[40].Number:IsShown(), "large routes hide all labels")

local unordered = route({ point(37, 0.8, 0.8), point(37, 0.2, 0.2), point(37, 0.6, 0.3) }, "loop")
unordered.unordered = true
map:SetRoute(unordered)
check(not unordered.unordered and unordered.pts[1].x == 0.2 and map.pins[1].index == 1,
    "ready-made loops are prepared before numbering")
local common, calls = ns.Geo.CommonMap, 0
ns.Geo.CommonMap = function(points) calls = calls + 1; return common(points) end
local cached = route({ point(37) })
local id, shown = RM.MapFor(cached)
RM.MapFor(cached)
check(id == 37 and shown == 1 and calls == 1, "map selection is cached per route")
ns.Geo.CommonMap = common
check(RM.MapFor(nil) == nil, "nil route has no map")

if not bare then
    local getLayers = C_Map.GetMapArtLayers
    C_Map.GetMapArtLayers = function() error("unavailable") end
    check(RM.Art(18) == nil, "throwing art API falls back")
    map:SetRoute(route({ point(18) }))
    check(#map.pins == 1 and map.artData == nil and map.caption:GetText() == L.ROUTE_PREVIEW_NO_ART:format("Tirisfal Glades"),
        "fallback panel retains projected pins")
    check(map.captionBg:IsShown(), "fallback caption keeps its backing strip")
    C_Map.GetMapArtLayers = getLayers
    local create = CreateFrame
    CreateFrame = function(...)
        local frame = create(...)
        frame.CreateLine, frame.SetClipsChildren = false, false
        return frame
    end
    local fallback = RM.Create(parent, 290, 160)
    CreateFrame = create
    fallback:SetRoute(r)
    check(fallback.artData == nil and #fallback.pins == 3 and #fallback.lines == 0,
        "missing clipping and lines build the fallback with pins")
    fallback:SetRoute(nil)
end

M.player.combat = true
local blocked = M.actionBlocked or 0
map:SetRoute(r)
map:Refresh()
check(map:IsShown() and #map.pins == 3 and (M.actionBlocked or 0) == blocked, "pane preview works in combat")
M.player.combat = false
local heldPins, heldLines = {}, {}
for i, pin in ipairs(map.pins) do heldPins[i] = pin end
for i, line in ipairs(map.lines) do heldLines[i] = line end
map:SetRoute(nil)
check(not map:IsShown() and not map.art:IsShown() and not map.player:IsShown()
    and not map.caption:IsShown() and not map.captionBg:IsShown() and not map.elsewhere:IsShown() and #map.pins == 0 and #map.lines == 0
    and map.route == nil and map:GetMapID() == nil, "clearing the route hides everything and clears active arrays")
for i, pin in ipairs(heldPins) do check(not pin:IsShown() and pin.route == nil, "cleared pin " .. i .. " releases its route") end
for i, line in ipairs(heldLines) do check(not line:IsShown(), "cleared line " .. i .. " is hidden") end
for i, tex in ipairs(tileTextures) do
    check(not tex:IsShown() and tex:GetTexture() == nil, "cleared tile texture " .. i .. " releases its file")
end
map:Refresh()
check(not map.player:IsShown(), "refresh after clearing stays empty")
map:SetRoute(route({}))
check(not map:IsShown() and #map.pins == 0, "empty route is hidden")
check(#M.errors == 0, "no reported Lua errors")

print(("RouteMap%s: %d passed, %d failed"):format(bare and " (bare)" or "", passed, failed))
if failed > 0 then os.exit(1) end
