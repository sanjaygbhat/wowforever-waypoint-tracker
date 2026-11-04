-- Follow owns disposable quest/corpse pins, even at a user's saved spot.
package.path = 'tests/?.lua;' .. package.path
local M = require('wowmock')
local ns = M.LoadAddon('WaypointTracker', 'WaypointTracker')
M.FireEvent('ADDON_LOADED', 'WaypointTracker'); M.FireEvent('PLAYER_LOGIN'); M.Tick(1)
local WP = ns.WP
local callback = function() end
local callbacks = { distance = { [50] = callback } }
local original = assert(WP.Add(37, .39, .82, {title=M.quests[1].title, silent=true, callbacks=callbacks}))
original.routeID, original.routeStep = 'saved-route', 3
local function preserved()
    assert(WP.IsValid(original) and original.persistent and original.source == 'user', 'user waypoint remains owned and persistent')
    assert(original.callbacks == callbacks and original.routeID == 'saved-route' and original.routeStep == 3, 'user route and callbacks unchanged')
    local saved = false
    for _, wp in ipairs(ns.charDB.waypoints) do
        if wp.title == original.title and wp.x == original.x and wp.y == original.y then saved = true end
    end
    assert(saved, 'user waypoint remains in SavedVariables')
end
local quest = assert(ns.Follow.TrackQuest(101))
assert(quest ~= original and not quest.persistent and quest.source == 'quest', 'explicit tracking creates an owned ephemeral pin')
M.FireEvent('QUEST_TURNED_IN', 101)
assert(not WP.IsValid(quest), 'turned-in quest pin removed'); preserved()
-- Replacement at the same authored location must not adopt the persistent pin.
quest = assert(ns.Follow.TrackQuest(101))
M.quests[1].onMap[37] = {.44, .82}
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(.7)
assert(not WP.IsValid(quest) and WP.GetActive().x == .44, 'moving quest replaces only its own pin'); preserved()
M.quests[1].onMap[37] = {.39, .82}
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(.7)
quest = WP.GetActive()
assert(quest ~= original and quest.source == 'quest', 'returning quest still cannot borrow user pin')
table.remove(M.quests, 1)
M.FireEvent('QUEST_LOG_UPDATE'); M.Tick(.7)
assert(not WP.IsValid(quest), 'abandoned quest pin removed'); preserved()
-- Automatic super-tracking uses the same ownership boundary.
M.quests = {{id=101, title=original.title, onMap={[37]={.39,.82}}}}
M.superTracked = 101
ns.Set('followQuest', true)
M.FireEvent('SUPER_TRACKING_CHANGED'); M.Tick(.7)
quest = WP.GetActive()
assert(quest ~= original and quest.source == 'quest', 'automatic tracking owns its waypoint')
ns.Set('followQuest', false); M.Tick(.7)
assert(not WP.IsValid(quest), 'automatic quest untracking removes only its pin'); preserved()
assert(WP.Add(37, .39, .82, {title=original.title, silent=true}) == original, 'normal waypoint deduplication still works')
-- Corpse navigation also removes its temporary object on resurrection.
local m, x, y = ns.Geo.GetPlayerMapPosition()
local corpseNamed = WP.Add(m, x, y, {title=ns.L.CORPSE_NAME, silent=true, setActive=false})
WP.SetActive(original, true)
M.player.dead = true; M.FireEvent('PLAYER_DEAD')
local corpse = WP.GetActive()
assert(corpse ~= corpseNamed and corpse.source == 'corpse' and not corpse.persistent, 'corpse navigation owns a separate pin')
M.player.dead = false; M.FireEvent('PLAYER_UNGHOST')
assert(not WP.IsValid(corpse) and WP.IsValid(corpseNamed) and corpseNamed.persistent, 'resurrection preserves same-named saved pin')
assert(WP.GetActive() == original, 'resurrection restores prior selection'); preserved()
assert(#M.errors == 0, tostring(M.errors[1]))
print('PASS: click/automatic tracking, moving/abandoned/turned-in quests and corpse ownership')
