local _, ns = ...
local L, W = ns.L, ns.Widgets

local Options = {}
ns.Options = Options
Options.categories = {}
local root, registered = nil, {}
local canvasRows, canvasLayout
local PREFIX = "WAYPOINTTRACKER_"
local CATEGORY_NAMES = {
    { "arrow", L.ARROW_HEADER }, { "maps", L.MAPS_HEADER },
    { "routes", L.ROUTES_TITLE }, { "treasure", L.TREASURE_HEADER },
    { "find", L.SETTINGS_FIND_SHARING },
}

local function CombatBlocked()
    if ns.InCombat() then
        ns.Print(L.IN_COMBAT_NO_PANELS, true)
        return true
    end
    return false
end

local function CloseSettings()
    if not SettingsPanel or ns.InCombat() then return end
    if HideUIPanel then
        if pcall(HideUIPanel, SettingsPanel) then return end
    end
    if SettingsPanel.Close and pcall(SettingsPanel.Close, SettingsPanel, true) then return end
    SettingsPanel:Hide()
end

local function OpenWindow()
    if CombatBlocked() then return end
    CloseSettings()
    if ns.Window and ns.Window.Show then ns.Window.Show() end
end

local function EnterEditMode()
    if CombatBlocked() then return end
    CloseSettings()
    if ns.EditMode and ns.EditMode.Enter then
        local ok, reason = ns.EditMode.Enter()
        if not ok then ns.Print(reason == "combat" and L.IN_COMBAT_NO_PANELS or L.EDIT_MODE_HINT, true) end
    elseif ns.Arrow and ns.Arrow.SetMoving then
        ns.Arrow.SetMoving(true)
    end
end

local function KeybindingsCategoryID()
    if Settings and Settings.KEYBINDINGS_CATEGORY_ID then return Settings.KEYBINDINGS_CATEGORY_ID end
    local category = SettingsPanel and SettingsPanel.keybindingsCategory
    if category and category.GetID then
        local ok, id = pcall(category.GetID, category)
        if ok then return id end
    end
end

local function OpenBindings()
    if CombatBlocked() then return end
    local id = KeybindingsCategoryID()
    if id and Settings and Settings.OpenToCategory then pcall(Settings.OpenToCategory, id) end
end

local function Reset()
    W.Confirm("WAYPOINTTRACKER_RESET", {
        text = L.RESET_CONFIRM, button1 = L.YES, button2 = L.NO, onAccept = ns.ResetSettings,
    })
    W.Ask("WAYPOINTTRACKER_RESET")
end

local function HasColourPicker()
    return ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow and ColorPickerFrame.GetColorRGB
end

local function OpenColourPicker()
    if not HasColourPicker() then return end
    local c = ns.Get("singleColor")
    local prev = { r = c.r, g = c.g, b = c.b }
    pcall(ColorPickerFrame.SetupColorPickerAndShow, ColorPickerFrame, {
        r = c.r, g = c.g, b = c.b, hasOpacity = false,
        swatchFunc = ns.Safe(function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ns.Set("singleColor", { r = r, g = g, b = b })
        end),
        cancelFunc = ns.Safe(function() ns.Set("singleColor", prev) end),
    })
end

local function AddInitializer(cat, init)
    if not init then return end
    if SettingsPanel and SettingsPanel.GetLayout then
        local ok, layout = pcall(SettingsPanel.GetLayout, SettingsPanel, cat)
        if ok and layout and layout.AddInitializer and pcall(layout.AddInitializer, layout, init) then return init end
    end
    if Settings.RegisterInitializer then pcall(Settings.RegisterInitializer, cat, init) end
    return init
end

local Native = {}
function Native.Header(cat, text)
    if CreateSettingsListSectionHeaderInitializer then
        local ok, init = pcall(CreateSettingsListSectionHeaderInitializer, text)
        if ok then return AddInitializer(cat, init) end
    end
end

function Native.ButtonRow(cat, name, text, fn, tooltip)
    if CreateSettingsButtonInitializer then
        local ok, init = pcall(CreateSettingsButtonInitializer, name, text, ns.Safe(fn), tooltip, true)
        if ok then return AddInitializer(cat, init) end
    end
end

local function Proxy(cat, key, valueType, label, get, set)
    local setting = Settings.RegisterProxySetting(cat, PREFIX .. key, valueType, label, ns.defaults[key], get, set)
    registered[key] = true
    return setting
end

function Native.Bool(cat, key, label, tooltip)
    local setting = Proxy(cat, key, Settings.VarType.Boolean, label,
        function() return ns.Get(key) and true or false end,
        function(v) ns.Set(key, v and true or false) end)
    return Settings.CreateCheckbox(cat, setting, tooltip)
end

function Native.Num(cat, key, label, minV, maxV, step, format, tooltip)
    local setting = Proxy(cat, key, Settings.VarType.Number, label,
        function() return ns.Get(key) end, function(v) ns.Set(key, v) end)
    local options = Settings.CreateSliderOptions(minV, maxV, step)
    local right = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
        and MinimalSliderWithSteppersMixin.Label.Right
    if options.SetLabelFormatter and right then pcall(options.SetLabelFormatter, options, right, format) end
    return Settings.CreateSlider(cat, setting, options, tooltip)
end

function Native.Choice(cat, key, label, options, tooltip)
    local setting = Proxy(cat, key, Settings.VarType.String, label,
        function() return ns.Get(key) end, function(v) ns.Set(key, v) end)
    return Settings.CreateDropdown(cat, setting, function()
        local c = Settings.CreateControlTextContainer()
        for _, o in ipairs(options) do c:Add(o.value, o.text) end
        return c:GetData()
    end, tooltip)
end

function Native.Parent(init, parent, predicate, hide)
    if init and parent and init.SetParentInitializer then pcall(init.SetParentInitializer, init, parent, predicate) end
    if hide and init and init.AddShownPredicate then pcall(init.AddShownPredicate, init, predicate) end
end

-- Both layouts use this list, so the fallback has every setting too.
local function Populate(api, categories)
    local cat = categories.root
    api.ButtonRow(cat, L.OPEN_WINDOW, L.OPEN_WINDOW, OpenWindow,
        L.OPTIONS_PANEL_DESC .. "\n\n" .. L.VERSION_FMT:format(ns.version))
    api.ButtonRow(cat, L.OPEN_EDIT_MODE, L.OPEN_EDIT_MODE_BUTTON, EnterEditMode, L.OPEN_EDIT_MODE_DESC)
    -- Blizzard may register the bindings category after our login handler; resolve it on click.
    api.ButtonRow(cat, L.OPEN_KEYBINDINGS, L.OPEN_KEYBINDINGS, OpenBindings, L.OPEN_KEYBINDINGS_DESC)
    api.Header(cat, L.GENERAL_HEADER)
    api.Bool(cat, "arrowShown", L.SHOW_ARROW, L.SHOW_ARROW_DESC)
    api.Bool(cat, "autoClosest", L.AUTO_CLOSEST, L.AUTO_CLOSEST_DESC)
    api.Bool(cat, "corpseWaypoint", L.CORPSE_WAYPOINT, L.CORPSE_WAYPOINT_DESC)
    api.Bool(cat, "persist", L.PERSIST, L.PERSIST_DESC)
    api.Bool(cat, "minimapButton", L.MINIMAP_BUTTON, L.MINIMAP_BUTTON_DESC)
    api.Bool(cat, "chatMessages", L.CHAT_MESSAGES, L.CHAT_MESSAGES_DESC)
    api.Bool(cat, "useMetres", L.USE_METRES, L.USE_METRES_DESC)
    api.Bool(cat, "addonWaypoints", L.ADDON_WAYPOINTS, L.ADDON_WAYPOINTS_DESC)
    api.Bool(cat, "blizzardPin", L.BLIZZARD_PIN, L.BLIZZARD_PIN_DESC)
    api.ButtonRow(cat, L.RESET_SETTINGS, L.RESET_SETTINGS, Reset, L.RESET_SETTINGS_DESC)

    cat = categories.arrow
    api.Header(cat, L.ARROW_EXTRAS_HEADER)
    api.Num(cat, "arrowScale", L.ARROW_SIZE, 0.5, 2, 0.05, W.Percent, L.ARROW_SIZE_DESC)
    api.Num(cat, "arrowAlpha", L.ARROW_TRANSPARENCY, 0.2, 1, 0.05, W.Percent, L.ARROW_TRANSPARENCY_DESC)
    local colour = api.Choice(cat, "colorMode", L.COLOUR, {
        { value = "distance", text = L.COLOUR_DISTANCE }, { value = "direction", text = L.COLOUR_DIRECTION },
        { value = "single", text = L.COLOUR_SINGLE },
    }, L.COLOUR_DESC)
    if HasColourPicker() then
        local pick = api.ButtonRow(cat, L.PICK_COLOUR, L.PICK_COLOUR, OpenColourPicker, L.PICK_COLOUR_DESC)
        api.Parent(pick, colour, function() return ns.Get("colorMode") == "single" end, true)
    end
    api.Bool(cat, "fadeOnCourse", L.FADE_ON_COURSE, L.FADE_ON_COURSE_DESC)
    api.Bool(cat, "hideInCombat", L.HIDE_IN_COMBAT, L.HIDE_IN_COMBAT_DESC)
    api.Bool(cat, "hideOnTaxi", L.HIDE_ON_TAXI, L.HIDE_ON_TAXI_DESC)
    api.Header(cat, L.TEXT_HEADER)
    api.Num(cat, "textScale", L.TEXT_SIZE, 0.5, 2, 0.05, W.Percent, L.TEXT_SIZE_DESC)
    api.Num(cat, "textAlpha", L.TEXT_VISIBILITY, 0.2, 1, 0.05, W.Percent, L.TEXT_VISIBILITY_DESC)
    api.Bool(cat, "showTitle", L.SHOW_TITLE, L.SHOW_TITLE_DESC)
    api.Bool(cat, "showDistance", L.SHOW_DISTANCE, L.SHOW_DISTANCE_DESC)
    api.Bool(cat, "showETA", L.SHOW_ETA, L.SHOW_ETA_DESC)
    api.Bool(cat, "textSeparate", L.TEXT_SEPARATE, L.TEXT_SEPARATE_DESC)
    api.Header(cat, L.ARRIVAL_HEADER)
    api.Num(cat, "arrivalDistance", L.ARRIVAL_DISTANCE, 3, 50, 1, W.Yards, L.ARRIVAL_DISTANCE_DESC)
    api.Bool(cat, "autoClear", L.AUTO_CLEAR, L.AUTO_CLEAR_DESC)
    api.Bool(cat, "arrivalSound", L.ARRIVAL_SOUND, L.ARRIVAL_SOUND_DESC)
    api.Bool(cat, "autoNext", L.AUTO_NEXT, L.AUTO_NEXT_DESC)

    cat = categories.maps
    api.Header(cat, L.SETTINGS_WORLD_MAP_HEADER)
    api.Bool(cat, "worldPins", L.WORLD_PINS, L.WORLD_PINS_DESC)
    api.Bool(cat, "worldCoords", L.WORLD_COORDS, L.WORLD_COORDS_DESC)
    api.Bool(cat, "mapClick", L.MAP_CLICK, L.MAP_CLICK_DESC)
    api.Bool(cat, "followMapPins", L.FOLLOW_MAP_PINS, L.FOLLOW_MAP_PINS_DESC)
    api.Bool(cat, "followQuest", L.FOLLOW_QUEST, L.FOLLOW_QUEST_DESC)
    api.Header(cat, L.SETTINGS_MINIMAP_HEADER)
    api.Bool(cat, "minimapPins", L.MINIMAP_PINS, L.MINIMAP_PINS_DESC)
    api.Bool(cat, "minimapEdge", L.MINIMAP_EDGE, L.MINIMAP_EDGE_DESC)
    api.Header(cat, L.SETTINGS_COORDS_HEADER)
    api.Bool(cat, "coordsBox", L.COORDS_BOX, L.COORDS_BOX_DESC)

    cat = categories.routes
    api.Header(cat, L.ROUTES_TITLE)
    api.Choice(cat, "routeApply", L.ROUTE_APPLY_OPTION, {
        { value = "ask", text = L.ROUTE_APPLY_ASK }, { value = "replace", text = L.ROUTE_APPLY_REPLACE },
        { value = "add", text = L.ROUTE_APPLY_ADD },
    }, L.ROUTE_APPLY_OPTION_DESC)
    api.Bool(cat, "routeSharing", L.ROUTES_SHARING, L.ROUTES_SHARING_DESC)
    api.Bool(cat, "routeLowRated", L.ROUTES_LOW_RATED, L.ROUTES_LOW_RATED_DESC)
    api.Header(cat, L.TRAVEL_HEADER)
    api.Bool(cat, "realRoutes", L.REAL_ROUTES, L.REAL_ROUTES_DESC)
    api.Bool(cat, "travelFlights", L.TRAVEL_FLIGHTS, L.TRAVEL_FLIGHTS_DESC)
    api.Bool(cat, "travelBoats", L.TRAVEL_BOATS, L.TRAVEL_BOATS_DESC)
    api.Bool(cat, "travelHearth", L.TRAVEL_HEARTH_OPTION, L.TRAVEL_HEARTH_DESC)
    api.Bool(cat, "travelMapLine", L.TRAVEL_MAP_LINE, L.TRAVEL_MAP_LINE_DESC)
    api.Bool(cat, "travelTrails", L.TRAVEL_TRAILS, L.TRAVEL_TRAILS_DESC)
    api.Bool(cat, "travelShare", L.TRAVEL_SHARE, L.TRAVEL_SHARE_DESC)

    cat = categories.treasure
    local hunt = api.Bool(cat, "treasureHunt", L.TREASURE_HUNT, L.TREASURE_HUNT_DESC)
    for _, o in ipairs({
        { "treasureChests", L.TREASURE_CHESTS, L.TREASURE_CHESTS_DESC },
        { "treasureRares", L.TREASURE_RARES, L.TREASURE_RARES_DESC },
        { "treasureOther", L.TREASURE_OTHER, L.TREASURE_OTHER_DESC },
        { "treasureKnownSpots", L.TREASURE_KNOWN, L.TREASURE_KNOWN_DESC },
        { "treasurePing", L.TREASURE_PING, L.TREASURE_PING_DESC },
        { "treasureFocus", L.TREASURE_FOCUS, L.TREASURE_FOCUS_DESC },
    }) do
        api.Parent(api.Bool(cat, o[1], o[2], o[3]), hunt, function() return ns.Get("treasureHunt") end)
    end

    cat = categories.find
    api.Header(cat, L.SETTINGS_FIND_HEADER)
    api.Bool(cat, "learn", L.LEARN, L.LEARN_DESC)
    api.Bool(cat, "findFaction", L.MY_FACTION_ONLY, L.MY_FACTION_ONLY_DESC)
    api.Bool(cat, "findThisZone", L.THIS_ZONE_ONLY, L.THIS_ZONE_ONLY_DESC)
    api.Header(cat, L.SETTINGS_SHARING_HEADER)
    api.Bool(cat, "sharePrefix", L.SHARE_PREFIX, L.SHARE_PREFIX_DESC)
end

local function Build()
    local category = Settings.RegisterVerticalLayoutCategory(L.ADDON_TITLE)
    local categories = { root = category }
    for _, o in ipairs(CATEGORY_NAMES) do
        categories[o[1]] = Settings.RegisterVerticalLayoutSubcategory(category, o[2])
    end
    Populate(Native, categories)
    Settings.RegisterAddOnCategory(category)
    root, Options.categoryID = category, category:GetID()
    for _, o in ipairs(CATEGORY_NAMES) do Options.categories[o[1]] = categories[o[1]] end
end

local function BuildCanvas()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    local title = W.Label(panel, L.ADDON_TITLE, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    if not ok then scroll = CreateFrame("ScrollFrame", nil, panel) end
    scroll:SetPoint("TOPLEFT", 16, -52)
    scroll:SetPoint("BOTTOMRIGHT", -36, 16)
    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    canvasRows = {}
    local controls, categories, names, api = {}, { root = "root" }, {}, {}
    local current
    local function Row(widget, height, key, label)
        local row = { widget = widget, height = height, key = key, label = label }
        canvasRows[#canvasRows + 1] = row
        if key then controls[key] = widget end
        return row
    end
    function api.Header(cat, text)
        if current ~= cat then
            current = cat
            if cat ~= "root" and text ~= names[cat] then Row(W.Header(content, names[cat]), 36) end
        end
        return Row(W.Header(content, text), 36)
    end
    function api.Bool(cat, key, label, tooltip)
        if current ~= cat then api.Header(cat, names[cat]) end
        local cb = W.Check(content, label, key, tooltip)
        cb.label:ClearAllPoints()
        cb.label:SetPoint("TOPLEFT", cb, "TOPRIGHT", 2, -4)
        return Row(cb, 28, key)
    end
    function api.Num(cat, key, label, minV, maxV, step, format, tooltip)
        return Row(W.Slider(content, label, key, minV, maxV, step, 320, format, tooltip), 54, key)
    end
    function api.Choice(cat, key, label, options, tooltip)
        local holder = CreateFrame("Frame", nil, content)
        local text = W.Label(holder, label, "GameFontNormal")
        text:SetPoint("TOPLEFT", 2, 0)
        local dd = W.Dropdown(holder, 320, {
            text = function()
                for _, o in ipairs(options) do if ns.Get(key) == o.value then return o.text end end
                return ""
            end,
            menu = function(menu)
                for _, o in ipairs(options) do
                    menu:CreateRadio(o.text, function() return ns.Get(key) == o.value end, function() ns.Set(key, o.value) end)
                end
            end,
        })
        dd:SetPoint("TOPLEFT", 0, -22)
        W.Tooltip(dd, label, tooltip)
        holder.dropdown = dd
        return Row(holder, 56, key, text)
    end
    function api.ButtonRow(cat, name, text, fn, tooltip)
        local holder = CreateFrame("Frame", nil, content)
        local label = W.Label(holder, name)
        label:SetPoint("TOPLEFT", 2, 0)
        local button = W.Button(holder, text, math.max(160, #text * 7 + 24))
        button:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
        button:SetScript("OnClick", ns.Safe(fn))
        W.Tooltip(button, text, tooltip)
        holder.button = button
        return Row(holder, 64, nil, label)
    end
    function api.Parent(row, parent, predicate, hide)
        row.predicate, row.hide = predicate, hide
    end
    for _, o in ipairs(CATEGORY_NAMES) do categories[o[1]], names[o[1]] = o[1], o[2] end
    Populate(api, categories)
    canvasLayout = function()
        local width = math.max(240, scroll:GetWidth())
        content:SetWidth(width)
        local y = 4
        for _, row in ipairs(canvasRows) do
            local enabled = not row.predicate or row.predicate()
            local visible = not row.hide or enabled
            local widget = row.widget
            widget:SetShown(visible)
            if visible then
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                local height = row.height
                if row.label then
                    row.label:SetWidth(width - 8)
                    height = math.max(height, row.label:GetStringHeight() + (widget.button and 36 or 34))
                    if widget.dropdown then
                        widget.dropdown:SetWidth(math.min(width, 320))
                        widget.dropdown:ClearAllPoints()
                        widget.dropdown:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, -row.label:GetStringHeight() - 8)
                    end
                end
                if row.key and type(ns.defaults[row.key]) == "boolean" then
                    widget.label:SetWidth(width - 34)
                    widget.label:SetWordWrap(true)
                    height = math.max(height, widget.label:GetStringHeight() + 8)
                    widget:SetHitRectInsets(0, -(width - 30), 0, 0)
                    widget.label:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5)
                else
                    widget:SetWidth(math.min(width, row.key and 360 or width))
                    widget:SetHeight(height)
                    if widget.button then
                        widget.button:SetWidth(math.min(width, math.max(160, #(widget.button:GetText() or "") * 7 + 24)))
                    end
                end
                if row.predicate and widget.SetEnabled then widget:SetEnabled(enabled and true or false) end
                y = y + height
            end
        end
        content:SetHeight(y + 12)
        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    end
    scroll:SetScript("OnSizeChanged", ns.Safe(canvasLayout))
    panel:SetScript("OnShow", ns.Safe(function() W.Refresh(); canvasLayout() end))
    panel.scroll, panel.content, panel.controls = scroll, content, controls
    canvasLayout()
    local category = Settings.RegisterCanvasLayoutCategory(panel, L.ADDON_TITLE)
    Settings.RegisterAddOnCategory(category)
    root, Options.categoryID, Options.canvas = category, category:GetID(), panel
    for _, o in ipairs(CATEGORY_NAMES) do Options.categories[o[1]] = category end
end

local function CanBuildVertical()
    for _, name in ipairs({ "RegisterVerticalLayoutCategory", "RegisterVerticalLayoutSubcategory", "RegisterProxySetting",
        "RegisterAddOnCategory", "CreateCheckbox", "CreateSliderOptions", "CreateSlider", "CreateDropdown",
        "CreateControlTextContainer" }) do
        if not Settings[name] then return false end
    end
    return Settings.VarType and CreateSettingsListSectionHeaderInitializer and CreateSettingsButtonInitializer
        and ((SettingsPanel and SettingsPanel.GetLayout) or Settings.RegisterInitializer) and true or false
end

ns.On("LOGIN", function()
    if root or not Settings then return end
    ns.Call(function()
        if CanBuildVertical() then
            Build()
        elseif Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            BuildCanvas()
        end
    end)
end)

ns.On("SETTING_CHANGED", function(key)
    if Settings and Settings.NotifyUpdate then
        if key then
            pcall(Settings.NotifyUpdate, PREFIX .. key)
        else
            for k in pairs(registered) do pcall(Settings.NotifyUpdate, PREFIX .. k) end
        end
    end
    if canvasLayout then canvasLayout() end
end)

function Options.IsAvailable()
    return root ~= nil and Settings ~= nil and Settings.OpenToCategory ~= nil
end

function Options.Open(sub)
    if CombatBlocked() then return end
    if Options.IsAvailable() then
        local category = (sub and Options.categories[sub]) or root
        if pcall(Settings.OpenToCategory, category:GetID()) then return end
    end
    if ns.Window and ns.Window.Show then ns.Window.Show() end
    ns.Print(L.SETTINGS_UNAVAILABLE, true)
end
