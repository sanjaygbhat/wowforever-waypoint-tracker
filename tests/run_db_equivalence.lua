-- The Find database is the same however it is built: read all at once
-- (DB.Load), read a little each frame (DB.LoadAsync), or by the loader of
-- 1.4.2 (tests/fixtures/loader-1.4.2: Database.lua, Learn.lua and Core.lua
-- as released, which read every shipped store whole on every merge).
-- tests/db_dump.lua builds it each way in a process of its own and writes
-- every entry, field by field, then every change made by a history of
-- merges: more discoveries, discoveries taken back, an import, records put
-- into a shipped store and stores put in the shipped ones' place. The
-- stores are given more than they hold today (corrections, a curated
-- mailbox, records waiting for an NPC only you have seen, objectives
-- matched by name), so every part of a merge is compared. The files
-- must be the same, line for line: so yours still win over the community's,
-- and the community's over the curated store's, with the two shipped stores
-- kept only as what a merge needs of them.
-- Run from the repository root: lua5.1 tests/run_db_equivalence.lua
local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end
local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end
local lua = arg and arg[-1] or "lua5.1"
-- os.tmpname() needs a writable /tmp; honour TMPDIR where one is given.
math.randomseed(os.time())
local function tmpName(tag)
    local dir = os.getenv("TMPDIR")
    if dir and dir ~= "" then
        return (dir:gsub("/+$", "")) .. "/wt_db_" .. tag .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e9))
    end
    return os.tmpname()
end

local function Dump(locale, side, mode)
    local path = tmpName(locale .. "_" .. mode)
    local status = os.execute(("WT_LOCALE=%s WT_SIDE=%s %s tests/db_dump.lua %s %s"):format(locale, side, quote(lua), mode, quote(path)))
    check(status == 0 or status == true, ("%s %s %s: the database was built and written"):format(locale, side, mode))
    return path
end

-- Line by line; returns how many lines, the first few that differ, and how many stages.
local function Compare(pathA, pathB)
    local a, b = io.open(pathA), io.open(pathB)
    if not (a and b) then
        return 0, { "a file is missing" }, 0
    end
    local n, differ, stages, last = 0, {}, 0, nil
    while true do
        local x, y = a:read("*l"), b:read("*l")
        if not x and not y then break end
        n, last = n + 1, x
        if x and x:find("^== ") then stages = stages + 1 end
        if x ~= y and #differ < 5 then
            local at = 1
            while x and y and at <= #x and x:sub(at, at) == y:sub(at, at) do at = at + 1 end
            differ[#differ + 1] = ("line %d: %s | %s"):format(n, x and x:sub(math.max(1, at - 60), at + 80) or "<end>",
                y and y:sub(math.max(1, at - 60), at + 80) or "<end>")
        elseif x ~= y and differ[#differ] ~= "..." then
            differ[#differ + 1] = "..."
        end
    end
    a:close()
    b:close()
    if last ~= "errors 0 nil" then
        differ[#differ + 1] = "the history did not end without errors: " .. tostring(last)
    end
    return n, differ, stages
end

-- Every way, against the released loader: in English as an Alliance
-- player, and in another language (with the English fallback names, and
-- esMX reading esES) as a Horde player
for _, case in ipairs({ { "enUS", "Alliance" }, { "esMX", "Horde" } }) do
    local locale, side = case[1], case[2]
    local reference = Dump(locale, side, "reference")
    for _, mode in ipairs({ "sync", "sliced" }) do
        local path = Dump(locale, side, mode)
        local lines, differ, stages = Compare(reference, path)
        local what = locale .. " " .. side .. " " .. mode
        check(lines > 30000 and stages == 11, ("%s: every entry and eleven stages were written (%d lines, %d stages)"):format(what, lines, stages or 0))
        check(#differ == 0, ("%s: differs from the 1.4.2 loader\n  %s"):format(what, table.concat(differ, "\n  ")))
        os.remove(path)
    end
    os.remove(reference)
end

print(("Database equivalence: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
