# Routing behaviour

The restored network includes flights, zeppelins, boats, the tram, portals,
walking connections, authored region/barrier constraints, and terrain evidence.
Fastest and Safer use the pre-prune planner and its existing access restrictions.

Thrall trips from southern Alterac and Hillsbrad reach Tarren Mill's flight
master, fly to Undercity, then take the zeppelin toward Orgrimmar. An unknown
source flight master adds a discovery step. Quest 557 retains its ground route.
The forward Hillsbrad-to-Alterac corpse corridor is available only to ghosts;
its provenance is observed player trace.

The standard gates use the restored routing expectations. The prune executor
and its verified-policy gate were removed because they reject the restored
network. Terrain candidate gaps remain distinct from active terrain links.
The original terrain evidence identity is retained during regeneration; private
calibration diagnostics have been removed from the public evidence documents.

Runtime identity tests use synthetic names and realms. No personal trace
excerpts or private timestamps are published. Native rendering, boarding,
tracker hit testing, and combat behaviour require in-game verification.

## November 4 launch travel review

Real routes remains beta. The three services in Blizzard's
[Found Photos recap](https://worldofwarcraft.blizzard.com/en-gb/news/24304071)
were already present: Stormwind–Auberdine, the ordered
Menethil–Southshore–Auberdine loop, and Steamwheedle–Powderfuse Port.
The first two retain their existing dock anchors and reported timings:
Stormwind 55 seconds aboard / 170 seconds including average wait; the loop
has a reported 455-second cycle, with distinct directed rides including
intermediate stops. These are estimates, not launch measurements. Boat boarding
has no hard faction gate; hostile shore access is separate from eligibility.

The client spline places the Steamwheedle stop at Tanaris **1446:68.5801,22.9913**
and Powderfuse at Riverglades **2548:80.6005,54.6072**. The former authored
positions were approximately 222 and 803 yards away respectively. Those old
points remain ordinary passes so that their surveyed terrain connections keep
their exact coordinates. The ship now connects separate `*_CLIENT_STOP`
anchors. A vehicle stop does not certify a boarding platform: no walking links
or terrain proofs were added at these anchors. Since 1.3.1 the service costs a
reported live 198 seconds (69 aboard, 60 waiting) instead of the inherited
90-second placeholder; the client path's 60-second stop delays match the
reported wait (`docs/data-audit.md`, "Upstream network review for 1.3.1"). The
link stays explicitly `unmeasured-traversal`; stop evidence separately marks
boarding/landing access unmeasured. We have not measured the ride or the wait ourselves.
Existing same-area walking inference can approach these anchors;
that inference is not a new surveyed walking leg.

The two existing Skyborne skyships have client TaxiPathNode evidence:
Valanaar–Skywatcher Plateau (Zephras 2521 to Mulgore 1412, path 11457) and
Zephras–Dalaran (2521 to Alterac 1416, path 11398). Their service existence is
supported by the frozen 1.60.1.70338 client evidence, while precise boarding
access and transit durations remain unmeasured. No additional skyship was added.

Blizzard's [October 16 development note](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes/2360696/6)
makes open-world Dalaran hostile to Horde, including characters with the sewer
key. Horde plans cannot use its dock, portal or city anchor as an intermediate
connection. Its existing city/dock/portal positions also receive the same
estimated 200-yard guard-exposure model as other faction towns. This is not a
surveyed city boundary, and does not mark all of Alterac hostile. Explicit
walking destinations and ghost movement remain possible; dungeon access is
unchanged. There is no ordinary Dalaran flight master in either taxi snapshot;
the quest translocation node 3260 remains excluded. The Stormwind portal keeps
its Alliance/Skyborne restriction.

The [1.60.1.70755 TaxiNodes export](https://wago.tools/db2/TaxiNodes/csv?build=1.60.1.70755&locale=enUS)
contains 101 rows: all 100 rows from the frozen snapshot are unchanged, and the
only addition is quest transport 3361, “Zephras Isle - Spires Wind Bridge”.
It is not a discoverable player flight master. No new flight points were added:
the two Hyjal points and the connected Riverglades points already ship;
Shen'dralas and Zephras have no new ordinary taxi nodes. Powderfuse Horde node
3274 still lacks a verified route in the available path fixture. Launch
TaxiPath, TaxiPathNode and map exports returned HTTP 403, so new connections
between existing nodes could not be checked. The stored launch CSV, its SHA-256
and the scope of this comparison are in `tools/fixtures/travel/launch-review.json`.

Regenerate with `python3 -B tools/build_travel.py tools/fixtures/travel`.
`tools/launch_travel.py` applies these transport/access changes after the frozen
terrain compiler, preserving its build identity and walking proofs. Regression
coverage is in `tests/check_travel_launch.py` and `tests/run_travel_launch.lua`.
