-- World map coordinates and the waypoint overlay menu, with native and
-- older-client paths. Run from the repository root with Lua 5.1.
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

local legacy = arg[1] == "--legacy"
local delayed = arg[1] == "--delayed"
local coordsOn = arg[1] == "--coords-on"
local globalCVars = arg[1] == "--global-cvars"
local noCallbacks = legacy or arg[1] == "--no-cvar-callbacks"
local incompleteRegistry = arg[1] == "--incomplete-cvar-registry"
local map = WorldMapFrame
-- Model Blizzard's CVAR_UPDATE -> CVarCallbackRegistry path locally; the
-- shared mock has no CVar registry or CVar change events yet.
local cvarCallbacks = {}
CVarCallbackRegistry = nil
if not noCallbacks then CVarCallbackRegistry = {} end
if CVarCallbackRegistry and not incompleteRegistry then
    function CVarCallbackRegistry:RegisterCallback(key, fn, owner)
        cvarCallbacks[key] = { fn = fn, owner = owner }
    end
    local events = CreateFrame("Frame")
    events:RegisterEvent("CVAR_UPDATE")
    events:SetScript("OnEvent", function(_, _, key, value)
        local callback = cvarCallbacks[key]
        if callback then callback.fn(callback.owner, value) end
    end)
end
-- Record native menu enabled state without changing the shared mock.
local createMenu = MenuUtil.CreateContextMenu
MenuUtil.CreateContextMenu = function(owner, generator)
    return createMenu(owner, function(menuOwner, root)
        local createButton = root.CreateButton
        function root:CreateButton(...)
            local item = createButton(self, ...)
            local setEnabled = item.SetEnabled
            function item:SetEnabled(enabled)
                self.enabled = enabled
                setEnabled(self, enabled)
            end
            return item
        end
        generator(menuOwner, root)
    end)
end
local cvarAPI, getCVar, setCVar, getCVarBool = C_CVar, GetCVar, SetCVar, GetCVarBool
local writes = 0
local function TrackCVar(key, value)
    writes = writes + 1
    setCVar(key, value)
    M.FireEvent("CVAR_UPDATE", key, tostring(value))
end
SetCVar, C_CVar.SetCVar = TrackCVar, TrackCVar
if globalCVars then
    GetCVarBool, C_CVar = cvarAPI.GetCVarBool, nil
end
if legacy then
    C_CVar = nil
    M.cvars.worldMapShowPlayerCoords, M.cvars.worldMapShowCursorCoords = nil, nil
else
    -- Deliberately disagree with the addon preference, and keep the player's
    -- two coordinate choices different so login must preserve each one.
    M.cvars.worldMapShowPlayerCoords = coordsOn and "1" or "0"
    M.cvars.worldMapShowCursorCoords = coordsOn and "0" or "1"
end

local continuations = M.addonContinuations or {}
if delayed then
    M.addonContinuations = continuations
    WorldMapFrame = nil
    -- The shared mock does not yet simulate loading Blizzard_WorldMap.
    if not EventUtil then EventUtil = {} end
    if not EventUtil.ContinueOnAddOnLoaded then
        function EventUtil.ContinueOnAddOnLoaded(name, fn)
            continuations[#continuations + 1] = { name = name, fn = fn }
        end
    end
end

WaypointTrackerDB = coordsOn and { settings = { worldCoords = false } } or nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
local coordsChanges = 0
ns.On("SETTING_CHANGED", function(key)
    if key == "worldCoords" or key == nil then coordsChanges = coordsChanges + 1 end
end)
M.FireEvent("PLAYER_LOGIN")
check(writes == 0 and coordsChanges == 0, "login never writes CVars or broadcasts a coordinate setting change")
if not legacy then
    check(ns.settings.worldCoords == coordsOn, "login mirrors Blizzard player coordinates into the saved setting")
    check(M.cvars.worldMapShowPlayerCoords == (coordsOn and "1" or "0")
        and M.cvars.worldMapShowCursorCoords == (coordsOn and "0" or "1"),
        "login preserves separate player and cursor coordinate choices")
end
if not noCallbacks and not incompleteRegistry then
    check(cvarCallbacks.worldMapShowPlayerCoords and cvarCallbacks.worldMapShowPlayerCoords.owner == ns,
        "player-coordinate callback registers with the addon namespace as owner")
    local setting = Settings.GetSetting("WAYPOINTTRACKER_worldCoords")
    local api, notify = Settings, Settings.NotifyUpdate
    local notified, displayed
    Settings.NotifyUpdate = function(variable)
        notified, displayed = variable, setting:GetValue()
        notify(variable)
    end
    local function NativeCoords(on)
        local beforeWrites, beforeChanges = writes, coordsChanges
        local cursor = M.cvars.worldMapShowCursorCoords
        notified, displayed = nil, nil
        SetCVar("worldMapShowPlayerCoords", on and "1" or "0")
        check(ns.Get("worldCoords") == on and setting:GetValue() == on,
            "native coordinate toggle updates the saved setting and Settings proxy")
        check(notified == "WAYPOINTTRACKER_worldCoords" and displayed == on,
            "Settings is notified after mirroring the native coordinate choice")
        check(writes == beforeWrites + 1 and coordsChanges == beforeChanges
            and M.cvars.worldMapShowCursorCoords == cursor,
            "native coordinate toggle never writes back, broadcasts, or changes cursor coordinates")
    end
    NativeCoords(not coordsOn)
    M.player.combat = true
    local showCalls, hideCalls = M.uiPanelCalls.show, M.uiPanelCalls.hide
    NativeCoords(coordsOn)
    check(M.uiPanelCalls.show == showCalls and M.uiPanelCalls.hide == hideCalls and not M.actionBlocked,
        "native coordinate callback uses no protected panel calls in combat")
    M.player.combat = false
    notified = nil
    SetCVar("worldMapShowCursorCoords", coordsOn and "1" or "0")
    check(ns.Get("worldCoords") == coordsOn and not notified,
        "cursor-only changes preserve the player-coordinate setting")
    SetCVar("worldMapShowCursorCoords", coordsOn and "0" or "1")
    Settings = nil
    SetCVar("worldMapShowPlayerCoords", coordsOn and "0" or "1")
    check(ns.Get("worldCoords") == not coordsOn, "native coordinates sync without Settings")
    Settings = api
    Settings.NotifyUpdate = nil
    SetCVar("worldMapShowPlayerCoords", coordsOn and "1" or "0")
    check(ns.Get("worldCoords") == coordsOn, "native coordinates sync without NotifyUpdate")
    Settings.NotifyUpdate = function() error("Settings refresh unavailable") end
    local ok = pcall(SetCVar, "worldMapShowPlayerCoords", coordsOn and "0" or "1")
    check(ok and ns.Get("worldCoords") == not coordsOn, "a failed Settings refresh cannot break native coordinates")
    Settings.NotifyUpdate = notify
    SetCVar("worldMapShowPlayerCoords", coordsOn and "1" or "0")
end
if delayed then
    check(not WaypointTrackerMapButton, "button waits for the world map")
    check(#continuations == 2, "pins and button wait for Blizzard_WorldMap")
    ns.Set("worldCoords", false)
    M.cvars.worldMapShowCursorCoords = "1" -- Blizzard's UI changed it before map load.
    local beforeLoad = writes
    WorldMapFrame = map
    for _, continuation in ipairs(continuations) do
        check(continuation.name == "Blizzard_WorldMap", "correct addon load continuation")
        continuation.fn()
        continuation.fn() -- load notifications must not duplicate UI
    end
    check(writes == beforeLoad and M.cvars.worldMapShowPlayerCoords == "0"
        and M.cvars.worldMapShowCursorCoords == "1", "delayed map setup preserves native CVars without writing")
end

local WP, L = ns.WP, ns.L
local function CoordsFrames()
    local frames = {}
    for _, frame in ipairs(M.frames) do
        if frame:GetParent() == map.ScrollContainer and frame:GetScript("OnUpdate") then
            frames[#frames + 1] = frame
        end
    end
    return frames
end
local function FindItem(menu, kind, text)
    for _, item in ipairs(menu and menu.items or {}) do
        if item.kind == kind and item.text == text then return item end
    end
end
local function Radios(menu)
    local items = {}
    for _, item in ipairs(menu and menu.items or {}) do
        if item.kind == "radio" then items[#items + 1] = item end
    end
    return items
end

if legacy then
    local frames = CoordsFrames()
    check(#frames == 1 and frames[1]:IsShown(), "legacy coordinates created at login")
else
    check(#CoordsFrames() == 0, "native coordinates have no addon line")
    ns.Set("worldCoords", false)
    check(M.cvars.worldMapShowPlayerCoords == "0" and M.cvars.worldMapShowCursorCoords == "0",
        "turning coordinates off sets both CVars to zero")
    ns.Set("worldCoords", true)
    check(M.cvars.worldMapShowPlayerCoords == "1" and M.cvars.worldMapShowCursorCoords == "1",
        "turning coordinates on sets both CVars to one")
    C_CVar = nil
    ns.Set("worldCoords", false)
    check(M.cvars.worldMapShowPlayerCoords == "0" and M.cvars.worldMapShowCursorCoords == "0"
        and #CoordsFrames() == 0, "global GetCVar detects native coordinates")
    C_CVar, GetCVar, SetCVar = cvarAPI, nil, nil
    ns.Set("worldCoords", true)
    check(M.cvars.worldMapShowPlayerCoords == "1" and M.cvars.worldMapShowCursorCoords == "1",
        "C_CVar setters work without global CVar functions")
    GetCVar, SetCVar = getCVar, setCVar
    GetCVarBool = getCVarBool
end

local button = WaypointTrackerMapButton
check(button ~= nil, "map button exists after login or map load")
check(button:GetParent() == map.ScrollContainer, "button belongs to the canvas container")
check(button:GetWidth() == 32 and button:GetHeight() == 32, "button matches Blizzard's 32 by 32 map control")
check(button:GetFrameLevel() == map.ScrollContainer:GetFrameLevel() + 510, "button sits above canvas pins")
check(button.Icon:GetTexture() == ns.MEDIA .. "Pin", "button uses the waypoint pin icon")
check(button.Background:GetTexture() == "Interface\\Minimap\\UI-Minimap-Background"
    and button.Background:GetWidth() == 25 and button.Background:GetHeight() == 25,
    "button has Blizzard's round minimap backing")
local bgPoint, _, _, bgX, bgY = button.Background:GetPoint()
check(bgPoint == "TOPLEFT" and bgX == 3 and bgY == -4, "background matches Blizzard's inset")
local iconPoint, _, _, iconX, iconY = button.Icon:GetPoint()
check(button.Icon:GetWidth() == 20 and button.Icon:GetHeight() == 20
    and iconPoint == "TOPLEFT" and iconX == 7 and iconY == -6, "pin matches Blizzard's size and inset")
local red, green, blue = button.Icon:GetVertexColor()
check(red == 1 and green == 0.82 and blue == 0, "map button pin is gold")
local point, relative, relativePoint, x, y = button:GetPoint()
check(point == "TOP" and relative == map.WorldMapTrackingPinButton and relativePoint == "BOTTOM"
    and x == 0 and y == 0, "button anchors directly below Blizzard's pin button")

map:Show()
WP.ClearAll(true)
check(button:IsVisible(), "map button remains visible with no waypoints")
button:RunScript("OnClick", "LeftButton")
local emptyMenu = M.lastMenu
local emptyClear = FindItem(emptyMenu, "button", L.CLEAR_ALL)
check(emptyClear and emptyClear.enabled == false, "empty map disables Remove All")
local previousPopup = M.lastPopup
emptyClear.fn()
check(M.lastPopup == previousPopup, "empty removal callback does not open a zero-waypoint popup")
check(#Radios(emptyMenu) == 0 and FindItem(emptyMenu, "checkbox", L.WORLD_PINS)
    and FindItem(emptyMenu, "checkbox", L.WORLD_COORDS), "empty map still offers display toggles")

local here = WP.Add(37, 0.4, 0.5, { title = "Here", setActive = false })
local second = WP.Add(37, 0.6, 0.7, { title = "Second", setActive = false })
local westfall = WP.Add(52, 0.5, 0.5, { title = "Westfall", setActive = false })
local kalimdor = WP.Add(1411, 0.5, 0.5, { title = "Kalimdor", setActive = false })
WP.SetActive(here, true)
map.mapID = 37
button:RunScript("OnClick", "LeftButton")
local menu = M.lastMenu
check(menu.items[1].kind == "title" and menu.items[1].text == L.MENU_QUICK_TITLE, "menu has the addon title")
check(#Radios(menu) == 2 and FindItem(menu, "radio", WP.ShortName(here))
    and FindItem(menu, "radio", WP.ShortName(second)), "zone menu lists waypoints on this map")
check(not FindItem(menu, "radio", WP.ShortName(westfall))
    and not FindItem(menu, "radio", WP.ShortName(kalimdor)), "zone menu omits waypoints outside the map")
local hereItem, secondItem = FindItem(menu, "radio", WP.ShortName(here)), FindItem(menu, "radio", WP.ShortName(second))
check(hereItem.isSelected() and not secondItem.isSelected(), "active waypoint is checked")
secondItem.fn()
check(WP.GetActive() == second and secondItem.isSelected() and not hereItem.isSelected(), "radio points to its own waypoint")
hereItem.fn()
check(WP.GetActive() == here, "each radio keeps its waypoint callback")
local pinsItem = FindItem(menu, "checkbox", L.WORLD_PINS)
local pins = ns.Get("worldPins")
pinsItem.fn()
check(ns.Get("worldPins") ~= pins and pinsItem.isSelected() == ns.Get("worldPins"), "pins checkbox toggles the setting")
check(#map.pins == 0, "pins toggle refreshes the map provider")
pinsItem.fn()
check(#map.pins == 2, "turning pins back on restores current map pins")
local coordsItem = FindItem(menu, "checkbox", L.WORLD_COORDS)
coordsItem.fn()
check(not ns.Get("worldCoords") and not coordsItem.isSelected(), "coordinates checkbox toggles off")
if legacy then
    check(not CoordsFrames()[1]:IsShown(), "coordinates checkbox hides the legacy line")
else
    check(M.cvars.worldMapShowPlayerCoords == "0" and M.cvars.worldMapShowCursorCoords == "0",
        "coordinates checkbox updates both native CVars")
end
coordsItem.fn()

map.mapID = 13
button:RunScript("OnClick", "LeftButton")
menu = M.lastMenu
check(#Radios(menu) == 3 and FindItem(menu, "radio", WP.ShortName(westfall)), "continent menu includes translated zone waypoints")
check(not FindItem(menu, "radio", WP.ShortName(kalimdor)), "continent menu excludes the other continent")
map.mapID = nil
button:RunScript("OnClick", "LeftButton")
check(#Radios(M.lastMenu) == 0, "map without an ID keeps only controls")
map.mapID = 37

M.tooltip = {}
button:RunScript("OnEnter")
check(M.tooltip[1] == L.MAP_BUTTON_TOOLTIP and M.tooltip[2] == L.MAP_BUTTON_CLICK, "map button tooltip shows title and click hint")
button:RunScript("OnLeave")
check(not GameTooltip:IsShown(), "map button tooltip hides on leave")

button:RunScript("OnClick", "LeftButton")
local clear = FindItem(M.lastMenu, "button", L.CLEAR_ALL)
check(clear.enabled == true, "Remove All is enabled with waypoints")
clear.fn()
check(M.lastPopup == "WAYPOINTTRACKER_CLEAR_ALL" and M.lastPopupArgs[1] == 4,
    "clear all asks with the live waypoint count before opening any tab")
check(WP.Count() == 4, "clear all waits for confirmation")
StaticPopupDialogs.WAYPOINTTRACKER_CLEAR_ALL.OnCancel()
check(WP.Count() == 4, "cancelling clear all keeps waypoints")
local printedBeforeClear = #M.printed
M.autoAcceptPopup = true
clear.fn()
M.autoAcceptPopup = false
check(WP.Count() == 0 and button:IsVisible(), "confirming clears waypoints and keeps the button")
check(#M.printed == printedBeforeClear, "map popup clears silently despite registering after the Waypoints tab")
StaticPopupDialogs.WAYPOINTTRACKER_CLEAR_ALL.OnAccept()
check(#M.printed == printedBeforeClear, "accepting an already empty clear-all popup stays silent")

M.player.combat = true
local showCalls, hideCalls = M.uiPanelCalls.show, M.uiPanelCalls.hide
button:RunScript("OnClick", "LeftButton")
FindItem(M.lastMenu, "checkbox", L.WORLD_PINS).fn()
FindItem(M.lastMenu, "checkbox", L.WORLD_COORDS).fn()
check(M.uiPanelCalls.show == showCalls and M.uiPanelCalls.hide == hideCalls and not M.actionBlocked,
    "map menu uses no protected panel calls in combat")
M.player.combat = false
ns.Set("worldCoords", true)

-- Unknown CVars can return nil or throw on older clients.
C_CVar = nil
M.cvars.worldMapShowPlayerCoords, M.cvars.worldMapShowCursorCoords = nil, nil
ns.Set("worldCoords", false)
local frames = CoordsFrames()
check(#frames == 1 and not frames[1]:IsShown(), "missing CVars create one hidden fallback line")
ns.Set("worldCoords", true)
check(CoordsFrames()[1] == frames[1] and frames[1]:IsShown(), "fallback line is reused and shown")
M.Tick(0.2)
local text
for _, frame in ipairs(M.frames) do
    if frame:GetParent() == frames[1] and frame:GetObjectType() == "FontString" then text = frame:GetText() end
end
check(text and text:find(L.YOU, 1, true), "fallback line still shows player coordinates")
GetCVar = function() error("unknown CVar") end
ns.Set("worldCoords", false)
check(not frames[1]:IsShown(), "throwing legacy getter safely hides fallback coordinates")
C_CVar = { GetCVarInfo = function() error("unknown CVar") end }
ns.Set("worldCoords", true)
check(frames[1]:IsShown(), "throwing native getter safely uses the fallback")
GetCVar, SetCVar, C_CVar = getCVar, setCVar, cvarAPI
M.cvars.worldMapShowPlayerCoords, M.cvars.worldMapShowCursorCoords = "0", "0"
ns.ResetSettings()
check(not frames[1]:IsShown() and M.cvars.worldMapShowPlayerCoords == "1"
    and M.cvars.worldMapShowCursorCoords == "1", "reset reapplies native coordinates without overlapping the fallback")

-- Exercise the overlay's older-client anchor without reloading other modules.
local login
local buttonNS = setmetatable({ On = function(event, fn) if event == "LOGIN" then login = fn end end }, { __index = ns })
map.WorldMapTrackingPinButton, map.GetCanvasContainer = false, false
assert(loadfile("WaypointTracker/MapButton.lua"))("WaypointTracker", buttonNS)
login()
local fallbackButton = WaypointTrackerMapButton
point, relative, relativePoint, x, y = fallbackButton:GetPoint()
check(fallbackButton:GetParent() == map.ScrollContainer and point == "TOPRIGHT"
    and relative == map.ScrollContainer and relativePoint == "TOPRIGHT" and x == -4 and y == -60,
    "older map anchors the button at the canvas top right")
login()
check(WaypointTrackerMapButton == fallbackButton, "repeated setup reuses the map button")
MenuUtil = nil
previousPopup = M.lastPopup
fallbackButton:RunScript("OnClick", "LeftButton")
check(M.lastPopup == previousPopup, "empty fallback map menu cannot open a clear-all popup")
check(ns.Widgets.lastMenu and FindItem(ns.Widgets.lastMenu, "checkbox", L.WORLD_PINS), "map menu fallback builds display controls")
map:Hide()
check(not button:IsVisible() and not fallbackButton:IsVisible(), "map buttons hide with their parent map")

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
