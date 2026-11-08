-- Regression: the quest icon in front of each tracked quest (Blizzard's POI
-- button, "..." while in progress) must take the arrow to that quest's
-- current objective with default settings, follow objective updates, and let
-- go when the icon is clicked again. Build 1.60.1 ObjectiveTracker shape:
-- QuestObjectiveTracker blocks with HeaderButton, HeaderText and a pooled
-- poiButton whose OnClick (POIButtonMixin) super-tracks the quest.
-- Run from repo root: lua5.1 tests/run_quest_poi.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. message) end
end
local function near(a, b) return a and math.abs(a - b) < 0.002 end

M.shift = false
IsShiftKeyDown = function() return M.shift end
IsModifiedClick = function() return false end
C_SuperTrack.SetSuperTrackedQuestID = function(id) M.superTracked = id or 0 end
C_SuperTrack.ClearAllSuperTracked = function() M.superTracked = 0 end
M.watched = {}
C_QuestLog.AddQuestWatch = function(id) M.watched[id] = true end

ObjectiveTrackerFrame = CreateFrame('Frame', nil, UIParent)

-- POIButtonMixin:OnClick as shipped in 1.60.1 (Blizzard_POIButton/POIButton.lua).
local function POIButton(parent, questID)
    local poi = CreateFrame('Button', nil, parent)
    poi.questID = questID
    function poi:GetQuestID() return self.questID end
    function poi:SetQuestID(id) self.questID = id end
    function poi:IsSelected() return M.superTracked == self.questID end
    poi:SetScript('OnClick', function(self, button)
        M.blizzardPOIClicks = (M.blizzardPOIClicks or 0) + 1
        if button ~= 'LeftButton' then return end
        if self:IsSelected() then C_SuperTrack.ClearAllSuperTracked(); return end
        if M.watched[self.questID] then
            if IsShiftKeyDown() then return end
        else
            C_QuestLog.AddQuestWatch(self.questID)
        end
        C_SuperTrack.SetSuperTrackedQuestID(self.questID)
    end)
    return poi
end

local layouts = {}
local function Module()
    local module = CreateFrame('Frame', nil, ObjectiveTrackerFrame)
    module.usedBlocks = { ObjectiveTrackerQuestPOIBlockTemplate = {} }
    function module:EnumerateActiveBlocks(callback)
        for _, blocks in pairs(self.usedBlocks) do for _, block in pairs(blocks) do callback(block) end end
    end
    function module:OnBlockHeaderClick() end
    function module:EndLayout() layouts[#layouts + 1] = self end
    function module:OnFreeBlock(block)
        self.usedBlocks.ObjectiveTrackerQuestPOIBlockTemplate[block.id] = nil
        block.used = false
        block:Hide()
    end
    return module
end
local function Block(module, id, withPOI)
    local block = CreateFrame('Frame', nil, module)
    block.id, block.used, block.parentModule = id, true, module
    block.HeaderText = block:CreateFontString()
    block.HeaderButton = CreateFrame('Button', nil, block)
    function block.HeaderButton:IsMouseOver() return false end
    if withPOI ~= false then block.poiButton = POIButton(block, id) end
    module.usedBlocks.ObjectiveTrackerQuestPOIBlockTemplate[id] = block
    return block
end

QuestObjectiveTracker = Module()
CampaignQuestObjectiveTracker = Module()
local module = QuestObjectiveTracker
local first = Block(module, 101)
local second = Block(module, 102)

local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
M.Tick(0.1)
local WP, Follow = ns.WP, ns.Follow

check(ns.Get('questClickTrack') == true and ns.Get('followQuest') == false,
    'defaults: quest clicks track, automatic following stays off')
check(WP.GetActive() == nil, 'no waypoint before any click')

-- 1. The "..." icon in front of an in-progress quest takes the arrow.
first.poiButton:Click('LeftButton')
M.Tick(0.1)
local active = WP.GetActive()
check(M.superTracked == 101 and M.blizzardPOIClicks == 1, "Blizzard's own POI click still super-tracks the quest")
check(active and active.source == 'quest' and active.m == 37 and near(active.x, 0.39) and near(active.y, 0.82),
    'POI click points the arrow at the quest objective (got ' .. tostring(active and (active.m .. ' ' .. active.x .. ',' .. active.y)) .. ')')
check(Follow.GetTrackedQuestID() == 101, 'the clicked quest is the tracked quest')

-- 2. It follows the latest objective as the quest log updates.
M.quests[1].onMap[37] = { 0.47, 0.71 }
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(0.7)
active = WP.GetActive()
check(active and active.source == 'quest' and near(active.x, 0.47) and near(active.y, 0.71),
    'objective update moves the arrow to the latest objective')

-- 3. A pooled POI button reassigned to another quest tracks that quest.
second.poiButton:Click('LeftButton')
M.Tick(0.1)
active = WP.GetActive()
check(M.superTracked == 102 and active and active.source == 'quest' and active.m == 52 and near(active.x, 0.56) and near(active.y, 0.47),
    'clicking another quest icon switches the arrow to that quest (got ' .. tostring(active and (active.m .. ' ' .. active.x)) .. ')')
check(WP.Count() == 1, 'switching quests reuses one quest waypoint')

-- 4. Clicking the selected icon again lets go of the quest.
second.poiButton:Click('LeftButton')
M.Tick(0.1)
check(M.superTracked == 0 and Follow.GetTrackedQuestID() == nil and WP.Count() == 0,
    'deselecting the quest icon removes its waypoint')

-- 5. Shift-click on a watched quest keeps Blizzard behaviour and does not track.
M.shift = true
first.poiButton:Click('LeftButton')
M.Tick(0.1)
M.shift = false
check(WP.Count() == 0, 'shift-click on the quest icon does not set a waypoint')

-- 6. With the setting off, the icon only does what Blizzard does.
ns.Set('questClickTrack', false)
M.Tick(0.1)
first.poiButton:Click('LeftButton')
M.Tick(0.1)
check(M.superTracked == 101 and WP.Count() == 0, 'questClickTrack off leaves the arrow alone')
C_SuperTrack.ClearAllSuperTracked()
ns.Set('questClickTrack', true)
M.Tick(0.1)

-- 7. Blocks laid out later (new quest accepted) are hooked after EndLayout.
local late = Block(CampaignQuestObjectiveTracker, 101)
CampaignQuestObjectiveTracker:EndLayout()
M.Tick(0.1)
late.poiButton:Click('LeftButton')
M.Tick(0.1)
active = WP.GetActive()
check(active and active.source == 'quest' and Follow.GetTrackedQuestID() == 101,
    'a campaign quest icon laid out later also takes the arrow')
check(#layouts >= 1, 'layout hook ran')

-- 8. Each POI button is hooked once, however often the tracker lays out.
for _ = 1, 5 do module:EndLayout(); M.Tick(0.1) end
C_SuperTrack.ClearAllSuperTracked()
local track, calls = Follow.TrackQuest, 0
Follow.TrackQuest = function(...) calls = calls + 1; return track(...) end
first.poiButton:Click('LeftButton')
M.Tick(0.1)
Follow.TrackQuest = track
check(calls == 1, 'repeated layouts do not stack duplicate POI hooks (tracked ' .. calls .. ' times for one click)')

check(#M.errors == 0, 'quest POI tracking has no reported Lua errors')
for _, errorMessage in ipairs(M.errors) do print(errorMessage) end
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and #M.errors == 0 and 0 or 1)
