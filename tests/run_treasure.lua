-- Treasure detection, per-character persistence, the shared tab and entry points.
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local secret = setmetatable({}, {
    __tostring = function() error('secret formatted') end,
    __lt = function() error('secret compared') end,
    __le = function() error('secret compared') end,
    __sub = function() error('secret arithmetic') end,
})
local wasSecret = issecretvalue
issecretvalue = function(v) return rawequal(v, secret) or wasSecret(v) end
local bare = arg[1] == '--bare'
if bare then
    MenuUtil, ShowUIPanel, HideUIPanel, RegisterUIPanel = nil, nil, nil, nil
    local create = CreateFrame
    CreateFrame = function(kind, name, parent, template)
        if template == 'UICheckButtonTemplate' or template == 'UIPanelButtonTemplate'
            or template == 'ButtonFrameTemplate' then error('optional template unavailable') end
        return create(kind, name, parent, template)
    end
end
-- wowmock keeps only the last anchor. Record each anchor here without
-- changing the shared mock, so sibling edges and bottom containment are testable.
local nativeCreate = CreateFrame
local function RecordAnchors(f)
    local point, all = f.SetPoint, f.SetAllPoints
    f.reviewPoints = {}
    function f:SetPoint(p, rel, rp, x, y)
        if type(rel) == 'number' then rel, rp, x, y = self:GetParent(), p, rel, rp end
        self.reviewPoints[p] = {rel or self:GetParent(), rp or p, x or 0, y or 0}
        return point(self, p, rel, rp, x, y)
    end
    function f:SetAllPoints(rel) self.reviewAll = rel or self:GetParent(); return all(self, rel) end
    local createFont = f.CreateFontString
    function f:CreateFontString(...) return RecordAnchors(createFont(self, ...)) end
    return f
end
CreateFrame = function(...) return RecordAnchors(nativeCreate(...)) end
-- Install geometry before loading modules that cache missing maps.
for _, f in ipairs({
    {1416, 1500, 783.33331298828, 2799.99993896488, 1866.66665649414},
    {1424, 400, 1066.6666259766, 3199.9998779297, 2133.3332519531},
    {1420, 3837.4997558594, 3033.33325195313, 4518.7498779297, 3012.49981689456},
    {1458, 1877.9453125, 873.19262695313, 959.37503051758, 640.1041259766},
}) do
    M.maps[f[1]] = {mapID = f[1], name = 'Travel fixture', cont = 0, top = f[2], left = f[3], w = f[4], h = f[5], mapType = 3, parentMapID = 13}
end
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker')
M.FireEvent('PLAYER_LOGIN')
local T, G, WP, Window, L = ns.Treasure, ns.Geo, ns.WP, ns.Window, ns.L
local passed, failed = 0, 0
local function check(ok, text)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. text) end
end
local function close(a, b) return a and b and math.abs(a - b) < 0.00001 end
local function guid(id, suffix, object)
    return (object and 'GameObject' or 'Creature') .. '-0-1-0-0-' .. id .. '-' .. (suffix or '1')
end
local function reset()
    T.Clear(); WP.ClearAll(true); M.units, M.vignettes = {}, {}
    ns.settings.treasureKnownSpots, ns.settings.treasureKnownRares = false, false
end
local function rare(token, id, suffix, fields)
    local u = {guid = guid(id, suffix), name = 'Unknown rare', class = 'rareelite', reaction = 2, level = 30}
    for k, v in pairs(fields or {}) do u[k] = v end
    M.units[token] = u
    return u.guid, u
end
local function marker(key, name, kind, x, y)
    M.vignettes[key] = { objectGUID = key, name = name or 'Find', onMinimap = true,
        atlasName = kind == 'rare' and 'VignetteKill' or 'VignetteLoot', pos = {x or 0.65, y or 0.6} }
end
check(not ns.Get('treasureHunt') and not ns.Get('treasureKnownRares'), 'fresh beta and known rares default off')
T.Recent() -- first log consumer lazily initializes the missing character log
check(WaypointTrackerDB.version == 5 and type(ns.charDB.treasureLog) == 'table', 'nil character log initializes without schema migration')
check(Window.tabs.treasure.spec.title == L.TREASURE_TAB and L.TREASURE_TAB:find('(beta)', 1, true), 'fourth tab labelled beta')
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, 'treasure show')
local ui = ns.TabTreasure.widgets
check(Window.IsShown() and Window.GetTab() == 'treasure' and not ns.Get('treasureHunt'), 'show opens shared tab without opting in')
check(ui.off:IsShown() and not ui.on:IsShown() and ui.enable:GetText() == L.TREASURE_ENABLE, 'off state gives introduction and enable control')
local printed = #M.printed
ui.enable:Click()
check(ns.Get('treasureHunt') and ui.on:IsShown() and not ui.off:IsShown(), 'enable button switches to lists and settings')
check(#M.printed == printed and Window.frame.status:GetText() == L.TREASURE_ON, 'enable feedback uses window status, not chat')
for _, key in ipairs({'treasureChests','treasureRares','treasureOther','treasureKnownSpots','treasureKnownRares','treasurePing','treasureFocus'}) do
    check(ui[key] ~= nil and M.settings['WAYPOINTTRACKER_' .. key] ~= nil, 'same setting exists in tab and Settings: ' .. key)
end
ui.treasurePing:Click()
check(not ns.Get('treasurePing'), 'tab checkbox writes shared setting')
M.settings.WAYPOINTTRACKER_treasurePing:SetValue(true)
ns.TabTreasure.Refresh()
check(ui.treasurePing:GetChecked(), 'Settings writes reflected in tab')
local quick = {items = {}}
function quick:CreateTitle() end
function quick:CreateDivider() end
function quick:CreateCheckbox(text, selected, fn) self.items[text] = {fn = fn, selected = selected} end
function quick:CreateButton(text, fn) self.items[text] = {fn = fn}; return {} end
ns.QuickMenu.Build(quick)
check(quick.items[L.TREASURE_TAB] and quick.items[L.TREASURE_HUNT], 'quick menu retains toggle and adds setup entry')
Window.Hide(); quick.items[L.TREASURE_TAB].fn()
check(Window.GetTab() == 'treasure' and Window.IsShown(), 'quick menu opens treasure setup')
local setupButton
for _, init in ipairs(M.settingsLayouts[ns.Options.categories.treasure].initializers) do
    if init.kind == 'button' and init.name == L.TREASURE_TAB then setupButton = init end
end
check(setupButton and setupButton.tooltip == L.TREASURE_INTRO, 'Settings category has setup button with plain instructions')
Window.Hide(); setupButton.click()
check(Window.IsShown() and Window.GetTab() == 'treasure', 'Settings setup button opens same window tab')

ns.Set('realRoutes', false)
reset()
local map, px, py = G.GetPlayerMapPosition()
local key, unit = rare('nameplate1', 999001)
T.Scan()
local t = T.Targets()[key]
check(t and t.near and t.wp and t.m == map and close(t.x, px) and close(t.y, py), 'unknown rare placed at first player sighting')
check(not WP.CheckArrival(t.wp, 0) and WP.IsValid(t.wp), 'seen-near waypoint is not immediately auto-cleared at player position')
local alert = table.concat(M.printed, '\n')
check(alert:find(L.TREASURE_CLASS_ELITE, 1, true) and alert:find(L.TREASURE_LEVEL:format('30'), 1, true), 'unit alert includes plain classification and level')
M.player.wx = M.player.wx - 40
T.Scan()
check(close(t.x, px), 'fallback position stays fixed as the player moves')
M.now = M.now + 2; T.Scan()
check(T.LastSeen(999001) == math.floor(M.now), 'last-seen time advances while a rare remains visible')
marker(key, 'Unknown rare', 'rare', 0.63, 0.52)
T.Scan()
check(t.vig and not t.near and close(t.wp.x, 0.63), 'vignette upgrades approximate position')
check(T.Recent()[1].id == 999001 and close(T.Recent()[1].x, 0.63), 'persistent log gains id and improved position')
local levelKey = rare('target', 999002, '1', {class = 'worldboss', level = -1})
T.LookAt('target')
alert = table.concat(M.printed, '\n')
check(alert:find(L.TREASURE_CLASS_BOSS, 1, true) and alert:find(L.TREASURE_LEVEL:format('??'), 1, true), 'boss unknown level is displayed as ??')
-- Known spawn outside the matching radius falls back; a near spawn stays precise.
ns.DB.units[999003] = {id = 999003, kind = 'npc', name = 'Far spawn', points = {{m = map, x = 0.95, y = 0.95}}}
local farKey = rare('focus', 999003)
T.LookAt('focus')
check(T.Targets()[farKey] and T.Targets()[farKey].near, 'far known spawn does not masquerade as current rare location')
local hm, hx, hy = G.GetPlayerMapPosition()
ns.DB.units[999004] = {id = 999004, kind = 'npc', name = 'Near spawn', points = {{m = hm, x = hx + 0.01, y = hy}}}
local nearKey = rare('nameplate2', 999004)
T.LookAt('nameplate2')
check(T.Targets()[nearKey] and not T.Targets()[nearKey].near and close(T.Targets()[nearKey].x, hx + 0.01), 'near known spawn used precisely')
reset()
local tapped = rare('nameplate1', 999005, '1', {tapped = true})
local friend = rare('nameplate2', 999006, '1', {reaction = 5})
marker(tapped, 'Tapped', 'rare'); marker(friend, 'Friendly', 'rare')
printed = #M.printed
T.Scan()
check(not next(T.Targets()) and #M.printed == printed, 'friendly and tapped units suppress their vignettes before alert')
M.units.nameplate1.tapped = false
T.Scan()
check(T.Targets()[tapped] ~= nil, 'an attackable untapped unit can be tracked again')
M.units.nameplate1.tapped = true
T.Scan()
check(T.Targets()[tapped] == nil, 'a tracked rare that becomes tapped is removed')
reset()
local deadKey, deadUnit = rare('target', 999007)
T.Scan(); deadUnit.dead = true; T.Scan()
check(not T.Targets()[deadKey] and T.Recent()[1].outcome == 'killed', 'death updates log and removes waypoint')
deadUnit.dead = false
M.FireEvent('ZONE_CHANGED_NEW_AREA'); T.Scan()
check(not T.Targets()[deadKey], 'done memory survives zone notifications')
M.now = M.now + 601; T.Scan()
check(T.Targets()[deadKey] ~= nil, 'done memory expires after ten minutes')
reset()
local chest = guid(2843, 'front', true)
M.units.softinteract = {guid = chest, name = 'Battered Chest'}
T.CheckInFront()
check(T.Targets()[chest] and T.Targets()[chest].wp and T.Targets()[chest].near, 'soft-interact chest has seen-near position and arrow')
M.loot = {chest}; M.FireEvent('LOOT_OPENED'); M.loot = {}
check(not T.Targets()[chest] and T.Recent()[1].outcome == 'looted', 'looting updates persistent outcome')
T.CheckInFront()
check(not T.Targets()[chest], 'looted chest remains suppressed')
reset()
local moving = guid(2843, 'moving', true)
marker(moving)
T.Scan()
local old = T.Targets()[moving]
local bestMap, positionAPI = C_Map.GetBestMapForUnit, C_VignetteInfo.GetVignettePosition
local requested = {}
C_Map.GetBestMapForUnit = function() return 52 end
C_VignetteInfo.GetVignettePosition = function(v, m)
    requested[m] = true
    if m == map then return CreateVector2D(0.65, 0.6), 1.23 end
end
T.Scan()
check(old.m == map and old.wp.m == map and requested[52] and requested[map], 'unprojectable best-map change retains prior map, never treats facing as map id')
C_VignetteInfo.GetVignettePosition = function() return CreateVector2D(0.2, 0.3), 1.23 end
T.Scan()
check(old.m == 52 and old.wp.m == 52 and close(old.x, 0.2), 'position returned on requested new map moves waypoint consistently')
M.vignettes = {}; T.Scan()
check(not T.Targets()[moving] and T.Recent()[1].outcome == 'gone', 'vanished vignette is recorded as gone')
marker(moving); T.Scan()
check(T.Targets()[moving] ~= nil, 'leaving marker range does not count as loot or suppress a later sighting')
C_Map.GetBestMapForUnit, C_VignetteInfo.GetVignettePosition = bestMap, positionAPI
reset()
local stale = rare('target', 999008)
T.Scan(); M.units = {}; C_Map.GetBestMapForUnit = function() return 52 end
T.Scan()
check(not T.Targets()[stale], 'best-map change expires old unit-only positions without requiring zone event')
C_Map.GetBestMapForUnit = bestMap
reset()
local sameMapStale = rare('target', 999012)
T.Scan(); M.units = {}; M.FireEvent('ZONE_CHANGED_NEW_AREA')
check(not T.Targets()[sameMapStale], 'area transition drops old unit sightings even when instances reuse the same map id')
-- Isolated known-point fixture makes selection, visit expiry and cache work observable.
reset()
local realDB, vectors = ns.DB, G.GetVector
ns.DB = {ready = true, generation = realDB.generation + 100, objects = {
    [1] = {id = 1, name = 'Distant chest', chest = true, points = {{m = map, x = 0.8, y = 0.5}}},
    [2] = {id = 2, name = 'Other zone', chest = true, points = {{m = 52, x = 0.51, y = 0.5}}},
}, units = {
    [3] = {id = 3, name = 'Rare spot', rank = '4', points = {{m = map, x = 0.7, y = 0.5}}},
}, Points = function(e) return e.points end, IsEnemy = function() return true end}
local vectorCalls, pointCalls, wrongMap = 0, 0, false
G.GetVector = function(p)
    vectorCalls = vectorCalls + 1
    if p.m ~= map then wrongMap = true end
    return p.x * 1000
end
ns.DB.Points = function(e) pointCalls = pointCalls + 1; return e.points end
ns.settings.treasureKnownSpots, ns.settings.treasureKnownRares = true, true
ns.settings.treasureFocus = false
local mine = WP.Add(map, 0.3, 0.3, {title = 'Mine', silent = true})
T.PickKnown()
check(not T.Targets().spot and WP.GetActive() == mine, 'known exploration preserves player waypoint when focus off')
WP.Remove(mine, true); T.PickKnown()
check(T.Targets().spot and T.Targets().spot.kind == 'spawn' and T.Targets().spot.id == 3, 'nearest rare or chest anywhere in current zone is selected beyond 300 yards')
check(not wrongMap and pointCalls == 3 and vectorCalls == 2, 'index built once and pick only measures current zone')
T.Clear(); T.PickKnown()
check(pointCalls == 3, 'same generation reuses point index')
WP.Remove(T.Targets().spot.wp, true); T.PickKnown()
check(T.Targets().spot and T.Targets().spot.id == 1, 'visited rare skipped in favour of next chest')
WP.Remove(T.Targets().spot.wp, true); T.PickKnown()
check(not T.Targets().spot, 'both checked spots skipped for ten minutes')
M.now = M.now + 601; T.PickKnown()
check(T.Targets().spot and T.Targets().spot.id == 3, 'visited spots become eligible after ten minutes')
ns.DB.generation = ns.DB.generation + 1; ns.DB.objects[4] = {id = 4, name = 'New chest', chest = true, points = {{m = map, x = 0.6, y = 0.5}}}
T.Clear(); T.PickKnown()
check(T.Targets().spot and T.Targets().spot.id == 4 and pointCalls == 7, 'new database generation invalidates index')
T.SetOption('treasureKnownRares', false)
T.Clear(); T.PickKnown()
check(T.Targets().spot and T.Targets().spot.kind == 'spot', 'rare exploration has a separate setting')
T.Ignore(T.Targets().spot); T.PickKnown()
check(T.Targets().spot and T.Targets().spot.id == 1, 'ignoring a known spot skips only that location, not all exploration')
marker(guid(2843, 'live', true)); T.Scan()
local live = T.Targets()[guid(2843, 'live', true)]
WP.SetActive(live.wp, true)
T.PickKnown()
check(WP.GetActive() == live.wp, 'known spots never steal arrow from live find')
-- The tab lists use the same index and normal waypoint entry point.
ns.TabTreasure.Refresh()
check(#ui.zone.items == 3 and ui.zone.items[1].id == 4 and #ui.nearby.items == 2, 'tab lists zone nearest-first and all current tracked targets')
local wpAdd, addCalls, addOptions = WP.Add, 0
WP.Add = function(m, x, y, options) addCalls = addCalls + 1; addOptions = options; return wpAdd(m, x, y, options) end
ui.zone.rows[1]:RunScript('OnDoubleClick', 'LeftButton')
check(addCalls == 1 and addOptions.source == 'user' and WP.GetActive().persistent, 'zone double-click uses normal user waypoint path for Real routes')
WP.Add = wpAdd
-- Always exercise menu callbacks, including the Widgets fallback menu model.
local row
for _, r in ipairs(ui.nearby.rows) do if r.item == live then row = r end end
check(row ~= nil, 'nearby row is available')
local menuTool = MenuUtil
local menu
MenuUtil = {CreateContextMenu = function(owner, build)
    menu = {items = {}}
    function menu:CreateButton(text, fn) self.items[#self.items + 1] = {text = text, fn = fn} end
    build(owner, menu); return menu
end}
printed = #M.printed
row:Click('RightButton')
check(#menu.items == 2 and menu.items[1].text == L.ROW_MENU_POINT and menu.items[2].text == L.TREASURE_IGNORE, 'nearby right-click offers point and ignore')
menu.items[1].fn()
check(WP.GetActive() == live.wp, 'point menu action selects live waypoint')
menu.items[2].fn()
check(not T.Targets()[live.key] and #M.printed == printed and Window.frame.status:GetText() == L.TREASURE_IGNORED, 'ignore removes quietly with status feedback')
T.Scan()
check(not T.Targets()[live.key], 'ignored live marker stays suppressed')
MenuUtil = menuTool
ns.DB, G.GetVector = realDB, vectors
reset()
-- Hidden callbacks and off-tab callbacks must not rebuild or even measure lists.
local refreshes, realSetItems = 0, ui.zone.SetItems
ui.zone.SetItems = function(...) refreshes = refreshes + 1; return realSetItems(...) end
Window.Hide(); ns.TabTreasure.Refresh(); Window.frame:RunScript('OnUpdate', 1)
check(refreshes == 0, 'hidden window does no treasure list work')
Window.Show('waypoints'); ns.TabTreasure.Refresh()
check(refreshes == 0, 'other visible tab does no treasure list work')
Window.Show('treasure'); refreshes = 0
Window.frame:RunScript('OnUpdate', 0.2); Window.frame:RunScript('OnUpdate', 0.2)
check(refreshes == 0, 'visible refresh is throttled')
Window.frame:RunScript('OnUpdate', 0.11)
check(refreshes == 1, 'visible lists refresh at about twice a second')
ui.zone.SetItems = realSetItems
-- Distinct creatures at the same approximate point have independent lifetimes.
reset()
local twinA = rare('target', 999050)
local twinB = rare('focus', 999050, '2')
T.Scan()
check(T.Targets()[twinA].wp ~= T.Targets()[twinB].wp, 'same-name finds at the same point never share temporary waypoints')
local survivor = T.Targets()[twinB].wp
T.Ignore(T.Targets()[twinA])
check(WP.IsValid(survivor), 'ignoring one nearby creature preserves the other arrow target')
-- Cap, reload, corruption and character isolation.
ns.settings.treasurePing = false
for i = 1, 60 do
    M.units = {}; rare('target', 999100 + i); T.LookAt('target'); M.now = M.now + 1
end
check(#T.Recent() == 50 and T.Recent()[1].id == 999160 and T.Recent()[50].id == 999111, 'persistent log keeps newest fifty finds')
check(ns.charDB.treasureLog == T.Recent(), 'log belongs to per-character SavedVariables')
local last = T.LastSeen(999160)
T.LoadLog()
check(#T.Recent() == 50 and T.LastSeen(999160) == last, 'last-seen timestamps survive log reload')
ns.charDB.treasureLog = {
    {at = 1, kind = 'rare', name = '|cffffffffValid|r', id = 999160, m = 37, x = 0.2, y = 0.3, outcome = 'killed', arbitrary = 'discard'},
    {at = secret, kind = 'rare', name = 'Secret time'},
    {at = 0/0, kind = 'rare', name = 'NaN'},
    {at = 2, kind = secret, name = 'Secret kind'},
    {at = 2, kind = 'rare', name = secret},
    {at = 2, kind = 'invalid', name = 'Wrong kind'},
    {at = 3, kind = 'chest', name = 'Partial', m = secret, x = secret, y = 0.3, id = secret, outcome = secret, via = secret},
    {at = math.huge, kind = 'rare', name = 'Infinite'},
    secret,
    {at = 4, kind = 'rare', name = 'Bounds', m = 37, x = 2, y = -1, id = -5, outcome = 'madeup'},
}
T.LoadLog()
check(#T.Recent() == 3 and T.Recent()[3].name == 'Valid' and not T.Recent()[3].arbitrary, 'corrupt records filtered and only clean whitelisted fields copied')
check(T.Recent()[2].m == nil and T.Recent()[2].id == nil and T.Recent()[1].x == nil, 'secret and out-of-range saved coordinates and ids rejected')
local charDB = ns.charDB
ns.charDB = {}; T.LoadLog(); check(#T.Recent() == 0, 'new character starts with independent empty log')
ns.charDB = charDB; T.LoadLog(); check(#T.Recent() == 3, 'original character log retained')
local saveTime, saveServer = time, GetServerTime
time, GetServerTime = function() return secret end, function() return secret end
check(T.Time() == 0, 'secret wall clocks safely fall back')
time, GetServerTime = nil, nil
check(T.Time() == 0, 'missing wall clocks safe')
time, GetServerTime = saveTime, saveServer
reset()
local secretGUID = rare('target', 999009, '1', {level = secret})
T.LookAt('target')
check(T.Targets()[secretGUID] and not T.Targets()[secretGUID].level, 'secret unit level omitted')
local unitFunctions = {'UnitExists','UnitClassification','UnitGUID','UnitName','UnitIsPlayer','UnitPlayerControlled','UnitCanAttack','UnitIsDead','UnitIsTapDenied'}
for _, name in ipairs(unitFunctions) do
    reset(); rare('target', 999010)
    local original = _G[name]; _G[name] = function() return secret end
    check(pcall(T.Scan), 'secret unit API handled: ' .. name)
    _G[name] = original
end
reset()
local vigAPI, mapAPI = C_VignetteInfo, C_Map.GetBestMapForUnit
C_VignetteInfo = {GetVignettes = function() return {secret, 'test'} end,
    GetVignetteInfo = function(g) assert(not rawequal(g, secret)); return {name = secret, objectGUID = secret, atlasName = secret, onMinimap = true} end,
    GetVignettePosition = function() return secret end}
C_Map.GetBestMapForUnit = function() return secret end
check(pcall(T.Scan) and not next(T.Targets()), 'secret vignette GUID, info, position and map do not leak into APIs or storage')
C_Map.GetBestMapForUnit = mapAPI
C_VignetteInfo = nil
M.units = {}; rare('target', 999011)
check(pcall(T.Scan) and T.Targets()[guid(999011)], 'missing vignette API still detects target rare')
UnitExists = nil
check(pcall(T.Scan), 'missing unit API/nameplates is safe')
UnitExists = function(token) return M.units[token] ~= nil end
C_VignetteInfo = vigAPI
reset()
M.FireEvent('VIGNETTES_UPDATED'); T.SetOption('treasureHunt', false)
marker(guid(2843, 'late', true)); M.Tick(0.15)
check(not next(T.Targets()), 'queued vignette callback cannot restart disabled feature')
printed = #M.printed
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, 'treasure status')
check(not ns.Get('treasureHunt') and #M.printed > printed, 'status reports without toggling')
M.TypeSlash(SlashCmdList.WAYPOINTTRACKER, 'treasure')
check(ns.Get('treasureHunt'), 'original treasure command still toggles on')
M.player.combat = true
Window.Hide(); Window.Show('treasure'); ui.disable:Click(); ui.enable:Click()
check(not M.actionBlocked and Window.IsShown() and ns.Get('treasureHunt'), 'combat UI actions use shared safe window without protected calls')
M.player.combat = false
-- Adversarial-review regressions: exercise public APIs and rendered rows.
reset(); ns.settings.treasureHunt = true
local fallbackAPIs = {best = C_Map.GetBestMapForUnit, pos = C_Map.GetPlayerMapPosition}
for _, mode in ipairs({'secret map', 'secret position', 'missing method', 'missing namespace'}) do
    reset()
    rare('target', 998001)
    M.units.softinteract = {guid = guid(2843, mode, true), name = 'Battered Chest'}
    if mode == 'secret map' then
        C_Map.GetBestMapForUnit = function() return secret end
        C_Map.GetPlayerMapPosition = function(m) assert(not rawequal(m, secret), 'secret map forwarded') end
    elseif mode == 'secret position' then
        secret.GetXY = function() error('secret position accessed') end
        C_Map.GetPlayerMapPosition = function() return secret end
    elseif mode == 'missing method' then C_Map.GetPlayerMapPosition = nil end
    local namespace = C_Map
    if mode == 'missing namespace' then C_Map = nil end
    local ok = pcall(T.Scan)
    check(ok and T.Targets()[guid(998001)] and T.Targets()[guid(2843, mode, true)], 'fallback boundaries: ' .. mode .. ' keeps unpositioned rare and chest')
    C_Map = namespace
    C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition = fallbackAPIs.best, fallbackAPIs.pos
end
secret.GetXY = nil
reset()
local hostile = '|cffff0000Danger|r|Tbad:128|t|Hitem:25|hClick|h|Ksecret|k|n\027'
local store = ns.Learn.Store()
store.objects[2843] = {name = hostile, spots = {[map] = {0.8, 0.5}}}
ns.DB.MergeLearned()
Window.Show('treasure'); ns.TabTreasure.Refresh()
local foundClean = false
for i, p in ipairs(ui.zone.items) do
    if p.id == 2843 then
        ui.zone:ScrollTo(i)
        for _, row in ipairs(ui.zone.rows) do
            if row.item == p then foundClean = not row.text:GetText():find('|', 1, true) and #p.name <= 60 end
        end
        break
    end
end
check(foundClean, 'database saved names are cleaned before zone FontStrings')
ns.settings.treasurePing = true
local alertStart, noticeStart = #M.printed, #M.raidNotices
M.now = M.now + 2 -- let the warning throttle expire
marker(guid(998002), hostile, 'rare'); T.Scan()
local cleanTarget = T.Targets()[guid(998002)]
check(cleanTarget and not cleanTarget.name:find('|', 1, true) and not cleanTarget.wp.title:find('|', 1, true), 'live names and waypoint titles neutralize escape codes')
local cleanChat = true
for i = alertStart + 1, #M.printed do
    -- ns.Print adds its own trusted addon colour prefix; the payload must be safe.
    if M.printed[i]:find('|Tbad', 1, true) or M.printed[i]:find('|Hitem', 1, true) or M.printed[i]:find('|Ksecret', 1, true) then cleanChat = false end
end
check(cleanChat, 'chat payloads neutralize saved-name markup')
check(#M.raidNotices > noticeStart and not M.raidNotices[#M.raidNotices]:find('|', 1, true), 'raid warning payload neutralizes saved-name markup')
ns.charDB.treasureLog = {{at = 1000, kind = 'rare', name = hostile}}
T.LoadLog(); ns.TabTreasure.Refresh()
check(not T.Recent()[1].name:find('|', 1, true) and not ui.recent.rows[1].text:GetText():find('|', 1, true), 'saved log names cleaned before recent FontStrings')
reset()
for _, fields in ipairs({{class = 'normal', reaction = 5}, {class = 'normal', tapped = true}, {class = 'normal', controlled = true}}) do
    reset()
    local k = rare('target', 998003, tostring(fields), fields)
    marker(k, 'Non-actionable', 'rare')
    local before = #M.printed
    T.Scan()
    check(not T.Targets()[k] and #M.printed == before, 'normal classification cannot bypass visible-unit rejection: ' .. (fields.tapped and 'tap' or fields.controlled and 'controlled' or 'friendly'))
end
reset()
local lootCount, lootSources = GetNumLootItems, GetLootSourceInfo
local front = guid(2843, 'unrelated', true)
M.units.softinteract = {guid = front, name = 'Battered Chest'}; T.CheckInFront()
for _, source in ipairs({'Creature-0-1-0-0-998004-1', 'Item-0-1-1234', ''}) do
    GetNumLootItems = function() return source == '' and 0 or 1 end
    GetLootSourceInfo = function() return source ~= '' and source or nil, 1 end
    M.FireEvent('LOOT_OPENED')
    check(T.Targets()[front] and not T.Targets()[front].log.outcome, 'unrelated or empty loot preserves soft-interact chest: ' .. source)
end
GetNumLootItems = function() return 1 end
GetLootSourceInfo = function() return nil end
M.FireEvent('LOOT_OPENED')
check(T.Targets()[front] ~= nil, 'unidentified loot without opening evidence preserves chest')
reset()
local sourceA, sourceB = guid(2843, 'sourceA', true), guid(2843, 'sourceB', true)
marker(sourceA); marker(sourceB); T.Scan()
local logA, logB = T.Targets()[sourceA].log, T.Targets()[sourceB].log
GetLootSourceInfo = function() return sourceA, 1, secret, secret, sourceB, 1 end
local lootOK = pcall(M.FireEvent, 'LOOT_OPENED')
check(lootOK and not T.Targets()[sourceA] and not T.Targets()[sourceB] and logA.outcome == 'looted' and logB.outcome == 'looted', 'all loot GUID/count pairs processed with secret later source')
GetNumLootItems, GetLootSourceInfo = lootCount, lootSources
reset()
local spawnA = rare('target', 998005, 'A'); T.Scan(); M.now = M.now + 10
local spawnB = rare('focus', 998005, 'B'); T.Scan(); M.units.focus = nil; M.now = M.now + 100; T.Scan()
check(T.LastSeen(998005) == T.Targets()[spawnA].log.lastSeen and T.LastSeen(998005) > T.Targets()[spawnB].log.lastSeen, 'last seen takes latest observation across spawns')
reset()
local renameKey, renameUnit = rare('target', 998006, 'rename', {name = false})
renameUnit.name = nil; T.Scan()
local rename = T.Targets()[renameKey]; local sameWP = rename.wp
local renames = 0
ns.On('WAYPOINTS_CHANGED', function() renames = renames + 1 end)
renameUnit.name = 'Real name'; T.Scan()
check(rename.name == 'Real name' and rename.log.name == 'Real name' and rename.wp == sameWP and sameWP.title == L.TREASURE_TITLE:format(T.Label(rename), 'Real name'), 'corrected name updates log and same waypoint title')
local notifications = renames; T.Scan()
check(notifications > 0 and renames == notifications, 'name correction notifies once without repeated waypoint changes')
WP.Remove(sameWP, true); T.Scan(); renameUnit.name = 'Better name'; T.Scan()
check(rename.dismissed and not rename.wp and rename.log.name == 'Better name', 'name correction preserves manual dismissal')
ns.charDB.treasureLog = {}
for i = 1, 50 do ns.charDB.treasureLog[i] = {at = 1000, kind = 'rare', name = 'entry ' .. i, id = i} end
for reload = 1, 3 do
    T.LoadLog()
    local stable = true
    for i = 1, 50 do if T.Recent()[i].id ~= i then stable = false end end
    check(stable, 'equal timestamp saved order stable through reload ' .. reload)
end
-- Feature-off INIT must not inspect or replace the saved log.
ns.settings.treasureHunt = false
local rawLog = {}
for i = 1, 50 do rawLog[i] = {at = 1000, kind = 'rare', name = string.rep('|H', 16000)} end
ns.charDB.treasureLog = rawLog
local loadStart = os.clock(); ns.Fire('INIT')
check(ns.charDB.treasureLog == rawLog and (os.clock() - loadStart) < 0.02, 'feature-off INIT leaves hostile saved log untouched')
ns.charDB.treasureLog = rawLog
loadStart = os.clock(); T.LoadLog()
local hostileMS = (os.clock() - loadStart) * 1000
check(hostileMS < 20 and #T.Recent() == 50, 'hostile fifty-entry 32 KB name log loads within 20 ms')
print(('Hostile 50 x 32 KB log: %.3f ms'):format(hostileMS))
local hugeLog = {}
for i = 1, 100000 do hugeLog[i] = {at = i, kind = 'rare', name = 'entry'} end
ns.charDB.treasureLog = hugeLog
loadStart = os.clock(); T.LoadLog()
local hugeMS = (os.clock() - loadStart) * 1000
check(hugeMS < 20 and #T.Recent() == 50, '100000-entry saved table reads at most fifty entries within 20 ms')
print(('100000-entry saved table: %.3f ms'):format(hugeMS))
local badRecord = setmetatable({}, {__index = function() error('saved metamethod ran') end})
ns.charDB.treasureLog = {badRecord, secret, function() end, {at = 1, kind = 'rare', name = {}}}
check(pcall(T.LoadLog) and #T.Recent() == 0, 'non-plain saved records and non-string names rejected without metamethods')
ns.settings.treasureHunt = true
reset()
local hierarchyDB, originalBest = ns.DB, C_Map.GetBestMapForUnit
ns.DB = {ready = true, generation = hierarchyDB.generation + 1000, objects = {
 [1] = {name = 'Parent chest', chest = true, points = {{m = 18, x = .33, y = .4}}},
 [2] = {name = 'Child chest', chest = true, points = {{m = 5001, x = .6, y = .6}}},
 [3] = {name = 'Dungeon chest', chest = true, points = {{m = 291, x = .5, y = .5}}},
}, units = {}, Points = function(e) return e.points end, IsEnemy = function() return true end}
C_Map.GetBestMapForUnit = function() return 5001 end
local savedX, savedY, savedInst = M.player.wx, M.player.wy, M.player.inst
M.player.inst, M.player.wx, M.player.wy = 0, 10850, 1750
ns.settings.treasureKnownSpots = true
T.PickKnown(); ns.TabTreasure.Refresh()
check(#T.ZoneSpots(5001) == 2 and #ui.zone.items == 2 and T.Targets().spot ~= nil, 'child map offers reachable parent and child spots, excludes dungeon')
local known = T.Targets().spot
C_Map.GetBestMapForUnit = function() return 18 end
T.Scan(); T.PickKnown()
check(#T.ZoneSpots(18) == 2 and T.Targets().spot == known, 'parent-child transition retains same-zone suggestion')
C_Map.GetBestMapForUnit = originalBest
M.player.wx, M.player.wy, M.player.inst = savedX, savedY, savedInst
ns.DB = hierarchyDB
reset()
ns.settings.treasureFocus = false -- mirror reviewer's direct setting fixture
local ownFocus = WP.Add(map, .3, .3, {title = 'Own', silent = true})
local farFocus, nearFocus = guid(998007, 'far'), guid(998007, 'near')
marker(farFocus, 'Far', 'rare', .9, .9); marker(nearFocus, 'Near', 'rare', .51, .51); T.Scan()
local nearest, nearestD
for _, find in pairs(T.Targets()) do local d = G.GetVector(find); if d and (not nearestD or d < nearestD) then nearest, nearestD = find, d end end
ns.Set('treasureFocus', true)
check(nearest and WP.GetActive() == nearest.wp, 'enabling focus immediately selects nearest existing live find')
WP.SetActive(ownFocus, true); ns.Set('treasureFocus', true)
check(WP.GetActive() == ownFocus, 'writing unchanged focus setting does not refocus')
ns.Set('treasureFocus', false)
check(WP.GetActive() == ownFocus, 'disabling focus never moves arrow')
for _, state in ipairs({'dead', 'ghost'}) do
    M.player[state] = true; ns.Set('treasureFocus', true)
    check(WP.GetActive() == ownFocus, 'enabling focus preserves arrow while ' .. state)
    M.player[state] = false; ns.Set('treasureFocus', false)
end
reset()
T.SetOption('treasureFocus', false)
local onlyKnown = {key = 'spot', kind = 'spot', name = 'Suggestion', m = map, x = .8, y = .5}
T.Targets().spot = onlyKnown
ns.Set('treasureFocus', true)
check(not onlyKnown.wp and WP.GetActive() == nil, 'enabling focus does not point at known-only suggestion')
reset()
-- Guard public row data too: missing/invalid names must never reach comparisons/format.
T.Targets().badNameA = {key = 'badNameA', kind = 'chest', name = nil}
T.Targets().badNameB = {key = 'badNameB', kind = 'chest', name = {}}
check(pcall(ns.TabTreasure.Refresh), 'tab sort and row format accept nil and non-string names')
T.Targets().badNameA, T.Targets().badNameB = nil, nil
local labelOK, label = pcall(T.Label, nil)
check(labelOK and type(label) == 'string', 'Treasure.Label always supplies a string for missing data')
-- Sibling cases from the second boundary review.
reset()
local retainedKey = guid(2843, 'transient-name', true)
marker(retainedKey, 'Good name'); T.Scan()
local retained = T.Targets()[retainedKey]
M.vignettes[retainedKey].name = nil; T.Scan()
check(T.Targets()[retainedKey] == retained and not retained.log.outcome, 'transient missing marker name retains live target and log identity')
M.vignettes[retainedKey].name = '?'; T.Scan()
check(retained.name == 'Good name' and retained.log.name == 'Good name', 'placeholder never downgrades an already known name')
reset()
local hugeGUID = UnitGUID
UnitGUID = function() return string.rep('Creature-', 10000) end
M.units.target = {class = 'rare', reaction = 2}
check(pcall(T.Scan) and not next(T.Targets()), 'overlong unit GUID rejected before GUID patterns')
UnitGUID = hugeGUID
local utfName = T.Name and T.Name(string.rep('|r', 34) .. 'x' .. string.rep('é', 30))
check(utfName and utfName:byte(-1) ~= 195, 'raw name bound never leaves a split UTF-8 character')
for _, state in ipairs({'dead', 'ghost'}) do
    reset(); M.player[state] = true
    local deathAPI, unitDeadAPI = UnitIsDeadOrGhost, UnitIsDead
    UnitIsDeadOrGhost = nil
    -- wowmock's UnitIsDead only models NPC tokens; model the player here.
    UnitIsDead = function(token) if token == 'player' then return M.player.dead end; return unitDeadAPI(token) end
    marker(guid(998009, state), 'Visible while dead', 'rare'); T.Scan()
    check(T.Targets()[guid(998009, state)] and not WP.GetActive(), 'dead/ghost without combined API cannot acquire first treasure waypoint: ' .. state)
    M.player[state] = false; UnitIsDeadOrGhost, UnitIsDead = deathAPI, unitDeadAPI; T.Scan()
    check(T.Targets()[guid(998009, state)].wp ~= nil, 'positioned live target gains waypoint after resurrection: ' .. state)
end
-- Actual planner coverage is required even in the correctness suite; the
-- performance suite times 12 seconds each of moving and stationary goals.
reset()
local planningBest = C_Map.GetBestMapForUnit
C_Map.GetBestMapForUnit = function() return 1416 end
local planX, planY, planInst = M.player.wx, M.player.wy, M.player.inst
M.player.inst, M.player.wx, M.player.wy = G.MapToWorld(1416, .4, .5)
ns.settings.realRoutes, ns.settings.treasureFocus = true, true
local searches, terrainRefresh = 0, ns.Terrain.Refresh
ns.Terrain.Refresh = function(...) searches = searches + 1; return terrainRefresh(...) end
ns.Travel._Reset(); ns.Travel._SetSliced(true)
marker(guid(998008, 'planner'), 'Planner rare', 'rare', .6, .5); T.Scan()
for frame = 1, 10 do M.Tick(1 / 60, 1 / 60); ns.Travel.Steer(WP.GetActive()) end
check(searches > 0, 'Real routes regression pumps timers and executes actual planning searches')
ns.Terrain.Refresh = terrainRefresh
ns.settings.realRoutes = false; reset(); ns.Travel._Reset()
C_Map.GetBestMapForUnit = planningBest
M.player.wx, M.player.wy, M.player.inst = planX, planY, planInst
reset()
local infoAPI, optionalDB = C_Map.GetMapInfo, ns.DB
ns.DB = {ready = true, generation = optionalDB.generation + 3000, objects = {
    [1] = {name = 'Deferred hierarchy', chest = true, points = {{m = map, x = .8, y = .5}}},
}, units = {}, Points = function(e) return e.points end, IsEnemy = function() return true end}
C_Map.GetMapInfo = nil
local optionalOK, optionalList = pcall(T.ZoneSpots, map)
check(optionalOK and #optionalList == 0, 'missing map-info API defers zone index without poisoning its generation')
C_Map.GetMapInfo = infoAPI
check(#T.ZoneSpots(map) == 1 and #T.ZoneSpots(secret) == 0, 'zone index recovers when map-info API returns and rejects secret query map')
ns.DB = optionalDB
local orphanDB = ns.DB
for _, id in ipairs({6001, 6002}) do M.maps[id] = {mapID = id, name = 'Orphan ' .. id, mapType = 6, parentMapID = 13, cont = 0, top = 0, left = 0, w = 500, h = 500} end
ns.DB = {ready = true, generation = orphanDB.generation + 4000, objects = {}, units = {}, Points = function(e) return e.points end, IsEnemy = function() return true end}
for i, id in ipairs({6001, 6002, 13}) do ns.DB.objects[i] = {name = 'Separate area ' .. i, chest = true, points = {{m = id, x = .5, y = .5}}} end
check(#T.ZoneSpots(6001) == 1 and T.ZoneSpots(6001)[1].m == 6001, 'orphan maps without containing zone never merge siblings or continent points')
ns.DB = orphanDB
reset()
ns.charDB.treasureLog = {{at = 1000, kind = 'rare', name = 'Map label', m = 777777}}
T.LoadLog()
local mapNamespace = C_Map; C_Map = nil
check(pcall(ns.TabTreasure.Refresh) and ui.recent.rows[1].detail:GetText():find('#777777', 1, true), 'recent map label tolerates missing map namespace')
C_Map = mapNamespace
local mapInfoAPI = C_Map.GetMapInfo
for i, value in ipairs({secret, {name = secret}}) do
    ns.charDB.treasureLog = {{at = 1000, kind = 'rare', name = 'Map label', m = 777777 + i}}
    T.LoadLog(); C_Map.GetMapInfo = function() return value end
    check(pcall(ns.TabTreasure.Refresh) and ui.recent.rows[1].detail:GetText():find('#' .. (777777 + i), 1, true), 'recent map label rejects secret map info/name: ' .. i)
end
C_Map.GetMapInfo = mapInfoAPI
-- The stress fixture size is a contract, not an estimate from shipped data.
local stressDB = ns.DB
ns.DB = {ready = true, generation = stressDB.generation + 2000, objects = {}, units = {},
    Points = function(e) return e.points end, IsEnemy = function() return true end}
for i = 1, 200 do ns.DB.objects[i] = {name = 'Spot ' .. i, chest = true, points = {{m = map, x = .1 + (i % 19) * .04, y = .1 + math.floor(i / 19) * .05}}} end
ns.charDB.treasureLog = {}
for i = 1, 50 do ns.charDB.treasureLog[i] = {at = 1000, kind = 'rare', name = 'Recent ' .. i} end
T.LoadLog(); ns.TabTreasure.Refresh()
check(#ui.zone.items == 200 and #ui.recent.items == 50, 'stress fixture has exactly 200 zone spots and 50 recent finds')
ns.DB = stressDB
-- Reviewer's perf_coverage repro, in a fresh Lua process so its real modules,
-- settings and allocation fixtures cannot be contaminated by this suite.
-- os.tmpname() needs a writable /tmp; honour TMPDIR where one is given.
local function tmpName(tag)
    local dir = os.getenv('TMPDIR')
    if dir and dir ~= '' then
        return (dir:gsub('/+$', '')) .. '/wt_treasure_' .. tag .. '_' .. tostring(os.time()) .. '_' .. tostring(math.random(1e9))
    end
    return os.tmpname()
end
local coverageScript, coverageLog = tmpName('script'), tmpName('log')
local coverage = assert(io.open(coverageScript, 'w'))
coverage:write([=[
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local load, addon, searches = M.LoadAddon, nil, 0
M.LoadAddon = function(...)
    addon = load(...)
    local refresh = addon.Terrain.Refresh
    addon.Terrain.Refresh = function(...) searches = searches + 1; return refresh(...) end
    return addon
end
dofile('tests/run_treasure_perf.lua')
assert(searches > 0, 'performance harness executed zero real planning searches')
assert(#addon.Treasure.Recent() == 50 and #addon.TabTreasure.widgets.zone.items == 200, 'performance harness fixture must have 50 recent and 200 zone rows')
print('Coverage proof: searches=' .. searches .. ' log=50 zone=200')
]=])
coverage:close()
local function shellQuote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
local coverageLua = os.getenv('LUA51') or arg[-1] or 'lua5.1'
-- this run proves coverage (real searches, exact fixture); timing ceilings are run_treasure_perf's own job
local coverageResult = os.execute('WT_PERF_SLACK=20 ' .. shellQuote(coverageLua) .. ' ' .. shellQuote(coverageScript) .. ' > ' .. shellQuote(coverageLog) .. ' 2>&1')
local coverageOutput = assert(io.open(coverageLog)); local coverageText = coverageOutput:read('*a'); coverageOutput:close()
os.remove(coverageScript); os.remove(coverageLog)
check(coverageResult == 0 and coverageText:find('Coverage proof: searches=%d+ log=50 zone=200'), 'performance harness executes real searches with exact 50/200 fixture')
if coverageResult ~= 0 then print(coverageText) end
-- Window.lua has no resizing API: default and minimum are both 640 x 540,
-- with 442 px of content after inset/title/button-bar margins. Also check a
-- larger content area to prove the zone takes the surplus space.
for _, height in ipairs({442, 442, 500}) do
    ui.on:SetSize(618, height)
    ui.on:RunScript('OnSizeChanged', 618, height)
    local function top(f)
        if f == ui.on or f == ui.off then return 0 end
        local a = f.reviewPoints and (f.reviewPoints.TOPLEFT or f.reviewPoints.TOPRIGHT)
        if a then return top(a[1]) + (a[2]:find('BOTTOM', 1, true) and a[1]:GetHeight() or 0) - a[4] end
        a = f.reviewPoints and (f.reviewPoints.BOTTOMLEFT or f.reviewPoints.BOTTOMRIGHT)
        if a then return top(a[1]) + (a[2]:find('BOTTOM', 1, true) and a[1]:GetHeight() or 0) - a[4] - f:GetHeight() end
        return 0
    end
    for _, enabled in ipairs({false, true}) do
        ns.settings.treasureHunt = enabled; ns.TabTreasure.Refresh()
        check(ui.off.reviewAll == ui.on:GetParent() and ui.on.reviewAll == ui.on:GetParent()
            and ui.off:IsShown() ~= enabled and ui.on:IsShown() == enabled, 'off/on fills same content area: ' .. height .. '/' .. tostring(enabled))
        check(ui.nearby:GetHeight() >= 72 and ui.zone:GetHeight() >= 96 and ui.recent:GetHeight() >= 72,
            'list capacities at default/minimum content size: ' .. height .. '/' .. tostring(enabled))
        check(top(ui.nearby) >= 132 and top(ui.zone) >= top(ui.nearby) + ui.nearby:GetHeight() + 18
            and top(ui.recent) >= top(ui.zone) + ui.zone:GetHeight() + 18
            and top(ui.recent) + ui.recent:GetHeight() <= height - 4,
            'relative list anchors do not overlap or pass content bottom: ' .. height .. '/' .. tostring(enabled))
        check(ui.nearbyHeader and ui.zoneHeader and ui.recentHeader
            and ui.nearbyHeader.reviewPoints.TOPLEFT[1] == ui.options
            and ui.zoneHeader.reviewPoints.TOPLEFT[1] == ui.nearby
            and ui.recentHeader.reviewPoints.BOTTOMLEFT[1] == ui.recent, 'section anchors follow neighbouring sections: ' .. height .. '/' .. tostring(enabled))
        check(ui.nearby.scrollbar and ui.zone.scrollbar and ui.recent.scrollbar, 'all three lists scroll: ' .. height .. '/' .. tostring(enabled))
    end
    check(ui.zone:GetHeight() == height - 338, 'zone list uses remaining content height: ' .. height)
end
ns.settings.treasureHunt = true
-- Every option's single-line label fits 265 px: Latin/Cyrillic <=37 glyphs
-- at 7 px each, CJK/Hangul <=22 at 12 px. Width budget leaves 6/1 px slack.
for _, locale in ipairs({'enUS','deDE','ruRU','frFR','esES','ptBR','koKR','zhCN','zhTW'}) do
    local localeNS = {L = {}}
    local localeFn = assert(loadfile('WaypointTracker/Locales/' .. locale .. '.lua'))
    local priorLocale = GetLocale; GetLocale = function() return locale end
    localeFn('WaypointTracker', localeNS); GetLocale = priorLocale
    local within = true
    for _, k in ipairs({'TREASURE_CHESTS','TREASURE_RARES','TREASURE_OTHER','TREASURE_KNOWN','TREASURE_KNOWN_RARES','TREASURE_PING','TREASURE_FOCUS'}) do
        local text = localeNS.L[k]
        local _, chars = text:gsub('[^\128-\191]', '')
        if chars > ((locale == 'koKR' or locale == 'zhCN' or locale == 'zhTW') and 22 or 37) then within = false end
    end
    check(within, 'option label character budget: ' .. locale)
end

check(#M.errors == 0, 'no captured addon errors: ' .. tostring(M.errors[1]))
print(('%d passed, %d failed%s'):format(passed, failed, bare and ' (bare)' or ''))
os.exit(failed == 0 and 0 or 1)
