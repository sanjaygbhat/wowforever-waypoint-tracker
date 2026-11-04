-- Tests the mock's native UI surface without loading the addon. Run from
-- the repository root: lua5.1 tests/run_mock_selftest.lua
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

-- Template children and methods also work in a comma-separated template list.
for _, template in ipairs({ "ButtonFrameTemplate,BackdropTemplate", "PortraitFrameTemplate" }) do
    local f = CreateFrame("Frame", nil, UIParent, template)
    check(f.TitleText == f.TitleContainer.TitleText, template .. " title alias")
    check(f.CloseButton:IsObjectType("Button") and f.Inset:IsObjectType("Frame"), template .. " children")
    check(f.Bg:IsObjectType("Texture") and f.portrait == f.PortraitContainer.portrait, template .. " portrait alias")
    f:SetTitle("Window title")
    f:SetPortraitToAsset("Icon")
    check(f.TitleText:GetText() == "Window title" and f.portrait:GetTexture() == "Icon", template .. " setters")
    f:SetPortraitTextureRaw("Raw icon")
    check(f.portrait:GetTexture() == "Raw icon", template .. " raw portrait")
    ButtonFrameTemplate_HideAttic(f)
    ButtonFrameTemplate_ShowButtonBar(f)
    ButtonFrameTemplate_HidePortrait(f)
end
local panel = CreateFrame("Frame", "MockSelftestPanel", UIParent)
local tab = CreateFrame("Button", nil, panel, "PanelTabButtonTemplate")
tab:SetID(2)
tab:SetText("Find")
check(tab:GetID() == 2 and tab:GetTextWidth() > 0, "tab ID and text width")
check(tab.Left:GetWidth() > 0 and tab.Middle:GetWidth() > 0 and tab.Right:GetWidth() > 0, "tab region widths")
PanelTemplates_SetNumTabs(panel, 3)
PanelTemplates_SetTab(panel, 2)
check(panel.numTabs == 3 and panel.selectedTab == 2 and PanelTemplates_GetSelectedTab(panel) == 2, "tab selection")
PanelTemplates_TabResize(tab, 4)
check(tab:GetWidth() >= tab:GetTextWidth() + 4, "tab resize")
PanelTemplates_UpdateTabs(panel)
PanelTemplates_DeselectTab(tab)
PanelTemplates_SelectTab(tab)

for _, template in ipairs({ "SearchBoxTemplate", "InputBoxInstructionsTemplate", "InputBoxTemplate" }) do
    local edit = CreateFrame("EditBox", nil, panel, template)
    check(edit:IsObjectType("EditBox"), template .. " edit box")
    if template == "InputBoxTemplate" then
        check(rawget(edit, "Instructions") == nil, "plain input has no instructions")
    else
        check(edit.Instructions:IsObjectType("FontString"), template .. " instructions")
    end
    if template == "SearchBoxTemplate" then
        check(edit.clearButton:IsObjectType("Button") and edit.searchIcon:IsObjectType("Texture"), "search controls")
        edit:SetFocus()
        check(edit.clearButton:IsShown(), "focused search shows the clear button")
        edit:SetText("query")
        edit.clearButton:Click()
        check(edit:GetText() == "" and not edit:HasFocus() and not edit.clearButton:IsShown()
            and edit.Instructions:IsShown(), "clearing search restores instructions and releases focus")
    else
        check(rawget(edit, "clearButton") == nil and rawget(edit, "searchIcon") == nil, template .. " has no search controls")
    end
    local typed
    edit:SetScript("OnTextChanged", function(_, userInput) typed = userInput end)
    edit:Type("Search")
    check(edit:GetText() == "Search" and typed == true, template .. " text script")
end
local area = CreateFrame("ScrollFrame", nil, panel, "InputScrollFrameTemplate")
check(area.EditBox:IsObjectType("EditBox") and area.EditBox:IsMultiLine(), "text area edit box")
check(area.ScrollBar:IsObjectType("Slider") and area._child == area.EditBox, "text area scrollbar and child")
area.EditBox:SetMultiLine(true)
InputScrollFrame_SetInstructions(area, "Paste here")
check(area.EditBox.Instructions:GetText() == "Paste here", "text area instructions")
for _, template in ipairs({ "MagicButtonTemplate", "UIPanelButtonTemplate" }) do
    check(CreateFrame("Button", nil, panel, template):IsObjectType("Button"), template .. " button")
end
check(CreateFrame("Frame", nil, panel, "DialogBorderTranslucentTemplate"):IsObjectType("Frame"), "dialog border")

-- Menus preserve the old Share.lua title/text/fn shape and support submenus.
local clicked, selected = 0, false
local menu = MenuUtil.CreateContextMenu(panel, function(owner, root)
    check(owner == panel, "menu owner passed to generator")
    local title = root:CreateTitle("Share")
    title:SetTooltip(function() end)
    title:SetEnabled(true)
    title:AddInitializer(function() end)
    root:CreateButton("Post", function() clicked = clicked + 1 end)
    root:CreateCheckbox("On", function() return selected end, function() selected = not selected end)
    root:CreateRadio("Choice", function() return selected end, function() selected = true end)
    root:CreateDivider()
    root:CreateSpacer()
    root:CreateButton("Submenu"):CreateButton("Nested", function() clicked = clicked + 1 end)
end)
check(M.lastMenu == menu and M.menus[#M.menus] == menu and #menu.items == 7, "menu recordings")
check(menu.items[1].title == "Share" and menu.items[2].text == "Post", "legacy menu shape")
menu.items[2].fn()
check(clicked == 1, "menu action callable")
menu.items[3].setSelected()
check(menu.items[3].kind == "checkbox" and menu.items[3].isSelected(), "checkbox menu callbacks")
selected = false
menu.items[4].fn()
check(menu.items[4].kind == "radio" and menu.items[4].isSelected(), "radio menu callbacks")
check(menu.items[5].kind == "divider" and menu.items[6].kind == "spacer", "menu separators")
menu.items[7].items[1].fn()
check(clicked == 2, "submenu action callable")

local dd = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
dd:SetDefaultText("Default")
check(dd:GetText() == "Default", "dropdown default text")
dd:OverrideText("Override")
check(dd:GetText() == "Override", "dropdown override text")
dd:SetText("Text")
check(dd:GetText() == "Text", "dropdown text")
local generated = 0
dd:SetupMenu(function(owner, root)
    check(owner == dd, "dropdown generator owner")
    generated = generated + 1
    root:CreateButton("Select", function() dd:SetText("Selected") end)
end)
check(generated == 0, "dropdown setup stores generator")
local ddRoot = dd:GenerateMenu()
check(generated == 1 and dd.lastRoot == ddRoot and M.lastMenu == ddRoot, "dropdown records generated menu")
ddRoot.items[1].fn()
check(dd:GetText() == "Selected", "dropdown action")

local valueSetting, valueChanged
function panel:OnSettingValueChanged(setting, value)
    valueSetting, valueChanged = setting, value
end
local slider = CreateFrame("Frame", nil, panel, "EditModeSettingSliderTemplate")
local sliderData = { settingName = "Scale", currentValue = 1,
    displayInfo = { setting = 1, type = Enum.EditModeSettingDisplayType.Slider,
        minValue = 0.5, maxValue = 2, stepSize = 0.05, formatter = tostring } }
slider:SetupSetting(sliderData)
check(slider.data == sliderData and slider.Label:GetText() == "Scale", "edit slider setup")
check(slider.Slider:GetValue() == 1, "edit slider initial value")
local callbackOwner, callbackValue
slider.Slider:RegisterCallback("OnValueChanged", function(owner, value)
    callbackOwner, callbackValue = owner, value
end, panel)
slider.Slider:SetValue(1.5)
check(callbackOwner == panel and callbackValue == 1.5, "edit slider registered callback")
check(valueSetting == 1 and valueChanged == 1.5 and slider.Slider:GetValue() == 1.5, "edit slider parent callback")
slider.Slider:Init(0.8, 0.5, 2, 30, { tostring })
local lo, hi = slider.Slider:GetMinMaxValues()
check(slider.Slider:GetValue() == 0.8 and lo == 0.5 and hi == 2 and slider.Slider.steps == 30, "slider Init")

local cb = CreateFrame("Frame", nil, panel, "EditModeSettingCheckboxTemplate")
local cbData = { settingName = "Separate text", currentValue = 1, displayInfo = { setting = 2 } }
cb:SetupSetting(cbData)
check(cb.data == cbData and cb.Label:GetText() == "Separate text" and cb.Button:GetChecked(), "edit checkbox setup")
cb.Button:Click()
check(valueSetting == 2 and valueChanged == 0, "edit checkbox parent callback")
local editDD = CreateFrame("Frame", nil, panel, "EditModeSettingDropdownTemplate")
local editDDData = { settingName = "Colour", currentValue = "gold", displayInfo = { setting = 3,
    options = { { value = "gold", text = "Gold" }, { value = "green", text = "Green" } } } }
editDD:SetupSetting(editDDData)
check(editDD.data == editDDData and editDD.Label:GetText() == "Colour", "edit dropdown setup")
local editRoot = editDD.Dropdown:GenerateMenu()
check(editRoot.items[1].isSelected() and not editRoot.items[2].isSelected(), "edit dropdown initial selection")
editRoot.items[2].fn()
check(valueSetting == 3 and valueChanged == "green" and editRoot.items[2].isSelected(), "edit dropdown parent callback")
local selection = CreateFrame("Frame", nil, panel, "EditModeSystemSelectionTemplate")
check(selection.Label:IsObjectType("FontString"), "selection label")
selection:ShowSelected()
check(selection.isSelected and selection:IsShown(), "existing selected behavior")
selection:ShowHighlighted()
check(not selection.isSelected and selection:IsShown(), "existing highlighted behavior")

local attrs = { area = "left", width = 640 }
RegisterUIPanel(panel, attrs)
check(UIPanelWindows.MockSelftestPanel == attrs, "UI panel registration by name")
panel:Hide()
ShowUIPanel(panel)
check(panel:IsShown() and M.uiPanelCalls.show == 1, "UI panel show")
HideUIPanel(panel)
check(not panel:IsShown() and M.uiPanelCalls.hide == 1, "UI panel hide")
M.player.combat = true
check(InCombatLockdown(), "combat flag")
ShowUIPanel(panel)
check(not panel:IsShown() and M.uiPanelCalls.show == 2 and M.actionBlocked == 1, "show blocked in combat")
panel:Show()
HideUIPanel(panel)
check(panel:IsShown() and M.uiPanelCalls.hide == 2 and M.actionBlocked == 2, "hide blocked in combat")
M.player.combat = false
ToggleFrame(panel)
check(not panel:IsShown(), "ToggleFrame hides")
ToggleFrame(panel)
check(panel:IsShown(), "ToggleFrame shows")
check(type(UISpecialFrames) == "table", "special frames remain available")

local canvas = Settings.RegisterCanvasLayoutCategory(panel, "Canvas")
check(M.settingsCategory == canvas and canvas.frame == panel and canvas.name == "Canvas", "existing canvas registration")
local cat = Settings.RegisterVerticalLayoutCategory("Addon")
local sub = Settings.RegisterVerticalLayoutSubcategory(cat, "Routes")
Settings.RegisterAddOnCategory(cat)
check(cat:GetID() == cat.ID and sub:GetID() ~= cat:GetID() and cat.subcategories[1] == sub, "settings categories")
check(Settings.VarType.Boolean == "boolean" and Settings.VarType.Number == "number" and Settings.VarType.String == "string", "settings value types")
check(Settings.KEYBINDINGS_CATEGORY_ID == 1, "keybindings category")
local proxyValue = true
local proxy = Settings.RegisterProxySetting(cat, "MOCK_BOOL", Settings.VarType.Boolean, "Show arrow", true,
    function() return proxyValue end, function(v) proxyValue = v end)
check(M.settings.MOCK_BOOL == proxy and proxy.variable == "MOCK_BOOL" and proxy:GetValue(), "proxy registration")
local changedSetting, changedValue
proxy:SetValueChangedCallback(function(setting, value) changedSetting, changedValue = setting, value end)
proxy:SetValue(false)
check(proxyValue == false and proxy:GetValue() == false and changedSetting == proxy and changedValue == false, "proxy setter and callback")
check(Settings.GetSetting("MOCK_BOOL") == proxy and Settings.GetSetting("MISSING") == nil, "setting lookup")
local options = Settings.CreateSliderOptions(0.5, 2, 0.05)
options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, tostring)
check(options.min == 0.5 and options.max == 2 and options.step == 0.05 and options.formatters[2](1) == "1", "slider options")
local container = Settings.CreateControlTextContainer()
container:Add("gold", "Gold", "Tooltip")
check(container:GetData()[1].value == "gold" and container:GetData()[1].text == "Gold", "dropdown options container")
local checkbox = Settings.CreateCheckbox(cat, proxy, "Tip")
local settingsSlider = Settings.CreateSlider(cat, proxy, options, "Slider tip")
local settingsDD = Settings.CreateDropdown(sub, proxy, function() return container:GetData() end, "Dropdown tip")
local swatch = Settings.CreateColorSwatch(cat, proxy, "Colour tip")
check(#M.settingsControls == 4 and checkbox.kind == "checkbox" and settingsSlider.kind == "slider", "checkbox and slider recording")
check(settingsDD.kind == "dropdown" and swatch.kind == "colorSwatch", "dropdown and swatch recording")
check(settingsSlider.cat == cat and settingsSlider.setting == proxy and settingsSlider.options == options, "control arguments recorded")
check(settingsDD.cat == sub and settingsDD.options()[1].value == "gold", "dropdown options preserved")
Settings.OpenToCategory(sub:GetID())
Settings.NotifyUpdate("MOCK_BOOL")
check(M.settingsOpened == sub.ID and M.settingsNotified.MOCK_BOOL, "settings open and notification")
local layout = SettingsPanel:GetLayout(cat)
local header = CreateSettingsListSectionHeaderInitializer("General")
local button = CreateSettingsButtonInitializer("Open addon", "Open", function() clicked = clicked + 1 end, "Open tip", true)
local predicate = function() return proxy:GetValue() end
button:SetParentInitializer(checkbox, predicate)
button:AddSearchTags("addon", "waypoint")
layout:AddInitializer(header)
layout:AddInitializer(button)
check(M.settingsLayouts[cat] == layout and SettingsPanel:GetLayout(cat) == layout and #layout.initializers == 2, "settings layout recording")
check(header.kind == "header" and header.name == "General" and button.kind == "button" and button.text == "Open", "settings initializers")
check(button.parentInitializer == checkbox and button.parentPredicate == predicate and #button.searchTags == 2, "initializer parenting and search tags")
button.click()
check(clicked == 3, "settings button callback")
SettingsPanel:Show()
check(SettingsPanel:IsShown(), "settings panel visibility")
SettingsPanel:Close()
check(not SettingsPanel:IsShown(), "settings panel close")

local popupData, receivedFrame, receivedData, action = {}, nil, nil, nil
StaticPopupDialogs.MOCK_POPUP = {
    OnAccept = function(frame, data) receivedFrame, receivedData, action = frame, data, "accept" end,
    OnAlt = function(frame, data) receivedFrame, receivedData, action = frame, data, "alt" end,
    OnCancel = function(frame, data) receivedFrame, receivedData, action = frame, data, "cancel" end,
}
local popup = StaticPopup_Show("MOCK_POPUP", "Name", 7, popupData)
check(M.lastPopup == "MOCK_POPUP" and M.lastPopupArgs[1] == "Name" and M.lastPopupArgs[2] == 7 and M.lastPopupArgs[3] == popupData, "popup arguments recorded")
check(StaticPopup_Visible("MOCK_POPUP") and popup.data == popupData and popup.which == "MOCK_POPUP", "popup visibility and data")
StaticPopup_Hide("MOCK_POPUP")
check(not StaticPopup_Visible("MOCK_POPUP"), "popup hide")
for _, choice in ipairs({ { "autoAcceptPopup", "accept" }, { "autoAltPopup", "alt" }, { "autoCancelPopup", "cancel" } }) do
    M[choice[1]] = true
    popup = StaticPopup_Show("MOCK_POPUP", nil, nil, popupData)
    check(receivedFrame == popup and receivedData == popupData and action == choice[2], choice[2] .. " popup callback arguments")
    check(not StaticPopup_Visible("MOCK_POPUP"), choice[2] .. " closes popup")
    M[choice[1]] = nil
end
StaticPopup_Hide("MISSING")
check(not StaticPopup_Visible("MISSING") and StaticPopup_Show("MISSING") == nil, "unknown popup safe")

local pointNames = { "TopEdgeLeft", "TopEdgeCenter", "TopEdgeRight", "BottomEdgeLeft", "BottomEdgeCenter", "BottomEdgeRight",
    "RightEdgeTop", "RightEdgeCenter", "RightEdgeBottom", "LeftEdgeTop", "LeftEdgeCenter", "LeftEdgeBottom" }
for i, name in ipairs(pointNames) do
    check(HelpTip.Point[name] == i, "HelpTip point " .. name)
end
check(HelpTip.Alignment.Left == 1 and HelpTip.Alignment.Center == 2 and HelpTip.Alignment.Right == 3, "HelpTip alignment")
check(HelpTip.ButtonStyle.None == 1 and HelpTip.ButtonStyle.Close == 2 and HelpTip.ButtonStyle.Okay == 3 and HelpTip.ButtonStyle.GotIt == 4, "HelpTip button styles")
local acknowledged
local info = { text = "Add a waypoint", callbackArg = popupData,
    onAcknowledgeCallback = function(arg) acknowledged = arg end }
check(HelpTip:Show(panel, info, tab), "HelpTip show returns true")
check(#M.helpTips == 1 and M.helpTips[1].parent == panel and M.helpTips[1].info == info and M.helpTips[1].relativeRegion == tab, "HelpTip records arguments")
check(HelpTip:IsShowing(panel, info.text), "HelpTip showing")
HelpTip:Hide(panel, info.text)
check(not HelpTip:IsShowing(panel, info.text) and acknowledged == nil, "HelpTip hide without acknowledgement")
HelpTip:Show(panel, info)
HelpTip:Acknowledge(panel, info.text)
check(not HelpTip:IsShowing(panel, info.text) and acknowledged == popupData, "HelpTip acknowledge callback")

check(M.cvars.worldMapShowPlayerCoords == "0" and M.cvars.worldMapShowCursorCoords == "0", "coordinate CVars seeded")
SetCVar("worldMapShowPlayerCoords", 1)
check(GetCVar("worldMapShowPlayerCoords") == "1" and C_CVar.GetCVarBool("worldMapShowPlayerCoords"), "global CVar write and boolean read")
C_CVar.SetCVar("worldMapShowCursorCoords", false)
check(C_CVar.GetCVar("worldMapShowCursorCoords") == "false" and not C_CVar.GetCVarBool("worldMapShowCursorCoords"), "namespaced CVar write and read")
check(C_CVar.GetCVarInfo("worldMapShowPlayerCoords") == "1" and C_CVar.GetCVarInfo("MISSING") == nil, "CVar feature detection")
check(WorldMapFrame:GetCanvasContainer() == WorldMapFrame.ScrollContainer, "map canvas container")
check(WorldMapFrame.WorldMapTrackingPinButton:IsObjectType("Button"), "map tracking button")
local overlay = WorldMapFrame:AddOverlayFrame("UIPanelButtonTemplate", "Button", "TOP",
    WorldMapFrame.WorldMapTrackingPinButton, "BOTTOM", 0, -2)
local point, rel, relPoint, x, y = overlay:GetPoint()
check(WorldMapFrame.overlayFrames[1] == overlay and overlay:GetParent() == WorldMapFrame, "overlay recording")
check(point == "TOP" and rel == WorldMapFrame.WorldMapTrackingPinButton and relPoint == "BOTTOM" and x == 0 and y == -2, "overlay anchoring")
local entered = 0
EventRegistry:RegisterCallback("EditMode.Enter", function() entered = entered + 1 end)
EditModeManagerFrame:EnterEditMode()
check(M.editModeEntered == 1 and entered == 1 and EditModeManagerFrame:IsEditModeActive(), "edit mode entry and existing event")
EditModeManagerFrame:ExitEditMode()
check(not EditModeManagerFrame:IsEditModeActive(), "edit mode exits")
M.units.target = { dead = true }
check(UnitIsDead("target") and not UnitIsDead("missing"), "existing UnitIsDead API")
check(GetAppropriateTooltip() == GameTooltip, "appropriate tooltip")

-- Route previews need recorded line geometry and region rendering properties.
local line = panel:CreateLine(nil, "OVERLAY", nil, 1)
check(line:IsObjectType("Line") and type(line.SetStartPoint) == "function"
    and line:GetParent() == panel, "CreateLine creates a Line region")
line:SetStartPoint("TOPLEFT", panel, 10, -20)
line:SetEndPoint("TOPLEFT", panel, 30, -40)
check(line._start[1] == "TOPLEFT" and line._start[2] == panel and line._start[3] == 10
    and line._start[4] == -20 and line._end[1] == "TOPLEFT" and line._end[2] == panel
    and line._end[3] == 30 and line._end[4] == -40, "line endpoints recorded")
line:SetThickness(2)
check(line:GetThickness() == 2, "line thickness")
line:SetColorTexture(1, 0.82, 0, 0.4)
check(line._colorTexture[1] == 1 and line._colorTexture[2] == 0.82
    and line._colorTexture[3] == 0 and line._colorTexture[4] == 0.4, "line colour and alpha")
line:Hide()
check(not line:IsShown(), "line hides")
line:Show()
check(line:IsShown(), "line shows")
check(line._drawLayer[1] == "OVERLAY" and line._drawLayer[2] == 1, "line creation draw layer")
line:SetDrawLayer("ARTWORK", 2)
check(line._drawLayer[1] == "ARTWORK" and line._drawLayer[2] == 2, "region draw layer recorded")
panel:SetClipsChildren(true)
check(panel._clipsChildren == true, "child clipping enabled")
panel:SetClipsChildren(false)
check(panel._clipsChildren == false, "child clipping disabled")
local texture = panel:CreateTexture()
texture:SetRotation(0.5)
texture:SetColorTexture(0.08, 0.08, 0.1)
texture:SetHitRectInsets(0, 0, -11, 11)
panel:SetHitRectInsets(0, 0, 0, 0)
check(texture._rotation == 0.5 and texture._colorTexture[3] == 0.1
    and texture._colorTexture[4] == 1, "texture rotation and default colour alpha")

check(Enum.UIMapType.World == 1 and UnitLevel("player") > 0, "world enum and player level retained")
check(M.maps[12].name == "Kalimdor" and M.maps[13].name == "Eastern Kingdoms"
    and not M.maps[1414] and not M.maps[1415], "retail continent IDs retained")
check(M.maps[291].parentMapID == 52 and M.maps[291].cont ~= M.maps[52].cont
    and M.maps[1].parentMapID == 12, "dungeon instance and cross-continent zone fixtures")
check(C_Map.GetWorldPosFromMapPos(947, CreateVector2D(0.5, 0.5)) == nil, "world map has no world position")
check(C_Map.GetMapArtID(37) == 370 and C_Map.GetMapArtID(-1) == nil, "map art IDs")
local layers = C_Map.GetMapArtLayers(37)
check(C_Map.MapHasArt(37) and #layers == 1 and layers[1].layerWidth == 1002
    and layers[1].layerHeight == 668 and layers[1].tileWidth == 256 and layers[1].tileHeight == 256
    and layers[1].minScale == 1 and layers[1].maxScale == 1 and layers[1].additionalZoomSteps == 0,
    "map art layer dimensions and scales")
local textures = C_Map.GetMapArtLayerTextures(37, 1)
local ordered = #textures == 12
for i, file in ipairs(textures) do ordered = ordered and file == 37000 + i end
check(ordered, "all twelve map art texture IDs in order")
check(C_Map.GetMapArtLayerTextures(37, 2) == nil and C_Map.GetMapArtLayers(-1) == nil
    and not C_Map.MapHasArt(-1) and C_Map.GetMapArtLayerTextures(-1, 1) == nil, "missing map art and layer")
M.maps[52].noArt = true
check(not C_Map.MapHasArt(52) and C_Map.GetMapArtLayers(52) == nil
    and C_Map.GetMapArtLayerTextures(52, 1) == nil, "noArt disables layers and textures")
M.maps[52].noArt = nil
local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(13, 947)
check(minX == 0.55 and maxX == 0.95 and minY == 0.10 and maxY == 0.90,
    "Eastern Kingdoms world rectangle returns four numbers")
minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(12, 947)
check(minX == 0.05 and maxX == 0.45 and minY == 0.10 and maxY == 0.90, "Kalimdor world rectangle")
check(C_Map.GetMapRectOnMap(37, 947) == nil and C_Map.GetMapRectOnMap(13, 12) == nil
    and C_Map.GetMapRectOnMap(-1, 947) == nil, "only continents have world rectangles")
local explored = C_MapExplorationInfo.GetExploredMapTextures(37)
local patch = explored[1]
check(explored == M.explored[37] and #explored == 1 and patch.textureWidth == 300
    and patch.textureHeight == 270 and patch.offsetX == 100 and patch.offsetY == 50
    and #patch.fileDataIDs == 4 and patch.fileDataIDs[1] == 9001 and patch.fileDataIDs[2] == 9002
    and patch.fileDataIDs[3] == 9003 and patch.fileDataIDs[4] == 9004
    and patch.isShownByMouseOver == false and patch.isDrawOnTopLayer == false, "explored texture fixture")
check(#C_MapExplorationInfo.GetExploredMapTextures(-1) == 0, "unexplored map has no overlays")

local map = WorldMapFrame
check(map:GetCanvas() == map.ScrollContainer.Child and map:GetCanvas():IsObjectType("Frame")
    and map:GetCanvas():GetParent() == map.ScrollContainer and map.ScrollContainer:GetCanvasScale() == 1,
    "map canvas child and scale")
local refreshed, changed, providerShown, providerHidden, scriptShown, scriptHidden = 0, 0, 0, 0, 0, 0
local provider = CreateFromMixins(MapCanvasDataProviderMixin)
function provider:RefreshAllData()
    refreshed = refreshed + 1
    check(self:GetMap() == map, "provider refresh owns the map")
end
function provider:OnShow() providerShown = providerShown + 1 end
function provider:OnHide() providerHidden = providerHidden + 1 end
map:AddDataProvider(provider)
local explicitProvider = CreateFromMixins(MapCanvasDataProviderMixin)
function explicitProvider:OnMapChanged() changed = changed + 1 end
map:AddDataProvider(explicitProvider)
map:SetMapID(52)
check(map:GetMapID() == 52 and refreshed == 1 and changed == 1,
    "SetMapID calls every provider, defaulting to RefreshAllData")
map:SetScript("OnShow", function() scriptShown = scriptShown + 1 end)
map:SetScript("OnHide", function() scriptHidden = scriptHidden + 1 end)
OpenWorldMap(52)
check(M.worldMapOpened == 52 and map:IsShown() and map:GetMapID() == 52 and refreshed == 2
    and changed == 2 and scriptShown == 1 and providerShown == 1, "OpenWorldMap opens on requested map")
map:Show()
check(scriptShown == 1 and providerShown == 1, "repeated map Show has no visibility callbacks")
HideUIPanel(map)
check(not map:IsShown() and scriptHidden == 1 and providerHidden == 1, "map hide scripts and providers")
map:Hide()
check(scriptHidden == 1 and providerHidden == 1, "repeated map Hide has no visibility callbacks")
local blocked = M.actionBlocked or 0
M.player.combat = true
OpenWorldMap(37)
check(not map:IsShown() and map:GetMapID() == 52 and M.worldMapOpened == 52
    and M.actionBlocked == blocked + 1 and refreshed == 2, "OpenWorldMap blocked in combat")
M.player.combat = false
ToggleWorldMap()
check(map:IsShown() and map:GetMapID() == C_Map.GetBestMapForUnit("player"), "ToggleWorldMap opens player map")
blocked = M.actionBlocked
M.player.combat = true
ToggleWorldMap()
check(map:IsShown() and M.actionBlocked == blocked + 1, "ToggleWorldMap hide blocked in combat")
M.player.combat = false
ToggleWorldMap()
check(not map:IsShown() and scriptShown == 2 and providerShown == 2
    and scriptHidden == 2 and providerHidden == 2, "ToggleWorldMap hides through panel lifecycle")

-- Keep waypoint and route pins together until their own template is removed.
local oldWaypointMixin, oldRouteMixin = WaypointTrackerMapPinMixin, WaypointTrackerRoutePinMixin
local waypointLoads, routeLoads, acquired = 0, 0, 0
WaypointTrackerMapPinMixin = CreateFromMixins(MapCanvasPinMixin)
function WaypointTrackerMapPinMixin:OnLoad() waypointLoads = waypointLoads + 1 end
WaypointTrackerRoutePinMixin = CreateFromMixins(MapCanvasPinMixin)
function WaypointTrackerRoutePinMixin:OnLoad() routeLoads = routeLoads + 1 end
function WaypointTrackerRoutePinMixin:OnAcquired(route, i, x, y)
    acquired = acquired + 1
    self.route, self.index = route, i
    self:SetPosition(x, y)
    self.Number:SetText(i)
end
local route = { name = "Mock route" }
local waypointPin = map:AcquirePin("WaypointTrackerMapPinTemplate")
local routePin = map:AcquirePin("WaypointTrackerRoutePinTemplate", route, 2, 0.4, 0.6)
check(#map.pins == 2 and waypointLoads == 1 and routeLoads == 1 and acquired == 1,
    "AcquirePin honours each template mixin and lifecycle")
check(routePin.Icon:IsObjectType("Texture") and routePin.Highlight:IsObjectType("Texture")
    and routePin.Number:IsObjectType("FontString") and routePin.Number:GetText() == 2
    and routePin.route == route and routePin.index == 2 and routePin.normalizedX == 0.4
    and routePin.normalizedY == 0.6 and routePin:GetMap() == map, "route pin regions and acquisition arguments")
check(rawget(waypointPin, "Number") == nil and waypointPin.template == "WaypointTrackerMapPinTemplate"
    and routePin.template == "WaypointTrackerRoutePinTemplate", "pins retain their template")
map:RemoveAllPinsByTemplate("MissingPinTemplate")
check(#map.pins == 2, "unknown template removal preserves pins")
map:RemoveAllPinsByTemplate("WaypointTrackerRoutePinTemplate")
check(#map.pins == 1 and map.pins[1] == waypointPin and waypointPin:IsShown()
    and not routePin:IsShown(), "route pin removal preserves waypoint pins")
map:RemoveAllPinsByTemplate()
check(#map.pins == 0 and not waypointPin:IsShown(), "nil template removal still clears all pins")
check(PIN_FRAME_LEVEL_WAYPOINT_LOCATION == "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", "waypoint frame level constant")
WaypointTrackerMapPinMixin, WaypointTrackerRoutePinMixin = oldWaypointMixin, oldRouteMixin
map.providers = {}
map:SetScript("OnShow", nil)
map:SetScript("OnHide", nil)
map:SetMapID(37)

check(next(M.unknownMethods) == nil, "new APIs use implemented methods")
check(#M.errors == 0, "no reported Lua errors")

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
