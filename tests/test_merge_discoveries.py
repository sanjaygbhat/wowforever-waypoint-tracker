#!/usr/bin/env python3
"""Checks tools/merge_discoveries.py: reading a saved file as data, the
shared text it makes, leaving out what the database has, and refusing
anything that isn't plain data. Run: python3 tests/test_merge_discoveries.py
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import merge_discoveries as md  # noqa: E402

failures = 0
passed = 0


def check(cond, msg):
    global failures, passed
    if cond:
        passed += 1
    else:
        failures += 1
        print("FAIL:", msg)


# a saved file the way the game writes it
SAVED = r'''
WaypointTrackerDB = {
	["version"] = 3,
	["learned"] = {
		["npcs"] = {
			[248197] = {
				["title"] = "Blacksmith",
				["fac"] = "H",
				["name"] = "Gor'mak",
				["hostile"] = false,
				["level"] = 60,
				["services"] = {
					["vendor"] = true,
				},
				["spots"] = {
					[1413] = {
						0.498, -- [1]
						0.296, -- [2]
					},
				},
			},
			[3] = {
				["name"] = "Flesh Eater",
				["hostile"] = true,
				["spots"] = {
					[1431] = {
						0.24, -- [1]
						0.39, -- [2]
					},
				},
			},
			[248198] = {
				["name"] = "|cffff0000Sneaky|r |Hurl:x|hlink|h\tname",
				["spots"] = {
					[1413] = {
						5, -- [1]
						0.5, -- [2]
					},
				},
			},
		},
		["objects"] = {
		},
		["quests"] = {
			[90001] = {
				["title"] = "A New Quest",
				["giver"] = "U248197",
				["objs"] = {
					"item:Plans", -- [1]
					"monster:Scarlet Trainee", -- [2]
				},
			},
		},
		["items"] = {
			[248601] = {
				["name"] = "Plans: Merchant's Belt",
				["sold"] = {
					["U248197"] = true,
					["X1"] = true,
				},
			},
		},
		["mailboxes"] = {
		},
		["fixes"] = {
			["N3"] = {
				{
					["wrong"] = {
						1431, -- [1]
						0.24, -- [2]
						0.39, -- [3]
					},
					["right"] = {
						1431, -- [1]
						0.3, -- [2]
						0.4, -- [3]
					},
				}, -- [1]
				{
					["wrong"] = {
						1431, -- [1]
						0.5, -- [2]
						0.5, -- [3]
					},
					["shared"] = true,
				}, -- [2]
			},
			["X9"] = {
			},
		},
	},
	["questTitles"] = {
		["locale"] = "enUS",
		["names"] = {
		},
	},
}
WaypointTrackerDB2 = nil
'''

with tempfile.TemporaryDirectory() as tmp:
    saved = Path(tmp) / "WaypointTracker.lua"
    saved.write_text(SAVED, encoding="utf-8")
    text = md.saved_to_text(str(saved))
    lines = text.split("\n")
    check(lines[0] == "WTL1\tenUS\tsaved", "header names the language: " + lines[0])
    check("N\t248197\tGor'mak\t0\t60\tvendor\t1413:498,296\tH\tBlacksmith" in lines, "an NPC with its title, faction and spot")
    check("I\t248601\tPlans: Merchant's Belt\t\tU248197" in lines, "a vendor's stock, without junk refs")
    check(any(l.startswith("Q\t90001\tA New Quest\t\tU248197\t") and l.endswith("item:Plans|monster:Scarlet Trainee") for l in lines), "a quest with its giver and objectives")
    sneaky = [l for l in lines if l.startswith("N\t248198\t")][0].split("\t")
    check(sneaky[2] == "Sneaky link name" and sneaky[6] == "", "names are cleaned and bad spots dropped: " + repr(sneaky[2:7]))

    check("C\tN\t3\t1431:240,390\t1431:300,400" in lines and not any(l.startswith("C\tN\t3\t1431:500") for l in lines), "the player's own corrections, not imported ones")
    db = {}
    md.load(text, db)
    shipped = md.Shipped()
    out = md.dump(db, shipped).split("\n")
    check(any(l.startswith("N\t248197\t") for l in out), "a new NPC is kept")
    check(not any(l.startswith("N\t3\t") for l in out), "a classic enemy with nothing new is left out")
    check(any(l.startswith("I\t248601\t") for l in out), "a new vendor is kept")
    # corrections to classic entries are kept: a new spot, or friend/foe the other way round
    md.load("WTL1\tenUS\t1\nN\t3\tFlesh Eater\t1\t\t\t1431:800,800", db)
    check(any(l.startswith("N\t3\t") for l in md.dump(db, shipped).split("\n")), "a classic enemy seen somewhere new is kept")
    db.pop(("N", 3))
    md.load("WTL1\tenUS\t1\nN\t3\tFlesh Eater\t0\t\t\t1431:240,390", db)
    check(any(l.startswith("N\t3\t") for l in md.dump(db, shipped).split("\n")), "a classic enemy seen as friendly is kept")
    db.pop(("N", 3))
    md.load(text, db)
    check(len(shipped.area_map) >= 40 and shipped.area_map.get(12) == 1429, "classic zones line up with the game's maps")

    # the same file again: nothing doubles up
    md.load(text, db)
    check(md.dump(db, shipped).split("\n") == out, "merging the same file twice changes nothing")

    check("C\tN\t3\t1431:240,390\t1431:300,400" in out, "corrections are always kept")
    md.load("WTL1\tenUS\t1\nC\tN\t3\t1431:240,390\t1431:310,410\nC\tQ\t3\t1:1,1\t\nC\tN\t4\t1:5000,1\t\nC\tN\t5\t\t", db)
    out2 = md.dump(db, shipped).split("\n")
    check("C\tN\t3\t1431:240,390\t1431:310,410" in out2 and "C\tN\t3\t1431:240,390\t1431:300,400" not in out2, "a later correction of the same spot wins")
    check(not any(l.startswith(("C\tQ", "C\tN\t4", "C\tN\t5")) for l in out2), "broken corrections are dropped")

    # a later English observation corrects the title
    md.load("WTL1\tenUS\t1\nN\t248197\tGor'mak\t0\t60\t\t\tH\tMaster Blacksmith", db)
    check([l for l in md.dump(db, shipped).split("\n") if l.startswith("N\t248197\t")][0].endswith("\tMaster Blacksmith"), "newer English title wins")
    md.load("WTL1\tdeDE\t1\nN\t248197\tGor'mak\t0\t60\t\t\tH\tSchmied", db)
    check([l for l in md.dump(db, shipped).split("\n") if l.startswith("N\t248197\t")][0].endswith("\tMaster Blacksmith"), "other languages don't replace English text")

    # anything that isn't plain data is refused
    for bad in ['os.execute("rm -rf /")', 'WaypointTrackerDB = { [1] = loadstring("x") }', 'WaypointTrackerDB = function() end',
                'WaypointTrackerDB = ' + "{" * 100 + "}" * 100]:
        p = Path(tmp) / "bad.lua"
        p.write_text(bad, encoding="utf-8")
        try:
            md.saved_to_text(str(p))
            check(False, "refused: " + bad[:40])
        except ValueError:
            check(True, "refused")

    # spot limits: 30 per map, maps 1..2^31
    db = {}
    many = ",".join(f"{i * 10},{i * 10}" for i in range(60))
    md.load(f"WTL1\tenUS\t1\nN\t999999\tX\t\t\t\t5:{many};99999999999:1,1", db)
    e = db[("N", 999999)]
    check(len(e["spots"][5]) == 30 and 99999999999 not in e["spots"], "spots are limited")

# a name can never end the shipped file's long string and run as code
import subprocess  # noqa: E402

evil = "N\t5\tx]==]os.exit(3)--[==[\t\t\t\t\t\t]===]"
long = md.lua_long("WTL1\tcommunity\t1\n" + evil)
check(long.startswith("[====[") and long.endswith("]====]"), "the bracket level is above anything in the text: " + long[:6])
lua = subprocess.run(["lua5.1", "-e", "local s = " + long + " io.write(#s)"], capture_output=True, text=True)
# (Lua drops the newline right after the opening bracket and keeps the last)
check(lua.returncode == 0 and lua.stdout == str(len("WTL1\tcommunity\t1\n" + evil) + 1), "Lua reads it back as the same text: " + lua.stdout + lua.stderr)

# fields that aren't text are checked against what they must look like
db = {}
md.load("WTL1\tenUS\t1\nQ\t2000000002\tQuest\t]==]\tU1,X2\tU3\t1:2,3\t\t\t]==] print(1)\tH\nN\t7\tA\t2\t9999\tvendor,BAD!\t1:1,1\tZ", db)
q, n = db[("Q", 2000000002)]["fields"], db[("N", 7)]["fields"]
check(q[3] == "" and q[4] == "" and q[5] == "U3" and q[6] == "1:2,3" and q[9] == "" and q[10] == "H", "bad quest fields are dropped: " + repr(q))
check(n[3] == "" and n[4] == "" and n[5] == "" and n[7] == "", "bad NPC fields are dropped: " + repr(n))

# a long comment that never ends is refused quickly
import time  # noqa: E402
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / "slow.lua"
    p.write_text("WaypointTrackerDB = {}\n" + "--[[ x\n" * 20000, encoding="utf-8")
    t0 = time.time()
    try:
        md.saved_to_text(str(p))
        check(False, "an unclosed comment is refused")
    except ValueError:
        check(time.time() - t0 < 2, "an unclosed comment is refused quickly (%.2fs)" % (time.time() - t0))
check(md.int_id("²") is None, "odd digits aren't numbers")

print(f"{passed} passed, {failures} failed")
sys.exit(1 if failures else 0)
