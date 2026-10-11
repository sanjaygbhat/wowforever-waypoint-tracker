-- Routes live in the shared window; questions use popups and sharing uses menus.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP
local Widgets, Window = ns.Widgets, ns.Window

local RoutesUI = {}
ns.RoutesUI = RoutesUI

local frame, rows, detail, searchBox, emptyText, countText, netText, list, listBg
local detailID
local selectedID
local state = { tab = "all", cat = "all", sort = "near" }
local results = {}
local firstHelp
local function R() return ns.Routes end
local function Status(text, good)
    if RoutesUI.IsShown() then Window.SetStatus(text, good) end
end
local function ScoreText(id)
    local up, down = R().Score(id)
    return ("|cff40ff40+%d|r |cffff6060-%d|r"):format(up, down)
end
local TABS = {
    { value = "all", text = L.ROUTES_SOURCE_ALL },
    { value = "suggested", text = L.ROUTES_TAB_SUGGESTED },
    { value = "shared", text = L.ROUTES_TAB_SHARED },
    { value = "mine", text = L.ROUTES_TAB_MINE },
}
local CAT_COLOUR = {
    mining = { 0.85, 0.65, 0.45 }, herbs = { 0.45, 1, 0.45 }, skinning = { 0.8, 0.55, 0.35 }, fishing = { 0.4, 0.75, 1 }, farming = { 1, 0.5, 0.4 }, treasure = { 1, 0.82, 0 },
    quests = { 1, 1, 0.4 }, travel = { 0.5, 0.8, 1 }, dungeons = { 0.8, 0.6, 1 }, other = { 0.9, 0.9, 0.9 },
}


-- what a search looks through, per route (worked out once)
local hayOf = setmetatable({}, { __mode = "k" })

local function Matches(r, q, here)
    if state.tab ~= "all" and r.src ~= state.tab then
        return false
    end
    if state.cat ~= "all" and r.cat ~= state.cat then
        return false
    end
    if ns.Get("routeThisZone") then
        local on = false
        for _, p in ipairs(r.pts) do
            if here and Geo.SameMap(p.m, here) then
                on = true
                break
            end
        end
        if not on then
            return false
        end
    end
    if r.src ~= "mine" and not ns.Get("routeLowRated") and R().IsLowRated(R().Score(r.id)) then
        return false
    end
    if q ~= "" then
        local hay = hayOf[r]
        if not hay then
            hay = Geo.Squash(r.name) .. " " .. Geo.Squash(Geo.GetMapName(r.zone) or "") .. " " .. Geo.Squash(r.author or "")
                .. " " .. Geo.Squash(R().CategoryLabel(r.cat)) .. " " .. Geo.Squash(r.note or "")
            hayOf[r] = hay
        end
        if not hay:find(q, 1, true) then
            return false
        end
    end
    return true
end

local RefreshDetail
local function RefreshRows()
    list:SetSelected(selectedID and R().Get(selectedID))
end

local function RefreshList()
    if not frame then
        return
    end
    -- suggested routes come from Find's database (loaded once, when needed)
    if ns.DB and not ns.DB.ready and not frame.triedDB and (state.tab == "all" or state.tab == "suggested") then
        frame.triedDB = true
        ns.DB.Load()
    end
    local q = Geo.Squash(searchBox.edit:GetText())
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    results = {}
    local dist = {}
    for _, r in ipairs(R().All()) do
        if Matches(r, q, here) then
            results[#results + 1] = r
            if state.sort == "near" then
                dist[r] = R().Distance(r) or math.huge
            end
        end
    end
    local rating = {}
    for _, r in ipairs(results) do
        local up, down = R().Score(r.id)
        rating[r] = { R().Rating(up, down), up }
    end
    table.sort(results, function(a, b)
        if state.sort == "near" and dist[a] ~= dist[b] then
            return dist[a] < dist[b]
        elseif state.sort == "new" then
            local ta, tb = a.made or a.got or 0, b.made or b.got or 0
            if ta ~= tb then
                return ta > tb
            end
        elseif state.sort == "top" then
            if rating[a][1] ~= rating[b][1] then
                return rating[a][1] > rating[b][1]
            end
            if rating[a][2] ~= rating[b][2] then
                return rating[a][2] > rating[b][2]
            end
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.id < b.id
    end)
    countText:SetText(L.ROUTES_COUNT:format(#results))
    if #results == 0 then
        emptyText:SetText((state.tab == "mine" and L.ROUTES_EMPTY_MINE) or (state.tab == "shared" and L.ROUTES_EMPTY_SHARED) or L.ROUTES_EMPTY)
        emptyText:Show()
    else
        emptyText:Hide()
    end
    local visible
    for _, r in ipairs(results) do
        if r.id == selectedID then visible = r; break end
    end
    if not visible then
        selectedID = not firstHelp and results[1] and results[1].id or nil
    end
    list:SetItems(results)
    RefreshRows()
    RefreshDetail()
    local s = ns.RoutesNet and ns.RoutesNet.Status()
    netText:SetText(ns.Get("routeSharing") and L.ROUTES_SHARING_LINE:format(s and s.peers or 0) or L.ROUTES_SHARING_OFF_LINE)
    local w = RoutesUI.widgets
    if w then w.source:Refresh(); w.cat:Refresh(); w.sort:Refresh() end
end
RoutesUI.Refresh = RefreshList

local ShowEditor, ShowText, ShowShare, ShowCreate, ShowHelp

local function Minutes(secs)
    return math.max(1, math.floor((secs or 0) / 60 + 0.5))
end

RefreshDetail = function()
    local r = selectedID and R().Get(selectedID)
    local id = r and r.id
    local changed = detailID ~= id
    detailID = id
    detail.route = r
    if changed then detail.scroll:SetVerticalScroll(0) end
    detail.share = nil
    detail.body:ClearAllPoints()
    detail.body:SetPoint("TOPLEFT")
    for _, b in ipairs(detail.buttons) do
        b:Hide()
    end
    detail.up:SetShown(r ~= nil)
    detail.down:SetShown(r ~= nil)
    detail.name:SetShown(r ~= nil)
    detail.meta:SetShown(r ~= nil)
    detail.votes:SetShown(r ~= nil)
    detail.scroll:ClearAllPoints()
    if r then
        detail.scroll:SetPoint("TOPLEFT", detail.up, "BOTTOMLEFT", 0, -10)
    else
        detail.scroll:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -10)
    end
    detail.scroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -26, r and 104 or 10)
    if not r then
        detail.name:SetText("")
        detail.meta:SetText("")
        detail.body:SetText(firstHelp and L.ROUTES_HELP_TEXT or L.ROUTES_PICK)
        detail.FitBody()
        detail.votes:SetText("")
        return
    end
    local c = CAT_COLOUR[r.cat] or CAT_COLOUR.other
    detail.name:SetText(r.name)
    detail.name:SetTextColor(c[1], c[2], c[3])
    local author = r.src == "mine" and L.ROUTES_BY_YOU or L.ROUTES_BY:format(R().ShortName(r.author))
    local dist = R().Distance(r)
    local lines = {
        author .. "  ·  " .. R().CategoryLabel(r.cat) .. "  ·  " .. (Geo.GetMapName(r.zone) or "?"),
        L.ROUTES_POINTS:format(#r.pts) .. "  ·  " .. R().ModeLabel(r.mode) .. (dist and ("  ·  " .. L.ROUTES_AWAY:format(Geo.FormatDistance(dist))) or ""),
    }
    if r.src == "mine" then
        lines[#lines + 1] = r.public and L.ROUTES_PUBLIC or L.ROUTES_PRIVATE
    elseif r.via and r.via ~= r.author then
        lines[#lines + 1] = L.ROUTES_VIA:format(R().ShortName(r.via))
    end
    detail.meta:SetText(table.concat(lines, "\n"))
    local body = r.note or ""
    local run = R().Run()
    local running = run and run.id == r.id
    if running then
        local progress
        if run.mode == "loop" then
            progress = L.ROUTES_RUNNING_LOOP:format(run.lap or 0, Minutes(run.secs))
        else
            progress = L.ROUTES_RUNNING:format(run.done or 0, run.total or #r.pts, Minutes(run.secs))
        end
        body = "|cff40ff40" .. progress .. "|r" .. (body ~= "" and ("\n\n" .. body) or "")
    end
    detail.body:SetText(body)
    detail.FitBody()

    local mine = R().IsMine(r)
    local my = R().MyVote(r.id)
    local up, down = R().Score(r.id)
    detail.up:SetText("▲ " .. up)
    detail.down:SetText("▼ " .. down)
    detail.votes:SetText(my ~= 0 and (my > 0 and L.ROUTES_YOU_UP or L.ROUTES_YOU_DOWN) or "")
    detail.up:SetEnabled(not mine)
    detail.down:SetEnabled(not mine)
    if my > 0 then
        detail.up:LockHighlight()
    else
        detail.up:UnlockHighlight()
    end
    if my < 0 then
        detail.down:LockHighlight()
    else
        detail.down:UnlockHighlight()
    end

    local actions = {}
    if running then
        actions[#actions + 1] = { L.ROUTE_STOP, function()
            R().Stop()
        end }
        actions[#actions + 1] = { L.ROUTE_SKIP, function()
            R().Skip()
        end }
    else
        actions[#actions + 1] = { L.ROUTE_START, function()
            R().Start(r.id)
            local now = R().Run()
            if now and now.id == r.id then
                Status(L.ROUTE_STARTED:format(r.name, #r.pts), true)
            end
        end }
    end
    actions[#actions + 1] = { L.ROUTE_SHARE, function()
        ShowShare(r)
    end }
    if mine then
        actions[#actions + 1] = { L.ROUTE_EDIT, function()
            ShowEditor(r)
        end }
        actions[#actions + 1] = { L.ROUTE_DELETE, function()
            Widgets.Confirm("WAYPOINTTRACKER_ROUTE_DELETE", {
                text = L.ROUTE_DELETE_CONFIRM, button1 = L.ROUTE_DELETE, button2 = CANCEL or L.NO,
                onAccept = function()
                    R().Delete(r.id)
                    selectedID = nil
                    RefreshList()
                end,
            })
            Widgets.Ask("WAYPOINTTRACKER_ROUTE_DELETE", r.name, nil, r.id)
        end }
    elseif r.src == "shared" then
        actions[#actions + 1] = { L.ROUTE_REMOVE, function()
            R().Delete(r.id)
            selectedID = nil
        end }
        actions[#actions + 1] = { L.ROUTE_BLOCK, function()
            R().Block(r.author)
            selectedID = nil
            Status(L.ROUTE_BLOCKED:format(R().ShortName(r.author)), true)
        end }
    end
    for i, a in ipairs(actions) do
        local b = detail.buttons[i]
        if b then
            if a[1] == L.ROUTE_SHARE then detail.share = b end
            b:SetText(a[1])
            b.action = a[2]
            b:Show()
        end
    end
end

local function Dropdown(parent, width, options, get, set)
    return Widgets.Dropdown(parent, width, {
        text = function()
            for _, o in ipairs(options) do
                if o.value == get() then return o.text end
            end
            return options[1] and options[1].text or ""
        end,
        menu = function(root)
            for _, o in ipairs(options) do
                local value = o.value
                root:CreateRadio(o.text, function() return get() == value end, function() set(value) end)
            end
        end,
    })
end

local function Categories(all)
    local choices = all and { { value = "all", text = L.ROUTES_ALL_CATEGORIES } } or {}
    for _, c in ipairs(R().CATEGORIES) do
        choices[#choices + 1] = { value = c, text = R().CategoryLabel(c) }
    end
    return choices
end

local function SelectRoute(id)
    selectedID = id
    if id and R().Get(id) then
        firstHelp = false
        ns.Set("routesHelpShown", true)
    end
    RefreshRows()
    RefreshDetail()
end

local function Layout()
    if not frame then return end
    local notice = not ns.Get("travelNoticeShown") and not ns.Get("realRoutes")
    frame.notice:SetShown(notice)
    local top = notice and -78 or 0
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, top)
    listBg:ClearAllPoints()
    listBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, top - 62)
    listBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 28)
end

local function Build(content)
    frame = content
    firstHelp = not ns.Get("routesHelpShown")
    frame.status = Window.frame.status
    frame.notice = CreateFrame("Frame", nil, frame)
    frame.notice:SetPoint("TOPLEFT")
    frame.notice:SetPoint("TOPRIGHT")
    frame.notice:SetHeight(72)
    frame.notice.text = Widgets.Label(frame.notice, L.TRAVEL_NEW_WINDOW, "GameFontHighlightSmall")
    frame.notice.text:SetPoint("TOPLEFT", 4, -4)
    frame.notice.text:SetPoint("RIGHT", -4, 0)
    frame.notice.dismiss = Widgets.Button(frame.notice, L.TRAVEL_NOTICE_DISMISS, 90, 22)
    frame.notice.dismiss:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.notice.dismiss:SetScript("OnClick", ns.Safe(function() ns.Set("travelNoticeShown", true) end))
    frame.notice.enable = Widgets.Button(frame.notice, L.TRAVEL_NOTICE_ENABLE, 110, 22)
    frame.notice.enable:SetPoint("RIGHT", frame.notice.dismiss, "LEFT", -6, 0)
    frame.notice.enable:SetScript("OnClick", ns.Safe(function()
        ns.Set("realRoutes", true)
        ns.Set("travelNoticeShown", true)
    end))
    Widgets.Tooltip(frame.notice.enable, L.REAL_ROUTES, L.REAL_ROUTES_DESC)

    -- Two filter rows leave enough room for translated dropdown labels.
    searchBox = Widgets.EditBox(frame, 260, { search = true, placeholder = L.ROUTES_SEARCH })
    searchBox.edit:HookScript("OnTextChanged", ns.Safe(function()
        if list then list.offset = 0; RefreshList() end
    end))
    local source = Dropdown(frame, 160, TABS, function() return state.tab end, function(v) RoutesUI.SetTab(v) end)
    source:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    local zoneOnly = Widgets.Check(frame, L.THIS_ZONE_ONLY, "routeThisZone", nil, 150)
    zoneOnly:SetPoint("LEFT", source, "RIGHT", 4, 0)
    local cat = Dropdown(frame, 300, Categories(true), function() return state.cat end, function(v)
        state.cat = v
        list.offset = 0
        RefreshList()
    end)
    cat:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -4)
    local sort = Dropdown(frame, 270, {
        { value = "near", text = L.ROUTES_SORT_NEAR }, { value = "top", text = L.ROUTES_SORT_TOP },
        { value = "new", text = L.ROUTES_SORT_NEW },
    }, function() return state.sort end, function(v)
        state.sort = v
        list.offset = 0
        RefreshList()
    end)
    sort:SetPoint("LEFT", cat, "RIGHT", 6, 0)

    listBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listBg:SetWidth(300)
    if listBg.SetBackdrop then
        listBg:SetBackdrop(Widgets.BACKDROP_BOX)
        listBg:SetBackdropColor(0, 0, 0, 0.6)
        listBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end
    list = Widgets.List(listBg, {
        rowHeight = 22, emptyText = L.ROUTES_EMPTY,
        rowInit = function(row)
            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(1, 0.82, 0, 0.12)
            row.right = Widgets.Label(row, "", "GameFontHighlightSmall")
            row.right:SetPoint("RIGHT", -4, 0)
            row.text = Widgets.Label(row, "")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
            row.text:SetWordWrap(false)
        end,
        rowUpdate = function(row, r)
            row.route = r
            local c = CAT_COLOUR[r.cat] or CAT_COLOUR.other
            local run = R().Run()
            local mark = run and run.id == r.id and "|cff40ff40>|r " or ""
            row.text:SetText(mark .. r.name .. "  |cff999999" .. (Geo.GetMapName(r.zone) or "") .. "|r")
            row.text:SetTextColor(c[1], c[2], c[3])
            row.right:SetText(ScoreText(r.id) .. "  |cffbbbbbb" .. #r.pts .. "|r")
            row.sel:SetShown(r.id == selectedID)
        end,
        onClick = function(_, r, button) if button == "LeftButton" then SelectRoute(r.id) end end,
        onDoubleClick = function(_, r) R().Start(r.id) end,
    })
    list:SetPoint("TOPLEFT", 5, -5)
    list:SetPoint("BOTTOMRIGHT", -5, 5)
    rows, emptyText = list.rows, list.emptyText
    countText = Widgets.Label(frame, "", "GameFontDisableSmall")
    countText:SetPoint("BOTTOMLEFT", 4, 7)

    detail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 8, 0)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 28)
    if detail.SetBackdrop then
        detail:SetBackdrop(Widgets.BACKDROP_BOX)
        detail:SetBackdropColor(0, 0, 0, 0.6)
    end
    detail.name = Widgets.Label(detail, "", "GameFontNormalLarge")
    detail.name:SetPoint("TOPLEFT", 10, -10)
    detail.name:SetPoint("RIGHT", -10, 0)
    detail.name:SetWordWrap(false)
    detail.meta = Widgets.Label(detail, "", "GameFontHighlightSmall")
    detail.meta:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -6)
    detail.meta:SetPoint("RIGHT", -10, 0)
    detail.meta:SetTextColor(0.8, 0.8, 0.8)
    detail.up = Widgets.Button(detail, L.ROUTE_UPVOTE, 56, 22)
    detail.up:SetPoint("TOPLEFT", detail.meta, "BOTTOMLEFT", 0, -8)
    detail.down = Widgets.Button(detail, L.ROUTE_DOWNVOTE, 56, 22)
    detail.down:SetPoint("LEFT", detail.up, "RIGHT", 4, 0)
    detail.votes = Widgets.Label(detail, "", "GameFontHighlightSmall")
    detail.votes:SetPoint("LEFT", detail.down, "RIGHT", 4, 0)
    detail.votes:SetPoint("RIGHT", -10, 0)
    detail.votes:SetWordWrap(false)
    local function Vote(v)
        local r = detail.route
        if not r then return end
        local value = R().MyVote(r.id) == v and 0 or v
        R().Vote(r.id, value)
        RefreshList()
        Status(value == 0 and L.ROUTE_VOTE_REMOVED or L.ROUTE_VOTED, true)
    end
    detail.up:SetScript("OnClick", ns.Safe(function() Vote(1) end))
    detail.down:SetScript("OnClick", ns.Safe(function() Vote(-1) end))
    Widgets.Tooltip(detail.up, L.ROUTE_UPVOTE, L.ROUTE_VOTE_DESC)
    Widgets.Tooltip(detail.down, L.ROUTE_DOWNVOTE, L.ROUTE_VOTE_DESC)
    -- Long notes and the first-open help scroll inside the detail pane.
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
    detail.scroll = ok and scroll or CreateFrame("ScrollFrame", nil, detail)
    detail.bodyFrame = CreateFrame("Frame", nil, detail.scroll)
    detail.body = Widgets.Label(detail.bodyFrame, "", "GameFontHighlightSmall")
    detail.body:SetJustifyV("TOP")
    detail.scroll:SetScrollChild(detail.bodyFrame)
    detail.FitBody = function()
        local width = math.max(1, detail.scroll:GetWidth())
        detail.bodyFrame:SetWidth(width)
        detail.body:SetWidth(width)
        detail.bodyFrame:SetHeight(math.max(1, detail.body:GetStringHeight()))
    end
    detail.scroll:SetScript("OnSizeChanged", ns.Safe(detail.FitBody))
    detail.scroll:EnableMouseWheel(true)
    detail.scroll:SetScript("OnMouseWheel", ns.Safe(function(self, delta)
        self:SetVerticalScroll(ns.Clamp(self:GetVerticalScroll() - delta * 22, 0, math.max(0, detail.bodyFrame:GetHeight() - self:GetHeight())))
    end))
    detail.buttons = {}
    for i = 1, 6 do
        local b = Widgets.Button(detail, "", 130, 24)
        local fs = b:GetFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", 6, 0)
            fs:SetPoint("RIGHT", -6, 0)
            fs:SetWordWrap(false)
        end
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        if col == 0 then
            b:SetPoint("BOTTOMLEFT", 10, 10 + (2 - line) * 28)
            b:SetPoint("RIGHT", detail, "CENTER", -3, 0)
        else
            b:SetPoint("BOTTOMRIGHT", -10, 10 + (2 - line) * 28)
            b:SetPoint("LEFT", detail, "CENTER", 3, 0)
        end
        b:SetScript("OnClick", ns.Safe(function(self)
            if self.action then self.action(); RefreshList() end
        end))
        detail.buttons[i] = b
    end

    local footer = CreateFrame("Button", nil, frame)
    footer:SetPoint("LEFT", countText, "RIGHT", 8, 0)
    footer:SetPoint("RIGHT", frame, "RIGHT", -30, 0)
    footer:SetHeight(22)
    netText = Widgets.Label(footer, "", "GameFontDisableSmall")
    netText:SetAllPoints()
    netText:SetWordWrap(false)
    footer:SetScript("OnClick", ns.Safe(function()
        if ns.Options and ns.Options.Open then ns.Options.Open("routes") end
    end))
    Widgets.Tooltip(footer, L.SETTINGS, L.ROUTES_SHARING_DESC)
    local okHelp, help = pcall(CreateFrame, "Button", nil, frame, "UIPanelInfoButton")
    if not okHelp then help = Widgets.Button(frame, "?", 24, 24) end
    help:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 8)
    help:SetScript("OnClick", ns.Safe(function() ShowHelp() end))
    Widgets.Tooltip(help, L.ROUTES_HOWTO, L.ROUTES_DESC)
    local tab = Window.tabs.routes
    RoutesUI.widgets = {
        source = source, rows = rows, detail = detail, search = searchBox.edit, new = tab.leftButton,
        import = tab.leftButton2, help = help, cat = cat, sort = sort, zoneOnly = zoneOnly,
        empty = emptyText, net = netText, status = frame.status, list = list, notice = frame.notice,
    }
    Layout()
    RefreshList()
end

local editor, textBox, help, create
local function Page(key, title, build)
    if not Window.Show("routes") then return nil end
    return Window.PushPage("routes", { key = key, title = title, build = build })
end

local function Reveal(r, source)
    state.cat, state.tab = "all", source
    searchBox.edit:SetText("")
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not Matches(r, "", here) then ns.Set("routeThisZone", false) end
    SelectRoute(r.id)
    RoutesUI.SetTab(source)
    for i, route in ipairs(results) do
        if route.id == r.id then list:ScrollTo(i); break end
    end
end

ShowEditor = function(r)
    if not r then return end
    local d = {}
    for k, v in pairs(r) do d[k] = v end
    d.public = d.public ~= false
    editor = Page("editor", d.id and L.ROUTE_EDIT_TITLE or L.ROUTE_NEW_TITLE, function(p)
        p.draft = d
        local function Field(label, y, hint, max)
            local text = Widgets.Label(p, label, "GameFontNormal")
            text:SetPoint("TOPLEFT", 12, y - 6)
            local box = Widgets.EditBox(p, 450, { placeholder = hint, maxLetters = max })
            box:SetPoint("TOPLEFT", 110, y)
            return box
        end
        p.name = Field(L.ROUTE_NAME, -8, L.ROUTE_NAME_HINT, R().MAX_NAME)
        p.note = Field(L.ROUTE_NOTE, -44, L.ROUTE_NOTE_HINT, R().MAX_NOTE)
        local catLabel = Widgets.Label(p, L.ROUTE_CATEGORY, "GameFontNormal")
        catLabel:SetPoint("TOPLEFT", 12, -86)
        p.cat = Dropdown(p, 185, Categories(), function() return p.draft.cat end, function(v) p.draft.cat = v end)
        p.cat:SetPoint("TOPLEFT", 110, -80)
        local modeLabel = Widgets.Label(p, L.ROUTE_MODE, "GameFontNormal")
        modeLabel:SetPoint("TOPLEFT", 310, -86)
        local modes = {}
        for _, m in ipairs(R().MODES) do modes[#modes + 1] = { value = m, text = R().ModeLabel(m) } end
        p.mode = Dropdown(p, 185, modes, function() return p.draft.mode end, function(v) p.draft.mode = v end)
        p.mode:SetPoint("TOPLEFT", 380, -80)
        Widgets.Tooltip(p.mode, L.ROUTE_MODE, L.ROUTE_MODE_DESC)
        p.public = Widgets.Check(p, L.ROUTE_PUBLIC, { get = function() return p.draft.public end, set = function(v) p.draft.public = v end }, L.ROUTE_PUBLIC_DESC, 540)
        p.public:SetPoint("TOPLEFT", 8, -118)
        p.info = Widgets.Label(p, "", "GameFontHighlightSmall")
        p.info:SetPoint("TOPLEFT", 12, -154)
        p.save = Widgets.Button(p, L.ROUTE_SAVE, 120, 24)
        p.save:SetPoint("BOTTOMRIGHT", -10, 10)
        p.save:SetScript("OnClick", ns.Safe(function()
            local d = p.draft
            d.name, d.note = p.name.edit:GetText(), p.note.edit:GetText()
            d.public = p.public:GetChecked() and true or false
            local saved = R().SaveMine(d)
            if not saved then return end
            Window.PopAll("routes")
            Reveal(saved, "mine")
            Status(L.ROUTE_SAVED:format(saved.name), true)
            ShowShare(saved, true)
        end))
        p.cancel = Widgets.Button(p, CANCEL or L.NO, 100, 24)
        p.cancel:SetPoint("RIGHT", p.save, "LEFT", -6, 0)
        p.cancel:SetScript("OnClick", ns.Safe(function() Window.PopPage("routes") end))
    end)
    if not editor then return end
    editor.draft = d
    editor.name.edit:SetText(d.name or "")
    editor.note.edit:SetText(d.note or "")
    editor.cat:Refresh()
    editor.mode:Refresh()
    editor.public:Refresh()
    editor.info:SetText(L.ROUTES_POINTS:format(#d.pts) .. "  ·  " .. (Geo.GetMapName(d.zone) or ""))
    editor.name.edit:SetFocus()
end
RoutesUI.ShowEditor = ShowEditor

ShowText = function(mode, text)
    textBox = Page(mode == "copy" and "copy" or "import", mode == "copy" and L.ROUTE_COPY_TITLE or L.ROUTE_IMPORT_TITLE, function(p)
        p.help = Widgets.Label(p, mode == "copy" and L.ROUTE_COPY_HELP or L.ROUTE_IMPORT_HELP, "GameFontHighlightSmall")
        p.help:SetPoint("TOPLEFT", 10, -4)
        p.help:SetPoint("RIGHT", -10, 0)
        p.area = Widgets.TextArea(p)
        p.area:SetPoint("TOPLEFT", 8, -56)
        p.area:SetPoint("BOTTOMRIGHT", -8, 48)
        p.edit = p.area.edit
        p.result = Widgets.Label(p, "", "GameFontHighlightSmall")
        p.result:SetPoint("BOTTOMLEFT", 12, 18)
        p.result:SetPoint("RIGHT", -170, 0)
        p.action = Widgets.Button(p, L.IMPORT, 140, 24)
        p.action:SetPoint("BOTTOMRIGHT", -10, 10)
        p.action:SetShown(mode ~= "copy")
        p.action:SetScript("OnClick", ns.Safe(function()
            local input = p.edit:GetText()
            local r, skipped
            if #input <= 100000 then r, skipped = R().Parse(input) end
            if not r then
                p.result:SetText(L.ROUTE_IMPORT_NOTHING)
                p.result:SetTextColor(1, 0.35, 0.3)
                return
            end
            if r.id and r.author and r.author ~= R().Me() then
                local kept = R().Keep(r)
                if kept then
                    Window.PopAll("routes")
                    Reveal(kept, "shared")
                    Status(L.ROUTE_IMPORTED:format(kept.name, #kept.pts), true)
                    return
                end
            end
            r.id = (r.id and R().Get(r.id) and R().IsMine(R().Get(r.id))) and r.id or nil
            Window.PopPage("routes")
            ShowEditor(r)
            if (skipped or 0) > 0 then Status(L.ROUTE_IMPORT_SKIPPED:format(skipped)) end
        end))
    end)
    if not textBox then return end
    textBox.edit:SetText(text or "")
    textBox.result:SetText("")
    textBox.edit:SetFocus()
    if mode == "copy" then textBox.edit:HighlightText() end
end
RoutesUI.ShowText = ShowText

ShowHelp = function()
    help = Page("help", L.ROUTES_HELP_TITLE, function(p)
        p.text = Widgets.Label(p, L.ROUTES_HELP_TEXT)
        p.text:SetPoint("TOPLEFT", 12, -8)
        p.text:SetPoint("RIGHT", -12, 0)
        p.text:SetSpacing(3)
        p.create = Widgets.Button(p, L.ROUTE_CREATE, 150, 24)
        p.create:SetPoint("BOTTOMRIGHT", -10, 10)
        p.create:SetScript("OnClick", ns.Safe(function() Window.PopPage("routes"); ShowCreate() end))
        p.ok = Widgets.Button(p, L.ROUTES_HELP_OK, 110, 24)
        p.ok:SetPoint("RIGHT", p.create, "LEFT", -6, 0)
        p.ok:SetScript("OnClick", ns.Safe(function() Window.PopPage("routes") end))
    end)
    if not help then return end
end
RoutesUI.ShowHelp = ShowHelp

ShowCreate = function()
    create = Page("create", L.ROUTE_CREATE_TITLE, function(p)
        local y = -10
        local function Choice(label, desc, fn)
            local b = Widgets.Button(p, label, 190, 26)
            b:SetPoint("TOPLEFT", 10, y)
            local text = Widgets.Label(p, desc, "GameFontHighlightSmall")
            text:SetPoint("TOPLEFT", b, "TOPRIGHT", 10, 0)
            text:SetPoint("RIGHT", -12, 0)
            b:SetScript("OnClick", ns.Safe(fn))
            Widgets.Tooltip(b, label, desc)
            y = y - 80
            return b, text
        end
        p.record = Choice(L.ROUTE_CREATE_RECORD, L.ROUTE_CREATE_RECORD_DESC, function()
            Window.Hide()
            R().RecordStart()
        end)
        p.fromWp, p.fromWpText = Choice(L.ROUTE_NEW, "", function()
            local draft = R().FromWaypoints()
            if not draft then Status(L.ROUTE_NEW_NONE); return end
            Window.PopPage("routes")
            ShowEditor(draft)
        end)
        p.fromWp:SetMotionScriptsWhileDisabled(true)
        p.fromWp:SetScript("OnEnter", ns.Safe(function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L.ROUTE_NEW, 1, 1, 1)
            GameTooltip:AddLine(p.fromWpText:GetText(), 1, 0.82, 0, true)
            GameTooltip:Show()
        end))
        p.fromWp:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        p.paste = Choice(L.ROUTE_CREATE_PASTE, L.ROUTE_IMPORT_DESC, function()
            Window.PopPage("routes")
            ShowText("import", "")
        end)
        p.footer = Widgets.Label(p, L.ROUTE_CREATE_FOOTER, "GameFontDisableSmall")
        p.footer:SetPoint("BOTTOMLEFT", 12, 12)
        p.footer:SetPoint("RIGHT", -12, 0)
    end)
    if not create then return end
    local n = WP.Count()
    create.fromWpText:SetText(n > 0 and L.ROUTE_NEW_DESC_N:format(n) or L.ROUTE_NEW_NONE)
    create.fromWp:SetEnabled(n > 0)
end
RoutesUI.ShowCreate = ShowCreate

local function ShareMenu(r, justSaved)
    return function(root)
        root:CreateTitle(justSaved and L.ROUTE_SHARE_SAVED_TITLE or L.ROUTE_SHARE_TITLE:format(r.name))
        local msg = L.ROUTE_CHAT_LINE:format(r.name, #r.pts, Geo.GetMapName(r.zone) or "")
        local first = r.pts[1]
        local link = first and ns.Share and ns.Share.MapPinLink(first)
        if link then msg = msg .. " " .. link end
        if ns.Get("sharePrefix") and ns.Share then msg = ns.Share.PREFIX .. " " .. msg end
        for _, ch in ipairs(ns.Share and ns.Share.Channels() or {}) do
            local prefix = ch[2]
            root:CreateButton(L.ROUTE_SHARE_POST:format(ch[1]), function()
                if ns.Share and ns.Share.OpenChat then ns.Share.OpenChat(prefix .. " " .. msg) end
            end)
        end
        root:CreateDivider()
        local send = root:CreateButton(L.ROUTE_SEND_TARGET, function()
            local name = UnitIsPlayer and UnitIsPlayer("target") and UnitName and UnitName("target")
            if not name or name == UnitName("player") then Status(L.ROUTE_SEND_NO_TARGET); return end
            if ns.RoutesNet and ns.RoutesNet.SendTo and ns.RoutesNet.SendTo(r.id, name) then
                Status(L.ROUTE_SENT:format(r.name, name), true)
            end
        end)
        if send and send.SetTooltip then
            send:SetTooltip(function(tt)
                if GameTooltip_SetTitle then GameTooltip_SetTitle(tt, L.ROUTE_SEND_TARGET) end
                if GameTooltip_AddNormalLine then GameTooltip_AddNormalLine(tt, L.ROUTE_SEND_TARGET_DESC) end
            end)
        end
        root:CreateButton(L.ROUTE_COPY, function() ShowText("copy", R().Serialize(r)) end)
    end
end

ShowShare = function(r, justSaved)
    if not r then return end
    local owner = frame or UIParent
    if RoutesUI.IsShown() and frame:IsVisible() and detail.share and detail.share:IsVisible() then
        owner = detail.share
    end
    return Widgets.Menu(owner, ShareMenu(r, justSaved))
end
RoutesUI.ShowShare = ShowShare

ns.On("ROUTE_ASK", function(id, others)
    local r = R().Get(id)
    if not r then return end
    local name = (r.name or ""):gsub("%%", "%%%%")
    Widgets.Confirm("WAYPOINTTRACKER_ROUTE_ASK", {
        text = L.ROUTE_ASK_TITLE:format(name) .. "\n\n" .. L.ROUTE_ASK_TEXT .. "\n\n" .. L.ROUTE_ASK_FOOTER,
        button1 = L.ROUTE_ASK_REPLACE, button3 = L.ROUTE_ASK_ADD, button2 = CANCEL or L.NO,
        onAccept = function() R().Apply(id, "replace") end,
        onAlt = function() R().Apply(id, "add") end,
    })
    Widgets.Ask("WAYPOINTTRACKER_ROUTE_ASK", others, nil, id)
end)

ns.On("ROUTE_FEEDBACK", function(id, secs)
    local r = R().Get(id)
    if not r then return end
    local text = L.ROUTE_FEEDBACK_TITLE:format(r.name) .. "\n\n" .. L.ROUTE_FEEDBACK_TEXT:format(Minutes(secs))
    local my = R().MyVote(id)
    if my ~= 0 then text = text .. "\n" .. (my > 0 and L.ROUTE_FEEDBACK_WAS_UP or L.ROUTE_FEEDBACK_WAS_DOWN) end
    local function Vote(value)
        if R().Vote(id, value) then Status(L.ROUTE_VOTED, true) end
    end
    Widgets.Confirm("WAYPOINTTRACKER_ROUTE_FEEDBACK", {
        -- No format arguments here: route names can contain percent signs.
        text = text:gsub("%%", "%%%%"), button1 = L.ROUTE_FEEDBACK_GOOD,
        button3 = L.ROUTE_FEEDBACK_BAD, button2 = L.ROUTE_FEEDBACK_LATER,
        onAccept = function() Vote(1) end, onAlt = function() Vote(-1) end,
        sound = (SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN) or 875,
    })
    Widgets.Ask("WAYPOINTTRACKER_ROUTE_FEEDBACK", nil, nil, id)
end)

function RoutesUI.Show()
    if not ns.settings then return end
    if not Window.Show("routes") then return end
    RefreshList()
end
function RoutesUI.Toggle() Window.Toggle("routes") end
function RoutesUI.IsShown() return Window.IsShown() and Window.GetTab() == "routes" end
function RoutesUI.Select(id)
    selectedID = id
    if id and R().Get(id) then
        firstHelp = false
        ns.Set("routesHelpShown", true)
    end
    if frame then RefreshList() end
end
function RoutesUI.SetTab(key)
    local valid = false
    for _, t in ipairs(TABS) do if t.value == key then valid = true; break end end
    if not valid then return end
    state.tab = key
    if frame then
        list.offset = 0
        RoutesUI.widgets.source:Refresh()
        RefreshList()
    end
end
function RoutesUI.Frames()
    return { editor = editor, text = textBox, help = help, create = create, recorder = ns.Recorder and ns.Recorder.frame }
end

Window.RegisterTab {
    key = "routes", order = 3, title = L.ROUTES_TITLE,
    leftButton = { text = L.ROUTE_CREATE, onClick = function() ShowCreate() end, tooltip = L.ROUTE_CREATE_DESC },
    leftButton2 = { text = L.IMPORT, onClick = function() ShowText("import", "") end, tooltip = L.ROUTE_IMPORT_DESC },
    build = Build,
    onShow = function() Layout(); RefreshList() end,
    onUpdate = function() RefreshList() end,
}
for _, event in ipairs({ "ROUTES_CHANGED", "WAYPOINTS_CHANGED", "ACTIVE_CHANGED", "SETTING_CHANGED" }) do
    ns.On(event, function()
        if RoutesUI.IsShown() and frame then Layout(); RefreshList() end
    end)
end
