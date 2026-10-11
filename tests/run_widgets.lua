-- Shared controls against the fake WoW API. Run from the repository root:
--     lua5.1 tests/run_widgets.lua
--     lua5.1 tests/run_widgets.lua --bare
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
local function summary()
    check(#M.errors == 0, "no reported Lua errors: " .. tostring(M.errors[1]))
    print(("%d passed, %d failed"):format(passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

-- Wave 1's TOC and mock are developed in other worktrees. Load Widgets
-- explicitly until the TOC lands; add only missing mock features locally.
local loadAddon = M.LoadAddon
local loadedNS
function M.LoadAddon(dir, name)
    local ns = loadAddon(dir, name)
    if name == "WaypointTracker" and not ns.Widgets then
        assert(loadfile("WaypointTracker/Widgets.lua"))(name, ns)
    end
    if name == "WaypointTracker" then loadedNS = ns end
    return ns
end
local createFrame = CreateFrame
local missingTemplates = {}
local function RejectTemplates(kind, name, parent, template)
    if missingTemplates[template] then error("missing template: " .. template) end
    local f = createFrame(kind, name, parent, template)
    local createFontString = f.CreateFontString
    function f:CreateFontString(name, layer, font)
        local fs = createFontString(self, name, layer, font)
        fs.fontTemplate = font
        return fs
    end
    -- The shared mock incorrectly gives InputBoxTemplate Instructions and a
    -- clear button, and does not model InputBoxInstructionsTemplate at all.
    if template == "InputBoxTemplate" then
        f.Instructions, f.clearButton = nil, nil
    elseif template == "InputBoxInstructionsTemplate" or template == "SearchBoxTemplate" then
        f.Instructions = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        f.Instructions:SetTextColor(0.35, 0.35, 0.35)
        -- Keep both anchors: the shared mock's SetPoint keeps only the last.
        function f.Instructions:SetPoint(point, x, y)
            local anchor = { point, nil, point, x, y }
            for i, existing in ipairs(self._points) do
                if existing[1] == point then
                    self._points[i] = anchor
                    return
                end
            end
            self._points[#self._points + 1] = anchor
        end
        f.Instructions:SetPoint("TOPLEFT", 16, 0)
        f.Instructions:SetPoint("BOTTOMRIGHT", -20, 0)
        if template == "SearchBoxTemplate" then
            f.instructionText = "Search"
            f.Instructions:SetText(f.instructionText)
            f.searchIcon = f:CreateTexture()
            f.clearButton = createFrame("Button", nil, f)
            f.clearButton:Hide()
            f.clearButton:SetScript("OnClick", function() f:SetText(""); f:ClearFocus() end)
            f:SetScript("OnEditFocusLost", function(self)
                if self:GetText() == "" then self.clearButton:Hide() end
            end)
            f:SetScript("OnEditFocusGained", function(self) self.clearButton:Show() end)
        end
        f:SetScript("OnTextChanged", function(self)
            self.nativeTextChanged = (self.nativeTextChanged or 0) + 1
            self.Instructions:SetShown(self:GetText() == "")
            if self.clearButton then self.clearButton:SetShown(self:HasFocus() or self:GetText() ~= "") end
        end)
    elseif template == "UIPanelButtonTemplate" then
        f:SetFontString(f:CreateFontString(nil, "ARTWORK", "GameFontNormal"))
        local setText = f.SetText
        function f:SetText(text)
            setText(self, text)
            self:GetFontString():SetText(text)
        end
    end
    return f
end

if arg and arg[1] == "--bare" then
    for _, template in ipairs({ "SearchBoxTemplate", "InputBoxInstructionsTemplate", "InputBoxTemplate", "InputScrollFrameTemplate", "WowStyle1DropdownTemplate", "MagicButtonTemplate" }) do
        missingTemplates[template] = true
    end
    CreateFrame = RejectTemplates
    StaticPopup_Show, StaticPopupDialogs = nil, nil
    dofile("tests/run_bare.lua")
    local W = loadedNS.Widgets
    check(W ~= nil, "Widgets loaded during the bare suite")
    local edit = W.EditBox(UIParent, 180, { search = true, placeholder = "Search" })
    check(edit.edit.placeholder:GetText() == "Search", "bare search uses the Box fallback")
    local plain = W.EditBox(UIParent, 180, { placeholder = "Name" })
    check(plain._template == "BackdropTemplate" and plain.edit.placeholder.fontTemplate == "GameFontDisableSmall", "bare plain field uses a small fallback placeholder")
    local area = W.TextArea(UIParent, { placeholder = "Paste" })
    check(area.edit and area.scroll._template == "UIPanelScrollFrameTemplate", "bare text area uses the scroll fallback")
    local value = 1
    local dd = W.Dropdown(UIParent, 180, {
        text = function() return tostring(value) end,
        menu = function(root)
            for i = 1, 2 do
                local v = i
                root:CreateRadio(tostring(v), function() return value == v end, function() value = v end)
            end
        end,
    })
    dd.next:Click()
    check(value == 2 and dd.text:GetText() == "2", "bare dropdown cycles and updates text")
    local called = 0
    W.Menu(UIParent, function(root) root:CreateButton("Action", function() called = called + 1 end) end)
    W.Confirm("WAYPOINTTRACKER_WIDGETS_TEST", { text = "Accept?", button1 = "Yes", onAccept = function() called = called + 1 end })
    W.Ask("WAYPOINTTRACKER_WIDGETS_TEST")
    check(called == 2, "bare menu and popup execute primary actions")
    check(W.MagicButton(UIParent, "Button", 80)._template == "UIPanelButtonTemplate", "bare MagicButton falls back")
    W.Check(UIParent, "Arrow", "arrowShown"):Click()
    W.Slider(UIParent, "Scale", "arrowScale", 0.5, 2, 0.05, 180, W.Percent).slider:SetValue(1.5)
    check(loadedNS.Get("arrowScale") == 1.5, "bare bound controls update settings")
    local list = W.List(UIParent, { rowHeight = 20 })
    list:SetSize(180, 40)
    list:SetItems({ 1, 2, 3 })
    list:RunScript("OnMouseWheel", -1)
    check(list.visibleRows == 2 and list.offset == 1, "bare list scrolls")
    summary()
end

local sizeEvents = false
local probe = CreateFrame("Frame", nil, UIParent)
probe:SetScript("OnSizeChanged", function() sizeEvents = true end)
probe:SetSize(10, 10)
probe:Hide()
function CreateFrame(kind, name, parent, template)
    local f = RejectTemplates(kind, name, parent, template)
    if not sizeEvents then
        local setSize = f.SetSize
        function f:SetSize(w, h)
            local changed = self:GetWidth() ~= w or self:GetHeight() ~= h
            setSize(self, w, h)
            if changed then self:RunScript("OnSizeChanged", w, h) end
        end
        function f:SetHeight(h) self:SetSize(self:GetWidth(), h) end
        function f:SetWidth(w) self:SetSize(w, self:GetHeight()) end
    end
    if template == "InputScrollFrameTemplate" and not rawget(f, "EditBox") then
        f.EditBox = createFrame("EditBox", nil, f)
        f.EditBox.Instructions = f.EditBox:CreateFontString()
        f.CharCount = f:CreateFontString()
        f:SetScrollChild(f.EditBox)
        f.EditBox:HookScript("OnTextChanged", function(self)
            self.nativeTextChanged = (self.nativeTextChanged or 0) + 1
        end)
    elseif template == "WowStyle1DropdownTemplate" and not rawget(f, "SetupMenu") then
        function f:SetupMenu(gen) self.menuGenerator = gen end
        function f:OverrideText(text) self:SetText(text) end
    end
    return f
end
if not InputScrollFrame_SetInstructions then
    function InputScrollFrame_SetInstructions(frame, text) frame.EditBox.Instructions:SetText(text) end
end
local contextMenu = MenuUtil.CreateContextMenu
function MenuUtil.CreateContextMenu(owner, gen)
    return contextMenu(owner, function(o, root)
        if not root.CreateRadio then
            function root:CreateRadio(text, isSelected, setSelected)
                local item = { text = text, kind = "radio", fn = setSelected, isSelected = isSelected, setSelected = setSelected }
                self.items[#self.items + 1] = item
                return item
            end
        end
        if not root.CreateCheckbox then
            function root:CreateCheckbox(text, isSelected, setSelected)
                local item = { text = text, kind = "checkbox", fn = setSelected, isSelected = isSelected, setSelected = setSelected }
                self.items[#self.items + 1] = item
                return item
            end
        end
        if not root.CreateDivider then
            function root:CreateDivider() self.items[#self.items + 1] = { kind = "divider" } end
        end
        gen(o, root)
        M.lastMenu = root
    end)
end

WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local W = ns.Widgets

local autoButton = W.Button(UIParent, "Translated button label")
check(autoButton:GetWidth() == autoButton:GetFontString():GetStringWidth() + 24 and autoButton:GetHeight() == 24, "omitted button width fits the label after SetText")
check(W.Button(UIParent, "OK"):GetWidth() == 80, "automatic button width has an 80-pixel minimum")
local fixedButton = W.Button(UIParent, "Long translated label", 90, 30)
check(fixedButton:GetWidth() == 90 and fixedButton:GetHeight() == 30, "explicit button dimensions are preserved")
missingTemplates.UIPanelButtonTemplate = true
local bareButton = W.Button(UIParent, "Button")
check(bareButton:GetWidth() == 84 and bareButton:GetHeight() == 24, "button without a template or font string gets a usable width")
missingTemplates.UIPanelButtonTemplate = nil

local changes = 0
ns.On("SETTING_CHANGED", function() changes = changes + 1 end)
local cb = W.Check(UIParent, "Show arrow", "arrowShown", "An arrow", 200)
check(cb:GetChecked() == ns.Get("arrowShown"), "checkbox initializes from its setting")
cb:Click()
check(not ns.Get("arrowShown") and not cb:GetChecked(), "checkbox toggles a setting key")
ns.Set("arrowShown", true)
check(cb:GetChecked(), "setting event refreshes the checkbox")
local localValue = false
local accessorCheck = W.Check(UIParent, "Local", { get = function() return localValue end, set = function(v) localValue = v end })
local changedValue
accessorCheck.onChange = function(v) changedValue = v end
accessorCheck:Click()
check(localValue and changedValue and accessorCheck:GetChecked(), "accessor checkbox toggles and calls onChange")
localValue = false
W.Refresh()
check(not accessorCheck:GetChecked(), "Refresh re-reads accessor checkboxes")

local slider = W.Slider(UIParent, "Arrow size", "arrowScale", 0.5, 2, 0.05, 200, W.Percent, "Size")
local before = changes
W.Refresh()
check(changes == before, "bound refresh does not write settings")
slider.slider:SetValue(9)
check(ns.Get("arrowScale") == 2 and slider.slider:GetValue() == 2 and slider.valueText:GetText() == "200%", "slider clamps and formats its maximum")
slider.slider:SetValue(-5)
check(ns.Get("arrowScale") == 0.5 and slider.valueText:GetText() == "50%", "slider clamps its minimum")
slider.slider:SetValue(1.23)
check(math.abs(ns.Get("arrowScale") - 1.25) < 0.00001 and slider.valueText:GetText() == "125%", "slider rounds to its step")
slider.slider:RunScript("OnMouseWheel", 1)
check(math.abs(ns.Get("arrowScale") - 1.3) < 0.00001, "slider wheel moves one step")
ns.Set("arrowScale", 1.5)
check(slider.valueText:GetText() == "150%", "setting event refreshes the slider")
check(W.Percent(0.805) == "81%" and W.Yards(15) == ns.Geo.FormatDistance(15), "shared formatters")

local inits, clicks, doubles, rights = 0, {}, {}, {}
local list = W.List(UIParent, {
    rowHeight = 20,
    emptyText = "Empty",
    rowInit = function(row) inits = inits + 1; row.label = W.Label(row, "") end,
    rowUpdate = function(row, item, index, selected) row.label:SetText(item.text); row.marked = selected; row.updatedIndex = index end,
    onClick = function(row, item, button) clicks = { row, item, button } end,
    onDoubleClick = function(row, item) doubles = { row, item } end,
    onRightClick = function(row, item) rights = { row, item } end,
})
check(#list.rows == 0, "zero-height list creates no rows")
list:SetSize(240, 205)
check(list.visibleRows == 10 and #list.rows == 10 and inits == 10, "size change creates only the rows that fit")
local items = {}
for i = 1, 50 do items[i] = { text = "Item " .. i } end
list:SetItems(items)
local shown = 0
for _, row in ipairs(list.rows) do if row:IsShown() then shown = shown + 1 end end
check(shown == list.visibleRows and list.scrollbar:IsShown() and not list.emptyText:IsShown(), "50-item list shows visibleRows and scrollbar")
check(list.scrollbar:GetWidth() == 14, "scrollbar is 14 pixels wide")
list:RunScript("OnMouseWheel", -1)
check(list.offset == 3 and list.rows[1].item == items[4], "wheel scrolls three rows")
list:SetSelected(items[5])
check(list:GetSelected() == items[5] and list.rows[2].marked and list.rows[2].selected, "selection reaches the row updater")
list.rows[2]:Click()
check(clicks[1] == list.rows[2] and clicks[2] == items[5] and clicks[3] == "LeftButton", "left-click receives row and item")
list.rows[2]:Click("RightButton")
check(clicks[3] == "RightButton" and rights[2] == items[5], "right-click receives item")
list.rows[2]:RunScript("OnDoubleClick", "LeftButton")
check(doubles[2] == items[5], "double-click receives item")
list:ScrollTo(50)
check(list.offset == 40 and list.rows[10].item == items[50], "ScrollTo reveals last item")
list:RunScript("OnMouseWheel", -99)
check(list.offset == 40, "wheel stops at the end")
list:ScrollTo(1)
check(list.offset == 0, "ScrollTo reveals first item")
list:RunScript("OnMouseWheel", 99)
check(list.offset == 0, "wheel stops at the start")
list.scrollbar:SetValue(11)
check(list.offset == 11 and list.rows[1].item == items[12], "scrollbar drives rows")
list:SetSize(240, 65)
check(list.visibleRows == 3 and not list.rows[4]:IsShown() and list.rows[4].item == nil and inits == 10, "shrinking hides and clears pooled rows")
list:SetSize(240, 305)
check(list.visibleRows == 15 and #list.rows == 15 and inits == 15, "growing initializes only new rows")
list:SetItems({ items[1], items[2] })
check(list.offset == 0 and not list.scrollbar:IsShown() and list.rows[2]:IsShown() and not list.rows[3]:IsShown(), "short list clamps offset and hides scrollbar")
list:SetItems({})
check(list.emptyText:IsShown() and not list.rows[1]:IsShown(), "empty list hides rows and shows its message")
list:SetSelected(nil)
check(list:GetSelected() == nil, "selection can be cleared")

local search = W.EditBox(UIParent, 180, { search = true, placeholder = "Search places", maxLetters = 200 })
check(search.edit._template == "SearchBoxTemplate" and search.edit.Instructions:GetText() == "Search places", "native search uses Instructions")
local point, _, _, x, y = search.edit.Instructions:GetPoint(1)
check(#search.edit.Instructions._points == 2 and point == "TOPLEFT" and x == 16 and y == 0, "search instructions retain space for the magnifier")
point, _, _, x, y = search.edit.Instructions:GetPoint(2)
check(point == "BOTTOMRIGHT" and x == -20 and y == 0, "search instructions retain space for the clear button")
search.edit:SetText("Hogger")
check(search.edit.nativeTextChanged == 1 and not search.edit.placeholder:IsShown() and search.edit.clearButton:IsShown(), "native search retains its text callback, clear button and placeholder behavior")
search.edit.clearButton:Click()
check(search.edit:GetText() == "" and search.edit.placeholder:IsShown() and search.edit.Instructions:GetText() == "Search places" and search.edit.instructionText == "Search places", "search clear button preserves the configured instructions after native OnLoad")
search.edit:SetFocus()
search.edit:RunScript("OnEscapePressed")
check(not search.edit:HasFocus(), "Escape clears edit focus")
local plain = W.EditBox(UIParent, 80, { search = false, placeholder = "Name", numeric = true })
check(plain.edit._template == "InputBoxInstructionsTemplate" and plain.edit.placeholder == plain.edit.Instructions and plain.edit.placeholder:GetText() == "Name" and not plain.edit.searchIcon, "plain field reuses native Instructions without a magnifier")
point, _, _, x, y = plain.edit.Instructions:GetPoint(1)
check(#plain.edit.Instructions._points == 2 and point == "TOPLEFT" and x == 10 and y == 0, "plain instructions align with the native text's left inset")
point, _, _, x, y = plain.edit.Instructions:GetPoint(2)
check(point == "BOTTOMRIGHT" and x == -10 and y == 0, "plain instructions span the field inside its native text insets")
plain.edit:SetText("42")
check(plain.edit.nativeTextChanged == 1 and not plain.edit.placeholder:IsShown(), "plain native callback hides instructions while typing")
plain.edit:SetText("")
check(plain.edit.placeholder:IsShown() and plain.edit.Instructions:GetText() == "Name", "plain native callback restores the configured instructions")
local area = W.TextArea(UIParent, { placeholder = "Paste here" })
check(area.scroll._template == "InputScrollFrameTemplate" and area.edit == area.scroll.EditBox, "native text area exposes template EditBox")
area.edit:SetText("One\nTwo")
check(not area.edit.placeholder:IsShown(), "text area hides placeholder for multiline text")
area:SetSize(420, 180)
check(area.edit:GetWidth() == 386 and area.edit.placeholder:GetWidth() == 386, "text area updates width and reserves room for its native scrollbar")

local selected = "a"
local function Menu(root)
    root:CreateTitle("Choose")
    root:CreateDivider()
    root:CreateButton("Action", function() end)
    for _, option in ipairs({ "a", "b", "c" }) do
        local value = option
        root:CreateRadio(value, function() return selected == value end, function() selected = value end)
    end
    root:CreateCheckbox("Checked", function() return false end, function() end)
end
local opts = { text = function() return "Choice " .. selected end, menu = Menu }
local magic = W.MagicButton(UIParent, "Settings", 100)
check(magic._template == "MagicButtonTemplate" and magic:GetHeight() == 22, "MagicButton uses its native template")
local native = W.Dropdown(UIParent, 160, opts)
check(native._template == "WowStyle1DropdownTemplate" and native:GetText() == "Choice a", "native dropdown initializes its label")
local gen = rawget(native, "menuGenerator") or rawget(native, "_menuGenerator")
if gen then
    W.Menu(native, function(root) gen(native, root) end)
else
    -- A merged mock may expose its setup generator under another field.
    W.Menu(native, Menu)
end
local root = M.lastMenu
check(root and #root.items == 7 and root.items[4].kind == "radio", "native menu records all supported entry types")
root.items[5].fn()
native:Refresh()
check(selected == "b" and native:GetText() == "Choice b", "native dropdown refreshes after selection")
native.OverrideText = function() error("OverrideText unavailable") end
native:Refresh()
check(native:GetText() == "Choice b", "native dropdown falls back to SetText")

missingTemplates.WowStyle1DropdownTemplate = true
selected = "a"
local fallback = W.Dropdown(UIParent, 160, opts)
check(fallback.next and fallback.text:GetText() == "Choice a", "dropdown creation failure uses Picker")
fallback.next:Click()
check(selected == "b" and fallback.text:GetText() == "Choice b", "fallback steps through radio choices")
fallback.prev:Click()
fallback.prev:Click()
check(selected == "c" and fallback.text:GetText() == "Choice c", "fallback wraps in either direction")
selected = "b"
W.Refresh()
check(fallback.text:GetText() == "Choice b", "global refresh updates fallback dropdown text")
check(fallback.menu.items[7].kind == "checkbox" and fallback.menu.items[7].setSelected ~= nil, "fake root records checkbox callbacks")
local actionCount = 0
local action = W.Dropdown(UIParent, 160, {
    text = function() return "Actions " .. actionCount end,
    menu = function(r) r:CreateButton("First", function() actionCount = actionCount + 1 end) end,
})
action.next:Click()
check(actionCount == 1 and action.text:GetText() == "Actions 1", "action-only fallback dropdown executes a button")
local actionNames = {}
local multiAction = W.Dropdown(UIParent, 160, {
    text = function() return "Actions" end,
    menu = function(r)
        r:CreateButton("First", function() actionNames[#actionNames + 1] = "first" end)
        r:CreateButton("Second", function() actionNames[#actionNames + 1] = "second" end)
        r:CreateButton("Third", function() actionNames[#actionNames + 1] = "third" end)
    end,
})
multiAction.next:Click()
multiAction.next:Click()
multiAction.next:Click()
check(table.concat(actionNames, ",") == "second,third,first", "action-only fallback cycles through every button")

local menuUtil = MenuUtil
MenuUtil = nil
local actions, checked = {}, false
W.Menu(UIParent, function(r)
    r:CreateTitle("Menu")
    r:CreateRadio("Radio", function() return false end, function() actions[#actions + 1] = "radio" end)
    r:CreateCheckbox("Check", function() return checked end, function() checked = not checked end)
    r:CreateDivider()
    r:CreateButton("First", function() actions[#actions + 1] = "first" end)
    r:CreateButton("Second", function() actions[#actions + 1] = "second" end)
end)
check(#actions == 1 and actions[1] == "first", "Menu fallback runs the first button, ignoring radio and checkbox entries")
W.lastMenu.items[6].fn()
W.lastMenu.items[3].fn()
check(actions[2] == "second" and checked, "fallback recorded entries can be clicked by tests")
W.Menu(UIParent, function(r) r:CreateTitle("No actions"); r:CreateDivider() end)
check(#W.lastMenu.items == 2, "menu without an action is safe")
MenuUtil = { CreateContextMenu = function() error("Menu API unavailable") end }
W.Menu(UIParent, function(r) r:CreateButton("First", function() actions[#actions + 1] = "first" end) end)
check(#actions == 3, "Menu API failure uses the fallback")
MenuUtil = menuUtil

local accepts, alts, cancels = 0, 0, 0
local id = "WAYPOINTTRACKER_WIDGETS_TEST"
W.Confirm(id, { text = "%s?", button1 = "Yes", button2 = "No", button3 = "Other", sound = 856,
    onAccept = function() accepts = accepts + 1 end,
    onAlt = function() alts = alts + 1 end,
    onCancel = function() cancels = cancels + 1 end,
})
local dialog = StaticPopupDialogs[id]
check(dialog.timeout == 0 and dialog.whileDead == 1 and dialog.hideOnEscape == 1 and dialog.preferredIndex == 3, "popup has native defaults")
M.autoAcceptPopup = true
W.Ask(id, "Accept")
check(accepts == 1 and M.lastPopup == id, "auto-accept popup calls onAccept")
M.autoAcceptPopup = false
dialog.OnAlt()
dialog.OnCancel()
check(alts == 1 and cancels == 1 and dialog.button3 == "Other", "third button and cancel callbacks are wired")
local args
local popupShow = StaticPopup_Show
StaticPopup_Show = function(...) args = { ... }; return popupShow(...) end
local data = {}
W.Ask(id, "name", 3, data)
check(args[1] == id and args[2] == "name" and args[3] == 3 and args[4] == data, "Ask forwards formatting arguments and popup data")
W.Confirm(id, { text = "Current question", button1 = "Yes", onAccept = function(_, value) accepts = accepts + 10; args = value end })
check(StaticPopupDialogs[id] == dialog and dialog.text == "Current question", "Confirm reuses its dialog with the current question")
dialog.OnAccept(nil, data)
check(accepts == 11 and args == data, "reused popup calls the latest callback with data")
StaticPopup_Show, StaticPopupDialogs = nil, nil
W.Ask(id)
check(accepts == 21, "missing popup API accepts directly")
W.Confirm("WAYPOINTTRACKER_WIDGETS_BARE", { onAccept = function() accepts = accepts + 1 end })
W.Ask("WAYPOINTTRACKER_WIDGETS_BARE")
check(accepts == 22, "Confirm works without StaticPopupDialogs")

missingTemplates.SearchBoxTemplate, missingTemplates.InputBoxInstructionsTemplate, missingTemplates.InputScrollFrameTemplate = true, true, true
local box = W.EditBox(UIParent, 160, { search = true, placeholder = "Fallback" })
check(box._template == "BackdropTemplate" and box.edit.placeholder:IsShown(), "missing search template uses old Box")
check(box.edit.placeholder.fontTemplate == "GameFontDisableSmall", "fallback search placeholder uses Blizzard's small disabled font")
local plainBox = W.EditBox(UIParent, 160, { placeholder = "Name" })
check(plainBox._template == "BackdropTemplate" and plainBox.edit.placeholder.fontTemplate == "GameFontDisableSmall", "missing plain instructions template uses Box with a small placeholder")
box.edit:SetText("text")
check(not box.edit.placeholder:IsShown(), "Box placeholder updates")
box.edit:SetText("")
check(box.edit.placeholder:IsShown(), "Box placeholder returns")
local textArea = W.TextArea(UIParent, { placeholder = "Paste" })
check(textArea.scroll._template == "UIPanelScrollFrameTemplate" and textArea.scroll._child == textArea.edit, "missing input-scroll template uses scroll plus EditBox")
textArea:SetSize(500, 200)
check(textArea.edit:GetWidth() == 464 and textArea.edit:GetScript("OnCursorChanged") and textArea.edit:GetScript("OnUpdate"), "fallback text area resizes and supports cursor scrolling")
missingTemplates.MagicButtonTemplate = true
local button = W.MagicButton(UIParent, "Settings", 100)
check(button._template == "UIPanelButtonTemplate" and button:GetHeight() == 22, "MagicButton fallback retains native height")
summary()
