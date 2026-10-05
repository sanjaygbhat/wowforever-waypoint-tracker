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
        setActive = changedQuest or wasActive or WP.GetActive() == nil,
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
-- it. Coming back to life removes it and puts back the waypoint you had.
-- ---------------------------------------------------------------------------
local corpseWp, beforeDeath

local function HasCorpseWaypoint()
    return corpseWp ~= nil and WP.IsValid(corpseWp)
end

local function AddCorpse(m, x, y)
    if HasCorpseWaypoint() then
        return
    end
    beforeDeath = WP.GetActive()
    corpseWp = WP.Add(m, x, y, { title = L.CORPSE_NAME, source = "corpse", persistent = false, silent = true })
end

local function OnDeath()
    if not ns.Get("corpseWaypoint") then
        return
    end
    local m, x, y = ns.Geo.GetPlayerMapPosition()
    if m then
        AddCorpse(m, x, y)
    end
end

-- As a ghost (after releasing, or logging in as one) the game knows where
-- the body is, even after dying somewhere that has no position.
local function OnGhost()
    if not ns.Get("corpseWaypoint") or HasCorpseWaypoint() or not (UnitIsGhost and UnitIsGhost("player")) then
        return
    end
    local m = C_Map.GetBestMapForUnit("player")
    local pos = m and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and C_DeathInfo.GetCorpseMapPosition(m)
    if pos then
        local x, y = ns.XY(pos)
        if ns.Num(x) and ns.Num(y) then
            AddCorpse(m, x, y)
        end
    end
end

local function OnAlive()
    -- PLAYER_ALIVE also fires when you release your spirit
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        OnGhost()
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
    corpseWp, beforeDeath = nil, nil
end

ns.RegisterEvent("PLAYER_DEAD", OnDeath)
ns.RegisterEvent("PLAYER_ALIVE", OnAlive)
ns.RegisterEvent("PLAYER_UNGHOST", OnAlive)
ns.On("LOGIN", OnGhost)
