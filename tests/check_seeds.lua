-- Validate the English seed data without loading the addon or WoW globals.
-- Run from the repository root: lua5.1 tests/check_seeds.lua
local env = { WaypointTrackerData = {} }
local chunk = assert(loadfile("WaypointTracker_Data/RouteSeeds.lua"))
setfenv(chunk, env)
chunk()
local seeds = assert(env.WaypointTrackerData.routeSeeds, "missing routeSeeds")
assert(type(seeds) == "string", "routeSeeds must be a string")

local categories = {
    mining = true, herbs = true, skinning = true, fishing = true,
    farming = true, treasure = true, quests = true, travel = true,
    dungeons = true, other = true,
}
local modes = { order = true, loop = true, nearest = true }
local factions = { [""] = true, A = true, H = true }
local ALLOWED_DIGIT_NAMES = { ["Chasing A-Me 01"] = true }
-- REVIEW3 S4 explicitly requires this 37-character name for consistency with
-- Dungeon entrances of Kalimdor. Other names retain the design's 36-char limit.
local NAME_LIMITS = { ["Dungeon entrances of Eastern Kingdoms"] = 37 }
local forbiddenPrefixes = {
    "Quest:", "Chain:", "Quests:", "Skinning", "Cloth ", "Mats ", "Meat ",
    "Rep ", "Gold ", "Eggs ", "Clams ", "Silk ", "Water ", "Life ", "Earth ",
    "Fire ", "Air ", "Pet ", "Formula ", "Felcloth ", "Turn-ins ", "Trinket ",
    "Leather farming", "Neutral town", "Dungeon entrances:", "Sightseeing:",
    "SoD ", "(A) ", "(H) ",
}
-- N2 forbids category labels, but its examples and N5 explicitly use Silk Cloth
-- and Gold from <source>. These are item/goal phrases, not category labels.
local itemPrefixes = { "Silk Cloth from ", "Silk Cloth at ", "Gold from " }
local itemTitles = {
    ["Gold Dust and Kobold Candles"] = true,
    ["Water Pouch Bounty"] = true,
    ["Water Pouches from Wastewander camps"] = true,
    ["Earth Shield rune quest chain"] = true,
}
local abbreviations = {
    "EK", "STV", "EPL", "WPL", "BWL", "UBRS", "LBRS", "BRD", "BFD", "SoD",
    "SM", "DM", "WC", "ZF", "ZG", "MC", "AQ", "Lv", "W.", "E.", "N.", "S.",
    "req", "rep",
}

local function StartsWith(text, prefix)
    return text:sub(1, #prefix) == prefix
end

local function ItemName(name)
    if itemTitles[name] then return true end
    for _, prefix in ipairs(itemPrefixes) do
        if StartsWith(name, prefix) and #name > #prefix then return true end
    end
end

local function HasToken(text, token)
    local from = 1
    while true do
        local first, last = text:find(token, from, true)
        if not first then return false end
        if not text:sub(first - 1, first - 1):match("[%w_]")
            and not text:sub(last + 1, last + 1):match("[%w_]") then
            return true
        end
        from = last + 1
    end
end

local function PositiveInteger(text)
    return text:match("^[1-9]%d*$") ~= nil
end

local function Levels(text)
    if text == "" or PositiveInteger(text) then return true end
    local minimum = text:match("^([1-9]%d*)%+$")
    if minimum then return true end
    local lo, hi = text:match("^([1-9]%d*)%-([1-9]%d*)$")
    return lo ~= nil and tonumber(lo) <= tonumber(hi)
end

local function Stop(token)
    local kind = token:sub(1, 1)
    if kind == "N" or kind == "Q" then
        return PositiveInteger(token:sub(2))
    elseif kind == "U" or kind == "O" then
        local ids, map = token:sub(2):match("^([%d,]+)@([1-9]%d*)$")
        if not ids or not map then return false end
        local list = {}
        for id in ids:gmatch("[^,]+") do
            if not PositiveInteger(id) then return false end
            list[#list + 1] = id
        end
        return #list > 0 and table.concat(list, ",") == ids
    elseif kind == "P" then
        local map, x, y, title = token:match("^P([1-9]%d*):([%d%.]+),([%d%.]+),(.*)$")
        x, y = tonumber(x), tonumber(y)
        return map ~= nil and x ~= nil and y ~= nil and title ~= nil
            and x >= 0 and x <= 100 and y >= 0 and y <= 100
    end
    return false
end

local triples, names, rows = {}, {}, {}
local count, stopsHash = 0, 0
local function Check(ok, why)
    assert(ok, ("Seed %d: %s"):format(count, why))
end

for line in (seeds:gsub("\n$", "") .. "\n"):gmatch("([^\n]*)\n") do
    count = count + 1
    local cat, mode, faction, levels, name, note, spec = line:match(
        "^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    Check(spec ~= nil, "expected seven tab-separated columns")
    Check(categories[cat], "unknown category: " .. cat)
    Check(modes[mode], "unknown mode: " .. mode)
    Check(factions[faction], "unknown faction: " .. faction)
    Check(Levels(levels), "invalid levels: " .. levels)
    Check(name ~= "" and not name:match("^%s") and not name:match("%s$"), "empty or padded name")
    -- Count UTF-8 characters rather than bytes (the current data is ASCII).
    local limit = NAME_LIMITS[name] or 36
    Check(#name:gsub("[\128-\191]", "") <= limit, "name exceeds " .. limit .. " characters: " .. name)
    local title = name:gsub(" chain$", "")
    Check(not name:find("%d") or ALLOWED_DIGIT_NAMES[title], "digits in name: " .. name)
    Check(not title:match(" Tour$"), "invented tour suffix should use sentence case: " .. name)
    for _, prefix in ipairs(forbiddenPrefixes) do
        Check(not StartsWith(name, prefix) or ItemName(name), "category/faction prefix: " .. name)
    end
    for _, token in ipairs(abbreviations) do
        Check(not HasToken(name, token), "abbreviation " .. token .. " in name: " .. name)
        Check(not HasToken(note, token), "abbreviation " .. token .. " in note: " .. note)
    end
    Check(#note <= 140, "note exceeds the 140-byte Routes.MAX_NOTE limit: " .. name)
    Check(not note:match("^Lv%s*%d"), "level prefix belongs in levels: " .. name)
    Check(levels ~= "" or not note:match("^Level %d"), "level prefix belongs in levels: " .. name)
    Check(not note:find("Eastern Kingdoms tour;", 1, true), "redundant tour fragment: " .. name)

    local key = cat .. "|" .. faction .. "|" .. spec
    Check(not triples[key], "duplicate category/faction/stops with seed " .. tostring(triples[key]))
    triples[key] = count
    for _, other in ipairs(names[name] or {}) do
        Check(faction ~= "" and other.faction ~= "" and faction ~= other.faction,
            "name also visible in seed " .. other.line .. ": " .. name)
    end
    names[name] = names[name] or {}
    names[name][#names[name] + 1] = { faction = faction, line = count }

    Check(spec ~= "", "empty stops: " .. name)
    local tokens = {}
    for token in spec:gmatch("[^;]+") do
        Check(Stop(token), "invalid stop: " .. token)
        tokens[#tokens + 1] = token
    end
    Check(table.concat(tokens, ";") == spec, "empty stop token: " .. name)
    -- Migration invariant: stops are the future seed IDs. Preserve every byte
    -- and the original row order; update this fingerprint only for a data edit.
    for i = 1, #spec + 1 do
        stopsHash = (stopsHash * 65599 + (i <= #spec and spec:byte(i) or 10)) % 4294967296
    end
    rows[count] = { faction = faction, levels = levels, name = name, note = note }
end
assert(count == 876, "expected 876 seeds, got " .. count)
assert(stopsHash == 1589333783, "stop bytes or row order changed")

-- Required design examples, identified by their original seed order.
local examples = {
    { 1, "", "5-8", "Boars for Light Leather" },
    { 179, "", "32-35", "Silk Cloth from Syndicate camps" },
    { 181, "", "35-40", "Silk Cloth from Syndicate assassins" },
    { 458, "A", "9", "Red Linen Goods" },
    { 423, "H", "43", "Venom Bottles: Eastern Kingdoms tour" },
    { 755, "A", "2-25", "Mage runes: Eastern Kingdoms tour" },
    { 744, "A", "", "Library books: all twenty" },
    { 823, "A", "", "Flight paths of Eastern Kingdoms" },
    { 822, "", "", "Blackwing Lair attunement" },
    -- REVIEW3 S3-S5: sentence-case tours, real quest titles and travel goals.
    { 578, "", "52-56", "Linken's Adventure chain" },
    { 579, "H", "50", "Un'Goro soil tour" },
    { 580, "A", "50", "Un'Goro soil tour" },
    { 593, "", "49", "Noggenfogger Elixir chain" },
    { 630, "", "17-21", "Wailing Caverns pickup tour" },
    { 631, "H", "18", "Serpentbloom pickup tour" },
    { 676, "", "57-59", "High Chief Winterfall chain" },
    { 680, "", "56", "Kel'Theril relics tour" },
    { 735, "", "20", "Deepmoss spider eggs tour" },
    { 797, "", "", "Dungeon entrances of Eastern Kingdoms" },
    { 798, "", "", "Dungeon entrances of Kalimdor" },
    { 876, "", "", "Faldir's Cove lookout" },
}
for _, example in ipairs(examples) do
    local row = rows[example[1]]
    assert(row.faction == example[2] and row.levels == example[3] and row.name == example[4],
        "design example changed at seed " .. example[1])
end
assert(StartsWith(rows[458].note, "Gather"), "Red Linen Goods note should start with Gather")
assert(StartsWith(rows[423].note, "Search"), "Venom Bottles note should start with Search")
assert(rows[181].note == "Silk Cloth from higher-level Syndicate camps; casters and Assassins require controlled pulls.",
    "Syndicate assassins note should retain its pull advice")

-- REVIEW3 S2: structured levels power detail metadata and For my level sorting;
-- the note retains the class/profession restriction and useful instructions.
local classChains = {
    { 541, "10-11", "warriors" },
    { 542, "10", "warriors" },
    { 543, "10-11", "warriors" },
    { 544, "10", "hunters" },
    { 545, "4", "priests" },
    { 546, "4", "priests" },
    { 547, "4", "priests" },
    { 548, "16-20", "rogues" },
    { 549, "20-24", "rogues" },
    { 550, "12-13", "paladins" },
    { 551, "12-13", "paladins" },
    { 552, "52", "warriors" },
    { 553, "40", "blacksmiths" },
}
for _, example in ipairs(classChains) do
    local row = rows[example[1]]
    assert(row.levels == example[2], "class-chain levels changed at seed " .. example[1])
    local prefix = "For " .. example[3] .. "; "
    assert(StartsWith(row.note, prefix) and #row.note > #prefix,
        "class-chain note should retain its restriction and advice at seed " .. example[1])
end
print(count .. " seeds OK")
