-- Fresh-VM coverage of passive trainer sightings (never open a trainer window).
local mode,state,source,path=arg[1],assert(arg[2]),arg[3],arg[4]
if mode=='reload' then WaypointTrackerDB=assert(loadfile(state))() end
local side=os.getenv('WT_FACTION') or 'Alliance'
local uf=UnitFactionGroup
UnitFactionGroup=function(u)if not u or u=='player' then return side end return uf(u)end
local ns=M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker');M.FireEvent('PLAYER_LOGIN');assert(ns.DB.Load())
local DB,Learn=ns.DB,ns.Learn
local cases=side=='Horde' and {{3355,1454,.764,.344,'trainer_profession_blacksmithing'},
    {3347,1454,.556,.466,'trainer_profession_alchemy'}} or {{5484,1453,.523,.476,'trainer_class_priest'}}
for _,r in ipairs(cases) do
    local id,m,x,y,service=unpack(r)
    M.player.inst,M.player.wx,M.player.wy=ns.Geo.MapToWorld(m,x,y);M.now=M.now+1
    if mode~='reload' then
        if source=='import' then
            assert(Learn.Import(('WTL1\tenUS\t1\nN\t%d\t%s\t0\t40\t\t%d:%d,%d\t%s'):format(
                id,DB.units[id].name,m,x*1000,y*1000,side:sub(1,1)))==1)
        else
            M.units.target={guid='Creature-0-1-2-3-'..id..'-ABC',name=DB.units[id].name,
                reaction=5,level=40,faction=side,dist=1}
            local best=C_Map.GetBestMapForUnit;C_Map.GetBestMapForUnit=function()return m end
            Learn.Sight('target');C_Map.GetBestMapForUnit=best
        end
    end
    local row=assert(Learn.Store().npcs[id],id..' observation missing')
    assert(not next(row.services or {}),'test must be passive, without typed service flags')
    if path=='ticker' then M.Tick(5.1,5.1);assert(DB.Load()) else DB.MergeLearned() end
    assert(Learn.Store().npcs[id],id..' compacted')
    local e,p,d=DB.NearestOf(DB.TrainerEntries(service),{faction=true})
    assert(e and e.id==id and d<1e-6,id..' trainer moved away from observation')
    local text=Learn.Export()
    assert((text:find('\nN\t'..id..'\t',1,true)~=nil)==(source~='import'),'share ownership/position lost')
end
if mode~='reload' then
    local function dump(v)
        if type(v)=='table' then local t={}for k,x in pairs(v)do t[#t+1]='['..dump(k)..']='..dump(x)end return '{'..table.concat(t,',')..'}'end
        return type(v)=='string' and string.format('%q',v) or tostring(v)
    end
    local f=assert(io.open(state,'w'));f:write('return ',dump(WaypointTrackerDB));f:close()
end
assert(#M.errors==0,table.concat(M.errors,'\n'))
print('Passive trainers: '..side..' '..source..' '..path..'; saved, zero yards, correct sharing')
