-- HUD systems, shared settings, per-layout positions and optional templates.
-- Run from the repository root with Lua 5.1; --bare disables Edit Mode templates.
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local bare = arg[1] == "--bare"
local createFrame = CreateFrame
-- Parcel-local model of forever's EditModeTemplates.lua and EditModeDialogs.lua:
-- callbacks installed on load target the GLOBAL Blizzard dialog, even when the
-- controls belong to an addon. Keep wowmock.lua unchanged for other parcels.
local blizzard = { calls = 0, changes = 0, interactions = 0 }
EditModeSystemSettingsDialog = blizzard
function blizzard:OnSettingValueChanged(setting, value)
    self.calls = self.calls + 1
    if self.attachedToSystem then
        self.changes = self.changes + 1
        self.lastSetting, self.lastValue = setting, value
    end
end
function blizzard:OnSettingInteractStart() self.interactions = self.interactions + 1 end
function blizzard:OnSettingInteractEnd() self.interactions = self.interactions + 1 end
local events = { OnValueChanged = "OnValueChanged", OnInteractStart = "OnInteractStart", OnInteractEnd = "OnInteractEnd" }
MinimalSliderWithSteppersMixin.Event = events
CreateFrame = function(kind, name, parent, template)
    local f = createFrame(kind, name, parent, template)
    if name == "WaypointTrackerEditModeDialog" then
        function f:SetMovable(on) self.movable = on end
        function f:RegisterForDrag(button) self.dragButton = button end
    end
    if template == "EditModeSettingSliderTemplate" then
        local slider, setup, init = f.Slider, f.SetupSetting, f.Slider.Init
        f.Label:SetWidth(100) -- native XML default
        slider:SetScript("OnValueChanged", nil) -- remove the mock's incorrect parent path
        slider._callbacks = {}
        function slider:UnregisterCallback(event, owner)
            if self._callbacks[event] then self._callbacks[event][owner] = nil end
        end
        function slider:RegisterCallback(event, fn, owner)
            self:UnregisterCallback(event, owner)
            self._callbacks[event] = self._callbacks[event] or {}
            self._callbacks[event][owner] = fn
        end
        function slider:TriggerEvent(event, ...)
            for owner, fn in pairs(self._callbacks[event] or {}) do fn(owner, ...) end
        end
        function slider:SetValue(value)
            if self._value == value then return end
            self._value = value
            self:TriggerEvent(events.OnValueChanged, value)
        end
        function slider:Init(value, ...)
            self.initCalls = (self.initCalls or 0) + 1
            init(self, value, ...)
            self:TriggerEvent(events.OnValueChanged, value)
        end
        function f:OnSliderValueChanged(value)
            if not self.initInProgress then EditModeSystemSettingsDialog:OnSettingValueChanged(self.setting, value) end
        end
        function f:OnSliderInteractStart() EditModeSystemSettingsDialog:OnSettingInteractStart(self.setting) end
        function f:OnSliderInteractEnd() EditModeSystemSettingsDialog:OnSettingInteractEnd(self.setting) end
        slider:RegisterCallback(events.OnValueChanged, f.OnSliderValueChanged, f)
        slider:RegisterCallback(events.OnInteractStart, f.OnSliderInteractStart, f)
        slider:RegisterCallback(events.OnInteractEnd, f.OnSliderInteractEnd, f)
        function f:SetupSetting(data)
            self.initInProgress, self.setting = true, data.displayInfo.setting
            setup(self, data)
            self.initInProgress = false
        end
    elseif template == "EditModeSettingCheckboxTemplate" then
        local setup = f.SetupSetting
        function f:SetupSetting(data)
            self.setting, self.checked = data.displayInfo.setting, data.currentValue == 1
            setup(self, data)
        end
        function f:OnCheckButtonClick()
            self.checked = not self.checked
            EditModeSystemSettingsDialog:OnSettingValueChanged(self.setting, self.checked and 1 or 0)
        end
        f.Button:SetScript("OnClick", function() f:OnCheckButtonClick() end)
    elseif template == "EditModeSettingDropdownTemplate" then
        local setup = f.SetupSetting
        function f:SetupSetting(data)
            setup(self, data)
            self.setting = data.displayInfo.setting
            local function enter() EditModeSystemSettingsDialog:OnSettingInteractStart(self.setting) end
            local function leave() EditModeSystemSettingsDialog:OnSettingInteractEnd(self.setting) end
            self.Dropdown:SetScript("OnEnter", enter)
            self.Dropdown:SetScript("OnLeave", leave)
            self.Dropdown:SetupMenu(function(_, root)
                for _, option in ipairs(data.displayInfo.options) do
                    local value = option.value
                    root:CreateRadio(option.text, function() return data.currentValue == value end,
                        function() EditModeSystemSettingsDialog:OnSettingValueChanged(self.setting, value) end)
                end
            end)
        end
        f:SetScript("OnEnter", function() EditModeSystemSettingsDialog:OnSettingInteractStart(f.setting) end)
        f:SetScript("OnLeave", function() EditModeSystemSettingsDialog:OnSettingInteractEnd(f.setting) end)
    end
    return f
end
if bare then
    Enum.EditModeSettingDisplayType = nil
    CreateFrame = function(kind, name, parent, template)
        if template and (template:find("EditMode") or (template == "DialogBorderTranslucentTemplate" or template == "WowStyle1DropdownTemplate")) then
            error("optional template missing")
        end
        local f = createFrame(kind, name, parent, template)
        if name == "WaypointTrackerEditModeDialog" then
            function f:SetMovable(on) self.movable = on end
            function f:RegisterForDrag(button) self.dragButton = button end
        end
        return f
    end
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

if not bare then
    -- Prove the unmodified mixin path discards changes when detached, then
    -- would apply our setting index to an attached Blizzard system.
    local probe = CreateFrame("Frame", nil, UIParent, "EditModeSettingSliderTemplate")
    probe:SetupSetting({ settingName = "Probe", currentValue = 1,
        displayInfo = { setting = 42, minValue = 0, maxValue = 2, stepSize = 0.1 } })
    probe.Slider:SetValue(1.2)
    check(blizzard.calls == 1 and blizzard.changes == 0, "native mixin targets the detached global dialog, not its parent")
    blizzard.attachedToSystem = {}
    probe.Slider:SetValue(1.4)
    check(blizzard.changes == 1 and blizzard.lastSetting == 42, "native mixin can change an attached Blizzard system")
    probe:Hide()
    blizzard.calls, blizzard.changes = 0, 0
end

WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local edit, arrow, WP = ns.EditMode, ns.Arrow, ns.WP
local settingChanges = 0
ns.On("SETTING_CHANGED", function() settingChanges = settingChanges + 1 end)
local af, tf, coords = arrow.frame, arrow.textFrame, WaypointTrackerCoordsBox
WP.ClearAll()
local point, relative = coords:GetPoint()
local x, y, _
check(point == "TOP" and relative == Minimap, "coordinates start under the minimap")
check(not coords:IsShown() and not coords:IsMouseEnabled(), "disabled coordinates ignore the mouse and stay hidden")
check(WaypointTrackerArrowSelection == nil, "selection boxes are created on entry")

local ok = edit.Enter()
M.Tick(0.1)
local sel, tsel, csel = WaypointTrackerArrowSelection, WaypointTrackerTextSelection, WaypointTrackerCoordsSelection
check(ok and edit.IsActive() and M.editModeEntered == 1, "Enter uses Blizzard Edit Mode")
check(sel and sel:IsShown(), "Edit Mode shows the arrow selection")
check(af:IsShown() and arrow.editing and not af:IsMouseEnabled(), "the arrow previews while remaining click-through")
check(tsel and not tsel:IsShown(), "grouped text has no separate selection")
check(csel and csel:IsShown() and coords:IsShown() and coords:GetAlpha() == 0.5, "disabled coordinates preview in Edit Mode")
check(csel:GetParent() == coords and csel.system:GetSystemName() == ns.L.COORDS_EDIT_NAME, "coordinates selection identifies its system")

sel:RunScript("OnMouseDown")
local d = WaypointTrackerEditModeDialog
check(d and d:IsShown() and edit.selected == "arrow", "selecting the arrow opens the shared dialog")
check(EditModeManagerFrame.cleared > 0, "selecting an addon system deselects Blizzard systems")
check(d.Border and d.reset:GetText() == ns.L.RESET_DEFAULT, "dialog uses a border and reset-to-default button")
check(d.reset:GetWidth() >= d.reset:GetFontString():GetStringWidth() + 24 and d.reset:GetWidth() <= 372,
    "reset button fits its translated text and the dialog content width")
point, relative, _, x, y = d.title:GetPoint()
check(point == "TOP" and relative == d and x == 0 and y == -15, "dialog title is centered like Blizzard's")
point, relative, _, x, y = d.close:GetPoint()
check(point == "TOPRIGHT" and relative == d and x == 0 and y == 0, "dialog close button uses Blizzard's corner offsets")
check(d.movable and d.dragButton == "LeftButton", "dialog enables native dragging")
local starts, stops = 0, 0
d.StartMoving = function() starts = starts + 1 end
d.StopMovingOrSizing = function() stops = stops + 1 end
d:RunScript("OnDragStart")
d:RunScript("OnDragStop")
check(starts == 1 and stops == 1, "dialog drag scripts start and stop movement")
M.player.combat = true
d:RunScript("OnDragStart")
check(starts == 1, "dialog does not start dragging in combat")
M.player.combat = false
check(d.controls.arrowScale and d.controls.textScale and d.controls.textSeparate, "arrow dialog has its five setting controls")
if bare then
    d.controls.arrowScale.slider:SetValue(1.5)
else
    check(d.controls.arrowScale.native and d.controls.arrowScale.data.displayInfo.setting == 1, "arrow size uses the native slider")
    local info = d.controls.arrowScale.data.displayInfo
    check(info.minValue == 0.5 and info.maxValue == 2 and info.stepSize == 0.05 and info.formatter(1) == "100%", "native slider receives range, step and formatter")
    local before = settingChanges
    ns.Fire("SETTING_CHANGED", "arrowScale")
    check(settingChanges == before + 1, "initializing native sliders does not write settings")
    for _, key in ipairs({ "arrowScale", "arrowAlpha", "textScale", "textAlpha" }) do
        check(d.controls[key].Label:GetWidth() == 160, key .. " label stays wide after initialization and refresh")
    end
    local slider, other = d.controls.arrowScale.Slider, d.controls.arrowAlpha.Slider
    local inits, otherInits = slider.initCalls, other.initCalls
    before = settingChanges
    slider:TriggerEvent(events.OnInteractStart)
    check(d.interacting == 1, "native slider interaction start tracks the setting index")
    slider:SetValue(1.4)
    slider:SetValue(1.5)
    check(ns.Get("arrowScale") == 1.5 and af:GetScale() == 1.5 and settingChanges == before + 2,
        "drag values apply immediately and write each setting exactly once")
    check(slider.initCalls == inits, "setting changes do not reinitialize the dragging slider")
    ns.Set("arrowAlpha", 0.65)
    check(slider.initCalls == inits and other.initCalls > otherInits and other:GetValue() == 0.65,
        "other controls still refresh during a slider drag")
    slider:TriggerEvent(events.OnInteractEnd)
    check(d.interacting == nil, "native slider interaction end clears the setting index")
    ns.Fire("SETTING_CHANGED", "arrowScale")
    check(slider.initCalls > inits and d.controls.arrowScale.data.currentValue == 1.5,
        "released sliders resume normal refreshes")
end
check(ns.Get("arrowScale") == 1.5 and af:GetScale() == 1.5, "arrow slider updates the setting and frame")
ns.Set("arrowScale", 1.25)
if bare then
    check(d.controls.arrowScale.slider:GetValue() == 1.25, "fallback dialog follows external setting changes")
else
    check(d.controls.arrowScale.data.currentValue == 1.25, "native dialog follows external setting changes")
    d.controls.arrowScale.Slider:SetValue(1.5)
    check(ns.Get("arrowScale") == 1.5, "native slider callback updates the setting")
end
local count = #M.frames
if not bare then d.controls.arrowScale.Slider:TriggerEvent(events.OnInteractStart) end
edit.Select("arrow")
check(#M.frames == count, "selecting the same system reuses controls")
check(d.interacting == nil, "rebuilding cached controls clears a previous interaction")

sel:RunScript("OnDragStart")
af:ClearAllPoints()
af:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -200)
sel:RunScript("OnDragStop")
check(ns.Get("arrowLayouts").Modern[3] == 300 and ns.Get("arrowPos")[3] == 300, "arrow drag saves the Modern layout and fallback")
if not bare then d.controls.arrowScale.Slider:TriggerEvent(events.OnInteractStart) end
EditModeManagerFrame:SelectSystem({})
check(not d:IsShown() and edit.selected == nil, "selecting a Blizzard frame closes the addon dialog")
check(d.interacting == nil, "deselecting clears an interrupted slider interaction")

M.editActive = 2
M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
M.Tick(0.1)
point, _, _, x = af:GetPoint()
check(arrow.layout == "Classic" and point == "TOPLEFT" and x == 300, "new layouts use the last saved position")
sel:RunScript("OnDragStart")
af:ClearAllPoints()
af:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 500, -200)
sel:RunScript("OnDragStop")
M.editActive = 1
M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
M.Tick(0.1)
point, _, _, x = af:GetPoint()
check(point == "TOPLEFT" and x == 300, "Modern retains its own arrow position")
M.editActive = 2
M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
M.Tick(0.1)
point, _, _, x = af:GetPoint()
check(x == 500, "Classic retains its own arrow position")
edit.Select("arrow")
d.reset:Click()
point, _, _, x = af:GetPoint()
check(point == "CENTER" and x == 0 and ns.Get("arrowLayouts").Classic == nil, "reset clears the current layout and restores the default")
EditModeManagerFrame:ExitEditMode()
M.Tick(0.1)
check(not edit.IsActive() and not sel:IsShown() and not arrow.editing and not d:IsShown(), "exit hides selections and the settings dialog")
check(not coords:IsShown() and coords:GetAlpha() == 1, "exit hides disabled coordinates and restores alpha")
ns.Set("arrowLayouts", nil)

point, relative = tf:GetPoint()
check(point == "TOP" and relative == af, "text anchors under the arrow by default")
ns.Set("textScale", 1.4)
ns.Set("textAlpha", 0.5)
ns.Set("arrowScale", 0.7)
check(tf:GetScale() == 1.4 and tf:GetAlpha() == 0.5 and af:GetScale() == 0.7, "text and arrow size and alpha remain independent")
arrow.SetMoving(true)
check(tf:IsMouseEnabled() and af:IsMouseEnabled(), "legacy move mode still drags both parts")
arrow.SetMoving(false)
ns.Set("textSeparate", true)
point, relative = tf:GetPoint()
check(point == "CENTER" and relative == UIParent, "separating text keeps its absolute position")
edit.Enter()
M.Tick(0.1)
check(tsel:IsShown(), "separate text has its own selection")
edit.Select("text")
check(edit.selected == "text" and d:IsShown() and not d.controls.arrowScale and d.controls.textScale, "text selection rebuilds the shared dialog")
tsel:RunScript("OnDragStart")
tf:ClearAllPoints()
tf:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -40)
tsel:RunScript("OnDragStop")
check(ns.Get("textLayouts").Classic[3] == 40, "text drag saves its layout")
point = af:GetPoint()
check(point == "CENTER", "moving text leaves the arrow in place")
ns.Set("textSeparate", false)
point, relative = tf:GetPoint()
check(not tsel:IsShown() and point == "TOP" and relative == af, "grouping hides the text selection and reanchors text")
M.editActive = 1
M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
M.Tick(0.1)
point, relative = tf:GetPoint()
check(point == "TOP" and relative == af, "layout changes keep grouped text under the arrow")
ns.Set("textSeparate", true)
point, _, _, x = tf:GetPoint()
check(point == "TOPLEFT" and x == 40, "separating text restores its saved spot")
edit.Select("arrow")
d.reset:Click()
check(ns.Get("arrowScale") == 1 and ns.Get("arrowAlpha") == 0.8 and ns.Get("textScale") == 1 and ns.Get("textAlpha") == 0.9, "arrow reset restores all display settings")
point, relative = tf:GetPoint()
check(not ns.Get("textSeparate") and point == "TOP" and relative == af and tf:GetScale() == 1, "reset restores grouped text")

csel:RunScript("OnDragStart")
coords:ClearAllPoints()
coords:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 160, -140)
csel:RunScript("OnDragStop")
check(ns.Get("coordsLayouts").Modern[3] == 160, "coordinates drag saves the Modern layout")
edit.Select("coords")
check(d.controls.coordsBox and not d.controls.arrowScale, "coordinates dialog contains only its checkbox")
if bare then
    d.controls.coordsBox:Click()
else
    d.controls.coordsBox.Button:Click()
end
check(ns.Get("coordsBox") == true and coords:GetAlpha() == 1, "native checkbox values become booleans")
if bare then d.controls.coordsBox:Click() else d.controls.coordsBox.Button:Click() end
check(ns.Get("coordsBox") == false and coords:IsShown() and coords:GetAlpha() == 0.5, "turning coordinates off retains the dim Edit Mode preview")
M.editActive = 2
M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
M.Tick(0.1)
csel:RunScript("OnDragStart")
coords:ClearAllPoints()
coords:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 260, -140)
csel:RunScript("OnDragStop")
M.editActive = 1
M.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
M.Tick(0.1)
point, relative, _, x = coords:GetPoint()
check(relative == UIParent and x == 160, "coordinates switch positions with layouts")
arrow.SetLayout("Classic")
point, relative, _, x = coords:GetPoint()
check(x == 260 and arrow.layout == "Classic", "Arrow.SetLayout remains a wrapper and applies every registered system")
arrow.SetLayout("Modern")
edit.Select("coords")
d.reset:Click()
point, relative = coords:GetPoint()
check(point == "TOP" and relative == Minimap and ns.Get("coordsLayouts").Classic[3] == 260, "coordinates reset restores minimap anchoring and preserves other layouts")
-- Saving an anchor relative to a scaled frame must convert to UIParent units.
local originalCenter, originalScale = coords.GetCenter, coords.GetEffectiveScale
coords.GetCenter = function() return 200, 300 end
coords.GetEffectiveScale = function() return 0.5 end
csel:RunScript("OnDragStart")
csel:RunScript("OnDragStop")
local pos = ns.Get("coordsLayouts").Modern
check(pos[1] == "CENTER" and pos[2] == "BOTTOMLEFT" and pos[3] == 100 and pos[4] == 150, "relative positions save absolute coordinates with the scale conversion")
coords.GetCenter, coords.GetEffectiveScale = originalCenter, originalScale

-- The recorder exercises generic settings on its existing registered frame.
local fake = ns.Recorder.frame
fake:Hide()
edit.RegisterSystem({
    key = "recorder", frame = fake, name = ns.L.RECORDER_EDIT_NAME,
    defaultPoint = { "TOP", "TOP", 0, -120 }, shouldShow = function() return true end,
    selectionInsets = { 2, 3, 4, 5 }, hint = ns.L.RECORDER_EDIT_HINT,
    settings = { { type = "dropdown", key = "arrowColour", label = ns.L.COLOUR,
        options = { { value = "distance", text = ns.L.COLOUR_DISTANCE }, { value = "direction", text = ns.L.COLOUR_DIRECTION } } } },
    onReset = function() edit.SavePosition("recorder", nil) end,
})
local rsel = WaypointTrackerRecorderSelection
check(rsel and rsel:GetParent() == fake and rsel:IsShown(), "the recorder reuses its selection when its settings change")
check(rsel.system:GetSystemName() == ns.L.RECORDER_EDIT_NAME, "selection names come from the registry")
rsel:RunScript("OnDragStart")
fake:ClearAllPoints()
fake:SetPoint("TOP", UIParent, "TOP", 50, -180)
rsel:RunScript("OnDragStop")
check(ns.Get("recorderLayouts").Modern[3] == 50 and ns.Get("recorderPos")[4] == -180, "generic drag saves fourth-system layout and fallback")
edit.Select("recorder")
check(d.hint:GetText() == ns.L.RECORDER_EDIT_HINT and d.controls.arrowColour, "fourth-system dialog uses its registered hint and dropdown")
if bare then
    d.controls.arrowColour.next:Click()
else
    local menu = d.controls.arrowColour.Dropdown:GenerateMenu()
    menu.items[2].fn()
end
check(ns.Get("arrowColour") == "direction", "dropdown actions update their setting")
if not bare then
    ns.Set("arrowColour", "distance")
    local control = d.controls.arrowColour
    local menu = control.Dropdown:GenerateMenu()
    check(menu.items[1].isSelected() and not menu.items[2].isSelected(), "dropdown selection follows external changes")
    control:RunScript("OnEnter")
    control:RunScript("OnLeave")
    control.Dropdown:RunScript("OnEnter")
    control.Dropdown:RunScript("OnLeave")
    menu.items[2].fn()
    check(ns.Get("arrowColour") == "direction", "refreshed dropdown keeps addon callbacks")
    control.Dropdown:RunScript("OnEnter")
    check(d.interacting == 1, "native dropdown interaction tracks the setting index")
    edit.Select("arrow")
    check(d.interacting == nil, "switching systems clears the old control's interaction")
    local before = settingChanges
    d.controls.arrowScale.Slider:SetValue(1.3)
    check(settingChanges == before + 1 and ns.Get("arrowScale") == 1.3, "cached slider still writes exactly once after switching systems")
    check(blizzard.calls == 0 and blizzard.changes == 0 and blizzard.interactions == 0,
        "addon controls never send values or interactions to the global Blizzard dialog")
end
edit.Select("recorder")
d.reset:Click()
point, _, _, x = fake:GetPoint()
check(point == "TOP" and x == 0, "fourth-system reset reapplies its default point")
EditModeManagerFrame:ExitEditMode()
M.Tick(0.1)
check(not rsel:IsShown() and not fake:IsShown(), "exit restores a fourth system's original visibility")

ns.Set("coordsBox", true)
check(coords:IsShown() and coords:GetAlpha() == 1 and not coords:IsMouseEnabled(), "enabled coordinates stay click-through outside Edit Mode")
ns.Set("coordsBox", false)
M.player.combat = true
local entered = M.editModeEntered
local success, reason = edit.Enter()
check(not success and reason == "combat" and M.editModeEntered == entered, "Enter in combat returns combat without calling Blizzard")
M.player.combat = false
local manager = EditModeManagerFrame
EditModeManagerFrame = nil
success, reason = edit.Enter()
check(success and reason == "legacy" and arrow.moving, "Enter without Blizzard uses legacy arrow movement")
success, reason = edit.Enter()
check(success and reason == "legacy" and not arrow.moving and not af:IsMouseEnabled() and not tf:IsMouseEnabled(),
    "Enter again ends legacy movement and restores click-through HUD frames")
local originalArrow = ns.Arrow
ns.Arrow = nil
success, reason = edit.Enter()
check(not success and reason == "unavailable", "Enter without either implementation reports unavailable")
ns.Arrow = originalArrow
EditModeManagerFrame = manager

for _, err in ipairs(M.errors) do check(false, "Lua error: " .. tostring(err)) end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
