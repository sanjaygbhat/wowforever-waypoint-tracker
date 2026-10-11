-- Each HUD element has a selection box and keeps its position per layout.
local _, ns = ...
local L, Widgets = ns.L, ns.Widgets

local EditMode = {}
ns.EditMode = EditMode

local systems, selections, dialog = {}, {}, nil
local active, dragging, refreshing = false, nil, false

local function ActiveLayoutName()
    local m = EditModeManagerFrame
    if not (m and m.GetActiveLayoutInfo) then return nil end
    local ok, info = pcall(m.GetActiveLayoutInfo, m)
    return ok and type(info) == "table" and info.layoutName or nil
end

function EditMode.IsActive()
    return active
end

function EditMode.SavedPosition(key)
    local layouts = ns.Get(key .. "Layouts")
    local layout = EditMode.layout
    if layout and type(layouts) == "table" and type(layouts[layout]) == "table" then
        return layouts[layout]
    end
    return ns.Get(key .. "Pos")
end

function EditMode.SavePosition(key, pos)
    if EditMode.layout then
        local layouts = ns.Get(key .. "Layouts")
        layouts = type(layouts) == "table" and layouts or {}
        layouts[EditMode.layout] = pos
        ns.Set(key .. "Layouts", layouts)
    end
    ns.Set(key .. "Pos", pos)
end

function EditMode.ApplyPosition(key)
    local spec = systems[key]
    if not spec then return end
    local f = spec.frame
    f:ClearAllPoints()
    local point, rel, x, y = ns.SavedPoint(EditMode.SavedPosition(key))
    if point then
        f:SetPoint(point, UIParent, rel, x, y)
    elseif spec.defaultAnchor then
        spec.defaultAnchor(f)
    else
        point, rel, x, y = ns.SavedPoint(spec.defaultPoint)
        if point then f:SetPoint(point, UIParent, rel, x, y) end
    end
    -- Grouped elements can re-anchor after applying their independent spot.
    if spec.onApply then spec.onApply(f) end
end

function EditMode.SetLayout(name)
    EditMode.layout = name
    for key in pairs(systems) do EditMode.ApplyPosition(key) end
    EditMode.PlaceDialog()
end

local function Template(kind, name, parent, template)
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok then return f end
end

local function SettingData(setting, index)
    local types = Enum and Enum.EditModeSettingDisplayType
    local names = { slider = "Slider", checkbox = "Checkbox", dropdown = "Dropdown" }
    if not types or not types[names[setting.type]] then return nil end
    local value = ns.Get(setting.key)
    if setting.type == "checkbox" then value = value and 1 or 0 end
    return {
        settingName = setting.label,
        currentValue = value,
        displayInfo = {
            setting = index, type = types[names[setting.type]],
            minValue = setting.min, maxValue = setting.max, stepSize = setting.step,
            formatter = setting.format or tostring, options = setting.options,
        },
    }
end

local function SetupDropdown(d, control, setting, index)
    -- SetupSetting rebuilds Blizzard's menu and its global-dialog callbacks.
    control.Dropdown:SetScript("OnEnter", function() d:OnSettingInteractStart(index) end)
    control.Dropdown:SetScript("OnLeave", function() d:OnSettingInteractEnd(index) end)
    control.Dropdown:SetupMenu(function(_, root)
        for _, option in ipairs(setting.options or {}) do
            local value, text = option.value or option[1], option.text or option[2]
            root:CreateRadio(text, function() return ns.Get(setting.key) == value end,
                function() d:OnSettingValueChanged(index, value) end)
        end
    end)
end

local function BindControl(d, control, setting, index)
    -- The native mixins call the global EditModeSystemSettingsDialog, not their
    -- parent. Replace only callbacks on our controls; leave Blizzard's dialog alone.
    if setting.type == "slider" then
        local slider = control.Slider
        local events = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event
        if not (slider and slider.RegisterCallback and slider.UnregisterCallback and events) then return false end
        slider:UnregisterCallback(events.OnValueChanged, control)
        slider:UnregisterCallback(events.OnInteractStart, control)
        slider:UnregisterCallback(events.OnInteractEnd, control)
        slider:RegisterCallback(events.OnValueChanged, function(_, value)
            if not control.initInProgress then d:OnSettingValueChanged(index, value) end
        end, control)
        slider:RegisterCallback(events.OnInteractStart, function() d:OnSettingInteractStart(index) end, control)
        slider:RegisterCallback(events.OnInteractEnd, function() d:OnSettingInteractEnd(index) end, control)
    elseif setting.type == "checkbox" and control.Button then
        control.OnCheckButtonClick = function(self)
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
            self.checked = not self.checked
            d:OnSettingValueChanged(index, self.checked and 1 or 0)
        end
        control.Button:SetScript("OnClick", function() control:OnCheckButtonClick() end)
    elseif setting.type == "dropdown" and control.Dropdown and control.Dropdown.SetupMenu then
        control:SetScript("OnEnter", function() d:OnSettingInteractStart(index) end)
        control:SetScript("OnLeave", function() d:OnSettingInteractEnd(index) end)
        SetupDropdown(d, control, setting, index)
    else
        return false
    end
    return true
end

local function CreateControl(d, setting, index)
    local names = {
        slider = "EditModeSettingSliderTemplate", checkbox = "EditModeSettingCheckboxTemplate",
        dropdown = "EditModeSettingDropdownTemplate",
    }
    local data = SettingData(setting, index)
    local control = data and Template("Frame", nil, d, names[setting.type])
    if control then
        refreshing = true
        local ok = control.SetupSetting and pcall(control.SetupSetting, control, data)
        refreshing = false
        if ok and BindControl(d, control, setting, index) then
            if setting.type == "slider" then control.Label:SetWidth(160) end
            control.native = true
            Widgets.Tooltip(control, setting.label, setting.tooltip)
            return control
        end
        control:Hide()
    end
    if setting.type == "slider" then
        return Widgets.Slider(d, setting.label, setting.key, setting.min, setting.max,
            setting.step, 372, setting.format, setting.tooltip)
    elseif setting.type == "checkbox" then
        return Widgets.Check(d, setting.label, setting.key, setting.tooltip, 330)
    elseif setting.type == "dropdown" then
        control = Widgets.Dropdown(d, 210, {
            text = function()
                for _, option in ipairs(setting.options or {}) do
                    if ns.Get(setting.key) == (option.value or option[1]) then
                        return option.text or option[2]
                    end
                end
                return ""
            end,
            menu = function(root)
                for _, option in ipairs(setting.options or {}) do
                    local value, text = option.value or option[1], option.text or option[2]
                    root:CreateRadio(text, function() return ns.Get(setting.key) == value end,
                        function() ns.Set(setting.key, value) end)
                end
            end,
        })
        control.label = Widgets.Label(control, setting.label, "GameFontNormal")
        control.label:SetPoint("BOTTOMLEFT", control, "TOPLEFT", 0, 2)
        Widgets.Tooltip(control, setting.label, setting.tooltip)
        return control
    end
end

local function RefreshDialog()
    if not dialog or not EditMode.selected then return end
    local spec = systems[EditMode.selected]
    refreshing = true
    for index, setting in ipairs(spec.settings or {}) do
        local control = dialog.controls[setting.key]
        -- Reinitializing a slider mid-drag interrupts the native interaction.
        if control and index ~= dialog.interacting then
            if control.native then
                local ok = pcall(control.SetupSetting, control, SettingData(setting, index))
                if ok and setting.type == "slider" then control.Label:SetWidth(160) end
                if ok and setting.type == "dropdown" then SetupDropdown(dialog, control, setting, index) end
            elseif control.Refresh then
                control:Refresh()
            end
        end
    end
    refreshing = false
end

local function CreateDialog()
    local d = CreateFrame("Frame", "WaypointTrackerEditModeDialog", UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", ns.Safe(function()
        if not ns.InCombat() then d:StartMoving() end
    end))
    d:SetScript("OnDragStop", ns.Safe(function() d:StopMovingOrSizing() end))
    d:Hide()
    local border = Template("Frame", nil, d, "DialogBorderTranslucentTemplate")
    if not border then
        border = Template("Frame", nil, d, "BackdropTemplate") or CreateFrame("Frame", nil, d)
        if border.SetBackdrop then border:SetBackdrop(Widgets.BACKDROP_DIALOG) end
    end
    d.Border = border
    d.Border:SetAllPoints(d)
    d.Border:SetFrameLevel(d:GetFrameLevel())
    d.title = Widgets.Label(d, "", "GameFontHighlightLarge")
    d.title:SetJustifyH("CENTER")
    d.title:SetPoint("TOP", d, "TOP", 0, -15)
    d.close = Template("Button", nil, d, "UIPanelCloseButton") or Widgets.Button(d, "X", 24, 24)
    d.close:ClearAllPoints()
    d.close:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)
    d.close:SetScript("OnClick", ns.Safe(EditMode.Deselect))
    d.container = CreateFrame("Frame", nil, d)
    d.container:SetPoint("TOPLEFT", 24, -48)
    d.container:SetPoint("TOPRIGHT", -24, -48)
    d.controls, d.rows = {}, {}
    d.hint = Widgets.Label(d, "", "GameFontHighlightSmall")
    d.hint:SetWidth(372)
    d.hint:SetWordWrap(true)
    d.buttons = CreateFrame("Frame", nil, d)
    d.buttons:SetPoint("BOTTOMLEFT", 24, 18)
    d.buttons:SetPoint("BOTTOMRIGHT", -24, 18)
    d.buttons:SetHeight(22)
    d.reset = Widgets.Button(d.buttons, L.RESET_DEFAULT, nil, 22)
    d.reset:SetPoint("LEFT")
    d.reset:SetScript("OnClick", ns.Safe(function()
        local spec = systems[EditMode.selected]
        if spec and spec.onReset then spec.onReset() end
        EditMode.PlaceDialog()
    end))
    function d:OnSettingValueChanged(index, value)
        if refreshing then return end
        local spec = systems[EditMode.selected]
        local setting = spec and spec.settings and spec.settings[index]
        if not setting then return end
        if setting.type == "checkbox" then value = value == true or value == 1 end
        ns.Set(setting.key, value)
    end
    function d:OnSettingInteractStart(index) self.interacting = index end
    function d:OnSettingInteractEnd() self.interacting = nil end
    return d
end

local function BuildDialog(key)
    local spec = systems[key]
    dialog.interacting = nil
    for _, rows in pairs(dialog.rows) do
        for _, control in ipairs(rows) do control:Hide() end
    end
    dialog.controls = {}
    local rows = dialog.rows[key] or {}
    dialog.rows[key] = rows
    dialog.title:SetText(spec.name)
    local y = 0
    for index, setting in ipairs(spec.settings or {}) do
        local control = rows[index] or CreateControl(dialog, setting, index)
        if control then
            rows[index] = control
            dialog.controls[setting.key] = control
            control:ClearAllPoints()
            local offset = not control.native and setting.type == "dropdown" and -18 or 0
            control:SetPoint("TOPLEFT", dialog.container, "TOPLEFT", 0, y + offset)
            if control.native then control:SetWidth(372) end
            control:Show()
            y = y - (setting.type == "checkbox" and 32 or 48)
        end
    end
    dialog.container:SetHeight(math.max(1, -y))
    dialog.hint:ClearAllPoints()
    dialog.hint:SetPoint("TOPLEFT", dialog.container, "TOPLEFT", 0, y - 4)
    dialog.hint:SetText(spec.hint or "")
    dialog.hint:SetShown(spec.hint ~= nil)
    local hintHeight = spec.hint and math.max(24, dialog.hint:GetStringHeight()) + 8 or 0
    dialog:SetSize(420, 48 - y + hintHeight + 60)
    dialog.reset:SetEnabled(spec.onReset ~= nil)
    RefreshDialog()
end

function EditMode.PlaceDialog()
    local spec = systems[EditMode.selected]
    if not dialog or not spec then return end
    local anchor = selections[EditMode.selected] or spec.frame
    dialog:ClearAllPoints()
    local x = anchor:GetCenter() or 0
    if x > ((UIParent:GetWidth() or 0) / 2) then
        dialog:SetPoint("RIGHT", anchor, "LEFT", -24, 0)
    else
        dialog:SetPoint("LEFT", anchor, "RIGHT", 24, 0)
    end
end

local function Highlight(sel, selected)
    local fn = selected and sel.ShowSelected or sel.ShowHighlighted
    if fn then pcall(fn, sel) else sel:Show() end
end

function EditMode.Select(key)
    key = key or "arrow"
    local sel = selections[key]
    if not active or not sel or not sel:IsShown() then return end
    local m = EditModeManagerFrame
    if not ns.InCombat() and m and m.ClearSelectedSystem then pcall(m.ClearSelectedSystem, m) end
    for other, s in pairs(selections) do
        if other ~= key and s:IsShown() then Highlight(s, false) end
    end
    EditMode.selected = key
    Highlight(sel, true)
    dialog = dialog or CreateDialog()
    BuildDialog(key)
    EditMode.PlaceDialog()
    dialog:Show()
end

function EditMode.Deselect()
    for _, sel in pairs(selections) do
        if sel:IsShown() then Highlight(sel, false) end
    end
    EditMode.selected = nil
    if dialog then
        dialog.interacting = nil
        dialog:Hide()
    end
end

-- Positions saved relative to UIParent survive the minimap's scale and anchor.
local function CurrentPoint(f)
    local point, relative, relPoint, x, y = f:GetPoint()
    if not point then return nil end
    if relative == UIParent then return { point, relPoint, x, y } end
    x, y = f:GetCenter()
    if x and y then
        local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return { "CENTER", "BOTTOMLEFT", x * scale, y * scale }
    end
end

local function StopDrag()
    local spec = dragging and systems[dragging]
    local key = dragging
    dragging = nil
    if spec then
        spec.frame:StopMovingOrSizing()
        local pos = CurrentPoint(spec.frame)
        if pos then EditMode.SavePosition(key, pos) end
        EditMode.PlaceDialog()
    end
end

local function CreateSelection(key, spec)
    local name = "WaypointTracker" .. key:gsub("^%l", string.upper) .. "Selection"
    local sel = Template("Frame", name, spec.frame, "EditModeSystemSelectionTemplate")
    if not sel then
        sel = Template("Frame", name, spec.frame, "BackdropTemplate") or CreateFrame("Frame", name, spec.frame)
        if sel.SetBackdrop then
            sel:SetBackdrop(Widgets.BACKDROP_BOX)
            sel:SetBackdropColor(0.1, 0.5, 1, 0.15)
            sel:SetBackdropBorderColor(0.2, 0.7, 1, 1)
        end
        sel.Label = Widgets.Label(sel, spec.name, "GameFontHighlightSmall")
        sel.Label:SetPoint("TOP", 0, -4)
        function sel:ShowHighlighted()
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.2, 0.7, 1, 1) end
            self:Show()
        end
        function sel:ShowSelected()
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(1, 0.82, 0, 1) end
            self:Show()
        end
    end
    sel.system = { GetSystemName = function() return spec.name end }
    sel:EnableMouse(true)
    sel:RegisterForDrag("LeftButton")
    sel:SetScript("OnMouseDown", ns.Safe(function() EditMode.Select(key) end))
    sel:SetScript("OnDragStart", ns.Safe(function()
        if not active or ns.InCombat() then return end
        EditMode.Select(key)
        dragging = key
        spec.frame:StartMoving()
    end))
    sel:SetScript("OnDragStop", ns.Safe(StopDrag))
    sel:Hide()
    return sel
end

local function RefreshSelections()
    if not active then return end
    for key, spec in pairs(systems) do
        local sel = selections[key]
        local insets = spec.selectionInsets
        if type(insets) == "function" then insets = insets() end
        if type(insets) ~= "table" then insets = { 8, 8, 8, 8 } end
        sel:ClearAllPoints()
        sel:SetPoint("TOPLEFT", spec.frame, "TOPLEFT", -(insets[1] or 8), insets[3] or 8)
        sel:SetPoint("BOTTOMRIGHT", spec.frame, "BOTTOMRIGHT", insets[2] or 8, -(insets[4] or 8))
        local show = not spec.shouldShow or spec.shouldShow()
        if show then
            spec.frame:Show()
            Highlight(sel, EditMode.selected == key)
        else
            sel:Hide()
            if EditMode.selected == key then EditMode.Deselect() end
        end
    end
end

-- Specs may also provide onEnter/onExit for previews, onApply for grouping,
-- and a selectionInsets function for bounds that change with settings.
function EditMode.RegisterSystem(spec)
    if not spec or not spec.key or not spec.frame then return end
    systems[spec.key] = spec
    spec.frame:SetMovable(true)
    EditMode.ApplyPosition(spec.key)
    if active then
        spec.wasShown = spec.frame:IsShown()
        if spec.onEnter then spec.onEnter() end
        selections[spec.key] = selections[spec.key] or CreateSelection(spec.key, spec)
        RefreshSelections()
    end
end

function EditMode.OnEnter()
    if active or ns.InCombat() then return end
    active = true
    EditMode.SetLayout(ActiveLayoutName())
    for key, spec in pairs(systems) do
        spec.wasShown = spec.frame:IsShown()
        if spec.onEnter then spec.onEnter() end
        selections[key] = selections[key] or CreateSelection(key, spec)
    end
    RefreshSelections()
end

function EditMode.OnExit()
    StopDrag()
    active = false
    EditMode.Deselect()
    for key, spec in pairs(systems) do
        if selections[key] then selections[key]:Hide() end
        if spec.wasShown ~= nil then spec.frame:SetShown(spec.wasShown) end
        if spec.onExit then spec.onExit() end
    end
end

function EditMode.Enter()
    if ns.InCombat() then return false, "combat" end
    local m = EditModeManagerFrame
    if m and m.EnterEditMode then return pcall(m.EnterEditMode, m) end
    if ns.Arrow and ns.Arrow.SetMoving then
        ns.Arrow.SetMoving(not ns.Arrow.moving)
        return true, "legacy"
    end
    return false, "unavailable"
end

ns.On("LOGIN", function()
    local m = EditModeManagerFrame
    if EventRegistry and EventRegistry.RegisterCallback and m then
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", function() ns.Call(EditMode.OnEnter) end, EditMode)
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", function() ns.Call(EditMode.OnExit) end, EditMode)
        if hooksecurefunc and m.SelectSystem then
            pcall(hooksecurefunc, m, "SelectSystem", EditMode.Deselect)
        end
    end
    EditMode.SetLayout(ActiveLayoutName())
end)

ns.On("SETTING_CHANGED", function(key)
    for system in pairs(systems) do
        if key == nil or key == system .. "Pos" or key == system .. "Layouts" then
            EditMode.ApplyPosition(system)
        end
    end
    RefreshSelections()
    RefreshDialog()
end)

ns.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
    local function Apply() EditMode.SetLayout(ActiveLayoutName()) end
    if C_Timer and C_Timer.After then C_Timer.After(0, ns.Safe(Apply)) else Apply() end
end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", StopDrag)
