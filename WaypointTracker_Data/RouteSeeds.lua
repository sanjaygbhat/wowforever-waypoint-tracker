-- Hand-picked routes for the Routes window: skinning and farming spots,
-- quests and chains, dungeons, flight paths and tours. Resolved against the
-- rest of the database when Routes opens (see Routes.lua for the format).
local D = WaypointTrackerData
if not D then
    return
end
-- category, mode, name, note, stops
D.routeSeeds = [==[
skinning	loop	Skinning 5-8: Dun Morogh boars	Light Leather; Ruined Leather Scraps; skin req 1; Open snowfields; start with Crag Boars.	U1125,1126,1127@1426
skinning	loop	Skinning 5-8: Dun Morogh bears	Light Leather; Ruined Leather Scraps; skin req 1; Snowy woodland; pull bears singly.	U1128,1196@1426
skinning	loop	Skinning 5-8: Dun Morogh snow leopards	Light Leather; Ruined Leather Scraps; skin req 1; Rocky snow slopes; begin with juveniles.	U1199,1201@1426
skinning	loop	Skinning 6-8: Dun Morogh winter wolves	Light Leather; Ruined Leather Scraps; skin req 1; Snow-covered foothills; loot fully before skinning.	U1138,1131@1426
skinning	loop	Skinning 5-8: Elwynn boars	Light Leather; Ruined Leather Scraps; skin req 1; Farm fields and woodland edges.	U113,524@1429
skinning	loop	Skinning 5-8: Elwynn forest wolves	Light Leather; Ruined Leather Scraps; skin req 1; Woodland around Goldshire and the eastern road.	U525,1922@1429
skinning	loop	Skinning 8-10: Elwynn east bears & wolves	Light Leather; Ruined Leather Scraps; skin req 1; Eastern woods; watch wandering Prowlers.	U822,118@1429
skinning	loop	Skinning 10-12: Westfall coyotes	Light Leather; Light Hide chance; skin req 1-20; Open farmland; watch Coyote Packleaders.	U834,833@1436
skinning	loop	Skinning 12-15: Westfall young goretusks	Light/Medium Leather; hide chance; skin req 20-50; Farm fields; keep snouts and livers for quests.	U454,157@1436
skinning	loop	Skinning 16-17: Westfall great goretusks	Light/Medium Leather; hide chance; skin req 60-70; Southern farm fields; save boar meat.	U547@1436
skinning	loop	Skinning 10-15: Loch Modan mountain boars	Light/Medium Leather; hide chance; skin req 1-50; Wooded slopes around the loch.	U1190,1191@1432
skinning	loop	Skinning 11-14: Loch Modan black bears	Light Leather; Light Hide chance; skin req 10-40; Woodland around the loch; start with Elder Bears.	U1186,1188@1432
skinning	loop	Skinning 16-17: Loch Modan east big game	Light/Medium Leather; hide chance; skin req 60-70; Eastern woods; avoid elite ogres.	U1189,1192@1432
skinning	loop	Skinning 14-15: Loch Modan loch crocs	Light/Medium Leather; hide chance; skin req 40-50; Loch shoreline and islands; allow for swimming.	U1693@1432
skinning	loop	Skinning 16-17: Redridge goretusks	Light/Medium Leather; hide chance; skin req 60-70; Western approach from Elwynn.	U547@1433
skinning	loop	Skinning 17-18: Redridge black whelps	Light/Medium Leather; hide chance; skin req 70-80; Eastern hills; interrupt the whelps' fire casts.	U441@1433
skinning	loop	Skinning 19-21: Duskwood dire wolves	Light/Medium Leather; hide chance; skin req 90-105; Western woods around Raven Hill.	U213,565@1431
skinning	loop	Skinning 23-26: Duskwood black ravagers	Medium/Heavy Leather; hide chance; skin req 115-130; Eastern woods around Darkshire; watch patrols.	U923,628,1258@1431
skinning	loop	Skinning 21-24: Wetlands young crocs	Light/Medium Leather; hide chance; skin req 105-120; Western marsh waterways toward Menethil.	U1417,1400@1437
skinning	loop	Skinning 25-26: Wetlands giant crocs	Medium/Heavy Leather; hide chance; skin req 125-130; Marsh waterways; leave room for an escape.	U2089@1437
skinning	loop	Skinning 22-25: Wetlands mottled raptors	Medium Leather; Medium Hide chance; skin req 110-125; Whelgar's Excavation approaches.	U1020,1021@1437
skinning	loop	Skinning 23-26: Wetlands highland raptors	Medium/Heavy Leather; hide chance; skin req 115-130; Eastern highland raptor grounds.	U1015,1016,1017@1437
skinning	loop	Skinning 27-29: Wetlands razormaws	Medium/Heavy Leather; hide chance; skin req 135-145; Eastern hills; avoid the named raptor.	U1018,1019@1437
skinning	loop	Skinning 23-25: Wetlands red whelps	Medium Leather; Medium Hide chance; skin req 115-125; Eastern dragon grounds; interrupt fire casts.	U1042,1043@1437
skinning	loop	Skinning 25-27: Wetlands fiery whelps	Medium/Heavy Leather; hide chance; skin req 125-135; Eastern dragon grounds; pull casters singly.	U1069,1044@1437
skinning	loop	Leather farming: Medium - Wetlands fossils	Medium/Heavy Leather; hide chance; skin req 125-135; Whelgar's Excavation; avoid falling into packs.	U1022,1023@1437
skinning	loop	Skinning 21-26: Hillsbrad gray bears	Medium/Heavy Leather; hide chance; skin req 105-130; Wooded foothills; start with the younger bears.	U2351,2354,2356@1424
skinning	loop	Skinning 23-28: Hillsbrad mountain lions	Medium/Heavy Leather; hide chance; skin req 115-140; Open hills north of Southshore.	U2384,2385@1424
skinning	loop	Skinning 30-32: Hillsbrad cave yetis	Heavy Leather; Heavy Hide chance; skin req 150-160; Yeti cave north of Southshore; pull to the mouth.	U2248,2249@1424
skinning	loop	Skinning 30-31: Hillsbrad lake turtles	Heavy Leather; Heavy Hide chance; skin req 150-155; Lordamere Lake shore; turtles have high armor.	U2408@1424
skinning	loop	Skinning 21-26: Alterac gray bears	Medium/Heavy Leather; hide chance; skin req 105-130; Lower wooded slopes toward Hillsbrad.	U2351,2354,2356@1416
skinning	loop	Skinning 32-34: Alterac mountain yetis	Heavy Leather; Heavy Hide chance; skin req 160-170; Mountain yeti grounds; avoid nearby ogres.	U2250,2251@1416
skinning	loop	Skinning 32-34: Alterac mountain lions	Heavy Leather; Heavy Hide chance; skin req 160-170; Lower mountain slopes and open foothills.	U2406,2407@1416
skinning	loop	Skinning 30-31: Alterac lake turtles	Heavy Leather; Heavy Hide chance; skin req 150-155; Lordamere Lake shoreline.	U2408@1416
skinning	loop	Skinning 30-31: Arathi young raptors	Heavy Leather; Heavy Hide chance; skin req 150-155; Western open grassland; start with Striders.	U2559@1417
skinning	loop	Skinning 33-34: Arathi thrasher raptors	Heavy Leather; Heavy Hide chance; skin req 165-170; Central open grassland; avoid humanoid camps.	U2560@1417
skinning	loop	Skinning 36-37: Arathi fleshstalkers	Heavy/Thick Leather; hide chance; skin req 180-185; Southeastern grassland; higher-level raptors.	U2561@1417
skinning	loop	Skinning 30-33: STV northern cats	Heavy Leather; Heavy Hide chance; skin req 150-165; Northern jungle near the hunting grounds.	U681,682,683,736@1434
skinning	loop	Skinning 34-35: STV elder tigers	Heavy Leather; Heavy Hide chance; skin req 170-175; Northern tiger hunting grounds.	U1085@1434
skinning	loop	Skinning 30-31: STV river crocs	Heavy Leather; Heavy Hide chance; skin req 150-155; Northern river banks; avoid crossing into camps.	U1150@1434
skinning	loop	Skinning 33-36: STV lashtail raptors	Heavy/Thick Leather; hide chance; skin req 165-180; Northern and central raptor hunting grounds.	U685,686@1434
skinning	loop	Skinning 34-35: STV crystal basilisks	Heavy Leather; Heavy Hide chance; skin req 170-175; Rocky ridges around the central jungle.	U689@1434
skinning	loop	Skinning 37-38: STV shadowmaw panthers	Heavy/Thick Leather; hide chance; skin req 185-190; Central jungle; watch for stealthed panthers.	U684@1434
skinning	loop	Skinning 35-36: STV coastal crocs	Heavy/Thick Leather; hide chance; skin req 175-180; Saltwater shoreline; avoid elite elder crocs.	U1151@1434
skinning	loop	Skinning 35-36: STV snapjaw crocs	Heavy/Thick Leather; hide chance; skin req 175-180; Central waterways; loot and skin on dry ground.	U1152@1434
skinning	loop	Skinning 32-33: STV mistvale gorillas	Heavy Leather; Heavy Hide chance; skin req 160-165; Mistvale Valley; keep pulls small.	U1108@1434
skinning	loop	Skinning 40-41: STV elder gorillas	Heavy/Thick Leather; hide chance; skin req 200-205; Southern Mistvale jungle; watch clustered pulls.	U1557@1434
skinning	loop	Skinning 40-41: STV arena raptors	Heavy/Thick Leather; hide chance; skin req 200-205; Behind Gurubashi Arena on the Savage Coast.	U687@1434
skinning	loop	Skinning 39-44: STV coast basilisks	Heavy/Thick Leather; hide chance; skin req 195-220; Coastal rocky ground; watch basilisk stun casts.	U690,1550,1551@1434
skinning	loop	Leather farming: Thick - Jaguero Isle	Thick/Rugged Leather; hide chance; skin req 250; Jaguero Isle; watch stealthed cats.	U2521,2522@1434
skinning	loop	Skinning 35-38: Badlands young coyotes	Heavy/Thick Leather; hide chance; skin req 175-190; Open rocky flats; start with Crag Coyotes.	U2727,2728@1418
skinning	loop	Skinning 36-39: Badlands ridge cats	Heavy/Thick Leather; hide chance; skin req 180-195; Rocky ridges; watch stealthed Ridge Stalkers.	U2731,2732@1418
skinning	loop	Skinning 39-43: Badlands older coyotes	Heavy/Thick Leather; hide chance; skin req 195-215; Craggy flats; Rabid Coyotes are the harder pulls.	U2729,2730@1418
skinning	loop	Skinning 40-41: Badlands patriarch cats	Heavy/Thick Leather; hide chance; skin req 200-205; Southern ridges; watch stealthed cats.	U2734@1418
skinning	loop	Skinning 41-43: Badlands scalding whelps	Heavy/Thick Leather; hide chance; skin req 205-215; Lethlor Ravine; interrupt fire casts.	U2725@1418
skinning	loop	Leather farming: Scales - Badlands guardians	Heavy/Thick Leather; Worn Dragonscales; skin req 215-225; Lethlor Ravine; elite dragons, bring help.	U2726@1418
skinning	loop	Skinning 35-39: Swamp of Sorrows crocs	Heavy/Thick Leather; hide chance; skin req 175-195; Marsh waterways; start with Young Sawtooths.	U1084,1082@1435
skinning	loop	Skinning 36-40: Swamp of Sorrows cats	Heavy/Thick Leather; hide chance; skin req 180-200; Wooded marsh; watch stealthed Shadow Panthers.	U767,768@1435
skinning	loop	Skinning 34-36: Swamp of Sorrows whelps	Medium/Heavy Leather; hide chance; skin req 170-180; Itharius's Cave area in the western swamp.	U740,741@1435
skinning	loop	Skinning 41-42: Swamp of Sorrows snappers	Heavy/Thick Leather; hide chance; skin req 205-210; Eastern waterways; these are crocolisks.	U1087@1435
skinning	loop	Skinning 41-44: Hinterlands young wolves	Heavy/Thick Leather; hide chance; skin req 205-220; Western wooded hills; begin with Mangy wolves.	U2923,2924@1425
skinning	loop	Skinning 45-48: Hinterlands older wolves	Thick/Rugged Leather; hide chance; skin req 225-240; Central and eastern woods; watch stealthed wolves.	U2925,2926@1425
skinning	loop	Leather farming: Turtle Scales - Hinterlands	Thick/Rugged Leather; Turtle Scales; skin req 245-250; Eastern beach near Raventusk; turtles have high armor.	U2505@1425
skinning	loop	Leather farming: Thick - Searing Gorge dinos	Thick/Rugged Leather; Thick Hide; skin req 235-245; Slag Pit cave; scales are normal loot, not skins.	U9318@1427
skinning	loop	Skinning 45-46: Blasted Lands young hyenas	Thick Leather; Thick Hide chance; skin req 225-230; Northern dry flats; watch roaming packs.	U5984@1419
skinning	loop	Skinning 47-48: Blasted Lands redstone basilisks	Thick/Rugged Leather; hide chance; skin req 235-240; Rocky flats; watch basilisk stun casts.	U5990@1419
skinning	loop	Skinning 48-50: Blasted Lands boars & hyenas	Thick/Rugged Leather; hide chance; skin req 240-250; Dry flats around the northern quest hunting grounds.	U5992,5985@1419
skinning	loop	Skinning 50-51: Blasted Lands scorpok stingers	Rugged/Thick Leather; hide chance; skin req 250-255; Open wasteland; save pincers for quests.	U5988@1419
skinning	loop	Skinning 51-52: Blasted Lands crystalhides	Thick/Rugged Leather; hide chance; skin req 255-260; Rocky wasteland; watch basilisk stun casts.	U5991@1419
skinning	loop	Leather farming: Rugged - Blasted Lands boars	Rugged/Thick Leather; hide chance; skin req 260-265; Southern wasteland; avoid the demon camps.	U5993@1419
skinning	loop	Skinning 51-54: Burning Steppes ember worgs	Rugged/Thick Leather; hide chance; skin req 255-270; Western ash fields; begin with Ember Worgs.	U9690,9694@1428
skinning	loop	Skinning 55-56: Burning Steppes giant worgs	Rugged/Thick Leather; hide chance; skin req 275-280; Ash fields; pull large wolves singly.	U9697@1428
skinning	loop	Skinning 52-55: Burning Steppes scorpids	Rugged/Thick Leather; hide chance; skin req 260-275; Ash fields; watch poison and nearby patrols.	U9691,9695@1428
skinning	loop	Skinning 56-57: Burning Steppes firetails	Rugged/Thick Leather; hide chance; skin req 280-285; Higher-level scorpid grounds; clear poison.	U9698@1428
skinning	loop	Skinning 51-54: Burning Steppes black broodlings	Black Dragonscales; Thick/Rugged Leather; skin req 255-270; Eastern dragon grounds; interrupt fire casts.	U7047,7048@1428
skinning	loop	Skinning 55-56: Burning Steppes flame broodlings	Black Dragonscales; Thick/Rugged Leather; skin req 275-280; Eastern dragon grounds; fewer spawns, keep moving.	U7049@1428
skinning	loop	Leather farming: Black Scales - Terror Wing	Black Dragonscales; Thick/Rugged Leather; skin req 260-270; Terror Wing Path; elite packs, bring help.	U7040,7041@1428
skinning	loop	Leather farming: Black Scales - Flamescales	Black Dragonscales; Thick/Rugged Leather; skin req 280-290; Terror Wing Path; higher-level elites, bring help.	U7042,7043@1428
skinning	loop	Skinning 51-54: W. Plaguelands bears & wolves	Rugged/Thick Leather; hide chance; skin req 255-270; Forests between the farms; avoid undead packs.	U1815,1817@1422
skinning	loop	Leather farming: Rugged - WPL grizzlies	Rugged/Thick Leather; hide chance; skin req 275-280; Northern woodland toward Hearthglen.	U1816@1422
skinning	loop	Skinning 53-56: E. Plaguelands plaguehounds	Rugged/Thick Leather; hide chance; skin req 265-280; Southern wilderness; avoid undead camps.	U8596,8597@1423
skinning	loop	Skinning 53-56: E. Plaguelands plaguebats	Rugged/Thick Leather; hide chance; skin req 265-280; Southern and central wilderness.	U8600,8601@1423
skinning	loop	Leather farming: Rugged - EPL frenzied hounds	Rugged Leather; Rugged Hide chance; skin req 285-290; Northern wilderness; pull hounds singly.	U8598@1423
skinning	loop	Leather farming: Rugged - EPL monstrous bats	Rugged Leather; Rugged Hide chance; skin req 280-290; Northern and eastern wilderness.	U8602@1423
skinning	loop	Skinning 5-8: Tirisfal darkhounds	Light Leather; Ruined Leather Scraps; skin req 1; Woodland outside Deathknell; start with Decrepit hounds.	U1547,1548@1420
skinning	loop	Skinning 6-9: Tirisfal duskbats	Light Leather; Ruined Leather Scraps; skin req 1; Fields around Brill; avoid the starter bats.	U1553,1554@1420
skinning	loop	Skinning 9-10: Tirisfal ravenous hounds	Light Leather; Ruined Leather Scraps; skin req 1; Eastern woods; avoid the Plaguelands border.	U1549@1420
skinning	loop	Skinning 10-12: Silverpine young worgs	Light Leather; Light Hide chance; skin req 1-20; Northern forest and road edges.	U1765,1766@1421
skinning	loop	Skinning 11-13: Silverpine grizzled bears	Light Leather; Light Hide chance; skin req 10-30; Northern woods; avoid wandering elite Sons of Arugal.	U1778,1797@1421
skinning	loop	Skinning 16-17: Silverpine bloodsnout worgs	Light/Medium Leather; hide chance; skin req 60-70; Southern woods; watch elite patrols.	U1923@1421
skinning	loop	Skinning 30-31: Silverpine lake turtles	Heavy Leather; Heavy Hide chance; skin req 150-155; Lordamere Lake shore; far above the forest's normal level.	U2408@1421
skinning	loop	Skinning 5-7: Durotar boars & scorpids	Razor Hill plains; Scraps/Light Leather; skin skill 1 required.	U3099,3125@1411
skinning	loop	Skinning 6-8: Durotar tigers & raptors	Echo Isles; Light Leather; occasional Light Hide; skin skill 1 required.	U3121,3122@1411
skinning	loop	Skinning 8-10: Durotar scythemaw raptors	Echo Isles; Light Leather; occasional Light Hide; skin skill 1 required.	U3123@1411
skinning	loop	Skinning 7-10: Durotar northern beasts	Northern dry plains; Light Leather; occasional Light Hide; skin skill 1 required.	U3100,3126,3127@1411
skinning	loop	Skinning 9-11: Durotar river crocolisks	Southfury River bank; Light Leather; occasional Light Hide; skin skill 1-10 required.	U3110@1411
skinning	loop	Skinning 9-10: Durotar thunder lizards	Northern rocky uplands; Light Leather; occasional Light Hide; skin skill 1 required.	U3130@1411
skinning	loop	Skinning 5-6: Mulgore prairie wolves	Southern grasslands; Scraps/Light Leather; skin skill 1 required.	U2958@1412
skinning	loop	Skinning 6-8: Mulgore cats & striders	Bloodhoof grasslands; Light Leather; occasional Light Hide; skin skill 1 required.	U2956,2959,3035@1412
skinning	loop	Skinning 8-10: Mulgore northern predators	Northern grasslands; Light Leather; occasional Light Hide; skin skill 1 required.	U2957,2960,3566@1412
skinning	loop	Skinning 7-12: Mulgore kodo herds	Open grasslands; Light Leather; occasional Light Hide; skin skill 1-20 required.	U2972,2973,2974@1412
skinning	loop	Skinning 11-13: Barrens northern striders	Northern open plains; Light Leather; occasional Light Hide; skin skill 10-30 required.	U3244,3246@1413
skinning	loop	Skinning 13-15: Barrens zhevras & kodos	Northern open plains; Light/Medium Leather; occasional hides; skin skill 30-50 required.	U3242,3234@1413
skinning	loop	Skinning 11-15: Barrens savannah cats	Northern savannah; Light/Medium Leather; occasional hides; skin skill 10-50 required.	U3415,3243,3425@1413
skinning	loop	Skinning 11-15: Barrens sunscale raptors	Northern raptor grounds; Light/Medium Leather; occasional hides; skin skill 10-50 required.	U3254,3255@1413
skinning	loop	Skinning 16-18: Barrens central grazers	Central open plains; Light/Medium Leather; occasional hides; skin skill 60-80 required.	U3245,3426@1413
skinning	loop	Skinning 15-19: Barrens hecklefang hyenas	Central savannah; Light/Medium Leather; occasional hides; skin skill 50-90 required.	U4127,4129@1413
skinning	loop	Skinning 16-18: Barrens scytheclaw raptors	Central raptor grounds; Light/Medium Leather; occasional hides; skin skill 60-80 required.	U3256@1413
skinning	loop	Skinning 15-16: Barrens oasis turtles	Lushwater and nearby oases; Light/Medium Leather; occasional hides; skin skill 50-60 required.	U3461@1413
skinning	loop	Skinning 18-21: Barrens southern beasts	Taurajo-side plains; Medium Leather; occasional Medium Hide; skin skill 80-105 required.	U3466,3240,3239@1413
skinning	loop	Skinning 22-23: Barrens southern hyenas	Southern savannah; Medium Leather; occasional Medium Hide; skin skill 110-115 required.	U4128@1413
skinning	loop	Skinning 5-6: Teldrassil nightsabers	Dolanaar woodland; Scraps/Light Leather; skin skill 1 required.	U2042@1438
skinning	loop	Skinning 7-8: Teldrassil stalker cats	Outer woodland trails; Light Leather; occasional Light Hide; skin skill 1 required.	U2043@1438
skinning	loop	Skinning 8-11: Teldrassil elder cats	Northern woodland; Light Leather; occasional Light Hide; skin skill 1-10 required.	U2033,2034@1438
skinning	loop	Skinning 10-12: Darkshore bears & runts	Auberdine woodland; Light Leather; occasional Light Hide; skin skill 1-20 required.	U2070,2163@1439
skinning	loop	Skinning 11-13: Darkshore fledgling striders	Auberdine woodland; Light Leather; occasional Light Hide; skin skill 10-30 required.	U2321@1439
skinning	loop	Skinning 13-15: Darkshore cats & rabid bears	Central woodland; Light/Medium Leather; occasional hides; skin skill 30-50 required.	U2069,2164@1439
skinning	loop	Skinning 14-19: Darkshore foreststriders	Central and southern woods; Light/Medium Leather; occasional hides; skin skill 40-90 required.	U2322,2323@1439
skinning	loop	Skinning 16-20: Darkshore southern predators	Southern woodland; Light/Medium Leather; occasional hides; skin skill 60-100 required.	U2165,2237,2071@1439
skinning	loop	Skinning 19-24: Ashenvale western wolves	Western woodland trails; Medium Leather; occasional Medium Hide; skin skill 90-120 required.	U3823,3824@1440
skinning	loop	Skinning 21-23: Ashenvale bears & stags	Central woodland clearings; Medium Leather; occasional Medium Hide; skin skill 105-115 required.	U3809,3817@1440
skinning	loop	Skinning 25-27: Ashenvale elder grazers	Central/eastern woodland; Medium/Heavy Leather; occasional hides; skin skill 125-135 required.	U3810,3818@1440
skinning	loop	Skinning 27-30: Ashenvale eastern predators	Eastern woodland; Medium/Heavy Leather; occasional hides; skin skill 135-150 required.	U3825,3811@1440
skinning	loop	Skinning 22-25: Stonetalon coursers	Mountain woodland; Medium Leather; occasional Medium Hide; skin skill 110-125 required.	U4018,4019@1442
skinning	loop	Skinning 23-24: Stonetalon twilight cats	Woodland trails; Medium Leather; occasional Medium Hide; skin skill 115-120 required.	U4067@1442
skinning	loop	Skinning 23-28: Stonetalon charred basilisks	Charred Vale; Medium/Heavy Leather; occasional hides; skin skill 115-140 required.	U4044,4042,4041@1442
skinning	loop	Skinning 25-29: Thousand Needles cats & hyenas	Main canyon floor; Medium/Heavy Leather; occasional hides; skin skill 125-145 required.	U4126,4248,4249@1441
skinning	loop	Skinning 25-29: Thousand Needles cloud serpents	Main canyon; Medium/Heavy Leather; occasional hides; skin skill 125-145 required.	U4117,4118,4119@1441
skinning	loop	Skinning 30-35: Thousand Needles salt basilisks	Shimmering Flats; Heavy Leather; occasional Heavy Hide; skin skill 150-175 required.	U4147,4151,4150@1441
skinning	loop	Skinning 31-34: Thousand Needles Flats scorpids	Shimmering Flats; Heavy Leather; occasional Heavy Hide; skin skill 155-170 required.	U4140,4139@1441
skinning	loop	Skinning 30-35: Thousand Needles Flats turtles	Shimmering Flats; Heavy Leather/Hide; chance of Turtle Scale; skin skill 150-175 required.	U4142,4144,4143@1441
skinning	loop	Skinning 31-36: Desolace gritjaw basilisks	Rocky inland plains; Heavy Leather; occasional Heavy Hide; skin skill 155-180 required.	U4728,4729@1443
skinning	loop	Skinning 30-35: Desolace bonepaw hyenas	Kodo Graveyard surroundings; Heavy Leather; occasional Heavy Hide; skin skill 150-175 required.	U4689,4688@1443
skinning	loop	Skinning 34-37: Desolace graveyard kodos	Kodo Graveyard; Heavy/Thick Leather; occasional hides; skin skill 170-185 required.	U4700,4701,4702@1443
skinning	loop	Skinning 33-38: Desolace thunder lizards	Open inland plains; Heavy/Thick Leather; occasional hides; skin skill 165-190 required.	U4726,4727@1443
skinning	loop	Skinning 30-35: Desolace young scorpids	Dry inland plains; Heavy Leather; occasional Heavy Hide; skin skill 150-175 required.	U4696,4697@1443
skinning	loop	Skinning 38-39: Desolace venomlash scorpids	Southern dry plains; Heavy/Thick Leather; occasional hides; skin skill 190-195 required.	U4699@1443
skinning	loop	Skinning 35-38: Dustwallow young crocolisks	Northern/central waterways; Heavy/Thick Leather; occasional hides; skin skill 175-190 required.	U4341,4342,4343@1445
skinning	loop	Skinning 38-41: Dustwallow large crocolisks	Southern marsh waterways; Heavy/Thick Leather/Hide; daggermaws elite; skin skill 190-205 required.	U4344,4345@1445
skinning	loop	Skinning 35-38: Dustwallow young raptors	Bloodfen marsh; Heavy/Thick Leather; occasional hides; skin skill 175-190 required.	U4351,4352,4355@1445
skinning	loop	Skinning 39-41: Dustwallow large raptors	Southern Bloodfen marsh; Heavy/Thick Leather; occasional hides; skin skill 195-205 required.	U4356,4357@1445
skinning	loop	Skinning 36-40: Dustwallow mudrock turtles	Eastern coast; Heavy/Thick Leather/Hide; Turtle Scale chance; skin skill 180-200 required.	U4396,4397,4398@1445
skinning	loop	Skinning 41-43: Dustwallow coastal snapjaws	Southern eastern coast; Thick Leather/Hide; Turtle Scale chance; skin skill 205-215 required.	U4400,4399@1445
skinning	loop	Skinning 40-42: Feralas young bears & wolves	Eastern forest; Thick Leather; occasional Thick Hide; skin skill 200-210 required.	U5268,5286@1444
skinning	loop	Skinning 43-45: Feralas central bears & wolves	Central forest; Thick Leather; occasional Thick Hide; skin skill 215-225 required.	U5272,5287@1444
skinning	loop	Skinning 42-43: Feralas groddoc apes	Groddoc forest; Thick Leather; occasional Thick Hide; skin skill 210-215 required.	U5260@1444
skinning	loop	Skinning 47-49: Feralas large bears & wolves	Western forest; Thick/Rugged Leather; occasional hides; skin skill 235-245 required.	U5274,5288@1444
skinning	loop	Skinning 49-50: Feralas groddoc thunderers	Western Groddoc forest; Thick/Rugged Leather; occasional hides; skin skill 245-250 required.	U5262@1444
skinning	loop	Skinning 41-45: Tanaris northern hyenas	Gadgetzan-side desert; Thick Leather; occasional Thick Hide; skin skill 205-225 required.	U5425,5426@1446
skinning	loop	Skinning 40-44: Tanaris young scorpids	Northern/central desert; Thick Leather/Hide; Scorpid Scale chance; skin skill 200-220 required.	U5422,5423@1446
skinning	loop	Skinning 42-46: Tanaris young basilisks	Northern/central desert; Thick Leather; occasional Thick Hide; skin skill 210-230 required.	U5419,5420@1446
skinning	loop	Skinning 46-48: Tanaris southern predators	Southern desert; Thick/Rugged Leather/Hide; Scorpid Scale chance; skin skill 230-240 required.	U5424,5427@1446
skinning	loop	Skinning 48-49: Tanaris petrifier basilisks	Southern rocky desert; Thick/Rugged Leather; occasional hides; skin skill 240-245 required.	U5421@1446
skinning	loop	Skinning 42-43: Tanaris steeljaw turtles	Eastern coast; Thick Leather/Hide; Turtle Scale chance; skin skill 210-215 required.	U14123@1446
skinning	loop	Skinning 48-50: Tanaris surf gliders	Southern eastern coast; Thick/Rugged Leather/Hide; Turtle Scale chance; skin skill 240-250 required.	U5431@1446
skinning	loop	Skinning 45-47: Azshara mosshoof runners	Western inland woodland; Thick Leather; occasional Thick Hide; skin skill 225-235 required.	U8759@1447
skinning	loop	Skinning 49-53: Azshara mosshoof stags	Central/eastern inland woods; Thick/Rugged Leather; occasional hides; skin skill 245-265 required.	U8760,8761@1447
skinning	loop	Skinning 50-54: Azshara coralshell turtles	Bay of Storms coast; Thick/Rugged Leather/Hide; Turtle Scale chance; skin skill 250-270 required.	U6369,6352@1447
skinning	loop	Skinning 47-48: Felwood southern predators	Southern woods; Thick/Rugged Leather; occasional hides; skin skill 235-240 required.	U8956,8959@1448
skinning	loop	Skinning 49-50: Felwood central predators	Central woods; Thick/Rugged Leather; occasional hides; skin skill 245-250 required.	U8958,8960@1448
skinning	loop	Skinning 51-52: Felwood grizzlies & ravagers	Northern woods; Rugged/Thick Leather/Hide; bears may yield Warbear; skin skill 255-260 required.	U8957,8961@1448
skinning	loop	Skinning 48-51: Un'Goro ravasaurs	Southeastern ravasaur grounds; Thick/Rugged Leather; occasional hides; skin skill 240-255 required.	U6505,6506,6507,6508@1449
skinning	loop	Skinning 50-53: Un'Goro gorillas	Fungal Rock and northern woods; Rugged/Thick Leather; occasional hides; skin skill 250-265 required.	U6514,6513,6516@1449
skinning	loop	Skinning 49-52: Un'Goro young diemetradons	Central crater grasslands; Thick/Rugged Leather; occasional hides; skin skill 245-260 required.	U9162,9163@1449
skinning	loop	Skinning 54-55: Un'Goro elder diemetradons	Central/western grasslands; Rugged/Thick Leather; occasional hides; skin skill 270-275 required.	U9164@1449
skinning	loop	Skinning 48-52: Un'Goro young pterrordax	Crater rim nests; Thick/Rugged Leather; occasional hides; skin skill 240-260 required.	U9165,9166@1449
skinning	loop	Skinning 52-54: Un'Goro frenzied pterrordax	Western crater rim nests; Rugged/Thick Leather; occasional hides; skin skill 260-270 required.	U9167@1449
skinning	loop	Skinning 52-54: Un'Goro stegodon elites	Southern Slithering Scar edge; Rugged/Thick Leather/Hide; elite packs; skin skill 260-270 required.	U6501,6502,6503@1449
skinning	loop	Skinning 54-56: Un'Goro devilsaur patrols	Roaming crater patrols; Devilsaur Leather; elites; 280 covers level 56; skin skill 270-280 required.	U6498,6499,6500@1449
skinning	loop	Skinning 54-56: Silithus hold-side scorpids	Cenarion Hold surroundings; Rugged/Thick Leather/Hide; Heavy Scorpid Scale; skin skill 270-280 required.	U11735,11736@1451
skinning	loop	Skinning 57-58: Silithus outer scorpids	Outer desert; Rugged/Thick Leather/Hide; Heavy Scorpid Scale; skin skill 285-290 required.	U11737@1451
skinning	loop	Skinning 55-58: Silithus sandworms	Open desert; Rugged/Thick Leather/Hide; loot Sandworm Meat first; skin skill 275-290 required.	U11740,11741@1451
skinning	loop	Skinning 55-57: Winterspring young frost cats	Frostsaber Rock; Rugged Leather/Hide; Frostsaber Leather chance; skin skill 275-285 required.	U7430,7431@1452
skinning	loop	Skinning 58-60: Winterspring adult frost cats	Frostsaber Rock; Rugged Leather/Hide; Frostsaber Leather chance; skin skill 290-300 required.	U7432,7433,7434@1452
skinning	loop	Skinning 53-56: Winterspring young shardtooths	Central snowy hills; Rugged Leather/Hide; Warbear Leather chance; skin skill 265-280 required.	U7444,7443@1452
skinning	loop	Skinning 57-60: Winterspring large shardtooths	Southern snowy hills; Rugged Leather/Hide; Warbear Leather chance; skin skill 285-300 required.	U7445,7446@1452
skinning	loop	Skinning 53-57: Winterspring chillwind chimaeras	Western snowy hills; Rugged Leather/Hide; Chimera Leather chance; skin skill 265-285 required.	U7447,7448@1452
skinning	loop	Skinning 57-59: Winterspring chillwind ravagers	Western/northern hills; Rugged Leather/Hide; Chimera Leather chance; skin skill 285-295 required.	U7449@1452
farming	loop	Cloth 32-35: Alterac Syndicate (silk)	Silk Cloth from Syndicate camps; rogues can also pickpocket humanoids before killing them.	U2240,2241,2319@1416
farming	loop	Cloth 34-36: Alterac Crushridge (silk)	Silk Cloth from non-elite Crushridge ogres; stay clear of the elite upper ruins at this level.	U2252,2253@1416
farming	loop	Cloth 35-40: Alterac Syndicate (silk)	Silk Cloth from higher-level Syndicate camps; casters and Assassins require controlled pulls.	U2242,2243,2245,2246,2247,2318@1416
farming	loop	Cloth 30-33: Arathi Northfold (silk)	Silk Cloth from Northfold Manor Syndicate; a non-elite alternative to Stromgarde.	U2586,2589,2587@1417
farming	loop	Cloth 30-36: Arathi Witherbark (silk)	Silk Cloth from southeast Witherbark camps; interrupt Witch Doctors and Shadowcasters.	U2552,2553,2554,2555,2556,2557@1417
farming	loop	Meat 30-37: Arathi raptors	Raptor Eggs and Raptor Flesh for cooking; skin Highland raptors for leather between packs.	U2559,2560,2561@1417
farming	loop	Cloth 35-38: Arathi Drywhisker (silk)	Silk Cloth from Drywhisker kobolds; clear cave branches for respawns and vendor their junk.	U2572,2574,2573@1417
farming	loop	Cloth 35-38: Arathi Stromgarde (silk)	Silk Cloth from elite Syndicate inside Stromgarde; bring a group or farm well above their level.	U2590,2588,2591@1417
farming	loop	Mats 38-39: Arathi air exiles	Elemental Air and Thundering Charms; warriors need charms for the Cyclonian weapon quest.	U2762@1417
farming	loop	Mats 38-39: Arathi earth exiles	Elemental Earth, Solid Stone and Deeprock Salt for crafting; loop the Circle of Inner Binding.	U2592@1417
farming	loop	Mats 38-39: Arathi fire exiles	Elemental Fire for protection potions; Burning Charms also sell to warriors doing Cyclonian.	U2760@1417
farming	loop	Mats 38-39: Arathi water exiles	Elemental Water for crafting; save Cresting Charms for warrior quest buyers.	U2761@1417
treasure	loop	Trinket 38-41: Arathi Faldir's Cove	Check Prince Nazjak for rare Tidal Charm; farm nearby Daggerspine for clams while waiting. Bring water breathing.	U2595,2596,2779@1417
farming	loop	Cloth 35-39: Badlands Shadowforge (silk)	Silk Cloth from surface Shadowforge dwarves; avoid adding Uldaman entrance elites at this level.	U2739,2740,2742,2743@1418
farming	loop	Meat 35-41: Badlands buzzards	Buzzard Wings for Barbecued Buzzard Wing and Rigglefuzz's quest; sell spare wings to cooks.	U2829,2830,2831@1418
farming	loop	Mats 37-40: Badlands rock elementals	Elemental Earth, Solid Stone and Deeprock Salt for crafting; clear Lesser and regular Rock Elementals.	U2735,92@1418
farming	loop	Cloth 40-45: Badlands Dustbelcher	Mageweave and silk from higher-level Dustbelcher ogres; kill shamans and mages first.	U2716,2717,2718,2720,2719@1418
farming	loop	Mats 42-44: Badlands greater elementals	Elemental Earth, Solid Stone and Deeprock Salt; vendor stone junk between clears.	U2736,2791@1418
farming	loop	Cloth 45-47: Blasted Dreadmaul (mageweave)	Mageweave Cloth from lower-level Dreadmaul ogres; interrupt Ogre Mages and vendor their weapons.	U5974,5975,5976@1419
farming	loop	Turn-ins 46-52: Blasted gizzards & brains	Vulture Gizzards and Basilisk Brains for Bloodmage buff quests; keep these white-quality turn-in drops.	U5982,5990,5991@1419
farming	loop	Turn-ins 48-53: Blasted lungs & pincers	Blasted Boar Lungs and Scorpok Pincers for Bloodmage buff quests; skin the boars and scorpids if trained.	U5992,5988,5993@1419
farming	loop	Cloth 51-55: Blasted Shadowsworn (runecloth)	Runecloth from Shadowsworn camps; interrupt Adepts, Warlocks and Dreadweavers.	U6004,6005,6006,6007,6008,6009@1419
farming	loop	Cloth 53-55: Blasted Dreadmaul (runecloth)	Runecloth from Dreadmaul Post's Maulers and Warlocks; split pulls and interrupt casters.	U5977,5978@1419
farming	loop	Cloth 50-53: Burning Firegut (runecloth)	Runecloth from Firegut ogres at Dreadmaul Rock; clear casters first and sell cloth to tailors.	U7033,7034,7035@1428
farming	loop	Mats 51-57: Burning obsidian elementals	Elemental Earth and Solid Stone for crafting; clear Obsidian Elementals and vendor their stone junk.	U7031,7032@1428
farming	loop	Cloth 53-55: Burning Thaurissan (runecloth)	Runecloth from Thaurissan dwarves in the ruins; interrupt Firewalkers and watch nearby War Reavers.	U7036,7037,7038@1428
farming	loop	Meat 54-56: Burning Ember Worgs	Tender Wolf Meat for cooking; skin the higher-level Ember Worgs and vendor teeth for extra income.	U7055,9697@1428
farming	loop	Cloth 55-58: Burning Blackrock (runecloth)	Runecloth from Blackrock camps; interrupt Sorcerers and Warlocks before clearing melee orcs.	U7025,7026,7027,7028,7029@1428
farming	loop	Cloth 55-58: Deadwind ogres (runecloth)	Runecloth and coin from southern ogres; Warlocks can rarely drop the Superior Strength bracer enchant formula.	U7369,7371,7372,7379@1430
farming	loop	Gold 58-60: Deadwind cellar ghosts	Coin, occasional Runecloth and BoE gear from Karazhan cellar ghosts; they hit hard, so split dense packs.	U7370,12377,12378@1430
farming	loop	Meat 3-10: Dun Morogh boars	Chunk of Boar Meat for beginner cooking; skin the boars for extra leather income.	U708,1125,1126,1127,1689@1426
farming	loop	Meat 6-8: Dun Morogh wolves	Stringy Wolf Meat for cooking; follow the wolf packs and vendor their teeth.	U1131,1138@1426
farming	loop	Cloth 7-10: Dun Morogh Frostmane (linen)	Linen Cloth for tailoring and bandages; casters make the troll cave pulls harder.	U1120,1121,1122,1123,1124,1397@1426
farming	loop	Cloth 8-10: Dun Morogh leper gnomes (linen)	Linen Cloth and coin; clear the leper gnomes around the Gnomeregan surface entrance.	U1211@1426
farming	loop	Cloth 21-24: Duskwood skeletons (wool)	Wool Cloth from Raven Hill skeletons; kill Skeletal Mages first to reduce spell damage.	U48,203,202@1431
farming	loop	Mats 21-25: Duskwood spiders	Spider's Silk and venom sacs for crafting; Green Recluses and Black Widows patrol the woods.	U569,930@1431
farming	loop	Cloth 24-27: Duskwood Defias (wool)	Wool Cloth from Defias at the southern farm; interrupt Enchanters and avoid linked pulls.	U215,909,910@1431
farming	loop	Cloth 25-30: Duskwood ogres (silk/wool)	Silk and Wool Cloth from Splinter Fist ogres; farm the southern mound and interrupt fire casters.	U889,891,892,1251,212@1431
farming	loop	Cloth 26-31: Duskwood Nightbane (silk/wool)	Silk and Wool Cloth from Nightbane worgen; clear their camps for tailoring and First Aid materials.	U898,533,205,206,920@1431
farming	loop	Rep 53-55: EPL Corin's Crossing	Runecloth and Argent Dawn scourgestones; equip Argent Dawn Commission and work the lower-level Scourge.	U8523,8524,8530@1423
farming	loop	Rep 53-56: EPL crypt fiend parts	Crypt Fiend Parts for Leopold at Light's Hope (level 55+, Friendly Argent Dawn); equip Commission for scourgestones.	U8555,8556@1423
farming	loop	Cloth 53-57: EPL Tyr's Hand (runecloth)	Runecloth and coin from elite Scarlet packs; bring a group at these levels or use an established solo strategy.	U9447,9448,9449,9450,9451,9452@1423
farming	loop	Pet 54-56: EPL scar oozes	Oozing Bags may contain a rare Disgusting Oozeling; farm Living Decay and Rotting Sludge and open every bag.	U8606,8607@1423
farming	loop	Mats 54-57: EPL carrion worms	Larval Acid for crafting; clear Carrion Grubs and Devourers and vendor their ichor and goo.	U8603,8605@1423
farming	loop	Mats 54-57: EPL water elementals	Essence of Water and Elemental Water for crafting; clear Blighted Surges, Plague Ravagers and Blighted Horrors.	U8519,8520,8521@1423
farming	loop	Gold 54-58: EPL plaguebats	Vendor bat ears and wings for steady coin; skin Noxious and Monstrous Plaguebats for extra leather.	U8601,8602@1423
farming	loop	Mats 55-57: EPL Corin ghosts	Essence of Undeath for crafting; equip Argent Dawn Commission for scourgestones while farming Hate Shriekers.	U8541@1423
farming	loop	Cloth 57-59: EPL Mossflayer (runecloth)	Runecloth from Zul'Mashar trolls; interrupt Shadowhunters and split pulls around the graves.	U8560,8561,8562@1423
farming	loop	Cloth 5-7: Elwynn kobold mines (linen)	Linen Cloth and candles from kobolds; mine tunnels have tight pulls and quick respawns.	U40,475@1429
farming	loop	Cloth 8-10: Elwynn Defias (linen)	Linen Cloth for First Aid and tailoring; farm eastern Defias camps and interrupt Rogue Wizards.	U116,474@1429
farming	loop	Cloth 8-10: Elwynn Riverpaw (linen)	Linen Cloth from southwest gnolls; keep clear of elite Hogger at low levels.	U97,478@1429
farming	loop	Cloth 20-22: Hillsbrad Syndicate (wool)	Wool Cloth from Durnholde Syndicate; kill Shadow Mages first and collect vendor loot.	U2261,2260,2244@1424
farming	loop	Mats 24-27: Hillsbrad spiders	Spider's Silk and venom sacs for crafting; use the higher-level Moss Creeper spawn belt.	U2349,2348@1424
farming	loop	Cloth 28-32: Hillsbrad Torn Fin (silk)	Silk Cloth, Fish Oil and clams from coastal murlocs; open clams for meat and pearls.	U2374,2375,2376,2377@1424
farming	loop	Cloth 10-13: Loch Modan Tunnel Rats (linen)	Linen Cloth from Silver Stream Mine kobolds; clear side tunnels between respawns.	U1172,1173,1174,1175,1176,1202@1432
farming	loop	Meat 11-17: Loch Modan bears	Bear Meat for Smoked Bear Meat and other cooking recipes; skin bears for additional leather.	U1186,1188,1189@1432
farming	loop	Cloth 15-19: Loch Modan troggs (wool)	Wool Cloth with some linen; work the higher-level Stonesplinter camps for First Aid materials.	U1164,1165,1167,1197@1432
farming	loop	Cloth 18-20: Loch Modan Mo'grosh (wool)	Wool Cloth from elite ogres; bring a group at the listed mob levels or return overleveled.	U1178,1179,1180,1181,1183@1432
farming	loop	Cloth 17-21: Redridge gnolls (wool)	Wool Cloth from Redridge gnolls; split pulls around the higher-level northern camps.	U426,430,446,580@1433
farming	loop	Cloth 22-26: Redridge Shadowhide (wool)	Wool Cloth from eastern Shadowhide camps; Darkweavers are casters and Brutes hit harder.	U433,432,568,431,429@1433
farming	loop	Cloth 43-45: Searing Dark Iron (mageweave)	Mageweave Cloth from Geologists and Watchmen; clear the surface dwarf camps for tailoring mats.	U5839,8637@1427
farming	loop	Mats 43-45: Searing Glassweb Spiders	Thick Spider's Silk and Shadow Silk for crafting; save White Spider Meat for cooking.	U5856@1427
farming	loop	Cloth 45-48: Searing Dark Iron (mageweave)	Mageweave Cloth from Slavers, Taskmasters and Lookouts; tunnel camps can have linked pulls.	U5844,5846,8566@1427
farming	loop	Mats 45-49: Searing fire elementals	Elemental Fire and Heart of Fire for crafting; avoid using fire spells on fire elementals.	U5850,5852@1427
farming	loop	Mats 47-49: Searing Muck Splash	Elemental Water and Globe of Water for crafting; loop the Muck Splash pools inside the Slag Pit.	U8837@1427
farming	loop	Cloth 10-14: Silverpine Moonrage (linen)	Linen Cloth from Moonrage worgen; watch for the roaming elite Son of Arugal.	U1769,1770,1779,1782@1421
farming	loop	Mats 16-18: Silverpine Vile Fin	Fish Oil, scales and clams from lake murlocs; open clams for meat and possible pearls.	U1957,1958@1421
farming	loop	Cloth 16-19: Silverpine Rot Hide (wool)	Wool Cloth from southern Rot Hide gnolls; Plague Weavers are casters, so interrupt them.	U1939,1940,1942,1943@1421
farming	loop	Cloth 32-35: STV Kurzen (silk)	Silk Cloth from Kurzen's Compound; Medicine Men heal, so interrupt or kill them first.	U937,940,938,941@1434
farming	loop	Cloth 33-37: STV Bloodscalp (silk)	Silk Cloth from northwest troll camps; Green Hills pages can be saved for quest buyers.	U694,697,699,701,702,671@1434
farming	loop	Cloth 34-36: STV Venture Co. (silk)	Silk Cloth from Venture Co. miners and geologists; clear the Lake Nazferiti work camps.	U1094,1096@1434
farming	loop	Meat 35-36: STV crocolisks	Tough Crocolisk Meat for Crocolisk Gumbo; skin Saltwater and Snapjaw Crocolisks for extra income.	U1151,1152@1434
farming	loop	Mats 36-37: STV water elementals	Elemental Water for crafting; circle the Lesser Water Elementals on the northwest coast.	U691@1434
farming	loop	Cloth 39-42: STV Skullsplitter (silk)	Silk Cloth with mageweave from central troll camps; save Green Hills pages for quest turn-ins.	U696,780,669,670,782,784@1434
farming	loop	Rep 40-41: STV Bloodsail beach	Silk and Mageweave Cloth; pirates raise Booty Bay rep and lower Bloodsail rep, with a rare Hyacinth Macaw chance.	U1561,1562@1434
farming	loop	Cloth 40-42: STV Venture Co. (mageweave)	Mageweave and silk from southern Venture Co. camps; clear Strip Miners before Foremen and casters.	U674,675,676,677@1434
farming	loop	Rep 42-45: STV Bloodsail ships	Mageweave, Booty Bay rep and rare Hyacinth Macaw chance; killing pirates lowers Bloodsail rep.	U1563,1564,1565,1653,4505,4506@1434
farming	loop	Cloth 43-44: STV Zanzil (mageweave)	Mageweave Cloth and Zanzil's Mixture for Crank Fizzlebub's quest; avoid Zanzil himself.	U1488,1489,1490,1491@1434
farming	loop	Mats 43-44: STV naga	Big-mouth Clams, Fish Oil and Naga Scales; open clams for Zesty Clam Meat and possible pearls.	U1907@1434
farming	loop	Rep 57: STV Booty Bay bruisers	Bruiser kills raise Bloodsail rep and lower Steamwheedle rep; bring a group and expect Booty Bay hostility.	U4624@1434
farming	loop	Cloth 34-38: Swamp Lost Ones (silk)	Silk Cloth from Fallow Sanctuary Lost Ones; interrupt Riftseekers and Seers for safer farming.	U755,757,759,760,761,762@1435
farming	loop	Pet 35-36: Swamp Dreaming Whelps	Rare Tiny Emerald Whelpling from Dreaming Whelps; Adolescent Whelps do not drop this pet in Classic.	U741@1435
farming	loop	Gold 36-37: Swamp jaguars	Long Soft Tails and Bristly Whiskers sell to vendors; skin Swamp Jaguars for added leather income.	U767@1435
farming	loop	Mats 38-40: Swampwalkers	Herbs and rare Advanced Herbalism enchant formula; no Herbalism skill is needed to loot killed Swampwalkers.	U764,765@1435
farming	loop	Mats 40-41: Swamp tarantulas	Shadow Silk, Thick Spider's Silk and White Spider Meat for crafting and cooking; sell silk on the AH.	U769@1435
farming	loop	Mats 41-45: Swamp coastal murlocs	Thick Murloc Scales, Fish Oil and Big-mouth Clams; open clams for Zesty Clam Meat and possible pearls.	U747,750,751,752@1435
farming	loop	Cloth 40-43: Hinterlands Witherbark	Mageweave and silk from lower-level Witherbark camps; interrupt Zealots and Venombloods.	U2649,2650,2651,2652@1425
farming	loop	Meat 43-48: Hinterlands wolves	Tender Wolf Meat for cooking; skin Silvermane wolves for leather and vendor their teeth.	U2924,2925,2926@1425
farming	loop	Cloth 45-47: Hinterlands Vilebranch	Mageweave Cloth from non-elite Vilebranch camps; avoid Jintha'Alor elite packs when farming solo.	U2639,2640,4466,4467@1425
farming	loop	Gold 46-48: Hinterlands Skulk Rock oozes	Vendor Gelatinous Goo and scavenged junk; open Scum Covered Bags for coins and supplies.	U2655,2656@1425
farming	loop	Cloth 6-8: Tirisfal Rot Hide (linen)	Linen Cloth from Rot Hide gnolls; clear the camps near Garren's Haunt for early tailoring mats.	U1674,1675,1941@1420
farming	loop	Cloth 6-8: Tirisfal Scarlet (linen)	Linen Cloth for bandages and tailoring; work the lower-level Scarlet camps first.	U1535,1536@1420
farming	loop	Cloth 8-11: Tirisfal Scarlet (linen)	Linen Cloth from the higher-level Scarlet camps; pull Friars away from nearby allies.	U1537,1538,1539,1540@1420
farming	loop	Rep 50-53: WPL Sorrow Hill	Runecloth and Argent Dawn scourgestones; equip Argent Dawn Commission and clear Sorrow Hill undead.	U1783,1784,1791@1422
farming	loop	Rep 52-54: WPL Felstone undead	Runecloth and Argent Dawn scourgestones; equip Argent Dawn Commission before farming Felstone zombies.	U4475,4474@1422
farming	loop	Mats 54-55: WPL Plague Lurkers	Ironweb Spider Silk, Shadow Silk and White Spider Meat; sell silk for high-level tailoring.	U1824@1422
farming	loop	Rep 54-55: WPL Dalson's Tears	Runecloth and Argent Dawn scourgestones; equip Argent Dawn Commission and clear the farm ghouls.	U1793,1794@1422
farming	loop	Rep 55-56: WPL Writhing Haunt	Runecloth and Argent Dawn scourgestones; equip Argent Dawn Commission and clear freezing and searing ghouls.	U1795,1796@1422
farming	loop	Formula 56-58: WPL Scarlet tower	Rare Crusader enchant formula from Spellbinders; kill nearby Avengers for runecloth between respawns.	U4493,4494@1422
farming	loop	Meat 10-11: Westfall eggs & feathers	Small Eggs for cooking and Light Feathers for spell reagents; save both white-quality drops from Young Fleshrippers.	U199@1436
farming	loop	Cloth 11-15: Westfall Defias (linen)	Linen Cloth from Defias camps; Moonbrook Pillagers cast hard-hitting fireballs.	U95,504,589,590@1436
farming	loop	Meat 12-17: Westfall goretusks	Boar Ribs, Goretusk Liver and snouts for cooking and Westfall quests; save white-quality drops.	U454,157,547@1436
farming	loop	Meat 13-17: Westfall fleshrippers	Stringy Vulture Meat for Westfall Stew; vendor feathers and skin the birds if trained.	U1109,154@1436
farming	loop	Cloth 15-18: Westfall Defias (wool)	Wool Cloth with linen from tougher Defias; farm Pathstalkers, Knuckledusters and Highwaymen.	U121,449,122@1436
farming	loop	Cloth 16-19: Westfall Riverpaw (wool)	Wool Cloth for bandages and tailoring; southern Riverpaw camps include caster Mystics.	U452,98,453@1436
farming	loop	Mats 18-19: Westfall Dust Devils	Elemental Air for crafting; scattered Dust Devils are a low-level alternative to Arathi elementals.	U832@1436
farming	loop	Cloth 20-23: Wetlands Mosshide (wool)	Wool Cloth from lower-level Mosshide camps; pull Mistweavers separately for easier kills.	U1007,1008,1009,1010@1437
farming	loop	Meat 21-26: Wetlands crocolisks	Crocolisk Meat and Tough Crocolisk Meat for cooking; circle the marsh pools and skin each kill.	U1417,1400,2089@1437
farming	loop	Meat 22-27: Wetlands mottled raptors	Raptor Eggs for Curiously Tasty Omelet; farm the western mottled raptor packs.	U1020,1021,1022,1023@1437
farming	loop	Mats 23-27: Wetlands red whelps	Rare Tiny Crimson Whelpling and Small Flame Sacs; all listed red whelps can drop the pet.	U1042,1069,1044@1437
farming	loop	Meat 23-29: Wetlands highland raptors	Raptor Eggs for cooking; clear the eastern highland raptor packs and skin them for extra income.	U1015,1016,1017,1018,1019@1437
farming	loop	Cloth 26-29: Wetlands Dragonmaw (silk/wool)	Silk and Wool Cloth from Dragonmaw camps; kill Bonewarders and Shadowwarders before melee orcs.	U1034,1035,1057,1036,1038@1437
farming	loop	Cloth 27-31: Wetlands Dark Iron (silk)	Silk Cloth and some wool from Dun Modr dwarves; elite packs favor a group or overleveled farmer.	U1051,1052,1053,1054@1437
farming	loop	Meat 1-2: Durotar mottled boars	Chunk of Boar Meat for starter cooking; follow the Valley of Trials boar spawns.	U3098@1411
farming	loop	Cloth 6-8: Durotar Razormane scouts	Linen for First Aid and tailoring; clear the quilboar camp before moving to its outer scouts.	U3111,3112@1411
farming	loop	Cloth 7-11: Durotar Dustwind harpies	Linen for tailoring; climb the harpy ridges and interrupt storm witches.	U3115,3116,3117,3118@1411
farming	loop	Cloth 8-10: Durotar Razormane guards	Linen and vendor loot from the higher-level quilboars; pull casters away from nearby guards.	U3113,3114@1411
farming	loop	Cloth 8-9: Durotar Echo Isles trolls	Linen and coin; clear Voodoo and Hexed Troll packs around the Echo Isles.	U3206,3207@1411
farming	loop	Cloth 9-11: Durotar Burning Blade	Linen and coin from cultists in the northern caves; check for patrols before pulling.	U3197,3198,3199@1411
farming	loop	Cloth 5-8: Mulgore Palemane gnolls	Linen for tailoring and bandages; work through the Palemane camps south of Bloodhoof Village.	U2949,2950,2951@1412
farming	loop	Cloth 5-8: Mulgore Venture Co. mine	Linen and coin; clear hirelings and taskmasters around the mine entrance before going inside.	U2975,2976,2977@1412
farming	loop	Eggs 5-10: Mulgore swoops	Small Eggs for cooking and seasonal Gingerbread Cookies; kill swoops around their known spawns.	U2969,2970,2971@1412
farming	loop	Cloth 7-11: Mulgore Windfury harpies	Linen for tailoring; follow the northern harpy ridges and interrupt the casters.	U2962,2963,2964,2965@1412
farming	loop	Cloth 8-10: Mulgore Venture Co. workers	Linen and vendor loot from workers and supervisors at the Venture Co. mine.	U2978,2979@1412
farming	loop	Cloth 5-7: Teldrassil Fel Rock sprites	Linen from sprites and grell in Fel Rock; pull cave packs carefully.	U2002,2003,2004,2005@1438
farming	loop	Cloth 5-8: Teldrassil Gnarlpine camp	Linen for First Aid and tailoring; clear the low-level Gnarlpine camps west of Dolanaar.	U2006,2007,2008,2009,2010@1438
farming	loop	Eggs 5-9: Teldrassil strigid owls	Small Eggs for cooking; follow owl spawns around Dolanaar and the surrounding woods.	U1995,1996,1997@1438
farming	loop	Cloth 8-11: Teldrassil Bloodfeather	Linen and coin; rotate through the Bloodfeather harpy nests in northwest Teldrassil.	U2015,2017,2018,2019,2020,2021@1438
farming	loop	Cloth 10-13: Darkshore Highborne ruins	Linen from cursed Highborne at Ameth'Aran; spellcasters can pull additional packs.	U2176,2177,2178@1439
farming	loop	Meat 11-14: Darkshore thistle bears	Bear Meat for cooking; clear the low-level bear spawns inland from Auberdine.	U2163,2164@1439
farming	loop	Clams 12-17: Darkshore coastal crawlers	Open dropped clams for Clam Meat or Tangy Clam Meat; keep crawler meat for cooking.	U2232,2235@1439
farming	loop	Cloth 12-14: Darkshore Blackwood camp	Linen from Blackwood furbolgs near the northern camp; pull shamans away from their allies.	U2167,2324@1439
farming	loop	Cloth 16-18: Darkshore Twilight camp	Wool and linen from Twilight Thugs and Disciples around the Master's Glaive.	U2338,2339@1439
farming	loop	Cloth 16-19: Darkshore Blackwood furbolgs	Wool and linen for tailoring; rotate through the higher-level Blackwood camp packs.	U2168,2169,2170@1439
farming	loop	Cloth 10-13: Barrens Razormane camp	Linen from the northern Razormane camps; First Aid and tailoring use full stacks.	U3265,3266,3267,3268,3269@1413
farming	loop	Cloth 12-14: Barrens Kolkar wranglers	Linen from Kolkar at the northern oasis; interrupt Stormers before they finish casting.	U3272,3273@1413
farming	loop	Cloth 12-15: Barrens Southsea pirates	Linen and coin from the pirates south of Ratchet; avoid pulling ship-side packs together.	U3381,3382,3383,3384@1413
farming	loop	Cloth 14-18: Barrens Witchwing harpies	Linen with some wool from higher-level harpies; follow the Witchwing nests northwest of the Crossroads.	U3276,3277,3278,3280@1413
farming	loop	Cloth 16-20: Barrens Bristleback camps	Wool and linen for bandages; clear the Bristleback camps south of the Crossroads.	U3258,3260,3261,3263@1413
farming	loop	Cloth 20-25: Barrens southern Razormane	Wool with some silk from higher-level quilboars; work the southern Razormane camps.	U3456,3457,3458,3459@1413
farming	loop	Cloth 14-16: Stonetalon Grimtotem camp	Linen and coin from Grimtotem packs around Camp Aparaje; pull sorcerers away from melee mobs.	U11910,11911,11912,11913@1442
farming	loop	Cloth 16-18: Stonetalon Gogger kobolds	Linen and wool from Gogger kobolds in Boulderslide Ravine; cave packs can chain-pull.	U11915,11917,11918@1442
farming	loop	Silk 16-20: Stonetalon Deepmoss spiders	Spider's Silk for tailoring; follow the Deepmoss spider spawns around Windshear Crag.	U4005,4006,4007@1442
farming	loop	Cloth 18-21: Stonetalon Venture Co.	Linen and wool from loggers and engineers around Windshear Crag; interrupt the engineers.	U3988,3989,3991,3992@1442
farming	loop	Cloth 20-22: Stonetalon Windshear mine	Wool and linen for tailoring; clear Windshear kobolds inside the mine and watch the corners.	U3999,4003,4004@1442
farming	loop	Cloth 23-27: Stonetalon Bloodfury	Wool and silk from harpies in the Charred Vale; interrupt Windcallers and Storm Witches.	U4022,4023,4024,4025,4026,4027@1442
farming	loop	Fire 23-27: Stonetalon Charred Vale	Elemental Fire for crafting; clear flame spirits and ravagers around the Charred Vale.	U4036,4037,4038@1442
farming	loop	Cloth 18-21: Ashenvale Dark Strand	Linen and wool from Dark Strand cultists at the northern ruins; interrupt casters.	U3725,3727,3728,3730@1440
farming	loop	Cloth 23-24: Ashenvale Thistlefur camp	Wool and silk from Thistlefur furbolgs; clear the village and cave packs carefully.	U3921,3922,3923,3924,3925,3926@1440
farming	loop	Cloth 23-25: Ashenvale Foulweald camp	Wool and silk from Foulweald furbolgs; rotate through the southern camp packs.	U3743,3745,3746,3748,3749,3750@1440
farming	loop	Silk 24-29: Ashenvale Wildthorn spiders	Spider's Silk for tailoring; kill the larger Wildthorn spiders rather than expecting cloth drops.	U3820,3821@1440
farming	loop	Cloth 25-27: Ashenvale Felmusk satyrs	Wool and silk for tailoring; pull Felmusk satyrs singly around their camp.	U3758,3759,3762,3763@1440
farming	loop	Cloth 26-28: Ashenvale Bleakheart satyrs	Silk and wool from Bleakheart satyrs; watch for stealth mobs between pulls.	U3765,3767,3770,3771@1440
farming	loop	Cloth 28-30: Ashenvale Xavian satyrs	Silk for tailoring and First Aid; clear Xavian and interrupt Hellcallers.	U3752,3754,3755,3757@1440
farming	loop	Cloth 24-28: Thousand Needles Galak	Wool and silk from Galak centaur camps; avoid pulling several casters together.	U4093,4094,4095,4096,4097,4099@1441
farming	loop	Cloth 25-28: Thousand Needles Grimtotem	Wool and silk from Grimtotem at Darkcloud Pinnacle; watch the narrow bridges and ledges.	U10758,10759,10760,10761@1441
farming	loop	Water 27-29: Thousand Needles elementals	Elemental Water for crafting; rotate Scalding and Boiling Elementals around the water pools.	U10756,10757@1441
farming	loop	Cloth 28-30: Thousand Needles harpies	Silk and wool from harpies in Screeching Canyon; interrupt the Windcallers.	U4100,4101,4104@1441
farming	loop	Earth 28-29: Thousand Needles boulderkin	Elemental Earth for crafting; boulderkin are scattered, so expect travel between pulls.	U4120@1441
farming	loop	Meat 30-35: Thousand Needles turtles	Turtle Meat for Soothing Turtle Bisque; clear Sparkleshell turtles in the Shimmering Flats.	U4142,4143,4144@1441
farming	loop	Cloth 30-33: Desolace Burning Blade	Silk and coin from Burning Blade cultists at Thunder Axe Fortress; interrupt casters.	U4663,4664,4665,4666,4667@1443
farming	loop	Cloth 30-33: Desolace Kolkar centaurs	Silk from the Kolkar camp; sell stacks to tailors or use them for bandages.	U4632,4633,4634,4635,4636,4637@1443
farming	loop	Cloth 31-33: Desolace Hatefury satyrs	Silk for tailoring; clear the Hatefury packs in Sargeron and watch for stealth mobs.	U4670,4671,4672,4673,4674,4675@1443
farming	loop	Air 32-37: Desolace whirlwinds	Elemental Air and Breath of Wind for crafting; follow the wandering whirlwind spawns.	U11576,11577,11578@1443
farming	loop	Cloth 32-37: Desolace Slitherblade naga	Silk and coin from Slitherblade naga on the northwest coast; water pulls may need breathing support.	U4711,4712,4713,4714,4715,4716,4718,4719@1443
farming	loop	Rep 32-36: Desolace Gelkis centaurs	Silk plus Magram reputation from Gelkis kills; this lowers Gelkis reputation, so choose your ally first.	U4646,4647,4648,4649,4651,4652,4653@1443
farming	loop	Rep 32-36: Desolace Magram centaurs	Silk plus Gelkis reputation from Magram kills; this lowers Magram reputation, so choose your ally first.	U4638,4639,4640,4641,4642,4644,4645@1443
farming	loop	Cloth 37-40: Desolace Maraudine camp	Silk with some mageweave from higher-level centaurs; clear the Valley of Spears camp packs.	U4654,4655,4656,4657,4658,4659@1443
farming	loop	Cloth 35-38: Dustwallow Mirefin murlocs	Silk and dropped clams from Mirefin murlocs; pull coast packs carefully to stop fleeing adds.	U4358,4359,4360,4361,4362,4363@1445
farming	loop	Meat 35-39: Dustwallow crocolisks	Tender Crocolisk Meat for cooking; follow Drywallow crocolisks around the marsh waterways.	U4341,4342,4343,4344@1445
farming	loop	Silk 35-39: Dustwallow Darkmist spiders	Spider silk reagents for tailoring; clear Darkmist Cavern and leave bag space for vendor loot.	U4376,4377,4378,4379@1445
farming	loop	Meat 39-43: Dustwallow coastal turtles	Turtle Meat and Big-mouth Clams; open clams for Zesty Clam Meat and possible pearls.	U4398,4399,4400@1445
farming	loop	Cloth 40-43: Feralas lower Gordunni	Mageweave and silk from lower-level Gordunni ogres; clear the northern ogre camp packs.	U5229,5232,5237@1444
farming	loop	Cloth 40-44: Feralas Woodpaw gnolls	Mageweave and silk from Woodpaw gnolls south of Camp Mojache; stop runners before they reach another pack.	U5249,5251,5253,5254,5255,5258@1444
farming	loop	Cloth 41-45: Feralas Hatecrest naga	Mageweave, silk and Big-mouth Clams from Hatecrest naga on the western islands; open clams for meat and pearls.	U5331,5332,5333,5334,5335,5336,5337@1444
farming	loop	Cloth 43-47: Feralas upper Gordunni	Mageweave for tailoring and bandages; clear higher-level Gordunni packs around the Ruins of Isildien.	U5234,5236,5238,5239,5240,5241@1444
farming	loop	Gold 43-46: Feralas Feral Scar yetis	Coin and vendor loot from Feral Scar yetis; skin corpses for extra leather if trained.	U5292,5293,5295@1444
farming	loop	Water 47-49: Feralas sea elementals	Elemental Water and Globe of Water for crafting; clear Sea Spray and Sea Elementals on the western coast.	U5461,5462@1444
farming	loop	Cloth 48-50: Feralas Northspring harpies	Mageweave and coin from Northspring harpies at the Ruins of Ravenwind; interrupt Windcallers.	U5362,5363,5364,5366@1444
farming	loop	Rep 40-45: Tanaris Wastewander camps	Mageweave and Water Pouches; turn five pouches in to Spigot Operator Luglunket in Gadgetzan after the prerequisite.	U5615,5616,5617,5618,5623@1446
farming	loop	Eggs 41-49: Tanaris desert rocs	Giant Eggs for Monster Omelet and the Artisan Cooking quest; rotate through desert roc spawns.	U5428,5429,5430@1446
farming	loop	Clams 42-50: Tanaris coastal turtles	Open Big-mouth Clams for Zesty Clam Meat and rare pearls; cooks need the meat for Artisan Cooking.	U14123,5431@1446
farming	loop	Cloth 44-45: Tanaris Southsea pirates	Mageweave and coin at Lost Rigger Cove; pirate kills also help Gadgetzan reputation until its kill cap.	U7855,7856,7857,7858@1446
farming	loop	Cloth 45-48: Tanaris Dunemaul ogres	Mageweave for tailoring and bandages; clear Dunemaul camp packs and interrupt Warlocks.	U5471,5472,5473,5474,5475@1446
farming	loop	Earth 45-47: Tanaris Land Ragers	Elemental Earth for crafting; these spawns are sparse, so expect travel and respawn waits.	U5465@1446
farming	loop	Cloth 45-47: Azshara Haldarr satyrs	Mageweave for tailoring; clear Haldarr satyrs near the western entrance and watch for stealth mobs.	U6125,6126,6127@1447
farming	loop	Cloth 45-47: Azshara Highborne ruins	Mageweave and coin from Highborne Apparitions and Lichlings; interrupt their spells at the ruins.	U6116,6117@1447
farming	loop	Silk 47-48: Azshara Timberweb spiders	Ironweb Spider Silk for high-level tailoring; follow Timberweb Recluse spawns through the woods.	U8762@1447
farming	loop	Cloth 51-53: Azshara blood elves	Runecloth and coin from blood elves at Thalassian Base Camp; interrupt Reclaimers.	U6198,6199@1447
farming	loop	Felcloth 51-53: Azshara Legashi satyrs	Felcloth, runecloth and Demonic Runes; runes bind on pickup and restore mana, while felcloth can be sold.	U6200,6201,6202@1447
farming	loop	Clams 53-55: Azshara Arkkoran makrura	Open Big-mouth Clams for Zesty Clam Meat and rare pearls; clear Arkkoran packs near their coastal camp.	U6135,6136,6137,6138@1447
farming	loop	Cloth 53-55: Azshara Spitelash ruins	Runecloth and dropped clams from higher-level Spitelash naga; interrupt Enchantresses at the Ruins of Eldarath.	U7885,7886@1447
farming	loop	Meat 47-52: Felwood Felpaw wolves	Tender Wolf Meat for Tender Wolf Steak; clear Felpaw wolf spawns and skin corpses if trained.	U8959,8960,8961@1448
farming	loop	Rep 48-50: Felwood southern Deadwood	Mageweave and Timbermaw reputation; complete Timbermaw Ally to unlock feather turn-ins before farming.	U7153,7154,7155@1448
farming	loop	Cloth 49-52: Felwood Jadefire Glen	Mageweave, felcloth and Demonic Runes from southern Jadefire satyrs; runes bind on pickup for mana recovery.	U7105,7106,7109,7110@1448
farming	loop	Cloth 50-53: Felwood Jaedenar camp	Runecloth and mageweave from Jaedenar cultists and guards; interrupt Adepts around the surface camp.	U7112,7113,7114,7115@1448
farming	loop	Felcloth 52-54: Felwood Jadefire Run	Felcloth, runecloth and Demonic Runes from northern satyrs; pull Hellcallers away from nearby packs.	U7107,7108,7111@1448
farming	loop	Life 52-53: Felwood Irontree woods	Living Essence and Heart of the Wild for crafting; rotate through Irontree Wanderers and Stompers.	U7138,7139@1448
farming	loop	Rep 53-55: Felwood northern Deadwood	Runecloth and Timbermaw reputation; collect Deadwood Headdress Feathers after the prerequisite and turn them in to Nafien.	U7156,7157,7158@1448
farming	loop	Water 53-54: Felwood Toxic Horrors	Essence of Water and Elemental Water for crafting; circle the Toxic Horror spawns in Irontree Woods.	U7132@1448
farming	loop	Life 48-53: Un'Goro Bloodpetal plants	Heart of the Wild and Living Essence for crafting; clear Bloodpetal plants across the crater floor.	U6509,6510,6511,6512@1449
farming	loop	Gold 50-53: Un'Goro Fungal Rock gorillas	Vendor loot from gorillas at Fungal Rock; skin them for extra leather if trained.	U6513,6514,6516@1449
farming	loop	Life 50-54: Un'Goro tar pits	Living Essence for crafting and vendor loot; rotate tar beasts through the northern Lakkari Tar Pits.	U6517,6518,6519,6527@1449
farming	loop	Gold 51-53: Un'Goro Gorishi hive	Vendor loot from Gorishi silithids in the Slithering Scar; the tunnels have close packs and limited exits.	U6551,6552,6553,6554,6555@1449
farming	loop	Fire 53-55: Un'Goro Fire Plume Ridge	Elemental Fire and Essence of Fire for crafting; climb the ridge while clearing fire elementals.	U6520,6521@1449
farming	loop	Cloth 53-58: Winterspring Ice Thistle	Runecloth and vendor loot from Ice Thistle yetis; skin corpses for extra leather if trained.	U7457,7458,7459,7460@1452
farming	loop	Rep 53-56: Winterspring Winterfall camp	Runecloth and Timbermaw reputation; unlock Winterfall Spirit Bead turn-ins through Winterfall Activity.	U7440,7441,7442@1452
farming	loop	Cloth 54-56: Winterspring Highborne	Runecloth from Highborne spirits at Lake Kel'Theril; use ranged pulls to separate spellcasters.	U7523,7524@1452
farming	loop	Eggs 54-59: Winterspring owls	Giant Eggs for Monster Omelet; follow Winterspring Owl and Screecher spawns in the snowy woods.	U7455,7456@1452
farming	loop	Rep 56-58: Winterspring Winterfall ursas	Runecloth, Winterfall Firewater and Timbermaw reputation; collect beads after the prerequisite for Salfa turn-ins.	U7438,7439@1452
farming	loop	Air 55-59: Silithus wind elementals	Essence of Air and Breath of Wind; elemental kills also grant Hydraxian Waterlords reputation until Honored.	U11744,11745@1451
farming	loop	Earth 56-59: Silithus desert elementals	Elemental Earth and Essence of Earth; these kills also grant Hydraxian Waterlords reputation until Honored.	U11746,11747@1451
farming	loop	Gold 57-59: Silithus Hive'Ashi elites	Group recommended for elite silithids; sell vendor loot and skin suitable corpses if trained.	U11698,11721,11722,11723,11724@1451
farming	loop	Gold 58-60: Silithus Hive'Zora	Elite packs need strong gear or a group; loot vendor items and skin suitable corpses if trained.	U11725,11726,11727,11728,11729@1451
farming	loop	Rep 58-60: Silithus Twilight camps	Runecloth and Encrypted Twilight Texts; turn ten texts in to Bor Wildmane for Cenarion Circle reputation.	U11880,11881,11882,11883@1451
farming	loop	Gold 59-61: Silithus Hive'Regal elites	Group recommended for elite silithids; sell vendor loot and skin suitable corpses if trained.	U11730,11731,11732,11733,11734@1451
quests	nearest	Quest: The Green Hills of Stranglethorn	Lv30-40; trade duplicate pages, complete all four chapters, then return to Barnil at the hunting camp.	Q339;Q340;Q341;Q342;Q338;U937,940,587,588@1434
quests	order	Chain: Tiger Mastery	Lv31-37; turn in each hunt to Ajeck before accepting the next; the final target is Sin'Dall.	Q185;Q186;Q187;Q188
quests	order	Chain: Panther Mastery	Lv31-40; turn in each hunt to Sir Erlgadin; stealthy panthers make the later stages slower.	Q190;Q191;Q192;Q193
quests	order	Chain: Raptor Mastery	Lv34-43; Hemet sends you through increasingly strong raptors; finish with Tethis.	Q194;Q195;Q196;Q197
quests	order	Chain: Nesingwary's final trophies	Lv37-43; finish the three Mastery trophy hunts, then defeat King Bangalash for a bow or rifle.	Q188;Q193;Q197;Q208
quests	order	(A) Chain: Colonel Kurzen's rebellion	Lv33-40; Rebel Camp hunts lead into the cave; bring help for Colonel Kurzen.	Q203;Q204;Q574;Q202;N813
quests	nearest	(A) Quest: Kurzen's Mystery	Lv38; read all four troll legends scattered among the ruins; return to Brother Nimetz.	Q207;O52,54,57,58@1434
quests	nearest	Quest: Bloodscalp Ears	Lv35; collect ears from Bloodscalp trolls in the northwest and turn in at Booty Bay.	Q189;U587,588,595@1434
quests	nearest	Quest: Skullsplitter Tusks	Lv42; collect tusks in the eastern troll ruins; return to Kebok in Booty Bay.	Q209;U667,669,670,696@1434
quests	nearest	Quest: Singing Blue Shards	Lv35; EK tour; hunt Cold Eye Basilisks for shards and return to Crank Fizzlebub.	Q605;U690@1434
quests	nearest	Quest: Some Assembly Required	Lv36; collect crocolisk skins along the rivers and return to Drizzlik in Booty Bay.	Q577;U1152@1434
quests	nearest	Quest: Venture Company Mining	Lv41; gather blue singing crystals from Venture Co. Geologists near the eastern mine.	Q600;U1096@1434
quests	order	Chain: The Bloodsail Buccaneers	Lv41-45; find correspondence, charts and orders before boarding the ships to kill the captains.	Q595;Q597;Q599;Q604;Q608
quests	nearest	Quest: Up to Snuff	Lv41; loot snuff from Bloodsail pirates along the southern coast; return to Deeg.	Q587;U1561,1562,1563,1564@1434
quests	nearest	Quest: Zanzil's Secret	Lv44; collect mixtures from Zanzil's followers in the southern ruins; return to Crank.	Q621;U1488,1489,1490,1491@1434
quests	nearest	(H) Quest: Hunt for Yenniku	Lv34; gather tusks from Bloodscalp trolls and return to Nimboya in Grom'gol.	Q581;U587,588,595,671@1434
quests	nearest	(H) Quest: The Singing Crystals	Lv45; collect pulsating crystals from Ironjaw Basilisks for Kin'weelay's Yenniku chain.	Q589;U1551@1434
quests	nearest	Quest: Voodoo Dues	Lv44; collect the three named troll trophies at the southern ruins for Sea Wolf MacKinley.	Q609;U2535,2536,2537@1434
quests	nearest	Quest: Akiris by the Bundle	Lv43; collect akiris reeds from Naga Explorers on the western coast; return to Bloads.	Q617;U1907@1434
quests	nearest	Quest: Whiskey Slim's Lost Grog	Lv50; EK tour; collect bottles on the Hinterlands coast, then return to Whiskey Slim in Booty Bay.	Q580;O2068@1425
quests	nearest	(A) Quest: Witherbark Cages	Lv45; EK tour; inspect all three cages at the Witherbark camps for Gryphon Master Talonaxe.	Q2988;O144066,144067,144068@1425
quests	nearest	(A) Quest: Troll Necklace Bounty	Lv45; EK tour; gather troll necklaces around the Witherbark camps; turn in at Aerie Peak.	Q2880;U2649,2650,2651@1425
quests	nearest	(A) Quest: Skulk Rock Clean-up	Lv48; clear Green Sludge and Jade Ooze at Skulk Rock for Fraggar Thundermantle.	Q2877
quests	nearest	(H) Quest: Dark Vessels	Lv50; EK tour; collect vessels of tainted blood throughout Jintha'Alor; bring a group for the upper terraces.	Q7850;O179922@1425
quests	nearest	(H) Quest: Vilebranch Hooligans	Lv48; search for Slagtree's lost tools at the troll settlements; the tool spawn can vary.	Q7839;O179908@1425
quests	nearest	(H) Quest: Separation Anxiety	Lv50; collect a pile of bones and a pile of skulls in Jintha'Alor for Huntsman Markhor.	Q7849;O179914,179915@1425
quests	order	Quest: The Ancient Egg (EK leg)	Lv50; group for Jintha'Alor guards and the cave egg; accept and turn in with Yeh'kinya in Tanaris.	U2648@1425;U7995@1425;O175889@1425
quests	order	(H) Chain: Rescue Elder Torntusk	Lv51; EK tour; climb Jintha'Alor, recover the key from Hitah'ya, and return to Revantusk Village.	Q7845;Q7846;Q7847;N10802
quests	nearest	(H) Quest: Venom Bottles (EK tour)	Lv43; EK tour; search the Hinterlands troll camps for a venom bottle, then visit Apothecary Lydon in Tarren Mill.	O142702,142703,142704,142705,142706,142707,142708,142709,142710,142711,142712,142713,142714@1425;Q2933
quests	nearest	Quest: The Lost Fragments	Lv41; gather the three tablet fragments from Enraged Rock Elementals for Theldurin the Lost.	Q692;U2791@1418
quests	nearest	(A) Quest: A Dwarf and His Tools	Lv35; recover Ryedol's tools from Angor Fortress dwarves; return to the camp north of the fortress.	Q719;U2739,2740,2742,2743@1418
quests	nearest	Quest: Power Stones	Lv36; EK tour; collect both power stone colors from Shadowforge dwarves at the Uldaman dig entrance.	Q2418;U4844,4845,4846@1418
quests	order	Chain: Study of the Elements: Rock	Lv37-42; EK tour; turn in each rock sample tier to Lotwil before hunting the next elemental tier.	Q710;Q711;Q712
quests	nearest	Quest: Barbecued Buzzard Wings (local)	Lv40; gather buzzard wings for Rigglefuzz; this local collection leg teaches a cooking recipe.	N2817;U2829,2830,2831@1418
quests	nearest	(H) Quest: Badlands Reagent Run (EK tour)	Lv39; EK tour; collect coyote jaws, buzzard gizzards and rock shards; turn in to Jarkal at Kargath.	Q2258;U2727,2728,2729,2829,2830,2735@1418
quests	nearest	(A) Quest: Badlands Reagent Run (EK tour)	Lv39; EK tour; collect the three Badlands reagent types, then return to Ghak Healtouch in Thelsamar.	Q2500;U2727,2728,2729,2829,2830,2735@1418
quests	nearest	(H) Quest: Coyote Thieves	Lv40; EK tour; collect coyote jawbones in the Badlands for Neeka Bloodscar in Kargath.	Q1419;U2727,2728,2729@1418
quests	order	(A) Chain: Agmond's Fate (EK tour)	Lv38-42; EK tour; follow the expedition from Loch Modan into Badlands; inspect Agmond's remains before hunting Murdaloc.	Q738;Q704;Q739;U2893,2945@1418
quests	nearest	Quest: Counting Out Time	Lv56; collect watches from the ruins of Andorhal for Chromie; search ruined buildings.	Q4972;O175802@1422
quests	order	Chain: The Wildlife Suffers Too	Lv54-56; EK tour; complete the diseased wolf hunt before the grizzly hunt for Mulgris Deepriver.	Q4984;Q4985
quests	nearest	(A) Quest: All Along the Watchtowers	Lv56; use the beacon at each of the four Andorhal towers and return to Ashlam Valorfist.	Q5097
quests	nearest	(H) Quest: All Along the Watchtowers	Lv56; EK tour; mark all four Andorhal towers with the beacon and return to High Executor Derrington.	Q5098
quests	order	(A) Chain: The Scourge Cauldrons	Lv53-58; clear each farm, loot its cauldron key, and report back before proceeding to the next farm.	Q5215;Q5216;Q5217;Q5219;Q5220;Q5222;Q5223;Q5225;Q5226;Q5237
quests	order	(H) Chain: The Scourge Cauldrons (EK tour)	Lv53-58; EK tour; visit the four farms in sequence, returning to the Bulwark after each key and cauldron.	Q5228;Q5229;Q5230;Q5231;Q5232;Q5233;Q5234;Q5235;Q5236;Q5238
quests	order	Chain: Unfinished Business	Lv56-58; help Kirsta Deepshadow, then kill Radley and Durgen before scouting the tower.	Q6004;Q6023;Q6025
quests	order	(A) Chain: A Plague Upon Thee (EK tour)	Lv55; EK tour; collect termites in Eastern Plaguelands, then use the barrel at Northridge Lumber Mill.	Q5903;O177464@1423;Q5904;O177490@1422;Q6389
quests	order	(H) Chain: A Plague Upon Thee (EK tour)	Lv55; EK tour; gather termites in Eastern Plaguelands before sabotaging Northridge Lumber Mill.	Q5901;O177464@1423;Q5902;O177490@1422;Q6390
quests	nearest	Quest: Pamela's Doll	Lv55; search Darrowshire houses for the head and two sides, combine them, and return to Pamela.	Q5149;O176116,176142,176143@1423
quests	order	Chain: Darrowshire memories (EK tour)	Lv55-56; EK tour; Pamela leads to Auntie Marlene and Chromie; retrieve the annals before meeting Carlin.	Q5149;Q5152;Q5153;Q5154;Q5210
quests	nearest	Quest: Defenders of Darrowshire	Lv55; free Darrowshire spirits from undead and speak to them for Carlin Redpath.	Q5211;U8530,8532@1423
quests	order	Chain: Tirion Fordring hunts (EK tour)	Lv56; EK tour; complete all three beast collections before Redemption; Carrion Grubbage needs grub meat.	Q5542;Q5543;Q5544;Q5742;U8603@1423
quests	nearest	(H) Quest: To Kill With Purpose	Lv58; collect living rot from undead around Corin's Crossing for Nathanos; it expires quickly.	Q6022;U8523,8524,8530,8532@1423
quests	nearest	(H) Quest: Un-Life's Little Annoyances	Lv58; hunt Noxious and Monstrous Plaguebats for Nathanos Blightcaller.	Q6042
quests	nearest	(H) Quest: The Ranger Lord's Behest	Lv60; kill the three Quel'Lithien elf types and recover the registry; watch for grouped enemies.	Q6133
quests	order	Quest: Hameya's Plea	Lv60; read the scroll, recover Hameya's key at Zul'Mashar, then search the dirt mound for the reward.	Q6024;N12248;O177675@1423
quests	order	(A) Chain: Northshire kobold cleanup	Lv2-5; report to Marshal McBride after each increasingly difficult Echo Ridge assignment.	Q7;Q15;Q21
quests	order	(A) Chain: Milly's Harvest	Lv4; gather grape buckets in the vineyard, then take Milly's manifest to Brother Neals upstairs.	Q3903;Q3904;Q3905;O161557@1429
quests	nearest	(A) Quest: Brotherhood of Thieves	Lv4; recover red bandanas from the vineyard Defias for Deputy Willem.	Q18;U38@1429
quests	nearest	(A) Quest: A Bundle of Trouble	Lv9; collect bundles of wood around Eastvale Logging Camp; watch for bears between trees.	Q5545;O176793@1429
quests	nearest	(A) Quests: Gold Dust and Kobold Candles	Lv7; collect both dust and candles in Fargodeep Mine before returning to Goldshire.	Q47;Q60;U40,475@1429
quests	order	(A) Chain: The Lost Necklace	Lv6-8; bring boar meat to Billy, deliver the pie, and then retrieve the necklace from Goldtooth.	Q85;U113@1429;N246;Q84;Q87
quests	order	(A) Chain: Young Lovers	Lv6-7; collect kelp for the potion after visiting Maybell, Tommy, Gramma and William.	Q106;Q111;Q107;Q112;Q114
quests	order	(A) Chain: Find the Lost Guards	Lv10; check both guard remains in the forest before reporting to Thomas and Goldshire.	Q40;Q35;Q37;Q45;Q71;Q39;Q59
quests	nearest	(A) Quest: Red Linen Goods	Lv9; gather red linen bandanas from Defias east of Goldshire; turn in at Eastvale.	Q83;U116,473@1429
quests	nearest	(A) Quest: Riverpaw Gnoll Bounty	Lv10; EK tour; collect painted armbands around Forest's Edge; return to Deputy Rainer at Westbrook.	Q11;U97,478@1429
quests	order	(A) Chain: Coldridge Valley mail	Lv3-5; deliver mail to Talin and Grelin, then carry Senir's observations toward Kharanos.	Q233;Q234;Q282;Q420
quests	nearest	(A) Quest: A Refugee's Quandary	Lv3; find Felix's box, chest and bucket of bolts around Coldridge Valley.	Q3361;O148499,178084,178085@1426
quests	order	(A) Chain: The Troll Cave and journal	Lv4-5; clear the Frostmane cave, then recover Grelin's journal from Grik'nir.	Q182;Q218;N808
quests	order	(A) Chain: Evershine for Jetsteam	Lv6-8; stock Jetsteam, visit Rejold, complete his beast hunt, and return to Bellowfiz.	N1378;U1125,1128@1426;Q318;Q319;Q320
quests	nearest	(A) Quest: The Perfect Stout	Lv9; loot shimmerweed baskets at the Frostmane camps for Rejold Barleybrew.	Q315;O276@1426
quests	nearest	(A) Quest: The Grizzled Den	Lv7; collect wendigo manes in the Grizzled Den and return to Pilot Stonegear.	Q313;U1134,1135@1426
quests	nearest	(A) Quest: Operation Recombobulation	Lv10; gather both mechanical parts from leper gnomes outside Gnomeregan for Razzle Sprysprocket.	Q412;U1211@1426
quests	order	(A) Chain: The Defias Brotherhood (EK tour)	Lv18-22; Lakeshire and Stormwind tour, messenger hunt and escort; the finale needs a Deadmines group.	Q65;Q132;Q135;Q141;Q142;Q155;Q166
quests	order	(A) Chain: The People's Militia	Lv12-17; finish each Defias tier for Gryan Stoutmantle before moving to the next camp.	Q12;Q13;Q14
quests	nearest	(A) Quest: Poor Old Blanchy	Lv14; gather sacks of oats from the farms for Verna Furlbrow near the Elwynn border.	Q151;O2724@1436
quests	nearest	(A) Quest: Westfall Stew	Lv13; collect meat, eyes and okra from local beasts and golems; return to Salma Saldean.	N235;U157,454,199,1109,126,127,36,114@1436
quests	nearest	(A) Quest: Patrolling Westfall	Lv14; collect gnoll paws from Riverpaw camps and return to Captain Danuvin at Sentinel Hill.	Q102;U123,124,452@1436
quests	nearest	(A) Quest: Redridge Goulash	Lv18; gather condor meat, boar snouts and spider eyes for Chef Breanna in Lakeshire.	N343;U547,428,442@1433
quests	nearest	(A) Quest: The Everstill Bridge	Lv20; EK tour; collect iron pikes and rivets from Redridge gnolls; return to Foreman Oslow.	Q89;U426,430@1433
quests	nearest	(A) Quest: Rethban Ore	Lv24; EK tour; gather ore in the Rethban caves and take it to Brother Paxton near the tower.	Q347;U580@1433;O2054,2055@1433
quests	order	(A) Chain: A Free Lunch	Lv15; visit Guard Parker and Martie, then bring the daffodils back to Darcy.	Q129;Q130;Q131
quests	nearest	(A) Quest: The Totem of Infliction	Lv25; EK tour; collect skeleton fingers, ghoul fangs and spider venom for Madame Eva.	Q101;U48,203,202,531,217@1431
quests	order	(A) Chain: The Night Watch	Lv24-30; turn in each undead hunt to Althea Ebonlocke before starting the next tier.	Q56;Q57;Q58
quests	order	(A) Chain: Worgen in the Woods	Lv28-31; EK tour; progress from Nightbane Shadow Weavers to the stronger worgen, then report to Jonathan.	Q173;Q221;Q222;Q223
quests	order	(A) Chain: Mor'Ladim	Lv35; investigate the weathered grave and Morgan Ladimore's story; bring help for Mor'Ladim.	Q225;Q227;Q228;Q229;Q231;O61@1431
quests	order	(A) Chain: The Legend of Stalvan (EK tour)	Lv28-35; EK tour; follow the documents through Westfall, Elwynn and Stormwind before confronting Stalvan.	Q66;Q67;Q68;Q69;Q70;Q72;Q74;Q75;Q78;Q79;Q80;Q97;Q98;N315
quests	nearest	(A) Quest: Gather Rot Blossoms	Lv24; gather rot blossoms from undead around Raven Hill; return to Tavernkeep Smitts.	Q156;U202,531@1431
quests	order	(A) Chain: The Embalmer	Lv24-30; follow Abercrombie's errands and collections; the final threat to Darkshire is elite.	Q148;Q149;Q154;Q157;Q158;Q156;Q159;Q133;Q134;Q160;Q251;Q401;Q252;Q253
quests	nearest	(A) Quest: Bingles' Missing Supplies	Lv15; find three tool buckets and the blastencapper near the eastern shore; return to Bingles.	Q2038;O104564,104569,104574,104575@1432
quests	nearest	(A) Quest: Thelsamar Blood Sausages	Lv11; collect bear meat, boar intestines and spider ichor for Vidra Hearthstove.	N1963;U1186,1190,1195@1432
quests	nearest	(A) Quest: Gathering Idols	Lv18; collect carved stone idols from the troggs around Ironband's excavation.	Q297;U1393@1432
quests	nearest	(A) Quest: Filthy Paws	Lv15; recover miners' gear from crates in Silver Stream Mine for Mountaineer Stormpike.	Q307;O271@1432
quests	order	(A) Chain: In Defense of the King's Lands	Lv12-17; EK tour; complete the four mountaineer assignments as the trogg enemies become stronger.	Q224;Q237;Q263;Q217
quests	nearest	(A) Quest: Uncovering the Past	Lv28; search ancient relics at Whelgar's excavation for four artifacts; return to Prospector Whelgar.	Q299;O333,334,35252@1437
quests	order	(A) Chain: Ormer's Revenge	Lv24-29; complete the two raptor hunts before facing Sarltooth at the excavation.	Q294;Q295;Q296;N1353
quests	nearest	(A) Quest: Digging Through the Ooze	Lv24; loot oozes near Ironbeard's Tomb until you recover the bag for Sida in Menethil.	Q470;U1032,1033@1437
quests	order	(A) Chain: The Cursed Crew	Lv27-30; bring mead for Fitzsimmons, then clear the wrecks and recover both captain trophies to lift the curse.	N1239;Q289;Q290;Q292
quests	order	(A) Chain: Nek'rosh's Gambit	Lv28-32; gather banners, burn the Dragonmaw catapults, then defeat Nek'rosh; a group helps.	Q464;Q465;Q474
quests	nearest	(H) Quest: Scavenging Deathknell	Lv3; search equipment boxes around Deathknell for six supplies; return to Deathguard Saltain.	Q3902;O164662@1420
quests	nearest	(H) Quest: Doom Weed	Lv6; collect doom weed near the graveyard for Junior Apothecary Holland; avoid nearby gnolls.	Q5482;O176753@1420
quests	nearest	(H) Quest: Gordo's Task	Lv5; collect gloom weed around Brill and deliver it to Junior Apothecary Holland.	Q5481;O175566@1420
quests	order	(H) Chain: A New Plague	Lv6-11; EK tour; gather the three reagent types for Johaan, then test the finished plague on his prisoner.	Q367;Q368;Q369;Q492
quests	nearest	(H) Quest: Deaths in the Family	Lv11; collect the three Agamand family weapons at the mills and return to Coleman Farthing.	Q354;U1654,1655,1656@1420
quests	order	(H) Chain: At War with the Scarlet Crusade	Lv8-12; EK tour; turn in each Scarlet hunt at Brill before attacking the next outpost.	Q427;Q370;Q371;Q372
quests	order	(H) Chain: The Scarlet Crusade in Deathknell	Lv4-5; collect Scarlet armbands, intercept Meven Korgal, then carry the intelligence to Brill.	Q381;Q382;Q383;N1667
quests	nearest	(H) Quest: Graverobbers	Lv8; clear both Rot Hide types and collect their embalming ichor for Magistrate Sevren.	Q358
quests	order	(H) Chain: Arugal's Folly	Lv11-15; recover the remedy, collect shackles and hearts, then confront Grimson at the farm.	Q422;Q423;Q99;Q424
quests	order	(H) Chain: Lost Deathstalkers (EK tour)	Lv11-12; EK tour; find Quinn, gather wild hearts, visit Renferrel and return to Quinn's wife.	Q428;Q429;Q430;Q449
quests	nearest	(H) Quest: Ambermill Investigations	Lv16; EK tour; gather Dalaran pendants from Ambermill casters for Dalar Dawnweaver.	Q479;U1912,1914,1915@1421
quests	order	(H) Chain: Rot Hide clues (EK tour)	Lv16-17; EK tour; inspect the ferry and island clues, gather ichor, then report the origins in Undercity.	Q438;Q439;Q443;Q444
quests	order	(H) Chain: A Recipe for Death (EK tour)	Lv12-18; EK tour; gather the first reagents in Silverpine, report to Undercity, then prepare the next batch.	Q447;Q450;Q451
quests	order	(H) Chain: Battle of Hillsbrad (EK tour)	Lv24-32; EK tour; complete each Hillsbrad assault and Dun Garok stage before reporting to Varimathras.	Q527;Q528;Q529;Q532;Q539;Q541;Q550
quests	order	(H) Chain: Helcular's Revenge (EK tour)	Lv33; EK tour; loot the rod from yetis, charge it at all three flames, then use it at Helcular's grave.	Q552;Q553;O1768,1769,1770@1416
quests	nearest	(H) Quest: Prison Break In (EK tour)	Lv34; EK tour; recover four prisoners' belongings from Dalaran enemies; return to Tarren Mill.	Q544;U2411,2412,2413,2414@1416
quests	order	(H) Chain: The Crown of Will (EK tour)	Lv39-43; EK tour; hunt Crushridge ogres and their leaders in Alterac; the final crown leads to Undercity.	Q495;Q518;Q519;Q520;Q521
quests	nearest	(A) Quest: Preserving Knowledge (EK tour)	Lv38; EK tour; recover the worn leather book and tomes from Alterac; return to Loremaster Dibbs in Southshore.	Q540;O1760@1416;U2252,2253,2255@1416
quests	nearest	(A) Quest: Worth Its Weight in Gold	Lv36; gather tusks, medicine pouches and shadow hunter knives from Witherbark trolls for Skuerto.	Q691;U2554,2555,2556,2557@1417
quests	order	(A) Chain: Trelane's Defenses	Lv39; recover the wand and crystal, get the enchantment, then collect the three tower relics.	Q693;Q694;Q695;Q696;O2716@1417
quests	order	(H) Chain: The Stromgarde sigils	Lv37-42; collect the four sigils and unlock Trol'kalar; several Stromgarde targets are elite.	Q639;Q640;Q641;Q643;Q644;Q645;Q646;O2703@1417
quests	order	(H) Chain: Call to Arms	Lv32-40; complete the Witherbark stage before progressing to the Boulderfist ogres.	Q677;Q678;Q679
quests	nearest	Quest: Deep Sea Salvage	Lv40; search both underwater wrecks for four documents; keep enough breath to escape the naga.	Q662;O2707,2708,2709,2710@1417
quests	order	Chain: Sunken Treasure (Faldir's Cove)	Lv40; EK tour; follow the diver's instructions, collect the gems, then report back to Captain O'Breen.	Q665;Q666;Q668
quests	nearest	Quest: Draenethyst Crystals	Lv35; collect six crystals around the Lost One village and return to Magtoor.	Q1389;O22550@1435
quests	nearest	(H) Quest: Pool of Tears	Lv43; dive around the temple for Atal'ai artifacts; return to Fel'zerul in Stonard.	Q1424;O30854@1435
quests	nearest	(A) Quest: Encroaching Wildlife	Lv37; kill young crocolisks, jaguars and sorrow spinners around the western swamp.	Q1396
quests	order	(H) Chain: Threat from the Sea	Lv43-45; EK tour; work through the coastal murloc hunts for Katar and Tok'Kar before the continued threat.	Q1422;Q1426;Q1427;Q1428
quests	nearest	Quest: Snickerfang Jowls	Lv50; collect hyena jowls, boar lungs and scorpok pincers for a temporary strength buff.	Q2581;U5984,5985,5992,5988@1419
quests	nearest	Quest: A Boar's Vitality	Lv50; collect boar lungs, scorpok pincers and basilisk brains for a temporary stamina buff.	Q2583;U5992,5988,5990@1419
quests	nearest	Quest: The Decisive Striker	Lv50; collect scorpok pincers, boar lungs and vulture gizzards for a temporary agility buff.	Q2585;U5988,5992,5982@1419
quests	nearest	Quest: The Basilisk's Bite	Lv50; collect basilisk brains and vulture gizzards for a temporary intellect buff.	Q2601;U5990,5982@1419
quests	nearest	Quest: Vulture's Vigor	Lv50; collect vulture gizzards and hyena jowls for a temporary spirit buff.	Q2603;U5982,5984,5985@1419
quests	order	Chain: The Torch of Retribution	Lv48-52; collect the flame, shaft and casing, then use the torch to light all four towers.	Q3441;Q3442;Q3443;Q3452;Q3453;Q3454;Q3462;Q3463
quests	nearest	Quest: Stolen Tuyere and Spyglass	Lv48; loot the tuyere from Dark Iron Steamsmiths and the spyglass from Lookouts; return to Taskmaster Scrange.	Q7728;U5840,8566@1427
quests	nearest	Quest: Culling the Competition	Lv48; clear Dark Iron Taskmasters and Slavers in the Cauldron for Taskmaster Scrange.	Q7729
quests	nearest	Quest: Incendosaurs	Lv49; find incendosaurs in the lower Cauldron tunnels; return to Hansel Heavyhands.	Q7727
quests	nearest	(A) Quest: Dragonkin Menace	Lv54; clear the four black dragonkin types near Morgan's Vigil to begin the Onyxia attunement chain.	Q4182
quests	nearest	Quest: Broodling Essence	Lv52; use the Draco-Incarcinatrix on broodlings before killing them, then collect the essence.	Q4726;U7047,7048,7049@1428
quests	order	(A) Chain: Thaurissan Relics (EK tour)	Lv54; EK tour; hear Archesonus' story in Ironforge, inspect twelve Burning Steppes relics, then return to her.	Q3702;Q3701;O153556@1428
quests	nearest	(A) Quest: FIFTY! YEP!	Lv56; collect fifty Blackrock Medallions from orcs for Oralius at Morgan's Vigil.	Q4283;U7025,7026,7027,7028,7029@1428
quests	order	(A) Chain: The Missing Diplomat (EK tour)	Lv28-33; EK tour; follow the Stormwind, Duskwood and Menethil investigation; this route ends before the boat to Kalimdor.	Q1274;Q1241;Q1242;Q1243;Q1244;Q1245;Q1246;Q1447;Q1247;Q1248;Q1249;Q1250
quests	order	(A) Chain: Onyxia - True Masters (EK tour)	Lv54; Morgan's Vigil, Lakeshire and Stormwind tour ends at Maxwell; continue Marshal Windsor inside BRD.	Q4183;Q4184;Q4185;Q4186;Q4223;Q4224;Q4241
quests	order	(A) Chain: Marshal Windsor returns (EK tour)	Lv60; EK tour; after BRD Jail Break, report to Maxwell, talk to Rowe, and follow Windsor through Stormwind.	Q6402;N17804;N12580;Q6403;N1749
quests	order	(A) Chain: Stormwind flight introduction	Lv10; Westfall-to-Stormwind tour introduces the flight master and a return flight to Sentinel Hill.	Q6181;Q6281;Q6261;Q6285
quests	order	(A) Chain: Ironforge flight introduction	Lv10; Loch Modan-to-Ironforge tour introduces Gryth Thurden and returns you to Brock Stoneseeker.	Q6387;Q6391;Q6388;Q6392
quests	order	(H) Chain: Undercity flight introduction	Lv10; Silverpine-to-Undercity tour introduces Michael Garrett and returns to Podrig at the Sepulcher.	Q6321;Q6323;Q6322;Q6324
quests	order	(A) Chain: Harlan and Thurman supplies	Lv2; a short city errand from Harlan to Rema, ending with Thurman's package.	Q333;Q334
quests	order	(H) Chain: Warrior Agamand heirlooms (EK tour)	Lv10-11 warrior; EK tour; speak with Dillinger, defeat Ulag, then collect four heirlooms for Coleman.	Q1818;Q1819;Q1820;Q1821;Q1822;O105169,105170,105171,105172@1420
quests	order	(A) Chain: Warrior defensive training (EK tour)	Lv10 warrior; EK tour; visit Harry and Bartleby in Stormwind, then retrieve Marshal Haggard's badge in Elwynn.	Q1638;Q1639;Q1640;Q1665;Q1666;Q1667
quests	order	(A) Chain: Dwarf warrior weapon (EK tour)	Lv10-11 warrior; Ironforge-to-Dun Morogh tour for Vejrek and Ironband's stolen shipment.	Q1679;Q1678;Q1680;Q1681;Q1682
quests	order	(A) Chain: Dwarf hunter pet training	Lv10 hunter; EK tour; tame a large boar, snow leopard and ice claw bear in order, then visit the Ironforge pet trainer.	Q6064;U1126@1426;Q6084;U1201@1426;Q6085;U1196@1426;Q6086
quests	order	(A) Chain: Human priest garments (EK tour)	Lv4 priest; EK tour; visit Priestess Josetta, heal and fortify Guard Roberts, then report back.	Q5623;Q5624
quests	order	(A) Chain: Dwarf priest garments (EK tour)	Lv4 priest; EK tour; visit Maxan, heal and fortify Mountaineer Dolf, then return to the trainer.	Q5626;Q5625
quests	order	(H) Chain: Undead priest garments	Lv4 priest; visit Dark Cleric Beryl and heal Deathguard Kel before reporting back.	Q5651;Q5650
quests	order	(A) Chain: Rogue lockpicking (EK tour)	Lv16-20 rogue; Stormwind-to-Redridge training tour; practice on the mill boxes before opening Lucius' chest.	Q2281;Q2282;O178244,178245,178246,121264@1433
quests	order	(A) Chain: Rogue Klaven's Tower (EK tour)	Lv20-24 rogue; EK tour; travel from SI:7 to Westfall, recover the tower items, then seek Doc Mixilpixil.	Q2360;Q2359;Q2607;Q2608
quests	order	(A) Chain: Human paladin resurrection	Lv12-13 paladin; Stormwind-to-Elwynn tour; bring linen for Stephanie, then resurrect Henze and recover the letter.	Q1641;Q1642;Q1643;N6174;Q1780;Q1781;Q1786;Q1787;Q1788
quests	order	(A) Chain: Dwarf paladin resurrection	Lv12-13 paladin; Ironforge-to-Dun Morogh tour; bring linen for John, then resurrect Narm and recover the letter.	Q1645;Q1646;Q1647;N6175;Q1778;Q1779;Q1783;Q1784;Q1785
quests	order	Quest: Warrior Kinship (EK tour)	Lv52 warrior; EK tour; seek the Fallen Hero of the Horde, hunt helboars, then fight the Shadowsworn.	Q8423;Q8424
quests	order	(A) Chain: Mithril Order contacts (EK tour)	Lv40 blacksmith; EK tour; visit Hank in Stormwind and McGavan in Booty Bay before meeting Galvan; EK introduction leg only.	Q2759;Q2760
quests	nearest	Quest: Crystals of Power	Lv 53. Collect all four crystal colors before visiting J.D. Collie.	Q4284;O164658,164659,164660,164661,164778,164779,164780,164781@1449
quests	order	Chain: Un'Goro Crystal Pylons	Lv 53. Inspect north, east and west pylons; report each discovery to J.D. Collie.	Q4285;O164955@1449;Q4287;O164957@1449;Q4288;O164956@1449;Q4321
quests	nearest	Quest: Crystal Restore	Lv 53. Green and yellow crystals become Crystal Restore at the northern pylon.	Q4381;O164659,164661@1449
quests	nearest	Quest: Crystal Force	Lv 53. Blue and green crystals become Crystal Force at the eastern pylon.	Q4382;O164658,164659@1449
quests	nearest	Quest: Crystal Ward	Lv 53. Green and red crystals become Crystal Ward at the western pylon.	Q4383;O164659,164660@1449
quests	nearest	Quest: Crystal Yield	Lv 53. Blue and red crystals become Crystal Yield at the western pylon.	Q4384;O164658,164660@1449
quests	nearest	Quest: Crystal Charge	Lv 53. Red and yellow crystals become Crystal Charge at the northern pylon.	Q4385;O164660,164661@1449
quests	nearest	Quest: Crystal Spire	Lv 53. Blue and yellow crystals become Crystal Spire at the eastern pylon.	Q4386;O164658,164661@1449
quests	nearest	Quest: Expedition Salvation	Lv 53. Find both the food crate and research equipment; return to Williden Marshal.	Q3881;O161526,161521@1449
quests	nearest	Quest: Roll the Bones	Lv 51. Collect dinosaur bones from ground piles and diemetradons; return to Spark Nilminer.	Q3882;O161527@1449;U9162,9163,9164@1449
quests	nearest	(A) Quest: Bloodpetal Sprouts	Lv 53. Gather scattered Bloodpetal Sprouts for Muigin.	Q4144;O164958@1449
quests	nearest	(H) Quest: Bloodpetal Zapper	Lv 53. Gather scattered Bloodpetal Sprouts for Larion.	Q4148;O164958@1449
quests	nearest	Quest: Dadanga is Hungry!	Lv 55. Gather Bloodpetal Sprouts and feed Dadanga at Marshal's Refuge.	Q5150;O164958@1449
quests	nearest	(A) Quest: Muigin and Larion	Lv 52. Gather Bloodpetal samples for Muigin.	Q4141;U6509,6510,6511,6512@1449
quests	nearest	(H) Quest: Larion and Muigin	Lv 52. Clear the four Bloodpetal types for Larion.	Q4145
quests	nearest	Quest: The Apes of Un'Goro	Lv 55. Collect gorilla, stomper and thunderer pelts in Fungal Rock.	Q4289;U6513,6514,6516@1449
quests	order	Chain: The Apes of Un'Goro	Lv 55. Collect the three ape pelts, then find U'cha deep in Fungal Rock.	Q4289;U6513,6514,6516@1449;Q4301;U9622@1449
quests	order	Chain: The Bait for Lar'korwi	Lv 53-56. Approach egg nests to provoke mates; use the supplied meat and scent to summon Lar'korwi.	Q4290;O169216@1449;Q4291;U9683@1449;Q4292;O169217@1449;U9684@1449
quests	nearest	Quest: Beware of Pterrordax	Lv 55. Hunt both Pterrordax types; turn in at Spraggle Frock.	Q4501
quests	nearest	Quest: Shizzle's Flyer	Lv 51. Gather diemetradon and pterrordax scales for Shizzle.	Q4503;U9162,9163,9164,9165,9166,9167@1449
quests	nearest	Quest: Finding the Source	Lv 55. Test the hot spots on Fire Plume Ridge with Krakle's thermometer.	Q974;O148503@1449
quests	order	Chain: Chasing A-Me 01	Lv 53. Bring a Mithril Casing before rescuing A-Me 01; clear nearby gorillas before the escort.	Q4243;Q4244;U6513,6514,6516@1449;Q4245
quests	order	Chain: A Little Help From My Friends	Lv 55. Clear ridge elementals; use Spraggle's Canteen whenever Ringo faints.	Q4492;U6520,6521@1449;Q4491
quests	order	Chain: Linken's Lost Pack	Lv 52. Inspect the wrecked raft and small pack, then take its contents to Linken.	Q3844;Q3845
quests	order	Chain: Linken's Adventure Tour	Lv 52-56. Kalimdor tour: Un'Goro, Winterspring, Feralas, Tanaris and Felwood; finish with Blazerunner.	Q3844;Q3845;Q3908;Q3909;N7775;N9467;O164729@1444;Q3912;Q3913;Q3914;Q3941;Q3942;Q4084;U7138,7139,8956,8957,8958,8959,8960,8961@1448;Q4005;O148507@1446;Q3961;Q3962;U9376@1449
quests	nearest	(H) Quest: Un'Goro Soil Tour	Lv 50. Collection tour: gather dirt piles in Un'Goro; finish with Ghede in Thunder Bluff.	Q3761;O157936@1449
quests	nearest	(A) Quest: Un'Goro Soil Tour	Lv 50. Collection tour: gather dirt piles in Un'Goro; finish with Jenal in Darnassus.	Q3764;O157936@1449
quests	nearest	Quest: Water Pouch Bounty	Lv 44. Wastewander humanoids drop the water pouches; deliver them in Gadgetzan.	Q1707;U5615,5616,5617,5618,5623@1446
quests	order	Chain: Wastewander Justice	Lv 43-44. Clear thieves and bandits first, then rogues, shadow mages and assassins.	Q1690;Q1691
quests	nearest	Quest: Gahz'ridian	Lv 48. Wear the supplied detector helmet while searching the ruins for Gahz'ridian.	Q3161;O140971@1446
quests	order	Chain: The Scrimshank Redemption	Lv 48. Find the surveying gear underground, then take the analysis between the Gadgetzan researchers.	Q10;O144053@1446;Q110;Q113
quests	nearest	Quest: Noxious Lair Investigation	Lv 47. Collect insect parts in the Noxious Lair; deliver them to Alchemist Pestlezugg.	Q82;U5455,5456,5457,5458,5459,5460@1446
quests	nearest	Quest: Gadgetzan Water Survey	Lv 46. Use the dowsing widget at the Sandsorrow Watch water hole.	Q992;O174796@1446;U5645,5646@1446
quests	nearest	Quest: The Dunemaul Compound	Lv 49. Clear enforcers and brutes; find Gor'marok inside the compound cave.	Q5863
quests	nearest	Quest: Thistleshrub Valley	Lv 50. Clear rootshapers and gnarled thistleshrubs in the southwest valley.	Q3362
quests	nearest	Quest: Caliph Scorpidsting	Lv 46. Read the wanted poster and search Wastewander camps for Caliph.	Q2781;U7847,5615,5617,5623@1446
quests	nearest	Quest: Andre Firebeard	Lv 45. Read the poster; clear Firebeard's pirate camp before looting his head.	Q2875;U7883,7855,7856,7857@1446
quests	nearest	Quest: Stoley's Shipment	Lv 45. Recover the stolen cargo from the pirate compound for Stoley.	Q2873;O142181@1446;U7855,7856@1446
quests	nearest	Quest: Ship Schedules	Lv 45. Loot footlockers dropped by pirates in Lost Rigger Cove; take the schedules to Security Chief Bilgewhizzle.	Q2876;U7855,7856,7857,7858@1446
quests	order	Chain: Noggenfogger Elixir Tour	Lv 49. Collection tour: thistleshrub dew in Tanaris, violet tragans in the Hinterlands, then return to Gadgetzan.	Q2605;U5481@1446;Q2606;Q2641;O141853@1425;Q2661;Q2662
quests	nearest	Quest: Clamlette Surprise	Lv 45. Cooking quest: hunt rocs for eggs and gather clam meat; buy the cheese before turning in.	Q6610;U5428,5429,5430@1446;U5431@1446
quests	nearest	Quest: Deadly Desert Venom	Lv 55. Collect scorpid and spider venoms for Beetix at Cenarion Hold.	Q8277;U11735,11738@1451
quests	nearest	Quest: Noggle's Last Hope	Lv 57. Collect the three stronger venom types; return to Beetix.	Q8278;U11736,11737,11739@1451
quests	nearest	Quest: The Twilight Mystery	Lv 58. Gather scattered Twilight Tablet Fragments before returning to Geologist Larksbane.	Q8284;O180436,180501,180583@1451
quests	order	Chain: The Twilight Lexicon	Lv 59-60. Speak to Ortell, collect the three lexicon chapters, then report to Commander Mar'alith.	Q8285;Q8279;U11803,11804,15200@1451;Q8287
quests	nearest	Quest: True Believers	Lv 59. Collect Encrypted Twilight Texts from cultists for Hermit Ortell.	Q8323;U11880,11881,11882,11883@1451
quests	nearest	Quest: Secret Communication	Lv 60. Collect Encrypted Twilight Texts from the camps for Bor Wildmane.	Q8318;U11880,11881,11882,11883@1451
quests	order	Chain: Securing the Supply Lines	Lv 55-57. Clear dredge strikers first and dredge crushers next.	Q8280;Q8281
quests	order	Chain: Desert Recipe	Lv 57. Read the Sandy Cookbook, bring it back, then collect sandworm meat for Kitchen Assistance.	Q8307;Q8313;Q8317;U11740,11741@1451
quests	nearest	Quest: Glyph Chasing	Lv 60. Collect glyphed crystals from all three silithid hives; prepare for dangerous tunnels.	Q8309;O180454,180455@1451;U11734@1451
quests	nearest	Quest: Breaking the Code	Lv 60. Collect silithid brain types in Hive'Ashi, Hive'Zora and Hive'Regal.	Q8310;U11721,11722,11723,11725,11726,11728,11730,11731,11732@1451
quests	nearest	Quest: Twilight Geolords	Lv 60. Hunt Twilight Geolords at the cultist camps.	Q8320
quests	nearest	Quest: Into The Maw of Madness	Lv 60. Find the expedition leader inside Hive'Regal; bring help for the hive lord.	Q8306;U11730,11731,11732,11733,11734@1451
quests	nearest	Quest: The Spirits of Southwind	Lv 55. Clear tortured druids and sentinels in Southwind Village.	Q1125
quests	nearest	(H) Quest: Mankrik's Wife & Revenge	Lv 20. Inspect the Beaten Corpse; the route also covers Mankrik's quilboar tusk collection.	Q4921;Q899;U3258,3260,3261,3263@1413
quests	order	(H) Chain: Kolkar Leaders	Lv 16-19. Hunt Barak, Verog and Hezrul in order; Verog appears after centaur kills near the oasis.	Q850;U3394@1413;Q851;U3272,3273,3395@1413;Q852;U3396@1413
quests	nearest	(H) Quest: Centaur Bracers	Lv 14. Collect centaur bracers around the northern oases for Regthar Deathgate.	Q855;U3272,3273@1413
quests	nearest	Quest: Raptor Horns	Lv 18. Hunt Sunscale Scytheclaws for intact horns; deliver them to Mebok in Ratchet.	Q865;U3256@1413
quests	nearest	(H) Quest: Egg Hunt	Lv 22. Search silithid mounds for eggs; return to Korran at the Crossroads.	Q868;O3685@1413
quests	nearest	(H) Quest: Fungal Spores	Lv 15. Pick Laden Mushrooms beside oasis water; return the spores to Helbrim.	Q848;O3640@1413
quests	nearest	(H) Quest: The Angry Scytheclaws	Lv 17. Loot a Sunscale feather, then use it at all three colored raptor nests.	Q905;U3254,3255,3256@1413
quests	order	Chain: Samophlange	Lv 14-16. Use all three valves, obtain the console key, then return to Sputtervalve.	Q894;Q900;Q901;U3471@1413;Q902
quests	nearest	(H) Quest: Nugget Slugs	Lv 15. Search Tool Buckets around the Sludge Fen for nugget slugs.	Q3922;O161752@1413
quests	order	(H) Chain: Witchwing Harpies	Lv 15-20. Gather talons and lieutenant rings, then confront Serena Bloodfeather.	Q867;U3276,3277@1413;Q875;U3278,3279,3280@1413;Q876;U3452@1413
quests	order	(H) Chain: Razormane Attacks	Lv 12-15. Clear the first Razormane camp, then defenders and geomancers; loot Kreenig's tusk.	Q871;Q872
quests	order	(H) Chain: Sergra's First Hunts	Lv 12-17. Collect beaks, hooves and claws; use Sergra's horn at Echeyakee's lair, then mark the three raptor nests.	Q844;U3244@1413;Q845;U3242@1413;Q903;U3425@1413;Q881;O164651@1413;U3475@1413;Q905
quests	order	Chain: Southsea Freebooters	Lv 14-16. Clear the pirates, check with Dizzywig, then recover Gazlowe's stolen supplies.	Q887;Q890;Q892;Q888;O3768,4166@1413
quests	nearest	Quest: Baron Longshore	Lv 16. Read the Ratchet wanted poster; search the pirate camps for Baron Longshore.	Q895;U3467@1413
quests	nearest	(H) Quest: The Guns of Northwatch	Lv 20. Collect Theramore medals and defeat the three named officers at Northwatch Hold.	Q891
quests	nearest	(H) Quest: Dig Rat Stew	Lv 23. Hunt Dig Rats inside Bael Modan; return to Grub.	Q862;U3444@1413
quests	nearest	(H) Quest: Consumed by Hatred	Lv 20. Collect quilboar tusks for Mankrik at the Crossroads.	Q899;U3258,3260,3261,3263@1413
quests	order	(H) Chain: Gann's Reclamation	Lv 23-26. Clear the Bael'dun dig, collect demolition materials, then destroy the flying machine.	Q843;Q846;U3376,3377,3378@1413;Q849
quests	nearest	(H) Quest: Raptor Thieves	Lv 13. Collect raptor heads for Gazrog at the Crossroads.	Q869;U3254,3255,3256@1413
quests	nearest	(H) Quest: Stolen Silver	Lv 18. Recover the silver from the raptor den; return to Gazrog.	Q3281;O147557@1413;U3254,3255,3256@1413
quests	nearest	Quest: Miner's Fortune	Lv 18. Hunt Venture Co. workers around the mine for a cats-eye emerald.	Q896;U3282,3283@1413
quests	order	Chain: Wizzlecrank's Escape	Lv 18. Recover the ignition key from the Venture Co. camp; clear the escape path before starting.	Q858;U3283,3286@1413;Q863
quests	order	Quest: Wailing Caverns Pickup Tour	Lv 17-21. Pickup tour: collect the cave and Ratchet quests before entering Wailing Caverns.	Q1486;Q1487;Q959
quests	nearest	(H) Quest: Serpentbloom Pickup Tour	Lv 18. Collection tour: pick Serpentbloom in the Wailing Caverns entrance caves; turn in to Zamah in Thunder Bluff.	Q962;O13891,19535@1413
quests	nearest	Quest: Bone Collector	Lv 39. Collect Kodo Bones at the graveyard; be ready for hostile scavengers.	Q5501;O176751,176752@1443
quests	nearest	Quest: Kodo Roundup	Lv 34. Use the Kodo Kombobulator on aged, dying and ancient kodos; lead each back to Smeed.	Q5561;U4700,4701,4702@1443
quests	nearest	(H) Quest: Fish in a Bucket	Lv 25. Loot shellfish traps underwater off Shadowprey; return to Jinar'Zillen.	Q5421;O176582,176592,176635@1443
quests	nearest	Quest: Broken Tears	Lv 33. Search the Tears of Theradras for broken tears; return to Warug.	Q1369;O22246@1443
quests	nearest	Quest: Stealing Supplies	Lv 35. Collect centaur supply sacks in Magram territory; return to Uthek.	Q1370;O22245@1443
quests	nearest	Quest: Claim Rackmore's Treasure!	Lv 36. Read Rackmore's Log; collect both keys from naga and crawlers before opening the chest.	Q6161;U4711,4712,4713,11562,11563@1443
quests	nearest	Quest: Ghost-o-plasm Round Up	Lv 39. Clear undead guards, use the ghost magnet between the southern valley's skeletons, then loot ghost residue.	Q6134;O177748@1443;U11561,11559@1443
quests	order	(A) Chain: Vahlarriel's Search	Lv 33. Find the Malem Chest, return to Vahlarriel, then rescue Dalinda and recover Tyranis' pendant.	Q1437;Q1465;Q1438;Q1439;U5643@1443;Q1440
quests	order	(A) Chain: The Karnitol Shipwreck	Lv 39. Inspect the submerged chest, report back, then hunt Slitherblade for Karnitol's satchel.	Q1454;Q1455;Q1456;U4716,4719@1443
quests	nearest	(H) Quest: Clam Bait	Lv 35. Gather giant softshell clams along the coast; turn in the clam bait at Shadowprey.	Q6142;O177784@1443
quests	nearest	(A) Quest: Down the Scarlet Path	Lv 39. Hunt undead ravagers at the Valley of Bones for Brother Anton.	Q261;U11561@1443
quests	nearest	(A) Quest: The Mark of Quality	Lv 46. Gather thick yeti hides in Feral Scar Vale; return to Pratt at Feathermoon.	Q2821;U5292@1444
quests	nearest	(H) Quest: The Mark of Quality	Lv 46. Gather thick yeti hides in Feral Scar Vale; return to Jangdor at Camp Mojache.	Q2822;U5292@1444
quests	nearest	(H) Quest: Gordunni Cobalt	Lv 43. Use Orwin's shovel at blue glows around Gordunni Outpost to recover cobalt.	Q2987;O144050@1444
quests	order	(H) Chain: Woodpaw Investigation	Lv 42-43. Collect Woodpaw manes, defeat alphas, then inspect the battle map and report to Hadoken.	Q2862;U5251,5253,5254@1444;Q2863;Q2902;Q2903
quests	order	(A) Chain: Against the Hatecrest	Lv 43-45. Inspect Solarsal, collect naga scales, defeat Lord Shalzaru, then deliver the relic.	Q2866;Q2867;Q3130;Q2869;U5331,5332,5333,5334,5335,5336,5337@1444;Q2870;U8136@1444;Q2871
quests	order	(A) Chain: The Stave of Equinex	Lv 50. Search the Ravenwind ruins for the four essences; activate the monolith and return to Troyas.	Q2879;O142185,142186,142187,142188@1444;Q2942
quests	order	(A) Chain: The Missing Courier	Lv 43-46. Follow the boat wreckage, Woodpaw backpacks and Zukk'ash pod; wait for the escort to complete.	Q4124;Q4125;Q4127;Q4129;Q4130;Q4131;Q4135;Q4265;Q4266
quests	nearest	(H) Quest: A New Cloak's Sheen	Lv 45. Collect iridescent sprite darter wings for Krueg at Camp Mojache.	Q2973;U5278@1444
quests	nearest	(H) Quest: Natural Materials	Lv 50. Gather natural materials from hippogryphs, faerie dragons, treants and giants for Uzer'i.	Q3128;U5300,5304,5305,5306,5276,5278,7584,5358,5359@1444
quests	nearest	Quest: Zapped Giants	Lv 48. Use Zorbin's shrinker on coastal giants before looting the residue.	Q7003;U5358,5359@1444
quests	nearest	(A) Quest: Doling Justice	Lv 47. Clear the Grimtotem camp for Jer'kai Moonweaver.	Q2970
quests	nearest	Quest: Corrupted Songflowers	Lv 55. Bring Cenarion Plant Salve; cleanse a corrupted flower before collecting its buff.	Q2523;Q2878;Q3363;Q4113;Q4114;Q4116;Q4118;Q4401;Q4464;Q4465;O171942,174594,174595,164886,174596,174597,174598,171939,174712,174713@1448
quests	nearest	Quest: Corrupted Windblossoms	Lv 55. Bring Cenarion Plant Salve to cleanse the scattered windblossoms.	Q996;Q998;Q1514;Q4115;Q4221;Q4222;Q4343;Q4403;Q4466;Q4467;O174600,174599,173327,164887,174604,174603,174602,174601,174708,174709@1448
quests	nearest	Quest: Corrupted Whipper Roots	Lv 55. Bring Cenarion Plant Salve and gather the cleansed roots.	Q4117;Q4443;Q4444;Q4445;Q4446;Q4461;O164888,173284,174605,174606,174607,174686@1448
quests	nearest	Quest: Corrupted Night Dragons	Lv 55. Bring Cenarion Plant Salve to cleanse each plant and gather its breath.	Q4119;Q4447;Q4448;Q4462;O164885,173324,174608,174684@1448
quests	nearest	(A) Quest: Cleansing Felwood	Lv 55. Gather tainted vitriol from Warpwood elementals; unlock Arathandris' plant salve quests.	Q4101;U7100,7101@1448
quests	nearest	(H) Quest: Cleansing Felwood	Lv 55. Gather tainted vitriol from Warpwood elementals; unlock Maybess' plant salve quests.	Q4102;U7100,7101@1448
quests	nearest	(A) Quest: Salve via Hunting	Lv 55. With the Cenarion Beacon, hunt Felwood beasts for salve materials; return to Arathandris.	Q4103;U8956,8957,8958,8959,8960,8961@1448
quests	nearest	(H) Quest: Salve via Hunting	Lv 55. With the Cenarion Beacon, hunt Felwood beasts for salve materials; return to Maybess.	Q4108;U8956,8957,8958,8959,8960,8961@1448
quests	order	Chain: Timbermaw Ally	Lv 48-55. Clear southern Deadwood, speak to Nafien, then clear the northern village; avoid attacking Timbermaw.	Q8460;Q8462;Q8461
quests	nearest	Quest: Feathers for Grazle	Lv 55. Collect Deadwood Headdress Feathers in the south; turn in to Grazle for Timbermaw reputation.	Q8466;U7153,7154,7155@1448
quests	nearest	Quest: Feathers for Nafien	Lv 55. Collect Deadwood Headdress Feathers in the north; turn in to Nafien for Timbermaw reputation.	Q8467;U7156,7157,7158@1448
quests	nearest	Quest: Forces of Jaedenar	Lv 51. Clear Jaedenar cultists, guardians, adepts and hounds for Greta Mosshoof.	Q5155
quests	nearest	Quest: Dousing the Flames of Protection	Lv 55. Douse all four braziers in Shadow Hold; bring help for crowded rooms.	Q5165
quests	nearest	Quest: Verifying the Corruption	Lv 54. Hunt entropic beasts and horrors in the Irontree area for Taronn Redfeather.	Q5156
quests	nearest	Quest: Silver Heart	Lv 54. Collect silvery claws from bears and wolves and an ironwood heart from Irontree treants.	Q4084;U7138,7139,8956,8957,8958,8959,8960,8961@1448
quests	order	Chain: Rescue From Jaedenar	Lv 55-57. Use the strange red key to free Arko'narin; escort her before pursuing Trey's remains.	Q5202;Q5203;Q5204;Q5385
quests	order	Chain: Are We There, Yeti?	Lv 56-58. Collect yeti fur first, then pristine horns; return to Umi after each step.	Q3783;U7457,7458@1452;Q977;U7459,7460@1452
quests	nearest	Quest: Luck Be With You	Lv 60. Gather Frostmaul Shards in the southern giant area; avoid the elite patrols.	Q969;O175324@1452
quests	nearest	Quest: Chillwind Horns	Lv 54. Collect chillwind horns for Felnok Steelspring at Everlook.	Q4809;U7447,7448,7449@1452
quests	nearest	Quest: Beads for Salfa	Lv 56. Collect Winterfall Spirit Beads; turn in to Salfa for Timbermaw reputation.	Q8469;U7438,7439,7440,7441,7442@1452
quests	nearest	Quest: Winterfall Activity	Lv 58. Clear Winterfall ursa, shamans and den watchers for Salfa.	Q8464
quests	nearest	Quest: Threat of the Winterfall	Lv 56. Clear den watchers, totemics and pathfinders near Timbermaw Post for Donova.	Q5082
quests	order	Chain: High Chief Winterfall Tour	Lv 57-59. Hunt runners and defeat the chief in Winterspring, then deliver the findings to Kelek in Felwood.	Q5087;U10916@1452;Q5121;Q5123;Q5128
quests	nearest	(A) Quest: Frostsaber Provisions	Lv 60. Collect shardtooth meat and chillwind meat for Rivern at Frostsaber Rock.	Q4970;U7443,7444,7445,7446,7447,7448,7449@1452
quests	nearest	(A) Quest: Winterfall Intrusion	Lv 60. Clear Winterfall ursa and shamans for Rivern Frostwind.	Q5201
quests	nearest	(A) Quest: Rampaging Giants	Lv 60. Defeat frostmaul giants and preservers; bring a group for the elite enemies.	Q5981
quests	nearest	Quest: Kel'Theril Relics Tour	Lv 56. Recover all four Highborne Relic Fragments around Kel'Theril; this tour ends with Aurora in EPL.	Q5245;O175888,175891,175892,175893@1452
quests	nearest	Quest: Frostsaber E'ko	Lv 60. Carry Mau'ari's Cache while hunting; return to Mau'ari in Everlook for the E'ko exchange.	Q4801;U7430,7431,7432,7433,7434@1452
quests	nearest	Quest: Winterfall E'ko	Lv 60. Carry Mau'ari's Cache while hunting; return to Mau'ari in Everlook for the E'ko exchange.	Q4802;U7438,7439,7440,7441,7442@1452
quests	nearest	Quest: Shardtooth E'ko	Lv 60. Carry Mau'ari's Cache while hunting; return to Mau'ari in Everlook for the E'ko exchange.	Q4803;U7443,7444,7445,7446@1452
quests	nearest	Quest: Chillwind E'ko	Lv 60. Carry Mau'ari's Cache while hunting; return to Mau'ari in Everlook for the E'ko exchange.	Q4804;U7447,7448,7449@1452
quests	nearest	Quest: Ice Thistle E'ko	Lv 60. Carry Mau'ari's Cache while hunting; return to Mau'ari in Everlook for the E'ko exchange.	Q4805;U7457,7458,7459,7460@1452
quests	nearest	Quest: Frostmaul E'ko	Lv 60. Carry Mau'ari's Cache while hunting; return to Mau'ari in Everlook for the E'ko exchange.	Q4806;U7428,7429@1452
quests	nearest	Quest: Wildkin E'ko	Lv 60. Carry Mau'ari's Cache while hunting; return to Mau'ari in Everlook for the E'ko exchange.	Q4807;U7450,7451,7452,7453,7454@1452
quests	nearest	(H) Quest: Galgar's Cactus Apple Surprise	Lv 3. Pick Cactus Apples around the Valley of Trials; return to Galgar.	Q4402;O171938@1411
quests	nearest	(H) Quest: Break a Few Eggs	Lv 8. Gather Taillasher Eggs on the Echo Isles; return to Cook Torka.	Q815;O3240@1411
quests	nearest	(H) Quest: Winds in the Desert	Lv 9. Recover stolen supply sacks from the harpy canyon for Rezlak.	Q834;O3290@1411
quests	nearest	(H) Quest: Thwarting Kolkar Aggression	Lv 8. Burn all three Kolkar attack plans in the ravine.	Q786
quests	nearest	(H) Quest: From The Wreckage....	Lv 8. Recover Gnomish Tools among the shipwrecks off the east coast.	Q825;P1411:61,42,Northern wreck tools;P1411:62,46,Central wreck tools;P1411:62,56,Southern wreck tools
quests	nearest	(H) Quest: A Solvent Spirit	Lv 7. Collect crawler mucus and makrura eyes along the shore.	Q818;U3103,3104,3106,3107@1411
quests	nearest	(H) Quest: Lazy Peons	Lv 4. Use the foreman's blackjack on sleeping peons around the Valley of Trials.	Q5441
quests	order	(H) Chain: Dark Storms & Skull Rock	Lv 12. Defeat Fizzle, consult Margoz, then collect searing collars in Skull Rock.	Q806;U3203@1411;Q828;Q827;U3197,3198,3199,3204@1411
quests	order	(H) Chain: Call of Earth: Durotar	Lv 4. Shaman: collect felstalker hooves, drink Earth Sapta at the shrine, then return for your totem.	Q1516;U3102@1411;Q1517;Q1518
quests	order	(H) Chain: Durotar Hunter Taming	Lv 10. Hunter: tame the boar, surf crawler and armored scorpid in order; return to Thotar after each.	Q6062;U3099@1411;Q6083;U3107@1411;Q6082;U3126@1411
quests	order	(H) Chain: Garments of Spirituality	Lv 5. Troll priest, level 5: heal and fortify Grunt Kor'ja; return to Tai'jin.	Q5649;Q5648
quests	nearest	(H) Quest: Ju-Ju Heaps	Lv 10. Mage: gather Ju-Ju Heaps on the Echo Isles for Un'Thuwa.	Q1884
quests	order	(H) Chain: The Narache Hunts	Lv 2-4. Collect plainstrider meat and feathers, cougar pelts, then battleboar snouts and flanks.	Q747;U2955@1412;Q750;U2961@1412;Q780;U2966@1412
quests	nearest	(H) Quest: Dangers of the Windfury	Lv 8. Gather Windfury talons from harpies northeast of Bloodhoof Village.	Q743;U2962,2963@1412
quests	nearest	(H) Quest: Poison Water	Lv 5. Collect wolf paws and plainstrider talons for Mull Thunderhorn.	Q748;U2958,2956@1412
quests	nearest	(H) Quest: Thunderhorn Totem	Lv 7. Collect cougar claws and prairie wolf alpha teeth for Mull Thunderhorn.	Q756;U3035,2960@1412
quests	nearest	(H) Quest: Wildmane Totem	Lv 10. Collect prairie alpha teeth for Mull's final cleansing totem.	Q759;U2960@1412
quests	order	(H) Chain: The Ravaged Caravan	Lv 8-12. Inspect the sealed crate, return to Morin, then clear the Venture Co. mine and defeat Fizsprocket.	Q749;Q751;Q764;Q765;U3051@1412
quests	order	(H) Chain: Rite of Vision	Lv 6-7. Collect ambercorns and well stones, then follow Zarlman's instructions to Seer Wiserunner.	Q767;Q771;O2910,2912@1412;Q772
quests	order	(H) Chain: Call of Earth: Mulgore	Lv 4. Shaman: collect ritual salves, visit the earth spirit, then return to Seer Ravenfeather.	Q1519;U2952,2953@1412;Q1520;Q1521
quests	order	(H) Chain: Mulgore Hunter Taming	Lv 10. Hunter: tame adult plainstrider, prairie stalker and swoop; return to Yaw after each.	Q6061;U2956@1412;Q6087;U2959@1412;Q6088;U2970@1412
quests	nearest	(A) Quest: The Relics of Wakening	Lv 9. Find all four relics inside the Ban'ethil Barrow Den.	Q483;O2739,2740,2741,2742@1438
quests	order	(A) Chain: Denalan's Timberlings	Lv 7. Collect timberling seeds and the sprouts scattered around Lake Al'Ameth.	Q918;U2022@1438;Q919;O4608@1438
quests	order	(A) Chain: Webwood Venom & Egg	Lv 4-5. Collect venom sacs first, then find the eggs at the back of the spider cave.	Q916;U1986@1438;Q917;O4406@1438
quests	nearest	(A) Quest: Seek Redemption!	Lv 7. Gather Fel Cones beneath trees and bring them to Zenn.	Q489;O1673@1438
quests	order	(A) Chain: Zenn's Bidding & Redemption	Lv 5-7. Gather owl feathers, spider silk and nightsaber fangs; then redeem yourself with Fel Cones.	Q488;U1995,1998,2032@1438;Q489;O1673@1438
quests	nearest	(A) Quest: The Emerald Dreamcatcher	Lv 6. Find Tallonkai's dreamcatcher in the Starbreeze village chest.	Q2438;O126158@1438;U2007,2008@1438
quests	order	(A) Chain: Crown of the Earth	Lv 5-11. Collect water from Shadowglen, Starbreeze, Arlithrien and Oracle Glade; report between samples.	Q921;O19549@1438;Q928;Q929;O19550@1438;Q933;O19551@1438;Q934;O19552@1438
quests	nearest	(A) Quest: The Enchanted Glade	Lv 11. Collect shimmering fronds from the harpies in the Oracle Glade.	Q937;U2015,2017,2018,2019,2020,2021@1438
quests	order	(A) Chain: Teldrassil Hunter Taming	Lv 10. Hunter: tame webwood lurker, nightsaber stalker and strigid screecher; return to Dazalar after each.	Q6063;U1998@1438;Q6101;U2043@1438;Q6102;U1996@1438
quests	order	(A) Chain: Garments of the Moon	Lv 5. Night elf priest, level 5: heal and fortify Sentinel Shaya; return to Laurna Morninglight.	Q5622;Q5621
quests	nearest	(A) Quest: Mathystra Relics	Lv 20. Collect relics scattered across the Mathystra ruins; return to Onu.	Q951;O12654,13360,13872@1439
quests	nearest	(A) Quest: Deep Ocean, Vast Sea	Lv 17. Recover both logbooks from the underwater wrecks; watch your breath.	Q982;O175166,175165@1439
quests	nearest	(A) Quest: The Fall of Ameth'Aran	Lv 12. Read both inscriptions in Ameth'Aran, then return to Sentinel Tysha.	Q953
quests	order	(A) Chain: Bashal'Aran	Lv 12-13. Collect grell earrings and the Highborne seal; use the seal at Ameth'Aran's ancient flame.	Q954;Q955;U2184,2190@1439;Q956;U2176,2177@1439;Q957
quests	order	(A) Chain: The Master's Glaive	Lv 17. Investigate the glaive, read the Twilight Tome, then report to Onu.	Q944;O12666@1439;Q949;Q950;U2336,2337@1439
quests	nearest	(A) Quest: Cave Mushrooms	Lv 17. Pick Death Caps and Scaber Stalks in the cave for Barithras.	Q947;O11713,11714@1439
quests	nearest	(A) Quest: Bathran's Hair	Lv 20. Search Plant Bundles at Bathran's Haunt for hair.	Q1010;O17282@1440
quests	nearest	(A) Quest: The Ruins of Stardust	Lv 23. Collect stardust from bushes in the Ruins of Stardust.	Q1034;O19016@1440
quests	nearest	(A) Quest: The Zoram Strand	Lv 19. Collect Wrathtail heads along the Zoram Strand.	Q1008;U3711,3712,3713,3715,3717@1440
quests	order	(A) Chain: Raene's Cleansing	Lv 19-30. Recover Teronis' gem and the rod pieces; visit the hidden shrine before confronting Ran Bloodtooth.	Q991;Q1023;U3944@1440;Q1024;Q1026;U3919@1440;Q1027;U3928@1440;Q1028;Q1055;Q1029;Q1030;Q1045;Q1046
quests	nearest	(H) Quest: Troll Charm	Lv 24. Collect troll charms from chests in Thistlefur Hold; return to Mitsuwa.	Q6462;O178144@1440
quests	nearest	(H) Quest: Satyr Horns	Lv 26. Collect satyr horns in the northern satyr camps for Pixel.	Q6441;U3752,3754,3755,3757,3758,3759@1440
quests	nearest	Quest: Rocket Car Parts	Lv 31. Collect Rocket Car Rubble around the Shimmering Flats; return to Kravel.	Q1110;O19868,19869,19870,19871,19872,19873@1441
quests	nearest	Quest: Salt Flat Venom	Lv 30. Collect venom from salt flat scorpids for Fizzle Brassbolts.	Q1104;U4139,4140@1441
quests	nearest	Quest: Hardened Shells	Lv 30. Collect hardened tortoise shells for Wizzle Brassbolts.	Q1105;U4144@1441
quests	nearest	Quest: Load Lightening	Lv 30. Collect hollow vulture bones for Pozzik.	Q1176;U4154,4158@1441
quests	nearest	Quest: Deepmoss Spider Eggs Tour	Lv 20. Collect Deepmoss Spider Eggs; this pickup tour starts and ends with Mebok in Ratchet.	Q1069;O19541@1442
quests	nearest	(A) Quest: A Gnome's Respite	Lv 21. Clear Venture Co. loggers and deforesters for Gaxim Rustfizzle.	Q1071
quests	nearest	(H) Quest: Harpies Threaten	Lv 26. Clear the Bloodfury harpies of the Charred Vale for Maggran Earthbinder.	Q6282
quests	order	(H) Chain: Cycle of Rebirth	Lv 23-25. Collect Gaea Seeds near Stonetalon Peak, then plant them in the Charred Vale.	Q6301;O177926@1442;Q6381
quests	order	(H) Chain: Forged Steel	Lv 10. Warrior: after Path of Defense, visit Thun'grim and recover the steel bars from the stolen iron chest.	Q1502;Q1503;O58369@1413
quests	nearest	Quest: Kroshius' Infernal Core	Lv 55. Warlock: use Fel Fire at Kroshius' remains, defeat the infernal and bring its core to Niby; unlocks Inferno.	Q7603;O179677@1448;U14467@1448
quests	nearest	(H) Quest: Mok'Morokk's Concern	Lv 43. Recover Mok'Morokk's snuff, grog and strongbox from the ruins around Stonemaul.	Q1166;O19904,19905,19906@1445
quests	order	(H) Chain: The Brood of Onyxia	Lv 43-45. Talk between Draz'Zilb and Mok'Morokk, then destroy Onyxia's eggs in the Wyrmbog.	Q1170;Q1171;Q1172
quests	order	(H) Chain: Onyxia Horde Attunement Tour	Lv 60. Lv55+ pickup tour: Thrall to Rexxar in Desolace, Myranda in Western Plaguelands, then Emberstrife in Dustwallow.	Q6566;Q6567;Q6568;Q6570
quests	nearest	(A) Library books: all 20	20 distinct books for quests 78150/79536; visit the final librarian after collecting. See notes for cave access.	O386691@1455;O386759@1429;O408014@1436;P1439:59.6,22.2,Nar'thalas Almanac;P1421:63.5,63.1,Dalaran Digest;P1436:45.4,70.5,Bewitchments and Glamours;P1413:46.0,36.5,Secrets book cave entrance;P1413:56.3,8.8,Arcanic Systems Manual;P1437:33.6,47.9,Goaz Scrolls;P1431:16.7,28.5,Crimes Against Anatomy;P1432:77.5,14.1,Runes of the Sorcerer-Kings;P1442:74.4,85.7,Fury of the Land;P1413:62.7,36.3,Baxtan destructive magics;P1441:34.0,40.0,Geomancy;P1416:48.5,57.6,Defensive Magics 101;P1417:73.6,65.2,A Web of Lies;P1443:55.1,26.2,Demons and You;P1434:41.5,50.8,Basilisks book;P1418:56.7,39.7,Mummies guide;P1445:57.0,21.0,RwlRwlRwlRwl;N211033
quests	nearest	(A) Library books: EK books	12 books from the 20-book selection; return to your librarian. Nearest mode does not pin the turn-in last.	O386691@1455;O386759@1429;O408014@1436;P1421:63.5,63.1,Dalaran Digest;P1436:45.4,70.5,Bewitchments and Glamours;P1437:33.6,47.9,Goaz Scrolls;P1431:16.7,28.5,Crimes Against Anatomy;P1432:77.5,14.1,Runes of the Sorcerer-Kings;P1416:48.5,57.6,Defensive Magics 101;P1417:73.6,65.2,A Web of Lies;P1434:41.5,50.8,Basilisks book;P1418:56.7,39.7,Mummies guide;N211033
quests	nearest	(A) Library books: Kalimdor books	8 books from the 20-book selection; return to your librarian. Nearest mode does not pin the turn-in last.	P1439:59.6,22.2,Nar'thalas Almanac;P1413:46.0,36.5,Secrets book cave entrance;P1413:56.3,8.8,Arcanic Systems Manual;P1442:74.4,85.7,Fury of the Land;P1413:62.7,36.3,Baxtan destructive magics;P1441:34.0,40.0,Geomancy;P1443:55.1,26.2,Demons and You;P1445:57.0,21.0,RwlRwlRwlRwl;N211033
quests	nearest	(A) Library books: first 10	10 distinct books toward Friend of the Library (78150); Rumi counts once. Return to the librarian for the necklace.	O386691@1455;O386759@1429;O408014@1436;P1439:59.6,22.2,Nar'thalas Almanac;P1421:63.5,63.1,Dalaran Digest;P1436:45.4,70.5,Bewitchments and Glamours;P1413:46.0,36.5,Secrets book cave entrance;P1413:56.3,8.8,Arcanic Systems Manual;P1437:33.6,47.9,Goaz Scrolls;P1442:74.4,85.7,Fury of the Land;N211033
quests	nearest	(H) Library books: all 20	20 distinct books for quests 78150/79536; visit the final librarian after collecting. See notes for cave access.	P1420:59.5,52.3,Apothecary primer;P1454:38.7,78.4,Lessons of Ta'zo;O408014@1436;P1439:59.6,22.2,Nar'thalas Almanac;P1421:63.5,63.1,Dalaran Digest;P1436:45.4,70.5,Bewitchments and Glamours;P1413:46.0,36.5,Secrets book cave entrance;P1413:56.3,8.8,Arcanic Systems Manual;P1437:33.6,47.9,Goaz Scrolls;P1431:16.7,28.5,Crimes Against Anatomy;P1432:77.5,14.1,Runes of the Sorcerer-Kings;P1442:74.4,85.7,Fury of the Land;P1413:62.7,36.3,Baxtan destructive magics;P1441:34.0,40.0,Geomancy;P1416:48.5,57.6,Defensive Magics 101;P1417:73.6,65.2,A Web of Lies;P1443:55.1,26.2,Demons and You;P1434:41.5,50.8,Basilisks book;P1418:56.7,39.7,Mummies guide;P1445:57.0,21.0,RwlRwlRwlRwl;N211022
quests	nearest	(H) Library books: EK books	11 books from the 20-book selection; return to your librarian. Nearest mode does not pin the turn-in last.	P1420:59.5,52.3,Apothecary primer;O408014@1436;P1421:63.5,63.1,Dalaran Digest;P1436:45.4,70.5,Bewitchments and Glamours;P1437:33.6,47.9,Goaz Scrolls;P1431:16.7,28.5,Crimes Against Anatomy;P1432:77.5,14.1,Runes of the Sorcerer-Kings;P1416:48.5,57.6,Defensive Magics 101;P1417:73.6,65.2,A Web of Lies;P1434:41.5,50.8,Basilisks book;P1418:56.7,39.7,Mummies guide;N211022
quests	nearest	(H) Library books: Kalimdor books	9 books from the 20-book selection; return to your librarian. Nearest mode does not pin the turn-in last.	P1454:38.7,78.4,Lessons of Ta'zo;P1439:59.6,22.2,Nar'thalas Almanac;P1413:46.0,36.5,Secrets book cave entrance;P1413:56.3,8.8,Arcanic Systems Manual;P1442:74.4,85.7,Fury of the Land;P1413:62.7,36.3,Baxtan destructive magics;P1441:34.0,40.0,Geomancy;P1443:55.1,26.2,Demons and You;P1445:57.0,21.0,RwlRwlRwlRwl;N211022
quests	nearest	(H) Library books: first 10	10 distinct books toward Friend of the Library (78150); Rumi counts once. Return to the librarian for the necklace.	P1420:59.5,52.3,Apothecary primer;P1454:38.7,78.4,Lessons of Ta'zo;O408014@1436;P1439:59.6,22.2,Nar'thalas Almanac;P1421:63.5,63.1,Dalaran Digest;P1436:45.4,70.5,Bewitchments and Glamours;P1413:46.0,36.5,Secrets book cave entrance;P1413:56.3,8.8,Arcanic Systems Manual;P1437:33.6,47.9,Goaz Scrolls;P1442:74.4,85.7,Fury of the Land;N211022
quests	nearest	Library books: Barrens trio	Three books; Secrets waypoint is the outer cave entrance. In the last cave room search right of the pool.	P1413:56.3,8.8,Arcanic Systems Manual;P1413:62.7,36.3,Baxtan destructive magics;P1413:46.0,36.5,Secrets book cave entrance
quests	order	(A) Cozy Sleeping Bag 14+: full tour	Follow the quest chain; click the satchel below the final Messenger Bag. Bring wood for optional Rekindle.	O415107@1436;O417072@1413;P1442:50.9,52.3,Sleeping bag uphill path;O424005@1442;O424012@1442;O424007@1432;P1424:87.3,49.6,Thoradin Wall cart climb;O406918@1417
quests	order	(H) Cozy Sleeping Bag 14+: full tour	Follow the quest chain; click the satchel below the final Messenger Bag. Bring wood for optional Rekindle.	O415106@1413;O417072@1436;P1442:50.9,52.3,Sleeping bag uphill path;O424005@1442;O424012@1442;O424007@1432;P1424:87.3,49.6,Thoradin Wall cart climb;O406918@1417
quests	nearest	(A) SoD Mage 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Living Flame and Regeneration sources.	N198;U476@1429;U1124,1397@1426;U589@1436;U1166@1432
quests	nearest	(H) SoD Mage 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Living Flame then Fenris Isle and Bethor.	N2124;U1535@1420;U1867@1421;U1939@1421;Q491;N1498
quests	nearest	(H) SoD Mage 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Skull Rock then Kolkar chests and puzzle.	N5884;U3198,3199@1411;O152608,152618@1413;P1413:45,80,Path of no steps
quests	order	SoD Mage 18-25: Zoram crystals	SoD legacy discovery; Forever rune rewards unconfirmed. Cast Arcane Explosion south to north.	P1440:13,24.8,South Arcane Shard;P1440:14,19.8,Middle Arcane Shard;P1440:13.5,15.8,North Arcane Shard
quests	nearest	(A) SoD Warrior 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Victory Rush and Furious Thunder sites.	N911;P1429:50.6,27.3,Victory Rush stash;N327;U706@1426;N391
quests	nearest	(A) SoD Warrior 2-12: Teldrassil	SoD legacy discovery; Forever rune rewards unconfirmed. Spiders for Victory Rush; heads for Devastate.	N3593;U1986@1438;U2042@1438;U1995@1438
quests	nearest	(H) SoD Warrior 2-12: Tirisfal	SoD legacy discovery; Forever rune rewards unconfirmed. Lost Stash then gnoll/bat/murloc heads.	N2119;P1420:27.6,59.3,Lost Stash cave entrance;U1674@1420;U1553@1420;U1543@1420
quests	order	(H) SoD Warrior 2-12: Durotar	SoD legacy discovery; Forever rune rewards unconfirmed. Hidden Cache then Sarkoth and head trophies.	N3153;P1411:40.7,65.0,Victory Rush cliff gap;P1411:43.2,69.6,Victory Rush Hidden Cache;N3281;U3119@1411;U3115@1411;U3111@1411
quests	nearest	(A) SoD Rogue 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Pickpocket Garrick; hunt Dark Iron spies.	N915;N103;U6123@1426;N6124;U215@1431
quests	nearest	(A) SoD Rogue 2-12: Teldrassil	SoD legacy discovery; Forever rune rewards unconfirmed. Melenas then Gnarlpine stash key and cache.	N3594;N2038;U2008@1438;P1438:37.9,82.5,Gnarlpine Stash
quests	nearest	(H) SoD Rogue 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Pickpocket Perrine; inspect SFK ledge.	N2122;U1506@1420;N1662;P1421:45.3,67.3,Saber Slash SFK ledge
quests	nearest	(H) SoD Rogue 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Burning Blade note and Cannoneer matchbox.	N3155;U3197@1411;U3382@1413;P1413:61.78,45.8,Blade Dance powder bucket
quests	nearest	(A) SoD Priest 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Penance then Shared Pain and Homunculi.	N375;U257@1429;U40@1429;U474@1429;N572
quests	nearest	(A) SoD Priest 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Melenas and the coastal Shadow Word Death orb.	N3595;N2038;P1438:33.6,35.6,Adventurers Remains;P1439:30.5,47.5,Shadow Word Death orb
quests	nearest	(H) SoD Priest 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Farmer and Scarlet drops; Fenris tower scroll.	N2123;U1934@1420;U1535@1420;N1947
quests	nearest	(H) SoD Priest 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Echo Isles then Desert Mirage; bring Dispel.	N3706;U3206,3207@1411;N3204;P1413:57.4,37.8,Shadow Word Death mirage
quests	nearest	(A) SoD Warlock 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Haunt and Chaos Bolt; bring fire help.	N459;P1429:50,51,Haunt vineyard chest;P1429:76,49,Frozen Murloc Chaos Bolt;U478@1429;U118@1429;U40@1429
quests	nearest	(H) SoD Warlock 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Haunt then Demonic Grace reagents.	N2126;U1674@1420;U1547@1420;U1520@1420;P1420:27.6,59.3,Haunt Lost Stash cave
quests	nearest	(H) SoD Warlock 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Frozen murloc and Lugwizzle soul ritual.	N3156;P1411:58,45,Frozen Murloc Chaos Bolt;U3206@1411;N3445;P1413:57,9,Hungry Idol
quests	nearest	(A) SoD Hunter 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Mark the bush; bait the Bear Den.	N895;P1426:29,49,Master Marksman bush;P1426:38,43,Flanking Strike Bear Den
quests	nearest	(A) SoD Hunter 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Mark bush; owl meat for Flanking Strike.	N3596;P1438:46,46,Master Marksman bush;U1995@1438;P1438:48,31,Flanking Strike Bear Den;N7318
quests	nearest	(H) SoD Hunter 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Bush and cat bait; Sarkoth Explosive Shot.	N3154;P1411:38,52,Master Marksman bush;P1411:69,71,Flanking Strike cat den;N3281;N210845
quests	order	SoD Hunter 20-25: Hillsbrad cobra	SoD legacy discovery; Forever rune rewards unconfirmed. Find Zixil on the road; use bait from the boat.	P1424:50.9,51.3,Zixil Southshore road stop;P1424:55,35.2,Zixil road tower stop;N3537;P1424:61,33,Cobra Strikes turtle lake
quests	nearest	(A) SoD Druid 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Moonfire stones; bring another healer for corpse.	U1988@1438;P1438:52,79,Sunfire Lunar Stones;P1438:67,58,Living Seed Wooden Effigy;P1438:33,35,Lifebloom corpse;N7318;N6788
quests	nearest	(H) SoD Druid 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Flowers for effigy; Moonfire three stones.	N3060;P1412:38,49,Living Seed Wooden Effigy;P1412:36,70,Sunfire Lunar Stones;P1412:60,33,Lifebloom corpse;P1413:44,22,Lacerate abandoned eggs;P1413:48,40,Lacerate oasis nest
quests	order	SoD Druid 20-25: EK owl tour	SoD legacy discovery; Forever rune rewards unconfirmed. Swim between Hillsbrad statues within 2 minutes.	P1431:50,35,Wild Growth owl statue;P1431:66,23,Wild Growth Agon;P1424:54,81,Wild Growth east owl;P1424:36,75,Wild Growth west owl
quests	nearest	(H) SoD Shaman 2-25: Kalimdor tour	SoD legacy discovery; Forever rune rewards unconfirmed. Fire for frozen makrura; corpse needs helper.	N3157;P1411:59,46,Lava Burst Frozen Makrura;P1411:48,80,Ancestral Guidance corpse;P1413:43,23,Earth Shock Kolkar chest;P1413:57,36,Way of Earth mirage
quests	nearest	(H) SoD Shaman 10-28: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Rot Totem and Grimson; Mudsnouts are 27-28.	N1972;U1773@1421;U2373@1424
quests	nearest	(A) SoD Paladin 2-25: EK tour	SoD legacy discovery; Forever rune rewards unconfirmed. Crusader Strike libram; Duskwood Exorcism drops.	N925;U38@1429;U706@1426;U215@1431;N6171
quests	order	(A) SoD Paladin 25+: Divine Storm tour	SoD legacy discovery; Forever rune rewards unconfirmed. Group for level 30+ tower mobs and demons.	P1439:56,26,Althalaxx tower orb;N3663;N5492;N5495;U435,4463@1433;N5495;U6071,6073,6115,11697@1440;P1440:89,77,Mannoroth weapons circle;O409315@1440;N3663
quests	order	(A) BFD 20-27: quest pickup tour	Collect BFD quests before entering; these are Forever dungeon quests, with faction-specific rewards.	N4984;N8997;N4786;N4784;N2786
quests	nearest	(H) BFD 22-27: Zoram quest prep	Damp Note from Tide Priestesses; collect Zoram quests before entering Blackfathom Deeps.	N12736;U4802@1440;U4803@1440
quests	order	(A) Gnomeregan 20-25: pickup tour	Pick up Techbot and Gnogaine chains before the run; complete Gnogaine outside then get the follow-up.	N7944;N6569;N7950;N1268
quests	order	(H) Gnomeregan 25+: teleporter tour	Accept Rig Wars before Chief Engineer Scooty; Scooty in Booty Bay supplies the Goblin Transponder.	N3412;N3413;N7853
quests	order	SoD Hunter 20-25: Kill Command prep	Legacy chain; bring Greater Magic Wand and WC crystal. Forever reward unconfirmed.	U3924,3925@1440;P1413:46.0,36.5,Secrets book cave entrance;N210845;Q78114;Q78121
quests	order	(H) SoD Shaman 20-25: Earth Shield prep	Legacy chain; Strange Water Globe starts it. Forever reward unconfirmed.	N12736;U4034,4035@1442;U4036,4037,4038@1442;U3917@1440;N12736;Q78537
quests	nearest	SoD Grizzby 20-30: Wetlands collection	Legacy: 24 Fish Oil plus 20 Dark Iron Ordinance; return to Grizzby. Forever unlock unconfirmed.	U1029@1437;U1051,1052,1053,1054@1437;N211653
quests	nearest	(A) Mage Comprehension: library tour	Forever Comprehension exists; take rare books to Garion. Check current trainer requirements after relogging.	O386759@1429;O386691@1455;N211033
quests	nearest	(H) Mage Comprehension: library tour	Forever Comprehension exists; take books to Owen. Check current trainer requirements after relogging.	P1420:59.5,52.3,Apothecary primer;P1454:38.7,78.4,Lessons of Ta'zo;P1421:63.5,63.1,Dalaran Digest;N211022
quests	nearest	(H) SoD Ashenvale: enemy camp tour	SoD event sites; Forever event activation unconfirmed. Follow your raid leader during an active battle.	P1440:29.0,28.5,Alliance Runestone camp;P1440:51.8,54.1,Alliance Glaive camp;P1440:72.5,73.0,Alliance Research camp;N212970
quests	nearest	(A) SoD Ashenvale: enemy camp tour	SoD event sites; Forever event activation unconfirmed. Follow your raid leader during an active battle.	P1440:21.5,37.4,Horde Shredder camp;P1440:54.9,55.1,Horde Catapult camp;P1440:69.4,63.1,Horde Lumber camp;N212969
quests	nearest	SoD Blood Moon: STV opt-out circuit	Legacy event services; Forever activation unconfirmed. Speak to one emissary to request protection.	P1434:39.4,5.4,North road emissary;P1434:15.2,15.6,Yojamba Isle Exhal;P1434:27.3,77.1,Booty Bay inn emissary
dungeons	nearest	Dungeon entrances: Eastern Kingdoms	Tour of all entrances. Blackrock floors need stairs; BWL uses Spire approach then right hall. Stockade is in Alliance territory.	P1436:38.31,77.52,Deadmines;P1421:44.82,67.85,Shadowfang Keep;P1453:40.6,56.8,The Stockade;P1426:17.76,39.18,Gnomeregan;P1426:21.23,29.88,Gnomeregan: Workshop;P1420:84.87,30.61,Scarlet Monastery: Graveyard;P1420:85.29,32.14,Scarlet Monastery: Library;P1420:85.62,31.59,Scarlet Monastery: Armory;P1420:85.35,30.62,Scarlet Monastery: Cathedral;P1418:35.19,10.65,Uldaman;P1418:67.78,44.07,Uldaman: Back entrance;P1435:77.27,36.34,Sunken Temple;P1428:22.38,7.54,Blackrock Depths;P1428:32.83,25.28,Lower Blackrock Spire;P1428:32.83,25.28,Upper Blackrock Spire;P1423:26.5,10.4,Stratholme;P1423:41.9,15.8,Stratholme: Service gate;P1422:69.06,73.0,Scholomance;P1428:26.43,24.37,Molten Core;P1428:32.83,25.28,Blackwing Lair;P1434:53.74,17.57,Zul'Gurub;P1423:33.7,20.7,Naxxramas
dungeons	nearest	Dungeon entrances: Kalimdor	All wings and raids. AQ markers lead to the gate paths; follow left for AQ20 or right for AQ40. Ragefire is in Horde territory.	P1454:52.8,49.6,Ragefire Chasm;P1413:47.74,34.82,Wailing Caverns;P1440:16.55,11.06,Blackfathom Deeps;P1413:42.31,89.93,Razorfen Kraul;P1413:50.82,92.81,Razorfen Downs;P1446:38.72,20.01,Zul'Farrak;P1443:30.16,54.53,Maraudon: Purple;P1443:36.01,64.05,Maraudon: Orange;P1444:64.85,29.61,Dire Maul: East;P1444:60.32,29.81,Dire Maul: West;P1444:62.79,24.91,Dire Maul: North;P1445:52.94,77.63,Onyxia's Lair;P1451:29,92.8,Ruins of Ahn'Qiraj;P1451:27,93,Temple of Ahn'Qiraj
dungeons	order	(H) Wailing Caverns: Crossroads approach	Enter the cave; turn right then left through shallow water and follow the winding tunnel down. Pack a group for elites.	N3615;P1413:46,36.4,Wailing Caverns cave;P1413:47.74,34.82,Wailing Caverns
dungeons	order	Wailing Caverns: Ratchet approach	Walk west from Ratchet to the cave. Inside turn right then left through water; descend the tunnel to the portal.	N16227;P1413:46,36.4,Wailing Caverns cave;P1413:47.74,34.82,Wailing Caverns
dungeons	order	(A) Maraudon: purple approach	From the flight master reach the stone doors; follow the purple crystals through the outer caverns. No scepter needed.	N6706;P1443:29.1,62.5,Maraudon stone doors;P1443:30.16,54.53,Maraudon: Purple
dungeons	order	(A) Maraudon: orange approach	From the flight master reach the stone doors; follow the orange crystals through the outer caverns. No scepter needed.	N6706;P1443:29.1,62.5,Maraudon stone doors;P1443:36.01,64.05,Maraudon: Orange
dungeons	order	(H) Maraudon: purple approach	From the flight master reach the stone doors; follow the purple crystals through the outer caverns. No scepter needed.	N6726;P1443:29.1,62.5,Maraudon stone doors;P1443:30.16,54.53,Maraudon: Purple
dungeons	order	(H) Maraudon: orange approach	From the flight master reach the stone doors; follow the orange crystals through the outer caverns. No scepter needed.	N6726;P1443:29.1,62.5,Maraudon stone doors;P1443:36.01,64.05,Maraudon: Orange
dungeons	order	(H) Sunken Temple: Stonard approach	Swim into the flooded temple hall; surface and follow the inner stairs down to the portal. Arrow cannot show floors.	N6026;P1435:69.9,53.6,Temple of Atal Hakkar;P1435:77.27,36.34,Sunken Temple
dungeons	order	(A) Dire Maul: east approach	Follow the road to the southern compound entry; through Eldreth Row turn right for East. Alliance cross from Feathermoon.	N8019;P1444:59,45,Dire Maul southern entry;P1444:64.85,29.61,Dire Maul: East
dungeons	order	(H) Dire Maul: east approach	Follow the road to the southern compound entry; through Eldreth Row turn right for East. Alliance cross from Feathermoon.	N8020;P1444:59,45,Dire Maul southern entry;P1444:64.85,29.61,Dire Maul: East
dungeons	order	Dire Maul: west and north doors	Walk into Eldreth Row from the south. West and North require Crescent Key; the arena is a PvP area.	P1444:59,45,Dire Maul southern entry;P1444:60.32,29.81,Dire Maul: West;P1444:62.79,24.91,Dire Maul: North
dungeons	order	(A) Scholomance: Chillwind approach	Ride east to Caer Darrow; cross its bridge and enter the keep beside Eva. Skeleton Key or lockpicking opens the gate.	N12596;N11216;P1422:69.06,73.0,Scholomance
dungeons	order	(A) Blackrock Mountain: Depths approach	From Thorium Point enter the north gate; descend the chains to the central tomb and quarry tunnel. Lothos is by the route.	N2941;P1427:34.8,85.3,Blackrock north gate;N14387;P1428:22.38,7.54,Blackrock Depths
dungeons	order	(A) Blackrock Mountain: Spire approach	From Thorium Point enter the north gate; ascend the outer ramp and chain to Spire. Inside left is LBRS; UBRS needs Seal.	N2941;P1427:34.8,85.3,Blackrock north gate;P1428:32.83,25.28,Lower Blackrock Spire
dungeons	order	(H) Blackrock Mountain: BWL orb approach	From Thorium Point ascend to Spire; take the right hallway to the Orb of Command. Blackhand attunement is required.	N3305;P1427:34.8,85.3,Blackrock north gate;P1428:32.83,25.28,Lower Blackrock Spire;O179879@1428
dungeons	order	(A) Gnomeregan: workshop approach	From Ironforge take the lift down; pass Techbot and follow the train depot hall to Workshop. Workshop Key or lockpicking needed.	N1573;P1426:24.3,39.8,Gnomeregan surface entry;N6231;P1426:21.23,29.88,Gnomeregan: Workshop
dungeons	order	(A) Uldaman: main entrance approach	Ride to the northern excavation; descend the uninstanced dig tunnels to the main portal. Beware elites before zoning in.	N1572;P1418:42.6,12.2,Uldaman excavation mouth;P1418:35.19,10.65,Uldaman
dungeons	order	(H) Uldaman: main entrance approach	Ride to the northern excavation; descend the uninstanced dig tunnels to the main portal. Beware elites before zoning in.	N2861;P1418:42.6,12.2,Uldaman excavation mouth;P1418:35.19,10.65,Uldaman
dungeons	order	(H) Uldaman: back entrance approach	From Kargath travel east to the back cave. Follow the tunnel to the portal; this skips the early main-entrance halls.	N2861;P1418:65.3,42.6,Uldaman back cave;P1418:67.78,44.07,Uldaman: Back entrance
dungeons	order	(A) Onyxia attunement: Drakefire Amulet	Begin at Morgan Vigil. BRD prison steps and SW escort need manual instance navigation; finish with General Drakkisath in UBRS.	N2299;Q4182;Q4183;Q4184;Q4185;Q4186;Q4223;Q4224;Q4241;Q4242;Q4264;Q4282;Q4322;Q6402;Q6403;Q6501;Q6502;N11872;P1445:52.94,77.63,Onyxia's Lair
dungeons	order	(H) Onyxia attunement: Drakefire Amulet	Start with Goretooth in Kargath. Rexxar patrols Desolace; dragon tests can run in parallel. Finish Drakkisath in UBRS.	N9077;Q4903;Q4941;Q4974;Q6566;Q6567;Q6568;Q6569;Q6570;Q6582;Q6583;Q6584;Q6585;Q6601;Q6602;N10321;P1445:52.94,77.63,Onyxia's Lair
dungeons	order	Molten Core attunement: Core Fragment	Take Attunement to the Core from Lothos. In BRD retrieve the fragment beside the MC portal, then return to Lothos.	N14624;P1427:34.8,85.3,Blackrock north gate;N14387;Q7487
dungeons	order	(A) UBRS key chain: Seal of Ascension	Collect the three gems in LBRS; take Vaelan quest steps. In Dustwallow weaken Emberstrife and use the orb on the seal.	P1428:32.83,25.28,Lower Blackrock Spire;Q4742;N4321;N10321;Q4743
dungeons	order	(H) UBRS key chain: Seal of Ascension	Collect the three gems in LBRS; take Vaelan quest steps. In Dustwallow weaken Emberstrife and use the orb on the seal.	P1428:32.83,25.28,Lower Blackrock Spire;Q4742;N11899;N10321;Q4743
dungeons	order	BWL attunement: Blackhand Command	Loot Quartermaster letter; accept quest, clear UBRS and touch Drakkisath Brand. Return to the outdoor Orb of Command.	P1427:34.8,85.3,Blackrock north gate;P1428:32.83,25.28,Lower Blackrock Spire;N9046;Q7761;O179879@1428
travel	order	(A) Flight paths: Eastern Kingdoms	Talk to each flight master to learn the node. A regional walking tour; mountains and sea crossings still require roads or boats.	N352;N523;N931;N2409;N2859;N8609;N2299;N2941;N1573;N1572;N1571;N2835;N2432;N8018;N12596;N12617
travel	order	(H) Flight paths: Eastern Kingdoms	Talk to each flight master to learn the node. A regional walking tour; mountains and sea crossings still require roads or boats.	N4551;N2226;N2389;N2851;N4314;N12636;N2861;N3305;N13177;N6026;N1387;N2858
travel	order	(A) Flight paths: Kalimdor	Talk to each flight master to learn the node. A regional walking tour; mountains and sea crossings still require roads or boats.	N3838;N3841;N4267;N4407;N6706;N8019;N4319;N4321;N16227;N7823;N10583;N15177;N12577;N12578;N10897;N11138
travel	order	(H) Flight paths: Kalimdor	Talk to each flight master to learn the node. A regional walking tour; mountains and sea crossings still require roads or boats.	N3310;N8610;N12616;N11901;N4312;N3615;N16227;N2995;N10378;N4317;N11899;N7824;N10583;N15178;N8020;N6726;N11900;N12740;N11139
travel	nearest	(A) All profession trainers: Eastern Kingdoms	World tour of primary and secondary trainers, specializations and skill-book teachers. Neutral trainers included; bring training money.	N514;N812;N908;N957;N1103;N1215;N1218;N1241;N1246;N1292;N1300;N1317;N1346;N1355;N1430;N1458;N1466;N1470;N1473;N1632;N1651;N1676;N1680;N1681;N1683;N1699;N1700;N1701;N1702;N1703;N2326;N2327;N2329;N2367;N2626;N2627;N2805;N2834;N2836;N2837;N3087;N3136;N3137;N3179;N3181;N3290;N4254;N4258;N5127;N5137;N5150;N5153;N5157;N5159;N5161;N5164;N5174;N5177;N5392;N5482;N5493;N5499;N5500;N5502;N5511;N5513;N5518;N5564;N5566;N5567;N6291;N6295;N6306;N7406;N7868;N7944;N10276;N10277;N11026;N11028;N11029;N11065;N11068;N11072;N11096;N11097;N11146
travel	nearest	(A) All profession trainers: Kalimdor	World tour of primary and secondary trainers, specializations and skill-book teachers. Neutral trainers included; bring training money.	N3494;N3603;N3604;N3605;N3606;N3607;N3955;N3964;N3965;N3967;N4156;N4159;N4160;N4193;N4204;N4210;N4211;N4212;N4213;N4898;N4900;N5784;N6094;N6286;N6287;N6288;N6292;N6297;N6299;N7866;N7870;N7946;N7948;N7949;N8125;N8126;N8128;N8736;N8738;N10993;N11037;N11041;N11042;N11050;N11052;N11070;N11081;N11083;N12025;N12919;N12939
travel	nearest	(H) All profession trainers: Eastern Kingdoms	World tour of primary and secondary trainers, specializations and skill-book teachers. Neutral trainers included; bring training money.	N223;N908;N1382;N1385;N1386;N2114;N2132;N2390;N2391;N2399;N2626;N2627;N2834;N2836;N2837;N2856;N3523;N3549;N3555;N3557;N4552;N4573;N4576;N4586;N4588;N4591;N4596;N4598;N4605;N4609;N4611;N4614;N4616;N5690;N5695;N5759;N6289;N7087;N7406;N7867;N7869;N7871;N11031;N11044;N11048;N11049;N11067;N12920;N14740
travel	nearest	(H) All profession trainers: Kalimdor	World tour of primary and secondary trainers, specializations and skill-book teachers. Neutral trainers included; bring training money.	N1383;N2798;N2855;N2857;N2998;N3001;N3004;N3007;N3008;N3009;N3011;N3013;N3026;N3028;N3067;N3069;N3174;N3175;N3184;N3185;N3332;N3345;N3347;N3355;N3357;N3363;N3365;N3373;N3399;N3404;N3412;N3478;N3484;N3494;N3703;N3704;N5784;N5811;N5938;N5939;N5941;N5943;N6290;N6387;N7088;N7089;N8125;N8126;N8128;N8144;N8146;N8306;N8736;N8738;N10266;N10278;N10993;N11017;N11025;N11046;N11047;N11051;N11066;N11071;N11074;N11084;N11098;N11177;N11178;N12025;N12030;N12032;N12033;N12919;N12961;N13476
travel	nearest	(A) Stormwind: capital services	Bank, auction, inn, flight master, class and profession trainers. Use ramps and stairs between districts.	N2455;N8719;N6740;N352;N914;N376;N928;N331;N918;N461;N5504;N5515;N957;N1292;N1300;N1317;N1346;N2327;N5482;N5493;N5499;N5500;N5502;N5511;N5513;N5518;N5564;N5566;N5567;N11026;N11068;N11096
travel	nearest	(A) Stormwind: class trainers	Find the class trainers hosted by this capital; train only skills available to your class and level.	N914;N376;N928;N331;N918;N461;N5504;N5515
travel	nearest	(A) Stormwind: profession trainers	Includes secondary skills and training assistants. Higher ranks and specializations may require travel outside this capital.	N957;N1292;N1300;N1317;N1346;N2327;N5482;N5493;N5499;N5500;N5502;N5511;N5513;N5518;N5564;N5566;N5567;N11026;N11068;N11096
travel	nearest	(A) Stormwind: repair and supplies	Visit equipment vendors to repair gear and restock weapons, armor or ammunition before leaving the city.	N1287;N1289;N1297;N1319
travel	nearest	(A) Ironforge: capital services	Bank, auction, inn, flight master, class and profession trainers. Use ramps and stairs between districts.	N2460;N8720;N5111;N1573;N5113;N5116;N5147;N5141;N5144;N5165;N5172;N1246;N1466;N1703;N4254;N4258;N5127;N5137;N5150;N5153;N5157;N5159;N5161;N5164;N5174;N5177;N6291;N7944;N10276;N10277;N11028;N11029;N11065;N11146
travel	nearest	(A) Ironforge: class trainers	Find the class trainers hosted by this capital; train only skills available to your class and level.	N5113;N5116;N5147;N5141;N5144;N5165;N5172
travel	nearest	(A) Ironforge: profession trainers	Includes secondary skills and training assistants. Higher ranks and specializations may require travel outside this capital.	N1246;N1466;N1703;N4254;N4258;N5127;N5137;N5150;N5153;N5157;N5159;N5161;N5164;N5174;N5177;N6291;N7944;N10276;N10277;N11028;N11029;N11065;N11146
travel	nearest	(A) Ironforge: repair and supplies	Visit equipment vendors to repair gear and restock weapons, armor or ammunition before leaving the city.	N5152;N5120;N5123;N5106;N5125;N5102
travel	nearest	(A) Darnassus: capital services	Bank, auction, inn and trainers. Flight master is outside the city: take the pink portal to Ruttheran Village.	N4155;N8669;N6735;N3838;N4087;N4090;N4138;N4214;N4217;N4156;N4159;N4160;N4204;N4210;N4211;N4212;N4213;N6292;N11041;N11042;N11050;N11070;N11081;N11083
travel	nearest	(A) Darnassus: class trainers	Find the class trainers hosted by this capital; train only skills available to your class and level.	N4087;N4090;N4138;N4214;N4217
travel	nearest	(A) Darnassus: profession trainers	Includes secondary skills and training assistants. Higher ranks and specializations may require travel outside this capital.	N4156;N4159;N4160;N4204;N4210;N4211;N4212;N4213;N6292;N11041;N11042;N11050;N11070;N11081;N11083
travel	nearest	(A) Darnassus: repair and supplies	Visit equipment vendors to repair gear and restock weapons, armor or ammunition before leaving the city.	N4172;N4234;N4203;N4240;N4164;N4236
travel	nearest	(H) Orgrimmar: capital services	Bank, auction, inn, flight master, class and profession trainers. Use ramps and stairs between districts.	N3309;N8673;N6929;N3310;N3353;N3352;N3401;N3324;N5882;N6018;N3344;N1383;N2855;N2857;N3332;N3345;N3347;N3355;N3357;N3363;N3365;N3373;N3399;N3404;N3412;N5811;N7088;N10266;N11017;N11046;N11066;N11177;N11178
travel	nearest	(H) Orgrimmar: class trainers	Find the class trainers hosted by this capital; train only skills available to your class and level.	N3353;N3352;N3401;N3324;N5882;N6018;N3344
travel	nearest	(H) Orgrimmar: profession trainers	Includes secondary skills and training assistants. Higher ranks and specializations may require travel outside this capital.	N1383;N2855;N2857;N3332;N3345;N3347;N3355;N3357;N3363;N3365;N3373;N3399;N3404;N3412;N5811;N7088;N10266;N11017;N11046;N11066;N11177;N11178
travel	nearest	(H) Orgrimmar: repair and supplies	Visit equipment vendors to repair gear and restock weapons, armor or ammunition before leaving the city.	N4043;N3316;N3410;N3322;N3331;N5816
travel	nearest	(H) Undercity: capital services	Bank, auction, inn, flight master, class and profession trainers. Use ramps and stairs between districts.	N2458;N8672;N6741;N4551;N4593;N4606;N4568;N4582;N4563;N260093;N223;N4552;N4573;N4576;N4586;N4588;N4591;N4596;N4598;N4605;N4609;N4611;N4614;N4616;N7087;N11031;N11044;N11048;N11049;N11067
travel	nearest	(H) Undercity: class trainers	Find the class trainers hosted by this capital; train only skills available to your class and level.	N4593;N4606;N4568;N4582;N4563;N260093
travel	nearest	(H) Undercity: profession trainers	Includes secondary skills and training assistants. Higher ranks and specializations may require travel outside this capital.	N223;N4552;N4573;N4576;N4586;N4588;N4591;N4596;N4598;N4605;N4609;N4611;N4614;N4616;N7087;N11031;N11044;N11048;N11049;N11067
travel	nearest	(H) Undercity: repair and supplies	Visit equipment vendors to repair gear and restock weapons, armor or ammunition before leaving the city.	N4604;N4602;N4569;N4601;N4600;N5820
travel	nearest	(H) Thunder Bluff: capital services	Bank, auction, inn, flight master, class and profession trainers. Use ramps and stairs between districts.	N2996;N8674;N6746;N2995;N3041;N3038;N3033;N3030;N3044;N3047;N2798;N2998;N3001;N3004;N3007;N3008;N3009;N3011;N3013;N3026;N3028;N7089;N10278;N11047;N11051;N11071;N11084
travel	nearest	(H) Thunder Bluff: class trainers	Find the class trainers hosted by this capital; train only skills available to your class and level.	N3041;N3038;N3033;N3030;N3044;N3047
travel	nearest	(H) Thunder Bluff: profession trainers	Includes secondary skills and training assistants. Higher ranks and specializations may require travel outside this capital.	N2798;N2998;N3001;N3004;N3007;N3008;N3009;N3011;N3013;N3026;N3028;N7089;N10278;N11047;N11051;N11071;N11084
travel	nearest	(H) Thunder Bluff: repair and supplies	Visit equipment vendors to repair gear and restock weapons, armor or ammunition before leaving the city.	N8359;N3019;N8360;N3020;N3095;N3093
travel	nearest	Neutral town: Booty Bay	Town services and supplies. Keep peace near guards; available training, auction and bank services vary by settlement.	N6807;N8123;N15677;N2836;N2837;N2834
travel	nearest	Neutral town: Ratchet	Town services and supplies. Keep peace near guards; available training, auction and bank services vary by settlement.	N6791;N3496;N258878;N16227;N3494;N3453
travel	nearest	Neutral town: Gadgetzan	Town services and supplies. Keep peace near guards; available training, auction and bank services vary by settlement.	N7733;N7799;N8661;N8128;N8126;N8736;N8125
travel	nearest	Neutral town: Everlook	Town services and supplies. Keep peace near guards; available training, auction and bank services vary by settlement.	N11118;N13917;N9857
travel	nearest	Neutral town: Cenarion Hold	Town services and supplies. Keep peace near guards; available training, auction and bank services vary by settlement.	N15174;N15176;N15179;N15419
travel	order	Neutral towns: both continents	Booty Bay to Ratchet by boat, then visit Gadgetzan, Everlook and Cenarion Hold. Bring flight paths or plan long road journeys.	N6807;N8123;N15677;N6791;N3496;N16227;N7733;N7799;N8661;N11118;N13917;N9857;N15174;N15176;N15179
travel	nearest	(A) Goldshire: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N295;N514;N1215;N1651;N2329;N1430
travel	nearest	(A) Auberdine: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N3841;N6737;N6297;N6299;N4193
travel	nearest	(A) Thelsamar: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N1572;N6734;N1470;N1681
travel	nearest	(A) Southshore: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N2432;N2352;N2367
travel	nearest	(H) Tarren Mill: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N2389;N2388;N2391;N2390;N2399
travel	nearest	(H) Stonard: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N6026;N6930;N1386
travel	nearest	(A) Nijel Point: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N6706;N11103;N8150
travel	nearest	(H) Shadowprey Village: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N6726;N11106;N12033;N12032
travel	nearest	(A) Feathermoon Stronghold: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N8019;N7736;N7948;N7949;N7946
travel	nearest	(H) Camp Mojache: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N8020;N7737;N8146;N8144;N11098
travel	nearest	(H) Crossroads: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N3615;N3934;N3478;N3484
travel	nearest	(H) Camp Taurajo: town services	Visit the local inn and trainers; flight master included where the town has one. Set your hearth before nearby adventures.	N10378;N7714;N3703;N3704;N6387
travel	order	Sightseeing: four Emerald Dream portals	Visit four ancient green-dragon groves across both continents. Keep clear of raid dragons and elite dragonkin.	P1431:45,40,Twilight Grove;P1425:62,20,Seradane;P1440:93,38,Bough Shadow;P1444:50,10,Dream Bough
travel	order	Sightseeing: sealed Gates of Uldum	From Gadgetzan stock up, then cross southern Tanaris to the ancient sealed gate. The original gate cannot be entered.	N7733;N8125;P1446:37,81,Sealed Gates of Uldum
travel	order	Secret trail: Ravenholdt Manor	Take the mountain trail and tunnel above northeastern Hillsbrad. Manor training and reputation work mainly serve rogues.	P1424:75,23,Ravenholdt trail;N6707;N6768
travel	nearest	Sightseeing: Faldir Cove	Find the hidden coastal cove in southwestern Arathi and visit the ship crew. Follow the ravine down; beware nearby naga.	P1417:32,81,Faldir Cove;N2610;N2769;N2768
]==]
