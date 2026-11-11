-- Looks through the addon's code for ways of reading game data that have
-- broken in WoW Forever. Run from the repository root:
--     lua5.1 tests/check_api.lua
local files = {}
local list = io.popen("ls WaypointTracker/*.lua")
for f in list:lines() do
    files[#files + 1] = f
end
list:close()

local NEVER = "\0never" -- no line allows these
local rules = {
    -- positions can be plain { x, y } tables: read them with ns.XY(pos)
    { pattern = ":GetXY%(", allow = "function ns%.XY", why = "use ns.XY(pos), some positions have no :GetXY()" },
    -- Taint (1.2.4 CompactUnitFrame "secret boolean value ... tainted by
    -- 'WaypointTracker'"): Blizzard code run from addon code stays tainted.
    -- Open Edit Mode with ShowUIPanel(EditModeManagerFrame), like the game menu.
    { pattern = "[:%.]EnterEditMode", allow = NEVER, why = "taints Edit Mode for party/raid frames; use ShowUIPanel(EditModeManagerFrame)" },
    { pattern = "[:%.]ExitEditMode", allow = NEVER, why = "taints Edit Mode for party/raid frames; use HideUIPanel(EditModeManagerFrame)" },
    { pattern = "SettingsPanel[:%.]Hide", allow = NEVER, why = "SettingsPanel is not a managed panel: hiding it from addon code taints it" },
    { pattern = "SettingsPanel[:%.]Close", allow = NEVER, why = "SettingsPanel is not a managed panel: closing it from addon code taints it" },
    { pattern = "HideUIPanel[%s%(,]+SettingsPanel", allow = NEVER, why = "SettingsPanel is not a managed panel: HideUIPanel hides it directly, tainted" },
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
