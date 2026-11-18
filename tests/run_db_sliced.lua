-- The Find database read a little each frame (DB.LoadAsync), as the game
-- client does it: nothing is ready until all of it is, the window's status
-- line says how far the load is (where nothing else is said), and whatever
-- was asked for meanwhile (a search, a Nearest button, "/way <name>", the
-- Routes tab) is answered once it is ready. Slices by a frame clock, at
-- several frame rates and in combat. A shipped store that cannot be read,
-- with the data addon's files read once a session as the game does. The
-- database asked for from inside its own load. Also: the shared empty ID
-- list is never written.
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

-- "--share" (run by this test itself in another language): only how far
-- the share done gets, with the data as shipped
if arg and arg[1] == "--share" then
    function UnitFactionGroup() return "Alliance" end
    local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
    M.FireEvent("ADDON_LOADED", "WaypointTracker")
    M.FireEvent("PLAYER_LOGIN")
    ns.settings.learn = false
    ns.DB._SetSliced(true)
    local done
    assert(ns.DB.LoadAsync(function(ok) done = ok end) == nil)
    local frames, share, held = 0, 0, 0
    while done == nil and frames < 100000 do
        M.Tick(1 / 60, 1 / 60)
        frames = frames + 1
        share = ns.DB.Loading() or share
        if ns.DB.Loading() == 0.99 then held = held + 1 end
    end
    local good = done == true and share > 0.93 and share <= 0.99 and held <= frames * 0.03
    print(("%s: the share done ends at %.3f, %d of %d frames at its last value"):format(GetLocale(), share, held, frames))
    os.exit(good and 0 or 1)
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
    M.addonsLoaded["WaypointTracker_Data"] = nil
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
-- (the first visit's tip is in the status line: the list says it instead)
check(Window.frame.status:GetText() == L.DB_NOTE, "the status line keeps what it said: " .. tostring(Window.frame.status:GetText()))
check(not fw.rows[1]:IsShown(), "no results while loading")
local firstList = fw.empty:GetText()
local sawReady, listChanged, listAlwaysLoading, tipKept = false, false, true, true
local frames, before = 0, #loadedEvents
while #loadedEvents == before and frames < 20000 do
    Frame()
    frames = frames + 1
    if #loadedEvents == before then
        if DB.ready or DB.loaded then sawReady = true end
        local text = fw.empty:GetText()
        if text ~= firstList then listChanged = true end
        if not IsLoadingLine(text) then listAlwaysLoading = false end
        if Window.frame.status:GetText() ~= L.DB_NOTE then tipKept = false end
    end
end
local normalFrames = frames
check(#loadedEvents == 1 and loadedEvents[1][1] == true and loadedEvents[1][2] == nil, "the load finishes once, well")
check(frames > 100, "the load is spread over many frames (" .. frames .. ")")
check(not sawReady, "the database never says ready before all of it is")
check(listChanged and listAlwaysLoading, "the list's line follows the load")
check(tipKept and Window.frame.status:GetText() == L.DB_NOTE, "and the status line is never taken from what it said")
local rising, top = true, 0
for i, share in ipairs(shares) do
    if share < top or share > 0.99 then rising = false end
    top = share
end
check(#shares > 100 and rising and shares[1] == 0, "the share done only rises and stops short of 100% (" .. top .. ")")
check(top > 0.93, "the share is near the end when the load finishes (" .. top .. ")")
-- in a language that also reads the English names (more rows) it gets as far
do
    local lua = arg and arg[-1] or "lua5.1"
    local status = os.execute(("WT_LOCALE=deDE '%s' tests/run_db_sliced.lua --share"):format(lua:gsub("'", "'\\''")))
    check(status == 0 or status == true, "in another language the share done is as near the end, and does not wait there")
end
check(DB.ready and DB.loaded and DB.hasShipped and DB.Loading() == nil, "then the database is ready")
check(fw.rows[1]:IsShown() and fw.rows[1].entry and fw.rows[1].entry.name == "Hogger", "the search that was typed has run by itself")
check(not fw.empty:IsShown(), "the loading line has left the list")
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
-- 1b. The status line: ours while it shows the loading line, and only then
-- ---------------------------------------------------------------------------
Reset()
Window.SetStatus("")
fw.search:Type("hogge")
M.Tick(0.3)
check(IsLoadingLine(Window.frame.status:GetText()), "an empty status line says the database is loading: " .. tostring(Window.frame.status:GetText()))
local firstStatus, statusChanged, statusAlwaysLoading = Window.frame.status:GetText(), false, true
for _ = 1, 60 do
    Frame()
    local text = Window.frame.status:GetText()
    if text ~= firstStatus then statusChanged = true end
    if not IsLoadingLine(text) then statusAlwaysLoading = false end
end
check(DB.Loading() and statusChanged and statusAlwaysLoading, "and follows the load")
Window.SetStatus("Something else was said", true)
local kept = true
before = #loadedEvents
while #loadedEvents == before do
    Frame()
    if Window.frame.status:GetText() ~= "Something else was said" then kept = false end
end
check(kept and Window.frame.status:GetText() == "Something else was said", "what is said meanwhile stays, also when the load has finished")
Reset()
Window.SetStatus("")
fw.search:Type("hogger")
M.Tick(0.3)
UntilLoaded()
check(Window.frame.status:GetText() == "", "a loading line still there at the end is cleared: " .. tostring(Window.frame.status:GetText()))
-- the window opened while a load runs that it did not ask for
Window.Hide()
Reset()
check(DB.LoadAsync() == nil, "a load starts with the window closed")
for _ = 1, 5 do Frame() end
Window.Show("waypoints")
Window.SetStatus("Waypoint added: somewhere", true)
kept = true
before = #loadedEvents
while #loadedEvents == before do
    Frame()
    if Window.frame.status:GetText() ~= "Waypoint added: somewhere" then kept = false end
end
check(kept, "the window opened meanwhile keeps its own status line")
check(#feedback == 0, "and nothing is said on screen for a load nobody asked for by a click (" .. #feedback .. ")")
Window.ShowTab("find")

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
-- the arrow sent somewhere else since the click stays there
Reset()
check(Find.GoToNearest("mailbox") == nil, "Nearest waits again")
local mine = WP.Add(37, 0.5, 0.5, { title = "Set after the click" })
WP.SetActive(mine)
check(WP.GetActive() == mine, "a waypoint is set meanwhile")
UntilLoaded()
check(WP.Count() == 1 and WP.GetActive() == mine, "the click from before it is dropped")
check(#feedback == 1, "without a word (" .. #feedback .. ")")
-- the profession menu, built when the pointer comes over its entry
Reset()
local titles, buttons = {}, {}
local root = {
    CreateTitle = function(_, text) titles[#titles + 1] = text end,
    CreateButton = function(_, text, fn) buttons[#buttons + 1] = fn; return {} end,
}
Find.ProfessionMenu(root)
check(DB.Loading() ~= nil and IsLoadingLine(titles[#titles]), "the profession menu starts the load and says so in the menu")
check(#feedback == 0, "and not on screen: nothing was clicked (" .. #feedback .. ")")
check(#buttons > 0 and buttons[1] ~= nil, "every profession can be chosen meanwhile")
buttons[1]()
check(#feedback == 1 and IsLoadingLine(feedback[1]), "a click is told the database is loading")
UntilLoaded()
check(#feedback == 2 and not IsLoadingLine(feedback[2]), "and answered once it is ready: " .. tostring(feedback[2]))
check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))

-- ---------------------------------------------------------------------------
-- 3. /way <name> while it loads
-- ---------------------------------------------------------------------------
local way = SlashCmdList.WAYPOINTTRACKERWAY
WP.ClearAll(true)
local direct = Find.Way("Hogger")
local dx = direct and { direct.mapID, direct.x, direct.y }
check(direct ~= nil, "/way Hogger sets the arrow with the database ready")
-- another name that is one thing only
local other, ox
for _, name in ipairs({ "Marshal Dughan", "Brog Hamfist", "Brother Danil", "Tharynn Bouden" }) do
    WP.ClearAll(true)
    Window.Hide()
    local wp = Find.Way(name)
    if wp then other, ox = name, { wp.mapID, wp.x, wp.y } break end
end
check(other ~= nil, "another name is one thing only")
Window.Hide()
Reset()
M.printed = {}
way(other)
way("Hogger")
check(WP.Count() == 0 and DB.Loading() ~= nil, "/way <name> waits for the database")
check(#feedback == 2 and IsLoadingLine(feedback[1]), "and says it is loading")
UntilLoaded()
got = WP.GetActive()
check(WP.Count() == 1 and got and dx and got.mapID == dx[1] and got.x == dx[2] and got.y == dx[3], "the last one asked for sets the arrow once it is ready, only")
check(not Window.IsShown(), "without opening the window")
check(#feedback == 3 and feedback[3] == L.ADDED:format(WP.Describe(got)) and #M.printed == 0, "said on screen, not in chat: " .. tostring(feedback[3]))
-- a name to choose from, asked for with the window closed: Find opens, as at once
Reset()
way("kobold")
UntilLoaded()
check(Window.IsShown() and Window.GetTab() == "find" and fw.search:GetText() == "kobold", "a name to choose from opens Find when the window is as it was")
check(WP.Count() == 0, "and sets nothing")
-- the window closed meanwhile stays closed
Reset()
Window.Show("waypoints")
way("kobold")
for _ = 1, 5 do Frame() end
Window.Hide()
feedback = {}
UntilLoaded()
check(not Window.IsShown(), "the window closed since stays closed")
check(#feedback == 1 and feedback[1] == L.WAY_SEARCH:format("kobold"), "and the answer is said on screen: " .. tostring(feedback[1]))
-- another tab opened meanwhile stays open
Reset()
Window.Show("waypoints")
way("kobold")
for _ = 1, 5 do Frame() end
Window.ShowTab("treasure")
UntilLoaded()
check(Window.IsShown() and Window.GetTab() == "treasure", "another tab opened since stays open")
check(Window.frame.status:GetText() == L.WAY_SEARCH:format("kobold"), "and the answer is in the status line: " .. tostring(Window.frame.status:GetText()))
-- one thing only: the arrow, whatever the window did
Reset()
Window.ShowTab("waypoints")
way("Hogger")
for _ = 1, 5 do Frame() end
Window.Hide()
UntilLoaded()
check(WP.Count() == 1 and not Window.IsShown(), "one thing only still gets its arrow with the window closed since")
check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))

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

-- DB.Load asked for from inside the load itself (a mistake: but it must
-- neither hang nor start another), a slice a frame and all at once
local isChest = ns.Treasure.IsChestName
for _, sliced in ipairs({ true, false }) do
    Reset()
    DB._SetSliced(sliced)
    local inside
    ns.Treasure.IsChestName = function(name)
        if not inside then
            inside = { DB.Load() }
            inside[3], inside[4] = DB.LoadAsync(function() inside.called = (inside.called or 0) + 1 end)
        end
        return isChest(name)
    end
    local how = sliced and "a slice a frame" or "all at once"
    if sliced then
        check(DB.LoadAsync() == nil, "a load starts")
        check(UntilLoaded() < 20000, how .. ": the load finishes")
    else
        check(DB.Load() == true, how .. ": the load finishes")
    end
    check(inside and inside[1] == false and inside[2] == "loading", how .. ": DB.Load from inside the load answers that it is loading: " .. tostring(inside and inside[2]))
    if sliced then
        check(inside[3] == nil and inside.called == 1, how .. ": DB.LoadAsync from inside waits like anyone else")
    else
        check(inside[3] == false and inside[4] == "loading" and not inside.called, how .. ": DB.LoadAsync from inside answers the same")
    end
    count = 0
    for _, name in ipairs({ "units", "objects", "quests", "items" }) do
        for _ in pairs(DB[name]) do count = count + 1 end
    end
    check(DB.loaded and DB.ready and count == everything, how .. ": with everything in it, once (" .. count .. ")")
    ns.Treasure.IsChestName = isChest
end
DB._SetSliced(true)
-- the load's first announcement leads to DB.Load: whoever started it is still told
Reset()
local finishAtOnce = true
ns.On("DB_LOADING", function(share)
    if finishAtOnce and share == 0 then
        finishAtOnce = false
        DB.Load()
    end
end)
answers = {}
ok = DB.LoadAsync(function(a, b) answers[#answers + 1] = { a, b } end)
check(ok == nil and #answers == 1 and answers[1][1] == true and DB.loaded, "a load finished by its own first announcement still answers who started it, once")
for _ = 1, 5 do Frame() end
check(#answers == 1 and #loadedEvents == 1, "and not again")
check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))

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
-- 5b. By the frame clock, as in the game: a slice is a share of what the
-- rest of the frame took, at most 8 ms and at least 3; 2 ms in combat
-- ---------------------------------------------------------------------------
DB._SetSliced(nil)
check(DB.Sliced() == false, "left to the client, this mock loads all at once")
local clock = 0
function debugprofilestop() -- every look at it takes a fifth of a millisecond
    clock = clock + 0.2
    return clock
end
check(DB.Sliced() == true, "a client with a frame clock loads a slice a frame")
local function Clocked(fps, combat)
    Reset()
    M.player.combat = combat
    check(DB.LoadAsync() == nil, "a load starts by the clock")
    local longest, shortest, n = 0, math.huge, 0
    local done = #loadedEvents
    while #loadedEvents == done and n < 100000 do
        local t = clock
        M.Tick(1 / fps, 1 / fps)
        n = n + 1
        if #loadedEvents == done and n > 3 then -- (the first slices find their pace; the last is cut short)
            local took = clock - t
            if took > longest then longest = took end
            if took < shortest then shortest = took end
        end
    end
    M.player.combat = false
    count = 0
    for _, name in ipairs({ "units", "objects", "quests", "items" }) do
        for _ in pairs(DB[name]) do count = count + 1 end
    end
    check(DB.loaded and count == everything, ("at %d frames a second%s the load finishes with everything in it"):format(fps, combat and " in combat" or ""))
    return shortest, longest, n
end
local low, high, n30 = Clocked(30)
check(low > 7 and high < 9, ("at 30 frames a second a slice is 8 ms (%.1f to %.1f)"):format(low, high))
local n60
low, high, n60 = Clocked(60)
check(low > 4 and high < 7.5, ("at 60 it is a share of the frame (%.1f to %.1f ms)"):format(low, high))
local n144
low, high, n144 = Clocked(144)
check(low > 2.5 and high < 4, ("at 144 it is the least, 3 ms (%.1f to %.1f)"):format(low, high))
check(n30 < n60 and n60 < n144, ("so a higher frame rate takes more frames (%d, %d, %d)"):format(n30, n60, n144))
low, high = Clocked(30, true)
check(low > 1.5 and high < 3, ("in combat a slice is 2 ms at any frame rate (%.1f to %.1f)"):format(low, high))
check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))
debugprofilestop = nil
DB._SetSliced(true)

-- ---------------------------------------------------------------------------
-- 6. The Routes tab asks for the database too
-- ---------------------------------------------------------------------------
Reset()
Window.Show("waypoints")
check(DB.Loading() == nil, "nothing asks for the database on the Waypoints tab")
Window.ShowTab("routes")
check(DB.Loading() ~= nil, "opening Routes starts the load")
Frame()
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
-- 8b. The game reads the data addon's files once a session: asked again it
-- does nothing. A shipped store that cannot be read is left out, and a
-- load that failed half-way goes on from where the rows were read.
-- ---------------------------------------------------------------------------
local reads, communityText = 0, nil
C_AddOns.LoadAddOn = function(name)
    if M.addonsLoaded[name] then return true end
    reads = reads + 1
    local a, b = loader(name)
    communityText = WaypointTrackerData.forever
    return a, b
end
local import, failure = ns.Learn.Import, nil -- (an error is reported once a session: each try has its own)
ns.Learn.Import = function(text, st, quiet, tick)
    if quiet and text == communityText then error(failure) end
    return import(text, st, quiet, tick)
end
for _, sliced in ipairs({ true, false }) do
    Reset()
    Window.Hide()
    M.errors, reads = {}, 0
    DB._SetSliced(sliced)
    local how = sliced and "a slice a frame" or "all at once"
    failure = "simulated: a bad line in the community store, read " .. how
    if sliced then
        check(DB.LoadAsync() == nil, "a load starts")
        UntilLoaded()
        ok, why = loadedEvents[1] and loadedEvents[1][1], loadedEvents[1] and loadedEvents[1][2]
    else
        local ran
        ran, ok, why = pcall(DB.Load)
        check(ran, how .. ": no error reaches whoever asked: " .. tostring(ok))
    end
    check(ok == true and why == nil, how .. ": a store that cannot be read does not stop the load: " .. tostring(why))
    check(DB.loaded and DB.ready and DB.hasShipped, how .. ": the database is ready, with the shipped rows")
    check(#M.errors == 1 and tostring(M.errors[1]):find("simulated", 1, true), how .. ": the failure is reported once (" .. #M.errors .. ")")
    check(DB.community == nil and type(DB.curated) == "table", how .. ": that store is left out, the other is there")
    check(WaypointTrackerData.forever == nil and WaypointTrackerData.curated == nil, how .. ": neither text is kept to be tried again")
    count = 0
    for _ in pairs(DB.units) do count = count + 1 end
    check(count > 8000, how .. ": the NPCs are there (" .. count .. ")")
    ok, why = DB.LoadAsync()
    check(ok == true and why == nil, how .. ": asked again it is ready at once")
    ok, why = DB.Load()
    check(ok == true and why == nil and reads == 1 and #M.errors == 1, how .. ": and again, without reading or failing again")
    local hogger = false
    for _, e in ipairs(DB.Search("hogger", { npc = true, enemy = true }, {}, 20)) do
        if e.name == "Hogger" then hogger = true end
    end
    check(hogger, how .. ": and Find finds things")
end
ns.Learn.Import = import
-- a failure in the loader's own lines, after the rows were read; then
-- asked again, a slice a frame or all at once
for _, again in ipairs({ "a slice a frame", "all at once" }) do
    DB._SetSliced(true)
    Reset()
    M.errors, reads = {}, 0
    local fault, curatedText = true, nil
    C_AddOns.LoadAddOn = function(name)
        if M.addonsLoaded[name] then return true end
        reads = reads + 1
        local a, b = loader(name)
        curatedText = WaypointTrackerData.curated
        WaypointTrackerData.curated = nil
        setmetatable(WaypointTrackerData, { __index = function(_, key)
            if key == "curated" and fault then error("simulated: the loader itself fails, before asking again " .. again) end
        end })
        return a, b
    end
    check(DB.LoadAsync() == nil, "a load starts")
    UntilLoaded()
    check(loadedEvents[1] and loadedEvents[1][1] == false and loadedEvents[1][2] == "broken", "a failure nothing protects ends the load")
    check(not DB.loaded and not DB.ready and DB.Loading() == nil and #M.errors == 1, "reported once, nothing keeps running (" .. #M.errors .. ")")
    check(tostring(M.errors[1]):find("Database.lua:%d+"), "with where it failed: " .. tostring(M.errors[1]):sub(1, 200))
    fault = false
    rawset(WaypointTrackerData, "curated", curatedText)
    if again == "all at once" then
        ok, why = DB.Load()
    else
        check(DB.LoadAsync() == nil, "asked again, the load goes on")
        UntilLoaded()
        ok, why = loadedEvents[2] and loadedEvents[2][1], loadedEvents[2] and loadedEvents[2][2]
    end
    check(ok == true and why == nil, "asked again " .. again .. ", the load finishes well: " .. tostring(why))
    count = 0
    for _, name in ipairs({ "units", "objects", "quests", "items" }) do
        for _ in pairs(DB[name]) do count = count + 1 end
    end
    check(DB.loaded and DB.hasShipped and reads == 1 and count == everything, "with everything in it, the files read once (" .. count .. " of " .. everything .. ")")
    ok, why = DB.Load()
    check(ok == true and why == nil, "and stays ready")
end
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
local whole = 0
for _, source in ipairs({ "curated", "community" }) do
    for _, kind in ipairs({ "npcs", "objects", "quests", "items" }) do
        for _ in pairs(DB[source][kind] or {}) do whole = whole + 1 end
    end
end
check(whole > 0 and whole < 3000, "only the shipped records that wait for something are kept whole (" .. whole .. ")")
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
