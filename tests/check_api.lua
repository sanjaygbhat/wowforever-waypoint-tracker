-- Looks through the addon's code for ways of reading game data that have
-- broken in WoW Forever. Run from the repository root:
--     lua5.1 tests/check_api.lua
local files = {}
local list = io.popen("ls WaypointTracker/*.lua")
for f in list:lines() do
    files[#files + 1] = f
end
list:close()

local rules = {
    -- positions can be plain { x, y } tables: read them with ns.XY(pos)
    { pattern = ":GetXY%(", allow = "function ns%.XY", why = "use ns.XY(pos), some positions have no :GetXY()" },
}

local problems = 0
for _, file in ipairs(files) do
    local text = assert(io.open(file)):read("*a")
    local n = 0
    local insideAllowed
    for line in text:gmatch("([^\n]*)\n?") do
        n = n + 1
        for _, rule in ipairs(rules) do
            if line:find(rule.allow) then
                insideAllowed = rule
            elseif insideAllowed == rule and line:match("^end") then
                insideAllowed = nil
            elseif insideAllowed ~= rule and not line:match("^%s*%-%-") and line:find(rule.pattern) then
                print(("%s:%d: %s"):format(file, n, rule.why))
                problems = problems + 1
            end
        end
    end
end
if problems > 0 then
    os.exit(1)
end
print("Game API use OK")
