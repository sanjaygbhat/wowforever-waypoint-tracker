-- Resource budget: what the addon allocates and how many game calls it
-- makes per second of play, in fixed scenarios (tools/perf_profile.lua,
-- without the ones that load the database). Only exact numbers are gated:
-- KB allocated by the addon's own Lua, game API calls and widget calls.
-- They do not depend on the machine's speed and repeat from run to run, so
-- a ceiling a little above the measured value catches a table, a string or
-- a call added to every frame (one small table a frame is 4 KB a second).
-- Times are printed by the tool and never gated here.
--
-- A ceiling that fails after a deliberate change: run
--     lua5.1 tools/perf_profile.lua --quick --verbose
-- to see which handler grew, and raise the ceiling only when the cost is
-- meant.
-- Run from the repository root: lua5.1 tests/run_perf_budget.lua
package.path = "./tests/?.lua;" .. package.path
local P = assert(loadfile("tools/perf_profile.lua"))("module")

-- 300 CPU seconds at most (it takes about ten): a hang fails, not blocks
local results = P.Run({ quick = true, seconds = 300 })

local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end

-- { metric, ceiling }: measured for 1.4.2, with a tenth or more of room
-- (the maths library and table sizes differ a little between machines)
local BUDGET = {
    -- nothing to do: no waypoint
    { "idle.alloc_addon_kb_per_s", 0.5 },
    { "idle.api_calls_per_s", 150 },
    { "idle.widget_calls_per_s", 10 },
    { "idle_moving.alloc_addon_kb_per_s", 2.5 },
    { "idle_moving.api_calls_per_s", 150 },
    { "idle_moving.widget_calls_per_s", 10 },
    { "idle_after_all.alloc_addon_kb_per_s", 0.5 },
    { "idle_after_all.widget_calls_per_s", 10 },
    { "real_route_after_clear.alloc_addon_kb_per_s", 0.5 },
    { "real_route_after_clear.widget_calls_per_s", 10 },
    -- one waypoint: walking to it, standing, and with the arrow turned off
    { "waypoint_walk.alloc_addon_kb_per_s", 52 },
    { "waypoint_walk.api_calls_per_s", 1000 },
    { "waypoint_walk.widget_calls_per_s", 310 },
    { "waypoint_still.alloc_addon_kb_per_s", 4 },
    { "waypoint_still.api_calls_per_s", 640 },
    { "waypoint_still.widget_calls_per_s", 185 },
    { "waypoint_arrow_hidden.alloc_addon_kb_per_s", 3.5 },
    { "waypoint_arrow_hidden.api_calls_per_s", 260 },
    { "waypoint_arrow_hidden.widget_calls_per_s", 220 },
    -- ten waypoints with minimap pins and the coordinates box; maps and window
    { "ten_waypoints.alloc_addon_kb_per_s", 52 },
    { "ten_waypoints.api_calls_per_s", 1020 },
    { "ten_waypoints.widget_calls_per_s", 360 },
    { "worldmap_open.alloc_addon_kb_per_s", 52 },
    { "worldmap_open.widget_calls_per_s", 360 },
    { "window_open.alloc_addon_kb_per_s", 55 },
    { "window_open.widget_calls_per_s", 920 },
    -- Real routes: following a route through two zones (the searches too)
    { "real_route_walk.alloc_addon_kb_per_s", 195 },
    { "real_route_walk.api_calls_per_s", 760 },
    { "real_route_walk.widget_calls_per_s", 330 },
    -- events that come in bursts: per event, with the delayed work they queue
    { "ev_quest_log_update.alloc_addon_kb_per_event", 0.08 },
    { "ev_mouseover.alloc_addon_kb_per_event", 0.01 },
    { "ev_mouseover.api_calls_per_event", 15 },
    { "ev_target.alloc_addon_kb_per_event", 0.01 },
    { "ev_nameplate.alloc_addon_kb_per_event", 0.01 },
    { "ev_spellcast.alloc_addon_kb_per_event", 0.01 },
    { "ev_bag_cooldown.alloc_addon_kb_per_event", 0.01 },
    { "ev_spell_cooldown.alloc_addon_kb_per_event", 0.01 },
    { "ev_chat_addon_other.alloc_addon_kb_per_event", 0.01 },
    { "ev_vignettes.alloc_addon_kb_per_event", 0.01 },
    { "ev_item_info.alloc_addon_kb_per_event", 0.01 },
}

for _, b in ipairs(BUDGET) do
    local name, ceiling = b[1], b[2]
    local value = results[name]
    check(value ~= nil, name .. " was measured")
    if value then
        check(value <= ceiling, ("%s is %.3f, over its budget of %.3f"):format(name, value, ceiling))
    end
end

-- the scenarios ran what they say: an arrow to a waypoint, a followed route
check((results["waypoint_walk.widget_calls_per_s"] or 0) > 60, "the arrow was drawn while walking to the waypoint")
check((results["real_route_walk.alloc_addon_kb_per_s"] or 0) > 5, "the route scenario planned a route")
check(#P.mock.errors == 0, "no Lua errors while profiling: " .. tostring(P.mock.errors[1]))

print(("Performance budget: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
