-- The terrain sampler (five times a second) only runs where its records can
-- be applied: Terrain.Record takes them on client build 70338 alone (or when
-- the build can't be read). On any other build nothing it writes is ever
-- read, so the ticker stops, after reading the travel network at its first
-- tick as sampling always did. On 70338 nothing changes.
-- Run from the repository root: lua5.1 tests/run_terrain_sampler.lua
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function check(ok, message)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. message) end
end

-- one of the eight state questions only the sampler asks
local asked = 0
function IsFalling()
    asked = asked + 1
    return false
end
function GetUnitSpeed() return 7, 7, 7, 4.7 end
local LIVE = function() return "1.60.1", "70862", "Nov 10 2026", 16001 end
local SURVEYED = function() return "1.60.1", "70338", "Oct 20 2026", 16001 end
GetBuildInfo = LIVE

local ns = M.LoadAddon("WaypointTracker", "WaypointTracker")
local Terrain = ns.Terrain
local samples, loads = 0, 0
local sample = Terrain.Sample
Terrain.Sample = function(...)
    samples = samples + 1
    return sample(...)
end
ns.On("TRAVEL_LOADED", function() loads = loads + 1 end)
M.FireEvent("ADDON_LOADED", "WaypointTracker")
M.FireEvent("PLAYER_LOGIN")
local ticker = Terrain._ticker
check(ticker and ticker:IsShown(), "the ticker starts with the addon")

-- A live build, Real routes off: nothing to read, nothing to sample
ns.settings.realRoutes = false
check(Terrain.RecordsApply() == false, "live build: records are not applied")
M.Tick(1, 0.05)
check(samples == 0 and asked == 0, "live build: no sample is taken (" .. samples .. ")")
check(loads == 0, "live build, Real routes off: the travel network is not read")
check(not ticker:IsShown(), "live build: the ticker stops")

-- Real routes on: the network is read at the next tick, as sampling did, and the ticker stops again
ns.Set("realRoutes", true)
check(ticker:IsShown(), "a setting change starts the ticker")
M.Tick(0.3, 0.05)
check(loads == 1, "live build: the travel network is read at the first tick with Real routes on (" .. loads .. ")")
check(samples == 0 and asked == 0 and not ticker:IsShown(), "live build: still no sample, and the ticker stops again")
M.Tick(5, 0.05)
check(samples == 0 and asked == 0 and loads == 1, "live build: nothing more in five seconds")

-- A stored record: taken on the surveyed build, refused on a live one, by the same test
local d = ns.Travel.Data()
local e
for _, proof in pairs(d.walkEvidence) do
    if proof.state == "TERRAIN_CLEAR" then e = proof; break end
end
local st = Terrain.Store()
st.records[e.key] = { state = "refuted", build = d.buildKey, scope = 0, when = 1, expires = 2e9 + 1e9, count = 1 }
check(Terrain.Record(e) == nil, "live build: a stored record is not applied")
GetBuildInfo = SURVEYED
check(Terrain.RecordsApply() == true and Terrain.Record(e) ~= nil, "build 70338: the same record is applied")

-- The surveyed build: five samples a second, for as long as you play
ns.Set("realRoutes", true)
samples, asked = 0, 0
M.Tick(2, 0.05)
check(samples >= 8 and samples <= 10 and asked == samples, "build 70338: five samples a second (" .. samples .. " in 2 s)")
check(ticker:IsShown(), "build 70338: the ticker keeps running")
check(loads == 1, "the travel network was read once")

-- A build that can't be read is treated as Terrain.Record treats it: records apply
for label, fn in pairs({ ["no GetBuildInfo"] = false, ["no build number"] = function() return "1.60.1", nil end }) do
    GetBuildInfo = fn or nil
    samples = 0
    M.Tick(1, 0.05)
    check(Terrain.RecordsApply() == true and Terrain.Record(e) ~= nil, label .. ": records apply")
    check(samples >= 4 and ticker:IsShown(), label .. ": sampling goes on (" .. samples .. " in 1 s)")
end

-- Back on a live build: it stops at the next tick
GetBuildInfo = LIVE
samples = 0
M.Tick(1, 0.05)
check(samples == 0 and not ticker:IsShown(), "live build again: the ticker stops at its next tick")

check(#M.errors == 0, "no Lua errors: " .. tostring(M.errors[1]))
print(("Terrain sampler: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
