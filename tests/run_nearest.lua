-- Regression: Nearest mailbox / innkeeper / flight master / repair / bank /
-- auction house / merchant / stable master / spirit healer / battlemaster /
-- meeting stone. 1.1.1 had one-click buttons; 1.2.0 hid them in a dropdown
-- and players lost the feature. This drives the real entry points
-- (the visible Find buttons and the quick menu) against the shipped database,
-- for both factions, for every service.
-- Run from repo root: lua5.1 tests/run_nearest.lua
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
-- Core caches this predicate: install it before any addon module is loaded.
local secret = {}
local originalSecret = issecretvalue
issecretvalue = function(v) return rawequal(v, secret) or originalSecret(v) end
local bare = arg[1] == "--bare"
if bare then
    MenuUtil = nil
    local create = CreateFrame
    CreateFrame = function(kind, name, parent, template)
        if template == 'WowStyle1DropdownTemplate' then error('optional dropdown unavailable') end
        return create(kind, name, parent, template)
    end
end
-- Additional synthetic map rectangles let the mock exercise both factions'
-- real roster IDs; these are test geometry, never shipped NPC positions.
local areaInfo = C_Map.GetAreaInfo
local areas = { [1537] = 1455, [1657] = 1457, [1637] = 1454, [1638] = 1456, [1497] = 1458 }
for area, map in pairs(areas) do
    M.maps[map] = { mapID = map, name = 'Trainer Test Map ' .. map, mapType = 3,
        parentMapID = (map == 1455 or map == 1458) and 13 or 12,
        cont = (map == 1455 or map == 1458) and 0 or 1,
        top = 2000, left = -3500, w = 2000, h = 2000 }
end
M.maps[1424] = { mapID = 1424, name = 'Trainer Test Hillsbrad', mapType = 3, parentMapID = 13,
    cont = 0, top = 2000, left = -3500, w = 2000, h = 2000 }
M.maps[1420] = { mapID = 1420, name = 'Trainer Test Tirisfal', mapType = 3, parentMapID = 13,
    cont = 0, top = 2000, left = -3500, w = 2000, h = 2000 }
C_Map.GetAreaInfo = function(area)
    return areas[area] and M.maps[areas[area]].name or areaInfo(area)
end
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. message) end
end

local faction = 'Alliance'
local unitFaction = UnitFactionGroup
UnitFactionGroup = function(unit)
    if unit == nil or unit == 'player' then return faction end
    return unitFaction(unit)
end

WaypointTrackerDB = nil
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN'); M.FireEvent('PLAYER_ENTERING_WORLD')
M.Tick(0.1)
local Find, Window, DB, WP, L = ns.Find, ns.Window, ns.DB, ns.WP, ns.L
M.player.wx, M.player.wy, M.player.inst = -9460, 62, 0 -- Goldshire
M.noDataAddon = false

local SERVICES = {
    { 'mailbox', 'SERVICE_MAILBOX' }, { 'innkeeper', 'SERVICE_INNKEEPER' }, { 'flight', 'SERVICE_FLIGHT' },
    { 'repair', 'SERVICE_REPAIR' }, { 'vendor', 'SERVICE_VENDOR' }, { 'banker', 'SERVICE_BANKER' },
    { 'auctioneer', 'SERVICE_AUCTIONEER' }, { 'stablemaster', 'SERVICE_STABLEMASTER' },
    { 'spirithealer', 'SERVICE_SPIRITHEALER' }, { 'battlemaster', 'SERVICE_BATTLEMASTER' },
    { 'meetingstone', 'SERVICE_MEETINGSTONE' },
}
check(Find.SERVICES and #Find.SERVICES == #SERVICES + 4, 'Find offers all ' .. (#SERVICES + 4) .. ' Nearest services (got ' .. tostring(Find.SERVICES and #Find.SERVICES) .. ')')

-- Building a hidden-window quick menu must remain lazy; only entering the
-- profession submenu may load its availability data.
if not bare then
    local load, entries, calls = DB.Load, DB.TrainerEntries, 0
    DB.Load = function(...) calls = calls + 1; return load(...) end
    DB.TrainerEntries = function(...) calls = calls + 1; return entries(...) end
    ns.QuickMenu.Show(UIParent)
    check(calls == 0 and not DB.loaded, 'quick-menu construction never loads or queries trainer data')
    local near
    for _, item in ipairs(M.lastMenu.items) do if item.text == L.NEAREST_MENU then near = item end end
    check(near and near.items[13] and #near.items[13].items == 1, 'unopened profession submenu has only its title')
    DB.Load, DB.TrainerEntries = load, entries
end

-- First-use menu feedback, before a main frame exists.
if not bare then
    local classAPI, printed = UnitClass, #M.printed
    UnitClass = nil
    M.player.combat = true
    ns.QuickMenu.Show(UIParent)
    for _, item in ipairs(M.lastMenu.items) do
        if item.text == L.NEAREST_MENU then item.items[12].fn() end
    end
    check(not Window.frame and #M.printed == printed + 1 and M.printed[#M.printed]:find(L.TRAINER_CLASS_UNKNOWN, 1, true), 'first quick-menu error has combat-safe visible feedback')
    UnitClass, M.player.combat = classAPI, false
end

-- 1. The buttons are on screen in the Find tab, one per service, in a row.
Find.Show()
M.Tick(0.3)
local fw = Find.widgets
check(Window.IsShown() and Window.GetTab() == 'find', 'Find tab is open')
local rowRight = {}
for i, service in ipairs(Find.SERVICES) do
    local b = fw.nearest[service.key]
    check(b ~= nil, 'Nearest button exists: ' .. service.key)
    if b then
        check(b:IsShown() and b:IsVisible(), 'Nearest button is visible: ' .. service.key)
        local text = b.GetText and b:GetText() or b.text:GetText()
        check(text == (bare and service.key == 'profession' and L.PROFESSION_ALCHEMY or L[service.label]), 'Nearest button is labelled ' .. L[service.label])
        check(fw.nearest[i] == b, 'Nearest buttons retain service order: ' .. service.key)
        local _, rel, _, x, y = b:GetPoint()
        local font = (b.GetFontString and b:GetFontString()) or b.text
        check(rel == fw.nearestGrid, 'button anchors in the Nearest grid: ' .. service.key)
        check(b:GetWidth() >= font:GetStringWidth() + 12, 'full label fits: ' .. service.key)
        check(x >= 0 and x + b:GetWidth() <= fw.nearestGrid:GetWidth(), 'button fits grid width: ' .. service.key)
        check(not rowRight[y] or x >= rowRight[y] + 4, 'buttons do not overlap: ' .. service.key)
        rowRight[y] = x + b:GetWidth()
        check(-y + b:GetHeight() <= fw.nearestGrid:GetHeight() + 2, 'button fits grid height: ' .. service.key)
    end
end
-- wowmock keeps only the last SetPoint; verify the first anchor with a wrapper
-- in run_tab_find too. In-game the top follows the grid and bottom is fixed.
check(fw.nearestGrid:GetHeight() >= 22 and fw.nearestGrid:GetHeight() < 300, 'grid leaves space for results at minimum window size')
check(fw.detail:GetPoint() == 'BOTTOMRIGHT', 'detail pane retains bottom control clearance')

-- 2. Each button sets the arrow on the nearest entry of that service.
local function OfService(key, wp)
    for _, e in ipairs(DB.ServiceEntries(key)) do
        if wp.title and (wp.title == e.name or wp.title:find(e.name, 1, true)) then return true end
    end
end
local function RunAll(label)
    for _, s in ipairs(SERVICES) do
        WP.ClearAll(true)
        Window.SetStatus('')
        local chat = #M.printed
        fw.nearest[s[1]]:Click()
        check(#M.printed == chat, 'UI Nearest click stays quiet: ' .. s[1])
        local wp = WP.GetActive()
        check(wp ~= nil, label .. ': Nearest ' .. s[1] .. ' sets the arrow')
        if wp then
            check(OfService(s[1], wp), label .. ': Nearest ' .. s[1] .. ' points at a ' .. s[1] .. ' (got ' .. tostring(wp.title) .. ')')
            check(Window.frame.status:GetText() == L.ADDED:format(WP.Describe(wp)), label .. ': Nearest ' .. s[1] .. ' reports the waypoint below the title')
        end
    end
end
RunAll('Alliance')

-- 3. Horde gets Horde services, never Alliance-only ones. (The mock models
-- only a few zones, so distances in Orgrimmar are not measured here; what
-- matters is that every list and every pick is open to the Horde.)
faction = 'Horde'
M.player.wx, M.player.wy, M.player.inst = 1630, -4373, 1 -- Orgrimmar
local function HordeAllowed(key, e)
    -- Precise mined candidates have their own explicit, evidence-gated access;
    -- they need not have a corresponding Classic roster entry.
    if e.minedService then
        return e.learned == 'community' and (e.fac == 'H' or e.fac == 'AH')
    end
    for _, row in ipairs(DB.services[key] or {}) do
        local same = row.entry == e
        if not same and type(row.id) == 'number' then
            same = (row.id < 0 and DB.objects[-row.id] == e) or (row.id >= 0 and DB.units[row.id] == e)
        end
        if same and (row.fac == '' or row.fac:find('H', 1, true)) then return true end
    end
    return false
end
for _, s in ipairs(SERVICES) do
    local list = DB.ServiceEntries(s[1])
    check(#list > 0, 'Horde has ' .. s[1] .. ' entries')
    local bad
    for _, e in ipairs(list) do if not HordeAllowed(s[1], e) then bad = e; break end end
    check(not bad, 'Horde ' .. s[1] .. ' list holds only Horde or neutral entries' .. (bad and (' (got ' .. tostring(bad.name) .. ')') or ''))
    WP.ClearAll(true)
    fw.nearest[s[1]]:Click()
    local wp = WP.GetActive()
    if wp then check(OfService(s[1], wp), 'Horde: Nearest ' .. s[1] .. ' points at a ' .. s[1]) end
end
faction = 'Alliance'
M.player.wx, M.player.wy, M.player.inst = -9460, 62, 0

-- 4. The quick menu (minimap right-click) has Nearest with all six.
Window.Hide()
ns.QuickMenu.Show(UIParent)
local root = M.lastMenu or ns.Widgets.lastMenu
local nearItem
for _, item in ipairs(root and root.items or {}) do
    if item.text == L.NEAREST_MENU then nearItem = item end
end
check(nearItem ~= nil, 'quick menu has Nearest...')
local children = nearItem and nearItem.items or {}
check(bare or #children == #SERVICES + 4, 'quick menu Nearest lists every service (got ' .. #children .. ')')
for i, s in ipairs(bare and {} or SERVICES) do
    local child = children[i]
    check(child and child.text == L[s[2]], 'quick menu Nearest item ' .. i .. ' is ' .. L[s[2]])
    if child then
        WP.ClearAll(true)
        child.fn()
        local wp = WP.GetActive()
        check(wp and OfService(s[1], wp), 'quick menu Nearest ' .. s[1] .. ' sets the arrow')
    end
end

-- 5. Where the menu cannot show submenus, the entry opens Find instead.
Window.Hide()
if nearItem and nearItem.fn then nearItem.fn() else Find.Show() end
check(Window.IsShown() and Window.GetTab() == 'find', 'quick menu Nearest opens Find when used directly')

-- 6. Without the database the buttons explain instead of failing silently.
WP.ClearAll(true)
local load = DB.Load
DB.Load = function() return false, 'missing' end
fw.nearest.mailbox:Click()
DB.Load = load
check(WP.GetActive() == nil and Window.frame.status:GetText() == L.DB_BROKEN, 'missing database is explained below the title')

-- Trainer entry points and faction restrictions.
local savedClass = UnitClass
for _, side in ipairs({ 'Alliance', 'Horde' }) do
    faction = side
    M.player.wx, M.player.wy, M.player.inst = -600, -700, 0
    for class in pairs(ns.Trainers.classes) do
        UnitClass = function() return class, class:upper() end
        WP.ClearAll(true)
        fw.nearest.class:Click()
        local entries = DB.TrainerEntries('trainer_class_' .. class)
        local wp = WP.GetActive()
        local _, _, measuredDistance = DB.NearestOf(entries)
        check((#entries > 0 and wp ~= nil) or (wp == nil and ((#entries == 0 and Window.frame.status:GetText() == L.TRAINER_NONE) or (#entries > 0 and not measuredDistance and Window.frame.status:GetText() == L.TRAINER_POSITION_UNKNOWN))), side .. ': class button handles ' .. class)
        for _, e in ipairs(entries) do
            check(#DB.Points(e) > 0, 'class trainer has a known point: ' .. e.id)
        end
        if wp then check((wp.title == L.SERVICE_CLASS_TRAINER or wp.title:find(L.SERVICE_CLASS_TRAINER .. ' - ', 1, true) == 1) and wp.source == 'find', 'class waypoint uses the normal Find path with service and available NPC title') end
    end
    for _, key in ipairs({ 'trainer_weapon', 'trainer_riding' }) do
        WP.ClearAll(true)
        fw.nearest[key]:Click()
        check(WP.GetActive() ~= nil, side .. ': ' .. key .. ' button sets arrow')
    end
    if not bare then
        fw.nearest.profession:Click()
        local menu, count = M.lastMenu, 0
        for _, item in ipairs(menu.items) do
            if item.kind == 'button' then
                count = count + 1
                if item.enabled then
                    WP.ClearAll(true)
                    item.fn()
                    check(WP.GetActive() and Window.frame.status:GetText():find(L.TRAINER_KNOWN_ADDED:match('%%s(.*)'), 1, true), side .. ': profession selection reports partial data')
                else check(item.fn == nil and item.text:find(L.TRAINER_UNAVAILABLE, 1, true), 'unavailable profession is disabled with reason') end
            end
        end
        check(count == 12, side .. ': profession menu lists twelve choices')
    else
        check(fw.nearest.profession.next ~= nil, 'missing menus use the shared profession picker')
        fw.nearest.profession.next:Click()
    end
end
if not bare then
    local keys = { class = 12, profession = 13, trainer_weapon = 14, trainer_riding = 15 }
    for key, index in pairs(keys) do
        check(children[index] and children[index].text == L[Find.SERVICES[index].label], 'quick menu trainer entry: ' .. key)
    end
    if children[13] and children[13].onEnter then
        children[13].onEnter()
        children[13].onEnter() -- repeated hover must not duplicate choices
    end
    check(children[13] and #children[13].items == 13, 'quick menu profession choices are nested')
    -- A partially featured menu can have the first submenu but no second level.
    local opened = 0
    local show = Find.Show
    Find.Show = function() opened = opened + 1 end
    local flat = { CreateTitle = function() end, CreateDivider = function() end, CreateCheckbox = function() end }
    function flat:CreateButton(text, fn)
        if text == L.NEAREST_MENU then
            return { CreateButton = function(_, label, action)
                if label == L.SERVICE_PROFESSION_TRAINER then action() end
            end }
        end
    end
    ns.QuickMenu.Build(flat)
    Find.Show = show
    check(opened == 1, 'menu without nested profession choices opens Find')
end
if not bare then
    local entries = DB.TrainerEntries
    DB.TrainerEntries = function(key) if key == 'trainer_profession_fishing' then return {} end; return entries(key) end
    fw.nearest.profession:Click()
    local fishing = M.lastMenu.items[13]
    check(fishing and fishing.enabled == false and fishing.fn == nil and fishing.text:find(L.TRAINER_UNAVAILABLE, 1, true), 'missing profession is visibly disabled with a reason')
    DB.TrainerEntries = entries
end
UnitClass = savedClass

-- Unknown fixture factions never become candidates, even with faction filter off.
ns.Set('findFaction', false)
local forbidden = {}
for line in io.lines('tools/fixtures/trainers/trainers.tsv') do
    local id, fac = line:match('^(%d+)\t[^\t]*\t[^\t]*\t[^\t]*\t([^\t]*)\t')
    if id and fac == '' then forbidden[tonumber(id)] = true end
end
for _, side in ipairs({ 'Alliance', 'Horde' }) do
    faction = side
    for key in pairs(ns.Trainers.services) do
        for _, e in ipairs(DB.TrainerEntries(key)) do
            check(not forbidden[e.id], side .. ': unknown-faction trainer excluded: ' .. e.id)
            local allowed
            for line in WaypointTrackerData.trainers:gmatch('[^\n]+') do
                if line:match('^([^\t]+)') == key then
                    local fac = line:match('%f[%d]' .. e.id .. ':([AH]+)')
                    allowed = fac and fac:find(side:sub(1, 1), 1, true)
                end
            end
            check(allowed, side .. ': roster trainer faction is allowed: ' .. e.id)
        end
    end
end
faction = 'Horde'
local paladins = DB.TrainerEntries('trainer_class_paladin')
local supplemental
for _, e in ipairs(paladins) do if e.id == 246152 then supplemental = e end end
check(supplemental ~= nil and #DB.Points(supplemental) > 0, 'Forever positions work for IDs absent from Data.lua')

local function candidate(service, id)
    for _, e in ipairs(DB.TrainerEntries(service)) do if e.id == id then return e end end
end
local observed = candidate('trainer_class_paladin', 246389)
check(observed ~= nil, 'observed-position Horde paladin is offered')
local op = observed and DB.Points(observed)[1]
check(op and op.m == 1420 and op.x == 0.2189 and op.y == 0.4709, 'missing database position uses exact observed map coordinates')
check(observed and (GetLocale() ~= 'enUS' or observed.name == 'Hilda the Breaker'), 'English fallback name is available')
check(observed and (GetLocale() == 'enUS' or observed.name == ''), 'other locales use the service label without an English fallback name')
local px, py, pi = M.player.wx, M.player.wy, M.player.inst
M.player.wx, M.player.wy, M.player.inst = 2000 - 0.4709 * 2000, -3500 - 0.2189 * 2000, 0
UnitClass = function() return 'Paladin', 'PALADIN' end
WP.ClearAll(true); fw.nearest.class:Click()
local observedWaypoint = WP.GetActive()
check(observedWaypoint and observedWaypoint.m == 1420 and observedWaypoint.x == 0.2189
    and observedWaypoint.y == 0.4709 and observedWaypoint.source == 'find', 'observed-position trainer sets a normal Find waypoint at the exact observed coordinates')
check(observedWaypoint and observedWaypoint.title == (GetLocale() == 'enUS'
    and L.SERVICE_CLASS_TRAINER .. ' - Hilda the Breaker' or L.SERVICE_CLASS_TRAINER), 'waypoint title uses the English fallback only on enUS')
M.player.wx, M.player.wy, M.player.inst, UnitClass = px, py, pi, savedClass
local stored = DB.units[246389]
local learnedStore = ns.Learn.Store()
local savedObservation = learnedStore.npcs[246389]
learnedStore.npcs[246389] = { name = 'Local observation', fac = 'H', spots = { [37] = { 0.4, 0.5 } } }
DB.MergeLearned()
check(candidate('trainer_class_paladin', 246389) == DB.units[246389], 'later learned position and localized name take precedence over fallback')
learnedStore.npcs[246389] = savedObservation
DB.units[246389] = stored
DB.MergeLearned()

-- The expanded roster includes Alliance shamans and neutral trainers.
-- Synthetic identities exercise additional access cases without inventing
-- production data or relying on geography/class guesses.
local savedRoster = WaypointTrackerData.trainers
for id = 990020, 990023 do
    DB.units[id] = { kind = 'npc', id = id, name = 'Access test', points = { { m = 37, x = 0.45, y = 0.55 } } }
end
-- Add to existing service lines: TrainerEntries intentionally stops at the
-- first matching service, as the generator emits each service exactly once.
WaypointTrackerData.trainers = savedRoster:gsub('(trainer_class_shaman\t[^\n]*)', '%1,990020:A')
    :gsub('(trainer_class_paladin\t[^\n]*)', '%1,990021:H')
    :gsub('(trainer_profession_fishing\t[^\n]*)', '%1,990022:AH,990023:')
for _, side in ipairs({ 'Alliance', 'Horde' }) do
    faction = side
    UnitClass = function() return 'Shaman', 'SHAMAN' end
    check((candidate('trainer_class_shaman', 990020) ~= nil) == (side == 'Alliance'), 'Alliance shaman access follows evidence, on ' .. side)
    if side == 'Alliance' then
        WP.ClearAll(true); fw.nearest.class:Click()
        local wp = WP.GetActive()
        check(wp and wp.m == 37 and wp.x == 0.45 and wp.y == 0.55, 'Alliance shaman player finds the evidenced Alliance shaman')
    end
    UnitClass = function() return 'Paladin', 'PALADIN' end
    check((candidate('trainer_class_paladin', 990021) ~= nil) == (side == 'Horde'), 'Horde paladin access follows evidence, on ' .. side)
    if side == 'Horde' then
        WP.ClearAll(true); fw.nearest.class:Click()
        local wp = WP.GetActive()
        check(wp and wp.m == 37 and wp.x == 0.45 and wp.y == 0.55, 'Horde paladin player finds the evidenced Horde paladin')
    end
    check(candidate('trainer_profession_fishing', 990022) ~= nil, 'AH trainer is offered to ' .. side)
    check(not candidate('trainer_profession_fishing', 990023), 'unknown trainer is never offered to ' .. side)
end
WaypointTrackerData.trainers, UnitClass = savedRoster, savedClass
for id = 990020, 990023 do DB.units[id] = nil end
faction = 'Horde'

-- Located and unlocated typed discoveries; unknown names stay ignored.
local Learn = ns.Learn
local function import(row)
    return Learn.Import('WTL1\tenUS\t1\n' .. row .. '\n')
end
import('N\t990001\tNo Position\t0\t60\ttrainer_class_mage\t\tH')
import('N\t990002\tNearby Class Teacher\t0\t60\ttrainer_class_mage,trainer_profession_unknown,evil\t37:450,550\tH')
M.player.wx, M.player.wy, M.player.inst = -1100, -1350, 0
DB.Load()
local found, unlocated
for _, e in ipairs(DB.TrainerEntries('trainer_class_mage')) do
    if e.id == 990002 then found = true end
    if e.id == 990001 then unlocated = true end
end
check(found and not unlocated, 'typed learned class candidates need actual positions')
check(not Learn.Store().npcs[990002].services.evil and not Learn.Store().npcs[990002].services.trainer_profession_unknown, 'import ignores unknown typed services')

-- Learn professions from open-trainer evidence, never localized NPC titles.
local savedTrainer, savedTrade = C_Trainer, C_TradeSkillUI
local savedCount, savedLine, savedIs = GetNumTrainerServices, GetTrainerServiceSkillLine, IsTradeskillTrainer
Enum.TrainerType = { General = 0, Tradeskills = 2, Pet = 3 }
local trainerType, lineNames = 2, { 'GameAlchemy', 'GameAlchemy' }
C_Trainer = { GetTrainerType = function() return trainerType end }
C_TradeSkillUI = { GetTradeSkillDisplayName = function(id) return 'Game' .. id end }
C_TradeSkillUI.GetTradeSkillDisplayName = function(id) return id == 171 and 'GameAlchemy' or ('Game' .. id) end
GetNumTrainerServices = function() return #lineNames end
GetTrainerServiceSkillLine = function(i) return lineNames[i] end
local id = 991000
local function visit()
    id = id + 1
    M.units.npc = { guid = 'Creature-0-1-2-3-' .. id .. '-00000ABC', name = 'Visited ' .. id, reaction = 5, level = 60 }
    M.FireEvent('TRAINER_SHOW')
    return Learn.Store().npcs[id]
end
local e = visit()
check(e.services.trainer and e.services.trainer_profession_alchemy and e.fac == 'H', 'visited profession trainer is typed with observed faction access')
DB.Load()
local list = DB.TrainerEntries('trainer_profession_alchemy')
local learned
for _, v in ipairs(list) do if v.id == id then learned = v end end
check(learned ~= nil, 'a visited profession trainer becomes a candidate')
local nearest = DB.NearestOf(list)
check(nearest and nearest.id == id, 'the visited nearby profession trainer becomes nearest')
for _, names in ipairs({ {'GameAlchemy', 'Game164'}, { 'Unknown' } }) do
    lineNames = names
    local ambiguous = visit()
    check(ambiguous.services.trainer and not ambiguous.services.trainer_profession_alchemy, 'ambiguous/unrecognized skill lines stay generic')
end
lineNames = { 'GameAlchemy' }
for _, kind in ipairs({ 0, 1, 3 }) do
    trainerType = kind
    local generic = visit()
    check(generic.services.trainer and not generic.services.trainer_class_mage and not generic.services.trainer_profession_alchemy, 'non-tradeskill/weapon/riding/pet/demon/portal type stays generic')
end
trainerType = 2
C_TradeSkillUI.GetTradeSkillDisplayName = function() return 'GameAlchemy' end
check(not visit().services.trainer_profession_alchemy, 'duplicate game-localized names stay generic')
C_TradeSkillUI.GetTradeSkillDisplayName = function(id) return id == 171 and 'GameAlchemy' or ('Game' .. id) end
for _, side in ipairs({ 'Alliance', 'Horde' }) do
    faction = side
    for _, p in ipairs(ns.Trainers.professions) do
        lineNames = { p.id == 171 and 'GameAlchemy' or ('Game' .. p.id) }
        local observed = visit()
        check(observed.services['trainer_profession_' .. p.key] and observed.fac == side:sub(1, 1), side .. ': exact game name learns ' .. p.key)
        DB.Load()
        local found
        for _, candidate in ipairs(DB.TrainerEntries('trainer_profession_' .. p.key)) do if candidate.id == id then found = true end end
        check(found, side .. ': visited ' .. p.key .. ' becomes a candidate')
    end
end
faction, lineNames = 'Horde', { 'GameAlchemy' }
C_Trainer = nil
IsTradeskillTrainer = function() return true end
check(visit().services.trainer_profession_alchemy, 'guarded legacy tradeskill API classifies exact names')
IsTradeskillTrainer = function() return false end
check(not visit().services.trainer_profession_alchemy, 'false legacy tradeskill signal stays generic')
IsTradeskillTrainer, C_TradeSkillUI = nil, nil
check(not visit().services.trainer_profession_alchemy, 'missing trainer APIs stay generic')

-- Secret/invalid API returns are rejected before indexing/comparison/formatting.
local oldSecret = issecretvalue
check(ns.Plain(secret) == nil, "Core cached predicate recognizes our secret sentinel")
for _, result in ipairs({ secret, false, 42, 'UNKNOWN' }) do
    UnitClass = function() return secret, result end
    WP.ClearAll(true)
    fw.nearest.class:Click()
    check(not WP.GetActive() and Window.frame.status:GetText() == L.TRAINER_CLASS_UNKNOWN, 'invalid/secret class gets a clear status')
end
UnitClass = nil
WP.ClearAll(true)
fw.nearest.class:Click()
check(not WP.GetActive() and Window.frame.status:GetText() == L.TRAINER_CLASS_UNKNOWN, 'missing class API gets a clear status')
UnitClass = function() return secret, 'MAGE' end
local class, className = ns.Trainers.PlayerClass()
check(class == 'mage' and type(className) == 'string', 'safe class token survives a secret localized name')
C_Trainer = { GetTrainerType = function() return secret end }
C_TradeSkillUI = { GetTradeSkillDisplayName = function() return secret end }
check(not visit().services.trainer_profession_alchemy, 'secret trainer type stays generic')
C_Trainer = nil
IsTradeskillTrainer = function() return secret end
check(not visit().services.trainer_profession_alchemy, 'secret legacy trainer boolean stays generic')
IsTradeskillTrainer = nil
C_Trainer = { GetTrainerType = function() return 2 end }
C_Trainer.GetTrainerType = function() return 2 end
check(not visit().services.trainer_profession_alchemy, 'secret localized profession stays generic')
C_TradeSkillUI.GetTradeSkillDisplayName = function(id) return id == 171 and 'GameAlchemy' or ('Game' .. id) end
GetTrainerServiceSkillLine = function() return secret end
check(not visit().services.trainer_profession_alchemy, 'secret service skill line stays generic')
GetNumTrainerServices = function() return 2 end
GetTrainerServiceSkillLine = function(i) return i == 1 and 'GameAlchemy' or secret end
check(not visit().services.trainer_profession_alchemy, 'one secret skill line among readable lines keeps the whole visit generic')
GetNumTrainerServices = function() return secret end
check(not visit().services.trainer_profession_alchemy, 'secret service count stays generic')
GetNumTrainerServices = function() error('API unavailable') end
check(not visit().services.trainer_profession_alchemy, 'throwing trainer API stays generic')
issecretvalue, UnitClass = oldSecret, savedClass
C_Trainer, C_TradeSkillUI = savedTrainer, savedTrade
GetNumTrainerServices, GetTrainerServiceSkillLine, IsTradeskillTrainer = savedCount, savedLine, savedIs
M.units.npc = nil

M.units.npc = { guid = 'Creature-0-1-2-3-990002-00000ABC', name = 'Nearby Class Teacher', reaction = 5, level = 60, faction = 'Horde' }
Learn.Unit('npc', 'trainer_class_mage') -- trusted typed observation, not inferred from trainer type
M.units.npc = nil
local exported = Learn.Export(true)
local st = { npcs = {}, objects = {}, quests = {}, items = {}, mailboxes = {} }
Learn.Import(exported, st, true)
check(st.npcs[990002] and st.npcs[990002].services.trainer_class_mage, 'WTL1 class trainer round trip')
check(st.npcs[991001] and st.npcs[991001].services.trainer_profession_alchemy, 'WTL1 profession trainer round trip')
local old = { npcs = {}, objects = {}, quests = {}, items = {}, mailboxes = {} }
Learn.Import('WTL1\tenUS\t1.0\nN\t990010\tOld Trainer\t0\t60\ttrainer\t37:500,500\tH\n', old, true)
check(old.npcs[990010] and old.npcs[990010].services.trainer, 'old generic-trainer WTL1 still imports')

local priorFaction = faction
faction = secret
local priorSecret = issecretvalue
issecretvalue = function(v) return rawequal(v, secret) or priorSecret(v) end
check(#DB.TrainerEntries('trainer_class_mage') == 0, 'secret player faction offers no trainer')
faction, issecretvalue = priorFaction, priorSecret

-- Nearest adds no background work, even after learning invalidates the DB.
Window.Hide()
local calls = 0
local entries, points, open = DB.TrainerEntries, DB.Points, ns.Trainers.OpenProfession
DB.TrainerEntries = function(...) calls = calls + 1; return entries(...) end
DB.Points = function(...) calls = calls + 1; return points(...) end
ns.Trainers.OpenProfession = function(...) calls = calls + 1; return open(...) end
ns.Fire('LEARNED')
M.Tick(5)
check(calls == 0, 'hidden window performs no trainer queries or scans')
DB.TrainerEntries, DB.Points, ns.Trainers.OpenProfession = entries, points, open

-- Existing quick-menu feedback channel remains visible with a hidden window.
Window.Hide()
local oldErrors, errorLines = UIErrorsFrame, {}
UIErrorsFrame = { AddMessage = function(_, text) errorLines[#errorLines + 1] = text end }
local oldClass = UnitClass
UnitClass = nil
M.player.combat = true
Find.GoToNearest('class')
check(errorLines[#errorLines] == L.TRAINER_CLASS_UNKNOWN, 'hidden-window quick action reports through the existing error channel in combat')
local oldEntries = DB.TrainerEntries
DB.TrainerEntries = function() return {} end
UnitClass = function() return 'Mage', 'MAGE' end
Find.GoToNearest('class')
check(errorLines[#errorLines] == L.TRAINER_NONE, 'quick action reports a missing trainer visibly')
UIErrorsFrame, UnitClass, DB.TrainerEntries, M.player.combat = oldErrors, oldClass, oldEntries, false
Find.Show()

-- Exact-token imports cannot promote malformed names into typed services.
for i, token in ipairs({ 'trainer_class_mage2', 'trainer_profession_alchemy|Tbad|t', 'UNKNOWN-trainer_weapon', 'trainer_riding_UNKNOWN' }) do
    import('N\t' .. (998100 + i) .. '\tBad token\t0\t60\t' .. token .. '\t37:500,500\tAH')
    check(not next(Learn.Store().npcs[998100 + i].services or {}), 'whole service token rejected: ' .. token)
end

-- Preserve faction/access evidence through repeated merges, repair and sharing.
C_Trainer = { GetTrainerType = function() return 2 end }
C_TradeSkillUI = { GetTradeSkillDisplayName = function(id) return 'Game' .. id end }
GetNumTrainerServices = function() return 1 end
GetTrainerServiceSkillLine = function() return 'Game171' end
local accessID = 998201
local function accessVisit(side)
    faction = side
    M.units.npc = { guid = 'Creature-0-1-2-3-' .. accessID .. '-ABC', name = 'Access trainer', reaction = 5, level = 60 }
    M.FireEvent('TRAINER_SHOW')
end
DB.Load()
local am, ax, ay = ns.Geo.GetPlayerMapPosition()
DB.community.npcs[accessID] = { name = 'Access trainer', hostile = false, level = 60,
    spots = { [am] = { ax, ay } }, services = { trainer = true, trainer_profession_alchemy = true } }
ns.Fire('LEARNED'); DB.Load()
accessVisit('Alliance'); DB.Load()
check(Learn.Store().npcs[accessID] ~= nil, 'compaction retains missing faction evidence')
ns.Fire('LEARNED'); DB.Load()
check(candidate('trainer_profession_alchemy', accessID), 'access survives a second database merge')
accessVisit('Horde'); DB.Load()
local access = Learn.Store().npcs[accessID]
check(access and access.fac == 'AH' and candidate('trainer_profession_alchemy', accessID), 'both characters can use their visited neutral trainer')
if access then Learn.Repair(access) end
local shared = { npcs = {}, objects = {}, quests = {}, items = {}, mailboxes = {} }
Learn.Import(Learn.Export(), shared, true)
check(shared.npcs[accessID] and shared.npcs[accessID].fac == 'AH' and shared.npcs[accessID].services.trainer_profession_alchemy, 'AH access survives repair, compaction, export and import')
local oldAccess = { npcs = {}, objects = {}, quests = {}, items = {}, mailboxes = {} }
Learn.Import('WTL1\tenUS\t1\nN\t998202\tOld\t0\t60\ttrainer\t37:500,500\tA\n', oldAccess, true)
Learn.Import('WTL1\tenUS\t1\nN\t998202\tOld\t0\t60\ttrainer_profession_alchemy\t37:500,500\tH\n', oldAccess, true)
check(oldAccess.npcs[998202].fac == 'AH', 'old one-faction exports combine access when imported successively')
C_Trainer, C_TradeSkillUI = savedTrainer, savedTrade
GetNumTrainerServices, GetTrainerServiceSkillLine, IsTradeskillTrainer = savedCount, savedLine, savedIs

-- Distinct class/profession rosters: exact NPC identity and minimum distance.
local originalRoster, originalServices = WaypointTrackerData.trainers, DB.services
local chosen, gotoEntry = nil, DB.GoTo
DB.GoTo = function(e, ...) chosen = e; return gotoEntry(e, ...) end
local serviceKeys = {}
for key in pairs(ns.Trainers.services) do serviceKeys[#serviceKeys + 1] = key end
table.sort(serviceKeys)
local testRoster, expected = {}, {}
for index, key in ipairs(serviceKeys) do
    local ids = {}
    for j = 1, 3 do
        local id = 997000 + index * 10 + j
        ids[j] = id .. ':AH'
        DB.units[id] = { kind = 'npc', id = id, fac = 'AH', name = key .. '-' .. j,
            points = { { m = 37, x = j == 2 and (0.2 + index * .005) or .8 + j * .01, y = j == 2 and .3 or .9 } } }
    end
    testRoster[#testRoster + 1] = key .. '\t' .. table.concat(ids, ',')
    expected[key] = 997000 + index * 10 + 2
end
WaypointTrackerData.trainers, DB.services = table.concat(testRoster, '\n'), {}
for _, side in ipairs({ 'Alliance', 'Horde' }) do
    faction = side
    for _, key in ipairs(serviceKeys) do
        local target = DB.units[expected[key]]
        local p = target.points[1]
        local cont, wx, wy = ns.Geo.MapToWorld(p.m, p.x, p.y)
        M.player.inst, M.player.wx, M.player.wy = cont, wx, wy
        M.Tick(.01)
        chosen = nil; WP.ClearAll(true)
        local chat = #M.printed
        if key:find('trainer_class_', 1, true) == 1 then
            local class = key:sub(#'trainer_class_' + 1)
            UnitClass = function() return class, class:upper() end
            Find.GoToNearest('class')
        elseif key:find('trainer_profession_', 1, true) == 1 then
            Find.GoToNearest('profession', key:sub(#'trainer_profession_' + 1))
        else Find.GoToNearest(key) end
        local wp = WP.GetActive()
        check(chosen and chosen.id == expected[key] and chosen.name:find(key, 1, true) == 1, side .. ': exact trainer identity and role for ' .. key)
        check(wp and wp.m == p.m and wp.x == p.x and wp.y == p.y, side .. ': exact nearest coordinates for ' .. key)
        local distance = chosen and ns.Geo.GetVector(chosen.points[1])
        local minimum = math.huge
        for _, entry in ipairs(DB.TrainerEntries(key)) do
            for _, point in ipairs(DB.Points(entry)) do minimum = math.min(minimum, ns.Geo.GetVector(point) or math.huge) end
        end
        check(distance and distance == minimum and distance < .001, side .. ': minimum measured distance for ' .. key)
        check(#M.printed == chat, 'trainer UI selection stays quiet: ' .. key)
    end
end
-- The roster order must never decide an unmeasurable Nearest result.
M.player.noPosition = true; M.Tick(.01)
for _, key in ipairs(serviceKeys) do
    WP.ClearAll(true)
    local result
    if key:find('trainer_class_', 1, true) == 1 then
        local class = key:sub(#'trainer_class_' + 1)
        UnitClass = function() return class, class:upper() end
        result = Find.GoToNearest('class')
    elseif key:find('trainer_profession_', 1, true) == 1 then
        result = Find.GoToNearest('profession', key:sub(#'trainer_profession_' + 1))
    else result = Find.GoToNearest(key) end
    check(not result and not WP.GetActive() and Window.frame.status:GetText() == L.TRAINER_POSITION_UNKNOWN, 'no player position is explained: ' .. key)
end
for _, service in ipairs(SERVICES) do
    DB.services[service[1]] = { { id = expected.trainer_weapon, fac = 'AH' } }
    WP.ClearAll(true)
    check(not Find.GoToNearest(service[1]) and Window.frame.status:GetText() == L.TRAINER_POSITION_UNKNOWN, 'old service refuses an unmeasured Nearest result: ' .. service[1])
end
M.player.noPosition = false; M.Tick(.01)
-- Malformed UTF-8 is repaired at both import and live observation boundaries.
for i, bytes in ipairs({ string.char(255), string.char(226, 130), string.char(192, 175), string.char(237, 160, 128), string.char(244, 144, 128, 128) }) do
    local id = 998300 + i
    import('N\t' .. id .. '\tBad' .. bytes .. 'name\t0\t60\ttrainer_weapon\t37:500,500\tAH')
    local e = Learn.Store().npcs[id]
    check(e.name == 'Bad' .. string.rep('?', #bytes) .. 'name', 'invalid UTF-8 import repaired, case ' .. i)
    local wp = DB.GoTo(e, { m = 37, x = .5, y = .5 }, e.name, true)
    check(wp and wp.title == e.name, 'only repaired text reaches waypoint title, case ' .. i)
    M.units.npc = { guid = 'Creature-0-1-2-3-' .. (998350 + i) .. '-ABC', name = bytes, reaction = 5 }
    Learn.Unit('npc', 'trainer')
    check(Learn.Store().npcs[998350 + i].name == string.rep('?', #bytes), 'live learned name repaired, case ' .. i)
end
for _, text in ipairs({ 'École', 'Учитель', '训练师', '訓練師', '전문가', '日本語', 'é' }) do
    check(ns.CleanText(text) == text and ns.CleanText(text, #text) == text, 'valid UTF-8 unchanged: ' .. text)
end
check(ns.CleanText('aéz', 2) == 'a', 'truncation never splits a UTF-8 character')
WaypointTrackerData.trainers, DB.services, DB.GoTo, UnitClass = originalRoster, originalServices, gotoEntry, savedClass

-- Later-source fallbacks: malformed points fail closed; DB/learned points win.
faction = 'Alliance'
local oldLocations = WaypointTrackerData.trainerLocations
WaypointTrackerData.trainers = 'trainer_weapon\t998401:AH'
for _, spots in ipairs({ '0:0.5,0.5', '999999:0.5,0.5', '37:2,0.5', '37:-0.1,0.5', '37:0.5', '37:NaN,0.5', ':0.5,0.5', '37:0.5,inf' }) do
    WaypointTrackerData.trainerLocations = '998401\tFallback\t' .. spots
    check(not candidate('trainer_weapon', 998401), 'invalid fallback position excluded: ' .. spots)
end
WaypointTrackerData.trainerLocations = '998401\t|cffffffffName|r|Tbad|t' .. string.char(255) .. '\t37:0.5,0.5'
local fallback = candidate('trainer_weapon', 998401)
check(fallback and fallback.name == (GetLocale() == 'enUS' and 'Name?' or ''), 'fallback name is clean and locale-safe')
DB.units[998401] = { kind = 'npc', id = 998401, name = 'Database name', fac = 'AH', points = { { m = 37, x = .4, y = .3 } } }
local entry = candidate('trainer_weapon', 998401)
check(entry == DB.units[998401] and #DB.TrainerEntries('trainer_weapon') == 1 and entry.points[1].x == .4, 'database position wins over duplicate fallback')
DB.units[998401] = nil
import('N\t998401\tLearned name\t0\t60\ttrainer_weapon\t37:200,300\tAH')
ns.Fire('LEARNED'); DB.Load()
local entry = candidate('trainer_weapon', 998401)
check(entry and entry.name == 'Learned name' and DB.Points(entry)[1].x == .2 and (function() local n = 0; for _, e in ipairs(DB.TrainerEntries('trainer_weapon')) do if e.id == 998401 then n = n + 1 end end; return n == 1 end)(), 'actual learned position wins over fallback with no duplicate')
WaypointTrackerData.trainers, WaypointTrackerData.trainerLocations = originalRoster, oldLocations

if bare then
    Find.Show()
    local picker = fw.nearest.profession
    local entries, go, actions = DB.TrainerEntries, Find.GoToNearest, 0
    DB.TrainerEntries = function() return {} end
    Find.GoToNearest = function() actions = actions + 1 end
    local initial = picker.text:GetText()
    local initialIndex = 1
    for i, p in ipairs(ns.Trainers.professions) do
        if initial:find(L['PROFESSION_' .. p.key:upper()], 1, true) == 1 then initialIndex = i end
    end
    local nextName = L['PROFESSION_' .. ns.Trainers.professions[initialIndex % 12 + 1].key:upper()]
    picker.next:Click()
    check(picker.text:GetText():find(L.TRAINER_UNAVAILABLE_SHORT, 1, true) and Window.frame.status:GetText():find(L.TRAINER_UNAVAILABLE, 1, true), 'bare picker displays availability and the status explains why')
    check(picker.text:GetText():find(nextName, 1, true), 'bare picker displays selected profession')
    check(picker.action and picker.action:GetWidth() >= picker.action:GetFontString():GetStringWidth() + 12 and picker:GetWidth() >= picker.action:GetWidth(), 'bare explicit action label fits the grid')
    check(picker:GetWidth() >= picker.text:GetStringWidth() + 56, 'bare selected name and reason fit the picker')
    check(actions == 0 and picker.action and picker.action:GetText() == L.TRAINER_ACTION, 'bare arrows select; explicit button performs the action')
    DB.TrainerEntries = function() return { {} } end
    picker.prev:Click(); if picker.action then picker.action:Click() end
    check(actions == 1 and picker.text:GetText():find(L['PROFESSION_' .. ns.Trainers.professions[initialIndex].key:upper()], 1, true) and picker.text:GetText():find(L.TRAINER_AVAILABLE, 1, true), 'bare action and availability use selected profession')
    DB.TrainerEntries, Find.GoToNearest = entries, go
end
-- Showing/refreshing a Nearest control and resizing never queries availability.
Find.Show()
local originalLoad, originalEntries = DB.Load, DB.TrainerEntries
local callbacks = 0
DB.Load = function(...) callbacks = callbacks + 1; return originalLoad(...) end
DB.TrainerEntries = function(...) callbacks = callbacks + 1; return originalEntries(...) end
ns.Set('arrowScale', 1.05)
fw.nearest[1]:GetParent():RunScript('OnSizeChanged')
fw.nearest.profession:RunScript('OnShow')
check(callbacks == 0, 'shown unrelated setting/size/control-show does zero database or trainer work')
DB.Load, DB.TrainerEntries = originalLoad, originalEntries

-- Unrelated callbacks must do zero trainer/database work while hidden.
Window.Hide()
local loads, queries, merges, sizeWrites, labelWrites = 0, 0, 0, 0, 0
local load, entries, merge = DB.Load, DB.TrainerEntries, DB.MergeLearned
DB.Load = function(...) loads = loads + 1; return load(...) end
DB.TrainerEntries = function(...) queries = queries + 1; return entries(...) end
DB.MergeLearned = function(...) merges = merges + 1; return merge(...) end
local button = fw.nearest[1]
local setWidth = button.SetWidth
button.SetWidth = function(...) sizeWrites = sizeWrites + 1; return setWidth(...) end
local pickerText = fw.nearest.profession.text
local setText = pickerText and pickerText.SetText
if setText then pickerText.SetText = function(...) labelWrites = labelWrites + 1; return setText(...) end end
ns.Fire('LEARNED')
local started = os.clock()
for i = 1, 1000 do ns.Set('arrowScale', 1 + (i % 2) * .1) end
local hiddenCost = (os.clock() - started) * 1000
fw.nearest[1]:GetParent():RunScript('OnSizeChanged')
fw.nearest.profession:RunScript('OnShow')
M.Tick(.1)
check(loads == 0 and queries == 0 and merges == 0, '1000 hidden settings, size/show and learned events perform zero loads/queries/merges')
check(sizeWrites == 0 and labelWrites == 0, 'hidden callbacks do no Nearest layout or picker label work')
if setText then pickerText.SetText = setText end
print(('Hidden 1000 settings: %.3f ms; loads=%d queries=%d merges=%d'):format(hiddenCost, loads, queries, merges))
button.SetWidth, DB.Load, DB.TrainerEntries, DB.MergeLearned = setWidth, load, entries, merge
check(#M.errors == 0, 'Nearest has no reported Lua errors')
for _, e in ipairs(M.errors) do print(e) end
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and #M.errors == 0 and 0 or 1)
