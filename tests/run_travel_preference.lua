-- Default safe policy, transient offer, trip lifetime and followed-only retention.
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')
local bare = arg and arg[1] == '--bare'
if bare then
    MenuUtil, ShowUIPanel, HideUIPanel, RegisterUIPanel = nil, nil, nil, nil
    local create = CreateFrame
    CreateFrame = function(kind, name, parent, template)
        if template == 'ButtonFrameTemplate' or template == 'WowStyle1DropdownTemplate'
            or template == 'SearchBoxTemplate' or template == 'InputBoxTemplate' then
            error('optional template unavailable')
        end
        return create(kind, name, parent, template)
    end
end
function UnitFactionGroup() return 'Horde' end
function UnitLevel() return 30 end
function GetUnitSpeed() return 0, 7 end
WaypointTrackerDB = {version = 3, settings = {}}
WaypointTrackerCharDB = {waypoints={{m=37,x=.8,y=.5,title='Old picker save',active=true,travelPreference='fastest',travelChosen=true}}}
-- A real tracker post-hook feeds the shared Follow/active-waypoint path.
ObjectiveTrackerFrame = CreateFrame('Frame', nil, UIParent)
QuestObjectiveTracker = CreateFrame('Frame', nil, ObjectiveTrackerFrame)
local questBlock = CreateFrame('Frame', nil, QuestObjectiveTracker)
questBlock.id, questBlock.used, questBlock.parentModule = 101, true, QuestObjectiveTracker
questBlock.HeaderButton = CreateFrame('Button', nil, questBlock)
function QuestObjectiveTracker:EnumerateActiveBlocks(callback) callback(questBlock) end
function QuestObjectiveTracker:OnBlockHeaderClick() M.openedQuest = questBlock.id end
questBlock.HeaderButton:SetScript('OnClick', function(_, button)
    QuestObjectiveTracker:OnBlockHeaderClick(questBlock, button)
end)
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN')
local T, G, WP = ns.Travel, ns.Geo, ns.WP
local passed, failed = 0, 0
local function check(v, why)
    if v then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. why) end
end
check(ns.Get('travelPreference') == 'safer', 'missing preference migrates to safe default')
check(WP.GetActive() and not WP.GetActive().travelPreference and not WP.GetActive().travelChosen, 'old per-waypoint picker overrides are discarded')
ns.Set('travelPreference', 'fastest')
check(WaypointTrackerDB.settings.travelPreference == 'fastest', 'option writes the saved settings table')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
check(ns.Get('travelPreference') == 'fastest', 'explicit Fastest survives reload')
WaypointTrackerDB.settings.travelPreference = 'bad'
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
check(ns.Get('travelPreference') == 'safer', 'invalid preference repaired')
WaypointTrackerDB.settings.travelPreference = 'safer'
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
check(ns.Get('travelPreference') == 'safer', 'old Safer value remains safe on reload')
local function node(id, area, map, x)
    local cont, wx, wy = G.MapToWorld(map, x, .5)
    return table.concat({id, 'pass', area, cont, wx, wy, map, x * 100, 50}, '\t')
end
ns.TravelData = {areas = {'start','risk','safe','goal'}, indoor = {},
    nodes = table.concat({node('A',1,37,.1),node('R',2,52,.3),node('S',3,37,.3),node('G',4,37,.8)}, '\n'),
    links = 'A\tR\twalk\t50\t\t\t1\nR\tG\twalk\t50\t\t\t1\nA\tS\twalk\t72.5\t\t\t1\nS\tG\twalk\t72.5\t\t\t1',
    maps = '37\t1', regions = '37\t4\t80\t50\t2', levels = '52\t60\t63', towns = '', cities = '', factors = ''}
T._Reset(); local d = T.Data()
local function place(x, area)
    local cont, wx, wy = G.MapToWorld(37, x, .5)
    return {m=37,x=x,y=.5,area=area,cont=cont,wx=wx,wy=wy}
end
local start, goal = place(.1,1), place(.8,4)
local c = {faction='Horde',level=30,run=7,ground=7,flights=false,boats=false,flightFactor=1,jumps={}}
local function has(path,id)
    for _, e in ipairs(path or {}) do if e.node.id == id then return true end end
end
local choices, chosen = T.Routes(start,goal,c,'fastest')
check(chosen.total == 100 and has(chosen.path,'R'), 'Always fastest ignores danger')
choices, chosen = T.Routes(start,goal,c,'safer')
check(chosen.total == 145 and has(chosen.path,'S'), 'safe policy selects lower-risk detour')
check(choices[1].total == 100 and choices[1].risk == 60 and choices[2].risk == 0, 'danger cost is separate from ETA')
check(choices[1].path[#choices[1].path].at == 100, 'ETA excludes danger surcharge')
check(c.preference == nil and c.measureDanger == nil, 'planning does not mutate context')
check(T.CanOffer(choices[1],chosen), 'faster riskier route merits offer')
local function costs(fast,safe)
    d.out.A[1].cost=fast/2;d.out.R[1].cost=fast/2
    d.out.A[2].cost=safe/2;d.out.S[1].cost=safe/2
end
costs(1000,1300)
choices, chosen = T.Routes(start,goal,c,'safer')
check(chosen.total==1300 and chosen.risk==0, 'safe policy never auto-switches at old 20% detour cap')
costs(200,280)
choices, chosen = T.Routes(start,goal,c,'safer')
check(chosen.total==280 and chosen.risk==0, 'safe policy never auto-switches at old 60-second cap')
local function eligible(fast,safe,risk,safeRisk)
    return T.CanOffer({total=fast,risk=risk or 60},{total=safe,risk=safeRisk or 0})
end
check(not eligible(100,114.999), 'under 15 seconds does not offer')
check(eligible(100,115), '15-second minimum is inclusive')
check(not eligible(381.001,400), 'under 5% of safe ETA does not offer')
check(eligible(380,400), '5% minimum is inclusive')
check(not eligible(385,400), '15 seconds alone insufficient below relative threshold')
check(not eligible(85,100,0,0), 'equal-risk faster route has no offer')
check(not eligible(100,100) and not eligible(101,100), 'equal or slower risky route has no offer')
check(not T.CanOffer(nil,{total=100,risk=0}), 'missing risky candidate has no offer')
-- Town corridor exposure includes an enemy town between the endpoints.
local mid=place(.5,1)
d.towns={{area=271,fac='Alliance',inn=mid}}
local risk, id, kind=T.Danger(place(.4,1),place(.6,1),c,100)
check(risk>0 and id==271 and kind=='town', 'enemy town crossing is penalized between stops')
d.towns[1].fac='Horde';check(T.Danger(place(.4,1),place(.6,1),c,100)==0,'friendly towns are safe')
d.towns[1].fac='Both';check(T.Danger(place(.4,1),place(.6,1),c,100)==0,'neutral towns are safe')
d.towns={}
d.cities[84]='Alliance'
local hostile=place(.4,1);hostile.city=84
check(T.Danger(hostile,place(.6,1),c,100)==60,'hostile city exposure is penalized')
local low=place(.4,1);low.m=52
check(T.Danger(start,low,c,100)==60,'high-level zones penalized')
c.level=57;check(T.Danger(start,low,c,100)==0,'exactly three levels above is not penalized');c.level=30
-- Hysteresis is never used by preview/initial choice or a different destination.
local token={}
local old={wp=token,total=100,risk=0,preference='fastest',followed=true}
local new={wp=token,total=98,risk=0}
check(T.KeepFollowed(old,new,'fastest',false),'followed route retains a two-second gain')
new.total=97;check(not T.KeepFollowed(old,new,'fastest',false),'three-second gain changes route')
old.total=1000;new.total=981;check(T.KeepFollowed(old,new,'fastest',false),'2% threshold retains a 19-second gain')
new.total=980;check(not T.KeepFollowed(old,new,'fastest',false),'2% gain changes route')
old.followed=false;check(not T.KeepFollowed(old,new,'fastest',true),'initial/preview routes never retain even explicit choices')
old.followed=true;new.wp={};check(not T.KeepFollowed(old,new,'fastest',true),'different destination never retains')
new.wp=token;check(not T.KeepFollowed(old,new,'safer',true),'different chosen policy never retains')
-- All activation paths use the same deferred offer without changing window pages.
costs(100,145)
ns.Set('realRoutes',true);ns.Set('travelFlights',false);ns.Set('travelHearth',false);ns.Set('travelTrails',false)
ns.Set('travelPreference','safer')
M.player.inst,M.player.wx,M.player.wy=start.cont,start.wx,start.wy
C_Map.GetBestMapForUnit=function() return 37 end
local function begin(title)
    local wp=WP.Add(37,.8,.5,{title=title})
    T.Steer(wp)
    return wp
end
local function update(seconds) T.offerButton:RunScript('OnUpdate',seconds) end
local wp=begin('Safe default')
local offer=T.offerButton
check(has(T.Current().path,'S') and T.Current().preference=='safer', 'initial trip chooses safe without input')
check(offer:IsShown() and offer:GetText():find('0:45',1,true) and offer:GetText():find(ns.L.TRAVEL_FASTER_OFFER:format('0:45'),1,true), 'unobtrusive offer shows localized time saving')
check(offer:GetText():find(ns.L.TRAVEL_RISK_LEVEL:format(G.GetMapName(52)),1,true), 'offer names the high-level hazard')
check(offer:GetParent()==UIParent and not ns.Window.CurrentPage('find'), 'offer uses independent addon control and no picker page')
update(8);check(offer:IsShown() and offer:GetAlpha()==1, 'offer remains fully visible for eight seconds')
update(1);check(offer:IsShown() and math.abs(offer:GetAlpha()-.5)<.001, 'offer fades during final two seconds')
update(1);check(not offer:IsShown(), 'offer hides after ten unhovered seconds')
T.Offer(wp);M.now=M.now+3;T.Invalidate();T.Steer(wp)
check(not offer:IsShown() and has(T.Current().path,'S'), 'expiry and ordinary replan never repeat offer or change safe policy')
-- Deferred activation callback must not repeat a consumed offer.
M.Tick(.05)
check(not offer:IsShown(), 'queued activation cannot reoffer after expiry')
wp=begin('Live clock trip');M.Tick(10)
check(not offer:IsShown() and T.Current().preference=='safer', 'real update clock expires offer despite repeated steering and replans')
wp=begin('Hover trip');update(9)
offer:RunScript('OnEnter');update(30)
check(offer:IsShown() and offer.remaining==1 and offer:GetAlpha()==1, 'hover pauses timer and restores full visibility')
offer:RunScript('OnLeave');update(.5)
check(offer:IsShown() and math.abs(offer:GetAlpha()-.25)<.001, 'leaving resumes the remaining fade')
update(.5);check(not offer:IsShown(), 'paused offer expires after remaining unhovered second')
wp=begin('Accepted risk');offer:Click()
check(wp.travelPreference=='fastest' and not wp.travelChosen and has(T.Current().path,'R') and not offer:IsShown(), 'click switches to fastest for this trip and hides offer')
check(ns.Get('travelPreference')=='safer', 'click does not change saved global preference')
WP.Save()
local leaked=false
for _, saved in ipairs(ns.charDB.waypoints) do leaked=leaked or saved.travelPreference~=nil or saved.travelChosen~=nil or saved.travelTrip~=nil end
check(not leaked, 'trip override and tokens never persist to SavedVariables')
costs(110,145);M.now=M.now+3;T.Invalidate();T.Steer(wp)
check(T.Current().preference=='fastest' and has(T.Current().path,'R') and not offer:IsShown(), 'two-second rerouting keeps accepted risky trip policy')
local nextwp=begin('Next trip')
check(T.Current().preference=='safer' and has(T.Current().path,'S') and offer:IsShown(), 'next trip starts safe and may offer again')
WP.SetActive(wp,true);T.Steer(wp)
check(wp.travelPreference==nil and T.Current().preference=='safer', 'returning to previous waypoint starts a safe new trip')
-- No meaningful saving, equal risk, Always fastest and stale click revalidation.
costs(100,110);wp=begin('Trivial gain')
check(has(T.Current().path,'S') and not offer:IsShown(), 'trivial riskier saving leaves single safe route')
costs(100,145);T.Invalidate();M.now=M.now+3;T.Steer(wp)
check(not offer:IsShown(), 'newly meaningful gain on replan never introduces offer mid-trip')
ns.Set('travelPreference','fastest');wp=begin('Always fastest')
check(has(T.Current().path,'R') and not offer:IsShown(), 'Always fastest selects minimum ETA with no offer')
ns.Set('travelPreference','safer');wp=begin('Stale advantage')
check(offer:IsShown(), 'new safe trip offers risky shortcut')
costs(100,110);offer:Click();T.Steer(wp)
check(wp.travelPreference==nil and has(T.Current().path,'S') and not offer:IsShown(), 'click revalidates expired advantage and stays safe')
costs(100,145);wp=begin('Combat acceptance');M.player.combat=true
offer:Click();M.player.combat=false
check(wp.travelPreference=='fastest' and has(T.Current().path,'R'), 'unprotected addon offer can be accepted in combat')
-- Find destination and quest click-to-track trigger deferred offer centrally.
local nearest=ns.DB.NearestOf
ns.DB.NearestOf=function() return {kind='npc',name='Found destination'}, {m=37,x=.8,y=.5} end
ns.Find.Activate({kind='npc',name='Find integration'});M.Tick(.05)
check(offer:IsShown() and WP.GetActive().travelPreference==nil, 'Find selection offers while retaining safe default')
ns.DB.NearestOf=nearest
local position=ns.Places.QuestPosition
ns.Places.QuestPosition=function() return 37,.8,.5 end
questBlock.HeaderButton:RunScript('OnClick','LeftButton');M.Tick(.05)
local quest=WP.GetActive();T.Steer(quest)
check(M.openedQuest==101 and quest.source=='quest', 'actual tracker title post-hook opens details and tracks destination')
check(offer:IsShown() and has(T.Current().path,'S'), 'quest click-to-track starts safe and offers shortcut')
offer:Click();local token=quest.travelTrip
-- Use a significant objective move to exercise waypoint replacement.
ns.Places.QuestPosition=function() return 37,.79,.5 end
local moved=ns.Follow.TrackQuest(101);M.Tick(.05)
check(moved~=quest and moved.travelTrip==token and moved.travelPreference=='fastest' and not offer:IsShown(), 'same quest objective update retains risky trip and never repeats offer')
-- Corpse navigation suspends the same living trip, even if its quest moves
-- while dead. Resurrection restores its policy, selection and consumed offer.
local nearDeath=WP.Add(37,.1,.5,{title='Near death',silent=true,setActive=false})
M.player.dead=true;M.FireEvent('PLAYER_DEAD');M.player.ghost=true
local corpse=WP.GetActive()
check(corpse and corpse.source=='corpse', 'death temporarily gives corpse navigation the arrow')
ns.Places.QuestPosition=function() return 37,.785,.5 end
M.FireEvent('QUEST_LOG_UPDATE');M.Tick(.7)
check(WP.GetActive()==corpse and not WP.IsValid(moved), 'dead quest update replaces living waypoint without stealing corpse arrow')
check(not offer:IsShown(), 'corpse navigation suppresses living faster offer')
WP.CheckArrival(corpse,100);WP.CheckArrival(corpse,0)
check(not WP.IsValid(corpse) and WP.GetActive().source=='quest', 'corpse arrival restores living quest before auto-clear can select a nearby pin')
M.player.dead,M.player.ghost=false,false;M.FireEvent('PLAYER_UNGHOST');M.Tick(.05)
local restored=WP.GetActive();T.Steer(restored)
check(restored~=nearDeath and restored.source=='quest' and restored.x==.785, 'resurrection restores updated clicked quest instead of near-death waypoint')
check(restored.travelTrip==token and restored.travelPreference=='fastest' and T.Current().preference=='fastest' and has(T.Current().path,'R'), 'resurrection preserves accepted faster policy and trip token')
check(not offer:IsShown(), 'resurrection never repeats the consumed offer')
local newquest=ns.Follow.TrackQuest(102);M.Tick(.05)
check(newquest.travelPreference==nil and newquest.travelTrip~=token and offer:IsShown(), 'different quest starts safe and permits a new offer')
ns.Places.QuestPosition=position
-- Actual followed-only hysteresis remains after replacing the picker.
costs(100,145);ns.Set('travelPreference','fastest')
local followed=begin('Hysteresis trip')
check(has(T.Current().path,'R'), 'initial followed choice gets fastest route')
costs(100,98);M.now=M.now+3;T.Invalidate();T.Steer(followed)
check(has(T.Current().path,'R') and T.Current().total==100, 'followed replan retains two-second gain')
local fresh=begin('Fresh hysteresis trip')
check(has(T.Current().path,'S') and T.Current().total==98, 'fresh trip never uses hysteresis')
WP.SetActive(followed,true);costs(100,145);T.Steer(followed)
costs(100,97);M.now=M.now+3;T.Invalidate();T.Steer(followed)
check(has(T.Current().path,'S') and T.Current().total==97, 'followed replan switches at three-second threshold')
print(('Travel preference: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
