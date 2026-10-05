-- EditMode: the arrow in Blizzard's HUD Edit Mode (Esc > Edit Mode).
--
-- While Edit Mode is open the arrow shows up with the same blue box as the
-- game's own frames. Drag it anywhere; click it for its settings (size and
-- visibility of the arrow and of its text, reset). With "Move the text
-- separately" the text gets a box of its own. Changes apply right away, like
-- Blizzard's own frames. Each Edit Mode layout keeps its own spots, so
-- switching layouts moves them too. Outside Edit Mode the arrow keeps
-- ignoring the mouse, so right-click to attack always works.
local _, ns = ...
local L = ns.L

local EditMode = {}
ns.EditMode = EditMode

local selections, dialog = {}, nil

local function Manager()
    return EditModeManagerFrame
end

-- Name of the active Edit Mode layout ("Modern", "Classic", or one the player made).
local function ActiveLayoutName()
    local m = Manager()
    if not (m and m.GetActiveLayoutInfo) then
        return nil
    end
    local ok, info = pcall(m.GetActiveLayoutInfo, m)
    return ok and type(info) == "table" and info.layoutName or nil
end

-- ---------------------------------------------------------------------------
-- The settings panel shown when the arrow or its text is selected
-- ---------------------------------------------------------------------------
local function CreateDialog()
    local w = ns.UI.W
    local d = CreateFrame("Frame", "WaypointTrackerEditModeDialog", UIParent, "BackdropTemplate")
    d:SetSize(280, 330)
    d:SetFrameStrata("DIALOG")
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:SetBackdrop(w.BACKDROP_DIALOG)
    d:Hide()

    local title = d:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText(L.ARROW_EDIT_NAME)

    local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        EditMode.Deselect()
    end)

    w.Slider(d, L.ARROW_SIZE, "arrowScale", 0.5, 2.0, 0.05, 22, -48, 236, w.Percent)
    w.Slider(d, L.ARROW_TRANSPARENCY, "arrowAlpha", 0.2, 1.0, 0.05, 22, -94, 236, w.Percent)
    w.Slider(d, L.TEXT_SIZE, "textScale", 0.5, 2.0, 0.05, 22, -140, 236, w.Percent, L.TEXT_SIZE_DESC)
    w.Slider(d, L.TEXT_VISIBILITY, "textAlpha", 0.2, 1.0, 0.05, 22, -186, 236, w.Percent, L.TEXT_VISIBILITY_DESC)
    w.Check(d, L.TEXT_SEPARATE, "textSeparate", 18, -234, L.TEXT_SEPARATE_DESC, 220)

    local reset = w.Button(d, L.RESET_POSITION, 112, 22)
    reset:SetPoint("BOTTOMLEFT", 22, 18)
    reset:SetScript("OnClick", function()
        ns.Arrow.Reset()
        EditMode.PlaceDialog()
    end)
    w.AddTooltip(reset, L.RESET_POSITION, L.RESET_POSITION_DESC)
    d.reset = reset

    local more = w.Button(d, L.MORE_OPTIONS, 112, 22)
    more:SetPoint("BOTTOMRIGHT", -22, 18)
    more:SetScript("OnClick", function()
        ns.Set("showAdvanced", true)
        ns.UI.Show()
    end)

    d:SetScript("OnShow", function()
        ns.UI.RefreshWidgets()
    end)
    return d
end

-- next to what's selected, on whichever side has room
function EditMode.PlaceDialog()
    if not dialog then
        return
    end
    local anchor = (EditMode.selected == "text" and ns.Arrow.textFrame) or ns.Arrow.frame
    dialog:ClearAllPoints()
    local x = anchor:GetCenter() or 0
    if x > ((UIParent:GetWidth() or 0) / 2) then
        dialog:SetPoint("RIGHT", anchor, "LEFT", -24, 0)
    else
        dialog:SetPoint("LEFT", anchor, "RIGHT", 24, 0)
    end
end

-- ---------------------------------------------------------------------------
-- Selecting and moving
-- ---------------------------------------------------------------------------
-- which: "arrow" or "text"
function EditMode.Select(which)
    which = which or "arrow"
    local sel = selections[which]
    if not sel then
        return
    end
    -- take the selection away from Blizzard's own frames
    local m = Manager()
    if m and m.ClearSelectedSystem then
        pcall(m.ClearSelectedSystem, m)
    end
    for key, s in pairs(selections) do
        if key ~= which and s:IsShown() then
            s:ShowHighlighted()
        end
    end
    EditMode.selected = which
    sel:ShowSelected()
    dialog = dialog or CreateDialog()
    EditMode.PlaceDialog()
    dialog:Show()
end

function EditMode.Deselect()
    for _, s in pairs(selections) do
        if s:IsShown() then
            s:ShowHighlighted()
        end
    end
    EditMode.selected = nil
    if dialog then
        dialog:Hide()
    end
end

-- The arrow's box covers the text too while they're grouped.
local function FitSelections()
    local a, t = selections.arrow, selections.text
    if not a then
        return
    end
    local separate = ns.Arrow.IsTextSeparate()
    a:ClearAllPoints()
    a:SetPoint("TOPLEFT", ns.Arrow.frame, "TOPLEFT", -12, 20)
    a:SetPoint("BOTTOMRIGHT", ns.Arrow.frame, "BOTTOMRIGHT", 12, separate and -12 or -26)
    if t then
        if separate and ns.Arrow.editing then
            t:ShowHighlighted()
        else
            t:Hide()
            if EditMode.selected == "text" then
                EditMode.Select("arrow")
            end
        end
    end
end
EditMode.FitSelections = FitSelections

local function CreateSelection(which, owner, name)
    local ok, sel = pcall(CreateFrame, "Frame", name, owner, "EditModeSystemSelectionTemplate")
    if not ok or not sel then
        return nil
    end
    sel:ClearAllPoints()
    sel:SetPoint("TOPLEFT", owner, "TOPLEFT", -8, 8)
    sel:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 8, -8)
    -- what Blizzard's selection code asks of the frame it belongs to
    sel.system = {
        GetSystemName = function()
            return which == "text" and L.TEXT_EDIT_NAME or L.ARROW_EDIT_NAME
        end,
    }
    sel:SetScript("OnMouseDown", function()
        EditMode.Select(which)
    end)
    sel:SetScript("OnDragStart", function()
        EditMode.Select(which)
        ns.Arrow.StartDrag(which)
    end)
    sel:SetScript("OnDragStop", function()
        ns.Arrow.StopDrag()
        EditMode.PlaceDialog()
    end)
    sel:Hide()
    return sel
end

local function OnEnter()
    ns.Arrow.SetLayout(ActiveLayoutName())
    ns.Arrow.SetEditMode(true)
    selections.arrow = selections.arrow or CreateSelection("arrow", ns.Arrow.frame, "WaypointTrackerArrowSelection")
    selections.text = selections.text or CreateSelection("text", ns.Arrow.textFrame, "WaypointTrackerTextSelection")
    if selections.arrow then
        selections.arrow:ShowHighlighted()
    end
    FitSelections()
end

local function OnExit()
    ns.Arrow.SetEditMode(false)
    for _, s in pairs(selections) do
        s:Hide()
    end
    EditMode.selected = nil
    if dialog then
        dialog:Hide()
    end
end
EditMode.OnEnter, EditMode.OnExit = OnEnter, OnExit

ns.On("LOGIN", function()
    if not (EventRegistry and EventRegistry.RegisterCallback and Manager()) then
        return -- no Edit Mode in this client: the window's Move Arrow still works
    end
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        ns.Call(OnEnter)
    end, EditMode)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        ns.Call(OnExit)
    end, EditMode)
    -- picking one of Blizzard's frames deselects the arrow
    if hooksecurefunc and Manager().SelectSystem then
        hooksecurefunc(Manager(), "SelectSystem", function()
            EditMode.Deselect()
        end)
    end
    ns.Arrow.SetLayout(ActiveLayoutName())
end)

ns.On("SETTING_CHANGED", function(key)
    if key == "textSeparate" or key == nil then
        FitSelections()
    end
end)

-- the layout changed (or finished loading at login): move the arrow with it.
-- Asked from Edit Mode itself once it has handled the event, as the event's
-- own list leaves out the preset layouts.
ns.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
    C_Timer.After(0, function()
        ns.Arrow.SetLayout(ActiveLayoutName())
    end)
end)
