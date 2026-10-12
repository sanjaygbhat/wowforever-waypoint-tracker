-- Build 1.60.1 uses ObjectiveTrackerFrame and QuestObjectiveTracker blocks.
-- Only post-hooks touch Blizzard code; all scripts below belong to our buttons.
local _, ns = ...
local L, Follow = ns.L, ns.Follow
local Tracker = { buttons = {} }
ns.QuestTracker = Tracker
local bindings, hooked, pool = {}, {}, {}
local pending = false
local Refresh, Schedule

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
    if button then button.flashUntil = GetTime() + 0.45 end
end

local function Valid(button)
    return ns.Get("questClickTrack") and button.block
        and bindings[button.block] == button and QuestID(button.block, button.module)
end

local function Fade(button, elapsed)
    local id = Valid(button)
    if not id then
        button:SetAlpha(0)
        -- Never intercept a header belonging to a different pooled module.
        if not ns.InCombat() then button:EnableMouse(false) end
        return
    end
    if not ns.InCombat() then button:EnableMouse(true) end
    local tracked = Follow.GetTrackedQuestID() == id
    local hovered = button.hovered or (button.header and ns.Plain(button.header:IsMouseOver()))
    local flashing = (button.flashUntil or 0) > GetTime()
    local target = (hovered or flashing) and 1 or (tracked and 0.08 or 0)
    local alpha = ns.Num(button:GetAlpha()) or 0
    local step = math.min(1, (ns.Num(elapsed) or 0) * 12)
    alpha = alpha + (target - alpha) * step
    if math.abs(target - alpha) < 0.01 then alpha = target end
    button:SetAlpha(alpha)
    button.icon:SetVertexColor(tracked and 0.35 or 1, 1, tracked and 0.55 or 1)
end

local function CreateButton()
    local button = CreateFrame("Button", nil, UIParent)
    button:SetSize(14, 14)
    button:RegisterForClicks("LeftButtonUp")
    button:SetAlpha(0)
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
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.QUEST_TRACK_BUTTON)
        GameTooltip:Show()
    end))
    button:SetScript("OnLeave", function(self)
        self.hovered = nil
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    button:SetScript("OnHide", function(self)
        self.hovered, self.flashUntil = nil, nil
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    button:SetScript("OnUpdate", ns.Safe(Fade))
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
    button:SetAlpha(0)
    if not ns.InCombat() then
        button:EnableMouse(false)
        button:Hide()
    end
    pool[#pool + 1] = button
end

local function Attach(block, module)
    local header = block.HeaderButton
    if not header or not QuestID(block, module) then return end
    local button = bindings[block]
    if not button then
        button = table.remove(pool) or CreateButton()
        bindings[block] = button
        button:SetAlpha(0)
    end
    button.block, button.module, button.header = block, module, header
    button:SetParent(header)
    button:ClearAllPoints()
    -- Overlay the header edge. Do not alter text anchors, block width or the
    -- right-edge item controls, and leave Blizzard's left-hand POI untouched.
    button:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    button:EnableMouse(true)
    button:Show()
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
        button:EnableMouse(false)
        button:Hide()
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
    for block, module in pairs(seen) do Attach(block, module) end
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
    if key == "questClickTrack" or key == nil then Schedule() end
end)
