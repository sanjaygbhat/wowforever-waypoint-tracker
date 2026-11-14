local mode,state=arg[1],assert(arg[2])
if mode=='reload' then WaypointTrackerDB=assert(loadfile(state))() end
local side=os.getenv('WT_FACTION') or 'Alliance'
UnitFactionGroup=function() return side end
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN')
local DB,Learn=ns.DB,ns.Learn
assert(DB.Load())
local cases={{2481,1431,.18,.544,'vendor'},
    {258878,1413,.4992,.2946,'auctioneer'},{265574,1413,.6255,.3757,'vendor'}}
if side=='Alliance' then cases[#cases+1]={4164,1457,.568,.536,'vendor'}
else
    for _,r in ipairs({{3333,1454,.666,.416,'vendor'},{3322,1454,.408,.496,'repair'},
        {3330,1454,.46,.578,'repair'},{3361,1454,.76,.378,'repair'}}) do cases[#cases+1]=r end
    local p=DB.Points(DB.units[3095])[1]
    cases[#cases+1]={3095,p.m,p.x,p.y,'repair'}
end
local st=Learn.Store()
for _,r in ipairs(cases) do
    local id,m,x,y,service=unpack(r)
    if mode=='observe' then
        st.npcs[id]={name=DB.units[id].name,hostile=false,fac=side:sub(1,1),services={[service]=true},spots={[m]={x,y}}}
    elseif mode=='import' then
        local text=('WTL1\tenUS\t1\nN\t%d\t%s\t0\t\t%s\t%d:%d,%d\t%s'):format(id,DB.units[id].name,service,m,math.floor(x*1000+.5),math.floor(y*1000+.5),side:sub(1,1))
        assert(Learn.Import(text))
    end
end
DB.MergeLearned();Learn.Compact(true)
for _,r in ipairs(cases) do
    local id,m,x,y,service=unpack(r)
    assert(st.npcs[id],id..' lost saved observation')
    assert(not DB.IsEnemy(DB.units[id]),id..' became Enemy')
    local entry
    for _,e in ipairs(DB.ServiceEntries(service)) do if e.id==id then entry=e end end
    assert(entry,id..' absent from Nearest')
    local found=false
    for _,p in ipairs(DB.Points(entry)) do
        if p.m==m and math.abs(p.x-x)<.001 and math.abs(p.y-y)<.001 then found=true end
    end
    assert(found,id..' lost effective point')
    M.player.inst,M.player.wx,M.player.wy=ns.Geo.MapToWorld(m,x,y);M.now=M.now+1
    local e,p,d=DB.NearestOf(DB.ServiceEntries(service),{faction=true})
    assert(e and e.id==id and d<8,id..' no longer local nearest')
    if mode~='import' then assert(Learn.Export():find('\nN\t'..id..'\t',1,true),id..' missing export') end
    print(id,'saved friendly nearest at observation')
end
if mode=='observe' then
    local function dump(v)
        if type(v)=='table' then
            local out={};for k,x in pairs(v) do out[#out+1]='['..dump(k)..']='..dump(x) end
            return '{'..table.concat(out,',')..'}'
        end
        return type(v)=='string' and string.format('%q',v) or tostring(v)
    end
    local f=assert(io.open(state,'w'));f:write('return ',dump(WaypointTrackerDB));f:close()
end
assert(#M.errors==0,table.concat(M.errors,'\n'))
