-- A small fake of the WoW API, just enough to load and exercise the addon
-- outside the game with plain Lua 5.1. Any frame method we don't implement
-- is nil, as in the client (see the strict widget methods note below).
-- Frames model enabled state, multiline text height and vertical scroll offsets.
-- Lines record _start/_end anchors and _thickness; regions record _drawLayer,
-- _rotation and _colorTexture; frames record _clipsChildren.
-- Settings initializers support parent and shown predicates.
-- UI test state:
--   frames, unknownMethods: created objects and "Type:Key" lookups that found
--     no client method for that widget type (feature probes and failed calls).
--   menus, lastMenu: opened menus and the latest generated root (items contain
--     kind, text/title, fn, isSelected, setSelected, enabled and tooltip;
--     elements support submenus; open menus have owner and open = true).
--   lastPopup, lastPopupArgs: last popup ID and { a1, a2, data }.
--   popups: visible dialog frames by ID; autoAcceptPopup/autoAltPopup/
--     autoCancelPopup select a callback automatically, in that order.
--   uiPanelCalls: show/hide call counts, including blocked calls; actionBlocked
--     counts combat-blocked calls, which return without changing visibility.
--   settings: proxy settings by variable; settingsControls: control initializers;
--     settingsOpened: last category ID; settingsNotified: variables notified;
--     settingsCategory: latest canvas category; settingsLayouts: layouts by category.
--   helpTips: Show history ({ parent, info, relativeRegion, shown }); Hide and
--     Acknowledge clear shown; Acknowledge invokes info.onAcknowledgeCallback.
--   cvars: string values (includes both world-map coordinate switches).
--   worldMapOpened: last successfully opened map ID; world-map providers receive
--     map-change and visibility callbacks; pins record their template name.
--   editModeEntered: entry count; editLayouts/editActive: layout names/index.
-- Game test state:
--   player: world position wx/wy/inst, facing, combat, taxi, dead, ghost,
--     noPosition and corpse { mapID, x, y }; writes advance now slightly.
--   now/timers: clock and queued C_Timer callbacks; eventFrames/unknownEvents:
--     event listeners and events that throw when registered; focus: edit focus.
--   printed/sounds/errors: chat, sound IDs and reported errors; locale: WT_LOCALE.
--   units: token -> guid/name/reaction/level/class/dead/tapped/faction/dist/
--     attackable/controlled/player; hasTarget: fallback unit presence/player flag.
--   shift/ctrl/alt: modifier keys; addonsLoaded/tomtomInstalled/noDataAddon:
--     addon availability; maps: map geometry; quests: quest log and objectives.
--   worldRects: continent rectangles { minX, maxX, minY, maxY } on map 947.
--   explored: explored-map texture records by map ID; maps[id].noArt disables art.
--   serverQuests/loadedQuests/questRequests: asynchronous quest title loading;
--     completedQuests/superTracked: completed quest IDs and tracked quest.
--   userWaypoint/pinTracked: Blizzard waypoint and tracking state; vignettes:
--     marker info and positions; tooltip/tooltipOwner/tooltipPostCalls: tooltip
--     lines, owner and data hooks; raidNotices/flashes: raid messages and flashes.
--   questDialog: id/title/text; loot: slot source GUIDs; lootItems: id/name by slot;
--     canRepair: merchant repair support; merchant: vendor id/name rows.
--   group: raid/party/guild flags; chatOpen/chatText: chat edit-box state.
-- Helpers: NewObject, FireEvent, Tick, ShowObjectTooltip, TypeSlash, LoadAddon,
--   ClickButton/OpenMenu/FindMenuItem/PickMenuItem (the mouse click path) and
--   ExplainError. hooksecurefunc raises when its target is not a function.
local M = {}

M.unknownMethods = {}
M.frames = {}
M.printed = {}
M.sounds = {}
M.errors = {}
M.uiPanelCalls = { show = 0, hide = 0 }
M.settings = {}
M.settingsControls = {}
M.settingsNotified = {}
M.settingsLayouts = {}
M.helpTips = {}
M.popups = {}
M.editModeEntered = 0

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
        table.insert(M.errors, M.ExplainError(err))
    end
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------
local Frame = {}
-- Strict widget methods. In the client a widget only has the methods of its
-- own type (and of the types it inherits from); indexing anything else gives
-- nil, so `if f.Method then` feature detection works and calling a missing
-- method raises "attempt to call method 'X' (a nil value)". The mock does the
-- same: a method in the shared Frame table is visible on an object only when
-- the object's widget type has it in the client. There is no catch-all any
-- more; an unknown capitalised key is recorded in M.unknownMethods
-- ("Type:Method" -> count) and the error handler names the widget type when
-- such a call fails (see M.ExplainError).
--
-- Evidence for every family below: the client's generated widget API
-- documentation, Gethe/wow-ui-source branch `forever`,
-- Interface/AddOns/Blizzard_APIDocumentationGenerated/Simple<Family>APIDocumentation.lua
-- (SimpleObject, SimpleFrameScriptObject, SimpleScriptRegion,
-- SimpleScriptRegionResizing, SimpleRegion, SimpleAnimatableObject,
-- SimpleTextureBase, SimpleLine, SimpleFont, SimpleFontString, SimpleFrame,
-- SimpleButton, SimpleCheckbox, SimpleEditBox, SimpleScrollFrame, SimpleSlider,
-- SimpleAnimGroup). GameTooltip methods are not in the generated docs; they are
-- used on the same branch by Blizzard_GameTooltip/Mainline/GameTooltip.lua
-- (SetOwner, GetOwner, AddLine, NumLines) and
-- Blizzard_Minimap/Mainline/GameTime.lua (IsOwned).
-- tests/run_mock_selftest.lua checks that every mocked method belongs to a family.
local FAMILY_METHODS = {
    Object = "GetParent GetName GetObjectType IsObjectType",
    ScriptRegion = "Show Hide SetShown IsShown IsVisible SetScript GetScript HookScript EnableMouse"
        .. " IsMouseEnabled EnableMouseWheel IsMouseWheelEnabled IsMouseOver GetCenter GetWidth GetHeight"
        .. " GetSize SetParent SetPassThroughButtons SetMouseClickEnabled SetMouseMotionEnabled",
    Resizing = "SetPoint ClearAllPoints GetPoint GetNumPoints SetAllPoints SetSize SetWidth SetHeight",
    Region = "SetAlpha GetAlpha SetScale GetScale GetEffectiveScale SetDrawLayer GetDrawLayer"
        .. " SetVertexColor GetVertexColor",
    Animatable = "CreateAnimationGroup",
    TextureBase = "SetTexture GetTexture SetTexCoord GetTexCoord SetColorTexture SetRotation GetRotation"
        .. " SetBlendMode GetBlendMode",
    Line = "SetStartPoint SetEndPoint SetThickness GetThickness ClearAllPoints",
    Font = "SetFont GetFont SetFontObject GetFontObject SetJustifyH GetJustifyH SetJustifyV GetJustifyV"
        .. " SetTextColor GetTextColor SetSpacing GetSpacing",
    FontString = "SetText GetText GetStringWidth GetStringHeight SetWordWrap CanWordWrap SetRotation GetRotation",
    Frame = "SetID GetID GetFrameLevel SetFrameLevel SetFrameStrata GetFrameStrata CreateTexture"
        .. " CreateFontString CreateLine SetClipsChildren DoesClipChildren SetHitRectInsets RegisterEvent"
        .. " UnregisterEvent IsEventRegistered SetMovable IsMovable SetClampedToScreen IsClampedToScreen"
        .. " RegisterForDrag StartMoving StopMovingOrSizing SetAlpha GetAlpha SetScale GetScale"
        .. " GetEffectiveScale LockHighlight UnlockHighlight",
    Button = "Click SetText GetText SetFontString GetFontString SetEnabled IsEnabled Enable Disable"
        .. " RegisterForClicks SetMotionScriptsWhileDisabled GetMotionScriptsWhileDisabled SetHighlightTexture"
        .. " GetHighlightTexture SetNormalTexture SetPushedTexture",
    Checkbox = "SetChecked GetChecked",
    EditBox = "SetText GetText SetFocus ClearFocus HasFocus SetEnabled IsEnabled Enable Disable SetMultiLine"
        .. " IsMultiLine SetNumeric IsNumeric SetMaxLetters GetMaxLetters SetAutoFocus IsAutoFocus"
        .. " HighlightText SetCursorPosition GetCursorPosition",
    ScrollFrame = "SetScrollChild GetScrollChild GetVerticalScroll SetVerticalScroll UpdateScrollChildRect",
    Slider = "SetMinMaxValues GetMinMaxValues SetValue GetValue SetValueStep GetValueStep SetObeyStepOnDrag"
        .. " GetObeyStepOnDrag SetOrientation GetOrientation SetThumbTexture SetEnabled IsEnabled Enable Disable",
    GameTooltip = "SetOwner GetOwner IsOwned AddLine SetText NumLines",
    AnimationGroup = "SetScript GetScript HookScript",
}
local FRAME = { "Object", "ScriptRegion", "Resizing", "Animatable", "Frame" }
local function Families(base, ...)
    local out = {}
    for _, f in ipairs(base) do out[#out + 1] = f end
    for i = 1, select("#", ...) do out[#out + 1] = select(i, ...) end
    return out
end
local BUTTON = Families(FRAME, "Button")
-- widget type -> method families, following the client's inheritance
local KIND_FAMILIES = {
    Frame = FRAME,
    Button = BUTTON,
    CheckButton = Families(BUTTON, "Checkbox"),
    -- the DropdownButton intrinsic adds DropdownButtonMixin per object
    DropdownButton = BUTTON,
    EditBox = Families(FRAME, "Font", "EditBox"),
    ScrollFrame = Families(FRAME, "ScrollFrame"),
    Slider = Families(FRAME, "Slider"),
    GameTooltip = Families(FRAME, "GameTooltip"),
    Texture = { "Object", "ScriptRegion", "Resizing", "Region", "Animatable", "TextureBase" },
    -- lines are anchored with SetStartPoint/SetEndPoint, not SetPoint
    Line = { "Object", "ScriptRegion", "Region", "Animatable", "TextureBase", "Line" },
    FontString = { "Object", "ScriptRegion", "Resizing", "Region", "Animatable", "Font", "FontString" },
    AnimationGroup = { "Object", "AnimationGroup" },
}
local familySets = {}
for family, names in pairs(FAMILY_METHODS) do
    familySets[family] = {}
    for n in names:gmatch("%S+") do familySets[family][n] = true end
end
local kindMethods = {}
for kind, families in pairs(KIND_FAMILIES) do
    kindMethods[kind] = {}
    for _, family in ipairs(families) do
        for n in pairs(familySets[family]) do kindMethods[kind][n] = true end
    end
end
-- Mock-only helpers for tests. They do not exist in the client, so addon code
-- (any chunk loaded from WaypointTracker/) gets nil for them like any other
-- missing method.
local TEST_HELPERS = { RunScript = true, Type = true }
local function CalledFromAddon()
    -- level 1 is this function, 2 the __index metamethod, 3 the indexing code
    local info = debug.getinfo(3, "S")
    local src = info and info.source or ""
    return src:find("WaypointTracker", 1, true) ~= nil and not src:find("tests/", 1, true)
end
M.lastUnknownMethod = nil
M.unknownMethodKind = {} -- method -> widget type of its latest failed lookup
local FrameMT = {
    __index = function(t, k)
        local v = Frame[k]
        local kind = rawget(t, "_kind")
        if v ~= nil then
            if TEST_HELPERS[k] then
                if not CalledFromAddon() then return v end
            elseif kindMethods[kind] and kindMethods[kind][k] then
                return v
            end
        end
        if type(k) == "string" and k:match("^[A-Z]") then
            local key = tostring(kind) .. ":" .. k
            M.unknownMethods[key] = (M.unknownMethods[key] or 0) + 1
            M.lastUnknownMethod = { kind = kind, method = k }
            M.unknownMethodKind[k] = kind
        end
        return nil
    end,
}
M.FAMILY_METHODS, M.KIND_FAMILIES, M.TEST_HELPERS, M.FrameMethods = FAMILY_METHODS, KIND_FAMILIES, TEST_HELPERS, Frame

-- Adds the widget type to "attempt to call method 'X' (a nil value)" errors.
function M.ExplainError(err)
    local text = tostring(err)
    local method = text:match("attempt to call method '([^']+)' %(a nil value%)")
    local kind = method and M.unknownMethodKind[method]
    if kind then
        return text .. (" [wowmock: %s has no method %s in the client]"):format(tostring(kind), method)
    end
    return text
end

local function NewObject(kind, name, parent)
    if not KIND_FAMILIES[kind] then
        error(('wowmock: unknown widget type "%s"'):format(tostring(kind)), 2)
    end
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
function Frame:SetID(id)
    self._id = id
end
function Frame:GetID()
    return self._id
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
-- test helper: fires a script like the game would, intrinsic handler first
function Frame:RunScript(event, ...)
    local intrinsic = rawget(self, "_intrinsic")
    if intrinsic and intrinsic[event] then
        intrinsic[event](self, ...)
    end
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
function Frame:CreateLine(name, layer, template, sub)
    local line = NewObject("Line", name, self)
    line:SetDrawLayer(layer or "ARTWORK", sub or 0)
    return line
end
function Frame:CreateFontString(name, layer, font)
    local fs = NewObject("FontString", name, self)
    fs.fontTemplate = font
    return fs
end
function Frame:CreateAnimationGroup()
    return NewObject("AnimationGroup", nil, self)
end
-- regions
function Frame:SetStartPoint(point, rel, x, y)
    self._start = { point, rel, x, y }
end
function Frame:SetEndPoint(point, rel, x, y)
    self._end = { point, rel, x, y }
end
function Frame:SetThickness(value)
    self._thickness = value
end
function Frame:GetThickness()
    return self._thickness or 1
end
function Frame:SetClipsChildren(on)
    self._clipsChildren = on and true or false
end
function Frame:SetDrawLayer(layer, sub)
    self._drawLayer = { layer, sub or 0 }
end
function Frame:SetRotation(rad)
    self._rotation = rad
end
function Frame:SetColorTexture(r, g, b, a)
    self._colorTexture = { r, g, b, a or 1 }
end
function Frame:SetHitRectInsets() end
function Frame:SetTextColor(r, g, b, a)
    self._textColor = { r, g, b, a or 1 }
end
function Frame:GetTextColor()
    return unpack(self._textColor or { 1, 1, 1, 1 })
end
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
function Frame:GetStringHeight()
    local text = (self:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local lines, width = 0, math.max(1, self:GetWidth())
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines = lines + math.max(1, math.ceil(#line * 6 / width))
    end
    return lines * 12
end
function Frame:GetVerticalScroll()
    return self._verticalScroll or 0
end
function Frame:SetVerticalScroll(value)
    self._verticalScroll = value
end
function Frame:SetEnabled(on)
    self.enabled = on and true or false
end
function Frame:IsEnabled()
    return self.enabled ~= false
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
function Frame:UnregisterEvent(e)
    local list = M.eventFrames[e]
    for i = #(list or {}), 1, -1 do
        if list[i] == self then
            table.remove(list, i)
        end
    end
end
function Frame:IsEventRegistered(e)
    for _, f in ipairs(M.eventFrames[e] or {}) do
        if f == self then
            return true
        end
    end
    return false
end
function Frame:SetScrollChild(c)
    self._child = c
end
function Frame:SetFontObject(f)
    self._fontObject = f
end
function Frame:SetHighlightTexture() end
function Frame:SetNormalTexture() end
function Frame:SetPushedTexture() end
function Frame:SetThumbTexture() end
function Frame:GetHighlightTexture()
    return NewObject("Texture", nil, self)
end
-- State-keeping versions of client methods the addon calls; tests can read
-- the stored fields (_strata, _movable, _clamped, _dragButtons, _clickButtons,
-- _justifyH/_justifyV, _wordWrap, _font, _spacing, _numeric, _maxLetters,
-- _autoFocus, _highlight, _cursor, _valueStep, _obeyStep, _orientation,
-- _blendMode, _highlightLocked, _motionWhileDisabled, _mouseWheel).
function Frame:GetDrawLayer()
    local d = self._drawLayer or { "ARTWORK", 0 }
    return d[1], d[2]
end
function Frame:GetRotation()
    return self._rotation or 0
end
function Frame:DoesClipChildren()
    return self._clipsChildren or false
end
function Frame:GetNumPoints()
    return #self._points
end
function Frame:EnableMouseWheel(on)
    self._mouseWheel = on and true or false
end
function Frame:IsMouseWheelEnabled()
    return self._mouseWheel or false
end
function Frame:SetMouseClickEnabled(on)
    self._mouseClick = on and true or false
end
function Frame:SetMouseMotionEnabled(on)
    self._mouseMotion = on and true or false
end
function Frame:SetFrameStrata(strata)
    self._strata = strata
end
function Frame:GetFrameStrata()
    return self._strata or "MEDIUM"
end
function Frame:SetMovable(on)
    self._movable = on and true or false
end
function Frame:IsMovable()
    return self._movable or false
end
function Frame:SetClampedToScreen(on)
    self._clamped = on and true or false
end
function Frame:IsClampedToScreen()
    return self._clamped or false
end
function Frame:RegisterForDrag(...)
    self._dragButtons = { ... }
end
function Frame:LockHighlight()
    self._highlightLocked = true
end
function Frame:UnlockHighlight()
    self._highlightLocked = false
end
-- buttons
function Frame:RegisterForClicks(...)
    self._clickButtons = { ... }
end
function Frame:SetMotionScriptsWhileDisabled(on)
    self._motionWhileDisabled = on and true or false
end
function Frame:GetMotionScriptsWhileDisabled()
    return self._motionWhileDisabled or false
end
function Frame:Enable()
    self:SetEnabled(true)
end
function Frame:Disable()
    self:SetEnabled(false)
end
-- fonts (FontString and EditBox)
function Frame:SetFont(path, height, flags)
    self._font = { path, height, flags }
    return true
end
function Frame:GetFont()
    local f = self._font
    if type(f) == "table" and f[1] then
        return f[1], f[2], f[3]
    end
end
function Frame:GetFontObject()
    local f = self._fontObject
    return f
end
function Frame:SetJustifyH(j)
    self._justifyH = j
end
function Frame:GetJustifyH()
    return self._justifyH or "CENTER"
end
function Frame:SetJustifyV(j)
    self._justifyV = j
end
function Frame:GetJustifyV()
    return self._justifyV or "MIDDLE"
end
function Frame:SetSpacing(s)
    self._spacing = s
end
function Frame:GetSpacing()
    return self._spacing or 0
end
function Frame:SetWordWrap(on)
    self._wordWrap = on and true or false
end
function Frame:CanWordWrap()
    return self._wordWrap ~= false
end
-- edit boxes
function Frame:SetMultiLine(on)
    self._multiLine = on and true or false
end
function Frame:IsMultiLine()
    return self._multiLine or false
end
function Frame:SetNumeric(on)
    self._numeric = on and true or false
end
function Frame:IsNumeric()
    return self._numeric or false
end
function Frame:SetMaxLetters(n)
    self._maxLetters = n
end
function Frame:GetMaxLetters()
    return self._maxLetters or 0
end
function Frame:SetAutoFocus(on)
    self._autoFocus = on and true or false
end
function Frame:IsAutoFocus()
    return self._autoFocus ~= false
end
function Frame:HighlightText(first, last)
    local len = #(self:GetText() or "")
    self._highlight = { first or 0, last or len }
end
function Frame:SetCursorPosition(pos)
    self._cursor = pos
end
function Frame:GetCursorPosition()
    return self._cursor or #(self:GetText() or "")
end
-- sliders
function Frame:SetValueStep(step)
    self._valueStep = step
end
function Frame:GetValueStep()
    return self._valueStep or 0
end
function Frame:SetObeyStepOnDrag(on)
    self._obeyStep = on and true or false
end
function Frame:GetObeyStepOnDrag()
    return self._obeyStep or false
end
function Frame:SetOrientation(o)
    self._orientation = o
end
function Frame:GetOrientation()
    return self._orientation or "HORIZONTAL"
end
-- scroll frames
function Frame:GetScrollChild()
    return self._child
end
function Frame:UpdateScrollChildRect()
    self._scrollRectUpdates = (self._scrollRectUpdates or 0) + 1
end
-- textures
function Frame:SetBlendMode(mode)
    self._blendMode = mode
end
function Frame:GetBlendMode()
    return self._blendMode or "BLEND"
end

M.eventFrames = {}

local function NewMenuRoot()
    local root = { items = {} }
    local function Add(self, item)
        item.items = {}
        -- element descriptions record what the menu would show
        function item:SetTooltip(fn)
            self.tooltip = fn
        end
        function item:SetEnabled(on)
            self.enabled = on
        end
        function item:AddInitializer(fn)
            self.initializers = self.initializers or {}
            table.insert(self.initializers, fn)
        end
        item.CreateTitle = root.CreateTitle
        item.CreateButton = root.CreateButton
        item.CreateCheckbox = root.CreateCheckbox
        item.CreateRadio = root.CreateRadio
        item.CreateDivider = root.CreateDivider
        item.CreateSpacer = root.CreateSpacer
        table.insert(self.items, item)
        return item
    end
    function root:CreateTitle(text)
        return Add(self, { kind = "title", title = text, text = text })
    end
    function root:CreateButton(text, fn)
        return Add(self, { kind = "button", text = text, fn = fn })
    end
    function root:CreateCheckbox(text, isSelected, setSelected)
        return Add(self, { kind = "checkbox", text = text, fn = setSelected,
            isSelected = isSelected, setSelected = setSelected })
    end
    function root:CreateRadio(text, isSelected, setSelected)
        return Add(self, { kind = "radio", text = text, fn = setSelected,
            isSelected = isSelected, setSelected = setSelected })
    end
    function root:CreateDivider()
        return Add(self, { kind = "divider" })
    end
    function root:CreateSpacer()
        return Add(self, { kind = "spacer" })
    end
    return root
end

-- DropdownButton intrinsic (Blizzard_Menu/DropdownButton.lua, DropdownButtonMixin):
-- SetupMenu generates at once when shown; a left mouse-down without Shift
-- toggles the menu, regenerating it each time it opens. GenerateMenu also
-- returns the root here, for tests.
local function AddDropdownMethods(f)
    f.intrinsic = "DropdownButton"
    function f:SetupMenu(gen)
        assert(type(gen) == "function", "DropdownButtonMixin:SetupMenu(generator): argument is not a function.")
        self.menuGenerator = gen
        if self:IsShown() then
            self:GenerateMenu()
        end
    end
    function f:GenerateMenu()
        if not self.menuGenerator then
            return
        end
        local root = NewMenuRoot()
        self.menuGenerator(self, root)
        self.lastRoot, self.menuDescription, M.lastMenu = root, root, root
        return root
    end
    function f:IsMenuOpen()
        return self.menu ~= nil
    end
    function f:OpenMenu()
        if not self:IsEnabled() or self:IsMenuOpen() then
            return
        end
        self:GenerateMenu()
        if not self.menuDescription then
            return
        end
        self.menu = self.menuDescription
        self.menu.owner, self.menu.open = self, true
        table.insert(M.menus, self.menu)
    end
    function f:CloseMenu()
        if self.menu then
            self.menu.open = false
            self.menu = nil
        end
    end
    function f:SetMenuOpen(open)
        if open then
            self:OpenMenu()
        else
            self:CloseMenu()
        end
    end
    function f:OverrideText(text)
        self:SetText(text)
    end
    function f:SetDefaultText(text)
        self.defaultText = text
        self:SetText(text)
    end
    rawset(f, "_intrinsic", {
        OnMouseDown = function(self)
            if IsShiftKeyDown() then
                return
            end
            self:SetMenuOpen(not self:IsMenuOpen())
        end,
        OnEnter = function(self)
            if self.canOpenOnEnter then
                self:OpenMenu()
            end
        end,
    })
end

local function AddSettingSliderMethods(slider)
    slider._callbacks = {}
    function slider:Init(value, min, max, steps, formatters)
        self._min, self._max = min, max
        self.steps, self.formatters = steps, formatters
        self._value = value
    end
    function slider:RegisterCallback(event, fn, owner)
        self._callbacks[event] = self._callbacks[event] or {}
        table.insert(self._callbacks[event], { fn = fn, owner = owner })
    end
    -- CallbackRegistryMixin:UnregisterCallback(event, owner)
    -- (Blizzard_SharedXMLBase/CallbackRegistry.lua)
    function slider:UnregisterCallback(event, owner)
        local list = self._callbacks[event] or {}
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                table.remove(list, i)
            end
        end
    end
    function slider:SetValue(value)
        local changed = self._value ~= value
        Frame.SetValue(self, value)
        if changed then
            for _, cb in ipairs(self._callbacks.OnValueChanged or {}) do
                cb.fn(cb.owner, value)
            end
        end
    end
end

function CreateFrame(kind, name, parent, template)
    local function Has(t)
        return template and template:find(t, 1, true)
    end
    if Has("MagicButtonTemplate") or Has("UIPanelButtonTemplate") then
        kind = "Button"
    elseif Has("SearchBoxTemplate") or Has("InputBoxInstructionsTemplate") or Has("InputBoxTemplate") then
        kind = "EditBox"
    elseif Has("DialogBorderTranslucentTemplate") then
        kind = "Frame"
    end
    local f = NewObject(kind, name, parent)
    f._template = template
    if Has("BackdropTemplate") then
        -- BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua): colours
        -- apply only after a backdrop with a bgFile or edgeFile is set.
        function f:SetBackdrop(info)
            if info and (info.bgFile or info.edgeFile) then
                self._backdrop = info
            else
                self._backdrop, self._backdropColor, self._backdropBorderColor = nil, nil, nil
            end
        end
        function f:GetBackdrop()
            return self._backdrop
        end
        function f:SetBackdropColor(r, g, b, a)
            if self._backdrop then self._backdropColor = { r, g, b, a or 1 } end
        end
        function f:GetBackdropColor()
            if self._backdropColor then return unpack(self._backdropColor) end
        end
        function f:SetBackdropBorderColor(r, g, b, a)
            if self._backdrop then self._backdropBorderColor = { r, g, b, a or 1 } end
        end
        function f:GetBackdropBorderColor()
            if self._backdropBorderColor then return unpack(self._backdropBorderColor) end
        end
    end
    if Has("UIPanelButtonTemplate") then
        f:SetFontString(f:CreateFontString(nil, "ARTWORK", "GameFontNormal"))
        function f:SetText(text)
            Frame.SetText(self, text)
            self:GetFontString():SetText(text)
        end
    end
    if Has("ButtonFrameTemplate") or Has("PortraitFrameTemplate") then
        f.TitleText = f:CreateFontString()
        f.TitleContainer = { TitleText = f.TitleText }
        f.CloseButton = NewObject("Button", nil, f)
        f.Inset = NewObject("Frame", nil, f)
        f.Bg = f:CreateTexture()
        f.TopTileStreaks = f:CreateTexture()
        f.PortraitContainer = NewObject("Frame", nil, f)
        f.PortraitContainer.portrait = f.PortraitContainer:CreateTexture()
        f.portrait = f.PortraitContainer.portrait
        function f:SetTitle(text)
            self.TitleText:SetText(text)
        end
        function f:SetPortraitToAsset(asset)
            self.portrait:SetTexture(asset)
        end
        f.SetPortraitTextureRaw = f.SetPortraitToAsset
    end
    if Has("PanelTabButtonTemplate") then
        f.Left, f.Middle, f.Right = f:CreateTexture(), f:CreateTexture(), f:CreateTexture()
        f.Left:SetWidth(20)
        f.Middle:SetWidth(1)
        f.Right:SetWidth(20)
        f.GetTextWidth = Frame.GetStringWidth
    end
    if Has("SearchBoxTemplate") or Has("InputBoxInstructionsTemplate") then
        f.Instructions = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        f.Instructions:SetTextColor(0.35, 0.35, 0.35)
        f.Instructions:SetPoint("TOPLEFT", 16, 0)
        f.Instructions:SetPoint("BOTTOMRIGHT", -20, 0)
        if Has("SearchBoxTemplate") then
            f.instructionText = "Search"
            f.Instructions:SetText(f.instructionText)
            f.searchIcon = f:CreateTexture()
            f.clearButton = NewObject("Button", nil, f)
            f.clearButton:Hide()
            f.clearButton:SetScript("OnClick", function()
                f:SetText("")
                f:ClearFocus()
            end)
            f:SetScript("OnEditFocusLost", function(self)
                if self:GetText() == "" then self.clearButton:Hide() end
            end)
            f:SetScript("OnEditFocusGained", function(self)
                self.clearButton:Show()
            end)
        end
        f:SetScript("OnTextChanged", function(self)
            self.Instructions:SetShown(self:GetText() == "")
            if self.clearButton then
                self.clearButton:SetShown(self:HasFocus() or self:GetText() ~= "")
            end
        end)
    end
    if Has("InputScrollFrameTemplate") then
        f.EditBox = NewObject("EditBox", nil, f)
        f.EditBox.Instructions = f.EditBox:CreateFontString()
        f.EditBox._multiLine = true
        f.ScrollBar = NewObject("Slider", nil, f)
        f:SetScrollChild(f.EditBox)
    end
    if kind == "DropdownButton" then
        AddDropdownMethods(f)
    end
    if Has("EditModeSettingSliderTemplate") then
        f.Label = f:CreateFontString()
        f.Slider = NewObject("Slider", nil, f)
        AddSettingSliderMethods(f.Slider)
        function f:SetupSetting(data)
            self.data = data
            self.Label:SetText(data.settingName)
            local info = data.displayInfo
            local steps = info.stepSize and (info.maxValue - info.minValue) / info.stepSize
            self.Slider:Init(data.currentValue, info.minValue, info.maxValue, steps, { info.formatter })
        end
        f.Slider:SetScript("OnValueChanged", function(_, value)
            if f.data and f:GetParent() then
                f:GetParent():OnSettingValueChanged(f.data.displayInfo.setting, value)
            end
        end)
    end
    if Has("EditModeSettingCheckboxTemplate") then
        f.Label = f:CreateFontString()
        f.Button = NewObject("CheckButton", nil, f)
        function f:SetupSetting(data)
            self.data = data
            self.Label:SetText(data.settingName)
            self.Button:SetChecked(data.currentValue == 1 or data.currentValue == true)
        end
        f.Button:SetScript("OnClick", function(button)
            if f.data and f:GetParent() then
                f:GetParent():OnSettingValueChanged(f.data.displayInfo.setting, button:GetChecked() and 1 or 0)
            end
        end)
    end
    if Has("EditModeSettingDropdownTemplate") then
        f.Label = f:CreateFontString()
        f.Dropdown = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
        function f:SetupSetting(data)
            self.data = data
            self.Label:SetText(data.settingName)
            self.Dropdown:SetupMenu(function(_, root)
                for _, option in ipairs(data.displayInfo.options or {}) do
                    local value, text = option.value or option[1], option.text or option[2]
                    root:CreateRadio(text, function() return data.currentValue == value end, function()
                        data.currentValue = value
                        if self:GetParent() then
                            self:GetParent():OnSettingValueChanged(data.displayInfo.setting, value)
                        end
                    end)
                end
            end)
        end
    end
    if Has("EditModeSystemSelectionTemplate") then
        f.Label = f:CreateFontString()
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
    if Has("UIPanelScrollFrameTemplate") then
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
-- SetOwner starts a new tooltip (the client clears its lines); SetText
-- replaces everything with one line.
function GameTooltip:SetOwner(owner, anchor)
    M.tooltipOwner, M.tooltipAnchor = owner, anchor
    M.tooltip = {}
end
function GameTooltip:IsOwned(owner)
    return M.tooltipOwner == owner
end
function GameTooltip:SetText(text)
    M.tooltip = { text }
end
function GameTooltip:NumLines()
    return #(M.tooltip or {})
end
DEFAULT_CHAT_FRAME = NewObject("Frame", "ChatFrame1", UIParent)
function DEFAULT_CHAT_FRAME:AddMessage(msg)
    table.insert(M.printed, msg)
end
UISpecialFrames = {}
SlashCmdList = {}
ChatFontNormal = {}

function PanelTemplates_SetNumTabs(frame, n)
    frame.numTabs = n
end
function PanelTemplates_SetTab(frame, i)
    frame.selectedTab = i
end
function PanelTemplates_GetSelectedTab(frame)
    return frame.selectedTab
end
function PanelTemplates_TabResize(tab, padding)
    tab:SetWidth(tab:GetTextWidth() + (padding or 0) + tab.Left:GetWidth() + tab.Right:GetWidth())
end
PanelTemplates_UpdateTabs = noop
PanelTemplates_DeselectTab = noop
PanelTemplates_SelectTab = noop
ButtonFrameTemplate_HideAttic = noop
ButtonFrameTemplate_ShowButtonBar = noop
ButtonFrameTemplate_HidePortrait = noop

UIPanelWindows = {}
function RegisterUIPanel(frame, attrs)
    UIPanelWindows[frame:GetName()] = attrs
end
function ToggleFrame(frame)
    frame:SetShown(not frame:IsShown())
end
function InputScrollFrame_SetInstructions(frame, text)
    if not rawget(frame.EditBox, "Instructions") then
        frame.EditBox.Instructions = frame.EditBox:CreateFontString()
    end
    frame.EditBox.Instructions:SetText(text)
end
function GetAppropriateTooltip()
    return GameTooltip
end

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
M.cvars = { rotateMinimap = "0", worldMapShowPlayerCoords = "0", worldMapShowCursorCoords = "0" }

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
function SetCVar(k, v)
    M.cvars[k] = tostring(v)
end
C_CVar = {
    GetCVar = GetCVar,
    SetCVar = SetCVar,
    GetCVarBool = function(k)
        return M.cvars[k] == "1"
    end,
    GetCVarInfo = function(k)
        return M.cvars[k] ~= nil and M.cvars[k] or nil
    end,
}
function GetCursorPosition()
    return 0, 0
end
function ShowUIPanel(frame)
    M.uiPanelCalls.show = M.uiPanelCalls.show + 1
    if M.player.combat then
        M.actionBlocked = (M.actionBlocked or 0) + 1
        return
    end
    frame:Show()
end
function HideUIPanel(frame)
    M.uiPanelCalls.hide = M.uiPanelCalls.hide + 1
    if M.player.combat then
        M.actionBlocked = (M.actionBlocked or 0) + 1
        return
    end
    frame:Hide()
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
-- Like the client: hooksecurefunc([table,] "name", hook) raises when the
-- arguments are wrong or the target is not a function, at hook time.
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then
        t, name, fn = _G, t, name
    end
    if type(t) ~= "table" or type(name) ~= "string" or type(fn) ~= "function" then
        error('Usage: hooksecurefunc([table,] "functionName", hookfunc)', 2)
    end
    local orig = t[name]
    if type(orig) ~= "function" then
        error(("hooksecurefunc(): %s is not a function"):format(name), 2)
    end
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
    M.editModeEntered = M.editModeEntered + 1
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
Enum.EditModeSettingDisplayType = { Dropdown = 0, Slider = 1, Checkbox = 2 }

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
M.worldRects = {
    [13] = { 0.55, 0.95, 0.10, 0.90 },
    [12] = { 0.05, 0.45, 0.10, 0.90 },
}
M.explored = {
    [37] = { { textureWidth = 300, textureHeight = 270, offsetX = 100, offsetY = 50,
        fileDataIDs = { 9001, 9002, 9003, 9004 }, isShownByMouseOver = false, isDrawOnTopLayer = false } },
}

local function MapToWorld(m, x, y)
    return m.top - y * m.h, m.left - x * m.w
end
local function WorldToMap(m, wx, wy)
    return (m.left - wy) / m.w, (m.top - wx) / m.h
end

C_Map = {}
function C_Map.GetMapArtID(id)
    return M.maps[id] and id * 10 or nil
end
function C_Map.MapHasArt(id)
    return M.maps[id] and not M.maps[id].noArt
end
function C_Map.GetMapArtLayers(id)
    if not C_Map.MapHasArt(id) then return nil end
    return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256,
        minScale = 1, maxScale = 1, additionalZoomSteps = 0 } }
end
function C_Map.GetMapArtLayerTextures(id, layer)
    if not C_Map.MapHasArt(id) or layer ~= 1 then return nil end
    local textures = {}
    for i = 1, 12 do
        textures[i] = id * 1000 + i
    end
    return textures
end
function C_Map.GetMapRectOnMap(child, top)
    local m = M.maps[child]
    local rect = top == 947 and m and m.mapType == 2 and M.worldRects[child]
    if rect then return unpack(rect) end
end
C_MapExplorationInfo = {
    GetExploredMapTextures = function(id) return M.explored[id] or {} end,
}
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
function MapCanvasDataProviderMixin:OnMapChanged()
    if self.RefreshAllData then self:RefreshAllData() end
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
WorldMapFrame.ScrollContainer.Child = NewObject("Frame", nil, WorldMapFrame.ScrollContainer)
function WorldMapFrame.ScrollContainer:GetCanvasScale()
    return 1
end
WorldMapFrame.WorldMapTrackingPinButton = NewObject("Button", nil, WorldMapFrame)
WorldMapFrame.overlayFrames = {}
WorldMapFrame.mapID = 37
WorldMapFrame.pins = {}
WorldMapFrame.providers = {}
WorldMapFrame.clickHandlers = {}
function WorldMapFrame:GetMapID()
    return self.mapID
end
function WorldMapFrame:SetMapID(id)
    self.mapID = id
    self:OnMapChanged()
end
function WorldMapFrame:OnMapChanged()
    for _, p in ipairs(self.providers) do
        if p.OnMapChanged then
            p:OnMapChanged()
        elseif p.RefreshAllData then
            p:RefreshAllData()
        end
    end
end
function WorldMapFrame:GetCanvas()
    return self.ScrollContainer.Child
end
function WorldMapFrame:Show()
    local was = self:IsVisible()
    Frame.Show(self)
    if not was and self:IsVisible() then
        for _, p in ipairs(self.providers) do
            if p.OnShow then p:OnShow() end
        end
    end
end
function WorldMapFrame:Hide()
    local was = self:IsVisible()
    Frame.Hide(self)
    if was then
        for _, p in ipairs(self.providers) do
            if p.OnHide then p:OnHide() end
        end
    end
end
function WorldMapFrame:GetCanvasContainer()
    return self.ScrollContainer
end
function WorldMapFrame:AddOverlayFrame(template, kind, point, rel, relPoint, x, y)
    local frame = CreateFrame(kind, nil, self, template)
    frame:SetPoint(point, rel, relPoint, x, y)
    table.insert(self.overlayFrames, frame)
    return frame
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
    local mixin
    if template == "WaypointTrackerRoutePinTemplate" then
        mixin = _G.WaypointTrackerRoutePinMixin
        pin.Number = pin:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    elseif template == "WaypointTrackerMapPinTemplate" then
        mixin = _G.WaypointTrackerMapPinMixin
    end
    Mixin(pin, MapCanvasPinMixin)
    if mixin then Mixin(pin, mixin) end
    pin.template = template
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
function WorldMapFrame:RemoveAllPinsByTemplate(template)
    local kept = {}
    for _, p in ipairs(self.pins) do
        if not template or p.template == template then
            p:Hide()
        else
            table.insert(kept, p)
        end
    end
    self.pins = kept
end
PIN_FRAME_LEVEL_WAYPOINT_LOCATION = "PIN_FRAME_LEVEL_WAYPOINT_LOCATION"
function OpenWorldMap(id)
    if M.player.combat then
        M.actionBlocked = (M.actionBlocked or 0) + 1
        return
    end
    M.worldMapOpened = id
    ShowUIPanel(WorldMapFrame)
    WorldMapFrame:SetMapID(id)
end
function ToggleWorldMap()
    if WorldMapFrame:IsShown() then
        HideUIPanel(WorldMapFrame)
    else
        OpenWorldMap(C_Map.GetBestMapForUnit("player"))
    end
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
        local root = NewMenuRoot()
        gen(owner, root)
        root.owner, root.open = owner, true
        M.lastMenu = root
        table.insert(M.menus, root)
        return root
    end,
}

-- Click path ------------------------------------------------------------------
-- M.ClickButton(button, mouseButton) presses and releases the mouse on a widget
-- the way the game does: OnMouseDown (intrinsic handler first, so a
-- DropdownButton toggles its menu), OnMouseUp, and OnClick when the widget is
-- an enabled Button registered for that click. Buttons answer "LeftButtonUp"
-- until RegisterForClicks replaces the set ("AnyUp"/"AnyDown" match every
-- button; "...Down" registrations click on press). Button:Click() stays the
-- programmatic call, which ignores registration like the client.
-- Returns the menu the click opened (dropdown or context menu), or nil.
local function ClickRegistered(button, mouseButton, phase)
    local list = rawget(button, "_clickButtons") or { "LeftButtonUp" }
    for _, reg in ipairs(list) do
        if reg == mouseButton .. phase or reg == "Any" .. phase then
            return true
        end
    end
    return false
end
function M.ClickButton(button, mouseButton)
    mouseButton = mouseButton or "LeftButton"
    local before = #M.menus
    local isButton = button.Click ~= nil
    local enabled = isButton and (not button.IsEnabled or button:IsEnabled())
    button:RunScript("OnMouseDown", mouseButton)
    if enabled and ClickRegistered(button, mouseButton, "Down") then
        button:RunScript("OnClick", mouseButton, true)
    end
    button:RunScript("OnMouseUp", mouseButton, true)
    if enabled and ClickRegistered(button, mouseButton, "Up") then
        button:RunScript("OnClick", mouseButton, false)
    end
    if #M.menus > before then
        return M.menus[#M.menus]
    end
end
-- Opens a dropdown or context menu through the click path; errors when the
-- click opens nothing, so a broken entry point fails the test.
function M.OpenMenu(button, mouseButton)
    local menu = M.ClickButton(button, mouseButton)
    if not menu then
        error(("wowmock: clicking %s with %s opened no menu"):format(
            tostring(button:GetName() or button:GetObjectType()), mouseButton or "LeftButton"), 2)
    end
    return menu
end
-- Finds an item by text (and kind) in a menu, searching submenus.
function M.FindMenuItem(menu, text, kind)
    for _, item in ipairs(menu.items or {}) do
        if item.text == text and (not kind or item.kind == kind) then
            return item
        end
        local sub = item.items and M.FindMenuItem(item, text, kind)
        if sub then
            return sub
        end
    end
end
-- Picks an item like a click in the open menu: runs its callback, then
-- closes the menu (the default menu response).
function M.PickMenuItem(menu, text, kind)
    assert(menu.open ~= false, "wowmock: menu is closed")
    local item = M.FindMenuItem(menu, text, kind)
    if not item then
        error(("wowmock: menu has no %s item %q"):format(kind or "", tostring(text)), 2)
    end
    if item.enabled == false then
        error(("wowmock: menu item %q is disabled"):format(tostring(text)), 2)
    end
    local result
    if item.fn then
        result = item.fn()
    end
    if menu.owner and menu.owner.CloseMenu and menu.owner.menu == menu then
        menu.owner:CloseMenu()
    end
    menu.open = false
    return item, result
end
local nextCategoryID = 1
local function NewCategory(name)
    nextCategoryID = nextCategoryID + 1
    local category = { name = name, ID = nextCategoryID, subcategories = {} }
    function category:GetID()
        return self.ID
    end
    return category
end
local function NewInitializer(kind, name)
    local initializer = { kind = kind, name = name, searchTags = {} }
    function initializer:SetParentInitializer(parent, predicate)
        self.parentInitializer, self.parentPredicate = parent, predicate
    end
    function initializer:AddShownPredicate(fn)
        self.shownPredicates = self.shownPredicates or {}
        table.insert(self.shownPredicates, fn)
    end
    function initializer:ShouldShow()
        for _, fn in ipairs(self.shownPredicates or {}) do
            if not fn() then return false end
        end
        return true
    end
    function initializer:AddSearchTags(...)
        for i = 1, select("#", ...) do
            local tag = select(i, ...)
            table.insert(self.searchTags, tag)
        end
    end
    return initializer
end
local function SettingsControl(kind, cat, setting, options, tooltip)
    local initializer = NewInitializer(kind, setting.name)
    initializer.cat, initializer.setting = cat, setting
    initializer.options, initializer.tooltip = options, tooltip
    table.insert(M.settingsControls, initializer)
    return initializer
end
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        M.settingsCategory = NewCategory(name)
        M.settingsCategory.frame = frame
        return M.settingsCategory
    end,
    RegisterAddOnCategory = noop,
    RegisterVerticalLayoutCategory = NewCategory,
    RegisterVerticalLayoutSubcategory = function(parent, name)
        local category = NewCategory(name)
        category.parent = parent
        table.insert(parent.subcategories, category)
        return category
    end,
    RegisterProxySetting = function(cat, var, valueType, name, default, get, set)
        local setting = { cat = cat, variable = var, valueType = valueType, name = name, default = default,
            GetValue = get }
        function setting:SetValue(value)
            local old = self:GetValue()
            set(value)
            if self.onValueChanged and self:GetValue() ~= old then
                self.onValueChanged(self, self:GetValue())
            end
        end
        function setting:SetValueChangedCallback(fn)
            self.onValueChanged = fn
        end
        function setting:NotifyUpdate()
            M.settingsNotified[var] = true
        end
        M.settings[var] = setting
        return setting
    end,
    CreateCheckbox = function(cat, setting, tooltip)
        return SettingsControl("checkbox", cat, setting, nil, tooltip)
    end,
    CreateSlider = function(cat, setting, options, tooltip)
        return SettingsControl("slider", cat, setting, options, tooltip)
    end,
    CreateDropdown = function(cat, setting, options, tooltip)
        return SettingsControl("dropdown", cat, setting, options, tooltip)
    end,
    CreateColorSwatch = function(cat, setting, tooltip)
        return SettingsControl("colorSwatch", cat, setting, nil, tooltip)
    end,
    CreateSliderOptions = function(min, max, step)
        local options = { min = min, max = max, step = step, formatters = {} }
        function options:SetLabelFormatter(label, fn)
            self.formatters[label] = fn
        end
        return options
    end,
    CreateControlTextContainer = function()
        local container = { data = {} }
        function container:Add(value, text, tooltip)
            table.insert(self.data, { value = value, text = text, tooltip = tooltip })
        end
        function container:GetData()
            return self.data
        end
        return container
    end,
    OpenToCategory = function(id)
        M.settingsOpened = id
    end,
    NotifyUpdate = function(var)
        M.settingsNotified[var] = true
    end,
    VarType = { Boolean = "boolean", Number = "number", String = "string" },
    KEYBINDINGS_CATEGORY_ID = 1,
    GetSetting = function(var)
        return M.settings[var]
    end,
}
SettingsPanel = NewObject("Frame", "SettingsPanel", UIParent)
SettingsPanel._shown = false
function SettingsPanel:GetLayout(category)
    local layout = M.settingsLayouts[category]
    if not layout then
        layout = { initializers = {} }
        function layout:AddInitializer(initializer)
            table.insert(self.initializers, initializer)
        end
        M.settingsLayouts[category] = layout
    end
    return layout
end
function SettingsPanel:Close()
    self:Hide()
end
function CreateSettingsListSectionHeaderInitializer(name)
    return NewInitializer("header", name)
end
function CreateSettingsButtonInitializer(name, text, click, tooltip, search)
    local initializer = NewInitializer("button", name)
    initializer.text, initializer.click = text, click
    initializer.tooltip, initializer.search = tooltip, search
    return initializer
end
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }

StaticPopupDialogs = {}
function StaticPopup_Show(which, a1, a2, data)
    M.lastPopup = which
    M.lastPopupArgs = { a1, a2, data }
    local d = StaticPopupDialogs[which]
    if not d then
        return
    end
    local frame = NewObject("Frame", nil, UIParent)
    frame.which, frame.data = which, data
    M.popups[which] = frame
    local fn
    if M.autoAcceptPopup then
        fn = d.OnAccept
    elseif M.autoAltPopup then
        fn = d.OnAlt
    elseif M.autoCancelPopup then
        fn = d.OnCancel
    end
    if fn then
        fn(frame, data)
        frame:Hide()
    end
    return frame
end
function StaticPopup_Hide(which)
    local frame = M.popups[which]
    if frame then
        frame:Hide()
    end
end
function StaticPopup_Visible(which)
    local frame = M.popups[which]
    return frame and frame:IsShown() or false
end

HelpTip = {
    Point = { TopEdgeLeft = 1, TopEdgeCenter = 2, TopEdgeRight = 3,
        BottomEdgeLeft = 4, BottomEdgeCenter = 5, BottomEdgeRight = 6,
        RightEdgeTop = 7, RightEdgeCenter = 8, RightEdgeBottom = 9,
        LeftEdgeTop = 10, LeftEdgeCenter = 11, LeftEdgeBottom = 12 },
    Alignment = { Left = 1, Center = 2, Right = 3 },
    ButtonStyle = { None = 1, Close = 2, Okay = 3, GotIt = 4 },
}
function HelpTip:Show(parent, info, relativeRegion)
    table.insert(M.helpTips, { parent = parent, info = info, relativeRegion = relativeRegion, shown = true })
    return true
end
function HelpTip:Hide(parent, text)
    for _, tip in ipairs(M.helpTips) do
        if tip.parent == parent and (text == nil or tip.info.text == text) then
            tip.shown = false
        end
    end
end
function HelpTip:IsShowing(parent, text)
    for _, tip in ipairs(M.helpTips) do
        if tip.shown and tip.parent == parent and (text == nil or tip.info.text == text) then
            return true
        end
    end
    return false
end
function HelpTip:Acknowledge(parent, text)
    for _, tip in ipairs(M.helpTips) do
        if tip.shown and tip.parent == parent and (text == nil or tip.info.text == text) then
            tip.shown = false
            if tip.info.onAcknowledgeCallback then
                tip.info.onAcknowledgeCallback(tip.info.callbackArg)
            end
        end
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

-- Every shared widget method must be a client method of some family above
-- (or a documented test helper), so the mock cannot invent widget API.
for name in pairs(Frame) do
    local known = TEST_HELPERS[name]
    for _, set in pairs(familySets) do
        known = known or set[name]
    end
    if not known then
        error("wowmock: Frame:" .. name .. " is not in any client widget family")
    end
end

return M
