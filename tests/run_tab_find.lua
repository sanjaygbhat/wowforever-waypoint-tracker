-- Find tab, menus and pages against the fake WoW API. Run from repo root:
--     lua5.1 tests/run_tab_find.lua [--bare]
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local bare = arg[1] == "--bare"
if bare then
    MenuUtil, ShowUIPanel, HideUIPanel, RegisterUIPanel = nil, nil, nil, nil
    local create = CreateFrame
    CreateFrame = function(kind, name, parent, template)
        if template == "SearchBoxTemplate" or template == "InputBoxTemplate"
            or template == "InputScrollFrameTemplate" or template == "WowStyle1DropdownTemplate"
            or template == "ButtonFrameTemplate" then
            error("optional template unavailable")
        end
        return create(kind, name, parent, template)
    end
end
local function OnlyKnownFrames()
    local allowed = {
        WaypointTrackerFrame = true, WaypointTrackerEditModeDialog = true,
        WaypointTrackerArrow = true, WaypointTrackerArrowText = true,
        WaypointTrackerCoordsBox = true, WaypointTrackerRouteRecorder = true,
        WaypointTrackerArrowSelection = true, WaypointTrackerTextSelection = true,
        WaypointTrackerCoordsSelection = true, WaypointTrackerRecorderSelection = true,
        WaypointTrackerMinimapButton = true, WaypointTrackerMapButton = true,
        WaypointTrackerFrameTab1 = true, WaypointTrackerFrameTab2 = true, WaypointTrackerFrameTab3 = true,
    }
    for _, frame in ipairs(M.frames) do
        local name = frame:GetName()
        if name and name:find("^WaypointTracker") and not allowed[name] then return false end
    end
    return true
end

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. msg) end
end
local function near(a, b) return a and math.abs(a - b) < 0.001 end
WaypointTrackerDB = nil
local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
local Find, Window, DB, WP, Learn, Geo, L = ns.Find, ns.Window, ns.DB, ns.WP, ns.Learn, ns.Geo, ns.L
Window.RegisterTab{ key = "waypoints", order = 1, title = L.TAB_WAYPOINTS }
Window.RegisterTab{ key = "routes", order = 3, title = L.ROUTES_TITLE }
check(Window.tabs.find and Window.tabs.find.spec.order == 2, "Find registers as the second tab")
check(Find.Toggle and Find.IsShown and Find.Show, "Find provides shared-window entry points")

M.player.wx, M.player.wy, M.player.inst = -1200, -1200, 0
M.noDataAddon = true
-- Exercise the real Window.Show path when Blizzard silently refuses the panel,
-- including the first visit before any Find page has been built.
local managerShow = ShowUIPanel
ShowUIPanel = function() M.uiPanelCalls.show = M.uiPanelCalls.show + 1 end
Find.Show()
Find.ShowShareBox("export")
Find.ShowShareBox("import")
Find.ShowFixBox({ kind = "npc", id = 60, name = "Test NPC" })
check(not Window.IsShown() and M.focus == nil, "refused first visit never focuses hidden Find controls")
check(not Window.CurrentPage("find") and not Find.shareBox and not Find.fixBox,
    "refused first visit never builds a Share, Import or Fix page")
ShowUIPanel = managerShow
local setStatus, tipTone = Window.SetStatus
Window.SetStatus = function(text, good)
    if text == L.DB_NOTE then tipTone = good end
    return setStatus(text, good)
end
Find.Show()
Window.SetStatus = setStatus
local fw = Find.widgets
check(Window.frame.status:GetText() == L.DB_NOTE, "first Find visit shows the tip in shell status")
check(tipTone == "info", "Find tip requests neutral informational status")
local running, pct = Learn.ScanProgress()
check(fw.note:GetText() == (running and L.SCAN_PROGRESS:format(pct) or ""), "footer contains only scan progress")
Window.Hide()
Find.Show()
check(Window.frame.status:GetText() == "", "reopening Find does not repeat the session tip")
Window.ShowTab("routes")
Window.ShowTab("find")
check(Window.frame.status:GetText() == "", "switching back to Find does not repeat the tip")
M.tooltip = {}
fw.kind:RunScript("OnEnter")
check(#M.tooltip == 2 and M.tooltip[1] == L.TAB_ALL and M.tooltip[2] == L.FIND_KIND_DESC,
    "Kind tooltip describes filtering")
fw.kind:RunScript("OnLeave")
-- The mock records anchors but does not resolve their sizes; give the list
-- the viewport size it has in the shell and exercise its resize handler.
fw.list:SetSize(276, 308)
fw.list:RunScript("OnSizeChanged")
check(Window.IsShown() and Window.GetTab() == "find" and Find.IsShown(), "Find opens the shared window on its tab")
check(OnlyKnownFrames(), "Find creates no floating windows")
check(fw.search.placeholder:GetText() == L.FIND_HINT, "search placeholder")
fw.search:Type("kobold")
M.Tick(0.3)
check(not fw.rows[1]:IsShown() and fw.empty:GetText() == L.DB_MISSING, "missing data has an empty state")
check(WaypointTrackerData == nil, "data loads on demand")
M.noDataAddon = false
fw.search:Type("a")
M.Tick(0.3)
check(DB.loaded and WaypointTrackerData ~= nil, "typing loads the database")
local function name(tbl, id) return DB[tbl][id].name end
local function typeSearch(text)
    fw.search:Type(text)
    M.Tick(0.3)
end
local function menuItem(dropdown, text, kind)
    local root
    if bare then dropdown:Refresh(); root = dropdown.menu
    else dropdown:GenerateMenu(); root = M.lastMenu end
    for _, item in ipairs(root.items) do
        if item.text == text and item.kind == kind then return item end
    end
    error("missing menu item: " .. text)
end
local function choose(key, label)
    local item = menuItem(fw.kind, L[label], "radio")
    item.fn()
    check(ns.Get("findTab") == key and item.isSelected(), "Kind chooses " .. key)
    check((bare and fw.kind.text:GetText() or fw.kind:GetText()) == L[label], "Kind label follows " .. key)
end
local function service(label) menuItem(fw.nearest, L[label], "button").fn() end

Find.Show("kobold")
check(Window.IsShown() and Window.GetTab() == "find" and fw.search:GetText() == "kobold", "Show fills search and opens Find")
check(M.focus ~= fw.search, "explicit search leaves focus clear for Escape")
typeSearch(name("units", 6))
local vermin = fw.rows[1].entry
check(vermin and vermin.id == 6, "typing finds Kobold Vermin")
check(DB.Points(vermin)[1].m == 37, "spawns are in Elwynn")
check(fw.detail.buttons[1]:IsShown(), "Take me there appears")
fw.detail.buttons[1]:Click()
check(WP.GetActive().title == name("units", 6) and WP.GetActive().m == 37, "detail action sets the nearest spawn")
check(select(1, Geo.GetVector(WP.GetActive())) < 600, "nearest spawn is nearby")
check(Window.frame.status:GetText() == L.ADDED:format(WP.Describe(WP.GetActive())), "actions use shell status")

choose("quest", "TAB_QUESTS")
typeSearch(name("quests", 62))
local quest = fw.rows[1].entry
check(quest and quest.kind == "quest" and quest.id == 62, "quest search")
check(fw.detail.buttons[1]:IsShown() and fw.detail.buttons[2]:IsShown() and fw.detail.buttons[3]:IsShown(), "three quest step actions")
Find.Activate(quest)
check(WP.GetActive().m == 37 and WP.GetActive().title:find(quest.name, 1, true), "quest goes to its giver")
choose("npc", "TAB_NPCS")
typeSearch(name("units", 4949))
check(not fw.rows[1].entry, "faction hides Thrall")
fw.faction:Click()
M.Tick(0.3)
check(fw.rows[1].entry and fw.rows[1].entry.id == 4949, "faction checkbox reruns search")
fw.faction:Click()
choose("enemy", "TAB_ENEMIES")
typeSearch(name("units", 6))
check(fw.rows[1].entry and fw.rows[1].entry.id == 6, "enemy kind includes monsters")
choose("npc", "TAB_NPCS")
typeSearch(name("units", 6))
check(not fw.rows[1].entry, "NPC kind excludes monsters")
choose("object", "TAB_OBJECTS")
typeSearch("chest")
for _, row in ipairs(fw.rows) do check(not row.entry or row.entry.kind == "object", "object filter") end
choose("item", "TAB_ITEMS")
typeSearch(name("items", 2605))
check(fw.rows[1].entry and fw.rows[1].entry.id == 2605, "item search")
fw.detail.buttons[1]:Click()
check(WP.GetActive() ~= nil, "item action goes to a seller")
choose("all", "TAB_ALL")
if fw.search.clearButton then fw.search.clearButton:Click()
else fw.search:Type("") end
M.Tick(0.3)
check(fw.search:GetText() == "" and Find.IsNearby(), "search clear restores nearby")
Find.Show(name("units", 6))
fw.search:RunScript("OnEnterPressed")
check(WP.GetActive().title == name("units", 6) and M.focus ~= fw.search, "Enter activates a result and clears focus")
service("SERVICE_INNKEEPER")
check(WP.GetActive().title == name("units", 295), "nearest innkeeper is Farley")
service("SERVICE_MAILBOX")
check(WP.GetActive().m == 37 and WP.GetActive().title ~= name("units", 295), "nearest mailbox")
Find.Show()
check(Find.IsNearby() and fw.search:GetText() == "" and fw.count:GetText() ~= "", "blank search shows nearby")
local old = fw.rows[1].entry
fw.list:RunScript("OnMouseWheel", -1)
check(fw.list.offset == 3 and fw.rows[1].entry ~= old, "list wheel scrolls")
fw.rows[2]:Click()
check(fw.rows[2].sel:IsShown() and fw.detail.name:GetText() == fw.rows[2].entry.name, "row selection updates detail")
M.Tick(0.6)
check(fw.list.offset == 3 and fw.rows[2].sel:IsShown(), "distance refresh retains scroll and selection")
fw.rows[2]:RunScript("OnDoubleClick", "LeftButton")
check(WP.GetActive() ~= nil, "double click activates")
typeSearch("zzzzqqq")
check(not fw.rows[1].entry and fw.list.offset == 0 and fw.empty:IsShown(), "new search clears stale rows and resets scroll")
if Learn.ScanProgress() then
    check(fw.empty:GetText():find(L.SCAN_SEARCH_NOTE, 1, true), "empty search explains quest scanning")
    check(fw.note:GetText() == L.SCAN_PROGRESS:format(select(2, Learn.ScanProgress())), "footer scan progress")
end
fw.zoneOnly:Click()
M.Tick(0.3)
check(ns.Get("findThisZone"), "zone checkbox is bound")
fw.zoneOnly:Click()
Find.Show()
M.player.inst, M.player.wx, M.player.wy = 2800, 1500, 1800
M.Tick(0.6)
check(Find.IsNearby(), "nearby refresh follows map changes")

local function guid(kind, id) return ("%s-0-1-2-3-%d-00000ABC"):format(kind, id) end
M.units.questnpc = { guid = guid("Creature", 90001), name = "Elder Skyfeather", reaction = 5, level = 12 }
M.questDialog = { id = 70001, title = "Wings Over Zephras", text = "Collect 6 Skyflowers." }
M.FireEvent("QUEST_DETAIL")
M.FireEvent("QUEST_ACCEPTED", 70001)
M.units.questnpc = nil
M.units.npc = { guid = guid("Creature", 90003), name = "Breezy Trader", reaction = 5, level = 15 }
M.canRepair = true
M.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Merchant)
M.units.npc = nil
M.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.MailInfo)
M.units.target = { guid = guid("Creature", 90010), name = "Galewing Serpent", reaction = 2, level = 9 }
M.FireEvent("PLAYER_TARGET_CHANGED")
M.loot = { guid("Creature", 90010) }
M.FireEvent("LOOT_OPENED")
M.units.target = nil
M.ShowObjectTooltip("Skyflower")
M.loot = { guid("GameObject", 95001) }
M.FireEvent("LOOT_OPENED")
M.loot, M.tooltipOwner = {}, nil
M.Tick(5.1)
Find.Show("Wings", "quest")
check(fw.rows[1].entry and fw.rows[1].entry.id == 70001, "learned quest searchable")
Find.Activate(fw.rows[1].entry)
check(WP.GetActive().m == 2521, "learned quest points to giver")
choose("enemy", "TAB_ENEMIES")
typeSearch("galewing")
check(fw.rows[1].entry and fw.rows[1].entry.id == 90010, "learned enemy searchable")
choose("npc", "TAB_NPCS")
typeSearch("breezy")
check(fw.rows[1].entry and fw.rows[1].entry.id == 90003, "learned friendly NPC searchable")
choose("object", "TAB_OBJECTS")
typeSearch("skyflower")
check(fw.rows[1].entry and fw.rows[1].entry.id == 95001, "learned object searchable")
service("SERVICE_REPAIR")
check(WP.GetActive().title == "Breezy Trader", "nearest repair uses learned vendor")
service("SERVICE_MAILBOX")
check(WP.GetActive().m == 2521, "nearest mailbox uses discoveries")

M.player.inst, M.player.wx, M.player.wy = 0, -1200, -1200
Find.Show("Runes of the Sorcerer", "item")
local runes = DB.items[209850]
check(runes and fw.rows[1].entry == runes, "game item is searchable")
M.ShowObjectTooltip("Scrolls")
M.loot = { guid("GameObject", 409731) }
M.lootItems = { { id = 209850, name = runes.name } }
M.FireEvent("LOOT_OPENED")
M.loot, M.lootItems, M.tooltipOwner = {}, {}, nil
M.Tick(5.1)
Find.Show(runes.name, "item")
Find.Activate(runes)
check(WP.GetActive().m == 37 and WP.GetActive().title:find(runes.name, 1, true), "item goes to the object it dropped from")
local cont, wx, wy = Geo.MapToWorld(37, 0.41, 0.61)
DB.ParseClient({
    flights = ("9001\t%d\t37\t%.1f\t%.1f\tAH"):format(cont, wx, wy),
    names = { flights = "9001\tTestport, Elwynn" },
})
service("SERVICE_FLIGHT")
check(WP.GetActive().title == "Testport, Elwynn" and near(WP.GetActive().x, 0.41), "nearest flight uses client flight paths")

local exported = Learn.Export()
menuItem(fw.discoveries, L.SHARE_DISCOVERIES, "button").fn()
local sb = Find.shareBox
local sharePage = sb
check(Window.CurrentPage("find").key == "share", "Share opts into shell page reuse")
check(Window.CurrentPage("find").title == L.SHARE_DISCOVERIES and not Window.tabs.find.content:IsShown(), "Share pushes a page")
check(sb.edit:GetText() == exported and #exported > 0 and not sb.action:IsShown(), "Share contains selected copy text")
check(M.focus == sb.edit, "export text has focus for copying")
sb.back:Click()
check(not Window.CurrentPage("find") and Window.tabs.find.content:IsShown(), "Back restores Find root")
WaypointTrackerDB.learned = nil
menuItem(fw.discoveries, L.IMPORT_DISCOVERIES, "button").fn()
sb = Find.shareBox
local importPage = sb
check(Window.CurrentPage("find").key == "import", "Import has a separate reuse key")
check(sb.edit:GetText() == "" and sb.action:IsShown(), "Import has an empty text area and action")
sb.edit:SetText(exported)
sb.action:Click()
check(Learn.Count() >= 5 and Learn.Store().quests[70001], "Import brings discoveries back")
check(sb.result:GetText():find(L.IMPORTED:match("^[^%%]+"), 1, true), "Import result line")
check((bare and fw.discoveries.text:GetText() or fw.discoveries:GetText()) == L.LEARNED_COUNT:format(Learn.Count()), "discoveries count refreshes after import")
sb.edit:SetText("hello")
sb.action:Click()
check(sb.result:GetText() == L.IMPORT_NOTHING, "junk import refused")
Window.PopAll("find")
Find.ShowShareBox("import")
sb = Find.shareBox
check(sb.edit:GetText() == "" and sb.result:GetText() == "" and sb.action:IsShown()
    and sb.help:GetText() == L.IMPORT_BOX_HELP, "reopening Import clears pasted text and result")
if Window.tabs.find.pageCache then
    check(sb == importPage, "Import reuses its cached page")
end
Window.PopAll("find")
M.units.target = { guid = guid("Creature", 90011), name = "Later Discovery", reaction = 5, level = 9 }
M.FireEvent("PLAYER_TARGET_CHANGED")
M.units.target = nil
local currentExport = Learn.Export()
check(currentExport ~= exported, "discoveries change between Share visits")
Find.ShowShareBox("export")
sb = Find.shareBox
check(sb.edit:GetText() == currentExport and sb.result:GetText() == "" and not sb.action:IsShown(),
    "reopening Share refreshes exported discoveries")
if Window.tabs.find.pageCache then
    check(sb == sharePage, "Share reuses its cached page")
end
Window.PopAll("find")

M.player.inst, M.player.wx, M.player.wy = 0, -1200, -1200
Find.Show(name("units", 60), "enemy")
fw.detail.buttons[2]:Click()
local fb = Find.fixBox
local fixPage = fb
check(Window.CurrentPage("find").key == "fix", "Fix opts into shell page reuse")
check(Window.CurrentPage("find").title == L.FIX_TITLE and fb.entry.id == 60, "detail correction pushes Fix page")
check(fb.help:GetText():find("64.6", 1, true) and fb.gone:IsShown() and not fb.undo:IsShown(), "Fix explains the original spot")
fb.x.edit:SetText("abc")
fb.save:Click()
check(fb.result:GetText() == L.FIX_BAD and #Learn.Fixes("npc", 60) == 0, "invalid correction refused")
fb.here:Click()
check(fb.x.edit:GetText() == "40.0" and fb.y.edit:GetText() == "60.0", "Here fills correction coordinates")
fb.save:Click()
check(fb.result:GetText() == L.FIX_SAVED and fb.undo:IsShown(), "saving correction shows Undo")
check(near(DB.Points(DB.units[60])[1].x, 0.4), "correction replaces database spot")
check(fw.detail.body:GetText():find(L.FIX_MARK, 1, true), "detail marks the correction")
Find.Activate(DB.units[60])
check(near(WP.GetActive().x, 0.4), "arrow uses corrected spot")
fb.undo:Click()
check(fb.result:GetText() == L.FIX_REMOVED and near(DB.Points(DB.units[60])[1].x, 0.646), "Undo restores original spot")
fb.gone:Click()
check(#DB.Points(DB.units[60]) == 0, "Gone removes the spot")
fb.undo:Click()
fb.back:Click()
Find.ShowFixBox(DB.units[60])
fb = Find.fixBox
check(fb.entry.id == 60 and fb.x.edit:GetText() == "" and fb.y.edit:GetText() == ""
    and fb.result:GetText() == "", "reopening Fix resets coordinates and result")
if Window.tabs.find.pageCache then
    check(fb == fixPage, "Fix reuses its cached page")
end
M.tooltip = {}
fb.gone:RunScript("OnEnter")
check(#M.tooltip == 2 and M.tooltip[2] == fb.help:GetText(), "reused Fix tooltip shows current help once")
fb.gone:RunScript("OnLeave")
fb.back:Click()
local spotless = { kind = "npc", id = 248500, name = "Spotless", key = "spotless", fac = "" }
DB.units[spotless.id] = spotless
Find.ShowFixBox(spotless)
fb = Find.fixBox
check(not fb.gone:IsShown() and fb.help:GetText() == L.FIX_HELP_NEW:format("Spotless"), "spotless entry has an Add correction page")
fb.x.edit:SetText("12,5")
fb.y.edit:SetText("34")
fb.save:Click()
spotless.points = nil
check(near(DB.Points(spotless)[1].x, 0.125), "decimal comma correction adds a spot")
-- A second page must not retarget the first page's saved callbacks.
Find.ShowFixBox(DB.units[60])
Find.fixBox.back:Click()
fb.undo:Click()
check(#Learn.Fixes("npc", spotless.id) == 0, "returning to a stacked Fix page keeps its entry")
Window.Hide()
check(not Window.CurrentPage("find") and not fb:IsVisible(), "closing pops all Find pages")
DB.units[spotless.id] = nil
DB.MergeLearned()

local mapPosition = C_Map.GetMapPosFromWorldPos
C_Map.GetMapPosFromWorldPos = function(_, _, override)
    return override or 1429, CreateVector2D(0.5, 0 / 0)
end
local errors = #M.errors
Find.Show("goldsh")
M.Tick(1)
Find.Show("zzqqxv")
M.Tick(1)
check(#M.errors == errors, "search tolerates an unusable game map position")
C_Map.GetMapPosFromWorldPos = mapPosition
for _, tbl in ipairs({ "units", "objects", "quests", "places", "items" }) do
    for _, e in pairs(DB[tbl]) do e.points = nil end
end
Window.Hide()

WP.ClearAll(true)
ns.Set("chatMessages", true)
local printed = #M.printed
Find.Way(name("units", 448))
check(not Window.IsShown() and WP.GetActive().title == name("units", 448), "way exact Hogger sets arrow without opening")
check(#M.printed == printed + 1 and M.printed[#M.printed]:find(L.ADDED:format(WP.Describe(WP.GetActive())), 1, true),
    "typed exact-name command prints one Added line with chat enabled")
WP.ClearAll(true)
ns.Set("chatMessages", false)
printed = #M.printed
Find.Way(name("units", 448))
check(#M.printed == printed + 1 and M.printed[#M.printed]:find(L.ADDED:format(WP.Describe(WP.GetActive())), 1, true),
    "typed exact-name command still replies once with chat disabled")
printed = #M.printed
Find.Activate(DB.units[60])
check(#M.printed == printed, "UI activation stays quiet with chat disabled")
ns.Set("chatMessages", true)
Find.Way("kobold")
check(Find.IsShown() and fw.search:GetText() == "kobold", "way partial name opens search")
Window.Hide()
local hog = DB.units[448]
DB.units[999999] = { kind = "npc", id = 999999, name = hog.name, key = hog.key, fac = "", points = { { m = 37, x = 0.2, y = 0.2 } } }
Find.Way(hog.name)
check(Find.IsShown() and fw.search:GetText() == hog.name, "ambiguous exact name opens search")
DB.units[999999] = nil
Window.ShowTab("routes")
check(not Find.IsShown(), "IsShown checks active tab")
Find.Toggle()
check(Find.IsShown(), "Toggle switches from another tab")
Find.Toggle()
check(not Window.IsShown(), "Toggle closes Find")
Find.Show("kobold")
local search, searches = DB.Search, 0
DB.Search = function(...)
    searches = searches + 1
    return search(...)
end
fw.search:Type("hogger")
Window.Hide()
M.Tick(0.3)
check(searches == 0, "pending typing search stops when the window closes")
DB.Search = search
-- Keep another visible edit box focused while the manager refuses to open Find.
-- Cached pages and search state must remain untouched by each entry point.
local otherEdit = CreateFrame("EditBox", nil, UIParent)
otherEdit:SetFocus()
managerShow = ShowUIPanel
ShowUIPanel = function() M.uiPanelCalls.show = M.uiPanelCalls.show + 1 end
local oldSearch, oldKind = fw.search:GetText(), ns.Get("findTab")
local oldShare, oldFix = Find.shareBox, Find.fixBox
local oldShareText, oldFixEntry = oldShare.edit:GetText(), oldFix.entry
local frameCount, waypointCount = #M.frames, WP.Count()
local function refused(action, label)
    local calls = M.uiPanelCalls.show
    action()
    check(M.uiPanelCalls.show == calls + 1 and not Window.IsShown(), label .. " respects panel refusal")
    check(M.focus == otherEdit and fw.search:GetText() == oldSearch and ns.Get("findTab") == oldKind,
        label .. " preserves focus and search state")
    check(not Window.CurrentPage("find") and #M.frames == frameCount
        and Find.shareBox == oldShare and oldShare.edit:GetText() == oldShareText
        and Find.fixBox == oldFix and oldFix.entry == oldFixEntry,
        label .. " leaves cached pages untouched")
end
refused(function() Find.Show() end, "blank Find")
refused(function() Find.Show("blocked search", "item") end, "typed Find")
refused(function() Find.ShowShareBox("export") end, "Share")
refused(function() Find.ShowShareBox("import") end, "Import")
refused(function() Find.ShowFixBox(DB.units[448]) end, "Fix")
refused(function() Find.Way("zzqqxv") end, "unmatched /way")
check(WP.Count() == waypointCount, "refused unmatched /way adds no waypoint")
ShowUIPanel = managerShow
otherEdit:ClearFocus()
otherEdit:Hide()
local shows, hides = M.uiPanelCalls.show, M.uiPanelCalls.hide
M.player.combat = true
Find.Show("kobold")
Find.ShowShareBox("import")
Find.ShowFixBox(DB.units[60])
Window.Hide()
check(M.uiPanelCalls.show == shows and M.uiPanelCalls.hide == hides and not M.actionBlocked, "Find and pages avoid protected panel calls in combat")
M.player.combat = false
Find.ShowShareBox("export")
check(Find.IsShown() and Find.shareBox:IsVisible(), "Share opens Find when hidden")
Window.Hide()
Find.ShowFixBox(DB.units[60])
check(Find.IsShown() and Find.fixBox:IsVisible(), "Fix opens Find when hidden")
Find.Show()
-- Publish the saved completion state that Learn.ScanProgress reads. The full
-- addon suite exercises the background scan; here only the UI transition matters.
Learn.QuestTitles()
local titles = WaypointTrackerDB.questTitles
local complete = titles.complete
titles.complete = true
M.Tick(0.6)
check(not Learn.ScanProgress() and fw.note:GetText() == "", "completed scan leaves the footer empty")
titles.complete = complete
check(OnlyKnownFrames(), "pages create no extra window globals")
for _, err in ipairs(M.errors) do check(false, "reported error: " .. tostring(err)) end
print(("Find tab%s: %d passed, %d failed"):format(bare and " (bare)" or "", passed, failed))
if failed > 0 then os.exit(1) end
