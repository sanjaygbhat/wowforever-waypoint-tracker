-- Standard review regression gate. Each child gets an isolated mock/API state.
local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local lua = quote(arg and arg[-1] or 'lua5.1')
local scenarios = {
    'run_quest_ownership', 'run_scheduled_safety', 'run_ghost_retention',
    'run_moved_goal', 'run_polyline_helpers', 'run_tracker_input', 'run_planner_scaling',
    'run_travel_preference', 'run_travel_projection', 'run_travel_reroute', 'run_ghost_travel',
}
local commands = {}
for _, name in ipairs(scenarios) do commands[#commands+1] = lua .. ' tests/' .. name .. '.lua' end
for _, mode in ipairs({'preference', 'abandon', 'ghost', 'ghost_arrival', 'ghost_arrival_selection'}) do
    commands[#commands+1] = lua .. ' tests/run_follow_regressions.lua ' .. mode
end
local failed = 0
for _, command in ipairs(commands) do
    print('Review regression: ' .. command); io.stdout:flush()
    local status = os.execute(command)
    if status ~= 0 and status ~= true then failed = failed+1 end
end
print(('Review regression gates: %d passed, %d failed'):format(#commands-failed, failed))
os.exit(failed==0 and 0 or 1)
