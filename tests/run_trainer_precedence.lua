-- Synthetic evidence matrix: every trainer source, access shape and hostility.
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN')
local DB, Learn = ns.DB, ns.Learn
assert(DB.Load())
ns.Set('realRoutes', false)
local passed, failed = 0, 0
local function check(ok, text)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. text) end
end
local side = 'Alliance'
UnitFactionGroup = function(unit) if unit == 'player' then return side end end
local function empty() return { npcs = {}, objects = {}, items = {}, quests = {}, mailboxes = {}, fixes = {} } end
local function candidate(id, service)
    for _, e in ipairs(DB.TrainerEntries(service or 'trainer_weapon')) do if e.id == id then return e end end
end
local function has(fac, letter) return fac:find(letter, 1, true) ~= nil end
local id = 992000
local cont, wx, wy = ns.Geo.MapToWorld(37, .5, .5)
for _, source in ipairs({'packaged', 'curated', 'community', 'learned', 'removed', 'fallback'}) do
    for _, rosterFac in ipairs({'', 'A', 'H', 'AH'}) do
        for _, observedFac in ipairs({'', 'A', 'H', 'AH'}) do
            for _, hostility in ipairs({'unknown', 'friendly', 'hostile'}) do
                id = id + 1
                DB.curated, DB.community = empty(), empty()
                WaypointTrackerDB.learned = empty()
                local st = Learn.Store()
                WaypointTrackerData.trainers = 'trainer_weapon\t' .. id .. ':' .. rosterFac
                WaypointTrackerData.trainerLocations = id .. '\tFallback\t37:0.5,0.5;37:0.8,0.8'
                local hostile = hostility == 'hostile' and true or (hostility == 'friendly' and false or nil)
                -- Lua's and/or idiom cannot preserve false.
                if hostility == 'friendly' then hostile = false end
                local row = {name='Evidence', fac=observedFac ~= '' and observedFac or nil,
                    hostile=hostile, services={trainer_weapon=true}, spots={[37]={.5,.5}}}
                if source == 'packaged' then
                    DB.units[id] = {kind='npc', id=id, name='Packaged', fac=observedFac, hostile=hostile,
                        world={{cont,37,wx,wy}}}
                elseif source == 'curated' then DB.curated.npcs[id] = row
                elseif source == 'community' then DB.community.npcs[id] = row
                elseif source == 'learned' then st.npcs[id] = row
                else
                    -- Explicit hostility/faction without a database location.
                    DB.units[id] = {kind='npc', id=id, name='Unlocated', fac=observedFac, hostile=hostile}
                end
                if source == 'removed' then st.fixes['N'..id] = {{wrong={37,.5,.5}}} end
                DB.MergeLearned()
                for _, faction in ipairs({'Alliance','Horde'}) do
                    side = faction
                    local letter = faction:sub(1,1)
                    local overlay = source == 'curated' or source == 'community' or source == 'learned'
                    local expected = hostility ~= 'hostile' and (has(rosterFac,letter) or (overlay and has(observedFac,letter)))
                    local e = candidate(id)
                    local label = table.concat({source,rosterFac,observedFac,hostility,faction}, '/')
                    check((e ~= nil) == expected, label .. ' availability')
                    if e then
                        local points = DB.Points(e)
                        check(#points == ((source == 'fallback' or source == 'removed') and (source == 'removed' and 1 or 2) or 1), label .. ' points')
                        if source == 'removed' then check(points[1].x == .8, label .. ' rejected fallback stays removed') end
                    end
                end
                DB.units[id] = nil
            end
        end
    end
end
-- Corrections for roster-only IDs, from each overlay, including replacement
-- and removal of every point. No raw/observed unit is required.
for _, source in ipairs({'curated','community','learned'}) do
    for _, replacement in ipairs({false,true}) do
        id = id + 1
        DB.curated, DB.community = empty(), empty(); WaypointTrackerDB.learned = empty()
        local st = Learn.Store()
        local target = source == 'learned' and st or DB[source]
        target.fixes['N'..id] = {{wrong={37,.5,.5}, right=replacement and {37,.9,.9} or nil}}
        WaypointTrackerData.trainers = 'trainer_weapon\t'..id..':AH'
        WaypointTrackerData.trainerLocations = id..'\tFallback\t37:0.5,0.5'
        DB.MergeLearned(); side = 'Alliance'
        local e = candidate(id)
        check((e ~= nil) == replacement, source .. ' correction without a database identity')
        if e then check(DB.Points(e)[1].x == .9, source .. ' correction replacement wins') end
    end
end
-- Layered precedence: curated replaces raw positions on its map; community
-- and personal points supplement them; the live hostility flag wins last.
for _, lowerHostile in ipairs({false,true}) do
    for _, liveHostile in ipairs({false,true}) do
        for _, correctionSource in ipairs({'none','curated','community','learned'}) do
            id=id+1; DB.curated,DB.community=empty(),empty(); WaypointTrackerDB.learned=empty()
            local st=Learn.Store()
            DB.units[id]={kind='npc',id=id,name='Packaged',fac='AH',hostile=lowerHostile,world={{cont,37,wx,wy}}}
            -- Use coords for a true raw position, with a controlled area lookup.
            DB.units[id].world=nil; DB.units[id].coords='12:500,500'
            local mapForArea=DB.MapForArea; DB.MapForArea=function(area) if area==12 then return 37 end return mapForArea(area) end
            DB.curated.npcs[id]={name='Curated',hostile=lowerHostile,spots={[37]={.6,.6}}}
            DB.community.npcs[id]={name='Community',hostile=lowerHostile,spots={[37]={.7,.7}}}
            st.npcs[id]={name='Live',hostile=liveHostile,fac='AH',spots={[37]={.8,.8}}}
            if correctionSource~='none' then
                local target=correctionSource=='learned' and st or DB[correctionSource]
                target.fixes['N'..id]={{wrong={37,.6,.6}}}
            end
            WaypointTrackerData.trainers='trainer_weapon\t'..id..':AH'
            WaypointTrackerData.trainerLocations=id..'\tFallback\t37:0.9,0.9'
            for cycle=1,3 do
                DB.MergeLearned(); side='Alliance'
                local e=candidate(id)
                check((e~=nil)==(not liveHostile),'layered hostility '..tostring(lowerHostile)..'/'..tostring(liveHostile)..' cycle '..cycle)
                if e then
                    check(e.name=='Live','live name wins every layer')
                    local spots={};for _,p in ipairs(DB.Points(e)) do spots[p.x]=true end
                    check(not spots[.5] and not spots[.9] and spots[.7] and spots[.8]
                        and (spots[.6] == (correctionSource=='none' and true or nil)), 'layered position/correction precedence')
                end
            end
            DB.MapForArea=mapForArea
        end
    end
end
-- An explicit hostile observation must survive compaction even if an empty
-- raw faction made general Find infer an enemy before the roster was consulted.
id=id+1; DB.curated,DB.community=empty(),empty(); WaypointTrackerDB.learned=empty()
local hostileStore=Learn.Store()
local mapForArea=DB.MapForArea
DB.MapForArea=function(area) if area==12 then return 37 end return mapForArea(area) end
DB.units[id]={kind='npc',id=id,name='Teacher',fac='',coords='12:500,500'}
WaypointTrackerData.trainers='trainer_weapon\t'..id..':AH'
hostileStore.npcs[id]={name='Teacher',hostile=true,spots={[37]={.5,.5}}}
DB.MergeLearned()
check(hostileStore.npcs[id] and hostileStore.npcs[id].hostile,'explicit hostile evidence survives compaction against inferred enemy')
-- Fresh session: reconstruct raw entry, retaining only compacted SavedVariables.
DB.units[id]={kind='npc',id=id,name='Teacher',fac='',coords='12:500,500'}
DB.MergeLearned(); check(not candidate(id),'hostile observation still excludes roster after reconstruction')
DB.MapForArea=mapForArea
-- Typed-only imported and SavedVariables shapes survive ordinary sightings,
-- trainer visits, compaction, export/import and a repaired store reload.
local families = {'trainer', 'trainer_class_mage','trainer_profession_alchemy','trainer_weapon','trainer_riding'}
for _, service in ipairs(families) do
    for _, shape in ipairs({'import','saved'}) do
        id = id + 1; DB.curated, DB.community = empty(), empty(); WaypointTrackerDB.learned = empty()
        local st = Learn.Store()
        if shape == 'import' then
            Learn.Import('WTL1\tenUS\t1\nN\t'..id..'\tTeacher\t0\t60\t'..service..'\t37:500,500\tAH')
        else st.npcs[id] = {name='Teacher',fac='AH',services={[service]=true},spots={[37]={.5,.5}}} end
        M.units.npc = {guid='Creature-0-1-2-3-'..id..'-ABC',name='Teacher',reaction=5,level=60}
        local uf = UnitFactionGroup
        UnitFactionGroup = function(unit) return unit == 'player' and side or 'Alliance' end
        Learn.Unit('npc'); check(st.npcs[id].fac == 'AH', service..' '..shape..' ordinary observation')
        Learn.Unit('npc','trainer'); check(st.npcs[id].fac == 'AH', service..' trainer visit')
        DB.MergeLearned(); Learn.Compact(true)
        check(st.npcs[id] and st.npcs[id].fac == 'AH', service..' compaction')
        local reloaded = empty(); Learn.Import(Learn.Export(),reloaded,true)
        check(reloaded.npcs[id] and reloaded.npcs[id].fac == 'AH', service..' export/import')
        WaypointTrackerDB.learned = reloaded
        check(Learn.Store().npcs[id].fac == 'AH', service..' repaired reload')
        UnitFactionGroup = uf
    end
end
check(#M.errors == 0, 'no captured Lua errors')
print(('Trainer precedence: %d passed, %d failed'):format(passed,failed))
os.exit(failed == 0 and 0 or 1)
