-- One panel for the tab roots and their pages. Widgets stay independent of
-- the shell so either module can load first.
local _, ns = ...
local L = ns.L

local Window = {}
ns.Window = Window
Window.tabs = {}

local WIDTH, HEIGHT = 640, 540
local BACKDROP_DIALOG = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local BACKDROP_BOX = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local frame, current, ordered
local updateElapsed = 0

local function InCombat()
    if ns.InCombat then
        return ns.InCombat()
    end
    return InCombatLockdown and InCombatLockdown() or false
end

local function Button(parent, text, magic)
    local ok, b = pcall(CreateFrame, "Button", nil, parent,
        magic and "MagicButtonTemplate" or "UIPanelButtonTemplate")
    if not ok then
        b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    end
    b:SetText(text)
    b:SetSize(math.max(80, b:GetFontString() and b:GetFontString():GetStringWidth() + 24 or 100), 22)
    return b
end

local function Tooltip(button, title, body)
    button:SetScript("OnEnter", ns.Safe(function(self)
        if not GameTooltip then return end
        local text = body
        if type(body) == "function" then text = body() end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        if text and text ~= "" then
            GameTooltip:AddLine(text, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end))
    button:SetScript("OnLeave", ns.Safe(function()
        if GameTooltip then GameTooltip:Hide() end
    end))
end

local function FillContent(content)
    content:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 6, -6)
    content:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -6, 6)
end

local function TopPage(tab)
    return tab.pages[#tab.pages]
end

local function HidePage(page)
    if page.active then
        page.active = false
        if page.spec.onHide then ns.Call(page.spec.onHide) end
    end
    page.container:Hide()
end

local function ShowContent(tab)
    local page = TopPage(tab)
    tab.content:SetShown(not page)
    if page then
        page.container:Show()
        if Window.IsShown() and current == tab.spec.key and not page.active then
            page.active = true
            if page.spec.onShow then ns.Call(page.spec.onShow) end
        end
    end
end

local function Deactivate(tab)
    if not tab then return end
    local page = TopPage(tab)
    if page then HidePage(page) end
    tab.content:Hide()
    if tab.active then
        tab.active = false
        if tab.spec.onHide then ns.Call(tab.spec.onHide) end
    end
end

local function Activate(tab)
    if not tab or not Window.IsShown() then return end
    tab.active = true
    if tab.spec.onShow then ns.Call(tab.spec.onShow) end
    ShowContent(tab)
end

local function Preview(on)
    if ns.Arrow and ns.Arrow.SetPreview then
        ns.Arrow.SetPreview(on)
    end
end

local function SettingsAvailable()
    return ns.Options and ns.Options.IsAvailable and ns.Options.IsAvailable()
end

local function RefreshButtons()
    frame.settings:SetEnabled(SettingsAvailable() and true or false)
    for _, tab in ipairs(ordered) do
        for _, b in ipairs(tab.buttons) do
            b:SetShown(tab.spec.key == current)
        end
    end
end

local function BuildTabs()
    ordered = {}
    for _, tab in pairs(Window.tabs) do ordered[#ordered + 1] = tab end
    table.sort(ordered, function(a, b)
        local ao, bo = a.spec.order or 0, b.spec.order or 0
        if ao == bo then return a.spec.key < b.spec.key end
        return ao < bo
    end)
    local previous
    for i, tab in ipairs(ordered) do
        local b = frame.Tabs[i]
        if not b then
            local ok
            if PanelTemplates_SetNumTabs and PanelTemplates_SetTab and PanelTemplates_TabResize then
                ok, b = pcall(CreateFrame, "Button", "WaypointTrackerFrameTab" .. i, frame, "PanelTabButtonTemplate")
            end
            if not ok then
                b = CreateFrame("Button", "WaypointTrackerFrameTab" .. i, frame)
                local text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                text:SetPoint("CENTER")
                b:SetFontString(text)
                b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                b.bar = b:CreateTexture(nil, "ARTWORK")
                b.bar:SetColorTexture(1, 0.82, 0, 0.9)
                b.bar:SetHeight(2)
                b.bar:SetPoint("BOTTOMLEFT", 4, 0)
                b.bar:SetPoint("BOTTOMRIGHT", -4, 0)
            end
            frame.Tabs[i] = b
        end
        b:SetID(i)
        b:SetText(tab.spec.title)
        if b.bar then
            b:GetFontString():SetText(tab.spec.title)
            b:SetSize(math.max(70, b:GetFontString():GetStringWidth() + 20), 22)
        elseif PanelTemplates_TabResize then
            pcall(PanelTemplates_TabResize, b, 0)
        end
        b:ClearAllPoints()
        if not previous then
            b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        elseif b.bar or previous.bar then
            b:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        end
        -- Blizzard anchors the remaining native tabs in SetNumTabs.
        b.key = tab.spec.key
        b:SetScript("OnClick", ns.Safe(function()
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
            Window.ShowTab(tab.spec.key)
        end))
        tab.button, tab.index = b, i
        previous = b
        if not tab.content then
            tab.content = CreateFrame("Frame", nil, frame.Inset)
            FillContent(tab.content)
            tab.content:Hide()
            tab.buttons = {}
            local previousButton
            for _, name in ipairs({ "leftButton", "leftButton2" }) do
                local spec = tab.spec[name]
                if spec then
                    local left = Button(frame, spec.text, true)
                    if previousButton then
                        left:SetPoint("LEFT", previousButton, "RIGHT", 4, 0)
                    else
                        left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
                    end
                    left:SetScript("OnClick", ns.Safe(function()
                        if spec.onClick then spec.onClick() end
                    end))
                    Tooltip(left, spec.text, spec.tooltip)
                    left:Hide()
                    tab.buttons[#tab.buttons + 1] = left
                    tab[name] = left
                    previousButton = left
                end
            end
        end
    end
    if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, frame, #ordered) end
    -- That helper also anchors plain tabs when native art is unavailable.
    -- Restore their manual chain so it remains their only horizontal anchor.
    for i = 2, #ordered do
        local b, previous = ordered[i].button, ordered[i - 1].button
        if b.bar or previous.bar then
            b:ClearAllPoints()
            b:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        end
    end
end

local function Build()
    if frame then return end
    local ok
    ok, frame = pcall(CreateFrame, "Frame", "WaypointTrackerFrame", UIParent, "ButtonFrameTemplate")
    if not ok then
        frame = CreateFrame("Frame", "WaypointTrackerFrame", UIParent, "BackdropTemplate")
        frame:SetBackdrop(BACKDROP_DIALOG)
        frame:SetBackdropColor(0, 0, 0, 1)
    end
    Window.frame = frame
    frame:SetSize(WIDTH, HEIGHT)
    frame:EnableMouse(true)
    frame:Hide()
    frame.TitleText = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if not frame.TitleText then
        frame.TitleText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        frame.TitleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 56, -18)
        frame.TitleText:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
        frame.TitleText:SetJustifyH("LEFT")
    end
    if not (frame.SetTitle and pcall(frame.SetTitle, frame, L.ADDON_TITLE)) then
        frame.TitleText:SetText(L.ADDON_TITLE)
    end
    frame.portrait = frame.portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
    if not (frame.SetPortraitToAsset and pcall(frame.SetPortraitToAsset, frame, ns.MEDIA .. "Icon")) then
        if not frame.portrait then
            frame.portrait = frame:CreateTexture(nil, "ARTWORK")
            frame.portrait:SetSize(32, 32)
            frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -12)
        end
        frame.portrait:SetTexture(ns.MEDIA .. "Icon")
    end
    if ButtonFrameTemplate_ShowButtonBar then pcall(ButtonFrameTemplate_ShowButtonBar, frame) end
    if not frame.CloseButton then
        frame.CloseButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        frame.CloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    end
    frame.CloseButton:SetScript("OnClick", ns.Safe(Window.Hide))
    if not frame.Inset then
        frame.Inset = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60)
        frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 26)
        frame.Inset:SetBackdrop(BACKDROP_BOX)
        frame.Inset:SetBackdropColor(0, 0, 0, 0.5)
    end
    tinsert(UISpecialFrames, "WaypointTrackerFrame")
    local attrs = { area = "left", pushable = 5, whileDead = 1, width = WIDTH, checkFit = 1 }
    if RegisterUIPanel then
        pcall(RegisterUIPanel, frame, attrs)
    elseif UIPanelWindows then
        UIPanelWindows["WaypointTrackerFrame"] = attrs
    end
    frame.settings = Button(frame, L.SETTINGS, true)
    frame.settings:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4)
    frame.settings:SetScript("OnClick", ns.Safe(function()
        if SettingsAvailable() and ns.Options.Open then ns.Options.Open() end
    end))
    if frame.settings.SetMotionScriptsWhileDisabled then
        pcall(frame.settings.SetMotionScriptsWhileDisabled, frame.settings, true)
    end
    Tooltip(frame.settings, L.SETTINGS, function()
        if not SettingsAvailable() then return L.SETTINGS_UNAVAILABLE end
    end)
    frame.status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -32)
    frame.status:SetPoint("RIGHT", frame, "RIGHT", -34, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)
    frame.status:SetText("")
    frame.Tabs = {}
    BuildTabs()
    frame:SetScript("OnShow", ns.Safe(function()
        if not frame.rehoming and PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
        updateElapsed = 0
        RefreshButtons()
        if not frame.rehoming then ns.Fire("UI_SHOWN") end
        Activate(Window.tabs[current])
        Preview(current == "waypoints")
    end))
    frame:SetScript("OnHide", ns.Safe(function()
        if frame.rehoming then return end
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
        frame.shownDirectly = nil
        Deactivate(Window.tabs[current])
        for key in pairs(Window.tabs) do Window.PopAll(key) end
        updateElapsed = 0
        Preview(false)
        if GameTooltip then GameTooltip:Hide() end
        ns.Fire("UI_HIDDEN")
    end))
    frame:SetScript("OnUpdate", ns.Safe(function(_, elapsed)
        if not Window.IsShown() then return end
        updateElapsed = updateElapsed + elapsed
        if updateElapsed < 0.5 then return end
        local dt = updateElapsed
        updateElapsed = 0
        RefreshButtons()
        local tab = Window.tabs[current]
        if tab and tab.spec.onUpdate then ns.Call(tab.spec.onUpdate, dt) end
    end))
end

function Window.RegisterTab(spec)
    Window.tabs[spec.key] = { spec = spec, pages = {}, pageCache = {} }
    if frame then
        BuildTabs()
        RefreshButtons()
    end
end

function Window.IsShown()
    return frame and frame:IsShown() or false
end

function Window.GetTab()
    return current
end

function Window.SetStatus(text, good)
    if not frame then return end
    frame.status:SetText(text or "")
    if good == "info" then
        frame.status:SetTextColor(1, 1, 1)
    elseif good then
        frame.status:SetTextColor(0.3, 1, 0.3)
    else
        frame.status:SetTextColor(1, 0.35, 0.3)
    end
end

function Window.ShowTab(key)
    Build()
    local tab = Window.tabs[key]
    if not tab then
        tab = Window.tabs.waypoints or ordered[1]
    end
    if not tab then return end
    key = tab.spec.key
    local changed = current ~= key
    if changed then
        Deactivate(Window.tabs[current])
        Window.SetStatus("")
        updateElapsed = 0
    end
    current = key
    if not tab.built then
        tab.built = true
        if tab.spec.build then ns.Call(tab.spec.build, tab.content) end
    end
    if ns.settings then ns.settings.uiLastTab = key end
    if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, frame, tab.index) end
    for _, other in ipairs(ordered) do
        if other.button.bar then other.button.bar:SetShown(other == tab) end
    end
    RefreshButtons()
    if Window.IsShown() then
        if changed then Activate(tab) else ShowContent(tab) end
        Preview(key == "waypoints")
    else
        ShowContent(tab)
    end
    if changed then ns.Fire("UI_TAB_SHOWN", key) end
end

function Window.Show(key)
    Build()
    Window.ShowTab(key or ns.Get("uiLastTab"))
    if ShowUIPanel and not InCombat() then
        pcall(ShowUIPanel, frame)
        return frame:IsShown()
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    frame.shownDirectly = true
    frame:Show()
    return true
end

function Window.Hide()
    if not frame then return end
    if HideUIPanel and not InCombat() then
        if pcall(HideUIPanel, frame) and not frame:IsShown() then return end
    end
    frame:Hide()
end

function Window.Toggle(key)
    if Window.IsShown() then
        if not key or key == current then Window.Hide() else Window.ShowTab(key) end
    else
        Window.Show(key)
    end
end

-- The returned frame is the page body below the header. Its .header,
-- .back and .title expose the shell-owned chrome; CurrentPage returns spec.
function Window.PushPage(key, spec)
    Build()
    local tab = Window.tabs[key]
    if not tab then return end
    local previous = TopPage(tab)
    if previous then HidePage(previous) end
    tab.content:Hide()
    local cached = spec.key and tab.pageCache[spec.key]
    if cached then
        -- A stacked page owns its draft and callbacks until it is popped.
        -- Nested pages with the same key need an independent frame tree.
        for _, page in ipairs(tab.pages) do
            if page == cached then cached = nil; break end
        end
    end
    if cached then
        cached.spec = spec
        cached.frame.title:SetText(spec.title)
        tab.pages[#tab.pages + 1] = cached
        if spec.onReuse then ns.Call(spec.onReuse, cached.frame) end
        if key == current then ShowContent(tab) end
        return cached.frame
    end
    local container = CreateFrame("Frame", nil, frame.Inset)
    FillContent(container)
    container:Hide()
    local header = CreateFrame("Frame", nil, container)
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    header:SetHeight(30)
    local back = Button(header, "< " .. L.BACK)
    back:SetPoint("LEFT", header, "LEFT", 0, 0)
    back:SetScript("OnClick", ns.Safe(function() Window.PopPage(key) end))
    Tooltip(back, L.BACK)
    local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", back, "RIGHT", 12, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText(spec.title)
    local body = CreateFrame("Frame", nil, container)
    body:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -36)
    body:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    body.header, body.back, body.title = header, back, title
    local page = { spec = spec, frame = body, container = container }
    tab.pages[#tab.pages + 1] = page
    if spec.key and not tab.pageCache[spec.key] then tab.pageCache[spec.key] = page end
    if spec.build then ns.Call(spec.build, body) end
    if key == current then ShowContent(tab) end
    return body
end

function Window.CurrentPage(key)
    local tab = Window.tabs[key or current]
    local page = tab and TopPage(tab)
    return page and page.spec or nil
end

function Window.PopPage(key)
    local tab = Window.tabs[key or current]
    if not tab or #tab.pages == 0 then return end
    HidePage(table.remove(tab.pages))
    if tab.spec.key == current then ShowContent(tab) end
end

function Window.PopAll(key)
    local tab = Window.tabs[key or current]
    if not tab then return end
    while #tab.pages > 0 do HidePage(table.remove(tab.pages)) end
    if tab.spec.key == current then ShowContent(tab) end
end

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if frame and frame.shownDirectly and frame:IsShown() and ShowUIPanel and not InCombat() then
        -- Hand off ownership without closing pages or discarding their drafts.
        frame.rehoming = true
        frame:Hide()
        frame.shownDirectly = nil
        pcall(ShowUIPanel, frame)
        frame.rehoming = nil
        if not frame:IsShown() then
            -- A refused panel really is closed; run the deferred cleanup once.
            frame:GetScript("OnHide")(frame)
        end
    end
end)

function WaypointTracker_ToggleWindow()
    Window.Toggle()
end

function WaypointTracker_ToggleFind()
    Window.Toggle("find")
end

function WaypointTracker_ToggleRoutes()
    Window.Toggle("routes")
end
