-- Read-only dump of explicit entity and quest-giver coordinate evidence.
local root,input,loader=assert(arg[1]),assert(arg[2]),assert(arg[3])
loadstring=loadstring or load
local f=assert(io.open(loader));local source=f:read('*a');f:close()
source=source:gsub('t%._kind, t%._id = kind, a','t._kind, t._id = kind, a; local info=debug.getinfo(2,"Sl"); t._src=info.source; t._line=info.currentline')
local M=assert(loadstring(source,'@'..loader))()
local targets={}
for line in io.lines(input) do
 local t=line:match('^[^#\t][^\t]*\t[^\t]+\t[^\t]+\t([^\t]+)')
 if t then if t:match('^%d+$') then t='Q'..t end; targets[t]=true end
end
local function json(v)
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"' end
 if type(v)~='table' then return 'null' end
 local out={}; local array=#v>0
 if array then for i=1,#v do out[#out+1]=json(v[i]) end else
 for k,x in pairs(v) do out[#out+1]=json(tostring(k))..':'..json(x) end;table.sort(out) end
 return (array and '[' or '{')..table.concat(out,',')..(array and ']' or '}')
end
C_Seasons={GetActiveSeason=function()return 2 end}; GetCVar=function()return ''end
local kinds={npc='U',object='O',quest='Q',item='I'}
for _,version in ipairs({'Camelot','VanillaSOD'}) do
 local cats=M.Load(root..'/db/'..version);local seen={}
 local function walk(t,context)
  if type(t)~='table' or getmetatable(t) or seen[t] then return end;seen[t]=true
  local key=kinds[t._kind] and tostring(kinds[t._kind])..tostring(t._id)
  local coords=t.coords or (t.coord and {t.coord})
  if coords then
   local matched={}
   if key and targets[key] then matched[key]='direct' end
   if t._kind=='quest' then
    local provider=t.provider
    if type(provider)=='table' and (provider[1]=='n' or provider[1]=='o') then
     local p=(provider[1]=='n' and 'U' or 'O')..tostring(provider[2]);if targets[p] then matched[p]='quest-provider' end
    end
    if tonumber(t.qg) then local p='U'..tostring(t.qg);if targets[p] then matched[p]='quest-giver' end end
   end
   for target,method in pairs(matched) do
    print(json({target=target,method=method,entity=key,coords=coords,version=version,source=t._src,line=t._line,context=context}))
   end
  end
  local ctx=context
  if t._kind=='map' or t._kind=='instance' then ctx=(context or '')..'/'..t._kind..':'..tostring(t._id) end
  for _,child in pairs(t) do if type(child)=='table' then walk(child,ctx) end end
 end
 walk(cats,'')
end
