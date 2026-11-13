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
for key in pairs(Trainers.classes) do Trainers.services["trainer_class_" .. key] = true end
for _, p in ipairs(Trainers.professions) do Trainers.services["trainer_profession_" .. p.key] = true end

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
