-- Read pinned pfQuest tables as data in an environment with no capabilities.
-- Called by extract_services.py --pfquest ROOT; never used by the addon.
local root=assert(arg[1])
local env={pfDB={units={},objects={}}}
for _,path in ipairs({'db/units.lua','db/objects.lua','db/enUS/units.lua','db/enUS/objects.lua','db/meta.lua'}) do
 local chunk=assert(loadfile(root..'/'..path));setfenv(chunk,env);chunk()
end
local function json(v)
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"' end
 if type(v)~='table' then return 'null' end
 local out={}
 for k,x in pairs(v) do out[#out+1]=json(tostring(k))..':'..json(x) end
 table.sort(out);return '{'..table.concat(out,',')..'}'
end
local services={mailbox=1,innkeeper=1,flight=1,repair=1,vendor=1,banker=1,auctioneer=1,
 stablemaster=1,spirithealer=1,battlemaster=1,meetingstone=1}
local out={}
for service in pairs(services) do
 out[service]={}
 for id,fac in pairs(env.pfDB.meta[service] or {}) do
  local data=id<0 and env.pfDB.objects or env.pfDB.units
  out[service][id]={fac=fac,name=data.enUS[math.abs(id)] or '',coords=(data.data[math.abs(id)] or {}).coords or {}}
 end
end
print(json(out))
