-- Run by check_discovery_roundtrip.py in separate observe/reload/import VMs.
local mode, state = arg[1], assert(arg[2])
if mode == 'reload' then WaypointTrackerDB = assert(loadfile(state))() end
local side = os.getenv('WT_FACTION') or 'Alliance'
UnitFactionGroup = function() return side end
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN')
local DB, Learn = ns.DB, ns.Learn
assert(DB.Load())
local function dump(v)
    if type(v) == 'table' then
        local keys, out = {}, {}
        for k in pairs(v) do keys[#keys+1] = k end
        table.sort(keys, function(a,b) return tostring(a)<tostring(b) end)
        for _, k in ipairs(keys) do out[#out+1] = '['..dump(k)..']='..dump(v[k]) end
        return '{'..table.concat(out, ',')..'}'
    end
    return type(v)=='string' and string.format('%q',v) or tostring(v)
end
local cases, rows = {}, {}
local st = Learn.Store()
DB.services.vendor = {}
DB.curated, DB.community = {}, {}
local id = 991000
for _, source in ipairs({'base','supplement','personal','imported','correction'}) do
    for _, reaction in ipairs({'friendly','hostile','unknown'}) do
        for _, fac in ipairs({'A','H','AH',''}) do
            id = id + 1
            local hostile
            if reaction ~= 'unknown' then hostile = reaction=='hostile' end
            local name = 'Roundtrip '..id
            DB.units[id] = {kind='npc',id=id,name=name,key=ns.Geo.Squash(name),fac=fac,
                hostile=hostile,coords='1:100,100',svc={vendor=true}}
            DB.services.vendor[#DB.services.vendor+1] = {id=id,fac=fac}
            -- Personal/imported observations override an R row too.
            if source ~= 'base' then
                rows[#rows+1] = table.concat({'SN',id,(source=='correction' and fac=='' and 'AH') or fac,name,'vendor','R','1426:0.5,0.5,0'},'\t')
            end
            if mode == 'observe' then
                if source == 'supplement' or source == 'personal' or source == 'imported' then
                    local x = source=='supplement' and .1 or .2
                    local record={name=name,hostile=hostile,fac=fac~='' and fac or nil,
                        services={vendor=true},spots={[1426]={x,x}}}
                    if source == 'imported' then
                        assert(Learn.Import(table.concat({'WTL1\tenUS\t1','N\t'..id..'\t'..name..'\t'..
                            (hostile==nil and '' or (hostile and '1' or '0'))..'\t\tvendor\t1426:200,200\t'..fac},'\n')))
                    else st.npcs[id]=record end
                elseif source == 'correction' then
                    st.fixes['N'..id]={{wrong={1426,.1,.1},right={1426,.9,.9}},{wrong={1426,.5,.5}}}
                end
            end
            cases[#cases+1] = {id=id,source=source,fac=fac,reaction=reaction,name=name}
        end
    end
end
-- A supplement-only service must not compact away its only Find identity.
id=id+1
rows[#rows+1]=table.concat({'SN',id,'AH','Roundtrip '..id,'vendor','R','1426:0.5,0.5,0'},'\t')
if mode=='observe' then st.npcs[id]={name='Roundtrip '..id,hostile=false,fac='AH',services={vendor=true},spots={[1426]={.5,.5}}} end
cases[#cases+1]={id=id,source='supplement-only',fac='AH',reaction='friendly',name='Roundtrip '..id}
-- A real shipped ID without a Find name still needs the observed name.
id=id+1
DB.units[id]={kind='npc',id=id,name='',key='',fac='AH',hostile=false,coords='1:500,500',svc={vendor=true}}
DB.services.vendor[#DB.services.vendor+1]={id=id,fac='AH'}
rows[#rows+1]=table.concat({'SN',id,'AH','Roundtrip '..id,'vendor','R','1426:0.5,0.5,0'},'\t')
if mode=='observe' then st.npcs[id]={name='Roundtrip '..id,hostile=false,fac='AH',services={vendor=true},spots={[1426]={.5,.5}}} end
cases[#cases+1]={id=id,source='supplement-empty-name',fac='AH',reaction='friendly',name='Roundtrip '..id}
WaypointTrackerData.serviceSupplement=table.concat(rows,'\n')
DB.MergeLearned()
Learn.Compact(true)
local export=Learn.Export()
for _, c in ipairs(cases) do
    local e=DB.units[c.id]
    local available={}
    for _, v in ipairs(DB.ServiceEntries('vendor')) do if v.id==c.id then available[#available+1]=v end end
    local nearest,p,d=DB.NearestOf(available,{faction=true})
    local function inFind(kind, factionFilter)
        for _, v in ipairs(DB.Search(c.name,{[kind]=true},factionFilter and {faction=true} or {},100)) do if v.id==c.id then return true end end
        return false
    end
    assert(inFind('enemy')==DB.IsEnemy(e))
    assert(inFind('npc')~=DB.IsEnemy(e))
    local visible=e.hostile or e.fac=='' or e.fac:find(side:sub(1,1),1,true)~=nil
    local showing=inFind(DB.IsEnemy(e) and 'enemy' or 'npc',true)
    assert(showing==visible,c.source..' changed faction-filtered Find')
    local allowed=c.fac=='' or c.fac:find(side:sub(1,1),1,true)~=nil
    local baseline=os.getenv('WT_ROUNDTRIP_BASELINE')=='1'
    if not baseline then assert((nearest~=nil)==(c.reaction~='hostile' and allowed),c.source..'/'..c.reaction..'/'..c.fac) end
    if p then
        local wanted=(c.source=='supplement-only' or c.source=='supplement-empty-name') and .5 or (c.source=='personal' or c.source=='imported') and .2 or c.source=='correction' and .9 or .1
        assert(math.abs(p.x-wanted)<1e-9 and math.abs(p.y-wanted)<1e-9,c.source..' lost observed point')
    end
    local record=st.npcs[c.id]
    local line=export:match('\n(N\t'..c.id..'\t[^\n]*)') or ''
    print(table.concat({'CASE',c.source,c.reaction,c.fac,c.id,(DB.IsEnemy(e) and 'enemy' or 'npc')..(showing and ':visible' or ':hidden'),
        p and string.format('%.9f,%.9f',p.x,p.y) or '',dump(record),dump(st.fixes['N'..c.id]),line},'\t'))
end
if mode=='observe' then
    local f=assert(io.open(state,'w')); f:write('return ',dump(WaypointTrackerDB)); f:close()
end
assert(#M.errors==0,table.concat(M.errors,'\n'))
