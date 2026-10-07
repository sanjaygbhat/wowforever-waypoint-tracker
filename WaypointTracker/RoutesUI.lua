-- The Routes window: browse routes (yours, shared by other players, and
-- suggested ones made from Find's database) by category and zone, vote on
-- them, start one, make and share your own. Plus the small questions it
-- asks: replace or add to your waypoints, and how a route was.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local RoutesUI = {}
ns.RoutesUI = RoutesUI

local WIDTH, HEIGHT = 800, 566
local LIST_W = 430
local ROWS = 15
local ROW_H = 22

local frame, rows, detail, searchBox, emptyText, countText, netText
local tabs = {}
local results = {}
local offset = 0
local selectedID
local state = { tab = "all", cat = "all", sort = "top" }

local function W()
    return ns.UI.W
end

local function R()
    return ns.Routes
end

local TABS = {
    { key = "all", label = "ROUTES_TAB_ALL" },
    { key = "mine", label = "ROUTES_TAB_MINE" },
    { key = "shared", label = "ROUTES_TAB_SHARED" },
    { key = "suggested", label = "ROUTES_TAB_SUGGESTED" },
}

local CAT_COLOUR = {
    mining = { 0.85, 0.65, 0.45 }, herbs = { 0.45, 1, 0.45 }, farming = { 1, 0.5, 0.4 }, treasure = { 1, 0.82, 0 },
    quests = { 1, 1, 0.4 }, travel = { 0.5, 0.8, 1 }, dungeons = { 0.8, 0.6, 1 }, other = { 0.9, 0.9, 0.9 },
}

local function Status(text, good)
    if not frame then
        return
    end
    frame.status:SetText(text or "")
    if good then
        frame.status:SetTextColor(0.3, 1, 0.3)
    else
        frame.status:SetTextColor(1, 0.35, 0.3)
    end
end

local function ScoreText(id)
    local up, down = R().Score(id)
    return ("|cff40ff40+%d|r |cffff6060-%d|r"):format(up, down)
end

-- "< text >" picker that doesn't need a setting
local function Picker(parent, width, options, get, set)
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
    local text = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    text:SetPoint("RIGHT", nextB, "LEFT", -2, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    local function Index()
        local cur = get()
        for i, o in ipairs(options) do
            if o.value == cur then
                return i
            end
        end
        return 1
    end
    function holder.Refresh()
        text:SetText(options[Index()].text)
    end
    local function Step(d)
        local i = (Index() - 1 + d) % #options + 1
        set(options[i].value)
        holder.Refresh()
    end
    prev:SetScript("OnClick", function()
        Step(-1)
    end)
    nextB:SetScript("OnClick", function()
        Step(1)
    end)
    holder.prev, holder.next = prev, nextB
    holder.Refresh()
    return holder
end

local function PlainCheck(parent, label, width)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    text:SetWidth(width or 200)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(label)
    cb:SetHitRectInsets(0, -math.min(text:GetStringWidth() + 4, width or 200), 0, 0)
    cb.label = text
    return cb
end

local function Dialog(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop(W().BACKDROP_DIALOG)
    f:SetBackdropColor(0, 0, 0, 1)
    f:Hide()
    tinsert(UISpecialFrames, name)
    f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 22, -20)
    f.title:SetPoint("RIGHT", -40, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    f.close = close
    return f
end

-- ---------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------
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
        local hay = Geo.Squash(r.name) .. " " .. Geo.Squash(Geo.GetMapName(r.zone) or "") .. " " .. Geo.Squash(r.author or "")
            .. " " .. Geo.Squash(R().CategoryLabel(r.cat))
        if not hay:find(q, 1, true) then
            return false
        end
    end
    return true
end

local RefreshDetail

local function RefreshRows()
    offset = ns.Clamp(offset, 0, math.max(0, #results - ROWS))
    local run = R().Run()
    for i = 1, ROWS do
        local row = rows[i]
        local r = results[i + offset]
        row.route = r
        if r then
            local c = CAT_COLOUR[r.cat] or CAT_COLOUR.other
            local zone = Geo.GetMapName(r.zone) or ""
            local mark = (run and run.id == r.id) and "|cff40ff40>|r " or ""
            row.text:SetText(mark .. r.name .. "  |cff999999" .. zone .. "|r")
            row.text:SetTextColor(c[1], c[2], c[3])
            row.right:SetText(ScoreText(r.id) .. "  |cffbbbbbb" .. #r.pts .. "|r")
            row.sel:SetShown(r.id == selectedID)
            row:Show()
        else
            row:Hide()
        end
    end
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
    local here = C_Map.GetBestMapForUnit("player")
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
        emptyText:SetText(state.tab == "mine" and L.ROUTES_EMPTY_MINE or L.ROUTES_EMPTY)
        emptyText:Show()
    else
        emptyText:Hide()
    end
    if not selectedID or not R().Get(selectedID) then
        selectedID = results[1] and results[1].id
    end
    RefreshRows()
    RefreshDetail()
    local s = ns.RoutesNet and ns.RoutesNet.Status()
    if s then
        if not s.sharing then
            netText:SetText(L.ROUTES_NET_OFF)
        else
            netText:SetText(L.ROUTES_NET:format(s.channel and L.ROUTES_NET_CHANNEL or L.ROUTES_NET_JOINING, s.peers, s.sent, s.got))
        end
    end
end
RoutesUI.Refresh = RefreshList

-- ---------------------------------------------------------------------------
-- The detail pane
-- ---------------------------------------------------------------------------
local ShowEditor, ShowText

local function Minutes(secs)
    return math.max(1, math.floor((secs or 0) / 60 + 0.5))
end

RefreshDetail = function()
    local r = selectedID and R().Get(selectedID)
    detail.route = r
    for _, b in ipairs(detail.buttons) do
        b:Hide()
    end
    detail.up:SetShown(r ~= nil)
    detail.down:SetShown(r ~= nil)
    if not r then
        detail.name:SetText("")
        detail.meta:SetText("")
        detail.body:SetText(L.ROUTES_PICK)
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

    local mine = R().IsMine(r)
    local my = R().MyVote(r.id)
    detail.votes:SetText(ScoreText(r.id) .. (my ~= 0 and ("   " .. (my > 0 and L.ROUTES_YOU_UP or L.ROUTES_YOU_DOWN)) or ""))
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
    actions[#actions + 1] = { L.ROUTE_COPY, function()
        ShowText("copy", R().Serialize(r))
    end }
    actions[#actions + 1] = { L.ROUTE_SEND_TARGET, function()
        local name = UnitIsPlayer and UnitIsPlayer("target") and UnitName("target")
        if not name or name == UnitName("player") then
            Status(L.ROUTE_SEND_NO_TARGET)
            return
        end
        ns.RoutesNet.SendTo(r.id, name)
        Status(L.ROUTE_SENT:format(r.name, name), true)
    end }
    if mine then
        actions[#actions + 1] = { L.ROUTE_EDIT, function()
            ShowEditor(r)
        end }
        if r.public then
            actions[#actions + 1] = { L.ROUTE_SHARE_AGAIN, function()
                ns.RoutesNet.Announce(r.id)
                Status(L.ROUTE_ANNOUNCED, true)
            end }
        end
        actions[#actions + 1] = { L.ROUTE_DELETE, function()
            R().Delete(r.id)
            selectedID = nil
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
            b:SetText(a[1])
            b.action = a[2]
            b:Show()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Building the window
-- ---------------------------------------------------------------------------
local function RefreshTabs()
    for _, b in ipairs(tabs) do
        if b.key == state.tab then
            b:LockHighlight()
            b.bar:Show()
        else
            b:UnlockHighlight()
            b.bar:Hide()
        end
    end
end

local function Create()
    local w = W()
    frame = CreateFrame("Frame", "WaypointTrackerRoutesFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop(w.BACKDROP_DIALOG)
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "WaypointTrackerRoutesFrame")

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "Icon")
    icon:SetSize(26, 26)
    icon:SetPoint("TOPLEFT", 20, -16)
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(L.ROUTES_TITLE)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    local newBtn = w.Button(frame, L.ROUTE_NEW, 190, 22)
    newBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
    newBtn:SetScript("OnClick", function()
        local draft = R().FromWaypoints()
        if not draft then
            Status(L.ROUTE_NEW_NONE)
            return
        end
        ShowEditor(draft)
    end)
    w.AddTooltip(newBtn, L.ROUTE_NEW, L.ROUTE_NEW_DESC)
    local importBtn = w.Button(frame, L.IMPORT, 90, 22)
    importBtn:SetPoint("RIGHT", newBtn, "LEFT", -4, 0)
    importBtn:SetScript("OnClick", function()
        ShowText("import", "")
    end)
    w.AddTooltip(importBtn, L.IMPORT, L.ROUTE_IMPORT_DESC)

    -- tabs
    local prev
    for _, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, frame)
        b:SetHeight(22)
        local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("CENTER")
        fs:SetText(L[t.label])
        b:SetFontString(fs)
        b:SetWidth(math.max(70, fs:GetStringWidth() + 20))
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetColorTexture(1, 0.82, 0, 0.9)
        b.bar:SetHeight(2)
        b.bar:SetPoint("BOTTOMLEFT", 4, 0)
        b.bar:SetPoint("BOTTOMRIGHT", -4, 0)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else
            b:SetPoint("TOPLEFT", 22, -54)
        end
        b.key = t.key
        b:SetScript("OnClick", function()
            state.tab = t.key
            offset = 0
            RefreshTabs()
            RefreshList()
        end)
        tabs[#tabs + 1] = b
        prev = b
    end

    -- filters
    searchBox = w.Box(frame, 220, L.ROUTES_SEARCH)
    searchBox:SetPoint("TOPLEFT", 22, -84)
    searchBox.edit:HookScript("OnTextChanged", function(_, user)
        if user then
            offset = 0
            RefreshList()
        end
    end)
    local cats = { { value = "all", text = L.ROUTES_ALL_CATEGORIES } }
    for _, c in ipairs(R().CATEGORIES) do
        cats[#cats + 1] = { value = c, text = R().CategoryLabel(c) }
    end
    local catPicker = Picker(frame, 190, cats, function()
        return state.cat
    end, function(v)
        state.cat = v
        offset = 0
        RefreshList()
    end)
    catPicker:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    local sortPicker = Picker(frame, 170, {
        { value = "top", text = L.ROUTES_SORT_TOP },
        { value = "new", text = L.ROUTES_SORT_NEW },
        { value = "near", text = L.ROUTES_SORT_NEAR },
    }, function()
        return state.sort
    end, function(v)
        state.sort = v
        RefreshList()
    end)
    sortPicker:SetPoint("LEFT", catPicker, "RIGHT", 8, 0)
    local zoneOnly = PlainCheck(frame, L.THIS_ZONE_ONLY, 140)
    zoneOnly:SetPoint("LEFT", sortPicker, "RIGHT", 8, 0)
    zoneOnly:SetScript("OnClick", function(self)
        ns.Set("routeThisZone", self:GetChecked() and true or false)
        offset = 0
        RefreshList()
    end)

    -- list
    local listBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 20, -116)
    listBg:SetSize(LIST_W + 4, ROWS * ROW_H + 10)
    listBg:SetBackdrop(w.BACKDROP_BOX)
    listBg:SetBackdropColor(0, 0, 0, 0.6)
    listBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    listBg:EnableMouseWheel(true)
    listBg:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        RefreshRows()
    end)
    rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, listBg)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 6, -5 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -6, 0)
        row:RegisterForClicks("LeftButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.12)
        row.sel:Hide()
        row.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.right:SetPoint("RIGHT", -4, 0)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", ns.Safe(function(self)
            selectedID = self.route and self.route.id
            RefreshRows()
            RefreshDetail()
        end))
        row:SetScript("OnDoubleClick", ns.Safe(function(self)
            if self.route then
                R().Start(self.route.id)
            end
        end))
        rows[i] = row
    end
    emptyText = listBg:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 12, -14)
    emptyText:SetPoint("RIGHT", -12, 0)
    emptyText:SetJustifyH("LEFT")
    countText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    countText:SetPoint("TOPRIGHT", listBg, "BOTTOMRIGHT", -4, -4)

    -- detail
    detail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 10, 0)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 76)
    detail:SetBackdrop(w.BACKDROP_BOX)
    detail:SetBackdropColor(0, 0, 0, 0.6)
    detail:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    detail.name = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    detail.name:SetPoint("TOPLEFT", 10, -10)
    detail.name:SetPoint("RIGHT", -10, 0)
    detail.name:SetJustifyH("LEFT")
    detail.meta = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detail.meta:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -6)
    detail.meta:SetPoint("RIGHT", -10, 0)
    detail.meta:SetJustifyH("LEFT")
    detail.meta:SetTextColor(0.8, 0.8, 0.8)
    -- votes
    detail.up = w.Button(detail, L.ROUTE_UPVOTE, 100, 22)
    detail.up:SetPoint("TOPLEFT", detail.meta, "BOTTOMLEFT", 0, -10)
    detail.down = w.Button(detail, L.ROUTE_DOWNVOTE, 100, 22)
    detail.down:SetPoint("LEFT", detail.up, "RIGHT", 6, 0)
    detail.votes = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detail.votes:SetPoint("LEFT", detail.down, "RIGHT", 8, 0)
    detail.votes:SetPoint("RIGHT", -10, 0)
    detail.votes:SetJustifyH("LEFT")
    local function VoteClick(v)
        local r = detail.route
        if not r then
            return
        end
        -- clicking your vote again takes it back
        local new = R().MyVote(r.id) == v and 0 or v
        R().Vote(r.id, new)
        RefreshList()
        Status(new == 0 and L.ROUTE_VOTE_REMOVED or L.ROUTE_VOTED, true)
    end
    detail.up:SetScript("OnClick", function()
        VoteClick(1)
    end)
    detail.down:SetScript("OnClick", function()
        VoteClick(-1)
    end)
    w.AddTooltip(detail.up, L.ROUTE_UPVOTE, L.ROUTE_VOTE_DESC)
    w.AddTooltip(detail.down, L.ROUTE_DOWNVOTE, L.ROUTE_VOTE_DESC)
    detail.body = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detail.body:SetPoint("TOPLEFT", detail.up, "BOTTOMLEFT", 0, -10)
    detail.body:SetPoint("RIGHT", -10, 0)
    detail.body:SetPoint("BOTTOM", detail, "BOTTOM", 0, 128)
    detail.body:SetJustifyH("LEFT")
    detail.body:SetJustifyV("TOP")
    detail.buttons = {}
    for i = 1, 8 do
        local b = w.Button(detail, "", 150, 24)
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        if col == 0 then
            b:SetPoint("BOTTOMLEFT", 10, 10 + (3 - line) * 28)
            b:SetPoint("RIGHT", detail, "CENTER", -3, 0)
        else
            b:SetPoint("BOTTOMRIGHT", -10, 10 + (3 - line) * 28)
            b:SetPoint("LEFT", detail, "CENTER", 3, 0)
        end
        b:SetScript("OnClick", ns.Safe(function(self)
            if self.action then
                self.action()
                RefreshList()
            end
        end))
        b:Hide()
        detail.buttons[i] = b
    end

    -- footer
    frame.status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 24, 50)
    frame.status:SetPoint("RIGHT", -24, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)
    local share = PlainCheck(frame, L.ROUTES_SHARING, 240)
    share:SetPoint("BOTTOMLEFT", 20, 16)
    share:SetScript("OnClick", function(self)
        ns.Set("routeSharing", self:GetChecked() and true or false)
        RefreshList()
    end)
    W().AddTooltip(share, L.ROUTES_SHARING, L.ROUTES_SHARING_DESC)
    local low = PlainCheck(frame, L.ROUTES_LOW_RATED, 180)
    low:SetPoint("LEFT", share, "RIGHT", 250, 0)
    low:SetScript("OnClick", function(self)
        ns.Set("routeLowRated", self:GetChecked() and true or false)
        RefreshList()
    end)
    netText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    netText:SetPoint("BOTTOMRIGHT", -24, 22)
    netText:SetJustifyH("RIGHT")

    -- keep progress and distances fresh while it's open
    local acc, dirty = 0, false
    frame.MarkDirty = function()
        dirty = true
    end
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= (dirty and 0.2 or 2) then
            acc, dirty = 0, false
            ns.Call(RefreshList)
        end
    end)
    frame:SetScript("OnShow", function()
        share:SetChecked(ns.Get("routeSharing") and true or false)
        low:SetChecked(ns.Get("routeLowRated") and true or false)
        zoneOnly:SetChecked(ns.Get("routeThisZone") and true or false)
        catPicker.Refresh()
        sortPicker.Refresh()
        RefreshTabs()
        Status("")
        RefreshList()
    end)

    RoutesUI.widgets = {
        tabs = tabs, rows = rows, detail = detail, search = searchBox.edit, new = newBtn, import = importBtn,
        cat = catPicker, sort = sortPicker, zoneOnly = zoneOnly, share = share, low = low, empty = emptyText, net = netText,
        status = frame.status,
    }
end

-- ---------------------------------------------------------------------------
-- Editor: name, category, how it's followed, a note, public or not
-- ---------------------------------------------------------------------------
local editor
local function CreateEditor()
    local w = W()
    editor = Dialog("WaypointTrackerRouteEditor", 440, 330)
    editor:SetPoint("CENTER", 0, 40)
    local y = -54
    local function Label(text)
        local fs = editor:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 24, y - 6)
        fs:SetText(text)
        return fs
    end
    Label(L.ROUTE_NAME)
    editor.name = w.Box(editor, 290, L.ROUTE_NAME_HINT)
    editor.name:SetPoint("TOPLEFT", 120, y)
    editor.name.edit:SetMaxLetters(R().MAX_NAME)
    y = y - 34
    Label(L.ROUTE_NOTE)
    editor.note = w.Box(editor, 290, L.ROUTE_NOTE_HINT)
    editor.note:SetPoint("TOPLEFT", 120, y)
    editor.note.edit:SetMaxLetters(R().MAX_NOTE)
    y = y - 38
    Label(L.ROUTE_CATEGORY)
    local cats = {}
    for _, c in ipairs(R().CATEGORIES) do
        cats[#cats + 1] = { value = c, text = R().CategoryLabel(c) }
    end
    editor.cat = Picker(editor, 220, cats, function()
        return editor.draft and editor.draft.cat
    end, function(v)
        editor.draft.cat = v
    end)
    editor.cat:SetPoint("TOPLEFT", 116, y)
    y = y - 32
    Label(L.ROUTE_MODE)
    local modes = {}
    for _, m in ipairs(R().MODES) do
        modes[#modes + 1] = { value = m, text = R().ModeLabel(m) }
    end
    editor.mode = Picker(editor, 220, modes, function()
        return editor.draft and editor.draft.mode
    end, function(v)
        editor.draft.mode = v
    end)
    editor.mode:SetPoint("TOPLEFT", 116, y)
    w.AddTooltip(editor.mode.next, L.ROUTE_MODE, L.ROUTE_MODE_DESC)
    y = y - 34
    editor.public = PlainCheck(editor, L.ROUTE_PUBLIC, 300)
    editor.public:SetPoint("TOPLEFT", 20, y)
    w.AddTooltip(editor.public, L.ROUTE_PUBLIC, L.ROUTE_PUBLIC_DESC)
    y = y - 30
    editor.info = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    editor.info:SetPoint("TOPLEFT", 24, y)
    editor.info:SetPoint("RIGHT", -24, 0)
    editor.info:SetJustifyH("LEFT")

    editor.save = w.Button(editor, L.ROUTE_SAVE, 120, 24)
    editor.save:SetPoint("BOTTOMRIGHT", -22, 18)
    editor.save:SetScript("OnClick", ns.Safe(function()
        local d = editor.draft
        d.name = editor.name.edit:GetText()
        d.note = editor.note.edit:GetText()
        d.public = editor.public:GetChecked() and true or false
        local saved = R().SaveMine(d)
        editor:Hide()
        if saved then
            selectedID = saved.id
            state.tab = "mine"
            RoutesUI.Show()
            Status(L.ROUTE_SAVED:format(saved.name), true)
        end
    end))
    local cancel = w.Button(editor, CANCEL or L.NO, 100, 24)
    cancel:SetPoint("RIGHT", editor.save, "LEFT", -6, 0)
    cancel:SetScript("OnClick", function()
        editor:Hide()
    end)
end

ShowEditor = function(r)
    if not editor then
        CreateEditor()
    end
    local d = {}
    for k, v in pairs(r) do
        d[k] = v
    end
    if d.public == nil then
        d.public = true
    end
    editor.draft = d
    editor.title:SetText(d.id and L.ROUTE_EDIT_TITLE or L.ROUTE_NEW_TITLE)
    editor.name.edit:SetText(d.name or "")
    editor.note.edit:SetText(d.note or "")
    editor.public:SetChecked(d.public and true or false)
    editor.cat.Refresh()
    editor.mode.Refresh()
    editor.info:SetText(L.ROUTES_POINTS:format(#d.pts) .. "  ·  " .. (Geo.GetMapName(d.zone) or ""))
    editor:Show()
    editor:Raise()
    editor.name.edit:SetFocus()
end
RoutesUI.ShowEditor = function(r)
    ShowEditor(r)
end

-- ---------------------------------------------------------------------------
-- Copy / import box
-- ---------------------------------------------------------------------------
local textBox
local function CreateTextBox()
    local w = W()
    textBox = Dialog("WaypointTrackerRouteText", 520, 360)
    textBox:SetPoint("CENTER", 0, 20)
    textBox.help = textBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    textBox.help:SetPoint("TOPLEFT", 22, -46)
    textBox.help:SetPoint("RIGHT", -22, 0)
    textBox.help:SetJustifyH("LEFT")
    local bg = CreateFrame("Frame", nil, textBox, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", 18, -86)
    bg:SetPoint("BOTTOMRIGHT", -18, 50)
    bg:SetBackdrop(w.BACKDROP_BOX)
    bg:SetBackdropColor(0, 0, 0, 0.8)
    local scroll = CreateFrame("ScrollFrame", "WaypointTrackerRouteTextScroll", bg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(440)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    scroll:SetScrollChild(edit)
    textBox.edit = edit
    textBox.action = w.Button(textBox, L.IMPORT, 140, 24)
    textBox.action:SetPoint("BOTTOMRIGHT", -22, 18)
    textBox.action:SetScript("OnClick", ns.Safe(function()
        local text = edit:GetText()
        local r, skipped = nil, 0
        if #text <= 100000 then
            r, skipped = R().Parse(text)
        end
        if not r then
            textBox.result:SetText(L.ROUTE_IMPORT_NOTHING)
            textBox.result:SetTextColor(1, 0.35, 0.3)
            return
        end
        textBox:Hide()
        -- a shared route with its id keeps it (and its votes); plain lines make a new one of yours
        if r.id and r.author and r.author ~= R().Me() then
            local kept = R().Keep(r)
            if kept then
                selectedID = kept.id
                state.tab = "shared"
                RoutesUI.Show()
                Status(L.ROUTE_IMPORTED:format(kept.name, #kept.pts), true)
                return
            end
        end
        r.id = (r.id and R().Get(r.id) and R().IsMine(R().Get(r.id))) and r.id or nil
        ShowEditor(r)
        if skipped > 0 then
            Status(L.ROUTE_IMPORT_SKIPPED:format(skipped))
        end
    end))
    textBox.result = textBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    textBox.result:SetPoint("BOTTOMLEFT", 24, 24)
    textBox.result:SetPoint("RIGHT", textBox.action, "LEFT", -8, 0)
    textBox.result:SetJustifyH("LEFT")
end

-- mode: "copy" (text to copy) or "import" (paste here)
ShowText = function(mode, text)
    if not textBox then
        CreateTextBox()
    end
    textBox.result:SetText("")
    textBox.edit:SetText(text or "")
    if mode == "copy" then
        textBox.title:SetText(L.ROUTE_COPY_TITLE)
        textBox.help:SetText(L.ROUTE_COPY_HELP)
        textBox.action:Hide()
    else
        textBox.title:SetText(L.ROUTE_IMPORT_TITLE)
        textBox.help:SetText(L.ROUTE_IMPORT_HELP)
        textBox.action:Show()
    end
    textBox:Show()
    textBox:Raise()
    textBox.edit:SetFocus()
    if mode == "copy" then
        textBox.edit:HighlightText()
    end
end
RoutesUI.ShowText = function(mode, text)
    ShowText(mode, text)
end

-- ---------------------------------------------------------------------------
-- "Replace your waypoints or add to them?"
-- ---------------------------------------------------------------------------
local ask
local function CreateAsk()
    local w = W()
    ask = Dialog("WaypointTrackerRouteAsk", 420, 170)
    ask:SetPoint("CENTER", 0, 120)
    ask.text = ask:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ask.text:SetPoint("TOPLEFT", 24, -50)
    ask.text:SetPoint("RIGHT", -24, 0)
    ask.text:SetJustifyH("LEFT")
    ask.remember = PlainCheck(ask, L.ROUTE_ASK_REMEMBER, 300)
    ask.remember:SetPoint("BOTTOMLEFT", 20, 50)
    local function Choose(how)
        if ask.remember:GetChecked() then
            ns.Set("routeApply", how)
            ns.Set("routeAsk", false)
        end
        ask:Hide()
        R().Apply(ask.routeID, how)
    end
    ask.replace = w.Button(ask, L.ROUTE_ASK_REPLACE, 120, 24)
    ask.replace:SetPoint("BOTTOMLEFT", 22, 18)
    ask.replace:SetScript("OnClick", ns.Safe(function()
        Choose("replace")
    end))
    ask.add = w.Button(ask, L.ROUTE_ASK_ADD, 120, 24)
    ask.add:SetPoint("LEFT", ask.replace, "RIGHT", 6, 0)
    ask.add:SetScript("OnClick", ns.Safe(function()
        Choose("add")
    end))
    ask.cancel = w.Button(ask, CANCEL or L.NO, 100, 24)
    ask.cancel:SetPoint("LEFT", ask.add, "RIGHT", 6, 0)
    ask.cancel:SetScript("OnClick", function()
        ask:Hide()
    end)
end

ns.On("ROUTE_ASK", function(id, others)
    local r = R().Get(id)
    if not r then
        return
    end
    if not ask then
        CreateAsk()
    end
    ask.routeID = id
    ask.title:SetText(L.ROUTE_ASK_TITLE:format(r.name))
    ask.text:SetText(L.ROUTE_ASK_TEXT:format(others))
    ask.remember:SetChecked(false)
    ask:Show()
    ask:Raise()
end)

-- ---------------------------------------------------------------------------
-- "How was it?"
-- ---------------------------------------------------------------------------
local feedback
local function CreateFeedback()
    local w = W()
    feedback = Dialog("WaypointTrackerRouteFeedback", 420, 150)
    feedback:SetPoint("TOP", 0, -140)
    feedback.text = feedback:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    feedback.text:SetPoint("TOPLEFT", 24, -50)
    feedback.text:SetPoint("RIGHT", -24, 0)
    feedback.text:SetJustifyH("LEFT")
    local function Answer(v)
        feedback:Hide()
        if v then
            R().Vote(feedback.routeID, v)
            ns.Print(L.ROUTE_FEEDBACK_THANKS)
        end
    end
    feedback.good = w.Button(feedback, L.ROUTE_FEEDBACK_GOOD, 120, 24)
    feedback.good:SetPoint("BOTTOMLEFT", 22, 18)
    feedback.good:SetScript("OnClick", ns.Safe(function()
        Answer(1)
    end))
    feedback.bad = w.Button(feedback, L.ROUTE_FEEDBACK_BAD, 120, 24)
    feedback.bad:SetPoint("LEFT", feedback.good, "RIGHT", 6, 0)
    feedback.bad:SetScript("OnClick", ns.Safe(function()
        Answer(-1)
    end))
    feedback.later = w.Button(feedback, L.ROUTE_FEEDBACK_LATER, 110, 24)
    feedback.later:SetPoint("LEFT", feedback.bad, "RIGHT", 6, 0)
    feedback.later:SetScript("OnClick", function()
        Answer(nil)
    end)
end

ns.On("ROUTE_FEEDBACK", function(id, secs)
    local r = R().Get(id)
    if not r then
        return
    end
    if not feedback then
        CreateFeedback()
    end
    feedback.routeID = id
    feedback.title:SetText(L.ROUTE_FEEDBACK_TITLE:format(r.name))
    local text = L.ROUTE_FEEDBACK_TEXT:format(Minutes(secs))
    local my = R().MyVote(id)
    if my ~= 0 then
        text = text .. "\n" .. (my > 0 and L.ROUTE_FEEDBACK_WAS_UP or L.ROUTE_FEEDBACK_WAS_DOWN)
    end
    feedback.text:SetText(text)
    feedback:Show()
    feedback:Raise()
    if PlaySound then
        PlaySound((SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN) or 875, "Master")
    end
end)

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
function RoutesUI.Show()
    if not ns.settings then
        return
    end
    if not frame then
        Create()
    end
    if frame:IsShown() then
        RefreshTabs()
        RefreshList()
    end
    frame:Show()
    frame:Raise()
end

function RoutesUI.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        RoutesUI.Show()
    end
end

function RoutesUI.IsShown()
    return frame and frame:IsShown() or false
end

function RoutesUI.Select(id)
    selectedID = id
    if frame and frame:IsShown() then
        RefreshList()
    end
end

function RoutesUI.SetTab(key)
    state.tab = key
    offset = 0
    if frame and frame:IsShown() then
        RefreshTabs()
        RefreshList()
    end
end

function RoutesUI.Frames()
    return { editor = editor, text = textBox, ask = ask, feedback = feedback }
end

for _, event in ipairs({ "ROUTES_CHANGED", "WAYPOINTS_CHANGED", "ACTIVE_CHANGED" }) do
    ns.On(event, function()
        if frame and frame:IsShown() then
            frame.MarkDirty()
        end
    end)
end

function WaypointTracker_ToggleRoutes()
    RoutesUI.Toggle()
end
