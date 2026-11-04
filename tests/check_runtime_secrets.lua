-- Secret-like sentinels fail numerical/string operations; issecretvalue knows them.
-- Offline fault injection proves the code path; it does not reproduce the WoW
-- VM's secret-string equality rules or prove which live player states trigger it.
-- Run at repo root: lua5.1 tests/check_runtime_secrets.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local secretString, secretNumber = 'Restricted audit name', 987654321
local secret = setmetatable({}, {
    __add=function() error('arithmetic on secret sentinel') end,
    __sub=function() error('arithmetic on secret sentinel') end,
    __mul=function() error('arithmetic on secret sentinel') end,
    __lt=function() error('comparison on secret sentinel') end,
    __le=function() error('comparison on secret sentinel') end,
    __concat=function() error('concatenation on secret sentinel') end,
    __tostring=function() error('string conversion on secret sentinel') end,
})
local oldSecret = issecretvalue
issecretvalue = function(v)
    return rawequal(v,secret) or rawequal(v,secretString) or rawequal(v,secretNumber)
        or (oldSecret and oldSecret(v)) or false
end
local ns = M.LoadAddon('WaypointTracker','WaypointTracker')
-- Lua 5.1's tonumber(table) quietly returns nil, so trap the unsafe conversion
-- explicitly. This makes a pre-guard conversion fail instead of hiding it.
local nativeTonumber = tonumber
tonumber = function(v, ...)
    assert(not rawequal(v, secret), 'numeric conversion on secret sentinel')
    return nativeTonumber(v, ...)
end
M.FireEvent('ADDON_LOADED','WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
M.FireEvent('PLAYER_ENTERING_WORLD')
local passed, failed=0,0
local function check(ok, line, entry, value, why)
    if ok then passed=passed+1 else
        failed=failed+1
        local shown = rawequal(value, secret) and '<secret>' or tostring(value)
        print(('Runtime secrets:%d: %s: value=%s: %s'):format(line,entry,shown,why))
    end
end
-- Find private helpers in the loaded closure graph; no source edits/load hacks.
local function find(fn, want, seen)
    seen=seen or {}
    if seen[fn] then return end
    seen[fn]=true
    for i=1,100 do
        local name,value=debug.getupvalue(fn,i)
        if not name then break end
        if name==want and type(value)=='function' then return value end
        if type(value)=='function' then
            local found=find(value,want,seen)
            if found then return found end
        end
    end
end
check(ns.Num(secret)==nil and ns.Plain(secret)==nil and ns.Str(secret)==nil,
    1, 'shared guards', 'nil', 'sentinel must be rejected')
check(ns.Str(secretString)==nil and ns.Num(secretNumber)==nil, 1, 'typed secret guards', 'nil',
    'secret values with the expected Lua type must still be rejected')
check(ns.Str('Player')=='Player' and ns.Str(nil)==nil and ns.Str(42)==nil
    and ns.Num(20)==20 and ns.Num(nil)==nil and ns.Num('20')==nil and ns.Num(0/0)==nil,
    1, 'normal guards', 'plain values', 'normal types survive, invalid types are rejected')
local ready=find(ns.Travel.Steer,'Ready')
assert(ready,'Travel Ready helper not found; update the test for a renamed helper')
local readyLine=debug.getinfo(ready,'S').linedefined
local ok, result=pcall(ready,secret,30)
check(ok and result==false, readyLine, 'Ready(secret start)', result,
    'restricted cooldown must be skipped without comparing or adding it')
ok,result=pcall(ready,1000,secret)
check(ok and result==false, readyLine, 'Ready(secret duration)', result,
    'restricted cooldown duration must be skipped without arithmetic')
local log=find(ns.Travel.Steer,'Log')
assert(log,'Travel Log helper not found; update the test for a renamed helper')
local facing=GetPlayerFacing
GetPlayerFacing=function() return secret end
ok,result=pcall(log,{m=1416,x=0.48,y=0.82,cont=0,wx=0,wy=0,area=1416},
    {id='AUDIT_FACE',cont0=0,wx0=1,wy0=1},{title='Audit',bearing=0})
GetPlayerFacing=facing
check(ok,debug.getinfo(log,'S').linedefined,'Log(secret facing)',result,'logger must sanitize facing before math.deg')
-- All returned components must be checked, including the instance id.
local position=UnitPosition
UnitPosition=function() return secret,secret,secret,secret end
M.now=M.now+10
ok,result=pcall(ns.Geo.GetPlayerWorld)
UnitPosition=position
check(ok,353,'Geo secret coordinates',result,'position fallback must reject restricted components')

-- Startup must not forward a restricted name to the addon API. A later call
-- with a normal name must work; nothing restricted is cached.
local nativeName, nativeLoaded = UnitName, C_AddOns.IsAddOnLoaded
local nativeState, nativeLoadable = C_AddOns.GetAddOnEnableState, C_AddOns.IsAddOnLoadable
local lookups = 0
C_AddOns.IsAddOnLoaded = function() return false end
C_AddOns.GetAddOnEnableState = function(addon, player)
    lookups = lookups + 1
    assert(addon=='TomTom' and player=='Audit Player', 'unexpected or restricted API argument')
    return 2
end
UnitName = function() return secret end
ok,result=pcall(ns.IsOtherArrowAddonPresent)
check(ok and result==false and lookups==0, 1, 'startup secret player name', result, 'skip lookup without forwarding secret')
UnitName = function() return secretString end
ok,result=pcall(ns.IsOtherArrowAddonPresent)
check(ok and result==false and lookups==0, 1, 'startup typed secret name', result, 'skip restricted string lookup')
UnitName = function() return 'Audit Player' end
ok,result=pcall(ns.IsOtherArrowAddonPresent)
check(ok and result==true and lookups==1, 1, 'startup normal player name', result, 'retry with the unchanged player name')
C_AddOns.GetAddOnEnableState = function() return secret end
ok,result=pcall(ns.IsOtherArrowAddonPresent)
check(ok and result==false, 1, 'startup secret enable state', result, 'reject state before comparison')
C_AddOns.GetAddOnEnableState = function() return 2 end
C_AddOns.IsAddOnLoadable = function() return false end
check(ns.IsOtherArrowAddonPresent()==false, 1, 'startup not loadable', false, 'normal disabled loadability is preserved')
C_AddOns.IsAddOnLoadable = function() return secret end
ok,result=pcall(ns.IsOtherArrowAddonPresent)
check(ok and result==true, 1, 'startup secret loadability', result, 'enabled addon with unknown loadability retains conservative fallback')
UnitName=nil
ok,result=pcall(ns.IsOtherArrowAddonPresent)
check(ok and result==false, 1, 'startup absent UnitName', result, 'skip unavailable player API')
UnitName, C_AddOns.IsAddOnLoaded = nativeName, nativeLoaded
C_AddOns.GetAddOnEnableState, C_AddOns.IsAddOnLoadable = nativeState, nativeLoadable

-- Exercise the gathering event and actual recorded stop; a secret title must
-- never reach saved route data or the recording UI.
local nativeSpells = C_Spell
C_Spell = C_Spell or {}
local R, nativeSpell, nativeMap = ns.Routes, C_Spell.GetSpellName, ns.Geo.GetPlayerMapPosition
C_Spell.GetSpellName = function(id) return 'Gather '..id end
ns.Geo.GetPlayerMapPosition = function() return 37,0.4,0.6 end
for _,case in ipairs({{secret, R.CategoryLabel('skinning')}, {secretString,R.CategoryLabel('skinning')},
    {'Audit Beast','Audit Beast'}, {false,R.CategoryLabel('skinning')}}) do
    UnitName = function(unit) if unit=='target' then return case[1] or nil end return nativeName(unit) end
    R.RecordStart()
    local errors = #M.errors
    M.FireEvent('UNIT_SPELLCAST_SUCCEEDED','player','audit-cast',8613)
    local pts = R.Recording().pts
    check(#M.errors==errors and #pts==1 and pts[1].t==case[2], 1,
        'skinning target title', #pts, 'record normal name or plain category fallback')
    R.RecordCancel()
end
UnitName, C_Spell.GetSpellName, ns.Geo.GetPlayerMapPosition = nativeName, nativeSpell, nativeMap
C_Spell = nativeSpells

-- A deterministic nearby quest fixture tests both sides of the minimum-level
-- comparison, including the level-1 fallback without relying on bundled data.
assert(ns.DB.Load(), 'database must load for quest fixture')
local DB, nativeLevel, nativeVector = ns.DB, UnitLevel, ns.Geo.GetVector
local nativeUnits, nativeObjects, nativeQuests = DB.units, DB.objects, DB.quests
local nativeEnemy, nativeQuestState, nativeEntries = DB.IsEnemy, DB.QuestState, C_QuestLog.GetNumQuestLogEntries
local map = C_Map.GetBestMapForUnit('player')
DB.units = {[900001]={id=900001,kind='npc',name='Audit Giver',points={{m=map,x=0.4,y=0.6}}}}
DB.objects = {}
local low = {id=900002,kind='quest',min=1,startU={900001}}
local high = {id=900003,kind='quest',min=10,startU={900001}}
DB.quests = {[low.id]=low,[high.id]=high}
DB.IsEnemy, DB.QuestState = function() return false end, function() return 'new' end
C_QuestLog.GetNumQuestLogEntries = function() return 0 end
ns.Geo.GetVector = function() return 10 end
DB.generation = DB.generation+1
for _,case in ipairs({{secret,1},{secretNumber,1},{false,1},{'invalid',1},{1,1},{20,2}}) do
    UnitLevel = function() return case[1] or nil end
    local total
    ok,result,total=pcall(DB.Nearby,{quest=true})
    check(ok and total==case[2] and result[1]==low and (case[2]==1 or result[2]==high),
        1, 'nearby quest level', total, 'filter by normal level or safe level-1 default')
end
DB.units, DB.objects, DB.quests = nativeUnits, nativeObjects, nativeQuests
DB.IsEnemy, DB.QuestState, C_QuestLog.GetNumQuestLogEntries = nativeEnemy, nativeQuestState, nativeEntries
ns.Geo.GetVector, UnitLevel = nativeVector, nativeLevel
DB.generation = DB.generation+1

-- Trigger the real level-sort menu. Unknown levels sort by distance; normal
-- levels still prioritize fitting routes and compute out-of-range gaps.
local UI = ns.RoutesUI
ns.Set('routeThisZone',false)
UI.Show()
local nativeAll, nativeDistance, nativeGet = R.All, R.Distance, R.Get
local near = {id='audit-near',name='Near',cat='mining',src='suggested',mode='order',zone=map,
    pts={{m=map,x=0.4,y=0.6}},lv={min=1,max=10},distance=1}
local far = {id='audit-far',name='Far',cat='mining',src='suggested',mode='order',zone=map,
    pts={{m=map,x=0.4,y=0.6}},lv={min=18,max=22},distance=20}
R.All, R.Distance = function() return {far,near} end, function(r) return r.distance end
R.Get = function(id) if id==near.id then return near elseif id==far.id then return far end return nativeGet(id) end
UI.widgets.sort:GenerateMenu()
local sortLevel
for _,item in ipairs(M.lastMenu.items) do if item.text==ns.L.ROUTES_SORT_LEVEL then sortLevel=item.fn end end
assert(sortLevel,'level sort menu action missing')
UnitLevel = function() return 20 end
sortLevel()
for _,case in ipairs({{secret,near},{secretNumber,near},{false,near},{'invalid',near},{20,far},{1,near}}) do
    UnitLevel = function() return case[1] or nil end
    ok,result=pcall(UI.Refresh)
    check(ok and UI.widgets.list.items[1]==case[2] and #UI.widgets.list.items==2,
        1, 'route UI level sort', result, 'normal level ranking or unknown-level distance fallback')
end
R.All, R.Distance, R.Get, UnitLevel = nativeAll, nativeDistance, nativeGet, nativeLevel

-- Clients without secret-value APIs keep the same helper behavior.
local secretAPI = issecretvalue
issecretvalue = nil
local legacy = {L=ns.L}
assert(loadfile('WaypointTracker/Core.lua'))('WaypointTracker',legacy)
check(legacy.Str('Player')=='Player' and legacy.Str(nil)==nil and legacy.Str(42)==nil
    and legacy.Num(20)==20 and legacy.Plain(false)==false, 1, 'legacy helper APIs', true,
    'helpers work when issecretvalue is absent')
issecretvalue, tonumber = secretAPI, nativeTonumber
print(('%d passed, %d failed'):format(passed,failed))
os.exit(failed == 0 and 0 or 1)
