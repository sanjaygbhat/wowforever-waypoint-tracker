-- A small fake of the WoW API, just enough to load and exercise the addon
-- outside the game with plain Lua 5.1. Any frame method we don't implement
-- is recorded so it can be checked against the real API by hand.
local M = {}

M.unknownMethods = {}
M.frames = {}
M.printed = {}
M.sounds = {}
M.errors = {}

local function noop() end

-- ---------------------------------------------------------------------------
-- Lua helpers WoW adds
-- ---------------------------------------------------------------------------
function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
tinsert = table.insert
tremove = table.remove
strsub = string.sub
strfind = string.find
format = string.format

function Mixin(object, ...)
    for i = 1, select("#", ...) do
        local mixin = select(i, ...)
        for k, v in pairs(mixin) do
            object[k] = v
        end
    end
    return object
end

function CreateFromMixins(...)
    return Mixin({}, ...)
end

local Vector2D = {}
Vector2D.__index = Vector2D
function Vector2D:GetXY()
    return self.x, self.y
end
-- WT_PLAIN_VECTORS=1: every position the game hands back is a plain
-- { x, y } table without :GetXY(), as some are in WoW Forever
local plainVectors = os.getenv("WT_PLAIN_VECTORS") == "1"
function CreateVector2D(x, y)
    if plainVectors then
        return { x = x, y = y }
    end
    return setmetatable({ x = x, y = y }, Vector2D)
end

function geterrorhandler()
    return function(err)
        table.insert(M.errors, err)
    end
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------
local Frame = {}
local FrameMT = {
    __index = function(t, k)
        local v = Frame[k]
        if v ~= nil then
            return v
        end
        -- unknown method: record it and return a no-op
        if type(k) == "string" and k:match("^[A-Z]") then
            M.unknownMethods[k] = (M.unknownMethods[k] or 0) + 1
            return noop
        end
        return nil
    end,
}

local function NewObject(kind, name, parent)
    local o = setmetatable({
        _kind = kind,
        _name = name,
        _parent = parent,
        _shown = true,
        _scripts = {},
        _points = {},
        _w = 0,
        _h = 0,
        _text = nil,
        _alpha = 1,
        _scale = 1,
        _mouse = false,
        _level = 1,
    }, FrameMT)
    if name then
        _G[name] = o
    end
    table.insert(M.frames, o)
    return o
end
M.NewObject = NewObject

function Frame:GetName()
    return self._name
end
function Frame:GetParent()
    return self._parent
end
function Frame:SetParent(p)
    self._parent = p
end
function Frame:IsObjectType(t)
    return self._kind:lower() == t:lower()
end
function Frame:GetObjectType()
    return self._kind
end
function Frame:SetScript(event, fn)
    self._scripts[event] = fn
end
function Frame:GetScript(event)
    return self._scripts[event]
end
function Frame:HookScript(event, fn)
    local old = self._scripts[event]
    if old then
        self._scripts[event] = function(...)
            old(...)
            fn(...)
        end
    else
        self._scripts[event] = fn
    end
end
function Frame:RunScript(event, ...)
    local fn = self._scripts[event]
    if fn then
        return fn(self, ...)
    end
end
function Frame:Show()
    local was = self:IsVisible()
    self._shown = true
    if not was and self:IsVisible() then
        self:RunScript("OnShow")
    end
end
function Frame:Hide()
    local was = self:IsVisible()
    self._shown = false
    if was then
        self:RunScript("OnHide")
    end
end
function Frame:SetShown(v)
    if v then
        self:Show()
    else
        self:Hide()
    end
end
function Frame:IsShown()
    return self._shown
end
function Frame:IsVisible()
    local f = self
    while f do
        if not f._shown then
            return false
        end
        f = f._parent
    end
    return true
end
function Frame:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then
        rel, relPoint, x, y = nil, nil, rel, relPoint
    end
    self._points = { { point, rel, relPoint or point, x or 0, y or 0 } }
end
function Frame:ClearAllPoints()
    self._points = {}
end
function Frame:GetPoint(i)
    local p = self._points[i or 1]
    if p then
        return p[1], p[2], p[3], p[4], p[5]
    end
end
function Frame:SetAllPoints() end
function Frame:SetFontString(fs)
    self._fontString = fs
end
function Frame:GetFontString()
    return self._fontString
end
function Frame:SetSize(w, h)
    self._w, self._h = w, h
end
function Frame:SetWidth(w)
    self._w = w
end
function Frame:SetHeight(h)
    self._h = h
end
function Frame:GetWidth()
    return self._w
end
function Frame:GetHeight()
    return self._h
end
function Frame:GetSize()
    return self._w, self._h
end
function Frame:GetCenter()
    return 500, 400
end
function Frame:SetAlpha(a)
    self._alpha = a
end
function Frame:GetAlpha()
    return self._alpha
end
function Frame:SetScale(s)
    self._scale = s
end
function Frame:GetScale()
    return self._scale
end
function Frame:GetEffectiveScale()
    return 1
end
function Frame:EnableMouse(v)
    self._mouse = v
end
function Frame:IsMouseEnabled()
    return self._mouse
end
function Frame:GetFrameLevel()
    return self._level
end
function Frame:SetFrameLevel(l)
    self._level = l
end
function Frame:IsMouseOver()
    return false
end
function Frame:CreateTexture(name)
    local t = NewObject("Texture", name, self)
    return t
end
function Frame:CreateFontString(name)
    local fs = NewObject("FontString", name, self)
    return fs
end
function Frame:CreateAnimationGroup()
    return NewObject("AnimationGroup", nil, self)
end
-- regions
function Frame:SetText(t)
    self._text = t
    if self._kind == "EditBox" then
        self:RunScript("OnTextChanged", false)
    end
end
function Frame:GetText()
    if self._kind == "EditBox" then
        return self._text or ""
    end
    return self._text
end
function Frame:GetStringWidth()
    return #(tostring(self._text or "")) * 7
end
function Frame:SetTexCoord(...)
    self._texcoord = { ... }
end
function Frame:GetTexCoord()
    return unpack(self._texcoord or {})
end
function Frame:SetVertexColor(r, g, b, a)
    self._color = { r, g, b, a }
end
function Frame:GetVertexColor()
    return unpack(self._color or { 1, 1, 1, 1 })
end
function Frame:SetTexture(t)
    self._texture = t
end
function Frame:GetTexture()
    return self._texture
end
-- check buttons
function Frame:SetChecked(v)
    self._checked = v and true or false
end
function Frame:GetChecked()
    return self._checked
end
function Frame:Click(button)
    if self._kind == "CheckButton" then
        self._checked = not self._checked
    end
    self:RunScript("OnClick", button or "LeftButton", false)
end
-- sliders
function Frame:SetMinMaxValues(a, b)
    self._min, self._max = a, b
    local v = self._value or 0
    if v < a then
        self:SetValue(a)
    elseif v > b then
        self:SetValue(b)
    end
end
function Frame:GetMinMaxValues()
    return self._min, self._max
end
function Frame:SetValue(v)
    if self._value ~= v then
        self._value = v
        self:RunScript("OnValueChanged", v, true)
    end
end
function Frame:GetValue()
    return self._value or 0
end
-- edit boxes
function Frame:SetFocus()
    M.focus = self
    self:RunScript("OnEditFocusGained")
end
function Frame:ClearFocus()
    if M.focus == self then
        M.focus = nil
        self:RunScript("OnEditFocusLost")
    end
end
function Frame:HasFocus()
    return M.focus == self
end
function Frame:Type(text)
    self._text = text
    self:RunScript("OnTextChanged", true)
end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
-- events this client doesn't know: registering them throws, like the game
M.unknownEvents = {}
function Frame:RegisterEvent(e)
    if M.unknownEvents[e] then
        error(('Attempt to register unknown event "%s"'):format(e), 2)
    end
    M.eventFrames[e] = M.eventFrames[e] or {}
    table.insert(M.eventFrames[e], self)
end
function Frame:UnregisterEvent() end
function Frame:SetBackdrop(b)
    self._backdrop = b
end
function Frame:SetScrollChild(c)
    self._child = c
end
function Frame:SetFontObject(f)
    self._font = f
end
function Frame:SetHighlightTexture() end
function Frame:SetNormalTexture() end
function Frame:SetPushedTexture() end
function Frame:SetThumbTexture() end
function Frame:GetHighlightTexture()
    return NewObject("Texture", nil, self)
end

M.eventFrames = {}

function CreateFrame(kind, name, parent, template)
    local f = NewObject(kind, name, parent)
    f._template = template
    if template == "EditModeSystemSelectionTemplate" then
        -- the parts of Blizzard's Edit Mode selection box addons use
        function f:ShowHighlighted()
            self.isSelected = false
            self:Show()
        end
        function f:ShowSelected()
            self.isSelected = true
            self:Show()
        end
    end
    if template and template:find("UIPanelScrollFrameTemplate") then
        f.ScrollBar = NewObject("Slider", nil, f)
    end
    return f
end

UIParent = NewObject("Frame", "UIParent")
Minimap = NewObject("Frame", "Minimap", UIParent)
Minimap:SetSize(198, 198)
GameTooltip = NewObject("GameTooltip", "GameTooltip", UIParent)
GameTooltipTextLeft1 = NewObject("FontString", "GameTooltipTextLeft1", GameTooltip)
function GameTooltip:GetOwner()
    return M.tooltipOwner
end
function GameTooltip:GetUnit()
    return nil
end
function GameTooltip:AddLine(text)
    M.tooltip = M.tooltip or {}
    table.insert(M.tooltip, text)
end
DEFAULT_CHAT_FRAME = NewObject("Frame", "ChatFrame1", UIParent)
function DEFAULT_CHAT_FRAME:AddMessage(msg)
    table.insert(M.printed, msg)
end
UISpecialFrames = {}
SlashCmdList = {}
ChatFontNormal = {}

function M.FireEvent(event, ...)
    for _, f in ipairs(M.eventFrames[event] or {}) do
        f:RunScript("OnEvent", event, ...)
    end
end

function M.Tick(seconds, step)
    step = step or 0.05
    local t = 0
    while t < seconds - 1e-9 do
        M.now = M.now + step
        t = t + step
        local timers = M.timers
        M.timers = {}
        for _, tm in ipairs(timers) do
            if tm.at <= M.now then
                tm.fn()
            else
                table.insert(M.timers, tm)
            end
        end
        for _, f in ipairs(M.frames) do
            local fn = f._scripts.OnUpdate
            if fn and f:IsVisible() then
                fn(f, step)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Game state + APIs
-- ---------------------------------------------------------------------------
M.now = 1000
M.timers = {}
-- The player. Moving takes a moment of game time (like in the game, where
-- your position never changes within one frame).
local playerState = { wx = -600, wy = -1200, inst = 0, facing = 0, combat = false, taxi = false }
M.player = setmetatable({}, {
    __index = playerState,
    __newindex = function(_, k, v)
        playerState[k] = v
        M.now = M.now + 0.001
    end,
})
M.locale = os.getenv("WT_LOCALE") or "enUS"
M.addonsLoaded = { WaypointTracker = true }
M.cvars = { rotateMinimap = "0" }

function GetTime()
    return M.now
end
function time()
    return math.floor(M.now)
end
function GetLocale()
    return M.locale
end
-- units: M.units[token] = { guid, name, reaction, level }
M.units = {}
function UnitName(unit)
    local u = M.units[unit]
    if u then
        return u.name
    end
    return "Tester"
end
function UnitGUID(unit)
    local u = M.units[unit]
    if u then
        return u.guid
    end
    return "Player-1"
end
function UnitReaction(unit)
    local u = M.units[unit]
    return u and u.reaction
end
function UnitLevel(unit)
    local u = M.units[unit]
    return u and u.level or 10
end
function UnitIsGhost()
    return M.player.ghost and true or false
end
function UnitIsDeadOrGhost()
    return (M.player.dead or M.player.ghost) and true or false
end
C_DeathInfo = {
    GetCorpseMapPosition = function(mapID)
        local c = M.player.corpse
        if c and c[1] == mapID then
            return CreateVector2D(c[2], c[3])
        end
    end,
}
function UnitPosition()
    if M.player.noPosition then
        return nil
    end
    return M.player.wx, M.player.wy, 0, M.player.inst
end
function GetPlayerFacing()
    return M.player.facing
end
function InCombatLockdown()
    return M.player.combat
end
function UnitOnTaxi()
    return M.player.taxi
end
function IsShiftKeyDown()
    return M.shift
end
function IsControlKeyDown()
    return M.ctrl
end
function IsAltKeyDown()
    return M.alt
end
function PlaySound(id)
    table.insert(M.sounds, id)
end
function GetCVar(k)
    return M.cvars[k]
end
function GetCursorPosition()
    return 0, 0
end
function HideUIPanel(f)
    f:Hide()
end
function issecretvalue()
    return false
end
-- the game's tooltip data hooks (pointing at a world object shows its name)
M.tooltipPostCalls = {}
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
        M.tooltipPostCalls[kind] = M.tooltipPostCalls[kind] or {}
        table.insert(M.tooltipPostCalls[kind], fn)
    end,
}
function M.ShowObjectTooltip(name)
    for _, fn in ipairs(M.tooltipPostCalls[Enum.TooltipDataType.Object] or {}) do
        fn(GameTooltip, { type = Enum.TooltipDataType.Object, lines = { { leftText = name } } })
    end
end

-- hooks and Blizzard's callback registry
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then
        t, name, fn = _G, t, name
    end
    local orig = t[name]
    t[name] = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
end
EventRegistry = { _callbacks = {} }
function EventRegistry:RegisterCallback(event, fn, owner)
    self._callbacks[event] = self._callbacks[event] or {}
    table.insert(self._callbacks[event], fn)
end
function EventRegistry:TriggerEvent(event, ...)
    for _, fn in ipairs(self._callbacks[event] or {}) do
        fn(nil, ...)
    end
end
-- Blizzard's HUD Edit Mode
M.editLayouts = { "Modern", "Classic" }
M.editActive = 1
EditModeManagerFrame = { active = false, selected = nil, cleared = 0 }
function EditModeManagerFrame:GetActiveLayoutInfo()
    return { layoutName = M.editLayouts[M.editActive] }
end
function EditModeManagerFrame:IsEditModeActive()
    return self.active
end
function EditModeManagerFrame:ClearSelectedSystem()
    self.cleared = self.cleared + 1
end
function EditModeManagerFrame:SelectSystem(frame)
    self.selected = frame
end
function EditModeManagerFrame:EnterEditMode()
    self.active = true
    EventRegistry:TriggerEvent("EditMode.Enter")
end
function EditModeManagerFrame:ExitEditMode()
    self.active = false
    EventRegistry:TriggerEvent("EditMode.Exit")
end

C_Timer = {
    After = function(delay, fn)
        table.insert(M.timers, { at = M.now + delay, fn = fn })
    end,
}
SOUNDKIT = { MAP_PING = 3175, IG_MAINMENU_OPTION_CHECKBOX_ON = 856, RAID_WARNING = 8959 }
Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Corpse = 3, Object = 4 }

C_AddOns = {
    GetAddOnMetadata = function(name, field)
        if field == "Version" then
            return "1.0.0-test"
        end
    end,
    IsAddOnLoaded = function(name)
        return M.addonsLoaded[name] or false
    end,
    GetAddOnEnableState = function(name)
        if name == "TomTom" then
            return M.tomtomInstalled and 2 or 0
        end
        return 2
    end,
    IsAddOnLoadable = function()
        return true
    end,
    -- loads WaypointTracker_Data from disk, like the game would
    LoadAddOn = function(name)
        if name ~= "WaypointTracker_Data" or M.noDataAddon then
            return false, "MISSING"
        end
        local dir = "WaypointTracker_Data/"
        local toc = assert(io.open(dir .. name .. ".toc")):read("*a")
        for line in toc:gmatch("[^\r\n]+") do
            if not line:match("^##") and line:match("%.lua%s*$") then
                assert(loadfile(dir .. line:gsub("%s+$", "")))(name, {})
            end
        end
        M.addonsLoaded[name] = true
        return true
    end,
}

-- Fake world ------------------------------------------------------------------
-- Each zone is a rectangle in world yards: top (north) edge, left (west)
-- edge, width and height. World x grows north, world y grows west, like the
-- real game.
M.maps = {
    [947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 0 },
    [13] = { mapID = 13, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947, cont = 0, top = 4000, left = 4000, w = 12000, h = 16000 },
    [12] = { mapID = 12, name = "Kalimdor", mapType = 2, parentMapID = 947, cont = 1, top = 8000, left = 6000, w = 12000, h = 16000 },
    [37] = { mapID = 37, name = "Elwynn Forest", mapType = 3, parentMapID = 13, cont = 0, top = 0, left = 0, w = 3000, h = 2000 },
    [52] = { mapID = 52, name = "Westfall", mapType = 3, parentMapID = 13, cont = 0, top = -2000, left = 500, w = 2500, h = 2500 },
    [84] = { mapID = 84, name = "Stormwind City", mapType = 3, parentMapID = 13, cont = 0, top = 1200, left = 600, w = 1200, h = 1100 },
    [1] = { mapID = 1, name = "Durotar", mapType = 3, parentMapID = 12, cont = 1, top = 0, left = -3000, w = 3000, h = 3500 },
    [1411] = { mapID = 1411, name = "Élan Test Zone", mapType = 3, parentMapID = 12, cont = 1, top = 5000, left = 3000, w = 1000, h = 1000 },
    -- Tirisfal Glades, a phased copy of it, and a small map inside it
    [18] = { mapID = 18, name = "Tirisfal Glades", mapType = 3, parentMapID = 13, cont = 0, top = 12000, left = 3000, w = 4000, h = 3500 },
    [2070] = { mapID = 2070, name = "Tirisfal Glades", mapType = 3, parentMapID = 13, cont = 0, top = 12000, left = 3000, w = 4000, h = 3500 },
    [5001] = { mapID = 5001, name = "Deathknell", mapType = 5, parentMapID = 18, cont = 0, top = 11000, left = 2000, w = 500, h = 500 },
    -- a zone the map tree doesn't lead to (only the ID scan finds it)
    [7777] = { mapID = 7777, name = "Forever Isle", mapType = 3, parentMapID = 0, cont = 0, top = -8000, left = -2000, w = 2000, h = 2000 },
    -- Stormwind as WoW Forever reshaped it (with the harbour)
    [1453] = { mapID = 1453, name = "Forever Harbour Test Map", mapType = 3, parentMapID = 13, cont = 0, top = -7995.83, left = 1722.92, w = 1737.504, h = 1158.34 },
    -- a brand-new WoW Forever zone
    [2521] = { mapID = 2521, name = "Zephras Isle", mapType = 3, parentMapID = 0, cont = 2800, top = 3000, left = 3000, w = 3000, h = 3000 },
    -- dungeon maps are not offered in the picker
    [291] = { mapID = 291, name = "The Deadmines", mapType = 4, parentMapID = 52, cont = 36, top = 100, left = 100, w = 200, h = 200 },
}

local function MapToWorld(m, x, y)
    return m.top - y * m.h, m.left - x * m.w
end
local function WorldToMap(m, wx, wy)
    return (m.left - wy) / m.w, (m.top - wx) / m.h
end

C_Map = {}
function C_Map.GetMapInfo(id)
    local m = M.maps[id]
    if not m then
        return nil
    end
    return { mapID = m.mapID, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID }
end
-- area names as the client would give them (same language as the maps)
local AREA_NAMES = { [12] = "Elwynn Forest", [40] = "Westfall", [85] = "Tirisfal Glades", [14] = "Durotar", [1519] = "Stormwind City" }
function C_Map.GetAreaInfo(area)
    return AREA_NAMES[area]
end
function C_Map.GetFallbackWorldMapID()
    return 947
end
function C_Map.GetMapChildrenInfo(id, mapType, all)
    local out = {}
    local function walk(pid)
        for _, m in pairs(M.maps) do
            if m.parentMapID == pid then
                if not mapType or m.mapType == mapType then
                    table.insert(out, C_Map.GetMapInfo(m.mapID))
                end
                if all then
                    walk(m.mapID)
                end
            end
        end
    end
    walk(id)
    return out
end
function C_Map.GetWorldPosFromMapPos(id, vec)
    local m = M.maps[id]
    if not m or not m.top then
        return nil
    end
    local wx, wy = MapToWorld(m, vec.x, vec.y)
    return m.cont, CreateVector2D(wx, wy)
end
function C_Map.GetMapPosFromWorldPos(cont, vec, override)
    local m = M.maps[override]
    if not m or m.cont ~= cont then
        return nil
    end
    local x, y = WorldToMap(m, vec.x, vec.y)
    return override, CreateVector2D(x, y)
end
function C_Map.GetBestMapForUnit()
    if M.player.noPosition then
        return nil
    end
    -- smallest zone containing the player
    for _, id in ipairs({ 84, 37, 52, 18, 1, 1411, 2521 }) do
        local m = M.maps[id]
        if m.cont == M.player.inst then
            local x, y = WorldToMap(m, M.player.wx, M.player.wy)
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                return id
            end
        end
    end
    return M.player.inst == 0 and 13 or 12
end
function C_Map.GetPlayerMapPosition(id)
    local m = M.maps[id]
    if not m or not m.top or m.cont ~= M.player.inst or M.player.noPosition then
        return nil
    end
    local x, y = WorldToMap(m, M.player.wx, M.player.wy)
    return CreateVector2D(x, y)
end
function C_Map.GetMapInfoAtPosition(id, x, y)
    local parent = M.maps[id]
    if not parent or not parent.top then
        return nil
    end
    local wx, wy = MapToWorld(parent, x, y)
    for _, cid in ipairs({ 84, 37, 52, 18, 1, 1411 }) do
        local m = M.maps[cid]
        if m.parentMapID == id then
            local zx, zy = WorldToMap(m, wx, wy)
            if zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 then
                return C_Map.GetMapInfo(cid)
            end
        end
    end
    return C_Map.GetMapInfo(id)
end
M.userWaypoint = nil
function C_Map.CanSetUserWaypointOnMap(id)
    return M.maps[id] ~= nil
end
-- pin changes are announced straight away (the stricter case for addons)
local function PinEvent()
    M.FireEvent("USER_WAYPOINT_UPDATED")
end
function C_Map.SetUserWaypoint(point)
    M.userWaypoint = point
    M.pinTracked = false
    PinEvent()
end
function C_Map.ClearUserWaypoint()
    M.userWaypoint = nil
    PinEvent()
end
function C_Map.GetUserWaypointHyperlink()
    local p = M.userWaypoint
    return ("|cffffff00|Hworldmap:%d:%d:%d|h[Map Pin Location]|h|r"):format(p.uiMapID, p.position.x * 10000, p.position.y * 10000)
end
function C_Map.HasUserWaypoint()
    return M.userWaypoint ~= nil
end
-- WoW Forever hands the pin back with a plain { x, y } position (no :GetXY)
function C_Map.GetUserWaypoint()
    local p = M.userWaypoint
    return p and { uiMapID = p.uiMapID, position = { x = p.position.x, y = p.position.y } }
end
UiMapPoint = {
    CreateFromCoordinates = function(id, x, y)
        return { uiMapID = id, position = CreateVector2D(x, y) }
    end,
}
M.superTracked = 0
M.pinTracked = false
C_SuperTrack = {
    SetSuperTrackedUserWaypoint = function(on)
        M.pinTracked = on and true or false
    end,
    IsSuperTrackingUserWaypoint = function()
        return M.pinTracked and M.userWaypoint ~= nil
    end,
    GetSuperTrackedQuestID = function()
        return M.superTracked
    end,
}

-- Quests, flight masters, dungeons, rares --------------------------------------
M.quests = {
    { id = 101, title = "The Fargodeep Mine", onMap = { [37] = { 0.39, 0.82 } } },
    { id = 102, title = "Report to Gryan", complete = true, next = { 52, 0.56, 0.47 } },
}
M.serverQuests, M.loadedQuests, M.questRequests = {}, {}, 0
C_QuestLog = {
    GetNumQuestLogEntries = function()
        return #M.quests, #M.quests
    end,
    GetQuestIDForLogIndex = function(i)
        return M.quests[i] and M.quests[i].id
    end,
    GetTitleForQuestID = function(id)
        for _, q in ipairs(M.quests) do
            if q.id == id then
                return q.title
            end
        end
        return M.loadedQuests[id]
    end,
    -- the server knows quests the client has no names for
    RequestLoadQuestByID = function(id)
        M.questRequests = M.questRequests + 1
        if M.serverQuests[id] then
            M.loadedQuests[id] = M.serverQuests[id]
            M.FireEvent("QUEST_DATA_LOAD_RESULT", id, true)
        end
    end,
    GetQuestsOnMap = function(mapID)
        local out = {}
        for _, q in ipairs(M.quests) do
            local pos = q.onMap and q.onMap[mapID]
            if pos then
                out[#out + 1] = { questID = q.id, mapID = mapID, x = pos[1], y = pos[2] }
            end
        end
        return out
    end,
    GetNextWaypoint = function(id)
        for _, q in ipairs(M.quests) do
            if q.id == id and q.next then
                return q.next[1], q.next[2], q.next[3]
            end
        end
    end,
    GetLogIndexForQuestID = function(id)
        for i, q in ipairs(M.quests) do
            if q.id == id then
                return i
            end
        end
    end,
    IsQuestFlaggedCompleted = function(id)
        return M.completedQuests and M.completedQuests[id] or false
    end,
    GetInfo = function(i)
        local q = M.quests[i]
        return q and { questID = q.id, title = q.title, level = q.level or 10, isHeader = false }
    end,
    GetQuestObjectives = function(id)
        for _, q in ipairs(M.quests) do
            if q.id == id then
                return q.objectives or {}
            end
        end
    end,
    IsComplete = function(id)
        for _, q in ipairs(M.quests) do
            if q.id == id then
                return q.complete or false
            end
        end
        return false
    end,
}
Enum.FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 }
C_TaxiMap = {
    GetTaxiNodesForMap = function(mapID)
        if mapID == 37 then
            return {
                { nodeID = 1, name = "Goldshire, Elwynn", position = CreateVector2D(0.42, 0.65), faction = 2 },
                { nodeID = 2, name = "Orc Camp", position = CreateVector2D(0.1, 0.1), faction = 1 },
            }
        end
        return {}
    end,
}
C_EncounterJournal = {
    GetDungeonEntrancesForMap = function(mapID)
        if mapID == 52 then
            return { { name = "The Deadmines", position = CreateVector2D(0.42, 0.71) } }
        end
        return {}
    end,
}
C_AreaPoiInfo = {
    GetAreaPOIForMap = function()
        return {}
    end,
    GetAreaPOIInfo = function() end,
}
-- the game's map markers: M.vignettes[guid] = { info fields..., pos = { x, y } }
M.vignettes = {
    ["v-1"] = { name = "Mother Fang", onWorldMap = true, isDead = false, pos = { 0.61, 0.5 } },
}
C_VignetteInfo = {
    GetVignettes = function()
        local out = {}
        for guid in pairs(M.vignettes) do
            out[#out + 1] = guid
        end
        table.sort(out)
        return out
    end,
    GetVignetteInfo = function(guid)
        local v = M.vignettes[guid]
        if not v then
            return nil
        end
        local info = {}
        for k, val in pairs(v) do
            if k ~= "pos" then
                info[k] = val
            end
        end
        info.vignetteGUID = guid
        return info
    end,
    GetVignettePosition = function(guid)
        local v = M.vignettes[guid]
        if v and v.pos then
            return CreateVector2D(v.pos[1], v.pos[2])
        end
    end,
}
function UnitClassification(unit)
    local u = M.units[unit]
    return u and u.class or "normal"
end
function UnitIsDead(unit)
    local u = M.units[unit]
    return u and u.dead or false
end
function UnitIsTapDenied(unit)
    local u = M.units[unit]
    return u and u.tapped or false
end
M.raidNotices, M.flashes = {}, 0
RaidWarningFrame = {}
ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.28, b = 0 } }
function RaidNotice_AddMessage(_, text)
    table.insert(M.raidNotices, text)
end
function FlashClientIcon()
    M.flashes = M.flashes + 1
end
M.questDialog = {}
function GetQuestID()
    return M.questDialog.id or 0
end
function GetTitleText()
    return M.questDialog.title
end
function GetObjectiveText()
    return M.questDialog.text
end
M.loot = {}
function GetNumLootItems()
    return #M.loot
end
function GetLootSourceInfo(slot)
    local src = M.loot[slot]
    if src then
        return src, 1
    end
end
M.lootItems = {}
function GetLootSlotLink(slot)
    local it = M.lootItems[slot]
    return it and ("|cffffffff|Hitem:%d::::::::20:::::|h[%s]|h|r"):format(it.id, it.name)
end
function GetLootSlotInfo(slot)
    local it = M.lootItems[slot]
    if it then
        return 134938, it.name, 1, nil, 1
    end
end
function CanMerchantRepair()
    return M.canRepair
end
Enum.PlayerInteractionType = { Gossip = 3, QuestGiver = 4, Merchant = 5, TaxiNode = 6, Trainer = 7, Banker = 8, MailInfo = 17, Binder = 20, Auctioneer = 21 }

function UnitFactionGroup(unit)
    if unit and unit ~= "player" then
        local u = M.units[unit]
        return u and u.faction
    end
    return "Alliance"
end
-- how far an NPC is: M.units[token].dist in yards (interact distances:
-- 3 = duel ~10 yards, 4 = follow ~28 yards)
local INTERACT_YARDS = { [1] = 28, [2] = 11.11, [3] = 9.9, [4] = 28 }
function CheckInteractDistance(unit, index)
    if M.player.combat then
        error("CheckInteractDistance is not allowed in combat")
    end
    local u = M.units[unit]
    return u ~= nil and u.dist ~= nil and u.dist <= INTERACT_YARDS[index]
end
function UnitCanAttack(_, unit)
    local u = M.units[unit]
    if not u then
        return false
    end
    if u.attackable ~= nil then
        return u.attackable
    end
    return (u.reaction or 5) <= 4 and not u.faction
end
function UnitPlayerControlled(unit)
    local u = M.units[unit]
    return u and u.controlled or false
end
LEVEL = "Level"
-- the tooltip's lines: name, then the title if it has one, then the level
C_TooltipInfo = {
    GetUnit = function(unit)
        local u = M.units[unit]
        if not u then
            return nil
        end
        local lines = { { leftText = u.name } }
        if u.title then
            lines[#lines + 1] = { leftText = u.title }
        end
        lines[#lines + 1] = { leftText = "Level " .. tostring(u.level or "??") .. " Humanoid" }
        return { lines = lines }
    end,
}
-- the vendor window: M.merchant = { { id, name }, ... }
M.merchant = {}
function GetMerchantNumItems()
    return #M.merchant
end
function GetMerchantItemLink(i)
    local it = M.merchant[i]
    return it and ("|cffffffff|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(it[1], it[2])
end
M.group = { raid = false, party = true, guild = true }
function IsInRaid()
    return M.group.raid
end
function IsInGroup()
    return M.group.party
end
function IsInGuild()
    return M.group.guild
end
function UnitExists(unit)
    if M.units[unit] then
        return true
    end
    return M.hasTarget
end
function UnitIsPlayer(unit)
    local u = M.units[unit]
    if u then
        return u.player or false
    end
    return M.hasTarget
end
function UnitIsUnit()
    return false
end
-- The chat box: links go into it only while it's open. A slash command
-- runs while it's still open, and the game empties and closes it after.
M.chatOpen = false
ChatFrameUtil = {
    OpenChat = function(text)
        M.chatOpen = true
        M.chatText = text
    end,
    InsertLink = function(text)
        if not M.chatOpen then
            return false
        end
        M.chatText = (M.chatText or "") .. text
        return true
    end,
}
function M.TypeSlash(handler, msg)
    M.chatOpen, M.chatText = true, ""
    handler(msg)
    M.chatOpen, M.chatText = false, nil
end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GameFontNormal = {
    GetFont = function()
        return STANDARD_TEXT_FONT, 12
    end,
}
C_Minimap = {
    GetViewRadius = function()
        return 233
    end,
    IsRotateMinimapIgnored = function()
        return false
    end,
}

-- World map ------------------------------------------------------------------
MapCanvasDataProviderMixin = {}
function MapCanvasDataProviderMixin:OnAdded(map)
    self.owningMap = map
end
function MapCanvasDataProviderMixin:GetMap()
    return self.owningMap
end
MapCanvasPinMixin = {}
function MapCanvasPinMixin:OnLoad() end
function MapCanvasPinMixin:OnAcquired() end
function MapCanvasPinMixin:UseFrameLevelType(t)
    self._frameLevelType = t
end
function MapCanvasPinMixin:SetScalingLimits() end
function MapCanvasPinMixin:SetPosition(x, y)
    self.normalizedX, self.normalizedY = x, y
end
function MapCanvasPinMixin:SetHitRectInsets() end
function MapCanvasPinMixin:CheckMouseButtonPassthrough(...)
    self:SetPassThroughButtons()
    self:SetPassThroughButtons(...)
end

-- a protected widget method, like the real one: blocked for addons in combat
function Frame:SetPassThroughButtons()
    if M.player.combat then
        table.insert(M.errors, "ADDON_ACTION_BLOCKED: SetPassThroughButtons")
    end
end

WorldMapFrame = NewObject("Frame", "WorldMapFrame", UIParent)
WorldMapFrame._shown = false
WorldMapFrame.ScrollContainer = NewObject("Frame", nil, WorldMapFrame)
WorldMapFrame.mapID = 37
WorldMapFrame.pins = {}
WorldMapFrame.providers = {}
WorldMapFrame.clickHandlers = {}
function WorldMapFrame:GetMapID()
    return self.mapID
end
function WorldMapFrame:AddDataProvider(p)
    table.insert(self.providers, p)
    p:OnAdded(self)
end
function WorldMapFrame:AddCanvasClickHandler(fn, prio)
    table.insert(self.clickHandlers, fn)
end
function WorldMapFrame:GetNormalizedCursorPosition()
    return 0.5, 0.5
end
function WorldMapFrame:AcquirePin(template, ...)
    local pin = CreateFrame("Frame", nil, self)
    -- the XML template's mixin + regions
    Mixin(pin, _G.WaypointTrackerMapPinMixin)
    pin.Icon = pin:CreateTexture()
    pin.Highlight = pin:CreateTexture()
    pin.GetMap = function()
        return self
    end
    pin:OnLoad()
    pin:OnAcquired(...)
    pin:CheckMouseButtonPassthrough("RightButton")
    table.insert(self.pins, pin)
    return pin
end
function WorldMapFrame:RemoveAllPinsByTemplate()
    for _, p in ipairs(self.pins) do
        p:Hide()
    end
    self.pins = {}
end
function WorldMapFrame:ClickCanvas(button, x, y)
    for _, fn in ipairs(self.clickHandlers) do
        if fn(self, button, x, y) then
            return true
        end
    end
    return false
end

-- Menus / settings ------------------------------------------------------------
M.menus = {}
MenuUtil = {
    CreateContextMenu = function(owner, gen)
        local root = { items = {} }
        function root:CreateTitle(t)
            table.insert(self.items, { title = t })
        end
        function root:CreateButton(t, fn)
            table.insert(self.items, { text = t, fn = fn })
        end
        gen(owner, root)
        table.insert(M.menus, root)
        return root
    end,
}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        M.settingsCategory = { frame = frame, name = name }
        return M.settingsCategory
    end,
    RegisterAddOnCategory = noop,
}
StaticPopupDialogs = {}
function StaticPopup_Show(which)
    M.lastPopup = which
    local d = StaticPopupDialogs[which]
    if d and M.autoAcceptPopup then
        d.OnAccept()
    end
end

-- ---------------------------------------------------------------------------
-- Loading the addon
-- ---------------------------------------------------------------------------
function M.LoadAddon(dir, name)
    local ns = {}
    local toc = assert(io.open(dir .. "/" .. name .. ".toc")):read("*a")
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^##") and line:match("%S") then
            local file = line:gsub("\\", "/"):gsub("%s+$", "")
            if file:match("%.lua$") then
                local chunk = assert(loadfile(dir .. "/" .. file))
                chunk(name, ns)
            end
        end
    end
    return ns
end

return M
