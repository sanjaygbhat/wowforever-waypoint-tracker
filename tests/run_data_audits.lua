-- Required offline data gates, also called by tests/run_tests.lua.
local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end
local lua = arg and arg[-1] or "lua5.1"
local ok = os.execute("python3 -B tools/validate_data.py --lua " .. quote(lua))
if ok ~= 0 and ok ~= true then
    error("Data audit gates failed; see the validator's entries and sources above")
end
