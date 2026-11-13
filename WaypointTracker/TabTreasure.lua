-- Treasure lives in the shared window. Only the shell's visible-tab 0.5 s
-- callback refreshes lists; events and hidden tabs do no list work.
local _, ns = ...
local W, Window, T, Geo, L = ns.Widgets, ns.Window, ns.Treasure, ns.Geo, ns.L
local Tab = { widgets = {} }
ns.TabTreasure = Tab
local widgets = Tab.widgets
local content, nearby, zone = nil, {}, {}
local zoneSource
local OPTIONS = {
    { "treasureChests", "TREASURE_CHESTS", "TREASURE_CHESTS_DESC" },
    { "treasureRares", "TREASURE_RARES", "TREASURE_RARES_DESC" },
    { "treasureOther", "TREASURE_OTHER", "TREASURE_OTHER_DESC" },
    { "treasureKnownSpots", "TREASURE_KNOWN", "TREASURE_KNOWN_DESC" },
    { "treasureKnownRares", "TREASURE_KNOWN_RARES", "TREASURE_KNOWN_RARES_DESC" },
    { "treasurePing", "TREASURE_PING", "TREASURE_PING_DESC" },
    { "treasureFocus", "TREASURE_FOCUS", "TREASURE_FOCUS_DESC" },
}
local OUTCOME = { killed = "TREASURE_KILLED", looted = "TREASURE_LOOTED", gone = "TREASURE_LOG_GONE" }
local function Ago(at)
    return L.TREASURE_STATUS_AGO:format(math.max(0, math.floor((T.Time() - at) / 60)))
end
local function MapName(map)
    local info = C_Map and C_Map.GetMapInfo and ns.Plain(Geo.GetMapInfo(map))
    return (type(info) == "table" and T.Name(info.name)) or ("#" .. map)
end
local function Point(t)
    local wp = T.Point(t)
    Window.SetStatus(wp and L.POINTING_TO:format(T.Name(t and t.name) or "?") or L.NO_POSITION, wp ~= nil)
end
local function Menu(row, t)
    W.Menu(row, function(root)
        root:CreateButton(L.ROW_MENU_POINT, function() Point(t) end)
        root:CreateButton(L.TREASURE_IGNORE, function()
            T.Ignore(t)
            Window.SetStatus(L.TREASURE_IGNORED, true)
            Tab.Refresh()
        end)
    end)
end
local function Less(a, b)
    if a.distance ~= b.distance then return (a.distance or math.huge) < (b.distance or math.huge) end
    return a.sortName < b.sortName
end
local function Distances(list)
    for _, t in ipairs(list) do
        t.sortName = ns.Str(t.name) or "?"
        t.distance = t.m and Geo.GetVector(t) or nil
    end
    table.sort(list, Less)
end
function Tab.Refresh()
    if not content or not Window.IsShown() or Window.GetTab() ~= "treasure" then return end
    local on = ns.Get("treasureHunt")
    widgets.off:SetShown(not on)
    widgets.on:SetShown(on)
    if not on then return end
    for _, option in ipairs(OPTIONS) do widgets[option[1]]:Refresh() end
    wipe(nearby)
    for _, t in pairs(T.Targets()) do nearby[#nearby + 1] = t end
    Distances(nearby)
    widgets.nearby:SetItems(nearby)
    local map = C_Map and C_Map.GetBestMapForUnit and ns.Num(C_Map.GetBestMapForUnit("player"))
    local source = T.ZoneSpots(map)
    if source ~= zoneSource then
        zoneSource = source
        wipe(zone)
        for _, t in ipairs(source) do zone[#zone + 1] = t end
    end
    Distances(zone)
    widgets.zone:SetItems(zone)
    widgets.recent:SetItems(T.Recent())
end
local function Section(parent, key, title, recent)
    local header = W.Label(parent, title, "GameFontNormal")
    header:SetHeight(14)
    widgets[key .. "Header"] = header
    local list = W.List(parent, {
        rowHeight = 24, emptyText = L.TREASURE_EMPTY,
        rowInit = function(row)
            row.text = W.Label(row, "", "GameFontHighlightSmall")
            row.text:SetPoint("TOPLEFT", 4, -1)
            row.text:SetPoint("TOPRIGHT", -4, -1)
            row.text:SetWordWrap(false)
            row.detail = W.Label(row, "", "GameFontDisableSmall")
            row.detail:SetPoint("TOPLEFT", 4, -13)
            row.detail:SetPoint("TOPRIGHT", -4, -13)
            row.detail:SetWordWrap(false)
            W.Tooltip(row, title, L.TREASURE_ACTION_HINT)
        end,
        rowUpdate = function(row, t)
            row.text:SetText(L.TREASURE_TITLE:format(T.Label(t), T.Name(t.name) or "?"))
            local detail
            if recent then
                detail = Ago(t.at)
                if t.outcome then detail = detail .. " - " .. L[OUTCOME[t.outcome]] end
                if t.m then detail = detail .. " - " .. MapName(t.m) end
            else
                detail = t.distance and Geo.FormatDistance(t.distance) or L.NO_POSITION
                if t.near then detail = detail .. " - " .. L.TREASURE_SEEN_NEAR end
                if t.kind == "spawn" then
                    local at = T.LastSeen(t.id)
                    detail = detail .. " - " .. (at and L.TREASURE_LAST_SEEN:format(Ago(at)) or L.TREASURE_NEVER_SEEN)
                end
            end
            row.detail:SetText(detail)
        end,
        onDoubleClick = function(_, t) Point(t) end,
        onRightClick = key == "nearby" and Menu or nil,
    })
    widgets[key] = list
    return header, list
end
local function Build(parent)
    content = parent
    widgets.off = CreateFrame("Frame", nil, parent)
    widgets.off:SetAllPoints()
    local intro = W.Label(widgets.off, L.TREASURE_INTRO)
    intro:SetPoint("TOPLEFT", 16, -24)
    intro:SetPoint("TOPRIGHT", -16, -24)
    intro:SetWordWrap(true)
    widgets.enable = W.Button(widgets.off, L.TREASURE_ENABLE, nil, 36)
    widgets.enable:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -24)
    widgets.enable:SetScript("OnClick", ns.Safe(function()
        T.SetOption("treasureHunt", true)
        Window.SetStatus(L.TREASURE_ON, true)
        Tab.Refresh()
    end))
    widgets.on = CreateFrame("Frame", nil, parent)
    widgets.on:SetAllPoints()
    widgets.disable = W.Button(widgets.on, L.TREASURE_DISABLE)
    widgets.disable:SetPoint("TOPRIGHT", -4, 0)
    widgets.disable:SetScript("OnClick", ns.Safe(function()
        T.SetOption("treasureHunt", false)
        Window.SetStatus(L.TREASURE_OFF, "info")
        Tab.Refresh()
    end))
    local hint = W.Label(widgets.on, L.TREASURE_ACTION_HINT, "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 4, -4)
    hint:SetPoint("RIGHT", widgets.disable, "LEFT", -12, 0)
    hint:SetWordWrap(true)
    widgets.options = CreateFrame("Frame", nil, widgets.on)
    widgets.options:SetPoint("TOPLEFT", 4, 0)
    widgets.options:SetPoint("TOPRIGHT", -4, 0)
    widgets.options:SetHeight(132)
    for i, option in ipairs(OPTIONS) do
        local setting = option[1]
        local check = W.Check(widgets.options, L[option[2]], {
            get = function() return ns.Get(setting) end,
            set = function(value) T.SetOption(setting, value); Tab.Refresh() end,
        }, L[option[3]], 265)
        check:SetPoint("TOPLEFT", ((i - 1) % 2) * 302, -26 - math.floor((i - 1) / 2) * 26)
        widgets[setting] = check
    end
    local nh, nl = Section(widgets.on, "nearby", L.TREASURE_NEARBY)
    local zh, zl = Section(widgets.on, "zone", L.TREASURE_ZONE)
    local rh, rl = Section(widgets.on, "recent", L.TREASURE_STATUS_RECENT, true)
    nh:SetPoint("TOPLEFT", widgets.options, "BOTTOMLEFT", 0, -2)
    nh:SetPoint("TOPRIGHT", widgets.options, "BOTTOMRIGHT", 0, -2)
    nl:SetPoint("TOPLEFT", nh, "BOTTOMLEFT", 0, -2)
    nl:SetPoint("TOPRIGHT", nh, "BOTTOMRIGHT", 0, -2)
    nl:SetHeight(72) -- three two-line rows
    zh:SetPoint("TOPLEFT", nl, "BOTTOMLEFT", 0, -4)
    zh:SetPoint("TOPRIGHT", nl, "BOTTOMRIGHT", 0, -4)
    zl:SetPoint("TOPLEFT", zh, "BOTTOMLEFT", 0, -2)
    zl:SetPoint("TOPRIGHT", zh, "BOTTOMRIGHT", 0, -2)
    rl:SetPoint("BOTTOMLEFT", widgets.on, "BOTTOMLEFT", 4, 4)
    rl:SetPoint("BOTTOMRIGHT", widgets.on, "BOTTOMRIGHT", -4, 4)
    rl:SetHeight(72) -- three rows, pinned above the content bottom
    rh:SetPoint("BOTTOMLEFT", rl, "TOPLEFT", 0, 2)
    rh:SetPoint("BOTTOMRIGHT", rl, "TOPRIGHT", 0, 2)
    -- The shell is fixed at 640 x 540 (no resize grip/minimum override).
    -- Its inset leaves 442 px. Zone gets all space between the fixed lists;
    -- sizing also follows the real content if the shell changes in future.
    local function Layout(_, _, height)
        height = ns.Num(height) or content:GetHeight()
        zl:SetHeight(math.max(96, height - 338)) -- at least four rows
    end
    widgets.on:SetScript("OnSizeChanged", Layout)
    Layout(nil, nil, widgets.on:GetHeight())
    widgets.on:Hide()
end
Window.RegisterTab {
    key = "treasure", order = 4, title = L.TREASURE_TAB,
    build = Build,
    onShow = function()
        if ns.Get("treasureHunt") and ns.DB and ns.DB.Load then ns.DB.Load() end
        Tab.Refresh()
    end,
    onUpdate = Tab.Refresh,
}
