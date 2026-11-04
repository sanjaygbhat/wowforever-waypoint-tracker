-- Inspect mouse configuration of the new invisible overlay; no client hit test.
package.path='tests/?.lua;'..package.path
local M=require('wowmock')
function GameTooltip:IsOwned(owner) return self:GetOwner()==owner end
local clicks=0
QuestObjectiveTracker=CreateFrame('Frame',nil,UIParent)
local module=QuestObjectiveTracker
local block=CreateFrame('Frame',nil,module)
block.id,block.used,block.parentModule=101,true,module
block.HeaderButton=CreateFrame('Button',nil,block)
function block.HeaderButton:IsMouseOver() return false end
function module:EnumerateActiveBlocks(fn) fn(block) end
function module:OnBlockHeaderClick() clicks=clicks+1 end
function module:EndLayout() end
function module:OnFreeBlock() block.used=false end
block.HeaderButton:SetScript('OnClick',function(_,button) module:OnBlockHeaderClick(block,button) end)
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN');M.Tick(.1)
local icon=assert(ns.QuestTracker.buttons[1])
assert(icon:IsMouseEnabled() and icon:IsVisible() and icon:GetAlpha()==0)
M.shift=true
block.HeaderButton:Click('LeftButton')
assert(clicks==1,'header preserves native click')
icon:Click('LeftButton')
assert(clicks==1 and ns.Follow.GetTrackedQuestID()==nil, 'modified overlay click does not track or invoke native handler')
M.shift=false;M.player.combat=true
ns.Set('questClickTrack',false);M.Tick(.1)
assert(icon:GetAlpha()==0 and ns.Follow.GetTrackedQuestID()==nil, 'disabled combat overlay remains inert')
icon:Click('LeftButton')
assert(ns.Follow.GetTrackedQuestID()==nil, 'disabled click never tracks')
module:OnFreeBlock(block);M.Tick(.1)
assert(icon.block==nil and icon:GetAlpha()==0, 'freed block loses its binding in combat')
icon:Click('LeftButton')
assert(ns.Follow.GetTrackedQuestID()==nil, 'freed pooled button cannot track a stale quest')
M.player.combat=false; M.FireEvent('PLAYER_REGEN_ENABLED'); M.Tick(.1)
assert(not icon:IsVisible() and not icon:IsMouseEnabled(), 'deferred cleanup hides and disables freed overlay')
print('PASS: modified clicks, combat disable, released binding and deferred cleanup (no native hit testing)')
assert(#M.errors==0,tostring(M.errors[1]))
