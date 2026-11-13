-- Included after service_maps.lua_prelude(), using pinned client geometry.
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local DB,Learn=ns.DB,ns.Learn
local side='Alliance';UnitFactionGroup=function()return side end
local passed,failed=0,0
local function check(ok,label,detail)
 print((ok and 'PASS' or 'FAIL')..' '..label..' '..tostring(detail or ''))
 if ok then passed=passed+1 else failed=failed+1 end
end
local function entry(service,id)
 for _,e in ipairs(DB.ServiceEntries(service)) do if e.id==id then return e end end
end
local function points(e)
 local out={};for _,p in ipairs(DB.Points(e)) do out[#out+1]=('%d:%.6f,%.6f'):format(p.m,p.x,p.y) end
 return table.concat(out,';')
end
local function has(e,m,x,y)
 for _,p in ipairs(DB.Points(e)) do if p.m==m and math.abs(p.x-x)<.00001 and math.abs(p.y-y)<.00001 then return true end end
end
local function empty()return {npcs={},objects={},items={},quests={},mailboxes={},fixes={}} end
assert(DB.Load());local st=Learn.Store()
local mode=arg[1] or 'all'
if mode=='all' or mode=='fix' then
 Learn.AddFix('npc',66,{1429,.419,.6706},{1429,.9,.9});DB.MergeLearned()
 local e=entry('vendor',66)
 check(has(e,1429,.9,.9),'1A replacement',points(e))
 for _,source in ipairs({'curated','community','personal'}) do
  local target=source=='personal' and st or DB[source]
  target.fixes=target.fixes or {}
  target.fixes['N352']={{wrong={1453,.7118,.7251},right={1453,.70,.70}}};DB.MergeLearned()
  M.player.inst,M.player.wx,M.player.wy=ns.Geo.MapToWorld(1453,.7,.7);M.now=M.now+1
  local winner,p,d=DB.NearestOf(DB.ServiceEntries('flight'),{faction=true})
  check(winner and winner.id==352 and d<.001,'1B '..source..' flight replacement',winner and winner.name..' '..tostring(d))
  local stale=false
  for _,v in ipairs(DB.ServiceEntries('flight')) do if v.kind=='place' and v.id==-100002 then stale=true end end
  check(not stale,'1B '..source..' no stale Stormwind taxi alias')
  target.fixes['N352']=nil
 end
 st.fixes={};DB.MergeLearned()
end
if mode=='all' or mode=='import' then
 Learn.Import('WTL1\tenUS\t1\nN\t66\tTharynn Bouden\t0\t10\tvendor\t1429:900,900\tA');DB.MergeLearned()
 local e=entry('vendor',66)
 check(has(e,1429,.9,.9) and has(e,1429,.418,.670),'2 imported discovery',points(e))
 st.npcs[66]=nil;DB.MergeLearned()
end
if mode=='all' or mode=='access' then
 side='Horde';st.npcs[66]={name='Personal vendor',fac='H',hostile=false,services={vendor=true},spots={[1429]={.9,.9}}};DB.MergeLearned()
 local e=entry('vendor',66)
 check(e and has(e,1429,.9,.9) and DB.ForMyFaction(e),'2 personal access',points(e))
 side='Alliance';st.npcs[66]=nil;DB.MergeLearned()
end
if mode=='all' or mode=='compact' then
 for _,r in ipairs({{3605,'Nadyia Maneweaver',1438,.4183,.4951},{3658,'Lizzarik',1413,.52,.30},{4167,'Dendrythis',1457,.488,.214}}) do
  -- Use the literal supplement observation, not a nearby guessed coordinate.
  local raw=WaypointTrackerData.serviceSupplement or ''
  local m,x,y=raw:match('SN\t'..r[1]..'\t[^\n]-\t(%d+):([%d.]+),([%d.]+),')
  if m then r[3],r[4],r[5]=tonumber(m),tonumber(x),tonumber(y) end
  M.player.inst,M.player.wx,M.player.wy=ns.Geo.MapToWorld(r[3],r[4],r[5]);M.now=M.now+1
  M.units.npc={guid='Creature-0-1-2-3-'..r[1]..'-ABC',name=r[2],reaction=5,level=10}
  local bestMap=C_Map.GetBestMapForUnit
  C_Map.GetBestMapForUnit=function()return r[3]end
  Learn.Unit('npc','vendor');C_Map.GetBestMapForUnit=bestMap
  DB.MergeLearned();Learn.Compact(true)
  check(not st.npcs[r[1]],'3 compact shipped '..r[1],Learn.Export():match('N\t'..r[1]..'[^\n]*'))
 end
end
if mode=='all' or mode=='retry' then
 local map=ns.Geo.MapToWorld
 ns.Geo.MapToWorld=function(m,...)if m~=1416 then return map(m,...) end end
 local e=entry('innkeeper',28687);local initial=#DB.Points(e)
 ns.Geo.MapToWorld=map
 e=entry('innkeeper',28687)
 check(has(e,1416,.1815,.6638),'4 pending map recovery',initial..' -> '..points(e))
end
check(#M.errors==0,'no captured errors',table.concat(M.errors,';'))
print(('Service regressions: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
