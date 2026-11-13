-- Shared trainer vocabulary. No database loads, scans or timers at login.
local _, ns = ...
local Trainers = {}
ns.Trainers = Trainers
Trainers.classes = { warrior = true, paladin = true, hunter = true, rogue = true, priest = true,
    shaman = true, mage = true, warlock = true, druid = true }
-- SkillLine IDs, also present in the reviewed profession-rank fixture evidence.
Trainers.professions = {
    { key = "alchemy", id = 171 }, { key = "blacksmithing", id = 164 },
    { key = "enchanting", id = 333 }, { key = "engineering", id = 202 },
    { key = "herbalism", id = 182 }, { key = "leatherworking", id = 165 },
    { key = "mining", id = 186 }, { key = "skinning", id = 393 },
    { key = "tailoring", id = 197 }, { key = "cooking", id = 185 },
    { key = "firstaid", id = 129 }, { key = "fishing", id = 356 },
}
Trainers.services = { trainer_weapon = true, trainer_riding = true }
-- Pet trainers are available to database consumers without changing the menus.
Trainers.additionalServices = { trainer_pet_hunter = true }
for key in pairs(Trainers.classes) do Trainers.services["trainer_class_" .. key] = true end
for _, p in ipairs(Trainers.professions) do Trainers.services["trainer_profession_" .. p.key] = true end

-- Created only by a trainer request. Keep text parsing out of login and out
-- of the candidate loop; merges invalidate resolved entries and corrections.
local index
function Trainers.Index(generation)
    local data = WaypointTrackerData
    local roster, locations = data and data.trainers or "", data and data.trainerLocations or ""
    if index and index.generation == generation and index.roster == roster and index.locations == locations then
        -- A map API may recover after the first request. Retain unresolved
        -- numeric points without rescanning either source string.
        for m, pending in pairs(index.pending) do
            if ns.Geo.IsValidMap(m) then
                for i = 1, #pending, 2 do
                    local id, point = pending[i], pending[i + 1]
                    local points = index.positions[id].points
                    points[#points + 1] = point
                    index.entries[id] = nil
                end
                index.pending[m] = nil
            end
        end
        return index
    end
    index = { generation = generation, roster = roster, locations = locations,
        services = {}, positions = {}, entries = {}, pending = {} }
    for line in roster:gmatch("[^\n]+") do
        local service, values = line:match("^([^\t]+)\t(.+)$")
        if Trainers.services[service] or Trainers.additionalServices[service] then
            local list = {}
            for id, fac in values:gmatch("(%d+):(%a*)") do
                list[#list + 1] = { id = tonumber(id), fac = fac }
            end
            index.services[service] = list
        end
    end
    for line in locations:gmatch("[^\n]+") do
        local id, name, spots, mode = line:match("^(%d+)\t([^\t]*)\t([^\t]+)\t?(.*)$")
        if id then
            id = tonumber(id)
            local points = {}
            for token in spots:gmatch("[^;]+") do
                local m, x, y = token:match("^(%d+):([%d%.]+),([%d%.]+)$")
                m, x, y = ns.Int(m), tonumber(x), tonumber(y)
                if m and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    local point = { m = m, x = x, y = y }
                    if ns.Geo.IsValidMap(m) then
                        points[#points + 1] = point
                    else
                        local pending = index.pending[m] or {}
                        index.pending[m] = pending
                        pending[#pending + 1], pending[#pending + 2] = id, point
                    end
                end
            end
            index.positions[id] = { name = ns.CleanText(name) or "", points = points,
                observed = mode == "observed" or mode == "player" }
        end
    end
    return index
end

-- Generic and typed trainer observations share the same access semantics.
function Trainers.IsService(service)
    return service == "trainer" or Trainers.services[service] == true or Trainers.additionalServices[service] == true
end

function Trainers.HasService(services)
    for service, value in pairs(type(services) == "table" and services or {}) do
        if value and Trainers.IsService(service) then return true end
    end
    return false
end

-- Access is account-wide; a second observed faction must not erase the first.
function Trainers.MergeAccess(a, b)
    a, b = ns.Str(a) or "", ns.Str(b) or ""
    local both = a .. b
    local result = (both:find("A", 1, true) and "A" or "") .. (both:find("H", 1, true) and "H" or "")
    return result ~= "" and result or nil
end

function Trainers.PlayerClass()
    if not UnitClass then return end
    local ok, name, token = pcall(UnitClass, "player")
    name, token = ns.Str(name), ns.Str(token)
    if not ok or not token then return end
    local key = token:lower()
    if not Trainers.classes[key] then return end
    local names = ns.Plain(LOCALIZED_CLASS_NAMES_MALE)
    if type(names) == "table" then name = ns.Str(names[token]) or name end
    return key, ns.CleanText(name) or token
end

-- Only a tradeskill trainer plus one exact game-localized skill-line match
-- is evidence. Names/titles of NPCs and non-tradeskill trainer types never
-- establish a class. The General type does not identify a class.
function Trainers.OpenProfession()
    local tradeskill
    if C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType then
        local ok, value = pcall(C_Trainer.GetTrainerType)
        value = ns.Num(value)
        local expected = ns.Num(Enum.TrainerType.Tradeskills)
        if ok and value and expected then tradeskill = value == expected end
    elseif IsTradeskillTrainer then
        local ok, value = pcall(IsTradeskillTrainer)
        value = ns.Plain(value)
        if ok then tradeskill = value == true end
    end
    if not tradeskill or not GetNumTrainerServices or not GetTrainerServiceSkillLine
        or not C_TradeSkillUI or not C_TradeSkillUI.GetTradeSkillDisplayName then return end
    local ok, count = pcall(GetNumTrainerServices)
    count = ns.Num(count)
    if not ok or not count or count < 1 or count > 1000 or count % 1 ~= 0 then return end
    local names, duplicate = {}, {}
    for _, p in ipairs(Trainers.professions) do
        local success, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, p.id)
        name = ns.Str(name)
        if not success or not name or name == "" then return end
        if names[name] then duplicate[name] = true end
        names[name] = p.key
    end
    local matched
    for i = 1, count do
        local success, name = pcall(GetTrainerServiceSkillLine, i)
        name = ns.Str(name)
        if not success or not name then return end
        if name ~= "" then
            -- Any unrecognized/ambiguous skill line makes the visit generic.
            local key = names[name]
            if not key or duplicate[name] or (matched and matched ~= key) then return end
            matched = key
        end
    end
    return matched
end
