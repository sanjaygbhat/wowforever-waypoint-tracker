-- The Find database read a little each frame (DB.LoadAsync), as the game
-- client does it: nothing is ready until all of it is, the window's status
-- line says how far the load is, and whatever was asked for meanwhile (a
-- search, a Nearest button, "/way <name>", the Routes tab) is answered once
-- it is ready. Also: the shared empty ID list is never written.
-- (That the database comes out the same as read all at once is
-- tests/run_db_equivalence.lua.) Run from the repository root:
--     lua5.1 tests/run_db_sliced.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. tostring(msg)) end
end

local feedback = {}
UIErrorsFrame = { AddMessage = function(_, text) feedback[#feedback + 1] = text end }
function UnitFactionGroup() return "Alliance" end
WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local Find, Window, DB, WP, L = ns.Find, ns.Window, ns.DB, ns.WP, ns.L
ns.settings.learn = false
M.player.wx, M.player.wy, M.player.inst = -9460, 62, 0 -- Goldshire

-- the loading line for any share: the translated text with a number in it
local LOADING = "^" .. L.DB_LOADING:gsub("%%d%%%%", "\1"):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"):gsub("\1", "%%d+%%%%") .. "$"
local function IsLoadingLine(text)
    return type(text) == "string" and text:find(LOADING) ~= nil
end
check(IsLoadingLine(L.DB_LOADING:format(37)) and not IsLoadingLine(L.DB_BROKEN), "the loading line is recognised")

check(DB.Sliced() == false, "without a frame clock (this mock) the database loads all at once")
DB._SetSliced(true)
check(DB.Sliced() == true, "tests can ask for loading a slice a frame")

local shares, loadedEvents = {}, {}
ns.On("DB_LOADING", function(share) shares[#shares + 1] = share end)
ns.On("DB_LOADED", function(ok, why) loadedEvents[#loadedEvents + 1] = { ok, why } end)

local function Frame()
    M.Tick(1 / 60, 1 / 60)
end
-- Frames until the load has finished (DB_LOADED), at most `most`.
local function UntilLoaded(most)
    local before, frames = #loadedEvents, 0
    while #loadedEvents == before and frames < (most or 20000) do
        Frame()
        frames = frames + 1
    end
    return frames
end

-- Forgets the database, as after a /reload.
local function Reset()
    for _, name in ipairs({ "units", "objects", "quests", "items", "services", "places", "marks" }) do
        for k in pairs(DB[name]) do DB[name][k] = nil end
    end
    DB.loaded, DB.ready, DB.hasShipped, DB.curated, DB.community, DB.loadStats = false, nil, nil, nil, nil, nil
    DB.zoneNames, DB.foreverQuests = nil, nil
    WaypointTrackerData = nil
    shares, loadedEvents, feedback = {}, {}, {}
    WP.ClearAll(true)
end

-- ---------------------------------------------------------------------------
-- 1. A search typed while the database loads
-- ---------------------------------------------------------------------------
Find.Show()
local fw = Find.widgets
fw.list:SetSize(276, 308)
fw.list:RunScript("OnSizeChanged")
fw.search:Type("hogger")
M.Tick(0.3)
check(DB.Loading() ~= nil and not DB.ready and not DB.loaded, "a search starts the load and nothing is ready yet")
check(IsLoadingLine(fw.empty:GetText()) and fw.empty:IsShown(), "the list says the database is loading: " .. tostring(fw.empty:GetText()))
check(IsLoadingLine(Window.frame.status:GetText()), "the status line says so too: " .. tostring(Window.frame.status:GetText()))
check(not fw.rows[1]:IsShown(), "no results while loading")
local first = Window.frame.status:GetText()
local sawReady, statusChanged, statusAlwaysLoading = false, false, true
local frames, before = 0, #loadedEvents
while #loadedEvents == before and frames < 20000 do
    Frame()
    frames = frames + 1
    if #loadedEvents == before then
        if DB.ready or DB.loaded then sawReady = true end
        local text = Window.frame.status:GetText()
        if text ~= first then statusChanged = true end
        if not IsLoadingLine(text) then statusAlwaysLoading = false end
    end
end
local normalFrames = frames
check(#loadedEvents == 1 and loadedEvents[1][1] == true and loadedEvents[1][2] == nil, "the load finishes once, well")
check(frames > 100, "the load is spread over many frames (" .. frames .. ")")
check(not sawReady, "the database never says ready before all of it is")
check(statusChanged and statusAlwaysLoading, "the status line follows the load")
local rising, top = true, 0
for i, share in ipairs(shares) do
    if share < top or share > 0.99 then rising = false end
    top = share
end
check(#shares > 100 and rising and shares[1] == 0, "the share done only rises and stops short of 100% (" .. top .. ")")
check(top > 0.8, "the share is near the end when the load finishes (" .. top .. ")")
check(DB.ready and DB.loaded and DB.hasShipped and DB.Loading() == nil, "then the database is ready")
check(fw.rows[1]:IsShown() and fw.rows[1].entry and fw.rows[1].entry.name == "Hogger", "the search that was typed has run by itself")
check(not fw.empty:IsShown(), "the loading line has left the list")
check(Window.frame.status:GetText() == "", "the status line is cleared: " .. tostring(Window.frame.status:GetText()))
local stats = DB.loadStats
check(type(stats) == "table" and stats.slices >= frames and stats.slices <= frames + 30 and stats.units > 100000, "the load keeps its figures")
check(stats and stats.most <= 900, "no slice reads much more than its share (" .. tostring(stats and stats.most) .. " rows)")
check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))
-- asking again is answered at once, without the callback
local called = false
local ok, why = DB.LoadAsync(function() called = true end)
check(ok == true and why == nil and not called, "a ready database answers at once")
Frame()
check(not called and #loadedEvents == 1, "and says nothing more later")
local everything = 0
for _, name in ipairs({ "units", "objects", "quests", "items" }) do
    for _ in pairs(DB[name]) do everything = everything + 1 end
end

-- ---------------------------------------------------------------------------
-- 2. Nearest clicked while it loads: the last click is answered when ready
-- ---------------------------------------------------------------------------
Window.Hide()
WP.ClearAll(true)
local expected = Find.GoToNearest("mailbox")
check(expected ~= nil, "a mailbox is found with the database ready")
local ex = expected and { expected.mapID, expected.x, expected.y, expected.title }
Reset()
check(Find.GoToNearest("innkeeper") == nil and Find.GoToNearest("mailbox") == nil, "Nearest answers later while loading")
check(#feedback == 2 and IsLoadingLine(feedback[1]) and IsLoadingLine(feedback[2]), "each click is told the database is loading")
check(WP.Count() == 0, "no waypoint yet")
UntilLoaded()
local got = WP.GetActive()
check(WP.Count() == 1 and got and ex and got.mapID == ex[1] and got.x == ex[2] and got.y == ex[3] and got.title == ex[4],
    "once ready the arrow goes to the last one asked for, only: " .. tostring(got and got.title))
check(#feedback == 3 and not IsLoadingLine(feedback[3]), "and says so")
check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))

-- ---------------------------------------------------------------------------
-- 3. /way <name> while it loads
-- ---------------------------------------------------------------------------
WP.ClearAll(true)
local direct = Find.Way("Hogger")
local dx = direct and { direct.mapID, direct.x, direct.y }
check(direct ~= nil, "/way Hogger sets the arrow with the database ready")
Window.Hide()
Reset()
SlashCmdList.WAYPOINTTRACKERWAY("Hogger")
check(WP.Count() == 0 and DB.Loading() ~= nil, "/way <name> waits for the database")
UntilLoaded()
got = WP.GetActive()
check(WP.Count() == 1 and got and dx and got.mapID == dx[1] and got.x == dx[2] and got.y == dx[3], "and sets the arrow once it is ready")
check(not Window.IsShown(), "without opening the window")

-- ---------------------------------------------------------------------------
-- 4. DB.Load() while it loads: the rest at once
-- ---------------------------------------------------------------------------
Reset()
local answers = {}
check(DB.LoadAsync(function(ok, why) answers[#answers + 1] = { ok, why } end) == nil, "a load starts")
DB.LoadAsync(function(ok, why) answers[#answers + 1] = { ok, why } end)
for _ = 1, 10 do Frame() end
check(#answers == 0 and not DB.ready, "under way")
ok, why = DB.Load()
check(ok == true and why == nil and DB.ready and DB.loaded and DB.Loading() == nil, "DB.Load finishes it at once")
check(#answers == 2 and answers[1][1] == true and answers[2][1] == true and #loadedEvents == 1, "everyone waiting is told, once")
for _ = 1, 5 do Frame() end
check(#answers == 2 and #loadedEvents == 1, "and not again")
local count = 0
for _, name in ipairs({ "units", "objects", "quests", "items" }) do
    for _ in pairs(DB[name]) do count = count + 1 end
end
check(count == everything, "with everything in it (" .. count .. " of " .. everything .. ")")

-- ---------------------------------------------------------------------------
-- 5. In combat the slices are smaller
-- ---------------------------------------------------------------------------
Reset()
M.player.combat = true
check(DB.LoadAsync() == nil, "a load starts in combat")
local combatFrames = UntilLoaded(100000)
M.player.combat = false
check(DB.ready and combatFrames > normalFrames * 2.5, "in combat a slice is a fraction of the usual (" .. combatFrames .. " frames against " .. normalFrames .. ")")
check(DB.loadStats and DB.loadStats.most <= 300, "no combat slice reads much more than its share (" .. tostring(DB.loadStats and DB.loadStats.most) .. " rows)")

-- ---------------------------------------------------------------------------
-- 6. The Routes tab asks for the database too
-- ---------------------------------------------------------------------------
Reset()
Window.Show() -- (on Find, whose search starts the load and says so)
Window.ShowTab("routes") -- (which empties the status line)
Frame()
check(DB.Loading() ~= nil, "opening the window starts the load")
check(IsLoadingLine(Window.frame.status:GetText()), "the status line says the database is loading: " .. tostring(Window.frame.status:GetText()))
UntilLoaded()
check(DB.ready and #ns.Routes.Suggested() > 0, "the suggested routes are there once it is ready")
check(Window.frame.status:GetText() == "", "and the status line is cleared")
check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))

-- ---------------------------------------------------------------------------
-- 7. Without the database folder
-- ---------------------------------------------------------------------------
Reset()
M.noDataAddon = true
Window.ShowTab("find")
fw.search:Type("hogger")
M.Tick(0.3)
for _ = 1, 20 do Frame() end
check(fw.empty:IsShown() and fw.empty:GetText() == L.DB_MISSING, "a missing database folder is explained: " .. tostring(fw.empty:GetText()))
called = false
ok, why = DB.LoadAsync(function() called = true end)
check(ok == true and why == "missing" and not called and DB.Loading() == nil, "and asked for again it answers at once")

-- ---------------------------------------------------------------------------
-- 8. A database that cannot be read
-- ---------------------------------------------------------------------------
Reset()
M.noDataAddon = false
local loader, loads = C_AddOns.LoadAddOn, 0
C_AddOns.LoadAddOn = function(name)
    local a, b = loader(name)
    loads = loads + 1
    WaypointTrackerData.raw.units = 5 -- not text
    return a, b
end
fw.search:Type("hogge")
M.Tick(0.3)
local broken = UntilLoaded()
check(broken < 20000 and loadedEvents[1] and loadedEvents[1][1] == false and loadedEvents[1][2] == "broken", "a database that cannot be read ends the load")
check(fw.empty:IsShown() and fw.empty:GetText() == L.DB_BROKEN, "the list says so: " .. tostring(fw.empty:GetText()))
check(#M.errors == 1, "the error is reported once (" .. #M.errors .. ")")
check(DB.Loading() == nil and not DB.loaded, "nothing keeps running")
for _ = 1, 30 do Frame() end
check(loads == 1 and #loadedEvents == 1, "and nothing tries again by itself")
fw.search:Type("hogg")
M.Tick(0.3)
UntilLoaded()
check(fw.empty:GetText() == L.DB_BROKEN and loads == 1 and #M.errors == 1, "another search says the same, without reading the files again")
C_AddOns.LoadAddOn = loader
M.errors = {}

-- ---------------------------------------------------------------------------
-- 9. The shared empty ID list
-- ---------------------------------------------------------------------------
Reset()
DB._SetSliced(false)
WaypointTrackerDB.learned = nil
ok = DB.Load()
check(ok == true and DB.ready, "the database loads all at once")
-- the shipped stores are kept as what a merge needs of them, not whole
local kept = 0
for _, source in ipairs({ "curated", "community" }) do
    for _, kind in ipairs({ "npcs", "objects", "quests", "items" }) do
        for _ in pairs(DB[source][kind] or {}) do kept = kept + 1 end
    end
end
check(kept > 0 and kept < 3000, "only the shipped records that wait for something are kept whole (" .. kept .. ")")
local FIELDS = { quests = { "startU", "startO", "endU", "endO", "objU", "objO", "objI" }, items = { "dropU", "dropO", "soldBy" } }
local function Lists()
    local shared, own, emptyOwn = 0, 0, 0
    for name, fields in pairs(FIELDS) do
        for _, e in pairs(DB[name]) do
            for _, field in ipairs(fields) do
                local list = e[field]
                if list == DB.NO_IDS then
                    shared = shared + 1
                elseif type(list) == "table" then
                    own = own + 1
                    if #list == 0 then emptyOwn = emptyOwn + 1 end
                end
            end
        end
    end
    return shared, own, emptyOwn
end
local shared, own, emptyOwn = Lists()
check(shared > 40000, "most empty lists are the one shared list (" .. shared .. ")")
check(own > 15000 and emptyOwn == 0, "and no entry keeps an empty list of its own (" .. emptyOwn .. " of " .. own .. ")")
check(next(DB.NO_IDS) == nil and #DB.NO_IDS == 0, "the shared list is empty")
check(not pcall(function() DB.NO_IDS[1] = 5 end), "writing to it is an error")
check(not pcall(function() DB.NO_IDS[#DB.NO_IDS + 1] = 5 end), "appending to it is an error")
check(not pcall(function() DB.NO_IDS.x = 5 end), "naming a field in it is an error")
check(next(DB.NO_IDS) == nil, "and it is still empty")
-- discoveries give an entry a list of its own
local bare
for id, q in pairs(DB.quests) do
    if q.startU == DB.NO_IDS and q.endU == DB.NO_IDS and q.objU == DB.NO_IDS and q.objI == DB.NO_IDS and (not bare or id < bare) then bare = id end
end
local item
for id, e in pairs(DB.items) do
    if e.dropU == DB.NO_IDS and e.dropO == DB.NO_IDS and e.soldBy == DB.NO_IDS and (not item or id < item) then item = id end
end
check(bare and item, "a quest and an item with shared lists")
local st = ns.Learn.Store()
st.npcs[990001] = { name = "Seen only here", spots = { [37] = { 0.5, 0.5 } } }
st.quests[bare] = { giver = "U990001", needs = { "U990001", "I" .. item } }
st.items[item] = { from = { U990001 = true }, sold = { U990001 = true } }
DB.MergeLearned()
local q, e = DB.quests[bare], DB.items[item]
check(q.startU ~= DB.NO_IDS and q.startU[1] == 990001 and q.objU[1] == 990001 and q.objI[1] == item, "a discovery gives the quest lists of its own")
check(e.dropU ~= DB.NO_IDS and e.dropU[1] == 990001 and e.soldBy[1] == 990001, "and the item")
check(q.endU == DB.NO_IDS and e.dropO == DB.NO_IDS, "its other lists stay the shared one")
check(next(DB.NO_IDS) == nil, "the shared list is still empty")
-- using the database leaves it empty
Window.Show()
Window.ShowTab("find")
for _, text in ipairs({ "hogger", "linen cloth", "kobold", "the", "a" }) do
    fw.search:Type(text)
    M.Tick(0.3)
    if fw.rows[1]:IsShown() then fw.rows[1]:Click() end
end
for id, quest in pairs(DB.quests) do
    if id % 7 == 0 then DB.QuestTargets(quest) end
end
ns.Routes.Suggested()
Find.GoToNearest("mailbox")
check(next(DB.NO_IDS) == nil and #DB.NO_IDS == 0, "searching, quest targets, routes and Nearest never write to it")
check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))

print(("Database a slice a frame: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
