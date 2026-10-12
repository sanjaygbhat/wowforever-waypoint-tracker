-- Exact-build ObjectiveTracker fixtures: nested usedBlocks, HeaderButton,
-- parentModule and OnBlockHeaderClick. No game or UI source is loaded.
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. message) end
end
local secret = 987654321
issecretvalue = function(value) return rawequal(value, secret) end
local nativeTonumber = tonumber
tonumber = function(value, ...)
    assert(not rawequal(value, secret), 'conversion before secret guard')
    return nativeTonumber(value, ...)
end
function GameTooltip:SetOwner(owner) M.tooltipOwner = owner end
function GameTooltip:IsOwned(owner) return self:GetOwner() == owner end
IsModifiedClick = function() return M.modified end
ObjectiveTrackerFrame = CreateFrame('Frame', nil, UIParent)
local hooks, replacements, defaultClicks = {}, 0, 0
local nativeHook = hooksecurefunc
hooksecurefunc = function(target, name, fn)
    hooks[name] = (hooks[name] or 0) + 1
    return nativeHook(target, name, fn)
end
local function Module()
    local module = CreateFrame('Frame', nil, ObjectiveTrackerFrame)
    module.usedBlocks = { ObjectiveTrackerQuestPOIBlockTemplate = {} }
    function module:EnumerateActiveBlocks(callback)
        for _, blocks in pairs(self.usedBlocks) do for _, block in pairs(blocks) do callback(block) end end
    end
    function module:OnBlockHeaderClick(block, button)
        defaultClicks = defaultClicks + 1
        -- Build-matched plain click opens details; it does not super-track.
        M.questDetails = block.id
        M.lastDefaultButton = button
    end
    function module:EndLayout() end
    function module:OnFreeBlock(block)
        self.usedBlocks.ObjectiveTrackerQuestPOIBlockTemplate[block.id] = nil
        block.used = false
        block:Hide()
    end
    return module
end
local function Block(module, id)
    local block = CreateFrame('Frame', nil, module)
    block.id, block.used, block.parentModule = id, true, module
    block.HeaderText = block:CreateFontString()
    block.HeaderButton = CreateFrame('Button', nil, block)
    local header = block.HeaderButton
    function header:IsMouseOver() return self.mouseOver or false end
    local click = function(_, button) module:OnBlockHeaderClick(block, button) end
    header:SetScript('OnClick', click)
    header:SetScript('OnEnter', function() M.defaultEnter = true end)
    header:SetScript('OnLeave', function() M.defaultLeave = true end)
    local setScript = header.SetScript
    header.SetScript = function(self, ...) replacements = replacements + 1; return setScript(self, ...) end
    header.originalClick = click
    module.usedBlocks.ObjectiveTrackerQuestPOIBlockTemplate[id] = block
    return block
end
QuestObjectiveTracker = Module()
local module = QuestObjectiveTracker
local first, second = Block(module, 101), Block(module, 102)
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
M.Tick(0.1)
local WP, T = ns.WP, ns.QuestTracker
local function Icon(block)
    for _, button in ipairs(T.buttons) do if button.block == block then return button end end
end
local icon = Icon(first)
check(ns.Get('questClickTrack') == true and ns.Get('followQuest') == false, 'click tracking defaults on independently of automatic following')
check(icon and #T.buttons == 2, 'one overlay for each visible quest header')
check(icon:GetAlpha() == 0 and icon:GetWidth() == 14, 'untracked icon is invisible and tiny')
check(icon:GetParent() == first.HeaderButton and #first.HeaderText._points == 0, 'overlay leaves Blizzard text and layout untouched')
first.HeaderButton.mouseOver = true
first.HeaderButton:RunScript('OnEnter')
M.Tick(0.6)
check(icon:GetAlpha() == 1 and M.defaultEnter, 'title hover fades icon in and preserves default enter')
first.HeaderButton.mouseOver = false
first.HeaderButton:RunScript('OnLeave')
M.Tick(0.6)
check(icon:GetAlpha() == 0 and M.defaultLeave, 'title leave fades back to invisible')
icon:RunScript('OnEnter')
check(icon:GetAlpha() == 1 and GameTooltip:GetText() == ns.L.QUEST_TRACK_BUTTON, 'icon hover is fully visible with localized tooltip')
icon:RunScript('OnLeave')
first.HeaderButton:RunScript('OnClick', 'LeftButton')
local questWP = WP.GetActive()
check(defaultClicks == 1 and M.questDetails == 101 and M.superTracked == 0, 'default details behavior runs before add-on action without changing super-tracking')
check(questWP and questWP.source == 'quest' and questWP.m == 37 and ns.Follow.GetTrackedQuestID() == 101, 'plain title click immediately tracks quest with automatic following off')
M.Tick(0.1)
check(icon:GetAlpha() > 0.5, 'successful click flashes the icon briefly')
M.Tick(1)
check(math.abs(icon:GetAlpha() - 0.08) < 0.001, 'tracked quest retains near-invisible marker')
local other = WP.Add(37, 0.2, 0.2, { title = 'Other waypoint', silent = true })
M.Tick(0.6)
check(icon:GetAlpha() == 0, 'marker follows active arrow rather than previous selection')
first.HeaderButton:RunScript('OnClick', 'LeftButton')
check(WP.GetActive() == questWP and #WP.List() == 2, 'repeat title click reactivates same waypoint without duplicates')
for _, key in ipairs({ 'shift', 'ctrl', 'alt', 'modified' }) do
    M[key] = true
    second.HeaderButton:RunScript('OnClick', 'LeftButton')
    Icon(second):RunScript('OnClick', 'LeftButton')
    M[key] = false
    check(WP.GetActive() == questWP, key .. ' click leaves waypoint unchanged')
end
second.HeaderButton:RunScript('OnClick', 'RightButton')
second.HeaderButton:RunScript('OnClick', 'MiddleButton')
check(WP.GetActive() == questWP and M.lastDefaultButton == 'MiddleButton', 'right and middle clicks preserve default handlers without tracking')
Icon(second):RunScript('OnClick', 'LeftButton')
check(WP.GetActive().m == 52 and ns.Follow.GetTrackedQuestID() == 102, 'secondary icon immediately tracks its quest')
check(first.HeaderButton:GetScript('OnClick') == first.HeaderButton.originalClick and replacements == 0, 'never replaces or sets Blizzard scripts')
check(hooks.OnBlockHeaderClick == 1 and hooks.EndLayout == 1 and hooks.OnFreeBlock == 1, 'one secure post-hook per module method')
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(0.7)
check(ns.Follow.GetTrackedQuestID() == 102, 'log updates retain explicit selection while automatic following is off')
local nextPosition = M.quests[2].next
M.quests[2].next = { 52, 0.6, 0.5 }
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(0.7)
check(WP.GetActive().x == 0.6, 'existing Follow updates clicked quest position')
M.quests[2].next = nextPosition
ns.Set('questClickTrack', false); M.Tick(0.1)
check(not icon:IsShown(), 'option off releases and hides overlays')
local active = WP.GetActive()
first.HeaderButton:RunScript('OnClick', 'LeftButton')
icon:RunScript('OnClick', 'LeftButton')
check(WP.GetActive() == active, 'option off disables primary and secondary actions')
ns.Set('questClickTrack', true); M.Tick(0.1)
check(#T.buttons == 2 and Icon(first), 'option on reuses released pool')
for i = 1, 10 do module:EndLayout(); M.Tick(0.1) end
check(#T.buttons == 2 and hooks.OnBlockHeaderClick == 1, 'repeated relayouts never allocate or duplicate hooks')
local released = Icon(second)
module:OnFreeBlock(second); M.Tick(0.1)
check(not released:IsShown() and released.block == nil, 'removed quest releases overlay and clears binding')
local third = Block(module, 102)
module:EndLayout(); M.Tick(0.1)
check(Icon(third) == released and #T.buttons == 2, 'pool reuses overlay for newly acquired quest block')
module:Hide()
check(not Icon(third):IsVisible(), 'overlay inherits tracker collapse visibility')
module:Show()
-- Existing bindings resolve a recycled ID at click time, even before refresh.
first.id = 102
first.HeaderButton:RunScript('OnClick', 'LeftButton')
check(ns.Follow.GetTrackedQuestID() == 102, 'recycled header tracks its current quest ID')
first.id = 101
M.player.combat = true
local fourth = Block(module, 101)
module:EndLayout(); M.Tick(0.1)
check(not Icon(fourth) and #T.buttons == 2, 'combat defers new overlay creation and anchoring')
first.HeaderButton:RunScript('OnClick', 'LeftButton')
check(ns.Follow.GetTrackedQuestID() == 101, 'existing plain click remains usable in combat')
module:OnFreeBlock(third)
third.parentModule = {} -- Blizzard can recycle this frame to another module.
released:RunScript('OnClick', 'LeftButton')
check(ns.Follow.GetTrackedQuestID() == 101, 'released combat overlay cannot track stale or different-module quest')
ns.Set('questClickTrack', false)
first.HeaderButton:RunScript('OnClick', 'LeftButton')
check(ns.Follow.GetTrackedQuestID() == 101, 'option changes take effect immediately during combat')
ns.Set('questClickTrack', true)
M.player.combat = false
M.FireEvent('PLAYER_REGEN_ENABLED'); M.Tick(0.1)
check(Icon(fourth) and #T.buttons == 2, 'combat exit refreshes using released overlay')
local current = WP.GetActive()
fourth.id = secret
fourth.HeaderButton:RunScript('OnClick', 'LeftButton')
check(WP.GetActive() == current, 'secret quest ID is rejected before conversion or API calls')
fourth.id = 101
local position = ns.Places.QuestPosition
ns.Places.QuestPosition = function() error('restricted quest map result') end
check(ns.Follow.TrackQuest(101) == nil and WP.GetActive() == current, 'restricted position API leaves arrow intact without reported errors')
for _, component in ipairs({ 1, 2, 3 }) do
    ns.Places.QuestPosition = function()
        local values = { 37, 0.4, 0.5 }; values[component] = secret; return unpack(values)
    end
    check(ns.Follow.TrackQuest(101) == nil and WP.GetActive() == current, 'secret destination component ' .. component .. ' leaves current arrow intact')
end
ns.Places.QuestPosition = function() return nil end
first.HeaderButton:RunScript('OnClick', 'LeftButton')
check(WP.GetActive() == current and M.printed[#M.printed]:find(ns.L.QUEST_TRACK_NO_POSITION, 1, true), 'missing position preserves arrow and explains failure')
ns.Places.QuestPosition = position
M.FireEvent('QUEST_TURNED_IN', 101); M.Tick(0.1)
check(not WP.IsValid(current) and not ns.Follow.GetTrackedQuestID(), 'turn-in clears explicit quest waypoint')
ns.Set('followQuest', true)
M.superTracked = 102; M.FireEvent('SUPER_TRACKING_CHANGED'); M.Tick(0.7)
check(ns.Follow.GetTrackedQuestID() == 102, 'optional automatic super-tracking still works')
first.HeaderButton:RunScript('OnClick', 'LeftButton')
M.Tick(0.7)
check(ns.Follow.GetTrackedQuestID() == 101, 'explicit click wins over a pending automatic update')
M.superTracked = 102; M.FireEvent('SUPER_TRACKING_CHANGED'); M.Tick(0.7)
check(ns.Follow.GetTrackedQuestID() == 102, 'later external super-track selection respects automatic setting')
ns.Set('followQuest', false); M.Tick(0.7)
first.HeaderButton:RunScript('OnClick', 'LeftButton')
WP.ClearAll(true)
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(0.7)
check(#WP.List() == 0, 'cleared explicit waypoint is not recreated by quest events')
-- Late-loaded tracker discovered from ADDON_LOADED without loading UI ourselves.
CampaignQuestObjectiveTracker = Module()
local late = Block(CampaignQuestObjectiveTracker, 101)
M.FireEvent('ADDON_LOADED', 'Blizzard_ObjectiveTracker'); M.Tick(0.1)
late.HeaderButton:RunScript('OnClick', 'LeftButton')
check(Icon(late) and ns.Follow.GetTrackedQuestID() == 101, 'late-loaded quest module receives secure hooks and overlays')
-- Lifecycle regressions from independent review: moving objectives must keep
-- user route choices, clean up on abandon, and restore properly after death.
ns.Set('followQuest', false)
WP.ClearAll(true)
ns.TravelData = { areas = { 'test' }, indoor = {}, nodes = '', links = '',
    maps = '37\t1', regions = '', cities = '', towns = '', levels = '', factors = '' }
local Travel = ns.Travel
Travel._Reset()
ns.Set('realRoutes', true); ns.Set('travelHearth', false)
local followed = ns.Follow.TrackQuest(101)
local _, chosen = Travel.Choices(followed)
assert(chosen)
chosen.preference = 'fastest'
Travel.Select(followed, chosen)
M.quests[1].onMap[37] = { 0.44, 0.82 }
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(0.7)
local updated = WP.GetActive()
check(updated.travelPreference == 'fastest' and updated.travelChosen, 'moving quest objective preserves explicit route preference')
check(not WP.IsValid(followed) and updated.x == 0.44, 'moving quest objective replaces the old destination')
local _, route = Travel.Choices(updated)
Travel.Select(updated, route)
WP.Move(updated, 37, 0.5, 0.82)
M.now = M.now + 3
Travel.Steer(updated)
local plan = Travel.Current()
check(plan and plan.path[#plan.path].node.x == updated.x, 'chosen itinerary replans to a moved waypoint destination')
ns.Set('realRoutes', false)
-- Update the selected quest while its previous waypoint is saved for revival.
local nearDeath = WP.Add(37, 0.3, 0.3, { title = 'Near death', silent = true, setActive = false })
M.player.dead = true; M.FireEvent('PLAYER_DEAD')
check(WP.GetActive().source == 'corpse', 'corpse takes the arrow before the quest update')
M.player.ghost = true
M.quests[1].onMap[37] = { 0.46, 0.82 }
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(0.7)
check(WP.GetActive().source == 'corpse' and not WP.IsValid(updated), 'quest update leaves corpse navigation active')
M.player.dead, M.player.ghost = false, false
M.FireEvent('PLAYER_UNGHOST')
local restored = WP.GetActive()
check(restored and restored.source == 'quest' and restored.x == 0.46, 'resurrection restores the updated clicked quest')
local removed = table.remove(M.quests, 1)
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(0.7)
check(not WP.IsValid(restored) and ns.Follow.GetTrackedQuestID() == nil, 'abandoning clicked quest removes its stale waypoint')
table.insert(M.quests, 1, removed)
check(#M.errors == 0, 'quest tracker runtime has no reported Lua errors')
for _, errorMessage in ipairs(M.errors) do print(errorMessage) end
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and #M.errors == 0 and 0 or 1)
