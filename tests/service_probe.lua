-- Included after tools/service_maps.py's pinned real-map prelude.
local faction=initialFaction or 'Alliance'
local originalFaction=UnitFactionGroup
UnitFactionGroup=function(u) if not u or u=='player' then return faction end return originalFaction(u) end
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN');M.FireEvent('PLAYER_ENTERING_WORLD')
assert(not ns.DB.loaded, 'service supplement must remain lazy at login')
M.noDataAddon=false
for _,origin in ipairs(origins) do
 if origin.faction==faction then
  M.player.inst,M.player.wx,M.player.wy=origin.cont,origin.wx,origin.wy;M.now=M.now+1
  break
 end
end
assert(ns.DB.Load())
local services={'mailbox','innkeeper','flight','repair','vendor','banker','auctioneer','stablemaster','spirithealer','battlemaster','meetingstone'}
local function field(v) return tostring(v or ''):gsub('[\t\r\n]',' ') end
for _,fac in ipairs({'Alliance','Horde'}) do
 faction=fac
 for _,service in ipairs(services) do
  for _,e in ipairs(ns.DB.ServiceEntries(service)) do
   local pts={}
   for _,p in ipairs(ns.DB.Points(e)) do pts[#pts+1]=string.format('%d:%.17g,%.17g',p.m,p.x,p.y) end
   print(table.concat({'ENTRY',fac,service,e.kind,tostring(e.id),field(e.name),e.coords or '',table.concat(pts,';'),e.fac or '',e.learned or ''},'\t'))
  end
 end
end
for _,origin in ipairs(origins) do
 faction=origin.faction;M.player.inst,M.player.wx,M.player.wy=origin.cont,origin.wx,origin.wy
 -- Invalidate the per-frame player cache when changing the survey origin.
 M.now=M.now+1
 for _,service in ipairs(services) do
  local entries=ns.DB.ServiceEntries(service)
  local e,p,d=ns.DB.NearestOf(entries,{faction=true})
  print(table.concat({'NEAREST',faction,origin.name,service,e and field(e.name) or '',p and p.m or '',d and string.format('%.9f',d) or '',e and e.id or '',p and string.format('%.17g',p.x) or '',p and string.format('%.17g',p.y) or ''},'\t'))
 end
end
-- A warm action uses the real map catalogue and complete production roster.
-- Keep this after the survey so position/index initialization is excluded.
if not auditBaseline then
for _,service in ipairs(services) do
 ns.Find.GoToNearest(service);ns.WP.ClearAll(true)
 local start=os.clock()
 ns.Find.GoToNearest(service);ns.WP.ClearAll(true)
 assert((os.clock()-start)*1000<3, 'warm Nearest exceeded 3 ms: '..service)
end
-- Mined rows are community data; later personal observations still win.
faction='Alliance'
local candidate
for _,e in ipairs(ns.DB.ServiceEntries('vendor')) do
 if e.minedService and #ns.DB.Points(e)>0 then candidate=e;break end
end
assert(candidate and candidate.learned=='community')
local store=ns.Learn.Store()
local old=store.npcs[candidate.id]
store.npcs[candidate.id]={name=candidate.name,fac='A',services={vendor=true},spots={[1455]={.33,.44}}}
ns.DB.MergeLearned()
local personal
for _,e in ipairs(ns.DB.ServiceEntries('vendor')) do if e.id==candidate.id then personal=e end end
assert(personal and not personal.minedService, 'personal service observation overrides mined candidate')
local found=false
for _,p in ipairs(ns.DB.Points(personal)) do if p.m==1455 and p.x==.33 and p.y==.44 then found=true end end
assert(found, 'personal observation preserves its position')
store.npcs[candidate.id]=old
-- Object services imported into the discovery store must enter Nearest too.
store.objects[2147483000]={name='Service coverage fixture',services={mailbox=true},spots={[1455]={.3,.4}}}
ns.DB.MergeLearned()
found=false
for _,e in ipairs(ns.DB.ServiceEntries('mailbox')) do if e.id==2147483000 then found=true end end
assert(found, 'object discovery service reaches Nearest')
store.objects[2147483000]=nil
ns.DB.MergeLearned()
end
-- Audit the immutable Classic roster, including records absent from Data.lua.
local env={pfDB={units={},objects={}}}
for _,path in ipairs({'tools/fixtures/pfquest/db/units.lua','tools/fixtures/pfquest/db/objects.lua',
 'tools/fixtures/pfquest/db/enUS/units.lua','tools/fixtures/pfquest/db/enUS/objects.lua','tools/fixtures/services/pfquest-meta.lua'}) do
 local fn=assert(loadfile(path));setfenv(fn,env);fn()
end
for _,service in ipairs(services) do
 for id,fac in pairs(env.pfDB.meta[service] or {}) do
  local data=id<0 and env.pfDB.objects or env.pfDB.units
  local coords={}
  for _,p in pairs((data.data[math.abs(id)] or {}).coords or {}) do
   local m=ns.DB.MapForArea(p[3])
   local x,y
   if m then x,y=ns.DB.FromClassicMap(m,p[1]/100,p[2]/100) end
   coords[#coords+1]=table.concat({p[3],p[1],p[2],m or '',x or '',y or ''},',')
  end
  print(table.concat({'ROSTER',service,id,fac,field(data.enUS[math.abs(id)]),table.concat(coords,';')},'\t'))
 end
end
for _,err in ipairs(M.errors) do io.stderr:write(err,'\n') end
assert(#M.errors==0)
