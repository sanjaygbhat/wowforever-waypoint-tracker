-- A route's area, continent or world map, with a lightweight pane preview.
local _, ns = ...
local L, Geo, Widgets = ns.L, ns.Geo, ns.Widgets
local RouteMap = {}
ns.RouteMap = RouteMap

local artOf = {}
local previewOf = setmetatable({}, { __mode = "k" })
local INDICATOR = "Interface\\COMMON\\Indicator-"

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function Positive(n)
    return type(n) == "number" and n > 0 and n < math.huge
end

local function Padded(n)
    local size = 16
    while size < n do size = size * 2 end
    return size
end

-- Layer 1, in map pixels. Match MapCanvasDetailLayer and the exploration
-- provider's row-major files and power-of-two padding on partial tiles.
function RouteMap.Art(mapID)
    if not mapID or not C_Map or not Call(C_Map.MapHasArt, mapID) then return nil end
    local artID = Call(C_Map.GetMapArtID, mapID)
    local key = tostring(mapID) .. ":" .. tostring(artID)
    if artOf[key] then return artOf[key] end
    local layers = Call(C_Map.GetMapArtLayers, mapID)
    local layer = type(layers) == "table" and layers[1]
    local files = Call(C_Map.GetMapArtLayerTextures, mapID, 1)
    if type(layer) ~= "table" or type(files) ~= "table"
        or not Positive(layer.layerWidth) or not Positive(layer.layerHeight)
        or not Positive(layer.tileWidth) or not Positive(layer.tileHeight) then return nil end
    local w, h, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
    local cols, rows = math.ceil(w / tw), math.ceil(h / th)
    local art = { w = w, h = h, tiles = {} }
    for row = 1, rows do
        for col = 1, cols do
            local file = files[(row - 1) * cols + col]
            if not file then return nil end
            art.tiles[#art.tiles + 1] = {
                file = file, x = (col - 1) * tw, y = (row - 1) * th,
                w = tw, h = th, tcx = 1, tcy = 1, top = false,
            }
        end
    end
    local explored = C_MapExplorationInfo and Call(C_MapExplorationInfo.GetExploredMapTextures, mapID)
    for _, info in ipairs(type(explored) == "table" and explored or {}) do
        if not info.isShownByMouseOver and Positive(info.textureWidth) and Positive(info.textureHeight)
            and type(info.fileDataIDs) == "table" then
            local wide, tall = math.ceil(info.textureWidth / tw), math.ceil(info.textureHeight / th)
            for row = 1, tall do
                for col = 1, wide do
                    local file = info.fileDataIDs[(row - 1) * wide + col]
                    local width = math.min(tw, info.textureWidth - (col - 1) * tw)
                    local height = math.min(th, info.textureHeight - (row - 1) * th)
                    if file then
                        art.tiles[#art.tiles + 1] = {
                            file = file, x = (info.offsetX or 0) + (col - 1) * tw,
                            y = (info.offsetY or 0) + (row - 1) * th,
                            w = width, h = height,
                            tcx = width / (col < wide and tw or Padded(width)),
                            tcy = height / (row < tall and th or Padded(height)),
                            top = info.isDrawOnTopLayer and true or false,
                        }
                    end
                end
            end
        end
    end
    artOf[key] = art
    return art
end

function RouteMap.MapFor(r)
    if not r then return nil, 0 end
    local cached = previewOf[r]
    if not cached then
        local map, shown = Geo.CommonMap(r.pts)
        cached = { map, shown }
        previewOf[r] = cached
    end
    return cached[1], cached[2]
end

local function StopTitle(r, i)
    if ns.Routes and ns.Routes.StopTitle then return ns.Routes.StopTitle(r, i) end
    local p = r.pts[i]
    return p and p.t and p.t ~= "" and p.t or L.ROUTE_UNNAMED
end

local function HandIn(title)
    local prefix = L.ROUTE_STOP_END:match("^(.-)%%s")
    return prefix and prefix ~= "" and title:sub(1, #prefix) == prefix
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function PinTooltip(pin)
    local r, i = pin.route, pin.index
    if not r or not GameTooltip then return end
    local p = r.pts[i]
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.ROUTE_STOP_N:format(i, StopTitle(r, i)), 1, 0.82, 0)
    if i == 1 then GameTooltip:AddLine(L.ROUTE_PREVIEW_START, 0.4, 1, 0.4) end
    GameTooltip:AddLine(Geo.GetMapName(p.m) .. "  " .. Geo.FormatCoords(p.x, p.y), 0.7, 0.7, 0.7)
    local dist = Call(Geo.GetVector, p)
    if dist then GameTooltip:AddLine(Geo.FormatDistance(dist), 0.8, 0.8, 0.8) end
    GameTooltip:Show()
end

function RouteMap.Create(parent, w, h)
    local ok, map = pcall(CreateFrame, "Button", nil, parent, "BackdropTemplate")
    if not ok then map = CreateFrame("Button", nil, parent) end
    map:SetSize(w, h)
    if map.SetBackdrop then
        map:SetBackdrop(Widgets.BACKDROP_BOX)
        map:SetBackdropColor(0, 0, 0, 0.6)
    end
    map.pins, map.lines = {}, {}
    local pinPool, linePool, textures = {}, {}, {}
    local art = CreateFrame("Frame", nil, map)
    map.art = art
    local clipped = art.SetClipsChildren and pcall(art.SetClipsChildren, art, true)
    -- Clip a child's regions, as Blizzard's map canvas does for its tiles.
    art.Tiles = CreateFrame("Frame", nil, art)
    art.Tiles:SetAllPoints(art)
    art.Tiles:SetFrameLevel(art:GetFrameLevel())
    local bg = art.Tiles:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.1, 1)
    local grid = {}
    for i = 1, 5 do
        grid[i] = art:CreateTexture(nil, "BACKGROUND")
        grid[i]:SetColorTexture(1, 1, 1, 0.05)
    end
    local name = art:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
    name:SetPoint("CENTER")
    name:SetWordWrap(false)

    -- Keep the caption and hover above the child frames used by pins.
    local overlay = CreateFrame("Frame", nil, map)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(art:GetFrameLevel() + 4)
    local highlight = overlay:CreateTexture(nil, "OVERLAY", nil, 4)
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.3)
    highlight:Hide()
    map.captionBg = overlay:CreateTexture(nil, "BACKGROUND")
    map.captionBg:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT")
    map.captionBg:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT")
    map.captionBg:SetHeight(16)
    map.captionBg:SetColorTexture(0, 0, 0, 0.55)
    map.caption = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    map.caption:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", 4, 4)
    map.caption:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -4, 4)
    map.caption:SetJustifyH("RIGHT")
    map.caption:SetWordWrap(false)
    map.elsewhere = map:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    map.elsewhere:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -4)
    map.elsewhere:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, -4)
    map.elsewhere:SetJustifyH("LEFT")
    map.player = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
    map.player:SetTexture("Interface\\Minimap\\MinimapArrow")
    map.player:SetSize(16, 16)

    local function Click(_, button)
        if button == "LeftButton" and map.route and map.onClick then
            map.onClick(map.route, map.mapID)
        end
    end
    map:SetScript("OnClick", ns.Safe(Click))
    map:SetScript("OnEnter", ns.Safe(function()
        if not map.route then return end
        highlight:Show()
        if GameTooltip then
            GameTooltip:SetOwner(map, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L.ROUTE_PREVIEW_TOOLTIP, 1, 0.82, 0, true)
            GameTooltip:Show()
        end
    end))
    map:SetScript("OnLeave", function() highlight:Hide(); HideTooltip() end)
    map:SetScript("OnHide", function() highlight:Hide(); HideTooltip() end)

    local function Clear()
        for _, pin in ipairs(pinPool) do pin:Hide(); pin.route = nil end
        for _, line in ipairs(linePool) do line:Hide() end
        for _, tex in ipairs(textures) do tex:Hide(); tex:SetTexture(nil) end
        wipe(map.pins)
        wipe(map.lines)
        map.artData = nil
        map.player:Hide()
        map.caption:Hide()
        map.captionBg:Hide()
        map.elsewhere:Hide()
        map.elsewhere:SetText("")
        name:Hide()
        for _, tex in ipairs(grid) do tex:Hide() end
        highlight:Hide()
    end

    function map:GetMapID() return self.mapID end

    function map:Refresh()
        self.player:Hide()
        if not self.route or not self.mapID then return end
        local m, x, y = Call(Geo.GetPlayerMapPosition)
        if not m then return end
        x, y = Geo.ProjectToMap(m, x, y, self.mapID)
        if not x or not y then return end
        self.player:ClearAllPoints()
        self.player:SetPoint("CENTER", art, "TOPLEFT", x * art:GetWidth(), -y * art:GetHeight())
        local facing = Call(Geo.GetFacing)
        if self.player.SetRotation then pcall(self.player.SetRotation, self.player, facing or 0) end
        self.player:Show()
    end

    function map:SetRoute(r)
        Clear()
        self.route, self.mapID, self.shown = r, nil, 0
        if not r or not r.pts or #r.pts == 0 then art:Hide(); self:Hide(); return end
        if ns.Routes and ns.Routes.Prepare then ns.Routes.Prepare(r) end
        self.mapID = RouteMap.MapFor(r)
        if not self.mapID then art:Hide(); self:Hide(); return end
        local data = clipped and RouteMap.Art(self.mapID) or nil
        self.artData = data
        local width, height = data and data.w or 3, data and data.h or 2
        local scale = math.min(self:GetWidth() / width, self:GetHeight() / height)
        local aw, ah = width * scale, height * scale
        art:ClearAllPoints()
        art:SetSize(aw, ah)
        art:SetPoint("CENTER", self, "CENTER")
        art:Show()
        local zone = Geo.GetMapName(self.mapID)
        if data then
            local baseCount = math.ceil(width / data.tiles[1].w) * math.ceil(height / data.tiles[1].h)
            for i, tile in ipairs(data.tiles) do
                local tex = textures[i]
                if not tex then tex = art.Tiles:CreateTexture(nil, "BACKGROUND"); textures[i] = tex end
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", art, "TOPLEFT", tile.x * scale, -tile.y * scale)
                tex:SetSize(tile.w * scale, tile.h * scale)
                if tex.SetDrawLayer then
                    tex:SetDrawLayer("BACKGROUND", i <= baseCount and 0 or (tile.top and 2 or 1))
                end
                tex:SetTexture(tile.file, nil, nil, "TRILINEAR")
                tex:SetTexCoord(0, tile.tcx, 0, tile.tcy)
                tex:Show()
            end
            self.caption:SetText(zone .. " \194\183 " .. L.ROUTE_PREVIEW_OPEN)
        else
            for i, tex in ipairs(grid) do
                tex:ClearAllPoints()
                if i <= 3 then
                    tex:SetSize(1, ah)
                    tex:SetPoint("TOPLEFT", art, "TOPLEFT", aw * i / 4, 0)
                else
                    tex:SetSize(aw, 1)
                    tex:SetPoint("TOPLEFT", art, "TOPLEFT", 0, -ah * (i - 3) / 3)
                end
                tex:Show()
            end
            name:SetWidth(math.max(1, aw - 16))
            name:SetText(zone)
            name:Show()
            self.caption:SetText(L.ROUTE_PREVIEW_NO_ART:format(zone))
        end
        self.caption:Show()
        self.captionBg:Show()
        local positions, missing, seen = {}, {}, {}
        for i, p in ipairs(r.pts) do
            local x, y = Geo.ProjectToMap(p.m, p.x, p.y, self.mapID)
            if x and y then
                x, y = x * aw, y * ah
                positions[i] = { x, y }
                local n = #self.pins + 1
                local pin = pinPool[n]
                if not pin then
                    pin = CreateFrame("Button", nil, self)
                    pin:SetSize(14, 14)
                    pin:SetFrameLevel(art:GetFrameLevel() + 2)
                    pin.Icon = pin:CreateTexture(nil, "OVERLAY", nil, 2)
                    pin.Icon:SetAllPoints()
                    pin.Number = pin:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
                    if pin.Number.SetDrawLayer then pin.Number:SetDrawLayer("OVERLAY", 3) end
                    pin.Number:SetPoint("CENTER")
                    pin:SetScript("OnClick", ns.Safe(Click))
                    pin:SetScript("OnEnter", ns.Safe(PinTooltip))
                    pin:SetScript("OnLeave", HideTooltip)
                    pinPool[n] = pin
                end
                pin.route, pin.index = r, i
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", art, "TOPLEFT", x, -y)
                local grey = i ~= 1 and HandIn(StopTitle(r, i))
                pin.Icon:SetTexture(INDICATOR .. (i == 1 and "Green" or grey and "Gray" or "Yellow"))
                pin.Number:SetText(tostring(i))
                pin.Number:SetTextColor(grey and 1 or 0, grey and 1 or 0, grey and 1 or 0)
                local label = #r.pts <= 40
                if label then
                    for j = 1, i - 1 do
                        local prev = positions[j]
                        if prev and (prev[1] - x)^2 + (prev[2] - y)^2 < 100 then label = false; break end
                    end
                end
                pin.Number:SetShown(label)
                pin:Show()
                self.pins[n] = pin
            elseif not seen[p.m] then
                seen[p.m] = true
                missing[#missing + 1] = Geo.GetMapName(p.m)
            end
        end
        self.shown = #self.pins
        local function Line(a, b, alpha)
            if not positions[a] or not positions[b] or #self.lines >= 200 then return end
            local n = #self.lines + 1
            local line = linePool[n]
            if not line then
                line = Call(art.CreateLine, art, nil, "OVERLAY", nil, 1)
                if not line or not line.SetStartPoint or not line.SetEndPoint then return end
                linePool[n] = line
            end
            line:SetStartPoint("TOPLEFT", art, positions[a][1], -positions[a][2])
            line:SetEndPoint("TOPLEFT", art, positions[b][1], -positions[b][2])
            line:SetThickness(2)
            line:SetColorTexture(1, 0.82, 0, 1)
            line:SetAlpha(alpha)
            line:Show()
            self.lines[n] = line
        end
        if r.mode == "order" or r.mode == "loop" then
            for i = 1, #r.pts - 1 do Line(i, i + 1, 0.85) end
            if r.mode == "loop" and #r.pts > 1 then Line(#r.pts, 1, 0.4) end
        end
        if self.shown < #r.pts then
            self.elsewhere:SetText(L.ROUTE_PREVIEW_ELSEWHERE:format(#r.pts - self.shown, table.concat(missing, ", ")))
            self.elsewhere:Show()
        end
        self:Show()
        self:Refresh()
    end

    map:SetRoute(nil)
    return map
end
