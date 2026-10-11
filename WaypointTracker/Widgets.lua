-- Shared controls, using Blizzard templates where the client has them.
-- Menus must use only root:CreateTitle(text), CreateButton(text, fn),
-- CreateRadio(text, isSelected, setSelected), CreateCheckbox(text, isSelected,
-- setSelected), and CreateDivider(). The fallback records these calls; it
-- supports neither submenus nor elem:SetTooltip(fn).
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local refreshers, confirmations = {}, {}

Widgets.BACKDROP_DIALOG = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
Widgets.BACKDROP_BOX = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BACKDROP_SLIDER = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

local function Template(kind, parent, template)
    local ok, frame = pcall(CreateFrame, kind, nil, parent, template)
    if ok then
        return frame
    end
end

local function Backdrop(parent, backdrop)
    local frame = Template("Frame", parent, "BackdropTemplate") or CreateFrame("Frame", nil, parent)
    if frame.SetBackdrop then
        frame:SetBackdrop(backdrop)
        frame:SetBackdropColor(0, 0, 0, 0.8)
    end
    return frame
end

local function Bind(widget)
    refreshers[#refreshers + 1] = function() widget:Refresh() end
    widget:Refresh()
end

local function Accessor(key)
    if type(key) == "table" then
        return key.get, key.set
    elseif key then
        return function() return ns.Get(key) end, function(v) ns.Set(key, v) end
    end
end

local function CheckSound()
    if PlaySound then
        PlaySound((SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856)
    end
end

function Widgets.Tooltip(widget, title, body)
    if not body or body == "" then
        return
    end
    widget:HookScript("OnEnter", ns.Safe(function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(title or "", 1, 1, 1)
            GameTooltip:AddLine(body, 1, 0.82, 0, true)
            GameTooltip:Show()
        end
    end))
    widget:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end
Widgets.AddTooltip = Widgets.Tooltip

function Widgets.Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

function Widgets.Header(parent, text)
    local fs = Widgets.Label(parent, text, "GameFontNormalLarge")
    fs:SetTextColor(1, 0.82, 0)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    return fs
end

function Widgets.Button(parent, text, width, height)
    local b = Template("Button", parent, "UIPanelButtonTemplate") or CreateFrame("Button", nil, parent)
    b:SetText(text)
    width = width or math.max(80, (b:GetFontString() and b:GetFontString():GetStringWidth() or 60) + 24)
    b:SetSize(width, height or 24)
    return b
end

function Widgets.MagicButton(parent, text, width)
    local b = Template("Button", parent, "MagicButtonTemplate")
    if not b then return Widgets.Button(parent, text, width, 22) end
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

function Widgets.Check(parent, label, key, tooltip, labelWidth)
    local cb = Template("CheckButton", parent, "UICheckButtonTemplate") or CreateFrame("CheckButton", nil, parent)
    cb:SetSize(26, 26)
    local text = Widgets.Label(cb, label)
    text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    text:SetWidth(labelWidth or 300)
    text:SetWordWrap(false)
    cb.label = text
    cb:SetHitRectInsets(0, -math.min(text:GetStringWidth() + 4, labelWidth or 300), 0, 0)
    local get, set = Accessor(key)
    cb.settingKey = type(key) == "string" and key or nil
    cb:SetScript("OnClick", ns.Safe(function(self)
        CheckSound()
        local checked = self:GetChecked() and true or false
        if set then set(checked) end
        if self.onChange then self.onChange(checked) end
        if get then self:Refresh() end
    end))
    function cb:Refresh()
        if get then self:SetChecked(get() and true or false) end
    end
    Widgets.Tooltip(cb, label, tooltip)
    if get then Bind(cb) end
    return cb
end

function Widgets.Slider(parent, label, key, minV, maxV, step, width, fmt, tooltip)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 44)
    local title = Widgets.Label(holder, label, "GameFontNormal")
    title:SetPoint("TOPLEFT", 2, 0)
    local valueText = Widgets.Label(holder, "")
    valueText:SetPoint("TOPRIGHT", -2, 0)
    fmt = fmt or tostring
    local s = Template("Slider", holder, "BackdropTemplate") or CreateFrame("Slider", nil, holder)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(17)
    s:SetPoint("TOPLEFT", 0, -16)
    s:SetPoint("TOPRIGHT", 0, -16)
    if s.SetBackdrop then s:SetBackdrop(BACKDROP_SLIDER) end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local get, set = Accessor(key)
    local updating = false
    local function Value(v)
        v = math.max(minV, math.min(maxV, tonumber(v) or minV))
        return math.max(minV, math.min(maxV, minV + math.floor((v - minV) / step + 0.5) * step))
    end
    s:SetScript("OnValueChanged", ns.Safe(function(self, value)
        if updating then return end
        value = Value(value)
        updating = true
        self:SetValue(value)
        updating = false
        valueText:SetText(fmt(value))
        if set then set(value) end
        if holder.onChange then holder.onChange(value) end
    end))
    s:SetScript("OnMouseWheel", ns.Safe(function(self, delta)
        self:SetValue(Value(self:GetValue() + delta * step))
    end))
    function holder:Refresh()
        updating = true
        local v = Value(get and get() or s:GetValue())
        s:SetValue(v)
        valueText:SetText(fmt(v))
        updating = false
    end
    holder.slider, holder.valueText, holder.label = s, valueText, title
    Widgets.Tooltip(s, label, tooltip)
    Bind(holder)
    return holder
end

local function Placeholder(edit, text)
    local ph = edit.Instructions
    if type(ph) == "function" then ph = nil end
    if not ph and text then
        ph = Widgets.Label(edit, text, "GameFontDisableSmall")
        ph:SetPoint("LEFT", 1, 0)
    end
    if ph then
        ph:SetText(text or "")
        edit.placeholder = ph
        local function Refresh(self) ph:SetShown(self:GetText() == "") end
        edit:HookScript("OnTextChanged", Refresh)
        Refresh(edit)
    end
end

function Widgets.Box(parent, width, placeholder)
    local bg = Backdrop(parent, Widgets.BACKDROP_BOX)
    bg:SetSize(width, 26)
    if bg.SetBackdropBorderColor then bg:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end
    local edit = CreateFrame("EditBox", nil, bg)
    edit:SetPoint("TOPLEFT", 7, -4)
    edit:SetPoint("BOTTOMRIGHT", -7, 4)
    edit:SetFontObject(ChatFontNormal)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(80)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function(self)
        if bg.SetBackdropBorderColor then bg:SetBackdropBorderColor(1, 0.82, 0, 1) end
        self:HighlightText()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if bg.SetBackdropBorderColor then bg:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end
        self:HighlightText(0, 0)
    end)
    Placeholder(edit, placeholder)
    bg.edit = edit
    return bg
end

function Widgets.EditBox(parent, width, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 26)
    local edit = Template("EditBox", holder, opts.search and "SearchBoxTemplate" or "InputBoxInstructionsTemplate")
    if edit then
        edit:SetPoint("TOPLEFT", 7, -3)
        edit:SetPoint("BOTTOMRIGHT", -2, 3)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        edit.instructionText = opts.placeholder or ""
        if not opts.search and edit.Instructions then
            edit.Instructions:ClearAllPoints()
            edit.Instructions:SetPoint("TOPLEFT", 10, 0)
            edit.Instructions:SetPoint("BOTTOMRIGHT", -10, 0)
        end
        Placeholder(edit, opts.placeholder)
        if not opts.search and edit.searchIcon then edit.searchIcon:Hide() end
    else
        holder:Hide()
        holder = Widgets.Box(parent, width, opts.placeholder)
        edit = holder.edit
    end
    edit:SetMaxLetters(opts.maxLetters or 80)
    if edit.SetNumeric then edit:SetNumeric(opts.numeric and true or false) end
    holder.edit = edit
    return holder
end

function Widgets.TextArea(parent, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(300, 160)
    local scroll = Template("ScrollFrame", holder, "InputScrollFrameTemplate")
    local edit = scroll and scroll.EditBox
    if type(edit) == "function" then edit = nil end
    local native = edit ~= nil
    if not native then
        if scroll then scroll:Hide() end
        holder:Hide()
        holder = Backdrop(parent, Widgets.BACKDROP_BOX)
        holder:SetSize(300, 160)
        scroll = Template("ScrollFrame", holder, "UIPanelScrollFrameTemplate") or CreateFrame("ScrollFrame", nil, holder)
        edit = CreateFrame("EditBox", nil, scroll)
        scroll:SetScrollChild(edit)
        edit:SetPoint("TOPLEFT")
        edit.cursorOffset, edit.cursorHeight = 0, 0
        edit:SetScript("OnCursorChanged", function(self, x, y, w, h)
            if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, x, y, w, h) end
        end)
        edit:SetScript("OnUpdate", function(self, elapsed)
            if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, scroll) end
        end)
        edit:SetScript("OnTextChanged", function(self)
            if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, scroll) end
            if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        end)
        scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    end
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", native and -8 or -28, 8)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if native then
        scroll.hideCharCount = true
        if scroll.CharCount and type(scroll.CharCount) ~= "function" then scroll.CharCount:Hide() end
        if InputScrollFrame_SetInstructions then
            pcall(InputScrollFrame_SetInstructions, scroll, opts.placeholder or "")
        end
    end
    Placeholder(edit, opts.placeholder)
    local function Size()
        -- The native scrollbar sits inside its viewport; the fallback's
        -- scrollbar sits beside it in the reserved right margin.
        local width = math.max(1, holder:GetWidth() - (native and 34 or 36))
        edit:SetWidth(width)
        if edit.placeholder then edit.placeholder:SetWidth(width) end
    end
    holder:SetScript("OnSizeChanged", Size)
    Size()
    holder.scroll, holder.edit = scroll, edit
    return holder
end

function Widgets.Picker(parent, width, options, get, set)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 24)
    local prev = CreateFrame("Button", nil, holder)
    prev:SetSize(24, 24)
    prev:SetPoint("LEFT")
    prev:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prev:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prev:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local nextB = CreateFrame("Button", nil, holder)
    nextB:SetSize(24, 24)
    nextB:SetPoint("RIGHT")
    nextB:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextB:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextB:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local text = Widgets.Label(holder, "", "GameFontHighlightSmall")
    text:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    text:SetPoint("RIGHT", nextB, "LEFT", -2, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    local function Index()
        local cur = get()
        for i, o in ipairs(options) do
            if o.value == cur then return i end
        end
        return 1
    end
    function holder:Refresh()
        text:SetText(options[Index()] and options[Index()].text or "")
    end
    local function Step(delta)
        if #options == 0 then return end
        CheckSound()
        set(options[(Index() - 1 + delta) % #options + 1].value)
        holder:Refresh()
    end
    prev:SetScript("OnClick", ns.Safe(function() Step(-1) end))
    nextB:SetScript("OnClick", ns.Safe(function() Step(1) end))
    holder.prev, holder.next, holder.text = prev, nextB, text
    holder.prevButton, holder.nextButton = prev, nextB
    Bind(holder)
    return holder
end

function Widgets.Cycler(parent, label, key, options, width, tooltip)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 46)
    local title = Widgets.Label(holder, label, "GameFontNormal")
    title:SetPoint("TOPLEFT", 2, 0)
    local get, set = Accessor(key)
    local picker = Widgets.Picker(holder, width, options, get, set)
    picker:SetPoint("TOPLEFT", 0, -16)
    holder.prev, holder.next = picker.prev, picker.next
    holder.nextButton, holder.prevButton = picker.next, picker.prev
    Widgets.Tooltip(picker.prev, label, tooltip)
    Widgets.Tooltip(picker.next, label, tooltip)
    return holder
end

local function MenuRoot()
    local root = { items = {} }
    local function Item(kind, text, fn, isSelected, setSelected)
        local item = { kind = kind, text = text, fn = fn, isSelected = isSelected, setSelected = setSelected }
        root.items[#root.items + 1] = item
        return item
    end
    function root:CreateTitle(text) return Item("title", text) end
    function root:CreateDivider() return Item("divider") end
    function root:CreateButton(text, fn) return Item("button", text, fn) end
    function root:CreateRadio(text, isSelected, setSelected)
        return Item("radio", text, setSelected, isSelected, setSelected)
    end
    function root:CreateCheckbox(text, isSelected, setSelected)
        return Item("checkbox", text, setSelected, isSelected, setSelected)
    end
    return root
end

function Widgets.Dropdown(parent, width, opts)
    local dd = Template("DropdownButton", parent, "WowStyle1DropdownTemplate")
    if dd and dd.SetupMenu then
        local ok = pcall(dd.SetupMenu, dd, function(_, root) opts.menu(root) end)
        if ok then
            dd:SetSize(width, 24)
            function dd:Refresh()
                local text = opts.text()
                local success = self.OverrideText and pcall(self.OverrideText, self, text)
                if not success and self.SetText then pcall(self.SetText, self, text) end
            end
            Bind(dd)
            return dd
        end
    end
    if dd then dd:Hide() end
    local options, selected = {}, 1
    local picker = Widgets.Picker(parent, width, options, function() return selected end, function(i)
        local item = options[i] and options[i].item
        selected = i
        if item and item.fn then item.fn() end
    end)
    function picker:Refresh()
        local root = MenuRoot()
        opts.menu(root)
        self.menu = root
        wipe(options)
        -- Radio choices cycle; an action-only dropdown cycles its buttons.
        local kind = "button"
        for _, item in ipairs(root.items) do
            if item.kind == "radio" then kind = "radio"; break end
        end
        if kind == "radio" then selected = 1 end
        for _, item in ipairs(root.items) do
            if item.kind == kind then
                options[#options + 1] = { value = #options + 1, text = item.text, item = item }
                if item.isSelected and item.isSelected() then selected = #options end
            end
        end
        selected = math.max(1, math.min(#options, selected))
        self.text:SetText(opts.text())
    end
    picker:Refresh()
    return picker
end

function Widgets.Menu(owner, generator)
    if MenuUtil and MenuUtil.CreateContextMenu then
        local ok, menu = pcall(MenuUtil.CreateContextMenu, owner, function(_, root) generator(root) end)
        if ok then return menu end
    end
    local root = MenuRoot()
    generator(root)
    Widgets.lastMenu = root
    for _, item in ipairs(root.items) do
        if item.kind == "button" then
            if item.fn then ns.Call(item.fn) end
            break
        end
    end
    return root
end

function Widgets.List(parent, opts)
    local list = CreateFrame("Frame", nil, parent)
    local rowHeight = opts.rowHeight or 22
    list.rows, list.items, list.offset, list.visibleRows = {}, {}, 0, 0
    local scrollbar = CreateFrame("Slider", nil, list)
    scrollbar:SetWidth(14)
    scrollbar:SetPoint("TOPRIGHT", 0, -8)
    scrollbar:SetPoint("BOTTOMRIGHT", 0, 8)
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    scrollbar:SetValueStep(1)
    if scrollbar.SetObeyStepOnDrag then scrollbar:SetObeyStepOnDrag(true) end
    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(1, 1, 1, 0.06)
    track:SetAllPoints()
    local empty = Widgets.Label(list, opts.emptyText or "", "GameFontDisable")
    empty:SetPoint("TOPLEFT", 8, -8)
    empty:SetPoint("TOPRIGHT", -8, -8)
    empty:SetJustifyH("CENTER")
    list.scrollbar, list.emptyText = scrollbar, empty
    local updating = false
    function list:Refresh()
        self.visibleRows = math.max(0, math.floor(self:GetHeight() / rowHeight))
        local maxOffset = math.max(0, #self.items - self.visibleRows)
        self.offset = math.max(0, math.min(maxOffset, math.floor(self.offset)))
        local scrolling = maxOffset > 0 and self.visibleRows > 0
        updating = true
        scrollbar:SetMinMaxValues(0, maxOffset)
        scrollbar:SetValue(self.offset)
        scrollbar:SetShown(scrolling)
        updating = false
        empty:SetShown(#self.items == 0)
        for i = 1, self.visibleRows do
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Button", nil, self)
                row:SetHeight(rowHeight)
                row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row:SetScript("OnClick", ns.Safe(function(r, button)
                    if r.item ~= nil and opts.onClick then opts.onClick(r, r.item, button) end
                    if r.item ~= nil and button == "RightButton" and opts.onRightClick then opts.onRightClick(r, r.item) end
                end))
                row:SetScript("OnDoubleClick", ns.Safe(function(r, button)
                    if r.item ~= nil and button == "LeftButton" and opts.onDoubleClick then opts.onDoubleClick(r, r.item) end
                end))
                self.rows[i] = row
                if opts.rowInit then opts.rowInit(row) end
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", self, "TOPRIGHT", scrolling and -18 or 0, -(i - 1) * rowHeight)
            local index = self.offset + i
            local item = self.items[index]
            row.item, row.index, row.selected = item, index, item ~= nil and item == self.selected
            if item ~= nil and opts.rowUpdate then opts.rowUpdate(row, item, index, row.selected) end
            row:SetShown(item ~= nil)
        end
        for i = self.visibleRows + 1, #self.rows do
            local row = self.rows[i]
            row.item, row.index, row.selected = nil, nil, false
            row:Hide()
        end
    end
    function list:SetItems(items)
        self.items = items or {}
        self:Refresh()
    end
    function list:SetSelected(item)
        self.selected = item
        self:Refresh()
    end
    function list:GetSelected() return self.selected end
    function list:ScrollTo(index)
        index = math.max(1, math.min(#self.items, tonumber(index) or 1))
        if index <= self.offset then
            self.offset = index - 1
        elseif index > self.offset + self.visibleRows then
            self.offset = index - self.visibleRows
        end
        self:Refresh()
    end
    scrollbar:SetScript("OnValueChanged", ns.Safe(function(_, value)
        if not updating then list.offset = math.floor(value + 0.5); list:Refresh() end
    end))
    local function Wheel(_, delta)
        list.offset = list.offset - delta * 3
        list:Refresh()
    end
    list:EnableMouseWheel(true)
    scrollbar:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", ns.Safe(Wheel))
    scrollbar:SetScript("OnMouseWheel", ns.Safe(Wheel))
    list:SetScript("OnSizeChanged", ns.Safe(function() list:Refresh() end))
    list:Refresh()
    return list
end

function Widgets.Confirm(id, def)
    confirmations[id] = def
    if not StaticPopupDialogs then return end
    local dialog = StaticPopupDialogs[id]
    if not dialog then
        dialog = {
            timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
            OnAccept = function(...) local fn = confirmations[id].onAccept; if fn then ns.Call(fn, ...) end end,
            OnAlt = function(...) local fn = confirmations[id].onAlt; if fn then ns.Call(fn, ...) end end,
            OnCancel = function(...) local fn = confirmations[id].onCancel; if fn then ns.Call(fn, ...) end end,
        }
        StaticPopupDialogs[id] = dialog
    end
    dialog.text, dialog.button1, dialog.button2, dialog.button3 = def.text, def.button1, def.button2, def.button3
end

function Widgets.Ask(id, ...)
    local def = confirmations[id]
    if not def then return end
    if def.sound and PlaySound then PlaySound(def.sound) end
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[id] then
        local ok, popup = pcall(StaticPopup_Show, id, ...)
        if ok then return popup end
    end
    if def.onAccept then ns.Call(def.onAccept) end
end

function Widgets.Percent(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
function Widgets.Yards(v) return ns.Geo.FormatDistance(v) end

function Widgets.Refresh()
    for i = 1, #refreshers do ns.Call(refreshers[i]) end
end
ns.On("SETTING_CHANGED", Widgets.Refresh)
