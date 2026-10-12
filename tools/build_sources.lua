-- Builds WaypointTracker_Data/Sources.lua and Sources_<loc>.lua from pfQuest's
-- item database: who sells, drops or holds every item, plus the names of the
-- items the rest of the database doesn't name.
-- usage: lua build_sources.lua <pfquest dir> <work dir>
local PF, W = arg[1], arg[2]
pfDB = { items = {}, units = {} }
dofile(PF .. "/db/items.lua")
dofile(PF .. "/db/units.lua")
local LOCALES = { "enUS", "deDE", "esES", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
for _, l in ipairs(LOCALES) do dofile(PF .. "/db/" .. l .. "/items.lua") end
local data, units = pfDB.items.data, pfDB.units.data

-- ids already named by Data.lua (Names_enUS items) or the client tables
local named = {}
local function scan(path, startPat, endPat, needName)
  local f = assert(io.open(path)); local inside = false
  for line in f:lines() do
    if line:find(startPat, 1, true) then inside = true
    elseif inside and line:find(endPat, 1, true) then inside = false
    elseif inside then
      local id, name = line:match("^(%d+)\t([^\t]*)")
      if id and (not needName or (name and name ~= "")) then named[tonumber(id)] = true end
    end
  end
  f:close()
end
scan(W .. "/WaypointTracker_Data/Names_enUS.lua", "items = [==[", "]==]")
scan(W .. "/WaypointTracker_Data/Items_enUS.lua", "D.clientItemNames.enUS = [==[", "]==]", true)

local ids = {}
for id in pairs(data) do ids[#ids + 1] = id end
table.sort(ids)
local lines, need = {}, {}
local nv = 0
for _, id in ipairs(ids) do
  local d = data[id]
  local v, u, o = {}, {}, {}
  for npc in pairs(d.V or {}) do if units[npc] then v[#v + 1] = npc end end
  for npc, ch in pairs(d.U or {}) do if ch >= 1 and units[npc] then u[#u + 1] = { npc, ch } end end
  for obj in pairs(d.O or {}) do o[#o + 1] = obj end
  table.sort(v); table.sort(o)
  table.sort(u, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
  local uu = {}
  for i = 1, math.min(#u, 20) do uu[i] = u[i][1] end
  while #o > 20 do table.remove(o) end
  local en = pfDB.items.enUS[id]
  if (#v + #uu + #o) > 0 and en and not en:find("^OLD") and not en:find("UNUSED") and not en:find("^Deprecated") then
    lines[#lines + 1] = id .. "\t" .. table.concat(uu, ",") .. "\t" .. table.concat(o, ",") .. "\t" .. table.concat(v, ",")
    if #v > 0 then nv = nv + 1 end
    if not named[id] then need[#need + 1] = id end
  end
end

local function clean(s) return (s:gsub("[\t\r\n]", " ")) end
local function write(path, body)
  local f = assert(io.open(path, "w")); f:write(body); f:close()
end
local head = "-- Generated from pfQuest's item database (https://github.com/shagu/pfQuest,\n-- MIT; see THIRD-PARTY-LICENSES.txt). Do not edit.\n"
local names = {}
for _, id in ipairs(need) do names[#names + 1] = id .. "\t" .. clean(pfDB.items.enUS[id]) end
write(W .. "/WaypointTracker_Data/Sources.lua", head .. table.concat({
  "local D = WaypointTrackerData",
  "if not D then",
  "    return",
  "end",
  "-- id, dropped by npcs (likeliest first), found in objects, sold by npcs",
  "D.sources = [==[",
  table.concat(lines, "\n"),
  "]==]",
  "D.sourceNames = D.sourceNames or {}",
  "-- id, name (for items the rest of the database doesn't name)",
  "D.sourceNames.enUS = [==[",
  table.concat(names, "\n"),
  "]==]",
  "",
}, "\n"))
for _, l in ipairs(LOCALES) do
  if l ~= "enUS" then
    local loc = {}
    local t = pfDB.items[l] or {}
    for _, id in ipairs(need) do
      -- Explicit English fallback matches Database.ParseSources when the
      -- source has no translated name; every locale retains the same IDs.
      local n = t[id]
      if not n or n == "" then n = pfDB.items.enUS[id] end
      loc[#loc + 1] = id .. "\t" .. clean(n)
    end
    write(W .. "/WaypointTracker_Data/Sources_" .. l .. ".lua", head .. table.concat({
      "local D = WaypointTrackerData",
      "if not D then",
      "    return",
      "end",
      "D.sourceNames = D.sourceNames or {}",
      "D.sourceNames." .. l .. " = [==[",
      table.concat(loc, "\n"),
      "]==]",
      "",
    }, "\n"))
  end
end
io.stderr:write(("sources %d (vendor %d), new names %d\n"):format(#lines, nv, #need))
