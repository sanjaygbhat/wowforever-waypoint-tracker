-- Read-only extraction from pinned pfQuest; no output-file writes.
local root, input = assert(arg[1]), assert(arg[2])
pfDB = { units = {}, objects = {}, items = {}, quests = {} }
for _, kind in ipairs({'units','objects','items','quests'}) do
 dofile(root..'/db/'..kind..'.lua')
 dofile(root..'/db/enUS/'..kind..'.lua')
end
local seen, kinds = {}, {U='units',O='objects',I='items',Q='quests'}
for line in io.lines(input) do
 if line:sub(1,1)~='#' then
  local target=line:match('^[^\t]+\t[^\t]+\t[^\t]+\t([^\t]+)')
  if target:match('^%d+$') then target='Q'..target end
  if not seen[target] then
   seen[target]=true
   local prefix,id=target:match('^(%u)(%d+)$'); id=tonumber(id)
   local name=pfDB[kinds[prefix]].enUS[id]
   if type(name)=='table' then name=name.T end
   local data=pfDB[kinds[prefix]].data[id]
   local coords={}
   for _,c in ipairs(data and data.coords or {}) do coords[#coords+1]=table.concat(c,',') end
   print(table.concat({target,(name or ''):gsub('[\r\n\t]',' '),table.concat(coords,';'),data and 'definition' or ''},'\t'))
  end
 end
end
