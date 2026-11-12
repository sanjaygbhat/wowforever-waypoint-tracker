-- Build 1.60.1 uses ObjectiveTrackerFrame and QuestObjectiveTracker blocks.
-- Only post-hooks touch Blizzard code; all scripts below belong to our buttons.
local _, ns = ...
local L, Follow = ns.L, ns.Follow
local Tracker = { buttons = {} }
ns.QuestTracker = Tracker
local bindings, hooked, pool = {}, {}, {}
local pending = false
local Refresh, Schedule, Arm

local function PlainLeft(button)
    return ns.Str(button) == "LeftButton"
        and not (IsShiftKeyDown and ns.Plain(IsShiftKeyDown()))
        and not (IsControlKeyDown and ns.Plain(IsControlKeyDown()))
        and not (IsAltKeyDown and ns.Plain(IsAltKeyDown()))
        and not (IsModifiedClick and ns.Plain(IsModifiedClick()))
end

local function QuestID(block, module)
    if not block or block.parentModule ~= module or not ns.Plain(block.used) then return end
    return ns.Int(ns.Num(block.id))
end

local function Track(block, module, mouseButton)
    if not ns.Get("questClickTrack") or not PlainLeft(mouseButton) then return end
    local id = QuestID(block, module)
    if not id then return end
    if not Follow.TrackQuest(id) then
        ns.Print(L.QUEST_TRACK_NO_POSITION, true)
        return
    end
    local button = bindings[block]
    if button then
        button.flashUntil = GetTime() + 0.45
        Arm(button)
    end
end

-- Blizzard's quest icon in front of each tracked quest (the "..." or "?"
-- POI button) super-tracks the quest. Selecting it also takes the arrow to
-- the quest's current objective; deselecting it lets go of that quest.
local poiHooked = {}
local function POIClick(poi, mouseButton)
    if not ns.Get("questClickTrack") or not PlainLeft(mouseButton) then return end
    local id = type(poi.GetQuestID) == "function" and ns.Int(ns.Num(poi:GetQuestID()))
    if not id then return end
    local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
        and ns.Int(ns.Num(C_SuperTrack.GetSuperTrackedQuestID()))
    if super ~= id then
        Follow.StopQuest(id)
        return
    end
    if not Follow.TrackQuest(id) then ns.Print(L.QUEST_TRACK_NO_POSITION, true) end
end

local function HookPOI(block)
    local poi = block.poiButton
    if poi and not poiHooked[poi] and type(poi.HookScript) == "function" then
        poiHooked[poi] = true
        poi:HookScript("OnClick", ns.Safe(POIClick))
    end
end

local function Valid(button)
    return ns.Get("questClickTrack") and button.block
        and bindings[button.block] == button and QuestID(button.block, button.module)
end

-- Each button remembers what it last set (wtAlpha, wtMouse, wtShown, wtTint,
-- wtAnchor); these setters are the only writers, so a value that is already
-- in place is never set again.
local function SetAlpha(button, alpha)
    if button.wtAlpha ~= alpha then
        button.wtAlpha = alpha
        button:SetAlpha(alpha)
    end
end

local function SetMouse(button, enabled)
    if button.wtMouse ~= enabled then
        button.wtMouse = enabled
        button:EnableMouse(enabled)
    end
end

local function SetShown(button, shown)
    if button.wtShown ~= shown then
        button.wtShown = shown
        if shown then button:Show() else button:Hide() end
    end
end

local function SetTint(button, tracked)
    if button.wtTint ~= tracked then
        button.wtTint = tracked
        button.icon:SetVertexColor(tracked and 0.35 or 1, 1, tracked and 0.55 or 1)
    end
end

-- Other code (a tracker skin, Blizzard) can show, hide, fade or disable our
-- overlays behind those setters. At each layout, out of combat, take the real
-- state as the remembered one so the setters below put it right again. Alpha
-- is stored as float32 by the client, hence the tolerance.
local function Resync(button)
    local shown = ns.Plain(button:IsShown())
    if type(shown) == "boolean" then button.wtShown = shown end
    if type(button.IsMouseEnabled) == "function" then
        local mouse = ns.Plain(button:IsMouseEnabled())
        if type(mouse) == "boolean" then button.wtMouse = mouse end
    end
    local alpha = ns.Num(button:GetAlpha())
    if alpha and math.abs(alpha - (button.wtAlpha or -1)) > 0.001 then button.wtAlpha = alpha end
end

-- One step of a visible button's fade. Returns true while it must run again
-- next frame (fading, hovered or flashing).
local function Fade(button, elapsed)
    local id = Valid(button)
    if not id then
        SetAlpha(button, 0)
        -- Never intercept a header belonging to a different pooled module.
        if not ns.InCombat() then SetMouse(button, false) end
        return false
    end
    if not ns.InCombat() then SetMouse(button, true) end
    local tracked = Follow.GetTrackedQuestID() == id
    local hovered = button.hovered or (button.header and ns.Plain(button.header:IsMouseOver()))
    local flashing = (button.flashUntil or 0) > GetTime()
    local target = (hovered or flashing) and 1 or (tracked and 0.08 or 0)
    local alpha = ns.Num(button:GetAlpha()) or 0
    local step = math.min(1, (ns.Num(elapsed) or 0) * 12)
    alpha = alpha + (target - alpha) * step
    if math.abs(target - alpha) < 0.01 then alpha = target end
    SetAlpha(button, alpha)
    SetTint(button, tracked)
    return alpha ~= target or hovered or flashing
end

-- Would Fade change anything on this button now? Same inputs as Fade, no
-- side effects.
local function Pending(button)
    local combat = ns.InCombat()
    local id = Valid(button)
    if not id then
        return button.wtAlpha ~= 0 or (not combat and button.wtMouse ~= false)
    end
    if not combat and button.wtMouse ~= true then return true end
    local tracked = Follow.GetTrackedQuestID() == id
    if button.wtTint ~= tracked then return true end
    if button.hovered or (button.header and ns.Plain(button.header:IsMouseOver())) then return true end
    if (button.flashUntil or 0) > GetTime() then return true end
    return button.wtAlpha ~= (tracked and 0.08 or 0)
end

-- Buttons have no OnUpdate of their own. A button is "armed" while it fades,
-- is hovered or flashes, or when something that can change it happened
-- (enter/leave, a flash, attach/release, the setting, combat ending, the
-- arrow's quest changing). One shared frame steps armed buttons every frame,
-- only while they are visible (as their own OnUpdate used to run). Title
-- hover is only visible through polling the Blizzard header, so idle
-- buttons are checked a few times a second instead of every frame.
local POLL_SECONDS = 0.05
local armed = {}
local current, frameElapsed, sincePoll = nil, 0, 0

Arm = function(button)
    armed[button] = true
end

local function ArmAll()
    for i = 1, #Tracker.buttons do armed[Tracker.buttons[i]] = true end
end

-- Argument-free so ns.Call allocates nothing per frame.
local function StepCurrent()
    local button = current
    if not button:IsVisible() or not Fade(button, frameElapsed) then
        armed[button] = nil
    end
end

-- Hidden buttons are skipped (they are armed again when shown); an error in
-- one button's check is reported and the others are still checked.
local function PollCurrent()
    local button = current
    if not armed[button] and button:IsVisible() and Pending(button) then
        armed[button] = true
    end
end

local function Poll()
    for i = 1, #Tracker.buttons do
        current = Tracker.buttons[i]
        ns.Call(PollCurrent)
    end
    current = nil
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(_, elapsed)
    frameElapsed = elapsed
    sincePoll = sincePoll + (ns.Num(elapsed) or 0)
    if sincePoll >= POLL_SECONDS then
        sincePoll = 0
        Poll()
    end
    if next(armed) == nil then return end
    for i = 1, #Tracker.buttons do
        local button = Tracker.buttons[i]
        if armed[button] then
            current = button
            ns.Call(StepCurrent)
        end
    end
    current = nil
end)

local function CreateButton()
    local button = CreateFrame("Button", nil, UIParent)
    button:SetSize(14, 14)
    button:RegisterForClicks("LeftButtonUp")
    SetAlpha(button, 0)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    -- Shipped TGA, already used by the addon's map pins on this client.
    button.icon:SetTexture("Interface\\AddOns\\WaypointTracker\\Media\\Pin")
    button:SetScript("OnClick", ns.Safe(function(self, mouseButton)
        if Valid(self) then Track(self.block, self.module, mouseButton) end
    end))
    button:SetScript("OnEnter", ns.Safe(function(self)
        if not Valid(self) then return end
        self.hovered = true
        SetAlpha(self, 1)
        Arm(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.QUEST_TRACK_BUTTON)
        GameTooltip:Show()
    end))
    button:SetScript("OnLeave", function(self)
        self.hovered = nil
        Arm(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    button:SetScript("OnHide", function(self)
        self.hovered, self.flashUntil = nil, nil
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    -- Also runs when a hidden parent (the tracker, a collapsed block) is
    -- shown: the first shown frame corrects alpha, mouse and tint.
    button:SetScript("OnShow", Arm)
    Tracker.buttons[#Tracker.buttons + 1] = button
    return button
end

-- Parentage, anchors, creation and visibility changes are deferred in combat.
-- Existing buttons read the current block ID, so recycled blocks cannot retain
-- stale quest IDs while waiting for the next safe refresh.
local function Release(block)
    local button = bindings[block]
    if not button then return end
    bindings[block] = nil
    button.block, button.module, button.header = nil, nil, nil
    button.hovered, button.flashUntil = nil, nil
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    SetAlpha(button, 0)
    if not ns.InCombat() then
        SetMouse(button, false)
        SetShown(button, false)
    end
    Arm(button)
    pool[#pool + 1] = button
end

local function Attach(block, module)
    local header = block.HeaderButton
    if not header or not QuestID(block, module) then return end
    local button = bindings[block]
    if not button then
        button = table.remove(pool) or CreateButton()
        bindings[block] = button
        Resync(button)
        SetAlpha(button, 0)
    else
        Resync(button)
    end
    button.block, button.module, button.header = block, module, header
    -- Parent and anchor stay put until the button moves to another header
    -- (Release never touches them), so an unchanged header is not re-anchored.
    if button.wtAnchor ~= header then
        button:SetParent(header)
        button:ClearAllPoints()
        -- Overlay the header edge. Do not alter text anchors, block width or the
        -- right-edge item controls, and leave Blizzard's left-hand POI untouched.
        button:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
        button.wtAnchor = header
    end
    SetMouse(button, true)
    SetShown(button, true)
    if Pending(button) then Arm(button) end
end

local function HookModule(module)
    if not module or hooked[module] or type(module.OnBlockHeaderClick) ~= "function"
        or type(module.EnumerateActiveBlocks) ~= "function" then return end
    hooked[module] = true
    hooksecurefunc(module, "OnBlockHeaderClick", ns.Safe(function(self, block, mouseButton)
        Track(block, self, mouseButton)
    end))
    if type(module.EndLayout) == "function" then hooksecurefunc(module, "EndLayout", Schedule) end
    if type(module.OnFreeBlock) == "function" then
        hooksecurefunc(module, "OnFreeBlock", ns.Safe(function(_, block) Release(block); Schedule() end))
    end
end

Refresh = function()
    if ns.InCombat() then return end
    -- Release can put a still-shown protected-parent button into the pool
    -- during combat. Finish its deferred cleanup before attaching new blocks.
    for _, button in ipairs(pool) do
        Resync(button)
        SetMouse(button, false)
        SetShown(button, false)
    end
    HookModule(QuestObjectiveTracker)
    HookModule(CampaignQuestObjectiveTracker)
    local seen = {}
    if ns.Get("questClickTrack") then
        for module in pairs(hooked) do
            module:EnumerateActiveBlocks(function(block)
                if QuestID(block, module) and block.HeaderButton then seen[block] = module end
            end)
        end
    end
    for block in pairs(bindings) do if not seen[block] then Release(block) end end
    for block, module in pairs(seen) do
        Attach(block, module)
        HookPOI(block)
    end
end

Schedule = function()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        ns.Call(Refresh)
    end)
end

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE" }) do ns.RegisterEvent(event, Schedule) end
ns.On("LOGIN", Schedule)
ns.On("SETTING_CHANGED", function(key)
    if key == "questClickTrack" or key == nil then
        ArmAll()
        Schedule()
    end
end)
-- Mouse state waits for combat to end; the arrow's quest sets the marker.
ns.RegisterEvent("PLAYER_REGEN_ENABLED", ArmAll)
ns.On("ACTIVE_CHANGED", ArmAll)
ns.On("QUEST_TRACKING_CHANGED", ArmAll)
