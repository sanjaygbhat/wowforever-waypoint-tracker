-- Read-only ATT provenance probe. Lua 5.1; no addon output is generated.
-- Usage: lua5.1 tools/quest_source_probe.lua ATT_ROOT ATT_LOAD_LUA
-- The existing offline loader is instrumented in memory for source locations.
local root, loader = assert(arg[1], "ATT root required"), assert(arg[2], "att_load.lua required")
local f = assert(io.open(loader)); local src = f:read("*a"); f:close()
local count
src, count = src:gsub("t%._kind, t%._id = kind, a", [[t._kind, t._id = kind, a
        local d = debug.getinfo(2, "Sl")
        t.__source, t.__line = d.source:gsub("^@", ""), d.currentline]])
assert(count == 1, "loader constructor changed")
local mod = assert(loadstring(src, "@" .. loader))()
local function coords(t, fallback)
    local out, c = {}, t.coords or t.coord
    if type(c) ~= "table" then return out end
    if type(c[1]) == "number" then return {{c[3] or fallback, c[1], c[2]}} end
    for m, pts in pairs(c) do
        if type(m) == "number" and type(pts) == "table" then
            for _, p in ipairs(pts) do
                if type(p) == "table" and type(p[1]) == "number" then out[#out+1] = {m,p[1],p[2]} end
            end
        end
    end
    return out
end
local function emit(t, dataset, target, role, cs, awp)
    if #cs == 0 then cs = {{"", "", ""}} end
    for _, c in ipairs(cs) do
        local path = (t.__source or ""):gsub(root .. "/", "")
        print(table.concat({dataset,target,role,t._kind or "",tostring(t._id or ""),
            tostring(c[1] or ""),tostring(c[2] or ""),tostring(c[3] or ""),
            tostring(t.r or ""),tostring(awp or ""),path,tostring(t.__line or "")}, "\t"))
    end
end
local function walk(t, ctx, dataset)
    if type(t) ~= "table" then return end
    local map = t._kind == "map" and t._id or ctx.map
    local awp = t.awp or ctx.awp
    local cs = coords(t,map)
    if t._kind == "npc" or t._kind == "object" then
        emit(t,dataset,(t._kind == "npc" and "N" or "O") .. t._id,"entity",cs,awp)
    elseif t._kind == "flight" then
        local cr = t.cr or type(t.crs) == "table" and t.crs[1]
        if cr then emit(t,dataset,"N"..cr,"flight",cs,awp) end
    elseif t._kind == "quest" then
        local gs = {}
        for _, g in ipairs(type(t.qgs) == "table" and t.qgs or {}) do gs[#gs+1] = "N"..g end
        if t.qg then gs[#gs+1] = "N"..t.qg end
        for _, key in ipairs({"providers","cost"}) do
            for _, p in ipairs(type(t[key]) == "table" and t[key] or {}) do
                if type(p) == "table" and #gs == 0 and (p[1] == "n" or p[1] == "o") then gs[#gs+1] = (p[1] == "n" and "N" or "O") .. p[2] end
            end
        end
        if #gs == 0 and ctx.npc then gs[1] = "N"..ctx.npc end
        if #gs == 1 then emit(t,dataset,gs[1],"quest-giver-inference",cs,awp) end
        emit(t,dataset,"Q"..t._id,"quest",cs,awp)
    end
    local children = t.g or type(t[1]) == "table" and t or {}
    local nextctx = {map=map,awp=awp,npc=t._kind == "npc" and t._id or ctx.npc}
    if t._kind == "quest" or t._kind == "object" then nextctx.npc=nil end
    for _, child in ipairs(children) do walk(child,nextctx,dataset) end
end
print("dataset\ttarget\trole\tnode_kind\tnode_id\tmap\tx\ty\tr\tawp\tsource\tline")
for _, dataset in ipairs({"Camelot","VanillaSOD"}) do
    C_Seasons = {GetActiveSeason=function() return 2 end}
    GetCVar = function() return "" end
    local cats = mod.Load(root .. "/db/" .. dataset)
    for _, tree in pairs(cats) do walk(tree,{},dataset) end
end
