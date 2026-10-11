-- Arrow: the 3D arrow that points to your waypoint.
--
-- It sits just below the middle of the screen (over your character), never
-- catches mouse clicks, and is a little see-through so it feels part of
-- the world. Its text (name, distance, time) is a second frame that hangs
-- under it, or goes anywhere with "Move the text separately". Moving it is done from Edit Mode or the
-- window ("Move arrow"), never by clicking the arrow itself, so right-click
-- to attack always keeps working.
local _, ns = ...
local L, Geo, WP = ns.L, ns.Geo, ns.WP

local floor, min, max, pi, sin = math.floor, math.min, math.max, math.pi, math.sin
local TWO_PI = pi * 2

local ARROW_TEX = ns.MEDIA .. "Arrow"
local ARRIVED_TEX = ns.MEDIA .. "Arrived"
local PIN_TEX = ns.MEDIA .. "Pin"
-- Arrow.tga: 108 frames, 9 columns x 12 rows of 112x84 pixels in 1024x1024
local FRAMES, COLS, CELL_W, CELL_H, TEX = 108, 9, 112, 84, 1024
-- Arrived.tga: 64 frames, 8 x 8 of 64 pixels in 512x512
local AFRAMES, ACOLS, ACELL, ATEX = 64, 8, 64, 512
local ARROW_W, ARROW_H = 64, 48
local ARRIVED_SHOW_TIME = 3
-- default spot: centred, a little below the middle of the screen
local DEFAULT_X, DEFAULT_Y = 0, -60

local Arrow = {}
ns.Arrow = Arrow

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------
local GREEN = { 0.25, 1.00, 0.30 }
local YELLOW = { 1.00, 0.85, 0.10 }
local GOLD = { 1.00, 0.80, 0.10 }
local RED = { 1.00, 0.22, 0.15 }

local function Lerp(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- Direction colours: 0 = facing it (green), 0.5 = side (yellow), 1 = behind (red)
function Arrow.Gradient(p)
    p = ns.Clamp(p, 0, 1)
    if p < 0.5 then
        return Lerp(GREEN, YELLOW, p * 2)
    end
    return Lerp(YELLOW, RED, (p - 0.5) * 2)
end

-- Distance colours: gold while it's far, turning green as you close in.
function Arrow.DistanceColour(p)
    return Lerp(GREEN, GOLD, ns.Clamp(p, 0, 1))
end

-- How far along you are, 0 (there) .. 1 (just set). Close waypoints never
-- start fully gold.
function Arrow.DistanceFraction(dist, startDist)
    local ref = max(startDist or dist, 150)
    return ns.Clamp(dist / ref, 0, 1)
end

-- ---------------------------------------------------------------------------
-- Frames. The arrow and its text (name, distance, time to arrive) are two
-- frames: by default the text hangs under the arrow and moves with it, and
-- "Move the text separately" lets it go anywhere. Both are click-through;
-- the mouse is only on while you move them.
-- ---------------------------------------------------------------------------
local TEXT_W, TEXT_H = 220, 40

local function NewFrame(name, w, h)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:Hide()
    return f
end

local frame = NewFrame("WaypointTrackerArrow", ARROW_W, ARROW_H)
local textFrame = NewFrame("WaypointTrackerArrowText", TEXT_W, TEXT_H)
Arrow.frame, Arrow.textFrame = frame, textFrame

local arrow = frame:CreateTexture(nil, "ARTWORK")
arrow:SetTexture(ARROW_TEX)
arrow:SetAllPoints()

local arrived = frame:CreateTexture(nil, "ARTWORK")
arrived:SetTexture(ARRIVED_TEX)
arrived:SetSize(ARROW_H * 1.1, ARROW_H * 1.1)
arrived:SetPoint("CENTER")
arrived:Hide()

local pin = frame:CreateTexture(nil, "ARTWORK")
pin:SetTexture(PIN_TEX)
pin:SetSize(ARROW_H * 0.6, ARROW_H * 0.6)
pin:SetPoint("CENTER")
pin:SetVertexColor(0.7, 0.7, 0.7)
pin:Hide()

-- Text: small, outlined, easy to read over any ground.
local fontFile = (GameFontNormal and GameFontNormal:GetFont()) or STANDARD_TEXT_FONT
local function Text(size, r, g, b)
    local fs = textFrame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontFile, size, "OUTLINE")
    fs:SetTextColor(r, g, b)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    return fs
end
local title = Text(12, 1, 0.82, 0)
title:SetPoint("TOP", textFrame, "TOP", 0, 0)
title:SetWidth(TEXT_W)
local distText = Text(11, 1, 1, 1)
distText:SetPoint("TOP", title, "BOTTOM", 0, -1)
local etaText = Text(10, 0.8, 0.8, 0.8)
etaText:SetPoint("TOP", distText, "BOTTOM", 0, -1)

-- Move mode: a soft highlight around each part so you can see what you drag.
local moveParts = {}
local function MoveBox(f, pad)
    local box = f:CreateTexture(nil, "BACKGROUND")
    box:SetPoint("TOPLEFT", -pad, pad)
    box:SetPoint("BOTTOMRIGHT", pad, -pad)
    box:SetColorTexture(1, 0.82, 0, 0.18)
    box:Hide()
    moveParts[#moveParts + 1] = box
    for _, spec in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 0.82, 0, 0.8)
        t:SetHeight(1)
        t:SetPoint(spec[1], box, spec[1])
        t:SetPoint(spec[2], box, spec[2])
        t:Hide()
        moveParts[#moveParts + 1] = t
    end
end
MoveBox(frame, 8)
MoveBox(textFrame, 4)

local function SetShown(on)
    frame:SetShown(on)
    textFrame:SetShown(on)
end

-- ---------------------------------------------------------------------------
-- Position / size / moving
-- ---------------------------------------------------------------------------
-- Each part's spot is kept per Edit Mode layout (Arrow.layout is the active
-- layout's name), falling back to the one spot saved from the window.
local SPOTS = {
    arrow = { key = "arrowPos", layouts = "arrowLayouts" },
    text = { key = "textPos", layouts = "textLayouts" },
}

function Arrow.IsTextSeparate()
    return ns.Get("textSeparate") and true or false
end

local function SavedPosition(which)
    local s = SPOTS[which]
    local layouts = ns.Get(s.layouts)
    if Arrow.layout and type(layouts) == "table" and type(layouts[Arrow.layout]) == "table" then
        return layouts[Arrow.layout]
    end
    return ns.Get(s.key)
end

-- which: "arrow" (default) or "text"
function Arrow.SavePosition(pos, which)
    local s = SPOTS[which or "arrow"]
    if Arrow.layout then
        local layouts = ns.Get(s.layouts)
        layouts = type(layouts) == "table" and layouts or {}
        layouts[Arrow.layout] = pos
        ns.Set(s.layouts, layouts)
    end
    -- also the spot for layouts where it wasn't placed yet
    ns.Set(s.key, pos)
end

local function CurrentPoint(f)
    local point, _, relPoint, x, y = f:GetPoint()
    return point and { point, relPoint, x, y } or nil
end

-- Remembers where a part was dragged to.
function Arrow.SaveCurrentPoint(which)
    local pos = CurrentPoint(which == "text" and textFrame or frame)
    if pos then
        Arrow.SavePosition(pos, which)
    end
end

function Arrow.SetLayout(name)
    if name ~= Arrow.layout then
        Arrow.layout = name
        Arrow.ApplyPosition()
    end
end

local function ApplyPosition()
    frame:ClearAllPoints()
    local point, rel, x, y = ns.SavedPoint(SavedPosition("arrow"))
    if point then
        frame:SetPoint(point, UIParent, rel, x, y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
    end
    textFrame:ClearAllPoints()
    point = nil
    if Arrow.IsTextSeparate() then
        point, rel, x, y = ns.SavedPoint(SavedPosition("text"))
    end
    if point then
        textFrame:SetPoint(point, UIParent, rel, x, y)
    else
        textFrame:SetPoint("TOP", frame, "BOTTOM", 0, 2)
    end
end

Arrow.ApplyPosition = ApplyPosition

local function ApplyLayout()
    frame:SetScale(ns.Clamp(tonumber(ns.Get("arrowScale")) or 1, 0.4, 3))
    textFrame:SetScale(ns.Clamp(tonumber(ns.Get("textScale")) or 1, 0.4, 3))
    textFrame:SetAlpha(ns.Clamp(tonumber(ns.Get("textAlpha")) or 1, 0, 1))
end

-- Turning "move the text separately" on keeps the text where it is on
-- screen (under the arrow), from where it can then be dragged away.
local function PinTextWhereItIs()
    local x, y = textFrame:GetCenter()
    if x and y then
        Arrow.SavePosition({ "CENTER", "BOTTOMLEFT", x, y }, "text")
    end
end

Arrow.moving = false

-- Turn "move" mode on or off (only from the window's Move button).
function Arrow.SetMoving(on)
    on = on and true or false
    Arrow.moving = on
    frame:EnableMouse(on)
    textFrame:EnableMouse(on)
    for _, t in ipairs(moveParts) do
        t:SetShown(on)
    end
    if not on then
        frame:StopMovingOrSizing()
        textFrame:StopMovingOrSizing()
    end
    ns.Fire("ARROW_MOVING", on)
end

-- Starts dragging a part. While grouped, dragging the text moves the arrow
-- (and the text with it).
function Arrow.StartDrag(which)
    if which == "text" and Arrow.IsTextSeparate() then
        textFrame:StartMoving()
    else
        frame:StartMoving()
    end
end

function Arrow.StopDrag()
    frame:StopMovingOrSizing()
    textFrame:StopMovingOrSizing()
    -- read both spots before saving: saving one re-applies the other
    local arrowPos, textPos = CurrentPoint(frame), Arrow.IsTextSeparate() and CurrentPoint(textFrame)
    if arrowPos then
        Arrow.SavePosition(arrowPos, "arrow")
    end
    if textPos then
        Arrow.SavePosition(textPos, "text")
    end
end

-- Back to the defaults: over your character, default size and visibility,
-- text under the arrow.
local RESET_KEYS = { "arrowScale", "arrowAlpha", "textScale", "textAlpha", "textSeparate" }
function Arrow.Reset()
    for _, key in ipairs(RESET_KEYS) do
        ns.Set(key, ns.defaults[key])
    end
    Arrow.SavePosition(nil, "text")
    Arrow.SavePosition(nil, "arrow")
    ApplyPosition()
    ApplyLayout()
end
Arrow.ResetPosition = Arrow.Reset

frame:SetScript("OnDragStart", function()
    if Arrow.moving then
        Arrow.StartDrag("arrow")
    end
end)
frame:SetScript("OnDragStop", Arrow.StopDrag)
textFrame:SetScript("OnDragStart", function()
    if Arrow.moving then
        Arrow.StartDrag("text")
    end
end)
textFrame:SetScript("OnDragStop", Arrow.StopDrag)

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------
local lastArrowIndex, lastArrivedIndex
local function SetArrowIndex(i)
    if i == lastArrowIndex then
        return
    end
    lastArrowIndex = i
    local col, row = i % COLS, floor(i / COLS)
    arrow:SetTexCoord(col * CELL_W / TEX, (col + 1) * CELL_W / TEX, row * CELL_H / TEX, (row + 1) * CELL_H / TEX)
end

local function SetArrivedIndex(i)
    if i == lastArrivedIndex then
        return
    end
    lastArrivedIndex = i
    local col, row = i % ACOLS, floor(i / ACOLS)
    arrived:SetTexCoord(col * ACELL / ATEX, (col + 1) * ACELL / ATEX, row * ACELL / ATEX, (row + 1) * ACELL / ATEX)
end

-- Frame of the sprite sheet for a turn of `rel` radians (counter-clockwise).
function Arrow.IndexFor(rel)
    return floor(rel / TWO_PI * FRAMES + 0.5) % FRAMES
end

-- mode: "arrow" | "arrived" | "pin"
local mode
local function SetMode(m)
    if m == mode then
        return
    end
    mode = m
    arrow:SetShown(m == "arrow")
    arrived:SetShown(m == "arrived")
    pin:SetShown(m == "pin")
end

local function SetTexts(t, d, e)
    title:SetText(ns.Get("showTitle") and t or "")
    distText:SetText(ns.Get("showDistance") and d or "")
    etaText:SetText(ns.Get("showETA") and e or "")
end

local function ArrowColour(dist, rel, wp)
    local cm = ns.Get("colorMode")
    if cm == "single" then
        local c = ns.Get("singleColor")
        return c.r or 1, c.g or 0.82, c.b or 0
    elseif cm == "direction" then
        local off = rel > pi and (TWO_PI - rel) or rel -- 0..pi
        return Arrow.Gradient(off / pi)
    end
    return Arrow.DistanceColour(Arrow.DistanceFraction(dist, wp and wp.startDist))
end

-- ---------------------------------------------------------------------------
-- Update loop. Runs on a separate always-on frame so arrival still works
-- while the arrow is hidden.
-- ---------------------------------------------------------------------------
local fade = 1
local arrivedUntil, arrivedName = 0, nil
local closestTimer, arrivalTimer = 0, 0
local speed, speedTimer, speedLastDist, speedWp = nil, 0, nil, nil
local previewAngle = 0

ns.On("ARRIVED", function(wp)
    arrivedUntil = GetTime() + ARRIVED_SHOW_TIME
    arrivedName = WP.ShortName(wp)
end)

ns.On("ACTIVE_CHANGED", function()
    speed, speedLastDist, speedWp = nil, nil, nil
end)

local function ShouldShow()
    if Arrow.moving or Arrow.editing then
        return true
    end
    if not ns.Get("arrowShown") then
        return false
    end
    if ns.Get("hideInCombat") and InCombatLockdown() then
        return false
    end
    if ns.Get("hideOnTaxi") and UnitOnTaxi("player") then
        return false
    end
    return true
end

local function UpdateSpeed(wp, dist, dt)
    if speedWp ~= wp then
        speedWp, speedLastDist, speed, speedTimer = wp, dist, nil, 0
        return
    end
    speedTimer = speedTimer + dt
    if speedTimer < 0.5 then
        return
    end
    local v = (speedLastDist - dist) / speedTimer -- yards per second towards it
    speed = speed and (speed * 0.7 + v * 0.3) or v
    speedLastDist, speedTimer = dist, 0
end

-- The arrow is a guide, not a sign: slightly see-through, and softer again
-- while you're already heading the right way.
local function SetFade(target, dt)
    fade = fade + (target - fade) * min(1, dt * 5)
    frame:SetAlpha(ns.Get("arrowAlpha") * fade)
end

local function Update(dt)
    local now = GetTime()
    local wp = WP.GetActive()
    local show = ShouldShow()

    -- "You have arrived!" moment
    if not Arrow.moving and (now < arrivedUntil or (wp and wp.arrivedAt)) then
        -- keep checking the waypoint we're standing on (for walking away)
        if wp and wp.arrivedAt then
            local dist = Geo.GetVector(wp)
            if dist then
                WP.CheckArrival(wp, dist)
            end
        end
        if not show then
            SetShown(false)
            return
        end
        SetShown(true)
        SetMode("arrived")
        SetArrivedIndex(floor(now * 40) % AFRAMES)
        arrived:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
        arrived:SetPoint("CENTER", frame, "CENTER", 0, sin(now * 5) * 3)
        SetTexts(wp and wp.arrivedAt and WP.ShortName(wp) or arrivedName or "", L.ARRIVED, "")
        distText:SetText(L.ARRIVED) -- even with the distance hidden
        SetFade(1, dt)
        return
    end

    -- a slowly turning preview while moving the arrow, or while the window
    -- is open and there's no waypoint, so it can be placed and sized
    if Arrow.moving or (Arrow.editing and not wp) or (not wp and Arrow.preview and ns.Get("arrowShown")) then
        SetShown(true)
        SetMode("arrow")
        previewAngle = (previewAngle + dt * 0.8) % TWO_PI
        SetArrowIndex(Arrow.IndexFor(previewAngle))
        arrow:SetVertexColor(Arrow.DistanceColour((sin(now * 0.8) + 1) / 2))
        title:SetText(L.ADDON_TITLE)
        distText:SetText(Arrow.moving and L.MOVING_HINT or "")
        etaText:SetText("")
        SetFade(1, dt)
        return
    end
    if not wp then
        SetShown(false)
        return
    end

    local dist, bearing = Geo.GetVector(wp)

    if dist then
        if not wp.startDist then
            wp.startDist = dist
        end
        arrivalTimer = arrivalTimer + dt
        if arrivalTimer >= 0.1 then
            arrivalTimer = 0
            if WP.CheckArrival(wp, dist) then
                return
            end
        end
        UpdateSpeed(wp, dist, dt)
    end

    -- optional: always follow the nearest waypoint
    if ns.Get("autoClosest") and WP.Count() > 1 then
        closestTimer = closestTimer + dt
        if closestTimer >= 1 then
            closestTimer = 0
            local best, bestDist = WP.Closest()
            if best and best ~= wp and bestDist and (not dist or bestDist < dist - 5) then
                WP.SetActive(best, true)
                return
            end
        end
    end

    if not show then
        SetShown(false)
        return
    end
    SetShown(true)

    local name = WP.ShortName(wp)
    -- set where you stand and not walked away from yet
    if dist and WP.IsWaiting(wp) then
        SetMode("pin")
        SetFade(1, dt)
        SetTexts(name, L.YOU_ARE_HERE, "")
        distText:SetText(L.YOU_ARE_HERE) -- even with the distance hidden
        return
    end
    -- Real routes: the way there, one step at a time, not the straight line
    local steer = ns.Travel and ns.Travel.Steer(wp)
    if steer then
        local distLine = steer.dist and Geo.FormatDistance(steer.dist) or ""
        if steer.wait then
            distLine = L.TRAVEL_LEAVES_IN:format(Geo.FormatTime(steer.wait))
        end
        local etaLine = steer.total and L.TRAVEL_TOTAL:format(steer.sub, Geo.FormatTime(steer.total)) or steer.sub
        local facing = steer.bearing and Geo.GetFacing()
        if facing then
            local rel = Geo.RelativeAngle(steer.bearing, facing)
            SetMode("arrow")
            SetArrowIndex(Arrow.IndexFor(rel))
            arrow:SetVertexColor(ArrowColour(dist or steer.dist or 0, rel, wp))
        else
            SetMode("pin")
        end
        SetFade(1, dt)
        title:SetText(steer.title or name) -- always shown: it says what to do next
        distText:SetText(ns.Get("showDistance") and distLine or "")
        etaText:SetText(ns.Get("showETA") and etaLine or "")
        return
    end
    if dist and bearing then
        local facing = Geo.GetFacing()
        if facing then
            local rel = Geo.RelativeAngle(bearing, facing)
            SetMode("arrow")
            SetArrowIndex(Arrow.IndexFor(rel))
            arrow:SetVertexColor(ArrowColour(dist, rel, wp))

            local target = 1
            if ns.Get("fadeOnCourse") then
                local off = rel > pi and (TWO_PI - rel) or rel
                if off < 0.30 then
                    target = 0.55
                elseif off < 0.60 then
                    target = 0.55 + (off - 0.30) / 0.30 * 0.45
                end
            end
            SetFade(target, dt)

            local eta = ""
            if speed and speed > 0.5 then
                eta = L.ETA:format(Geo.FormatTime(dist / speed))
            end
            SetTexts(name, Geo.FormatDistance(dist), eta)
            return
        end
    end

    -- can't point: other continent, inside an instance, etc.
    SetMode("pin")
    SetFade(1, dt)
    if bearing == "continent" then
        SetTexts(name, L.ANOTHER_CONTINENT, "")
        etaText:SetText(Geo.GetMapName(wp.m))
    else
        SetTexts(name, L.CANT_TRACK_HERE, "")
    end
end

local driver = CreateFrame("Frame")
local acc = 0
local safeUpdate = ns.Safe(Update)
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.016 then
        return
    end
    local dt = acc
    acc = 0
    safeUpdate(min(dt, 1))
end)
driver:Hide()

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
-- Blizzard's Edit Mode is open: show the arrow so it can be placed there.
function Arrow.SetEditMode(on)
    Arrow.editing = on and true or false
    if on and Arrow.moving then
        Arrow.SetMoving(false)
    end
end

function Arrow.SetPreview(on)
    Arrow.preview = on and true or false
end

ns.On("LOGIN", function()
    ApplyPosition()
    ApplyLayout()
    SetArrowIndex(0)
    SetArrivedIndex(0)
    driver:Show()
end)

ns.On("SETTING_CHANGED", function(key, value)
    if key == "textSeparate" and value and not ns.SavedPoint(SavedPosition("text")) then
        PinTextWhereItIs()
    end
    if key == nil or key == "textSeparate" then
        ApplyPosition()
    end
    for _, s in pairs(SPOTS) do
        if key == s.key or key == s.layouts then
            ApplyPosition()
        end
    end
    ApplyLayout()
end)

-- Leaving move mode when combat starts keeps the mouse free for fighting.
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if Arrow.moving then
        Arrow.SetMoving(false)
    end
end)

function WaypointTracker_ToggleArrow()
    local shown = not ns.Get("arrowShown")
    ns.Set("arrowShown", shown)
    ns.Print(shown and L.ARROW_SHOWN or L.ARROW_HIDDEN, true)
end
