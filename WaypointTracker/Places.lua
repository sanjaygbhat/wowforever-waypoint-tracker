-- Places: things you can pick in the search box besides zones. Everything
-- comes from the game's own map data, so it covers WoW Forever's new quests
-- and is always in the player's language:
--   * quests in your log (where to go next, or where to turn them in)
--   * flight masters, dungeon entrances and other named map spots on your
--     continent
--   * rares and treasures the game is currently showing on your map
local _, ns = ...
local L, Geo = ns.L, ns.Geo

local Places = {}
ns.Places = Places

local CACHE_SECONDS = 10
local cache, cacheTime = nil, -100

local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local Plain = ns.Plain

local function Call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then
        return a, b, c, d
    end
end

-- Zones on the continent you're on (the quest/flight data is per zone).
local function NearbyZones()
    local current = C_Map.GetBestMapForUnit("player")
    local myCont = current and Geo.ContinentOf(current)
    local ids, seen = {}, {}
    if current then
        ids[1], seen[current] = current, true
    end
    if myCont and myCont ~= "" then
        for _, z in ipairs(Geo.GetZoneList()) do
            if z.continent == myCont and z.mapType == ZONE and not seen[z.id] then
                seen[z.id] = true
                ids[#ids + 1] = z.id
            end
        end
    end
    return ids, current
end

local function Add(out, kind, name, m, x, y, extra)
    name = Plain(name)
    x, y = ns.Num(x), ns.Num(y)
    if not name or name == "" or not m or not x or not y then
        return
    end
    if x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then
        return
    end
    local e = extra or {}
    e.kind, e.name, e.m, e.x, e.y = kind, name, m, x, y
    e.key = Geo.Squash(name)
    e.words = Geo.Words(name)
    out[#out + 1] = e
    return e
end

local function CollectQuests(out, zones)
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then
        return
    end
    -- where each quest's marker is on the maps around you
    local where = {}
    for _, zid in ipairs(zones) do
        local quests = Call(C_QuestLog.GetQuestsOnMap, zid)
        if type(quests) == "table" then
            for _, q in ipairs(quests) do
                local id = q.questID
                if id and not where[id] and ns.Num(q.x) and ns.Num(q.y) then
                    where[id] = { zid, q.x, q.y } -- positions are on the map we asked about
                end
            end
        end
    end
    local num = Call(C_QuestLog.GetNumQuestLogEntries) or 0
    for i = 1, num do
        local id = Call(C_QuestLog.GetQuestIDForLogIndex, i)
        if id and id > 0 then
            local title = Call(C_QuestLog.GetTitleForQuestID, id)
            local pos = where[id]
            if not pos then
                local m, x, y = Call(C_QuestLog.GetNextWaypoint, id)
                if m and x and y then
                    pos = { m, x, y }
                end
            end
            if pos and title then
                local done = Call(C_QuestLog.IsComplete, id)
                Add(out, done and "turnin" or "quest", title, pos[1], pos[2], pos[3], { questID = id })
            end
        end
    end
end

local function CollectFlightMasters(out, zones)
    if not C_TaxiMap or not C_TaxiMap.GetTaxiNodesForMap then
        return
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local enum = Enum and Enum.FlightPathFaction
    local mine = enum and ((faction == "Horde" and enum.Horde) or (faction == "Alliance" and enum.Alliance))
    local seen = {}
    for _, zid in ipairs(zones) do
        local nodes = Call(C_TaxiMap.GetTaxiNodesForMap, zid)
        if type(nodes) == "table" then
            for _, node in ipairs(nodes) do
                local okFaction = not enum or node.faction == nil or node.faction == enum.Neutral or node.faction == mine
                if okFaction and node.name and node.position and not seen[node.name] then
                    seen[node.name] = true
                    local x, y = ns.XY(node.position)
                    Add(out, "flight", node.name, zid, x, y)
                end
            end
        end
    end
end

local function CollectDungeonsAndSpots(out, zones)
    local seen = {}
    for _, zid in ipairs(zones) do
        if C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
            local list = Call(C_EncounterJournal.GetDungeonEntrancesForMap, zid)
            if type(list) == "table" then
                for _, d in ipairs(list) do
                    if d.name and d.position and not seen[d.name] then
                        seen[d.name] = true
                        local x, y = ns.XY(d.position)
                        Add(out, "dungeon", d.name, zid, x, y)
                    end
                end
            end
        end
        if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap then
            local ids = Call(C_AreaPoiInfo.GetAreaPOIForMap, zid)
            if type(ids) == "table" then
                for _, poiID in ipairs(ids) do
                    local info = Call(C_AreaPoiInfo.GetAreaPOIInfo, zid, poiID)
                    if info and info.name and info.position and not seen[info.name] then
                        seen[info.name] = true
                        local x, y = ns.XY(info.position)
                        Add(out, "poi", info.name, zid, x, y)
                    end
                end
            end
        end
    end
end

local function CollectRares(out, current)
    if not current or not C_VignetteInfo or not C_VignetteInfo.GetVignettes then
        return
    end
    local guids = Call(C_VignetteInfo.GetVignettes)
    if type(guids) ~= "table" then
        return
    end
    for _, guid in ipairs(guids) do
        local info = Call(C_VignetteInfo.GetVignetteInfo, guid)
        if info and not info.isDead and (info.onWorldMap or info.onMinimap) then
            local pos = Call(C_VignetteInfo.GetVignettePosition, guid, current)
            if pos then
                local x, y = ns.XY(pos)
                Add(out, "rare", info.name, current, x, y)
            end
        end
    end
end

-- Everything, refreshed at most every few seconds.
function Places.GetAll(force)
    local now = GetTime()
    if cache and not force and now - cacheTime < CACHE_SECONDS then
        return cache
    end
    local out = {}
    local zones, current = NearbyZones()
    local steps = {
        function()
            CollectQuests(out, zones)
        end,
        function()
            CollectRares(out, current)
        end,
        function()
            CollectFlightMasters(out, zones)
        end,
        function()
            CollectDungeonsAndSpots(out, zones)
        end,
    }
    for _, step in ipairs(steps) do
        ns.Call(step)
    end
    cache, cacheTime = out, now
    return out
end

local KIND_ORDER = { quest = 1, turnin = 1, rare = 2, flight = 3, dungeon = 4, poi = 5 }

-- Matching places, best first. With no text: just your quests.
function Places.Search(text)
    local all = Places.GetAll()
    local q, qWords = Geo.PrepareQuery(text)
    local scored = {}
    for _, p in ipairs(all) do
        local score
        if q == "" then
            score = (p.kind == "quest" or p.kind == "turnin") and 5 or nil
        else
            score = Geo.MatchScore(p, q, qWords)
        end
        if score then
            scored[#scored + 1] = { p = p, s = score }
        end
    end
    table.sort(scored, function(a, b)
        if a.s ~= b.s then
            return a.s < b.s
        end
        local ka, kb = KIND_ORDER[a.p.kind] or 9, KIND_ORDER[b.p.kind] or 9
        if ka ~= kb then
            return ka < kb
        end
        return a.p.name < b.p.name
    end)
    local results = {}
    for i, e in ipairs(scored) do
        results[i] = e.p
        e.p.score = e.s
    end
    return results
end

local KIND_LABEL = {
    quest = "PLACE_QUEST",
    turnin = "PLACE_TURNIN",
    flight = "PLACE_FLIGHT",
    dungeon = "PLACE_DUNGEON",
    poi = "PLACE_POI",
    rare = "PLACE_RARE",
}

function Places.Label(p)
    return L[KIND_LABEL[p.kind] or "PLACE_POI"]
end

-- Find where a quest is right now (for "Point to the quest I'm tracking").
local questMiss = {} -- questID -> time before which not to look again

function Places.QuestPosition(questID)
    if not questID or questID == 0 then
        return nil
    end
    local current = C_Map.GetBestMapForUnit("player")
    if current and C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local quests = Call(C_QuestLog.GetQuestsOnMap, current)
        if type(quests) == "table" then
            for _, q in ipairs(quests) do
                if q.questID == questID and ns.Num(q.x) and ns.Num(q.y) then
                    return current, q.x, q.y
                end
            end
        end
    end
    local m, x, y = Call(C_QuestLog and C_QuestLog.GetNextWaypoint, questID)
    if m and ns.Num(x) and ns.Num(y) then
        return m, x, y
    end
    -- rescanning every map is slow, so a quest that isn't on any of them
    -- isn't looked for again for a few seconds
    if (questMiss[questID] or 0) > GetTime() then
        return nil
    end
    for _, p in ipairs(Places.GetAll(true)) do
        if p.questID == questID then
            return p.m, p.x, p.y
        end
    end
    questMiss[questID] = GetTime() + 10
end
