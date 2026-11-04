-- Checks every translation against English: all keys present, no unknown
-- keys, no unfinished translations, and the same %s / %d / %.1f placeholders
-- in the same order. Also catches deleted keys still used by addon code.
--     lua5.1 tests/check_locales.lua
local LOCALES = { "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "zhCN", "zhTW", "koKR" }
local FILES = { deDE = "deDE", frFR = "frFR", esES = "esES", esMX = "esES", ptBR = "ptBR", ruRU = "ruRU", zhCN = "zhCN", zhTW = "zhTW", koKR = "koKR" }
local DIR = "WaypointTracker/Locales/"

local function load(locale, file)
    local ns = {}
    _G.GetLocale = function()
        return locale
    end
    assert(loadfile(DIR .. "enUS.lua"))("WaypointTracker", ns)
    local english = {}
    for k, v in pairs(ns.L) do
        english[k] = v
    end
    local seen = {}
    -- record which keys the locale file sets
    local proxy = setmetatable({}, {
        __newindex = function(_, k, v)
            seen[k] = v
        end,
        __index = ns.L,
    })
    local ns2 = { L = proxy }
    if file then
        assert(loadfile(DIR .. file .. ".lua"))("WaypointTracker", ns2)
    end
    return english, seen
end

local function placeholders(s)
    local out = {}
    for p in tostring(s):gmatch("%%[%-%d%.]*[sdfgx]") do
        out[#out + 1] = p
    end
    return table.concat(out, " ")
end

local problems = 0
local english = load("enUS")
local files = assert(io.popen("ls WaypointTracker/*.lua"))
for file in files:lines() do
    local source = assert(io.open(file))
    local text = source:read("*a")
    source:close()
    local checked = {}
    for key in text:gmatch("%f[%w]L%.([A-Z][A-Z0-9_]+)") do
        if not checked[key] and english[key] == nil then
            checked[key] = true
            problems = problems + 1
            print(("%s: missing English key %s"):format(file, key))
        end
    end
end
files:close()
local total = 0
for _ in pairs(english) do
    total = total + 1
end
for _, locale in ipairs(LOCALES) do
    local source = assert(io.open(DIR .. FILES[locale] .. ".lua"))
    local text = source:read("*a")
    source:close()
    for key in text:gmatch("L%.([A-Z][A-Z0-9_]+)[^\n]*%-%- TODO translate") do
        problems = problems + 1
        print(("%s: unfinished translation %s"):format(locale, key))
    end
    local _, seen = load(locale, FILES[locale])
    local missing, count = {}, 0
    for k, v in pairs(english) do
        local t = seen[k]
        if t == nil then
            missing[#missing + 1] = k
        else
            count = count + 1
            if placeholders(t) ~= placeholders(v) then
                problems = problems + 1
                print(("%s %s: placeholders differ: '%s' vs '%s'"):format(locale, k, placeholders(t), placeholders(v)))
            end
            local args = {}
            for p in tostring(t):gmatch("%%[%-%d%.]*([sdfgx])") do
                args[#args + 1] = (p == "s") and "x" or 1
            end
            local ok = pcall(string.format, t, unpack(args))
            if not ok and placeholders(t) ~= "" then
                problems = problems + 1
                print(("%s %s: string.format fails"):format(locale, k))
            end
        end
    end
    for k in pairs(seen) do
        if english[k] == nil then
            problems = problems + 1
            print(("%s: unknown key %s"):format(locale, k))
        end
    end
    table.sort(missing)
    if #missing > 0 then
        problems = problems + #missing
        print(("%s: missing %d keys: %s"):format(locale, #missing, table.concat(missing, ", ")))
    end
    print(("%s: %d/%d strings"):format(locale, count, total))
end
print(problems == 0 and "All translations OK" or (problems .. " problems"))
os.exit(problems == 0 and 0 or 1)
