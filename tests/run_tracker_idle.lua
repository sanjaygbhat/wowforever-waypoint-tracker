-- Quest tracker overlay per-frame cost and fade fidelity. Ten tracked quests
-- sit idle for 600 frames: the overlays make no widget calls and the tracker
-- allocates nothing. Hover, flash, tracked-marker and combat sequences match
-- values recorded from the 1.3.1 implementation (one OnUpdate per button);
-- unchanged relayouts do not re-parent or re-anchor; freed blocks reattach;
-- an overlay hidden, faded or disabled by other code is put back from the
-- next layout (after combat ends, if in combat) as 1.3.1 did.
-- WT_RECORD=1 prints the observed sequences instead of checking them.
-- Run from repo root: lua5.1 tests/run_tracker_idle.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. message) end
end
local RECORD = os.getenv('WT_RECORD')
function GameTooltip:SetOwner(owner) M.tooltipOwner = owner end
function GameTooltip:IsOwned(owner) return self:GetOwner() == owner end
IsModifiedClick = function() return false end

ObjectiveTrackerFrame = CreateFrame('Frame', nil, UIParent)
local headerPolls = 0
local function Module()
    local module = CreateFrame('Frame', nil, ObjectiveTrackerFrame)
    module.usedBlocks = { ObjectiveTrackerQuestPOIBlockTemplate = {} }
    function module:EnumerateActiveBlocks(callback)
        for _, blocks in pairs(self.usedBlocks) do for _, block in pairs(blocks) do callback(block) end end
    end
    function module:OnBlockHeaderClick(block) M.headerClicks = (M.headerClicks or 0) + 1 end
    function module:EndLayout() end
    -- Freed blocks stay shown here, so a released overlay stays visible.
    function module:OnFreeBlock(block)
        self.usedBlocks.ObjectiveTrackerQuestPOIBlockTemplate[block.id] = nil
        block.used = false
    end
    return module
end
local function Block(module, id)
    local block = CreateFrame('Frame', nil, module)
    block.id, block.used, block.parentModule = id, true, module
    block.HeaderText = block:CreateFontString()
    block.HeaderButton = CreateFrame('Button', nil, block)
    function block.HeaderButton:IsMouseOver() headerPolls = headerPolls + 1; return self.mouseOver or false end
    block.HeaderButton:SetScript('OnClick', function(_, button) module:OnBlockHeaderClick(block, button) end)
    module.usedBlocks.ObjectiveTrackerQuestPOIBlockTemplate[id] = block
    return block
end
QuestObjectiveTracker = Module()
local module = QuestObjectiveTracker
local blocks = {}
for i = 1, 10 do blocks[i] = Block(module, 100 + i) end

local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
M.Tick(1)
local T, F = ns.QuestTracker, M.FrameMethods
local function Icon(block)
    for _, button in ipairs(T.buttons) do if button.block == block then return button end end
end
check(#T.buttons == 10, 'one overlay per tracked quest')

-- Count every widget call made on the overlays and their icons.
local counts, total, combatCalls, combatKinds = {}, 0, 0, {}
local PROTECTED = { EnableMouse = true, SetParent = true, SetPoint = true, ClearAllPoints = true, Show = true, Hide = true }
local function Count(name)
    counts[name] = (counts[name] or 0) + 1
    total = total + 1
    if M.player.combat and PROTECTED[name] then combatCalls = combatCalls + 1 end
    if M.player.combat then combatKinds[name] = true end
end
local METHODS = { 'SetAlpha', 'GetAlpha', 'EnableMouse', 'IsMouseEnabled', 'IsVisible', 'IsShown', 'Show', 'Hide',
    'SetShown', 'SetParent', 'ClearAllPoints', 'SetPoint', 'SetScript', 'GetScript' }
local function Instrument()
    for _, button in ipairs(T.buttons) do
        if not rawget(button, '_counted') then
            rawset(button, '_counted', true)
            for _, name in ipairs(METHODS) do
                local original = F[name]
                rawset(button, name, function(self, ...) Count(name); return original(self, ...) end)
            end
            rawset(button.icon, 'SetVertexColor', function(self, ...)
                Count('SetVertexColor'); return F.SetVertexColor(self, ...)
            end)
        end
    end
end
local function ResetCounts() counts, total, combatCalls, combatKinds = {}, 0, 0, {} end
local function Sum(names)
    local n = 0
    for _, name in ipairs(names) do n = n + (counts[name] or 0) end
    return n
end
Instrument()

-- Frame driver: timers then the tracker's own OnUpdate scripts (overlays,
-- or the frame whose script is defined in QuestTracker.lua), in creation
-- order like M.Tick. Nothing here allocates unless a timer is due.
local DT = 1 / 60
local frames = {}
local function CollectFrames()
    frames = {}
    local own = {}
    for _, button in ipairs(T.buttons) do own[button] = true end
    for _, f in ipairs(M.frames) do
        local fn = f._scripts.OnUpdate
        if own[f] or (fn and debug.getinfo(fn, 'S').source:find('QuestTracker.lua', 1, true)) then
            frames[#frames + 1] = f
        end
    end
end
local function Run(n, each)
    for i = 1, n do
        M.now = M.now + DT
        local due = false
        for t = 1, #M.timers do if M.timers[t].at <= M.now then due = true end end
        if due then
            local timers = M.timers
            M.timers = {}
            for _, tm in ipairs(timers) do
                if tm.at <= M.now then tm.fn() else M.timers[#M.timers + 1] = tm end
            end
        end
        for j = 1, #frames do
            local f = frames[j]
            local fn = f._scripts.OnUpdate
            if fn and F.IsVisible(f) then fn(f, DT) end
        end
        if each then each(i) end
    end
end
CollectFrames()

local function Record(button, n, field)
    local out = {}
    Run(n, function(i)
        if field == 'tint' then out[i] = button.icon._color and button.icon._color[1] or 1
        elseif field == 'mouse' then out[i] = button._mouse and 1 or 0
        elseif field == 'shown' then out[i] = button._shown and 1 or 0
        else out[i] = button._alpha end
    end)
    return out
end
local function Show(name, seq)
    local parts = {}
    for i, v in ipairs(seq) do parts[i] = ('%.17g'):format(v) end
    print(('G.%s = { %s }'):format(name, table.concat(parts, ', ')))
end
local function Same(seq, golden, shiftMax, before)
    for d = 0, shiftMax or 0 do
        local ok = #seq == #golden
        for i = 1, #seq do
            local want = i <= d and before or golden[i - d]
            if seq[i] ~= want then ok = false; break end
        end
        if ok then return true, d end
    end
    return false
end

-- Sequences recorded from the 1.3.1 QuestTracker.lua (commit b7598bf) with
-- this file and WT_RECORD=1, at 60 frames per second.
local G = {}
G.leave = { 0.80000000000000004, 0.64000000000000001, 0.51200000000000001, 0.40960000000000002, 0.32768000000000003, 0.26214400000000004, 0.20971520000000005, 0.16777216000000003, 0.13421772800000004, 0.10737418240000003, 0.085899345920000023, 0.068719476736000012, 0.054975581388800009, 0.043980465111040007, 0.035184372088832003, 0.028147497671065603, 0.022517998136852482, 0.018014398509481985, 0.014411518807585589, 0.011529215046068471, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
G.titleIn = { 0.20000000000000001, 0.36000000000000004, 0.48799999999999999, 0.59040000000000004, 0.67232000000000003, 0.73785600000000007, 0.79028480000000001, 0.83222784000000005, 0.86578227200000002, 0.89262581760000004, 0.91410065408000007, 0.93128052326400002, 0.94502441861120001, 0.95601953488895997, 0.96481562791116793, 0.97185250232893439, 0.97748200186314749, 0.98198560149051795, 0.98558848119241438, 0.98847078495393148, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }
G.titleOut = G.leave -- identical values recorded
G.flash = { 0.20000000000000001, 0.36000000000000004, 0.48799999999999999, 0.59040000000000004, 0.67232000000000003, 0.73785600000000007, 0.79028480000000001, 0.83222784000000005, 0.86578227200000002, 0.89262581760000004, 0.91410065408000007, 0.93128052326400002, 0.94502441861120001, 0.95601953488895997, 0.96481562791116793, 0.97185250232893439, 0.97748200186314749, 0.98198560149051795, 0.98558848119241438, 0.98847078495393148, 1, 1, 1, 1, 1, 1, 1, 0.81599999999999995, 0.66879999999999995, 0.55103999999999997, 0.45683199999999996, 0.38146559999999996, 0.32117247999999998, 0.27293798399999997, 0.23435038719999998, 0.20348030975999998, 0.17878424780799998, 0.1590273982464, 0.14322191859712, 0.13057753487769599, 0.12046202790215679, 0.11236962232172544, 0.10589569785738036, 0.10071655828590428, 0.096573246628723422, 0.093258597302978738, 0.090606877842382985, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002, 0.080000000000000002 }
G.flashTint = { 0.34999999999999998, 0.34999999999999998, 0.34999999999999998, 0.34999999999999998, 0.34999999999999998, 0.34999999999999998, 0.34999999999999998, 0.34999999999999998, 0.34999999999999998, 0.34999999999999998 }
G.untrack = { 0.064000000000000001, 0.051200000000000002, 0.040960000000000003, 0.032768000000000005, 0.026214400000000006, 0.020971520000000004, 0.016777216000000005, 0.013421772800000004, 0.010737418240000003, 0, 0, 0 }
G.untrackTint = { 1, 1, 1 }
G.combatA = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }
G.combatC = { 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
G.reshow = G.leave -- identical values recorded
G.foreignHide = { 1, 1, 1 }
G.foreignMouse = { 1, 1, 1 }
G.foreignAlpha = { 0.40000000000000002, 0.32000000000000001, 0.25600000000000001, 0.20480000000000001, 0.16384000000000001, 0.13107200000000002, 0.10485760000000002, 0.083886080000000016, 0.067108864000000018, 0.053687091200000016, 0.042949672960000011, 0.034359738368000006, 0.027487790694400004, 0.021990232555520003, 0.017592186044416001, 0.014073748835532801, 0.011258999068426241, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
G.combatHide = { 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }
G.combatMouse = { 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }

local function Expect(name, seq, shiftMax, before)
    if RECORD then Show(name, seq); return end
    local ok, d = Same(seq, G[name], shiftMax, before)
    check(ok, name .. ' sequence matches 1.3.1')
    return d
end

local A, B = Icon(blocks[1]), Icon(blocks[2])
Run(5)

-- 1. Hovering the overlay shows it at once; leaving fades it out.
A:RunScript('OnEnter')
local held = Record(A, 10)
local allOne = true
for _, v in ipairs(held) do allOne = allOne and v == 1 end
check(allOne, 'overlay hover holds full alpha')
A:RunScript('OnLeave')
Expect('leave', Record(A, 30))

-- 2. Hovering the quest title (Blizzard header) fades the overlay in and out.
-- The header is polled, so the fade may start up to 3 frames (50 ms) later
-- than 1.3.1; once started it is the same sequence.
blocks[1].HeaderButton.mouseOver = true
local shiftIn = Expect('titleIn', Record(A, 30), 3, 0)
blocks[1].HeaderButton.mouseOver = false
local shiftOut = Expect('titleOut', Record(A, 30), 3, 1)
if not RECORD then print(('title hover onset delay: in %d frame(s), out %d frame(s)'):format(shiftIn or -1, shiftOut or -1)) end

-- 3. A click tracks the quest: flash, then the tracked marker and tint.
A:RunScript('OnClick', 'LeftButton')
check(ns.Follow.GetTrackedQuestID() == 101, 'overlay click tracks its quest')
Expect('flash', Record(A, 60))
Expect('flashTint', Record(A, 10, 'tint'))

-- 4. Tracking another quest returns the first overlay to invisible and white.
B:RunScript('OnClick', 'LeftButton')
check(ns.Follow.GetTrackedQuestID() == 102, 'second overlay tracks its quest')
local untrack = Record(A, 12)
Expect('untrack', untrack)
Expect('untrackTint', Record(A, 3, 'tint'))
Run(120)

-- 5. Idle: ten overlays, one of them the tracked marker, for 600 frames.
ResetCounts()
headerPolls = 0
collectgarbage('collect')
collectgarbage('stop')
local before = collectgarbage('count')
Run(600)
local kib = (collectgarbage('count') - before) / 600
collectgarbage('restart')
local visible = counts.IsVisible or 0
print(('idle: %d overlay calls over 600 frames (%.2f per frame; %d of them IsVisible), %.4f KiB per frame, %.2f header polls per frame')
    :format(total, total / 600, visible, kib, headerPolls / 600))
-- Each poll (every 50 ms) asks each overlay IsVisible before anything else.
check(total - visible == 0, 'idle overlays make no widget calls besides the visibility check (got ' .. total - visible .. ')')
check(visible <= #T.buttons * 201, 'one visibility check per overlay per poll (got ' .. visible .. ')')
check(kib < 0.01, ('idle tracker allocates nothing (%.4f KiB per frame)'):format(kib))

-- 6. Relayouts with nothing changed neither re-parent nor re-anchor.
ResetCounts()
for _ = 1, 50 do
    module:EndLayout()
    M.FireEvent('QUEST_LOG_UPDATE')
    Run(1)
end
local anchors = Sum({ 'SetParent', 'ClearAllPoints', 'SetPoint', 'Show', 'Hide', 'EnableMouse' })
print(('50 unchanged layouts: %d re-anchor/visibility calls'):format(anchors))
check(anchors == 0, '50 unchanged layouts make no re-anchor calls (got ' .. anchors .. ')')
check(A:GetParent() == blocks[1].HeaderButton and select(2, A:GetPoint(1)) == blocks[1].HeaderButton,
    'overlay stays anchored to its header')

-- 7. Combat: option off and a freed block while in combat, then combat ends.
local C = Icon(blocks[3])
ResetCounts()
M.player.combat = true
M.FireEvent('PLAYER_REGEN_DISABLED')
ns.Set('questClickTrack', false)
Run(3)
module:OnFreeBlock(blocks[3])
Run(3)
check(A._alpha == 0 and A._mouse and C._mouse and C.block == nil, 'combat hides overlays without touching mouse state')
ns.Set('questClickTrack', true)
local seqA, seqC = {}, {}
local function Mouse(offset)
    return function(i) seqA[offset + i], seqC[offset + i] = A._mouse and 1 or 0, C._mouse and 1 or 0 end
end
Run(3, Mouse(0))
M.player.combat = false
M.FireEvent('PLAYER_REGEN_ENABLED')
Run(9, Mouse(3))
Expect('combatA', seqA)
Expect('combatC', seqC)
check(combatCalls == 0, 'no EnableMouse/SetParent/SetPoint/ClearAllPoints/Show/Hide on overlays in combat (got ' .. combatCalls .. ')')
check(not C:IsShown() and C._mouse == false, 'combat exit hides and disables the freed overlay')

-- 8. A freed block that Blizzard reuses for another quest reattaches, and a
-- pooled overlay moves to a different header.
module:OnFreeBlock(blocks[4]); module:EndLayout(); Run(2)
local D = blocks[4]
check(not Icon(D), 'freed block releases its overlay')
D.used, D.id = true, 120
module.usedBlocks.ObjectiveTrackerQuestPOIBlockTemplate[120] = D
module:EndLayout(); Run(2)
local reused = Icon(D)
check(reused and reused:IsShown() and reused._mouse and reused:GetParent() == D.HeaderButton
    and select(2, reused:GetPoint(1)) == D.HeaderButton, 'reused block reattaches a shown, clickable overlay')
local fresh = Block(module, 130)
module:EndLayout(); Run(2)
local moved = Icon(fresh)
check(moved and moved:GetParent() == fresh.HeaderButton and select(2, moved:GetPoint(1)) == fresh.HeaderButton
    and moved:IsShown() and moved._mouse, 'pooled overlay re-anchors to a new header')
Run(2)
check(reused._alpha == 0 and moved._alpha == 0, 'reattached overlays start invisible')

-- 9. An error while fading is reported once and never stops the tracker.
local errors = #M.errors
local tracked = ns.Follow.GetTrackedQuestID
ns.Follow.GetTrackedQuestID = function() error('fade failure probe') end
A:RunScript('OnLeave')
ns.Fire('QUEST_TRACKING_CHANGED')
Run(5)
ns.Follow.GetTrackedQuestID = tracked
local clicks = M.headerClicks or 0
blocks[2].HeaderButton:RunScript('OnClick', 'LeftButton')
Run(5)
check(#M.errors == errors + 1 and M.errors[#M.errors]:find('fade failure probe', 1, true),
    'fade error reported once through the addon error path')
check(M.headerClicks == clicks + 1 and ns.Follow.GetTrackedQuestID() == 102, 'Blizzard header click still works after an error')
table.remove(M.errors)

-- 10. An error in one overlay's title check is reported once and the other
-- overlays are still checked (1.3.1 ran each overlay on its own).
Run(30)
local broken, other
for _, button in ipairs(T.buttons) do
    if button.block and button.header then
        if not broken then broken = button else other = button end
    end
end
local probe = broken.header.IsMouseOver
broken.header.IsMouseOver = function() error('header probe') end
other.header.mouseOver = true
errors = #M.errors
Run(30)
check(other._alpha == 1, ('a later overlay still fades in on title hover after an earlier one fails (alpha %.3f)'):format(other._alpha))
check(#M.errors == errors + 1 and M.errors[#M.errors]:find('header probe', 1, true), 'title check error reported once')
table.remove(M.errors)
broken.header.IsMouseOver, other.header.mouseOver = probe, false
Run(60)

-- 11. A hidden tracker costs nothing but the visibility check, and an
-- overlay shown again is corrected on its first shown frame as in 1.3.1.
-- The game runs OnLeave/OnHide on the children of a hidden frame and OnShow
-- on those that become visible when it is shown again; the mock does not.
local H = Icon(blocks[1])
H:RunScript('OnEnter')
Run(3)
ObjectiveTrackerFrame:Hide()
H:RunScript('OnLeave')
H:RunScript('OnHide')
Run(1)
ResetCounts()
headerPolls = 0
Run(60)
check(total - (counts.IsVisible or 0) == 0 and headerPolls == 0,
    ('hidden overlays are not polled (%d calls, %d header polls)'):format(total - (counts.IsVisible or 0), headerPolls))
ObjectiveTrackerFrame:Show()
for _, button in ipairs(T.buttons) do
    if button:IsVisible() then button:RunScript('OnShow') end
end
Expect('reshow', Record(H, 30))

-- 12. Other code (a tracker skin, Blizzard) hides, fades or disables an
-- overlay directly (F.* bypasses the call counters). 1.3.1 re-applied Show
-- and EnableMouse on every layout and alpha every frame; from the next layout
-- on, each overlay must match 1.3.1 again.
Instrument()
Run(30)
local function Layout() module:EndLayout() end
local X, Y, Z = Icon(blocks[5]), Icon(blocks[6]), Icon(blocks[7])
F.Hide(X); Run(2); Layout()
Expect('foreignHide', Record(X, 3, 'shown'))
F.EnableMouse(Y, false); Layout()
Expect('foreignMouse', Record(Y, 3, 'mouse'))
F.SetAlpha(Z, 0.5); Layout()
Expect('foreignAlpha', Record(Z, 30))

-- The client stores alpha as float32: a read-back of 0.08 that is off in the
-- last bits is not a change, so layouts do not re-set the tracked marker.
local marker = Icon(blocks[2])
check(ns.Follow.GetTrackedQuestID() == 102 and marker._alpha == 0.08, 'tracked marker idle at 0.08')
local counted = rawget(marker, 'GetAlpha')
rawset(marker, 'GetAlpha', function(self) Count('GetAlpha'); return F.GetAlpha(self) * (1 - 2 ^ -24) end)
ResetCounts()
for _ = 1, 50 do Layout(); Run(1) end
check((counts.SetAlpha or 0) == 0 and marker._alpha == 0.08,
    ('float32 alpha read-back causes no SetAlpha over 50 layouts (got %d)'):format(counts.SetAlpha or 0))
rawset(marker, 'GetAlpha', counted)

-- In combat nothing protected is called and the overlays wait; combat end
-- puts all three back.
local P, Q, R = Icon(blocks[8]), Icon(blocks[9]), Icon(blocks[10])
ResetCounts()
M.player.combat = true
M.FireEvent('PLAYER_REGEN_DISABLED')
F.Hide(P); F.EnableMouse(Q, false); F.SetAlpha(R, 0.5)
Layout(); M.FireEvent('QUEST_LOG_UPDATE')
local seqP, seqQ = {}, {}
local function Watch(offset)
    return function(i) seqP[offset + i], seqQ[offset + i] = P._shown and 1 or 0, Q._mouse and 1 or 0 end
end
Run(5, Watch(0))
M.player.combat = false
M.FireEvent('PLAYER_REGEN_ENABLED')
Run(30, Watch(5))
Expect('combatHide', seqP)
Expect('combatMouse', seqQ)
check(combatCalls == 0, 'no protected overlay call in combat after foreign changes (got ' .. combatCalls .. ')')
local kinds = {}
for name in pairs(combatKinds) do kinds[#kinds + 1] = name end
table.sort(kinds)
local allowed = { SetAlpha = true, GetAlpha = true, SetVertexColor = true, IsVisible = true }
local extra = {}
for _, name in ipairs(kinds) do if not allowed[name] then extra[#extra + 1] = name end end
check(#extra == 0, 'in combat only SetAlpha/GetAlpha/SetVertexColor/IsVisible on overlays (also: ' .. table.concat(extra, ',') .. ')')
check(P._shown and Q._mouse and R._alpha == 0,
    ('combat end restores shown, mouse and alpha (shown %s, mouse %s, alpha %.3f)'):format(tostring(P._shown), tostring(Q._mouse), R._alpha))

check(#M.errors == 0, 'no reported Lua errors')
for _, message in ipairs(M.errors) do print(message) end
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and #M.errors == 0 and 0 or 1)
