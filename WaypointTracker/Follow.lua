-- Follow: the arrow can pick up
--   * the game's own map pin (Ctrl + click on the map in the default UI, or
--     clicking a map pin link someone shared in chat), and
--   * the quest you're tracking (optional).
local _, ns = ...
local L, WP, Places = ns.L, ns.WP, ns.Places

-- ---------------------------------------------------------------------------
-- The game's map pin
-- ---------------------------------------------------------------------------
local function ImportMapPin()
    -- (checked first so a pin you placed with this off isn't picked up later)
    if not WP.IsNewPin() or not ns.Get("followMapPins") then
        return
    end
    local point = C_Map.GetUserWaypoint()
    if not point or not point.uiMapID or not point.position then
        return
    end
    local x, y = ns.XY(point.position)
    x, y = ns.Num(x), ns.Num(y)
    if not x or not y or WP.IsOurBlizzardPin(point.uiMapID, x, y) then
        return
    end
    WP.Add(point.uiMapID, x, y, { title = L.MAP_PIN_NAME, source = "mappin" })
end

-- Clicking a map pin link runs the game's own code, which places the pin,
-- tracks it and opens the map. Wait until it has finished before we look,
-- so we never run in the middle of it.
local importPending = false
ns.RegisterEvent("USER_WAYPOINT_UPDATED", function()
    if importPending then
        return
    end
    importPending = true
    C_Timer.After(0, function()
        importPending = false
        ns.Call(ImportMapPin)
    end)
end)

-- ---------------------------------------------------------------------------
-- The quest you're tracking
-- ---------------------------------------------------------------------------
local questWp, questID

local function ClearQuestWaypoint()
    if questWp and WP.IsValid(questWp) then
        WP.Remove(questWp, true)
    end
    questWp, questID = nil, nil
end

local function UpdateTrackedQuest()
    if not ns.Get("followQuest") then
        if questWp then
            ClearQuestWaypoint()
        end
        return
    end
    local id = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    if not id or id == 0 then
        ClearQuestWaypoint()
        return
    end
    local m, x, y = Places.QuestPosition(id)
    if not m then
        return
    end
    local changedQuest = id ~= questID
    if questWp and WP.IsValid(questWp) and not changedQuest and questWp.m == m and math.abs(questWp.x - x) < 0.002 and math.abs(questWp.y - y) < 0.002 then
        return
    end
    local wasActive = questWp and WP.GetActive() == questWp
    if questWp and WP.IsValid(questWp) then
        WP.Remove(questWp, true, true)
    end
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    questWp = WP.Add(m, x, y, {
        title = title,
        persistent = false,
        silent = true,
        source = "quest",
        -- a newly tracked quest takes the arrow; an update keeps what you had
        setActive = (changedQuest and not (ns.IsPlayerDead and ns.IsPlayerDead())) or wasActive or WP.GetActive() == nil,
    })
    questID = id
end

-- Quest events come in bursts; look at most twice a second.
local pending = false
local function Schedule()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        ns.Call(UpdateTrackedQuest)
    end)
end

for _, event in ipairs({ "SUPER_TRACKING_CHANGED", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA", "QUEST_TURNED_IN" }) do
    ns.RegisterEvent(event, Schedule)
end
ns.On("LOGIN", Schedule)
ns.On("SETTING_CHANGED", function(key)
    if key == "followQuest" or key == nil then
        Schedule()
    end
end)

-- ---------------------------------------------------------------------------
-- Your corpse: dying drops a waypoint on your body and points the arrow at
-- it. Releasing your spirit points the arrow at it again (whatever took it
-- meanwhile), and coming back to life removes it and puts back the waypoint
-- you had.
-- ---------------------------------------------------------------------------
local corpseWp, beforeDeath, deathMap, reached

local function HasCorpseWaypoint()
    return corpseWp ~= nil and WP.IsValid(corpseWp)
end

local function IsDead()
    return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and true or false
end
ns.IsPlayerDead = IsDead

local function AddCorpse(m, x, y)
    if HasCorpseWaypoint() then
        return
    end
    local active = WP.GetActive()
    if active and active.source ~= "corpse" then
        beforeDeath = active
    end
    corpseWp = WP.Add(m, x, y, { title = L.CORPSE_NAME, source = "corpse", persistent = false, silent = true })
end

local function OnDeath()
    reached = false
    if not ns.Get("corpseWaypoint") then
        return
    end
    local m, x, y = ns.Geo.GetPlayerMapPosition()
    deathMap = m or C_Map.GetBestMapForUnit("player")
    if m then
        AddCorpse(m, x, y)
    end
end

-- Where the game says your body is: asked on the map you're on, the map you
-- died on, and the maps around them (the game only answers for a map that
-- holds the body).
local function CorpsePosition()
    if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then
        return nil
    end
    local tried = {}
    local function Try(m)
        while m and m ~= 0 and not tried[m] do
            tried[m] = true
            local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, m)
            if ok and pos then
                local x, y = ns.XY(pos)
                x, y = ns.Num(x), ns.Num(y)
                if x and y and (x > 0 or y > 0) and x <= 1 and y <= 1 then
                    return m, x, y
                end
            end
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
            m = info and info.parentMapID
        end
    end
    local m, x, y = Try(C_Map.GetBestMapForUnit("player"))
    if not m then
        m, x, y = Try(deathMap)
    end
    return m, x, y
end

-- As a ghost (after releasing, or logging in as one) the game knows where
-- the body is, even after dying somewhere that has no position.
local function OnGhost()
    if not ns.Get("corpseWaypoint") or not (UnitIsGhost and UnitIsGhost("player")) or reached then
        return
    end
    if not HasCorpseWaypoint() then
        local m, x, y = CorpsePosition()
        if m then
            AddCorpse(m, x, y)
        end
    end
    -- the arrow goes to your body, whatever was picked up while you were dead
    if HasCorpseWaypoint() and WP.GetActive() ~= corpseWp then
        WP.SetActive(corpseWp, true)
    end
end

local function OnAlive()
    -- PLAYER_ALIVE also fires when you release your spirit
    if IsDead() then
        -- a moment later: the game places you at the graveyard first
        C_Timer.After(0.5, function()
            ns.Call(OnGhost)
        end)
        return
    end
    if HasCorpseWaypoint() then
        local wasActive = WP.GetActive() == corpseWp
        local restore = wasActive and beforeDeath and WP.IsValid(beforeDeath) and beforeDeath
        WP.Remove(corpseWp, true, restore and true or false)
        if restore then
            WP.SetActive(restore, true)
        end
    end
    corpseWp, beforeDeath, deathMap, reached = nil, nil, nil, false
end

-- walking up to your body counts: don't put the waypoint back
ns.On("ARRIVED", function(wp)
    if wp == corpseWp then
        reached = true
    end
end)

ns.RegisterEvent("PLAYER_DEAD", OnDeath)
ns.RegisterEvent("PLAYER_ALIVE", OnAlive)
ns.RegisterEvent("PLAYER_UNGHOST", OnAlive)
-- releasing inside a dungeon, or a loading screen, puts you on another map
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    ns.RegisterEvent(event, function()
        if IsDead() then
            C_Timer.After(1, function()
                ns.Call(OnGhost)
            end)
        end
    end)
end
ns.On("LOGIN", OnGhost)
