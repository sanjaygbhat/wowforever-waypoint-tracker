-- Offline runtime gates, also invoked by the standard run_tests.lua entrypoint.
-- Child Lua processes isolate mocks and the validators' os.exit calls.
local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end
local lua = arg and arg[-1] or "lua5.1"
local commands = {
    "python3 -B tools/validate_runtime.py selftest",
    "python3 -B tests/check_runtime_reviews.py",
    "python3 -B tools/validate_runtime.py all --reviews tools/validate_runtime_reviews.json",
}
for _, file in ipairs({ "identity", "migration", "secrets", "registrations" }) do
    commands[#commands + 1] = quote(lua) .. " tests/check_runtime_" .. file .. ".lua"
end
commands[#commands + 1] = quote(lua) .. " tests/run_audit_planner.lua --no-client-cache"
for _, command in ipairs(commands) do
    print("Runtime gate: " .. command)
    io.stdout:flush()
    local ok = os.execute(command)
    if ok ~= 0 and ok ~= true then
        error("Runtime gate failed: " .. command)
    end
end
print("Runtime audit gates passed")
