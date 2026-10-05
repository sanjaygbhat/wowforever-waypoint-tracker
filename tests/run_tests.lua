-- Loads the whole addon against the fake WoW API and plays through the
-- things a player does. Run from the repository root:
--     lua5.1 tests/run_tests.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end
local function near(a, b, eps)
    return a and b and math.abs(a - b) <= (eps or 1e-6)
end

-- someone updating from an early test build with its old defaults saved
WaypointTrackerDB = { version = 1, settings = { arrowAlpha = 1.0, fadeOnCourse = false, arrowLocked = true, arrowPos = { "CENTER", "CENTER", 0, 230 } } }

searchTime, searchSpeed = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")

local Geo, WP, L = ns.Geo, ns.WP, ns.L
check(ns.settings ~= nil, "settings created")
check(ns.Get("arrowAlpha") == 0.8 and ns.Get("fadeOnCourse") == true, "old settings moved to the new softer defaults")
check(ns.Get("arrowPos") == nil and ns.settings.arrowLocked == nil, "arrow moved back over the character")
check(WaypointTrackerDB.version == 2, "settings version 2")
check(ns.Arrow.frame:IsMouseEnabled() == false, "arrow ignores the mouse (right-click to attack works)")
check(SlashCmdList.WAYPOINTTRACKER ~= nil, "/wp registered")
check(SlashCmdList.WAYPOINTTRACKERWAY ~= nil, "/way registered without TomTom")
check(TomTom and TomTom.isWaypointTrackerBridge, "TomTom bridge installed")

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------
local z, x, y, rest = Geo.ParseWayArgs("Elwynn Forest 42.5 65.3 Goldshire Inn")
check(z == "Elwynn Forest" and x == 42.5 and y == 65.3 and rest == "Goldshire Inn", "parse zone + coords + name")
z, x, y = Geo.ParseWayArgs("45,2 67,8")
check(z == "" and near(x, 45.2) and near(y, 67.8), "parse European decimals")
z, x, y = Geo.ParseWayArgs("45.2, 67.8")
check(near(x, 45.2) and near(y, 67.8), "parse comma+space")
z, x, y = Geo.ParseWayArgs("45.2,67.8")
check(near(x, 45.2) and near(y, 67.8), "parse dotted pair")
z, x, y = Geo.ParseWayArgs("45,67")
check(x == 45 and y == 67, "parse integer pair with comma")
z, x, y = Geo.ParseWayArgs("#52 10 20 Sentinel Hill")
check(z == "#52" and x == 10 and y == 20, "parse #mapID")
check(Geo.ParseWayArgs("Elwynn Forest") == nil, "no coords -> nil")
check(Geo.ParseWayArgs("Elwynn 120 50") == nil, "out of range -> nil")

check(Geo.FindZone("elwynn") == 37, "find zone by prefix")
check(Geo.FindZone("ElwynnForest") == 37, "find zone ignoring spaces")
check(Geo.FindZone("westfall") == 52, "find exact zone")
check(Geo.FindZone("storm") == 84, "find Stormwind")
check(Geo.FindZone("ÉLAN") == 1411, "accented upper case matches")
local none, sugg = Geo.FindZone("zzz")
check(none == nil and #sugg == 0, "unknown zone")

-- the zone list: every map with its own coordinates, found even when the map
-- tree doesn't lead to it; phased copies shown once; no dungeon maps
local names = {}
for _, z in ipairs(Geo.GetZoneList()) do
    names[z.name] = (names[z.name] or 0) + 1
end
check(names["Tirisfal Glades"] == 1, "Tirisfal Glades listed once")
check(names["Deathknell"] == 1, "small maps inside zones are listed")
check(names["Forever Isle"] == 1, "zones outside the map tree are found")
check(names["The Deadmines"] == nil, "dungeon maps are not offered")
check(names["Eastern Kingdoms"] == nil, "continents are not offered")
local tir = Geo.SearchZones("Trisifal")
check(tir[1] and tir[1].name == "Tirisfal Glades", "typo 'Trisifal' finds Tirisfal Glades")
local id, guessed = Geo.FindZone("trisifal glades")
check(id == 18 and guessed == true, "FindZone fixes the typo (got " .. tostring(id) .. ")")
check(Geo.SearchZones("tiris")[1].name == "Tirisfal Glades", "prefix search")
check(Geo.SearchZones("glades")[1].name == "Tirisfal Glades", "search by a later word")
local dk = Geo.SearchZones("deathknell")[1]
check(dk and Geo.ZoneSubtitle(dk) == "Tirisfal Glades", "small map shows the zone it belongs to")
check(Geo.EditDistance("trisifal", "tirisfal") == 2, "edit distance with swapped letters")

-- ---------------------------------------------------------------------------
-- Adding a waypoint and following the arrow
-- ---------------------------------------------------------------------------
-- player in Elwynn at 40, 60
M.player.wx, M.player.wy, M.player.inst, M.player.facing = -1200, -1200, 0, 0
SlashCmdList.WAYPOINTTRACKERWAY("Elwynn Forest 50 50 Test Spot")
check(WP.Count() == 1, "waypoint added by /way")
local wp = WP.GetActive()
check(wp and wp.m == 37 and near(wp.x, 0.5) and wp.title == "Test Spot", "waypoint fields")

M.Tick(0.3)
local arrowFrame = ns.Arrow.frame
check(arrowFrame:IsShown(), "arrow shown")
-- target is 200 yds north and 300 yds east: 56 degrees to the right
local dist, bearing = Geo.GetVector(wp)
check(near(dist, math.sqrt(200 * 200 + 300 * 300), 0.01), "distance correct")
local rel = Geo.RelativeAngle(bearing, 0)
local idx = math.floor(rel / (2 * math.pi) * 100 + 0.5) % 100
check(idx == 84, "arrow frame points north-east (got " .. idx .. ")")

-- facing east: the target is now slightly to the left
M.player.facing = -math.pi / 2 -- east
rel = Geo.RelativeAngle(bearing, -math.pi / 2)
local deg = math.deg(rel)
check(deg > 30 and deg < 40, "facing east, target is ~34 degrees left (got " .. deg .. ")")

-- colours: far = red, close = green
local r, g = ns.Arrow.Gradient(ns.Arrow.DistanceFraction(360, 360))
check(r > 0.9 and g < 0.4, "far is red")
r, g = ns.Arrow.Gradient(ns.Arrow.DistanceFraction(5, 360))
check(g > 0.9 and r < 0.4, "close is green")
r, g = ns.Arrow.Gradient(ns.Arrow.DistanceFraction(180, 360))
check(r > 0.9 and g > 0.8, "halfway is yellow")

-- walk to within arrival distance
M.player.wx, M.player.wy = -1000 - 3, -1500 + 4
M.Tick(0.5)
check(WP.Count() == 0, "waypoint removed on arrival")
check(#M.sounds > 0, "arrival sound played")
M.Tick(4)
check(not arrowFrame:IsShown(), "arrow hides after arriving")

-- ---------------------------------------------------------------------------
-- Several waypoints, closest, cross-continent, removing
-- ---------------------------------------------------------------------------
M.player.wx, M.player.wy = -1200, -1200
local a = WP.Add(37, 0.45, 0.62, { title = "Near" })
local b = WP.Add(52, 0.5, 0.5, { title = "Far" })
local c = WP.Add(1, 0.5, 0.5, { title = "Other continent" })
check(WP.GetActive() == c, "newest waypoint is active")
M.Tick(0.2)
check(ns.Arrow.frame:IsShown(), "arrow shown for other continent")
check(WP.Closest() == a, "closest waypoint")
WP.SetClosest(true)
check(WP.GetActive() == a, "set closest")
WP.Remove(a, true)
check(WP.GetActive() == b, "removing active moves to next closest")
check(WP.Add(52, 0.5, 0.5, { title = "Far" }) == b, "duplicate waypoint reused")

-- chat commands
SlashCmdList.WAYPOINTTRACKER("list")
SlashCmdList.WAYPOINTTRACKER("here Camp")
check(WP.GetActive().title == "Camp", "/wp here")
SlashCmdList.WAYPOINTTRACKER("clear")
check(WP.GetActive() ~= nil and WP.GetActive().title ~= "Camp", "/wp clear removes active")
SlashCmdList.WAYPOINTTRACKER("Nowhere Land 10 10")
check(M.printed[#M.printed]:find("Nowhere Land", 1, true) ~= nil, "unknown zone message")
SlashCmdList.WAYPOINTTRACKER("Trisifal Glades 50 50 Brill")
check(WP.GetActive().m == 18 and WP.GetActive().title == "Brill", "/wp with a typo in the zone")
check(M.printed[#M.printed - 1]:find("Tirisfal Glades", 1, true) ~= nil, "tells you which zone it used")
SlashCmdList.WAYPOINTTRACKER("#52 30 40")
check(WP.GetActive().m == 52, "/wp #mapID")
SlashCmdList.WAYPOINTTRACKER("arrow")
check(ns.Get("arrowShown") == false, "/wp arrow toggles off")
SlashCmdList.WAYPOINTTRACKER("arrow")
check(ns.Get("arrowShown") == true, "/wp arrow toggles on")
SlashCmdList.WAYPOINTTRACKERWAYB("Back")
check(WP.GetActive().title == "Back", "/wayb")
SlashCmdList.WAYPOINTTRACKERCWAY("")
SlashCmdList.WAYPOINTTRACKER("help")

-- ---------------------------------------------------------------------------
-- TomTom bridge (how quest addons send waypoints)
-- ---------------------------------------------------------------------------
local uid = TomTom:AddWaypoint(52, 0.3, 0.4, { title = "Quest Target", persistent = false })
check(TomTom:IsValidWaypoint(uid), "bridge waypoint valid")
check(TomTom:WaypointExists(52, 0.3, 0.4, "Quest Target"), "bridge WaypointExists")
check(type(TomTom:GetDistanceToWaypoint(uid)) == "number", "bridge distance")
TomTom:SetCrazyArrow(uid)
check(WP.GetActive() == uid, "bridge SetCrazyArrow")
TomTom:RemoveWaypoint(uid)
check(not TomTom:IsValidWaypoint(uid), "bridge remove")
check(TomTom:SomeFutureTomTomFunction() == nil, "unknown TomTom calls are harmless")
check(TomTom:RemoveWaypoint({}) == false, "removing a stranger's table is harmless")
local fired = false
local uid2 = TomTom:AddWaypoint(37, 0.40, 0.605, { title = "cb", callbacks = { distance = { [50] = function()
    fired = true
end } } })
TomTom:SetCrazyArrow(uid2)
M.Tick(0.3)
check(fired, "bridge distance callback fires")

-- ---------------------------------------------------------------------------
-- World map
-- ---------------------------------------------------------------------------
WorldMapFrame:Show()
WorldMapFrame.mapID = 37
ns.Fire("WAYPOINTS_CHANGED")
local provider = WorldMapFrame.providers[1]
check(provider ~= nil, "map data provider added")
local onElwynn = #WorldMapFrame.pins
check(onElwynn >= 1, "pins on Elwynn map (" .. onElwynn .. ")")
WorldMapFrame.mapID = 13
provider:RefreshAllData()
check(#WorldMapFrame.pins > onElwynn, "more pins on the continent map")
local pin = WorldMapFrame.pins[1]
pin:OnMouseEnter()
pin:OnClick("LeftButton")
check(WP.GetActive() == pin.wp, "clicking a pin points the arrow there")
M.shift = true
local before = WP.Count()
pin:OnClick("LeftButton")
M.shift = false
check(WP.Count() == before, "shift-click no longer removes a pin")
M.alt = true
pin:OnClick("LeftButton")
M.alt = false
check(WP.Count() == before - 1, "alt-click removes pin")

-- Ctrl + Right-click on the continent map adds a zone waypoint
M.ctrl = true
local cx, cy = (4000 - -1300) / 12000, (4000 - -1000) / 16000 -- a spot inside Elwynn
check(WorldMapFrame:ClickCanvas("RightButton", cx, cy), "ctrl+right-click handled")
M.ctrl = false
local added = WP.GetActive()
check(added.m == 37, "map click converted to the zone (got " .. tostring(added.m) .. ")")
check(not WorldMapFrame:ClickCanvas("RightButton", cx, cy), "plain right-click not taken")
M.Tick(0.3) -- coordinates text update

-- opening the map in combat must not call protected functions
M.player.combat = true
provider:RefreshAllData()
M.ctrl = true
WorldMapFrame:ClickCanvas("RightButton", cx, cy)
M.ctrl = false
M.player.combat = false

-- turning the map coordinates off and on again
local coordsFrame
for _, f in ipairs(M.frames) do
    if f._parent == WorldMapFrame.ScrollContainer and f._scripts.OnUpdate then
        coordsFrame = f
    end
end
ns.Set("worldCoords", false)
check(coordsFrame and not coordsFrame:IsShown(), "map coordinates hide")
ns.Set("worldCoords", true)
check(coordsFrame:IsShown(), "map coordinates come back")
WorldMapFrame:Hide()

-- ---------------------------------------------------------------------------
-- Minimap pins
-- ---------------------------------------------------------------------------
WP.ClearAll(true)
WP.Add(37, 0.41, 0.61, { title = "Close by" }) -- ~36 yds
WP.Add(52, 0.5, 0.9, { title = "Far away" })
M.Tick(0.2)
local shownPins = 0
for _, f in ipairs(M.frames) do
    if f._parent == Minimap and f._kind == "Button" and f.wp and f:IsShown() then
        shownPins = shownPins + 1
    end
end
check(shownPins == 2, "one minimap pin in range + active one on the edge (got " .. shownPins .. ")")
ns.Set("minimapEdge", false)
M.Tick(0.2)
shownPins = 0
for _, f in ipairs(M.frames) do
    if f._parent == Minimap and f._kind == "Button" and f.wp and f:IsShown() then
        shownPins = shownPins + 1
    end
end
check(shownPins == 1, "edge pin hidden when turned off (got " .. shownPins .. ")")
ns.Set("minimapEdge", true)
M.cvars.rotateMinimap = "1"
M.Tick(0.2)
M.cvars.rotateMinimap = "0"

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
WaypointTracker_ToggleWindow()
check(WaypointTrackerFrame and WaypointTrackerFrame:IsShown(), "window opens")
local w = ns.UI.widgets
check(w.zone:GetText() == "Elwynn Forest", "zone box starts at your zone")
w.zone:SetFocus()
w.zone:Type("west")
check(w.zoneList:IsShown(), "zone list shows while typing")
check(w.zoneList.buttons[1].result.zone.id == 52, "Westfall suggested")
w.zone:RunScript("OnEnterPressed")
check(w.zone:GetText() == "Westfall", "zone picked with Enter")
w.x:Type("45.5 60.25")
check(w.x:GetText() == "45.5" and w.y:GetText() == "60.25", "pasting 'x y' fills both boxes")
w.note:Type("Sentinel Hill")
local count = WP.Count()
w.set:Click()
check(WP.Count() == count + 1 and WP.GetActive().title == "Sentinel Hill", "Set Waypoint button")
check(near(WP.GetActive().x, 0.455) and near(WP.GetActive().y, 0.6025), "coords from boxes")
w.x:Type("45,5")
check(w.x:GetText() == "45,5", "European decimal stays in X")
w.y:Type("20")
w.set:Click()
check(near(WP.GetActive().x, 0.455), "European decimal accepted")
w.x:Type("150")
w.y:Type("20")
count = WP.Count()
w.set:Click()
check(WP.Count() == count, "bad coords rejected")
w.here:Click()
check(w.zone:GetText() == "Elwynn Forest" and w.x:GetText() == "40.0", "Use My Position")
M.Tick(0.6)
local row = w.rows[1]
check(row:IsShown() and row.wp ~= nil, "list rows show waypoints")
row:Click()
row.remove:Click()

-- more options
w.more:Click()
check(WaypointTrackerOptionsFrame and WaypointTrackerOptionsFrame:IsShown(), "more options opens")
for _, cb in ipairs(ns.UI.allChecks) do
    -- (treasure hunt loads the database when it starts; it's tested on its own)
    if cb.settingKey and cb.settingKey ~= "showAdvanced" and cb.settingKey ~= "treasureHunt" then
        local was = ns.Get(cb.settingKey)
        cb:Click()
        M.Tick(0.1)
        cb:Click()
        check(ns.Get(cb.settingKey) == was, "toggle " .. cb.settingKey)
    end
end
ns.Set("colorMode", "direction")
M.Tick(0.1)
ns.Set("colorMode", "single")
M.Tick(0.1)
ns.Set("fadeOnCourse", true)
ns.Set("showETA", true)
ns.Set("useMetres", true)
M.player.wx = M.player.wx + 5
M.Tick(1.5)
ns.Set("hideInCombat", true)
M.player.combat = true
M.Tick(0.1)
check(not ns.Arrow.frame:IsShown(), "hidden in combat")
M.player.combat = false
M.Tick(0.1)
check(ns.Arrow.frame:IsShown(), "back after combat")

-- moving the arrow happens from the window only
w.move:Click()
check(ns.Arrow.moving and ns.Arrow.frame:IsMouseEnabled(), "Move Arrow lets you drag it")
ns.Arrow.frame:RunScript("OnDragStart")
ns.Arrow.frame:RunScript("OnDragStop")
check(type(ns.Get("arrowPos")) == "table", "new position saved")
w.move:Click()
check(not ns.Arrow.moving and not ns.Arrow.frame:IsMouseEnabled(), "Done: click-through again")
w.move:Click()
M.player.combat = true
M.FireEvent("PLAYER_REGEN_DISABLED")
check(not ns.Arrow.moving, "entering combat stops moving mode")
M.player.combat = false
w.reset:Click()
check(ns.Get("arrowPos") == nil, "Reset puts the arrow back")

-- places: quests, flight masters, dungeons and rares from the game's own data
M.Tick(11) -- let the places cache expire
local places = ns.Places.GetAll(true)
local kinds = {}
for _, p in ipairs(places) do
    kinds[p.name] = p.kind
end
check(kinds["The Fargodeep Mine"] == "quest", "quest on the map found")
check(kinds["Report to Gryan"] == "turnin", "finished quest points to its turn-in")
check(kinds["Goldshire, Elwynn"] == "flight", "flight master found")
check(kinds["Orc Camp"] == nil, "other faction's flight master skipped")
check(kinds["The Deadmines"] == "dungeon", "dungeon entrance found")
check(kinds["Mother Fang"] == "rare", "rare on the map found")

w.zone:SetFocus()
w.zone:Type("")
local first = w.zoneList.buttons[1].result
check(first and first.here, "empty search starts with where you are")
check(w.zoneList.buttons[2].result.place and w.zoneList.buttons[2].result.place.kind ~= nil, "then your quests")
w.zone:Type("goldsh")
local hit
for _, b in ipairs(w.zoneList.buttons) do
    if b.result and b.result.place and b.result.place.name == "Goldshire, Elwynn" then
        hit = b
    end
end
check(hit ~= nil, "typing finds the flight master")
count = WP.Count()
hit:Click()
check(WP.Count() == count + 1 and WP.GetActive().title == "Goldshire, Elwynn", "picking a place sets the waypoint")
w.zone:SetFocus()
w.zone:Type("tri")
w.zone:RunScript("OnArrowPressed", "DOWN")
w.zone:RunScript("OnArrowPressed", "UP")
w.zone:RunScript("OnEnterPressed")
check(w.zone:GetText() == "Tirisfal Glades", "keyboard pick of a zone")

-- sharing
M.Tick(0.6)
local shareRow = w.rows[1]
check(shareRow.wp ~= nil, "row to share")
shareRow.share:Click()
local shareMenu = M.menus[#M.menus]
local labels = {}
for _, item in ipairs(shareMenu.items) do
    if item.text then
        labels[#labels + 1] = item.text
    end
end
check(table.concat(labels, ","):find(L.SHARE_PARTY, 1, true) and table.concat(labels, ","):find(L.SHARE_GUILD, 1, true), "share menu offers party and guild")
check(not table.concat(labels, ","):find(L.SHARE_RAID, 1, true), "no raid option when not in a raid")
local pinBefore = M.userWaypoint
count = WP.Count()
for _, item in ipairs(shareMenu.items) do
    if item.text == L.SHARE_PARTY then
        item.fn()
    end
end
check(M.chatText and M.chatText:find("^/party ") ~= nil, "chat opens on the party channel")
check(M.chatText:find("|Hworldmap:", 1, true) ~= nil, "message has a clickable map pin")
local function SamePin(a, b)
    if not a or not b then
        return a == b
    end
    return a.uiMapID == b.uiMapID and math.abs(a.position.x - b.position.x) < 0.0001 and math.abs(a.position.y - b.position.y) < 0.0001
end
check(SamePin(M.userWaypoint, pinBefore), "your own map pin is put back")
M.Tick(0.2)
check(WP.Count() == count, "sharing doesn't add a waypoint by itself")

-- share typed coordinates, or where you stand, without setting a waypoint
local function PickSay()
    local menu = M.menus[#M.menus]
    for _, item in ipairs(menu.items) do
        if item.text == L.SHARE_SAY then
            item.fn()
        end
    end
end
count = WP.Count()
w.zone:SetText("Westfall")
w.x:SetText("56.3")
w.y:SetText("47.1")
w.note:SetText("Sentinel Hill")
local menusBefore = #M.menus
w.share:Click()
check(#M.menus == menusBefore + 1, "Share opens the channel menu for typed coordinates")
M.chatText = nil
PickSay()
check(M.chatText and M.chatText:find("^/say Sentinel Hill: ") and M.chatText:find("56.3", 1, true), "typed coordinates go to chat (got " .. tostring(M.chatText) .. ")")
check(WP.Count() == count, "sharing typed coordinates doesn't set a waypoint")
w.x:SetText("")
w.y:SetText("")
w.note:SetText("")
w.share:Click()
M.chatText = nil
PickSay()
local myZone = Geo.GetMapName(C_Map.GetBestMapForUnit("player"))
check(M.chatText and M.chatText:find(myZone, 1, true), "empty X and Y share where you stand")
check(WP.Count() == count, "sharing your location doesn't set a waypoint")
w.x:SetText("150")
w.y:SetText("20")
menusBefore = #M.menus
w.share:Click()
check(#M.menus == menusBefore, "bad coordinates aren't shared")
w.x:SetText("")
w.y:SetText("")
w.zone:SetText("")
-- typed in the chat box, which the game empties and closes after the command
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "share Westfall 40 50 Camp")
M.Tick(0.1)
check(M.chatText and M.chatText:find("Camp: ", 1, true) and M.chatText:find("40.0", 1, true), "/wp share puts typed coordinates in chat (got " .. tostring(M.chatText) .. ")")
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "share Tirisfal Glades 62 66 Meet at the Ruins")
M.Tick(0.1)
check(M.chatText and M.chatText:find("Meet at the Ruins: ", 1, true), "/wp share with a zone name (got " .. tostring(M.chatText) .. ")")
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "share")
M.Tick(0.1)
check(M.chatText and M.chatText:find(myZone, 1, true), "/wp share alone shares where you stand")
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "share Here!")
M.Tick(0.1)
check(M.chatText and M.chatText:find("^Here!: ") and M.chatText:find(myZone, 1, true), "/wp share with a name shares where you stand (got " .. tostring(M.chatText) .. ")")
M.chatOpen, M.chatText = false, nil
WaypointTracker_ShareHere()
check(M.chatText and M.chatText:find(myZone, 1, true), "the key binding shares where you stand")
check(WP.Count() == count, "none of the share commands set a waypoint")
M.hasTarget = true
shareRow.share:Click()
local hasWhisper = false
for _, item in ipairs(M.menus[#M.menus].items) do
    if item.text and item.text:find("Tester", 1, true) then
        hasWhisper = true
    end
end
check(hasWhisper, "whisper your target")
M.hasTarget = false

-- Blizzard pin mirror
ns.Set("blizzardPin", true)
check(M.userWaypoint ~= nil, "game map pin placed")
ns.Set("blizzardPin", false)
check(M.userWaypoint == nil, "game map pin removed")

-- the game's own map pin (e.g. a map pin link clicked in chat) moves the arrow
M.Tick(1.2)
C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(37, 0.66, 0.33))
M.Tick(0.1)
check(WP.GetActive().title == L.MAP_PIN_NAME and WP.GetActive().m == 37, "arrow follows the game's map pin")
WP.Remove(WP.GetActive(), true)
check(M.userWaypoint == nil, "removing it clears the game's pin too")
M.Tick(0.1)

-- clicking a map pin link: the game places the pin, tracks it and opens the
-- map, and we only look once it has finished
local function ClickMapPinLink(m, x, y)
    local countBefore = WP.Count()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(m, x, y))
    check(WP.Count() == countBefore, "nothing of ours runs inside the game's link click")
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    M.Tick(0.1)
end
M.Tick(1.2)
ClickMapPinLink(18, 0.617, 0.521)
check(WP.GetActive().m == 18 and math.abs(WP.GetActive().x - 0.617) < 0.0001, "clicking a map pin link moves the arrow")
check(M.userWaypoint and M.userWaypoint.uiMapID == 18 and M.pinTracked, "the game's pin from the link stays set and tracked")
ns.Set("blizzardPin", true)
ClickMapPinLink(18, 0.62, 0.66)
check(WP.GetActive().m == 18 and math.abs(WP.GetActive().y - 0.66) < 0.0001, "the link moves the arrow with the game's pin option on")
check(M.userWaypoint and math.abs(M.userWaypoint.position.y - 0.66) < 0.0001 and M.pinTracked, "the game's pin stays on the link's spot")
-- sharing borrows the game's pin and puts yours back, still tracked
ns.Share.Message({ m = 37, x = 0.4, y = 0.5 })
check(M.userWaypoint and math.abs(M.userWaypoint.position.y - 0.66) < 0.0001 and M.pinTracked, "sharing puts your tracked pin back")
M.Tick(0.1)
check(math.abs(WP.GetActive().y - 0.66) < 0.0001, "sharing doesn't move the arrow")
ns.Set("blizzardPin", false)
for _, spot in ipairs({ 0.521, 0.66 }) do
    for _, have in ipairs(WP.List()) do
        if have.source == "mappin" and math.abs(have.y - spot) < 0.0001 then
            WP.Remove(have, true)
            break
        end
    end
end
M.Tick(0.1)
-- a pin of your own that we didn't place, then share: it comes back as it was
M.Tick(1.2)
C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(37, 0.25, 0.75))
C_SuperTrack.SetSuperTrackedUserWaypoint(true)
M.Tick(0.1)
local ownPin = M.userWaypoint
local shared = ns.Share.Message({ m = 18, x = 0.5, y = 0.5, title = "Here" })
check(shared:find("|Hworldmap:18:", 1, true) ~= nil, "sharing with your own game pin set makes the link")
check(SamePin(M.userWaypoint, ownPin) and M.pinTracked, "your own game pin comes back, still tracked")
M.Tick(0.1)
for _, have in ipairs(WP.List()) do
    if have.source == "mappin" and math.abs(have.y - 0.75) < 0.0001 then
        WP.Remove(have, true)
        break
    end
end
M.Tick(0.1)
ns.Set("followMapPins", false)
C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(37, 0.1, 0.1))
M.Tick(0.1)
check(not (WP.GetActive().x == 0.1), "map pins ignored when turned off")
ns.Set("followMapPins", true)

-- the quest you track
ns.Set("followQuest", true)
M.superTracked = 101
M.FireEvent("SUPER_TRACKING_CHANGED")
M.Tick(0.7)
check(WP.GetActive().title == "The Fargodeep Mine", "arrow points to the tracked quest")
M.superTracked = 102
M.FireEvent("SUPER_TRACKING_CHANGED")
M.Tick(0.7)
check(WP.GetActive().title == "Report to Gryan" and WP.GetActive().m == 52, "switching quests moves the arrow")
M.superTracked = 0
M.FireEvent("SUPER_TRACKING_CHANGED")
M.Tick(0.7)
for _, wpq in ipairs(WP.List()) do
    check(wpq.source ~= "quest", "untracking removes the quest waypoint")
end
ns.Set("followQuest", false)

-- reset
M.autoAcceptPopup = true
ns.Set("arrowScale", 1.7)
StaticPopup_Show("WAYPOINTTRACKER_RESET")
ns.ResetSettings()
check(ns.Get("arrowScale") == 1.0, "reset settings")
WaypointTracker_ToggleWindow()
check(not WaypointTrackerFrame:IsShown(), "window closes")

-- no position (instance)
M.player.noPosition = true
M.Tick(0.3)
M.player.noPosition = false
M.Tick(0.1)

-- ---------------------------------------------------------------------------
-- Find window (pfQuest's database, loaded on demand)
-- ---------------------------------------------------------------------------
M.player.wx, M.player.wy, M.player.inst = -1200, -1200, 0 -- Elwynn Forest 40, 60
M.noDataAddon = true
ns.Find.Show()
check(WaypointTrackerFindFrame:IsShown(), "Find window opens")
local fw = ns.Find.widgets
fw.search:Type("kobold")
M.Tick(0.3)
check(fw.rows[1]:IsShown() == false, "no results without the database")
M.noDataAddon = false
check(WaypointTrackerData == nil, "database not loaded until needed")
fw.search:Type("a")
local t0 = os.clock()
M.Tick(0.3)
searchTime = os.clock() - t0
check(WaypointTrackerData ~= nil and ns.DB.loaded, "database loaded on first search")
-- names are in the client's language, so look them up by ID
local function Name(tbl, id)
    return ns.DB[tbl][id] and ns.DB[tbl][id].name
end
local VERMIN, HOGGER, FARLEY, THRALL, FARGODEEP = 6, 448, 295, 4949, 62
fw.search:Type(Name("units", VERMIN))
M.Tick(0.3)
check(fw.rows[1].entry and fw.rows[1].entry.id == VERMIN, "finds Kobold Vermin by its name (got " .. tostring(fw.rows[1].entry and fw.rows[1].entry.name) .. ")")
local vermin = fw.rows[1].entry
check(#ns.DB.Points(vermin) > 0 and ns.DB.Points(vermin)[1].m == 37, "its spawns map to Elwynn Forest")
local goBtn = fw.detail.buttons[1]
check(goBtn:IsShown(), "Take me there button")
goBtn:Click()
check(WP.GetActive().title == Name("units", VERMIN) and WP.GetActive().m == 37, "arrow goes to the nearest Kobold Vermin")
local d = Geo.GetVector(WP.GetActive())
check(d and d < 600, "nearest spawn picked (" .. tostring(d and math.floor(d)) .. " yds)")

-- speed of a search once the database is loaded
local t1 = os.clock()
for _, word in ipairs({ "wolf", "defias trapper", "gold", Name("units", HOGGER), "mur" }) do
    ns.DB.Search(word, { quest = true, npc = true, enemy = true, object = true, item = true }, { faction = true })
end
searchSpeed = (os.clock() - t1) / 5
if M.locale == "enUS" then
    local typo = ns.DB.Search("Hoger", { npc = true, enemy = true }, {})
    check(typo[1] and typo[1].id == HOGGER, "typo finds Hogger (got " .. tostring(typo[1] and typo[1].name) .. ")")
    -- WoW Forever's own NPCs, from the curated database
    local dokimi = ns.DB.Search("Dokimi", { npc = true, enemy = true }, {})
    check(dokimi[1] and dokimi[1].id == 256386 and ns.DB.Points(dokimi[1])[1], "finds Dokimi, added in WoW Forever 1.60.1")
    local grund = ns.DB.Search("Grund Drokda", { npc = true, enemy = true }, {})
    check(grund[1] and grund[1].id == 2756, "finds an NPC only the curated database names")
    local applejack = ns.DB.Search("Applejack Still", { quest = true }, {})
    check(applejack[1] and applejack[1].id == 91736, "finds a curated quest the game client's quest table lacks")
    -- a quest started at an object leads there
    local wanted = ns.DB.quests[93318]
    local starts = wanted and ns.DB.QuestTargets(wanted, "start") or {}
    check(starts[1] and ns.DB.Points(starts[1])[1], "a quest started at an object leads to that object")
    check(#ns.DB.Search("", { object = true }, {}) == 0, "nameless entries never show up in a search")
end

-- quests: not started -> quest giver
fw.search:Type(Name("quests", FARGODEEP))
M.Tick(0.3)
local quest
for _, r in ipairs(fw.rows) do
    if r.entry and r.entry.kind == "quest" and r.entry.id == FARGODEEP then
        quest = r.entry
    end
end
check(quest ~= nil, "finds a quest")
ns.Find.Activate(quest)
check(WP.GetActive().title:find(quest.name, 1, true) and WP.GetActive().m == 37, "quest leads to its giver in Elwynn")
check(#ns.DB.QuestTargets(quest, "start") > 0 and #ns.DB.QuestTargets(quest, "end") > 0, "quest giver and hand-in known")

-- tabs and faction filter
ns.Set("findTab", "quest")
fw.search:Type(Name("units", VERMIN):sub(1, 4))
M.Tick(0.3)
local onlyQuests = true
for _, r in ipairs(fw.rows) do
    if r.entry and r.entry.kind ~= "quest" then
        onlyQuests = false
    end
end
check(onlyQuests, "Quests tab shows only quests")
ns.Set("findTab", "npc")
fw.search:Type(Name("units", THRALL))
M.Tick(0.3)
local thrall = false
for _, r in ipairs(fw.rows) do
    if r.entry and r.entry.id == THRALL then
        thrall = true
    end
end
check(not thrall, "Horde-only NPCs hidden for Alliance")
fw.faction:Click()
M.Tick(0.3)
thrall = false
for _, r in ipairs(fw.rows) do
    if r.entry and r.entry.id == THRALL then
        thrall = true
    end
end
check(thrall, "shown with the faction filter off")
fw.faction:Click()
ns.Set("findTab", "all")

-- nearest services
local innBtn, mailBtn
for _, b in ipairs(WaypointTrackerFindFrame.serviceButtons) do
    if b.service == "innkeeper" then
        innBtn = b
    elseif b.service == "mailbox" then
        mailBtn = b
    end
end
innBtn:Click()
check(WP.GetActive().title == Name("units", FARLEY), "nearest innkeeper is Goldshire's (got " .. tostring(WP.GetActive().title) .. ")")
mailBtn:Click()
check(WP.GetActive().m == 37 and WP.GetActive().title ~= Name("units", FARLEY), "nearest mailbox")
ns.Find.Toggle()
check(not WaypointTrackerFindFrame:IsShown(), "Find window closes")
SlashCmdList.WAYPOINTTRACKER("find mine")
check(WaypointTrackerFindFrame:IsShown() and fw.search:GetText() == "mine", "/wp find opens it with the text")
ns.Find.Toggle()

-- ---------------------------------------------------------------------------
-- Learning WoW Forever content as you play
-- ---------------------------------------------------------------------------
local Learn = ns.Learn
local function Here(x, y) -- stand on Zephras Isle at x, y (0..100)
    M.player.inst = 2800
    M.player.wx = 3000 - y / 100 * 3000
    M.player.wy = 3000 - x / 100 * 3000
end
local function Guid(kind, id)
    return ("%s-0-1-2-3-%d-00000ABC"):format(kind, id)
end
Here(40, 50)
check(select(1, Geo.GetPlayerMapPosition()) == 2521, "standing on Zephras Isle")

-- a quest giver offers a new quest
M.units.questnpc = { guid = Guid("Creature", 90001), name = "Elder Skyfeather", reaction = 5, level = 12 }
M.questDialog = { id = 70001, title = "Wings Over Zephras", text = "Collect 6 Skyflowers." }
M.FireEvent("QUEST_DETAIL")
M.FireEvent("QUEST_ACCEPTED", 70001)
local st = Learn.Store()
check(st.quests[70001] and st.quests[70001].title == "Wings Over Zephras" and st.quests[70001].giver == "U90001", "quest and its giver learned")
check(st.npcs[90001] and st.npcs[90001].spots[2521], "quest giver's spot learned")

-- the game marks the quest's area on the map
M.quests[#M.quests + 1] = { id = 70001, title = "Wings Over Zephras", onMap = { [2521] = { 0.62, 0.30 } } }
M.FireEvent("QUEST_LOG_UPDATE")
M.Tick(3.1)
check(st.quests[70001].area and st.quests[70001].area[1] == 2521, "objective area learned")
table.remove(M.quests)

-- talking to a vendor who repairs, and using a mailbox
Here(45, 55)
M.units.questnpc = nil
M.units.npc = { guid = Guid("Creature", 90003), name = "Breezy Trader", reaction = 5, level = 15 }
M.canRepair = true
M.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
check(st.npcs[90003] and st.npcs[90003].services.vendor and st.npcs[90003].services.repair, "vendor and repair learned")
M.units.npc = nil
M.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.MailInfo)
check(st.mailboxes.spots and st.mailboxes.spots[2521], "mailbox learned")

-- killing and looting an enemy
Here(60, 30)
M.units.target = { guid = Guid("Creature", 90010), name = "Galewing Serpent", reaction = 2, level = 9 }
M.FireEvent("PLAYER_TARGET_CHANGED")
M.loot = { Guid("Creature", 90010) }
M.FireEvent("LOOT_OPENED")
check(st.npcs[90010] and st.npcs[90010].name == "Galewing Serpent" and st.npcs[90010].hostile, "enemy learned where it was looted")
M.units.target = nil

-- gathering an object: its name comes from the tooltip you pointed at
M.ShowObjectTooltip("Skyflower")
M.loot = { Guid("GameObject", 95001) }
M.FireEvent("LOOT_OPENED")
check(st.objects[95001] and st.objects[95001].name == "Skyflower", "object learned with its name")
M.loot, M.tooltipOwner = {}, nil

-- turning the quest in
M.units.questnpc = { guid = Guid("Creature", 90002), name = "Warden Galebrook", reaction = 5 }
M.questDialog = { id = 70001 }
M.FireEvent("QUEST_COMPLETE")
check(st.quests[70001].ender == "U90002", "hand-in NPC learned")
M.units.questnpc = nil
M.Tick(5.1)

-- Find uses discoveries right away
check(Learn.Count() >= 5, "discoveries counted (" .. Learn.Count() .. ")")
ns.Find.Show(nil, "quest")
fw.search:Type("Wings")
M.Tick(0.3)
local wings = fw.rows[1].entry
check(wings and wings.id == 70001 and wings.learned == "you", "learned quest is searchable")
ns.Find.Activate(wings)
check(WP.GetActive().m == 2521 and WP.GetActive().title:find("Wings Over Zephras", 1, true), "arrow goes to the learned quest giver")
local objs = ns.DB.QuestTargets(wings, "objective")
check(objs[1] and objs[1].kind == "spot", "objective area is a target")
ns.Set("findTab", "enemy")
fw.search:Type("galewing")
M.Tick(0.3)
check(fw.rows[1].entry and fw.rows[1].entry.id == 90010, "Enemies tab finds the learned enemy (got " .. tostring(fw.rows[1].entry and fw.rows[1].entry.name .. " " .. fw.rows[1].entry.id) .. ")")
ns.Set("findTab", "npc")
fw.search:Type("galewing")
M.Tick(0.3)
check(not (fw.rows[1].entry and fw.rows[1].entry.id == 90010), "enemies are not in the NPCs tab")
fw.search:Type("breezy")
M.Tick(0.3)
check(fw.rows[1].entry and fw.rows[1].entry.id == 90003, "friendly NPC you met is in the NPCs tab")
ns.Set("findTab", "enemy")
fw.search:Type("breezy")
M.Tick(0.3)
check(not fw.rows[1].entry, "and not in the Enemies tab")
ns.Set("findTab", "npc")
fw.search:Type(Name("units", VERMIN))
M.Tick(0.3)
check(not (fw.rows[1].entry and fw.rows[1].entry.id == VERMIN), "monsters from the database are enemies, not NPCs")
ns.Set("findTab", "object")
fw.search:Type("skyflower")
M.Tick(0.3)
check(fw.rows[1].entry and fw.rows[1].entry.id == 95001, "Objects tab finds the learned object")
for _, b in ipairs(WaypointTrackerFindFrame.serviceButtons) do
    if b.service == "repair" then
        b:Click()
    end
end
check(WP.GetActive().title == "Breezy Trader", "Nearest repair uses a learned vendor (got " .. tostring(WP.GetActive().title) .. ")")
for _, b in ipairs(WaypointTrackerFindFrame.serviceButtons) do
    if b.service == "mailbox" then
        b:Click()
    end
end
check(WP.GetActive().m == 2521, "Nearest mailbox uses a learned mailbox")

-- sharing and importing discoveries
local exported = Learn.Export()
check(exported:find("Wings Over Zephras", 1, true) and exported:find("Galewing Serpent", 1, true), "export has the discoveries")
fw.share:Click()
check(WaypointTrackerShareBox:IsShown() and ns.Find.shareBox.edit:GetText() == exported, "share box shows the text to copy")
WaypointTrackerDB.learned = nil
check(Learn.Count() == 0, "discoveries cleared")
fw.import:Click()
ns.Find.shareBox.edit:SetText(exported)
ns.Find.shareBox.action:Click()
check(Learn.Count() >= 5 and Learn.Store().quests[70001] ~= nil, "import brings them back")
ns.Find.shareBox.edit:SetText("hello")
ns.Find.shareBox.action:Click()
check(ns.Find.shareBox.result:GetText() == L.IMPORT_NOTHING, "junk import is refused")
WaypointTrackerShareBox:Hide()

-- the community file shipped with the database is used too
local community = { npcs = {}, objects = {}, quests = {}, mailboxes = {} }
check(Learn.Import("WTL1\tcommunity\t1\nN\t91000\tRiver Guard\t0\t30\t\t2521:500,500", community) == 1, "community format parses")

-- learning can be turned off
ns.Set("learn", false)
M.units.npc = { guid = Guid("Creature", 90099), name = "Quiet NPC", reaction = 5 }
M.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
check(Learn.Store().npcs[90099] == nil, "nothing learned when turned off")
M.units.npc = nil
ns.Set("learn", true)

-- NPCs around you are written down: nameplates, target, mouse-over
st = Learn.Store()
Here(30, 30)
M.units.nameplate3 = { guid = Guid("Creature", 248197), name = "Gor'mak", title = "Blacksmith", reaction = 4, level = 60, faction = "Horde", dist = 20 }
M.Tick(1.1)
local gormak = st.npcs[248197]
check(gormak and gormak.name == "Gor'mak" and gormak.title == "Blacksmith" and gormak.fac == "H" and gormak.level == 60, "an NPC on a nameplate is written down with its title and faction")
check(gormak and gormak.spots[2521] and #gormak.spots[2521] == 2 and near(gormak.spots[2521][1], 0.30, 0.001), "at your spot when it's within reach")
Here(32, 31)
M.units.nameplate3.dist = 5
M.Tick(1.1)
check(#gormak.spots[2521] == 2 and near(gormak.spots[2521][1], 0.32, 0.001), "the rough spot moves to where you stand next to it")
Here(50, 50)
M.Tick(1.1)
check(#gormak.spots[2521] == 2, "and it isn't written down again")
M.units.nameplate3 = nil
M.units.nameplate4 = { guid = Guid("Creature", 248300), name = "Far Away", reaction = 5, level = 50, dist = 60 }
M.units.nameplate5 = { guid = Guid("Creature", 248301), name = "Someone's Pet", reaction = 5, level = 50, dist = 5, controlled = true }
M.units.nameplate6 = { guid = Guid("Creature", 248302), name = "Meadow Rabbit", reaction = 4, level = 1, dist = 5 }
M.units.nameplate7 = { guid = Guid("Player", 248303), name = "Somebody", reaction = 5, level = 50, dist = 5, player = true }
M.Tick(1.1)
check(not st.npcs[248300] and not st.npcs[248301] and not st.npcs[248302] and not st.npcs[248303], "not written down: too far, pets, critters and players")
M.units.nameplate4, M.units.nameplate5, M.units.nameplate6, M.units.nameplate7 = nil, nil, nil, nil
M.units.nameplate8 = { guid = Guid("Creature", 248304), name = "Scarlet Trainee", reaction = 2, level = 55, dist = 8 }
M.player.combat = true
M.Tick(1.1)
check(not st.npcs[248304], "nothing is looked at during combat")
M.player.combat = false
ns.Set("learn", false)
M.Tick(1.1)
check(not st.npcs[248304], "or with learning turned off")
ns.Set("learn", true)
M.Tick(1.1)
check(st.npcs[248304] and st.npcs[248304].hostile and not st.npcs[248304].title, "an enemy is written down after combat, with no title")
M.units.nameplate8 = nil
M.units.mouseover = { guid = Guid("Creature", 248305), name = "Pointed At", reaction = 5, level = 40, dist = 25 }
M.FireEvent("UPDATE_MOUSEOVER_UNIT")
check(st.npcs[248305] and st.npcs[248305].spots[2521], "an NPC you point at is written down")
M.units.mouseover = nil

-- what vendors sell
Here(32, 31)
M.canRepair = false
M.units.npc = { guid = Guid("Creature", 248197), name = "Gor'mak", title = "Blacksmith", reaction = 4, level = 60, faction = "Horde", dist = 3 }
M.merchant = { { 248601, "Plans: Merchant's Belt" }, { 248602, "Plans: Merchant's Helm" } }
M.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
M.FireEvent("MERCHANT_SHOW")
M.Tick(0.6)
check(st.items[248601] and st.items[248601].name == "Plans: Merchant's Belt" and st.items[248601].sold["U248197"], "a vendor's stock is written down")
M.units.npc, M.merchant = nil, {}
M.Tick(5.1)
-- (a Horde vendor: for this test, show both factions)
ns.Set("findFaction", false)
ns.Set("findTab", "item")
fw.search:Type("Merchant's Belt")
M.Tick(0.3)
local belt = fw.rows[1].entry
check(belt and belt.id == 248601 and belt.soldBy[1] == 248197, "Find knows who sells it")
check(fw.detail.body:GetText():find(L.SOLD_BY:format("Gor'mak"), 1, true) ~= nil, "and says so")
ns.Find.Activate(belt)
check(WP.GetActive().title:find("Gor'mak", 1, true) and near(WP.GetActive().x, 0.32, 0.001), "the arrow goes to the vendor")
ns.Set("findTab", "npc")
fw.search:Type("blacksmith")
M.Tick(0.3)
local smiths = {}
for i = 1, #fw.rows do
    if fw.rows[i].entry then
        smiths[fw.rows[i].entry.id] = true
    end
end
check(smiths[248197], "searching an NPC's title finds it")
ns.Set("findFaction", true)

-- only what's new is kept: an NPC seen where the database has it isn't saved
st.npcs[60] = { name = "Ruklar the Trapper", hostile = true, spots = { [37] = { 0.646, 0.567 } } }
ns.DB.MergeLearned()
check(st.npcs[60] == nil, "an NPC seen where the database has it isn't kept")
st.npcs[60] = { name = "Ruklar the Trapper", hostile = false, spots = { [37] = { 0.646, 0.567 } } }
ns.DB.MergeLearned()
check(st.npcs[60] ~= nil, "but is kept when it's friend instead of foe")
st.npcs[60] = nil
ns.DB.MergeLearned()
-- in play: seen once Find's database is loaded, it's dropped a moment later
M.units.nameplate13 = { guid = Guid("Creature", 60), name = "Ruklar the Trapper", reaction = 2, level = 10, dist = 5 }
M.player.inst, M.player.wx, M.player.wy = Geo.MapToWorld(37, 0.646, 0.567) -- where the database has it
M.Tick(1.1)
check(st.npcs[60] ~= nil, "a sighting is written down first")
M.units.nameplate13 = nil
M.Tick(5.1)
check(st.npcs[60] == nil, "and dropped within seconds once it turns out the database has it")
Here(30, 30)
local shared, everything = Learn.Export(), Learn.Export(true)
check(shared:find("\nN\t248197\tGor'mak\t0\t60\tvendor\t2521:320,310\tH\tBlacksmith", 1, true) ~= nil, "a new NPC is shared with its title and faction")
check(shared:find("\nI\t248601\tPlans: Merchant's Belt\t\tU248197", 1, true) ~= nil, "a vendor's stock is shared")
st.npcs[60] = { name = "Ruklar the Trapper", hostile = true, spots = { [37] = { 0.646, 0.567, 0.20, 0.20 } } }
ns.DB.MergeLearned()
check(Learn.Export():find("\nN\t60\t", 1, true) ~= nil, "an NPC seen somewhere new is kept and shared")
st.npcs[60] = nil
local fresh = { npcs = {}, objects = {}, quests = {}, items = {}, mailboxes = {} }
Learn.Import(shared, fresh, true)
check(fresh.npcs[248197] and fresh.npcs[248197].title == "Blacksmith" and fresh.npcs[248197].fac == "H" and fresh.items[248601].sold["U248197"], "titles and vendors come back in an import")
local many = { "WTL1\tcommunity\t1\nI\t5\tThing\t\t" }
for i = 1, 60 do
    many[#many + 1] = "U" .. i .. ","
end
Learn.Import(table.concat(many), fresh, true)
local sellers = 0
for _ in pairs(fresh.items[5].sold) do
    sellers = sellers + 1
end
check(sellers == 20, "an import keeps at most 20 vendors per item (" .. sellers .. ")")
check(Learn.Import("WTL1\tcommunity\t1\nN\t91001\t|cffff0000Evil|r\t0\t30\t\t2521:500,500\tA\t|TInterface\\x:0|t<Title>", fresh, true) == 1 and fresh.npcs[91001].name == "Evil" and not fresh.npcs[91001].title:find("|", 1, true), "imported names and titles are cleaned")

-- friend or foe is the same for every player
st = Learn.Store()
M.units.nameplate9 = { guid = Guid("Creature", 248310), name = "Prowling Wolf", reaction = 4, level = 20, dist = 5 }
M.units.nameplate10 = { guid = Guid("Creature", 248311), name = "Wandering Merchant", reaction = 4, level = 20, dist = 5, attackable = false }
M.units.nameplate11 = { guid = Guid("Creature", 248312), name = "Horde Grunt", reaction = 2, level = 55, dist = 5, faction = "Horde" }
M.Tick(1.1)
check(st.npcs[248310] and st.npcs[248310].hostile == true, "a neutral mob you can attack is an enemy")
check(st.npcs[248311] and st.npcs[248311].hostile == false, "a neutral NPC you can't attack isn't")
check(st.npcs[248312] and st.npcs[248312].hostile == false and st.npcs[248312].fac == "H", "the other faction's NPC is friendly to its side, not an enemy")
M.units.nameplate9, M.units.nameplate10, M.units.nameplate11 = nil, nil, nil

-- a vendor you just visited is in the share right away
M.units.npc = { guid = Guid("Creature", 248313), name = "Quick Trader", reaction = 5, level = 30, dist = 3 }
M.merchant = { { 2901, "Mining Pick" } }
M.FireEvent("MERCHANT_SHOW")
M.Tick(0.6)
M.FireEvent("MERCHANT_CLOSED")
M.units.npc, M.merchant = nil, {}
check(Learn.Export():find("\nI\t2901\tMining Pick\t\tU248313", 1, true) ~= nil, "a vendor seen seconds ago is shared")

-- a damaged saved file doesn't stop learning or sharing
WaypointTrackerDB.learned = {
    npcs = { [248320] = { name = {}, level = "x", fac = "Z", spots = { [2521] = "bad", x = { 1, 2 } }, services = 5 } },
    objects = "broken", quests = { [5] = { area = { "a" }, objs = { 1, "monster:X" } } }, items = { [7] = { from = "U1" } },
}
local bad = Learn.Store().npcs[248320]
check(bad.name == nil and bad.level == nil and bad.fac == nil and bad.services == nil and next(bad.spots) == nil, "bad fields of a saved entry are dropped")
check(Learn.Store().quests[5].area == nil and #Learn.Store().quests[5].objs == 1 and Learn.Store().items[7].from == nil, "and of quests and items")
M.units.nameplate12 = { guid = Guid("Creature", 248320), name = "Mended", reaction = 5, level = 30, dist = 5 }
M.Tick(1.1)
check(Learn.Store().npcs[248320].name == "Mended" and Learn.Store().npcs[248320].spots[2521], "learning carries on")
check(pcall(Learn.Export) and pcall(Learn.Export, true), "sharing works")
M.units.nameplate12 = nil
WaypointTrackerDB.learned = nil
st = Learn.Store()

-- imports fill gaps, never rename what the database has
-- (imported, it's labelled as other players' discoveries)
check(Learn.Import("WTL1\tenUS\t1\nN\t248400\tFriendly Stranger\t0\t30\t\t2521:100,100", nil) == 1, "an import is read")
ns.DB.MergeLearned()
check(ns.DB.units[248400] and ns.DB.units[248400].learned == "community", "what you imported is labelled as shared by other players")
Learn.Store().npcs[248400] = nil
local hogName = ns.DB.units[448].name
local hogQuest
for id, q in pairs(ns.DB.quests) do
    if #q.startU > 0 and not Learn.Store().quests[id] then
        hogQuest = q
        break
    end
end
local oldGiver = hogQuest.startU[1]
Learn.Import(("WTL1\tenUS\t1\nN\t448\tTotally Not Hogger\t0\t60\tvendor,warpgate\t37:500,500\nQ\t%d\tRenamed Quest\t\tU99999"):format(hogQuest.id))
ns.DB.MergeLearned()
check(ns.DB.units[448].name == hogName, "an import doesn't rename an NPC the database has")
check(hogQuest.name ~= "Renamed Quest" and hogQuest.startU[1] == oldGiver, "or a quest, or its giver")
check(Learn.Store().npcs[448].services.vendor and not Learn.Store().npcs[448].services.warpgate, "unknown services are ignored")
check(not Learn.Export(true):find("Totally Not Hogger", 1, true), "what you imported isn't shared on as yours")
M.units.target = { guid = Guid("Creature", 448), name = "Hogger", reaction = 2, level = 11, dist = 40 }
Learn.Unit("target")
check(not Learn.Store().npcs[448].shared and Learn.Export(true):find("\nN\t448\tHogger", 1, true), "once you see it in the game, it's yours")
M.units.target = nil
Learn.Store().npcs[448], Learn.Store().quests[hogQuest.id] = nil, nil
ns.DB.MergeLearned()
local flood = { "WTL1\tcommunity\t1" }
for i = 1, 20500 do
    flood[#flood + 1] = "N\t" .. (3000000 + i) .. "\tX"
end
Learn.Import(table.concat(flood, "\n"))
local npcsNow = 0
for _ in pairs(Learn.Store().npcs) do
    npcsNow = npcsNow + 1
end
check(npcsNow <= 20000, "an import can't grow your discoveries without end (" .. npcsNow .. ")")
for i = 1, 20500 do
    Learn.Store().npcs[3000000 + i] = nil
end
ns.DB.MergeLearned()

-- correcting a spot: "Find has it here, but it's really there"
local RUKLAR = 60
ns.Set("findTab", "enemy")
ns.Set("findThisZone", false)
fw.search:Type(Name("units", RUKLAR))
M.Tick(0.3)
local fixBtn = fw.detail.buttons[2]
check(fw.rows[1].entry and fw.rows[1].entry.id == RUKLAR and fixBtn:IsShown() and fixBtn:GetText() == L.FIX_SPOT, "Find offers to correct an NPC's spot")
fixBtn:Click()
local fb = ns.Find.fixBox
check(fb and fb:IsShown() and fb.help:GetText():find("64.6", 1, true) and fb.gone:IsShown() and not fb.undo:IsShown(), "the box says where Find has it")
fb.x.edit:SetText("abc")
fb.save:Click()
check(fb.result:GetText() == L.FIX_BAD and #Learn.Fixes("npc", RUKLAR) == 0, "nonsense coordinates are refused")
M.player.inst, M.player.wx, M.player.wy = 0, -1200, -1200 -- Elwynn Forest 40, 60
fb.here:Click()
check(fb.x.edit:GetText() == "40.0" and fb.y.edit:GetText() == "60.0", "Use My Position fills in where you stand")
fb.save:Click()
local ruklarPts = ns.DB.Points(ns.DB.units[RUKLAR])
check(fb.result:GetText() == L.FIX_SAVED and #ruklarPts == 1 and near(ruklarPts[1].x, 0.40, 0.001) and near(ruklarPts[1].y, 0.60, 0.001), "the corrected spot replaces the wrong one")
check(fw.detail.body:GetText():find(L.FIX_MARK, 1, true) ~= nil and fb.undo:IsShown(), "Find says you corrected it")
ns.Find.Activate(ns.DB.units[RUKLAR])
check(near(WP.GetActive().x, 0.40, 0.001), "and the arrow goes to the corrected spot")
check(Learn.Export():find("\nC\tN\t60\t37:646,567\t37:400,600", 1, true) ~= nil, "a correction is shared as wrong spot and right spot")
ns.DB.MergeLearned()
check(#Learn.Fixes("npc", RUKLAR) == 1, "corrections are kept (they're always yours to share)")
fb.undo:Click()
check(fb.result:GetText() == L.FIX_REMOVED and near(ns.DB.Points(ns.DB.units[RUKLAR])[1].x, 0.646, 0.001), "removing it brings the database's spot back")
ns.Find.ShowFixBox(ns.DB.units[RUKLAR])
fb.gone:Click()
check(#ns.DB.Points(ns.DB.units[RUKLAR]) == 0, "It's not there removes the spot")
check(Learn.Export():find("\nC\tN\t60\t37:646,567\t\n", 1, true) ~= nil or Learn.Export():find("\nC\tN\t60\t37:646,567\t$") ~= nil, "and is shared without a right spot")
fb.undo:Click()
fb:Hide()
-- someone else's correction: used, not shared on as yours, and yours wins
local theirs = "WTL1\tenUS\t1\nC\tN\t60\t37:646,567\t37:100,100"
check(Learn.Import(theirs) == 1 and #ns.DB.Points(ns.DB.units[RUKLAR]) >= 0, "a shared correction imports")
ns.DB.MergeLearned()
check(near(ns.DB.Points(ns.DB.units[RUKLAR])[1].x, 0.10, 0.001) and not Learn.Export():find("\nC\t", 1, true), "it's used, and not shared on as yours")
Learn.AddFix("npc", RUKLAR, { 37, 0.646, 0.567 }, { 37, 0.5, 0.5 })
Learn.Import(theirs)
ns.DB.MergeLearned()
check(#Learn.Fixes("npc", RUKLAR) == 1 and near(ns.DB.Points(ns.DB.units[RUKLAR])[1].x, 0.5, 0.001), "your own correction wins over an imported one")
Learn.ClearFixes("npc", RUKLAR)
check(Learn.Import("WTL1\tenUS\t1\nC\tX\t60\t37:1,1\t37:2,2\nC\tN\tabc\t37:1,1\t\nC\tN\t61\t37:5000,1\t37:9999999,1\nC\tN\t62\t\t") == 0, "broken corrections are ignored")
-- an NPC without a spot: add where it is
local spotless = { kind = "npc", id = 248500, name = "Spotless", key = "spotless", fac = "" }
ns.DB.units[248500] = spotless
ns.Find.ShowFixBox(spotless)
check(not fb.gone:IsShown() and fb.help:GetText() == L.FIX_HELP_NEW:format("Spotless"), "for something without a spot, the box adds one")
fb.x.edit:SetText("12,5")
fb.y.edit:SetText("34")
fb.save:Click()
spotless.points = nil
check(#ns.DB.Points(spotless) == 1 and near(ns.DB.Points(spotless)[1].x, 0.125, 0.001), "typed coordinates (with a decimal comma) add the spot")
Learn.ClearFixes("npc", 248500)
fb:Hide()
ns.DB.units[248500] = nil
ns.DB.MergeLearned()
ns.Set("findTab", "all")

-- WoW Forever's own game files: flight paths, towns and quest markers
ns.Set("findTab", "all")
fw.search:Type("Summit of Eternity")
M.Tick(0.3)
local summit = fw.rows[1].entry
if M.locale == "enUS" then
    check(summit and summit.kind == "place" and summit.learned == "game", "new Forever flight path is searchable")
end
check(next(ns.DB.places) ~= nil and ns.DB.marks[92742] and ns.DB.marks[92742].start, "client flight paths and quest markers loaded")
local cont, wx, wy = Geo.MapToWorld(37, 0.41, 0.61)
ns.DB.ParseClient({
    flights = ("9001\t%d\t37\t%.1f\t%.1f\tAH"):format(cont, wx, wy),
    names = { flights = "9001\tTestport, Elwynn" },
    pois = ("86574\tstart\t%d\t37\t%.1f\t%.1f\n86574\tobj0\t%d\t37\t%.1f\t%.1f"):format(cont, wx, wy, cont, wx - 300, wy),
})
M.player.inst, M.player.wx, M.player.wy = 0, -1200, -1200 -- Elwynn Forest 40, 60
for _, b in ipairs(WaypointTrackerFindFrame.serviceButtons) do
    if b.service == "flight" then
        b:Click()
    end
end
check(WP.GetActive().title == "Testport, Elwynn" and near(WP.GetActive().x, 0.41, 0.001), "Nearest flight path uses the game's flight paths")

-- while the first quest-name scan runs, Find says so
local scanRunning, scanPct = ns.Learn.ScanProgress()
check(scanRunning and scanPct >= 0 and scanPct < 100, "the quest-name scan is running (" .. tostring(scanPct) .. "%)")
WaypointTrackerFindFrame:Hide()
WaypointTrackerFindFrame:Show()
check(fw.note:GetText() == L.SCAN_PROGRESS:format(select(2, ns.Learn.ScanProgress())), "Find's footer shows the scan's progress")
ns.Set("findTab", "all")
fw.search:Type("zzzzqqq")
M.Tick(0.3)
check(fw.empty:GetText():find(L.SCAN_SEARCH_NOTE, 1, true) ~= nil, "nothing found mentions the scan while it runs")
local lonelyItem
for id, it in pairs(ns.DB.items) do
    if it.name and #ns.DB.QuestsNeeding(it) == 0 and #it.dropU + #it.dropO + #it.soldBy == 0 then
        lonelyItem = it
        break
    end
end
ns.Set("findTab", "item")
fw.search:Type(lonelyItem.name)
M.Tick(0.3)
local function DetailText()
    return fw.detail.body:GetText() or ""
end
check(DetailText():find(L.ITEM_NO_SOURCE, 1, true) and DetailText():find(L.SCAN_ITEM_NOTE, 1, true), "an item with no source or quest mentions the scan while it runs")
-- the scan finishes in the background (a few names a second)
for _ = 1, 400 do
    if not ns.Learn.ScanProgress() then
        break
    end
    M.Tick(5, 0.5)
end
check(not ns.Learn.ScanProgress(), "the scan finishes")
M.Tick(1.1)
check(fw.note:GetText() == L.DB_NOTE, "Find's footer goes back to the tip when the scan is done")
check(DetailText():find(L.ITEM_NO_SOURCE, 1, true) and not DetailText():find(L.SCAN_ITEM_NOTE, 1, true), "the scan note goes away when the scan is done")
check(WaypointTrackerDB.questTitles.complete == true, "a finished scan is remembered")
ns.Set("findTab", "all")
fw.search:Type("")

-- the names of new quests are asked from the game in the background
M.serverQuests[86574] = "Riverglades Rumble"
-- a Season of Discovery quest WoW Forever kept: only there once the game names it
check(ns.DB.quests[78088] == nil, "a Season of Discovery quest waits for the game to confirm it")
M.serverQuests[78088] = "A Quest Forever Kept"
Learn.RestartTitleScan()
M.questRequests = 0
local steps = 0
while Learn.AskTitles() and steps < 5000 do
    steps = steps + 1
end
check(Learn.QuestTitles()[86574] == "Riverglades Rumble", "new quest name asked from the game")
check(M.questRequests > 100 and M.questRequests <= select(2, Learn.TitleProgress()), "each new quest asked for once (" .. M.questRequests .. ")")
M.Tick(5.1)
ns.Set("findTab", "quest")
fw.search:Type("Riverglades Rumble")
M.Tick(0.3)
local rumble = fw.rows[1].entry
check(rumble and rumble.id == 86574 and rumble.learned == "game", "new Forever quest is searchable by name")
ns.Find.Activate(rumble)
check(WP.GetActive().m == 37 and near(WP.GetActive().x, 0.41, 0.001), "quest giver found from the game's quest marker")
check(#ns.DB.QuestTargets(rumble, "objective") == 1, "objective from the game's quest marker")
-- what you saw in the game wins over the files
Learn.Store().quests[86574] = { title = "Riverglades Rumble", giver = "U90003" }
ns.DB.MergeLearned()
local giver = ns.DB.QuestTargets(rumble, "start")[1]
check(giver and giver.id == 90003, "quest giver you met replaces the marker")
local kept = ns.DB.quests[78088]
local keptGiver = kept and ns.DB.QuestTargets(kept, "start")[1]
check(kept and kept.name == "A Quest Forever Kept" and keptGiver and keptGiver.id == 3663, "then it's in Find, with its quest giver from the Season of Discovery data")
Learn.Store().quests[86574] = nil
Learn.Store().npcs[448] = { name = "Hogger", hostile = true, spots = { [37] = { 0.5, 0.5 } } }
ns.DB.MergeLearned()
local hog = ns.DB.Points(ns.DB.units[448])
local onElwynn = 0
for _, p in ipairs(hog) do
    if p.m == 37 then
        onElwynn = onElwynn + 1
    end
end
check(onElwynn > 1 and hog[1].x == 0.5, "an enemy seen once keeps the database's other spawns on that map (" .. onElwynn .. ")")
Learn.Store().npcs[448] = nil
Learn.Store().npcs[60] = { spots = { [37] = { 0.45, 0.62 } } }
ns.DB.MergeLearned()
local ruklar = ns.DB.Points(ns.DB.units[60])
check(#ruklar == 1 and ruklar[1].x == 0.45, "where you saw an NPC who stands in one place replaces the database's spot")
Learn.Store().npcs[60] = nil
ns.DB.MergeLearned()
check(#ns.DB.Points(ns.DB.units[448]) > 1 and near(ns.DB.Points(ns.DB.units[60])[1].x, 0.646, 0.02), "and the database's spots come back when forgotten")

-- items from the game client, and learning where they drop
ns.Set("findTab", "item")
fw.search:Type(M.locale == "enUS" and "Runes of the Sorcerer" or tostring(209850))
M.Tick(0.3)
local runes = ns.DB.items[209850]
check(runes and runes.learned == "game" and runes.quality == 1 and runes.ilvl == 25 and runes.class == 5, "client item loaded with its details")
check(runes and runes.desc and runes.desc ~= "", "client item has its description")
if M.locale == "enUS" then
    check(fw.rows[1].entry == runes, "item from the game client is searchable")
end
check(ns.Learn.ObjectiveName("Runes of the Sorcerer-Kings: 0/1") == "Runes of the Sorcerer-Kings", "objective name (name: 0/1)")
check(ns.Learn.ObjectiveName("0/1 Runen der Zaubererkönige") == "Runen der Zaubererkönige", "objective name (0/1 name)")
-- loot the scroll from a "Scrolls" object
M.player.inst, M.player.wx, M.player.wy = 0, -1200, -1200 -- Elwynn Forest 40, 60
M.ShowObjectTooltip("Scrolls")
M.loot = { Guid("GameObject", 409731) }
M.lootItems = { { id = 209850, name = runes.name } }
M.FireEvent("LOOT_OPENED")
M.loot, M.lootItems, M.tooltipOwner = {}, {}, nil
check(Learn.Store().items[209850] and Learn.Store().items[209850].from.O409731, "which object dropped the item is learned")
-- the Mage quest that wants it, in the log
M.serverQuests[78148] = "Runes of the Sorceror-Kings"
Learn.RestartTitleScan()
while Learn.AskTitles() do
end
M.quests[#M.quests + 1] = { id = 78148, title = "Runes of the Sorceror-Kings", objectives = { { text = runes.name .. ": 0/1", type = "item", finished = false } } }
M.FireEvent("QUEST_LOG_UPDATE")
M.Tick(3.1)
M.Tick(5.1)
table.remove(M.quests)
check(Learn.Store().quests[78148] and Learn.Store().quests[78148].objs[1] == "item:" .. runes.name, "quest objective learned")
-- learning is merged into Find the next time Find is used
ns.DB.Load()
local src = ns.DB.ItemSources(runes)
check(src[1] and src[1].id == 409731 and src[1].name == "Scrolls", "item source: the object you looted it from")
local runeQuest = ns.DB.quests[78148]
check(runeQuest and runeQuest.name == "Runes of the Sorceror-Kings", "Season of Discovery quest the classic database lacks is named by the game")
local needed = ns.DB.QuestsNeeding(runes)
check(needed[1] == runeQuest, "item knows the quest that needs it")
local objTargets = ns.DB.QuestTargets(runeQuest, "objective")
check(objTargets[1] and objTargets[1].id == 409731, "Go to objective leads to where the item drops")
ns.Find.Show(nil, "item")
fw.search:Type(M.locale == "enUS" and "Runes of the Sorcerer" or runes.name)
M.Tick(0.3)
ns.Find.Activate(runes)
check(WP.GetActive().m == 37, "Take me there goes to the object that dropped it")
-- All The Things' WoW Forever data: who takes the library books
local attGivers = ns.DB.QuestTargets(runeQuest, "start")
local giverIDs = {}
for _, g in ipairs(attGivers) do
    giverIDs[g.id] = g
end
local hordeBook = ns.DB.quests[79094] and ns.DB.QuestTargets(ns.DB.quests[79094], "start")[1]
check(giverIDs[211033] and hordeBook and hordeBook.id == 211022, "library quest givers for both factions come from All The Things")
check(giverIDs[211033] and giverIDs[211033].learned == "curated", "marked as curated data")
local garion = giverIDs[211033] and ns.DB.Points(giverIDs[211033])[1]
check(garion and garion.m == 1453 and near(garion.x, 0.489, 0.002) and near(garion.y, 0.865, 0.002), "Garion Wendell on Forever's reshaped Stormwind map")
local needsBook = false
for _, id in ipairs(runeQuest.objI) do
    needsBook = needsBook or id == 209850
end
check(needsBook, "the quest needs the book")
-- the classic database's percentages move with Forever's new Stormwind
local fx, fy = ns.DB.FromClassicMap(1453, 0.377, 0.805)
check(near(fx, 0.488, 0.003) and near(fy, 0.867, 0.003), "classic Stormwind spot moved onto Forever's map (" .. fx .. ", " .. fy .. ")")
local ux, uy = ns.DB.FromClassicMap(37, 0.4, 0.6)
check(ux == 0.4 and uy == 0.6, "maps Forever didn't change stay as they are")

-- share and bring back items
local text = Learn.Export()
check(text:find("I\t209850\t", 1, true) and text:find("item:", 1, true), "items and objectives are shared")
local back = { npcs = {}, objects = {}, quests = {}, mailboxes = {} }
Learn.Import(text, back)
check(back.items[209850] and back.items[209850].from.O409731 and back.quests[78148].objs[1], "shared items and objectives import")

-- ---------------------------------------------------------------------------
-- Treasure hunt: chests, rares and other markers near you
-- ---------------------------------------------------------------------------
do
    local T = ns.Treasure
    local CHEST = "GameObject-0-1-0-0-2843-0000000001"
    local RARE = "Creature-0-1-0-0-471-0000000002"
    WP.ClearAll(true)
    M.vignettes, M.sounds, M.raidNotices, M.flashes = {}, {}, {}, 0
    check(ns.Get("treasureHunt") == false, "treasure hunt is off until you turn it on")
    ns.Set("treasureHunt", true)
    M.Tick(1.1)
    check(next(T.Targets()) == nil and #M.sounds == 0, "it starts quietly when nothing is around")
    -- a chest appears on the minimap
    M.vignettes["v-chest"] = { name = "Battered Chest", onMinimap = true, atlasName = "VignetteLoot", objectGUID = CHEST, pos = { 0.42, 0.62 } }
    M.FireEvent("VIGNETTE_MINIMAP_UPDATED", "v-chest", true)
    M.Tick(0.2)
    local t = T.Targets()[CHEST]
    check(t and t.kind == "chest" and t.wp and WP.GetActive() == t.wp, "a chest on the minimap gets a waypoint and the arrow")
    check(M.sounds[#M.sounds] == 8959 and #M.raidNotices == 1 and M.flashes == 1, "with a ping: a sound, a message on screen and the taskbar")
    check(t.wp.persistent == false and t.wp.title:find("Battered Chest", 1, true) ~= nil, "treasure waypoints say what they are and aren't saved")
    -- someone takes it: the marker goes
    M.vignettes["v-chest"] = nil
    M.FireEvent("VIGNETTE_MINIMAP_UPDATED", "v-chest", false)
    M.Tick(0.2)
    check(T.Targets()[CHEST] == nil and WP.Count() == 0, "taken: the waypoint is let go")
    -- a rare on the minimap that wanders
    M.vignettes["v-rare"] = { name = "Mother Fang", onMinimap = true, atlasName = "VignetteKill", objectGUID = RARE, pos = { 0.5, 0.5 } }
    M.Tick(1.1)
    local r = T.Targets()[RARE]
    check(r and r.kind == "rare" and r.wp, "a rare on the minimap gets a waypoint")
    M.vignettes["v-rare"].pos = { 0.52, 0.5 }
    local pings = #M.sounds
    M.Tick(2.2)
    check(r.wp and math.abs(r.wp.x - 0.52) < 1e-6, "the waypoint follows a rare that moves")
    check(#M.sounds == pings, "one ping per find")
    M.vignettes["v-rare"].isDead = true
    M.Tick(1.1)
    check(T.Targets()[RARE] == nil and WP.Count() == 0, "killed: let go")
    M.vignettes["v-rare"].isDead = false
    M.Tick(1.1)
    check(T.Targets()[RARE] == nil and #M.sounds == pings, "a rare that was killed isn't announced again")
    -- markers only on the world map are too far away; other markers count as events
    M.vignettes = { far = { name = "Far Away", onWorldMap = true, pos = { 0.1, 0.1 } }, ev = { name = "Gathering", onMinimap = true, atlasName = "VignetteEvent", pos = { 0.45, 0.6 } } }
    M.Tick(1.1)
    local kinds = {}
    for _, x in pairs(T.Targets()) do
        kinds[x.name] = x.kind
    end
    check(kinds["Far Away"] == nil and kinds.Gathering == "other", "only what's on the minimap, and events too")
    ns.Set("treasureOther", false)
    check(next(T.Targets()) == nil, "turning a kind off lets those go")
    ns.Set("treasureOther", true)
    M.vignettes = {}
    M.Tick(1.1)

    -- a rare on a nameplate (no minimap marker): placed at its known spawn
    local here, hx, hy = ns.Geo.GetPlayerMapPosition()
    ns.DB.units[990001] = { kind = "npc", id = 990001, name = "Test Rare", key = "testrare", fac = "", points = { { m = here, x = hx + 0.01, y = hy } } }
    M.units.nameplate3 = { guid = "Creature-0-1-0-0-990001-0000000003", name = "Test Rare", class = "rareelite", reaction = 2, level = 30 }
    M.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
    local nr = T.Targets()["Creature-0-1-0-0-990001-0000000003"]
    check(nr and nr.wp and nr.wp.m == here and math.abs(nr.wp.x - (hx + 0.01)) < 1e-6, "a rare on a nameplate gets a waypoint at its known spawn")
    -- you remove the waypoint yourself: it stays gone
    WP.Remove(nr.wp, true)
    M.Tick(1.1)
    check(WP.Count() == 0 and nr.dismissed, "a treasure waypoint you remove stays removed")
    M.units.nameplate3.dead = true
    M.Tick(1.1)
    check(T.Targets()["Creature-0-1-0-0-990001-0000000003"] == nil, "a dead rare is let go")
    M.units.nameplate3 = nil
    -- someone else is fighting it: not yours to loot
    M.units.nameplate4 = { guid = "Creature-0-1-0-0-990001-0000000004", name = "Test Rare", class = "rare", reaction = 2, tapped = true }
    M.Tick(1.1)
    check(T.Targets()["Creature-0-1-0-0-990001-0000000004"] == nil, "rares someone else is fighting are left out")
    M.units.nameplate4 = { guid = "Creature-0-1-0-0-6-0000000005", name = "Kobold Vermin", class = "normal", reaction = 2 }
    M.Tick(1.1)
    check(next(T.Targets()) == nil, "ordinary enemies are left out")
    M.units.nameplate4 = nil
    ns.DB.units[990001] = nil

    -- "point the arrow at it" off: your own waypoint keeps the arrow
    ns.Set("treasureFocus", false)
    local mine = WP.Add(here, 0.3, 0.3, { title = "Mine", silent = true })
    M.vignettes["v-chest"] = { name = "Solid Chest", onMinimap = true, atlasName = "VignetteLoot", objectGUID = CHEST, pos = { 0.42, 0.62 } }
    M.Tick(1.1)
    check(WP.GetActive() == mine and WP.Count() == 2, "with focus off the chest is added and the arrow stays")
    ns.Set("treasureFocus", true)
    M.vignettes = {}
    M.Tick(1.1)
    check(WP.GetActive() == mine and WP.Count() == 1, "and the arrow is back on your own waypoint once it's gone")

    -- the chest right in front of you, looted
    local chestId
    for id, e in pairs(ns.DB.objects) do
        if e.chest and id > 0 then
            chestId = id
            break
        end
    end
    check(chestId ~= nil, "the database knows which objects are treasure chests")
    local front = "GameObject-0-1-0-0-" .. tostring(chestId) .. "-0000000006"
    M.units.softinteract = { guid = front, name = ns.DB.objects[chestId].name }
    local before = #M.sounds
    M.FireEvent("PLAYER_SOFT_INTERACT_CHANGED")
    check(T.Targets()[front] and T.Targets()[front].here and #M.sounds == before + 1, "a chest in front of you pings")
    M.loot = { front }
    M.FireEvent("LOOT_OPENED")
    M.loot = {}
    check(T.Targets()[front] == nil, "looting it lets it go")
    M.FireEvent("PLAYER_SOFT_INTERACT_CHANGED")
    check(T.Targets()[front] == nil, "and it isn't announced again")
    M.units.softinteract = nil

    -- known chest spots, nearest first, once you've checked one the next
    WP.Remove(mine, true)
    ns.DB.objects[990002] = { kind = "object", id = 990002, name = "Battered Chest", key = "batteredchest", fac = "", chest = true, points = { { m = here, x = hx + 0.012, y = hy }, { m = here, x = hx + 0.03, y = hy } } }
    ns.Set("treasureKnownSpots", true)
    local spot = T.Targets().spot
    check(spot and spot.wp and math.abs(spot.x - (hx + 0.012)) < 1e-6 and #M.sounds == before + 1, "known chest spots: the nearest, without a ping")
    WP.Remove(spot.wp, true) -- arrived
    M.Tick(5.1)
    spot = T.Targets().spot
    check(spot and math.abs(spot.x - (hx + 0.03)) < 1e-6, "then the next one")
    -- something live comes first
    M.vignettes["v-chest"] = { name = "Solid Chest", onMinimap = true, atlasName = "VignetteLoot", objectGUID = CHEST, pos = { 0.42, 0.62 } }
    M.Tick(1.1)
    check(WP.GetActive() == T.Targets()[CHEST].wp, "a chest that appears takes over from known spots")
    M.vignettes = {}

    -- off: everything is let go
    ns.Set("treasureKnownSpots", false)
    M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "treasure")
    check(ns.Get("treasureHunt") == false and next(T.Targets()) == nil and WP.Count() == 0, "/wp treasure turns it off and lets everything go")
    ns.DB.objects[990002] = nil
    M.vignettes = { ["v-1"] = { name = "Mother Fang", onWorldMap = true, isDead = false, pos = { 0.61, 0.5 } } }
end

-- treasure hunt keeps going: one find after another, each with its own ping
do
    local T = ns.Treasure
    WP.ClearAll(true)
    M.vignettes, M.sounds, M.raidNotices = {}, {}, {}
    ns.Set("treasureHunt", true)
    M.Tick(2)
    local pings = 0
    for i = 1, 3 do
        local guid = "GameObject-0-1-0-0-2843-00000001" .. i
        M.vignettes["v" .. i] = { name = "Solid Chest", onMinimap = true, atlasName = "VignetteLoot", objectGUID = guid, pos = { 0.40 + i * 0.01, 0.6 } }
        M.Tick(2)
        local t = T.Targets()[guid]
        check(t and t.wp and WP.GetActive() == t.wp and #M.sounds == pings + 1, "chest " .. i .. " in a row gets its own ping and the arrow")
        pings = #M.sounds
        M.vignettes["v" .. i] = nil
        M.Tick(2)
        check(T.Targets()[guid] == nil and WP.Count() == 0, "chest " .. i .. " taken: let go")
    end
    for i = 1, 2 do
        local guid = "Creature-0-1-0-0-471-00000002" .. i
        M.vignettes["r" .. i] = { name = "Mother Fang", onMinimap = true, atlasName = "VignetteKill", objectGUID = guid, pos = { 0.5, 0.5 + i * 0.01 } }
        M.Tick(2)
        check(T.Targets()[guid] and #M.sounds == pings + 1, "rare " .. i .. " in a row gets its own ping")
        pings = #M.sounds
        M.vignettes["r" .. i].isDead = true
        M.Tick(2)
        M.vignettes["r" .. i] = nil
        M.Tick(2)
    end
    -- /wp treasure status says what it sees and what it found
    M.vignettes = { now = { name = "Solid Chest", onMinimap = true, atlasName = "VignetteLoot", pos = { 0.47, 0.6 } }, far = { name = "Far Away", onWorldMap = true, pos = { 0.1, 0.1 } } }
    M.Tick(2)
    local before = #M.printed
    M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "treasure status")
    local out = table.concat(M.printed, "\n", before + 1)
    check(ns.Get("treasureHunt") == true and out:find(L.TREASURE_STATUS_MARKERS:format(1), 1, true) and out:find(L.TREASURE_STATUS_MAP_ONLY:format(1), 1, true)
        and out:find(L.TREASURE_STATUS_RECENT, 1, true) and out:find(L.TREASURE_VIA_MARKER, 1, true), "/wp treasure status lists markers and recent finds without turning it off")
    M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, "treasure")
    check(ns.Get("treasureHunt") == false and WP.Count() == 0, "/wp treasure still turns it off")
    M.vignettes = { ["v-1"] = { name = "Mother Fang", onWorldMap = true, isDead = false, pos = { 0.61, 0.5 } } }
end

-- the same ground under two map IDs (Zephras Isle is 2521 and 2665)
do
    M.maps[2665] = { mapID = 2665, name = "Zephras Isle", mapType = 3, parentMapID = 0, cont = 2800, top = 3000, left = 3000, w = 3000, h = 3000 }
    check(ns.Geo.SameMap(2521, 2665) and ns.Geo.SameMap(2665, 2521) and not ns.Geo.SameMap(2521, 37) and not ns.Geo.SameMap(nil, nil), "two map IDs for the same ground count as one zone")
    local e = { kind = "npc", id = 990077, name = "Skyborne Test Greeter", key = "skyborne test greeter", points = { { m = 2521, x = 0.5, y = 0.5 } } }
    ns.DB.units[990077] = e
    local list = ns.DB.Search("skyborne test", { npc = true, enemy = true }, { zone = 2665 })
    local found = false
    for _, r in ipairs(list) do
        found = found or r == e
    end
    check(found, "This zone only finds Zephras Isle's NPCs on either of its maps")
    ns.DB.units[990077] = nil
    M.maps[2665] = nil
end

-- a world position the game maps to a half-filled spot is skipped, not an error
do
    local real = C_Map.GetMapPosFromWorldPos
    C_Map.GetMapPosFromWorldPos = function(_, _, override)
        return override or 1429, CreateVector2D(0.5, 0 / 0)
    end
    local e = { kind = "place", id = 0, name = "Test Place", world = { { 0, 1429, -9000, 400 } } }
    local ok, pts = pcall(ns.DB.Points, e)
    check(ok and #pts == 0, "a spot without a usable y is skipped")
    local before, wasShown = #M.errors, WaypointTrackerFindFrame and WaypointTrackerFindFrame:IsShown()
    ns.Find.Show("goldsh")
    M.Tick(1)
    ns.Find.Show("zzqqxv")
    M.Tick(1)
    check(#M.errors == before, "Find searches without errors when the game gives no usable map spot")
    C_Map.GetMapPosFromWorldPos = real
    for _, tbl in ipairs({ "units", "objects", "quests", "places", "items" }) do
        for _, p in pairs(ns.DB[tbl] or {}) do
            p.points = nil
        end
    end
    if not wasShown then
        ns.Find.Toggle()
    end
end

-- "/way <name>": an exact name goes straight there, anything else searches
ns.Find.Toggle()
M.player.inst, M.player.wx, M.player.wy = 0, -1200, -1200 -- Elwynn Forest 40, 60
SlashCmdList.WAYPOINTTRACKERWAY(Name("units", HOGGER))
check(not WaypointTrackerFindFrame:IsShown() and WP.GetActive().title == Name("units", HOGGER), "/way with an exact name sets the arrow")
SlashCmdList.WAYPOINTTRACKERWAY("kobold")
check(WaypointTrackerFindFrame:IsShown() and fw.search:GetText() == "kobold", "/way with a partial name opens Find with that search")
ns.Find.Toggle()
-- two different things with the very same name: let the player choose
local hog = ns.DB.units[HOGGER]
ns.DB.units[999999] = { kind = "npc", id = 999999, name = hog.name, key = hog.key, fac = "", points = { { m = 37, x = 0.2, y = 0.2 } } }
SlashCmdList.WAYPOINTTRACKERWAY(hog.name)
check(WaypointTrackerFindFrame:IsShown() and fw.search:GetText() == hog.name, "/way with a name several things share opens Find")
ns.Find.Toggle()
ns.DB.units[999999] = nil
local printed = M.lastPrint
SlashCmdList.WAYPOINTTRACKERWAY("45")
check(not WaypointTrackerFindFrame:IsShown(), "/way with one number doesn't search")

-- Blizzard's Edit Mode: the arrow can be placed there, per layout
WP.ClearAll()
local af = ns.Arrow.frame
EditModeManagerFrame:EnterEditMode()
M.Tick(0.1)
local sel = WaypointTrackerArrowSelection
check(sel and sel:IsShown() and not sel.isSelected, "Edit Mode shows the arrow's blue box")
check(af:IsShown() and ns.Arrow.editing, "the arrow shows in Edit Mode even without a waypoint")
check(af:IsMouseEnabled() == false, "the arrow itself still ignores the mouse")
sel:RunScript("OnMouseDown")
check(sel.isSelected and WaypointTrackerEditModeDialog:IsShown(), "clicking it selects it and opens its settings")
check(EditModeManagerFrame.cleared > 0, "Blizzard's own frames are deselected")
sel:RunScript("OnDragStart")
af:ClearAllPoints()
af:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -200)
sel:RunScript("OnDragStop")
local layouts = ns.Get("arrowLayouts")
check(type(layouts) == "table" and layouts.Modern and layouts.Modern[3] == 300, "dragged spot saved for the Modern layout")
EditModeManagerFrame:SelectSystem({})
check(not sel.isSelected and not WaypointTrackerEditModeDialog:IsShown(), "picking a Blizzard frame deselects the arrow")
-- switching layout moves the arrow
M.editActive = 2
M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
M.Tick(0.1)
local point, _, _, x = af:GetPoint()
check(ns.Arrow.layout == "Classic" and point == "TOPLEFT" and x == 300, "a layout without its own spot uses the last one")
sel:RunScript("OnDragStart")
af:ClearAllPoints()
af:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 500, -200)
sel:RunScript("OnDragStop")
M.editActive = 1
M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
M.Tick(0.1)
point, _, _, x = af:GetPoint()
check(point == "TOPLEFT" and x == 300, "back to Modern: the arrow goes back to its spot there")
M.editActive = 2
M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
M.Tick(0.1)
point, _, _, x = af:GetPoint()
check(x == 500, "and Classic keeps its own spot")
sel:RunScript("OnMouseDown")
WaypointTrackerEditModeDialog.reset:Click()
point, _, _, x = af:GetPoint()
check(point == "CENTER" and x == 0, "Reset in the Edit Mode panel puts the arrow back")
EditModeManagerFrame:ExitEditMode()
M.Tick(0.1)
check(not sel:IsShown() and not ns.Arrow.editing and not WaypointTrackerEditModeDialog:IsShown(), "leaving Edit Mode hides the box and panel")
ns.Set("arrowLayouts", nil)

-- The arrow's text: grouped by default, own size and visibility, can move
-- on its own; Reset brings back place, size and visibility
local tf = ns.Arrow.textFrame
local tpoint, trel = tf:GetPoint()
check(tpoint == "TOP" and trel == af, "the text hangs under the arrow by default")
ns.Set("textScale", 1.4)
ns.Set("textAlpha", 0.5)
ns.Set("arrowScale", 0.7)
check(tf:GetScale() == 1.4 and tf:GetAlpha() == 0.5 and af:GetScale() == 0.7, "text and arrow have their own size and visibility")
ns.Arrow.SetMoving(true)
check(tf:IsMouseEnabled() and af:IsMouseEnabled(), "Move Arrow lets you drag both parts")
ns.Arrow.SetMoving(false)
ns.Set("textSeparate", true)
tpoint, trel = tf:GetPoint()
check(tpoint == "CENTER" and trel == UIParent, "moving the text separately keeps it where it was, on its own")
EditModeManagerFrame:EnterEditMode()
M.Tick(0.1)
local tsel = WaypointTrackerTextSelection
check(tsel and tsel:IsShown(), "Edit Mode gives the text its own box when it moves separately")
tsel:RunScript("OnMouseDown")
check(tsel.isSelected and not sel.isSelected and WaypointTrackerEditModeDialog:IsShown(), "selecting the text opens the same panel")
tsel:RunScript("OnDragStart")
tf:ClearAllPoints()
tf:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -40)
tsel:RunScript("OnDragStop")
local tl = ns.Get("textLayouts")
check(type(tl) == "table" and tl[ns.Arrow.layout] and tl[ns.Arrow.layout][3] == 40, "the text's spot is saved per layout")
point = af:GetPoint()
check(point == "CENTER", "moving the text leaves the arrow where it is")
ns.Set("textSeparate", false)
check(not tsel:IsShown(), "turning it off removes the text's own box")
tpoint, trel = tf:GetPoint()
check(tpoint == "TOP" and trel == af, "and the text goes back under the arrow")
ns.Set("textSeparate", true)
tpoint, _, _, x = tf:GetPoint()
check(tpoint == "TOPLEFT" and x == 40, "turning it back on remembers where the text was")
sel:RunScript("OnMouseDown")
WaypointTrackerEditModeDialog.reset:Click()
check(ns.Get("arrowScale") == 1 and ns.Get("arrowAlpha") == 0.8 and ns.Get("textScale") == 1 and ns.Get("textAlpha") == 0.9, "Reset brings back the default size and visibility")
tpoint, trel = tf:GetPoint()
check(ns.Get("textSeparate") == false and tpoint == "TOP" and trel == af, "Reset puts the text back under the arrow")
check(tf:GetScale() == 1 and af:GetScale() == 1, "and the frames follow")
EditModeManagerFrame:ExitEditMode()
M.Tick(0.1)
ns.Set("arrowLayouts", nil)
ns.Set("textLayouts", nil)

-- A waypoint set where you stand isn't reached (and removed) right away
WP.ClearAll()
M.player.wx, M.player.wy, M.player.inst = -1200, -1200, 0
local here = WP.AddHere("Camp")
M.Tick(1)
check(here and WP.IsValid(here) and WP.IsWaiting(here), "a waypoint set on you stays")
check(ns.Arrow.frame:IsShown(), "the arrow shows you're there")
M.player.wx = -1100 -- 100 yards away
M.Tick(1)
check(WP.IsValid(here) and not WP.IsWaiting(here), "walking away arms it")
M.player.wx = -1200
M.Tick(1)
check(not WP.IsValid(here), "coming back reaches it")
local far = WP.Add(37, 0.5, 0.5, { title = "Far" })
M.Tick(3.5) -- past the "You have arrived!" moment
M.player.wx, M.player.wy = -1000, -1500
M.Tick(1)
check(not WP.IsValid(far), "walking onto a far waypoint still reaches it")

-- Dying points the arrow at your body
WP.ClearAll()
local before = WP.Add(37, 0.2, 0.2, { title = "Before" })
M.player.wx, M.player.wy = -1200, -1200
M.player.dead = true
M.FireEvent("PLAYER_DEAD")
local corpse = WP.GetActive()
check(corpse and corpse ~= before and corpse.title == L.CORPSE_NAME and corpse.source == "corpse", "dying adds your corpse and points the arrow at it")
M.player.dead, M.player.ghost = false, true
M.player.wx = -300 -- released at the graveyard
M.FireEvent("PLAYER_ALIVE")
check(WP.GetActive() == corpse and WP.Count() == 2, "releasing your spirit keeps the corpse waypoint")
M.player.ghost = false
M.FireEvent("PLAYER_UNGHOST")
check(not WP.IsValid(corpse) and WP.GetActive() == before, "coming back to life removes it and goes back to the old waypoint")
M.player.ghost, M.player.corpse = true, { 37, 0.6, 0.4 }
ns.Fire("LOGIN")
local ghostCorpse = WP.GetActive()
check(ghostCorpse and ghostCorpse.source == "corpse" and near(ghostCorpse.x, 0.6), "logging in as a ghost finds your corpse")
M.player.ghost, M.player.corpse = false, nil
M.FireEvent("PLAYER_UNGHOST")
ns.Set("corpseWaypoint", false)
M.player.dead = true
M.FireEvent("PLAYER_DEAD")
check(WP.Count() == 1 and WP.GetActive().title == "Before", "the corpse waypoint can be turned off")
M.player.dead = false
ns.Set("corpseWaypoint", true)
WP.ClearAll()

-- Find: quests in your log use where the game's map shows them, and Find
-- opens on All
check(ns.DB.Load(), "database loads")
local liveQ = { id = 101, name = "The Fargodeep Mine", kind = "quest" }
local objs = ns.DB.QuestTargets(liveQ, "objective")
local p1 = objs[1] and ns.DB.Points(objs[1])[1]
check(p1 and p1.m == 37 and near(p1.x, 0.39), "a quest in your log points to where its map marker is")
local doneQ = { id = 102, name = "Report to Gryan", kind = "quest" }
local ends = ns.DB.QuestTargets(doneQ, "end")
local p2 = ends[1] and ns.DB.Points(ends[1])[1]
check(p2 and p2.m == 52, "a finished quest in your log points to its hand-in")
check(#ns.DB.QuestTargets({ id = 424242, name = "Unknown", kind = "quest" }, "objective") == 0, "quests not in your log don't get a live spot")
ns.Set("findTab", "quest")
ns.Find.Show("abc 50")
check(ns.Get("findTab") == "all", "Find opens on All when no tab is asked for")
ns.Find.Toggle()
ns.Find.Show(nil, "npc")
check(ns.Get("findTab") == "npc", "the Quests/NPCs/... buttons still open their tab")
ns.Find.Toggle()
ns.Set("findTab", "all")

-- main window: one Find button per kind
WaypointTracker_ToggleWindow()
for _, b in ipairs(ns.UI.widgets.find) do
    if b.tab == "enemy" then
        b:Click()
    end
end
check(WaypointTrackerFindFrame:IsShown() and ns.Get("findTab") == "enemy", "main window Enemies button opens Find on that tab")
ns.Find.Toggle()
WaypointTracker_ToggleWindow()
ns.Set("findTab", "all")
M.player.inst, M.player.wx, M.player.wy = 0, -1200, -1200

-- ---------------------------------------------------------------------------
-- Saving and loading again
-- ---------------------------------------------------------------------------
WP.ClearAll(true)
WP.Add(37, 0.2, 0.3, { title = "Saved one" })
WP.Add(52, 0.6, 0.7, { title = "Saved two" })
WP.Add(52, 0.1, 0.1, { title = "Temp", persistent = false })
WP.SetActive(WP.List()[1])
local saved = WaypointTrackerCharDB.waypoints
check(#saved == 2, "only persistent waypoints saved")
check(saved[1].active == true, "active one remembered")

-- simulate /reload with the same saved variables
M.FireEvent("PLAYER_LOGOUT")
M.frames = {}
M.eventFrames = {}
TomTom = nil
local ns2 = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
-- another addon sends a waypoint before PLAYER_LOGIN
TomTom:AddWaypoint(52, 0.9, 0.9, { title = "Early bird", crazy = false })
M.FireEvent("PLAYER_LOGIN")
check(ns2.WP.Count() == 3, "saved waypoints restored and early one kept (got " .. ns2.WP.Count() .. ")")
check(ns2.WP.GetActive() and ns2.WP.GetActive().title == "Saved one", "active restored")
check(not ns2.Learn.ScanProgress(), "after one finished scan, later ones run quietly")

-- TomTom installed: stay out of the way
M.frames = {}
M.eventFrames = {}
M.tomtomInstalled = true
TomTom = nil
SlashCmdList.WAYPOINTTRACKERWAY = nil
local ns3 = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
check(TomTom == nil, "no bridge when TomTom is installed")
check(SlashCmdList.WAYPOINTTRACKERWAY == nil, "/way left to TomTom")

-- another addon already has /way: leave it (and /wayb, /cway) alone
do
    M.frames = {}
    M.eventFrames = {}
    M.tomtomInstalled = false
    TomTom = nil
    SlashCmdList.WAYPOINTTRACKERWAY, SlashCmdList.WAYPOINTTRACKERWAYB, SlashCmdList.WAYPOINTTRACKERCWAY = nil, nil, nil
    local theirs = function() end
    SLASH_SOMEOTHERWAY1, SLASH_SOMEOTHERWAY2 = "/somewhere", "/WAY"
    SlashCmdList.SOMEOTHERWAY = theirs
    local saved = WaypointTrackerDB
    WaypointTrackerDB = nil
    local ns5 = M.LoadAddon("WaypointTracker", "WaypointTracker")
    M.FireEvent("ADDON_LOADED", "WaypointTracker")
    M.FireEvent("PLAYER_LOGIN")
    check(SlashCmdList.WAYPOINTTRACKERWAY == nil and SlashCmdList.WAYPOINTTRACKERWAYB == nil, "/way left to the addon that has it")
    check(SlashCmdList.SOMEOTHERWAY == theirs and ns5.settings.wayNoticeShown == true, "the other addon keeps /way, and we say so once")
    check(SlashCmdList.WAYPOINTTRACKER ~= nil, "/wp still works")
    SlashCmdList.SOMEOTHERWAY, SLASH_SOMEOTHERWAY1, SLASH_SOMEOTHERWAY2 = nil, nil, nil
    -- and when it's free again, it's ours
    M.frames = {}
    M.eventFrames = {}
    TomTom = nil
    local ns6 = M.LoadAddon("WaypointTracker", "WaypointTracker")
    M.FireEvent("ADDON_LOADED", "WaypointTracker")
    M.FireEvent("PLAYER_LOGIN")
    check(SlashCmdList.WAYPOINTTRACKERWAY ~= nil and SlashCmdList.WAYPOINTTRACKERCWAY ~= nil, "/way is ours when no one else has it")
    WaypointTrackerDB = saved
    M.tomtomInstalled = true
end

-- settings saved by earlier builds under their old names carry over
do
    local saved = WaypointTrackerDB
    WaypointTrackerDB = { version = 2, settings = { tomtomCompat = false, tomtomNoticeShown = true } }
    M.frames = {}
    M.eventFrames = {}
    TomTom = nil
    local ns4 = M.LoadAddon("WaypointTracker", "WaypointTracker")
    M.FireEvent("ADDON_LOADED", "WaypointTracker")
    M.FireEvent("PLAYER_LOGIN")
    check(ns4.Get("addonWaypoints") == false and ns4.settings.wayNoticeShown == true, "old setting names carry over")
    check(ns4.settings.tomtomCompat == nil and ns4.settings.tomtomNoticeShown == nil, "old setting names removed")
    WaypointTrackerDB = saved
end

-- ---------------------------------------------------------------------------
-- Untrusted input: imports, other addons, damaged saved files
do
    local sns = ns3
    local st = { npcs = {}, objects = {}, quests = {}, mailboxes = {}, items = {} }
    local nines = string.rep("9", 400)
    local text = table.concat({
        "WTL1\ttest\t1",
        "N\tnan\tNaN guy",
        "N\t" .. nines .. "\tHuge guy",
        "N\t-5\tNegative guy",
        "N\t77\t|cffff0000Red|r |TInterface\\Buttons\\WHITE8X8:2000:2000|tGuy\tinf\tinf\tvendor\t" .. nines .. ":1,1 1429:500,500,2000,2000",
        "Q\t88\tQuest\t\tU1,U1,X9\t\t\t\t\tU1,U1,U1",
        "Q\t88\tQuest\t\t\t\t\t\t\tU1,U2",
    }, "\n")
    local ok = pcall(sns.Learn.Import, text, st, true)
    check(ok, "import with NaN, huge and negative numbers doesn't error")
    local count = 0
    for id in pairs(st.npcs) do
        count = count + 1
        check(id == 77, "only the valid NPC id is kept (got " .. tostring(id) .. ")")
    end
    check(count == 1, "bad NPC ids are dropped")
    local e = st.npcs[77]
    check(e and e.name == "Red Guy", "escape codes are stripped from imported names (got " .. tostring(e and e.name) .. ")")
    check(e and e.level == nil, "an infinite level is refused")
    local maps = 0
    for m, list in pairs(e and e.spots or {}) do
        maps = maps + 1
        check(m == 1429 and #list == 2, "only the valid spot is kept")
    end
    check(maps == 1, "spots on impossible maps are dropped")
    check(st.quests[88].giver == "U1", "quest giver refs are cleaned and deduplicated")
    check(#st.quests[88].needs == 2, "importing twice doesn't duplicate needs (got " .. #st.quests[88].needs .. ")")

    check(sns.WP.Add(37, 0 / 0, 0.5) == nil, "NaN coordinates are refused")
    check(sns.WP.Add(37.5, 0.5, 0.5) == nil, "a fractional map ID is refused")
    local wp = sns.WP.Add(37, 0.31, 0.31, { title = "|Hitem:1|h[Link]|h" })
    check(wp and wp.title == "[Link]", "waypoint titles lose escape codes")

    local bad = TomTom and TomTom.AddWaypoint and TomTom:AddWaypoint(37, 0.4, 0.4, { callbacks = { distance = true }, from = {}, arrivaldistance = 0 / 0 })
    check(bad == nil or type(bad) == "table", "the TomTom bridge accepts bad options without error")

    check(sns.SavedPoint({ "NOWHERE", "CENTER", 1, 2 }) == nil, "a damaged saved position is ignored")
    local p1, p2, px, py = sns.SavedPoint({ "TOP", "BOGUS", "12", 5 })
    check(p1 == "TOP" and p2 == "TOP" and px == 12 and py == 5, "a saved position is repaired where it can be")
    check(sns.SavedPoint({ "TOP", "TOP", 0, 1 / 0 }) == nil, "an off-screen saved position is ignored")
end

-- ---------------------------------------------------------------------------
print(("%d passed, %d failed"):format(passed, failed))
print(("first Find search incl. loading the database: %.2fs, later searches: %.3fs"):format(searchTime or 0, searchSpeed or 0))
if #M.errors > 0 then
    print("Lua errors reported:")
    for _, e in ipairs(M.errors) do
        print("  " .. e)
    end
end
local unknown = {}
for k, n in pairs(M.unknownMethods) do
    unknown[#unknown + 1] = k
end
table.sort(unknown)
print("Frame methods used but not mocked (check they exist in WoW): " .. table.concat(unknown, ", "))
os.exit((failed == 0 and #M.errors == 0) and 0 or 1)
