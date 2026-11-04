-- Public identity boundaries must canonicalize every character key.
-- Run at repo root: lua5.1 tests/check_runtime_identity.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
math.randomseed(12345)
UnitName = function() return 'TestPlayer' end
GetUnitName = function() return 'TestPlayer TestSurname-TestRealm' end
GetNormalizedRealmName = function() return 'TestRealm' end
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
M.FireEvent('PLAYER_ENTERING_WORLD')
assert(ns.DB.Load(), 'bundled database must load before selecting a seed')
local R, st = ns.Routes, ns.Routes.Store()
local passed, failed = 0, 0
local function check(ok, line, entry, value, why)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print(('WaypointTracker/Routes.lua:%d: %s: value=%s: %s'):format(line,entry,value,why))
    end
end
local voteLine=debug.getinfo(R.HeardVote,'S').linedefined
local blockLine=debug.getinfo(R.Block,'S').linedefined
local id = R.Suggested()[1].id
st.tally[id] = nil
R.HeardVote(id, 'Peer Surname', 1)
R.HeardVote(id, 'Peer Surname-TestRealm', 1)
local up, down = R.Score(id)
check(up == 1 and down == 0, voteLine, 'Routes.HeardVote', tostring(up)..' upvotes',
    'one character using short and full identities must occupy one Name-Realm tally key')
R.HeardVote(id, 'Peer Surname', 0)
up, down = R.Score(id)
check(up == 0 and down == 0, voteLine, 'Routes.HeardVote removal', tostring(up)..' upvotes',
    'removing a short-form vote must remove the equivalent full-form vote')
R.Block('Peer Surname')
check(st.blocked['Peer Surname-TestRealm'] == true and st.blocked['Peer Surname'] == nil,
    blockLine, 'Routes.Block', 'blocked key Peer Surname', 'block keys must use Name-Realm')
check(R.Me() == 'TestPlayer TestSurname-TestRealm', 139, 'Routes.Me', tostring(R.Me()),
    'full surname and realm from GetUnitName must survive')
st.tally[id] = nil
R.HeardVote(id, 'Peer Surname-TestRealm', 1)
R.HeardVote(id, 'Peer Surname-OtherRealm', 1)
up = R.Score(id)
check(up == 2, voteLine, 'cross-realm voters', tostring(up), 'different realms remain different characters')
-- Camelot/Forever's second UnitName return is a SURNAME, not a realm. See the
-- build-matched Blizzard_FrameXMLUtil/Camelot/NameUtil.lua:3-8. Other WoW
-- flavors use the traditional realm return; this regression targets this client.
UnitName=function(unit)
    if unit=='target' then return 'Peer','Surname' end
    return 'TestPlayer','TestSurname'
end
GetUnitName=function(unit)
    return unit=='target' and 'Peer Surname' or 'TestPlayer TestSurname'
end
UnitExists=function(unit) return unit=='target' or unit=='player' end
UnitIsPlayer=function() return true end
UnitIsUnit=function(a,b) return a==b end
local whisper
for _,channel in ipairs(ns.Share.Channels()) do
    if channel[2]:sub(1,3)=='/w ' then whisper=channel[2] end
end
if whisper~='/w Peer Surname-TestRealm' then
    failed=failed+1
    print(('WaypointTracker/Share.lua:%d: Share.Channels: value=%s: UnitName second return is a surname on this client; target must preserve full name and use the actual normalized realm'):format(debug.getinfo(ns.Share.Channels,'S').linedefined,tostring(whisper)))
else passed=passed+1 end
local targetSent
local originalSend=ns.RoutesNet.SendTo
ns.RoutesNet.SendTo=function(_,name) targetSent=name;return 1 end
ns.RoutesUI.ShowShare(R.Get(id))
local sendAction
for _,item in ipairs(M.lastMenu and M.lastMenu.items or {}) do
    if item.text==ns.L.ROUTE_SEND_TARGET then sendAction=item.fn end
end
assert(sendAction,'route share target action must exist')
sendAction()
if targetSent~='Peer Surname-TestRealm' then
    failed=failed+1
    print(('WaypointTracker/RoutesUI.lua:857: route target identity: value=%s: send must preserve surname and canonical Name-Realm, rather than first name only'):format(tostring(targetSent)))
else passed=passed+1 end
-- Same first name does not mean the target is us; the unit API decides.
GetUnitName=function(unit)
    return unit=='target' and 'TestPlayer OtherSurname' or 'TestPlayer TestSurname'
end
targetSent=nil
sendAction()
check(targetSent=='TestPlayer OtherSurname-TestRealm', 857, 'same first name target', tostring(targetSent),
    'another surname remains a different character')
UnitIsUnit=function() return true end
targetSent=nil
sendAction()
check(targetSent==nil, 857, 'self target', tostring(targetSent), 'self must not be sent a route from the menu')
UnitIsUnit=function(a,b) return a==b end
GetUnitName=function(unit)
    return unit=='target' and 'Peer Surname-OtherRealm' or 'TestPlayer TestSurname'
end
targetSent=nil
sendAction()
check(targetSent=='Peer Surname-OtherRealm', 857, 'qualified target', tostring(targetSent),
    'an explicit remote realm must not be replaced by the local realm')
ns.RoutesNet.SendTo=originalSend
-- Inspect protocol target through the actual queue without sending externally.
local selfTarget
C_ChatInfo=C_ChatInfo or {}
C_ChatInfo.SendAddonMessage=function(_,msg,chat,target)
    if chat=='WHISPER' and msg:sub(1,2)=='R^' then selfTarget=target end
    return 0
end
ns.RoutesNet.SelfTest()
M.Tick(0.1)
if selfTarget~=R.Me() then
    failed=failed+1
    print(('WaypointTracker/RoutesNet.lua:467: self-test whisper identity: value=%s: whisper target must equal Routes.Me() including surname and realm'):format(tostring(selfTarget)))
else passed=passed+1 end
-- Observe real registered callback identities without forcing duplicate calls.
-- SetScript overwrites; HookScript appends. The static validator audits literal
-- duplicates; this test focuses on the identity key boundaries.
check(#M.errors == 0, 1, 'mock errors', tostring(M.errors[1]), 'unexpected runtime error')
print(('%d passed, %d failed'):format(passed,failed))
os.exit(failed == 0 and 0 or 1)
