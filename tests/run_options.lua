-- Blizzard Settings proxies and the scrolling canvas fallback.
-- Run from the repository root: lua5.1 tests/run_options.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

-- Missing mock features stay local until P13 integrates them.
local createFrame = CreateFrame
local probe = CreateFrame("Frame")
local needsHeight = probe:GetStringHeight() == nil
local needsEnabled = probe:IsEnabled() == nil
function CreateFrame(...)
    local frame = createFrame(...)
    if needsHeight then
        local createFontString = frame.CreateFontString
        function frame:CreateFontString(...)
            local fs = createFontString(self, ...)
            if not rawget(fs, "GetStringHeight") then
                function fs:GetStringHeight()
                    return math.max(1, math.ceil(self:GetStringWidth() / math.max(1, self:GetWidth()))) * 14
                end
            end
            return fs
        end
    end
    if needsEnabled then
        function frame:SetEnabled(on) self.enabled = on and true or false end
        function frame:IsEnabled() return self.enabled ~= false end
    end
    return frame
end
if not ColorPickerFrame then
    ColorPickerFrame = {
        SetupColorPickerAndShow = function(self, info) self.info = info end,
        GetColorRGB = function() return 0.1, 0.2, 0.3 end,
    }
end
local buttonInitializer = CreateSettingsButtonInitializer
function CreateSettingsButtonInitializer(...)
    local init = buttonInitializer(...)
    if not init.AddShownPredicate then
        function init:AddShownPredicate(fn)
            self.shownPredicates = self.shownPredicates or {}
            table.insert(self.shownPredicates, fn)
        end
    end
    if not init.ShouldShow then
        function init:ShouldShow()
            for _, fn in ipairs(self.shownPredicates or {}) do if not fn() then return false end end
            return true
        end
    end
    return init
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- DESIGN §5.5: General 9 + Arrow 16 + Maps 8 + Routes 10 + Treasure 7 + Find/Sharing 4 = 54.
local keys = {
    root = { "arrowShown", "autoClosest", "corpseWaypoint", "persist", "minimapButton", "chatMessages", "useMetres", "addonWaypoints", "blizzardPin" },
    arrow = { "arrowScale", "arrowAlpha", "colorMode", "fadeOnCourse", "hideInCombat", "hideOnTaxi", "textScale", "textAlpha", "showTitle", "showDistance", "showETA", "textSeparate", "arrivalDistance", "autoClear", "arrivalSound", "autoNext" },
    maps = { "worldPins", "worldCoords", "mapClick", "followMapPins", "followQuest", "minimapPins", "minimapEdge", "coordsBox" },
    routes = { "routeApply", "routeSharing", "routeLowRated", "realRoutes", "travelFlights", "travelBoats", "travelHearth", "travelMapLine", "travelTrails", "travelShare" },
    treasure = { "treasureHunt", "treasureChests", "treasureRares", "treasureOther", "treasureKnownSpots", "treasurePing", "treasureFocus" },
    find = { "learn", "findFaction", "findThisZone", "sharePrefix" },
}

local registrations = {}
-- Forever stores a category on SettingsPanel, without this mock-only constant.
-- Leave the category unregistered until after addon login to exercise lazy lookup.
local bindingsConstant = Settings.KEYBINDINGS_CATEGORY_ID
Settings.KEYBINDINGS_CATEGORY_ID = nil
SettingsPanel.keybindingsCategory = nil
local register = Settings.RegisterAddOnCategory
Settings.RegisterAddOnCategory = function(cat)
    registrations[cat] = #M.settingsControls
    return register(cat)
end
WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
local O, L = ns.Options, ns.L
check(O.IsAvailable() and O.categoryID ~= nil, "native category is available after login")
check(#M.settingsControls == 54 and count(M.settings) == 54, "all 54 settings have one native control")
local category = M.settings.WAYPOINTTRACKER_arrowShown.cat
check(category:GetID() == O.categoryID and #category.subcategories == 5, "root has five subcategories")
check(registrations[category] == 54, "root registered after every control was added")
for sub, list in pairs(keys) do
    for _, key in ipairs(list) do
        local setting = M.settings["WAYPOINTTRACKER_" .. key]
        check(setting and setting.cat == (sub == "root" and category or O.categories[sub])
            and setting.name and setting.default == ns.defaults[key], "proxy belongs to the right category: " .. key)
    end
end
M.settings.WAYPOINTTRACKER_arrowShown:SetValue(false)
check(ns.Get("arrowShown") == false, "proxy checkbox writes the addon setting")
M.settingsNotified = {}
ns.Set("arrowShown", true)
check(M.settingsNotified.WAYPOINTTRACKER_arrowShown, "addon setting changes notify Blizzard")
M.settings.WAYPOINTTRACKER_arrowScale:SetValue(1.5)
check(ns.Get("arrowScale") == 1.5, "number proxy writes the addon setting")
M.settings.WAYPOINTTRACKER_routeApply:SetValue("add")
check(ns.Get("routeApply") == "add", "string proxy writes the addon setting")

local controls = {}
for _, init in ipairs(M.settingsControls) do controls[init.setting.variable] = init end
for key, tooltip in pairs({
    arrowShown = L.SHOW_ARROW_DESC, arrowScale = L.ARROW_SIZE_DESC,
    arrowAlpha = L.ARROW_TRANSPARENCY_DESC, routeLowRated = L.ROUTES_LOW_RATED_DESC,
}) do
    local init = controls["WAYPOINTTRACKER_" .. key]
    check(init.tooltip == tooltip and init.tooltip ~= init.setting.name, "descriptive Settings tooltip: " .. key)
end
local size = controls.WAYPOINTTRACKER_arrowScale
check(size.options.min == 0.5 and size.options.max == 2 and size.options.step == 0.05
    and size.options.formatters[MinimalSliderWithSteppersMixin.Label.Right](1.5) == "150%", "slider range and percentage formatter")
local arrival = controls.WAYPOINTTRACKER_arrivalDistance
check(arrival.options.min == 3 and arrival.options.max == 50 and arrival.options.step == 1, "arrival slider range")
local choices = controls.WAYPOINTTRACKER_routeApply.options()
check(#choices == 3 and choices[1].value == "ask" and choices[2].value == "replace" and choices[3].value == "add", "route dropdown has all three choices")
for _, key in ipairs(keys.treasure) do
    if key ~= "treasureHunt" then
        local child = controls["WAYPOINTTRACKER_" .. key]
        check(child.parentInitializer == controls.WAYPOINTTRACKER_treasureHunt and not child.parentPredicate(), "treasure child depends on hunt: " .. key)
    end
end
ns.Set("treasureHunt", true)
check(controls.WAYPOINTTRACKER_treasureChests.parentPredicate(), "treasure children enable immediately")

local function button(cat, text)
    for _, init in ipairs(M.settingsLayouts[cat].initializers) do
        if init.kind == "button" and init.text == text then return init end
    end
end
local open = button(category, L.OPEN_WINDOW)
check(open and open.name == L.OPEN_WINDOW
    and open.tooltip == L.OPTIONS_PANEL_DESC .. "\n\n" .. L.VERSION_FMT:format(ns.version),
    "Open row uses a short name with description and version in its tooltip")
local bindingsButton = button(category, L.OPEN_KEYBINDINGS)
check(bindingsButton and bindingsButton.name == L.OPEN_KEYBINDINGS
    and bindingsButton.tooltip == L.OPEN_KEYBINDINGS_DESC, "Key Bindings row exists before Blizzard registers its category")
local editButton = button(category, L.OPEN_EDIT_MODE_BUTTON)
check(editButton and editButton.name == L.OPEN_EDIT_MODE and editButton.tooltip == L.OPEN_EDIT_MODE_DESC,
    "Edit Mode row has a separate Open Edit Mode button label")
O.Open("routes")
check(M.settingsOpened == O.categories.routes:GetID(), "Open routes selects the subcategory")
O.Open("unknown")
check(M.settingsOpened == O.categoryID, "unknown subcategory opens root")
local oldOpened, oldCalls = M.settingsOpened, M.uiPanelCalls.hide
M.player.combat = true
O.Open("routes")
open.click()
bindingsButton.click()
editButton.click()
check(M.settingsOpened == oldOpened and M.uiPanelCalls.hide == oldCalls and not M.actionBlocked, "combat skips protected calls for all navigation")
check(M.printed[#M.printed]:find(L.IN_COMBAT_NO_PANELS, 1, true), "combat refusal is printed")
M.player.combat = false
local shown = 0
local windowShow = ns.Window.Show
ns.Window.Show = function() shown = shown + 1 end
SettingsPanel:Show()
open.click()
check(shown == 1 and not SettingsPanel:IsShown(), "Open closes Settings and opens the window")
local hidePanel = HideUIPanel
HideUIPanel = nil
SettingsPanel:Show()
open.click()
check(shown == 2 and not SettingsPanel:IsShown(), "Open still closes Settings without HideUIPanel")
HideUIPanel = hidePanel
local beforeBindings = M.settingsOpened
bindingsButton.click()
check(M.settingsOpened == beforeBindings, "unregistered bindings category safely does nothing")
local bindingsCategory = { ID = 901 }
function bindingsCategory:GetID() return self.ID end
SettingsPanel.keybindingsCategory = bindingsCategory
bindingsButton.click()
check(M.settingsOpened == 901, "Key Bindings resolves Blizzard category registered after addon login")
bindingsCategory.ID = 902
bindingsButton.click()
check(M.settingsOpened == 902, "Key Bindings resolves the current category on every click")
M.player.combat = true
bindingsCategory.ID = 903
bindingsButton.click()
check(M.settingsOpened == 902, "combat blocks the real Blizzard bindings-category path")
M.player.combat = false
Settings.KEYBINDINGS_CATEGORY_ID = bindingsConstant
bindingsButton.click()
check(M.settingsOpened == bindingsConstant, "clients exposing a bindings constant remain supported")
Settings.KEYBINDINGS_CATEGORY_ID = nil
SettingsPanel.keybindingsCategory = { GetID = function() error("category unavailable") end }
bindingsButton.click()
check(M.settingsOpened == bindingsConstant, "bindings-category lookup failure is contained")
SettingsPanel.keybindingsCategory = {}
bindingsButton.click()
check(M.settingsOpened == bindingsConstant, "bindings category without GetID is tolerated")
SettingsPanel.keybindingsCategory = bindingsCategory
local openCategory = Settings.OpenToCategory
Settings.OpenToCategory = nil
bindingsButton.click()
check(M.settingsOpened == bindingsConstant, "missing OpenToCategory is tolerated by the bindings button")
Settings.OpenToCategory = function() error("category unavailable") end
bindingsButton.click()
check(M.settingsOpened == bindingsConstant, "bindings navigation failure is contained")
Settings.OpenToCategory = openCategory
local oldEditMode, entered = ns.EditMode, 0
ns.EditMode = { Enter = function() entered = entered + 1; return true end }
editButton.click()
check(entered == 1, "Edit Mode button calls sibling API")
ns.EditMode = { Enter = function() return false, "combat" end }
editButton.click()
check(M.printed[#M.printed]:find(L.IN_COMBAT_NO_PANELS, 1, true), "Edit Mode failure reason is respected")
ns.EditMode = oldEditMode
local pick = button(O.categories.arrow, L.PICK_COLOUR)
check(pick and pick.parentInitializer == controls.WAYPOINTTRACKER_colorMode and not pick.parentPredicate()
    and not pick:ShouldShow(), "Pick colour is hidden unless colour is single")
ns.Set("colorMode", "single")
check(pick.parentPredicate() and pick:ShouldShow(), "Pick colour appears for single colour")
local prev = ns.Get("singleColor")
pick.click()
ColorPickerFrame.info.swatchFunc()
check(ns.Get("singleColor").r == 0.1 and ns.Get("singleColor").b == 0.3, "picker updates colour")
ColorPickerFrame.info.cancelFunc()
check(ns.Get("singleColor").r == prev.r and ns.Get("singleColor").g == prev.g, "picker cancellation restores colour")
local reset = button(category, L.RESET_SETTINGS)
check(reset and reset.name == L.RESET_SETTINGS and reset.tooltip == L.RESET_SETTINGS_DESC,
    "Reset row uses a short name with the description in its tooltip")
M.autoCancelPopup = true
reset.click()
check(M.lastPopup == "WAYPOINTTRACKER_RESET" and ns.Get("arrowScale") == 1.5, "cancel reset keeps settings")
M.autoCancelPopup, M.autoAcceptPopup = false, true
M.settingsNotified = {}
reset.click()
check(ns.Get("arrowScale") == ns.defaults.arrowScale and ns.Get("routeApply") == "ask", "confirmed reset restores defaults")
check(count(M.settingsNotified) == 54, "reset notifies every registered proxy")
M.autoAcceptPopup = false
local countBefore = #M.settingsControls
ns.Fire("LOGIN")
check(#M.settingsControls == countBefore, "repeated login does not duplicate registration")
Settings.OpenToCategory = function() error("category unavailable") end
O.Open()
check(shown == 3 and M.printed[#M.printed]:find(L.SETTINGS_UNAVAILABLE, 1, true), "opening failure falls back to window")
Settings.OpenToCategory = function(id) M.settingsOpened = id end
ns.Window.Show = windowShow

local function isolated()
    local testNS = {}
    for _, file in ipairs({ "Locales/enUS", "Core", "Geo", "Widgets", "Options" }) do
        assert(loadfile("WaypointTracker/" .. file .. ".lua"))("WaypointTracker", testNS)
    end
    WaypointTrackerDB, WaypointTrackerCharDB = nil, nil
    testNS.eventFrame:RunScript("OnEvent", "ADDON_LOADED", "WaypointTracker")
    testNS.Fire("LOGIN")
    return testNS
end
local vertical = Settings.RegisterVerticalLayoutCategory
Settings.RegisterVerticalLayoutCategory = nil
local fallback = isolated()
local canvas = fallback.Options.canvas
check(canvas and M.settingsCategory.frame == canvas and fallback.Options.IsAvailable(), "canvas fallback registers with Blizzard")
check(canvas and canvas.scroll._template == "UIPanelScrollFrameTemplate" and count(canvas.controls) == 54, "canvas has the same 54 controls in a scroll frame")
canvas:Show()
local function canvasButton(text)
    for _, frame in ipairs(M.frames) do
        local b = rawget(frame, "button")
        if frame:GetParent() == canvas.content and b and b:GetText() == text then return b end
    end
end
local canvasOpen = canvasButton(fallback.L.OPEN_WINDOW)
M.tooltip = {}
canvasOpen:RunScript("OnEnter")
check(M.tooltip[#M.tooltip] == fallback.L.OPTIONS_PANEL_DESC .. "\n\n" .. fallback.L.VERSION_FMT:format(fallback.version),
    "canvas Open tooltip includes description and version")
for key, tooltip in pairs({
    arrowShown = fallback.L.SHOW_ARROW_DESC, arrowScale = fallback.L.ARROW_SIZE_DESC,
    arrowAlpha = fallback.L.ARROW_TRANSPARENCY_DESC, routeLowRated = fallback.L.ROUTES_LOW_RATED_DESC,
}) do
    M.tooltip = {}
    local widget = canvas.controls[key]
    widget = rawget(widget, "slider") or widget
    widget:RunScript("OnEnter")
    check(M.tooltip[#M.tooltip] == tooltip, "canvas uses descriptive tooltip: " .. key)
end
check(canvasButton(fallback.L.OPEN_EDIT_MODE_BUTTON), "canvas also uses Open Edit Mode button text")
SettingsPanel.keybindingsCategory = nil
local canvasBindings = canvasButton(fallback.L.OPEN_KEYBINDINGS)
check(canvasBindings, "canvas Key Bindings row exists before category registration")
SettingsPanel.keybindingsCategory = bindingsCategory
canvasBindings:Click()
check(M.settingsOpened == bindingsCategory:GetID(), "canvas Key Bindings uses Blizzard category registered later")
canvas.scroll:SetSize(560, 420)
canvas.scroll:RunScript("OnSizeChanged")
check(canvas.content:GetHeight() > 420 and canvas.content:GetWidth() == 560, "canvas sizes content for scrolling")
canvas.scroll:SetSize(260, 420)
canvas.scroll:RunScript("OnSizeChanged")
check(canvas.controls.routeApply.dropdown:GetWidth() <= 260
    and canvas.controls.routeApply.dropdown:GetPoint() == "TOPLEFT", "canvas dropdown fits a narrow panel")
canvas.scroll:SetSize(560, 420)
canvas.scroll:RunScript("OnSizeChanged")
canvas.controls.arrowShown:Click()
check(fallback.Get("arrowShown") == false, "canvas checkbox writes setting")
fallback.Set("arrowShown", true)
check(canvas.controls.arrowShown:GetChecked(), "canvas checkbox follows external changes")
canvas.controls.arrowScale.slider:SetValue(1.4)
check(math.abs(fallback.Get("arrowScale") - 1.4) < 0.001, "canvas slider writes setting")
check(not canvas.controls.treasureChests:IsEnabled(), "canvas treasure child disabled initially")
fallback.Set("treasureHunt", true)
check(canvas.controls.treasureChests:IsEnabled(), "canvas treasure child enables when hunt starts")
canvas.controls.routeApply.dropdown:GenerateMenu()
M.lastMenu.items[3].fn()
check(fallback.Get("routeApply") == "add", "canvas dropdown writes setting")
fallback.Options.Open("routes")
check(M.settingsOpened == fallback.Options.categoryID, "canvas subcategory opens its root")
local canvasHeight = canvas.content:GetHeight()
fallback.Set("colorMode", "single")
check(canvas.content:GetHeight() > canvasHeight, "canvas relayouts when Pick colour appears")
Settings.RegisterVerticalLayoutCategory = vertical

-- Losing other native APIs also uses the complete canvas, without a partial root.
local checkbox = Settings.CreateCheckbox
Settings.CreateCheckbox = nil
local partial = isolated()
check(partial.Options.canvas and count(partial.Options.canvas.controls) == 54, "partial Settings API uses canvas")
Settings.CreateCheckbox = checkbox
local header = CreateSettingsListSectionHeaderInitializer
CreateSettingsListSectionHeaderInitializer = nil
local missingInitializer = isolated()
check(missingInitializer.Options.canvas and count(missingInitializer.Options.canvas.controls) == 54, "missing native initializer uses full canvas")
CreateSettingsListSectionHeaderInitializer = header
local mixin = MinimalSliderWithSteppersMixin
MinimalSliderWithSteppersMixin = nil
local missingFormatter = isolated()
check(missingFormatter.Options.IsAvailable() and not missingFormatter.Options.canvas, "native sliders tolerate missing label formatter enum")
MinimalSliderWithSteppersMixin = mixin

local getLayout = SettingsPanel.GetLayout
SettingsPanel.GetLayout = nil
local registerInitializer = Settings.RegisterInitializer
local alternativeCount = 0
if not Settings.RegisterInitializer then
    Settings.RegisterInitializer = function(cat, init)
        local layout = getLayout(SettingsPanel, cat)
        layout:AddInitializer(init)
    end
end
local alternativeRegister = Settings.RegisterInitializer
Settings.RegisterInitializer = function(cat, init)
    alternativeCount = alternativeCount + 1
    return alternativeRegister(cat, init)
end
local alternative = isolated()
check(alternative.Options.IsAvailable() and not alternative.Options.canvas and alternativeCount > 0,
    "headers and buttons use RegisterInitializer when GetLayout is absent")
SettingsPanel.GetLayout, Settings.RegisterInitializer = getLayout, registerInitializer
local picker, bindings = ColorPickerFrame, Settings.KEYBINDINGS_CATEGORY_ID
ColorPickerFrame, Settings.KEYBINDINGS_CATEGORY_ID = nil, nil
local minimal = isolated()
local minimalRoot = M.settings.WAYPOINTTRACKER_arrowShown.cat
check(button(minimalRoot, L.OPEN_KEYBINDINGS) and not button(minimal.Options.categories.arrow, L.PICK_COLOUR),
    "Key Bindings remains available without a constant while an unsupported colour picker is omitted")
ColorPickerFrame, Settings.KEYBINDINGS_CATEGORY_ID = picker, bindings

Settings.RegisterVerticalLayoutCategory = nil
local frameFactory = CreateFrame
CreateFrame = function(kind, name, parent, template)
    if template == "WowStyle1DropdownTemplate" or template == "UIPanelScrollFrameTemplate" then
        error("missing optional template: " .. template)
    end
    return frameFactory(kind, name, parent, template)
end
local missingTemplates = isolated()
local legacyCanvas = missingTemplates.Options.canvas
check(legacyCanvas and legacyCanvas.scroll._template == nil and count(legacyCanvas.controls) == 54,
    "missing optional templates keep the full canvas")
legacyCanvas.controls.routeApply.dropdown.next:Click()
check(missingTemplates.Get("routeApply") == "replace", "canvas dropdown template fallback sets the next choice")
CreateFrame, Settings.RegisterVerticalLayoutCategory = frameFactory, vertical

local settings, panel = Settings, SettingsPanel
Settings, SettingsPanel = nil, nil
local bare = isolated()
local bareShown = 0
bare.Window = { Show = function() bareShown = bareShown + 1 end }
bare.Options.Open()
check(not bare.Options.IsAvailable() and bareShown == 1 and M.printed[#M.printed]:find(L.SETTINGS_UNAVAILABLE, 1, true), "missing Settings opens window with explanation")
M.player.combat = true
bare.Options.Open()
check(bareShown == 1 and M.printed[#M.printed]:find(L.IN_COMBAT_NO_PANELS, 1, true), "missing Settings still refuses during combat")
M.player.combat = false
Settings, SettingsPanel = settings, panel

check(#M.errors == 0, "no reported Lua errors: " .. tostring(M.errors[1]))
print(("%d passed, %d failed"):format(passed, failed))
os.exit((failed == 0 and #M.errors == 0) and 0 or 1)
