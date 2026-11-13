-- Exercise the real LoadOnDemand contract, rather than stubbing DB.Load.
package.path = './tests/?.lua;' .. package.path
local M = require('wowmock')
local bare = arg[1] == '--bare'
if bare then MenuUtil = nil end
local ns = M.LoadAddon('WaypointTracker','WaypointTracker')
M.FireEvent('ADDON_LOADED','WaypointTracker'); M.FireEvent('PLAYER_LOGIN')
local Find, DB, WP, L = ns.Find, ns.DB, ns.WP, ns.L
ns.Set('realRoutes',false)
UnitClass = function() return 'Mage','MAGE' end
local feedback
UIErrorsFrame = {AddMessage=function(_,text) feedback=text end}
local passed, failed = 0, 0
local function check(ok,text)
    if ok then passed=passed+1 else failed=failed+1; print('FAIL: '..text) end
end
local loader = C_AddOns.LoadAddOn
local function missing(text) check(feedback == L.DB_BROKEN,text..' database-missing feedback: '..tostring(feedback)) end
local function click(service, profession)
    WP.ClearAll(true); feedback=nil
    local wp = Find.GoToNearest(service,profession)
    check(not wp and not WP.GetActive(),service..' no fabricated waypoint')
    missing(service..' '..tostring(profession))
end
local function menu(root)
    local titles={}
    local target = root or {CreateTitle=function(_,text) titles[#titles+1]=text end,
        CreateButton=function() return {SetEnabled=function() end} end}
    feedback=nil; Find.ProfessionMenu(target)
    missing('profession menu')
    if not root then check(titles[2] == L.DB_BROKEN,'profession menu includes missing-database explanation') end
end
for _, mode in ipairs({'disabled','failed','throwing'}) do
    M.noDataAddon = mode == 'disabled'
    C_AddOns.LoadAddOn = mode == 'disabled' and function() return false,'DISABLED' end
        or mode == 'failed' and function() return false,'LOAD_FAILED' end
        or mode == 'throwing' and function() error('synthetic load error') end or loader
    for _, service in ipairs(Find.SERVICES) do
        if service.key == 'profession' then
            for _, p in ipairs(ns.Trainers.professions) do click('profession',p.key) end
        else click(service.key) end
    end
    check(not DB.hasShipped and not DB.loaded,'missing data remains retryable: '..mode)
    menu()
    if not bare then
        ns.QuickMenu.Show(UIParent)
        for _, item in ipairs(M.lastMenu.items) do
            if item.text == L.NEAREST_MENU then
                -- Every direct quick-menu action and the lazy profession submenu.
                for _, action in ipairs(item.items) do
                    if action.onEnter then feedback=nil; action.onEnter(); missing('quick profession submenu')
                    elseif action.fn then feedback=nil; action.fn(); missing('quick '..action.text) end
                end
            end
        end
    end
end
-- Missing shipped data still permits a measured personal discovery.
ns.Learn.Import('WTL1\tenUS\t1\nN\t993001\tLocal teacher\t0\t60\ttrainer_class_mage,trainer_profession_alchemy,vendor\t37:500,500\tA')
ns.Fire('LEARNED')
for _, choice in ipairs({{'class'},{'profession','alchemy'},{'vendor'}}) do
    WP.ClearAll(true); feedback=nil
    check(Find.GoToNearest(choice[1],choice[2]) ~= nil,'local discovery usable without shipped data: '..choice[1])
    check(feedback ~= L.DB_BROKEN,'local discovery success feedback')
end
-- Bare picker reports the same explanation on interaction.
if bare then
    Find.Show(); ns.Window.Hide(); ns.Window.Show('find')
    local picker=Find.widgets.nearest.profession
    picker.next:Click()
    check(ns.Window.frame.status:GetText() == L.DB_BROKEN,'bare picker database-missing explanation')
end
-- Retry after enabling/recovering, through the real loader.
M.noDataAddon=false; C_AddOns.LoadAddOn=loader
local ok,reason=DB.Load()
check(ok and reason == nil and DB.hasShipped and DB.loaded,'loader recovers without reload')
check(#DB.TrainerEntries('trainer_class_mage') > 0,'shipped trainers available after recovery')
check(#M.errors == 0,'no captured loader errors')
print(('Nearest loader%s: %d passed, %d failed'):format(bare and ' (bare)' or '',passed,failed))
os.exit(failed == 0 and 0 or 1)
