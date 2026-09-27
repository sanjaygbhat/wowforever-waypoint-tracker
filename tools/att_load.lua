-- Loads All The Things' compiled WoW Forever database (db/Camelot) outside
-- the game and returns its category tree. Used by tools/build_att.lua.
local M = {}

-- anything ATT asks of itself: answers with more of the same
local function Universal()
    local u = {}
    return setmetatable(u, {
        __index = function(t, k)
            local v = Universal()
            rawset(t, k, v)
            return v
        end,
        __call = function()
            return nil
        end,
    })
end

local function Constructor(kind)
    return function(a, b, c)
        local t
        if type(b) == "table" then
            t = b
        elseif type(c) == "table" then
            t = c
        else
            t = {}
        end
        t._kind, t._id = kind, a
        if kind == "itemsource" then
            t._id = b -- s(sourceID, itemID, {...})
            t._source = a
        end
        return t
    end
end

local KINDS = {
    CreateQuest = "quest", CreateNPC = "npc", CreateObject = "object", CreateItem = "item",
    CreateItemSource = "itemsource", CreateMap = "map", CreateFlightPath = "flight",
    CreateQuestObjective = "objective", CreateHeader = "header", CreateCustomHeader = "header",
    CreateRecipe = "recipe", CreateAchievement = "achievement", CreateAchievementCriteria = "criteria",
    CreateExploration = "exploration", CreateFaction = "faction", CreateFilter = "filter",
    CreateMount = "mount", CreateProfession = "profession", CreateInstance = "instance",
    CreateCategory = "category", CreateCharacterClass = "class", CreateExpansion = "expansion",
}

function M.Load(dir)
    local handlers = {}
    local ns = setmetatable({}, {
        __index = function(t, k)
            if KINDS[k] then
                return Constructor(KINDS[k])
            elseif type(k) == "string" and k:find("^Create") then
                return Constructor(k:sub(7):lower())
            end
            local v = Universal()
            rawset(t, k, v)
            return v
        end,
    })
    ns.AddEventHandler = function(event, fn)
        handlers[#handlers + 1] = fn
    end
    ns.L = Universal()
    -- quest data helpers just hand the data back
    ns.ResolveQuestData = function(t)
        return t
    end
    local xml = assert(io.open(dir .. "/Database.xml")):read("*a")
    for file in xml:gmatch('Script file="([^"]+)"') do
        local path = dir .. "/" .. file:gsub("\\", "/")
        local src = assert(io.open(path, "rb")):read("*a"):gsub("^\239\187\191", "")
        local chunk = assert(loadstring(src, "@" .. path))
        local ok, err = pcall(chunk, "AllTheThings", ns, Universal())
        if not ok then
            io.stderr:write("skipped ", file, ": ", tostring(err), "\n")
        end
    end
    local categories = {}
    for _, fn in ipairs(handlers) do
        local ok, err = pcall(fn, categories)
        if not ok then
            io.stderr:write("handler failed: ", tostring(err), "\n")
        end
    end
    return categories
end

return M
