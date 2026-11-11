# Changelog

## 1.3.1

- Mage city teleports now need a **Rune of Teleportation** in your bags, as in the game. Without one, Real routes no longer tells a mage to cast Teleport: Stormwind, Ironforge, Darnassus, Orgrimmar, Undercity or Thunder Bluff. Teleport: Moonglade and Astral Recall need nothing and are unchanged.
- Real routes can use **engineering transporters**: Dimensional Ripper - Everlook, Ultrasafe Transporter: Gadgetzan, SAF-T Emergency Ripper: Everlook and EZ-Thro Field Transporter: Gadgetzan, plus the **Crumbling Hearthstone** (Orgrimmar for the Horde, Stormwind for the Alliance). One is suggested only when it is quicker and you can really use it: in your bags, off cooldown, with a charge left, worn if it's a trinket, and with the Engineering skill and specialization the game asks for. These devices can misfire, so the step says so. Where they land is the town, not an exact spot.
- The Steamwheedle Port – Powderfuse Port boat is now planned at about 3 minutes 20 seconds including the wait, instead of 1 minute 30 seconds, so routes no longer count on it being quicker than it is.
- New regression tests cover the rune, every transporter's requirements (carried, cooldown, charges, worn, skill, specialization, level, faction) and clients missing the item APIs.

## 1.3.0

- **Real routes is now a standard feature and on by default** (no longer a beta). The arrow follows the quickest way you can really go: through passes, gates and tunnels, by flight path, boat, zeppelin or the tram, and with your hearthstone or a teleport when that's quicker. Updating turns it on once for everyone; turn it off in **Settings → Routes**, the quick menu or with `/wp travel off`, and that choice is kept. The Routes tab no longer shows the "New to try" notice.
- Routes are quicker and more complete: the planner knows every mage city teleport and Teleport: Moonglade, uses Astral Recall before your hearthstone when both are ready (saving the longer cooldown), plans with your riding skill (Apprentice +60%, Journeyman +100%) and travel forms (Travel Form, Ghost Wolf, Aspect of the Cheetah, Cat Form with Feral Swiftness) even before you mount up, and counts Frequent Flier. A teleport or hearthstone on cooldown, or one you don't have, is never suggested; the global cooldown no longer hides a ready teleport, and in combat the last known cooldown is used.
- Sharing the paths you walk with other players stays opt-in: it is off by default and stays on only if you already had Real routes on with sharing enabled. Route sharing & votes (beta) and Treasure hunt (beta) are unchanged.
- New regression tests cover the default and the update, class teleports and cooldowns, the hearthstone and Astral Recall, teleport items, riding and form speeds, and clients missing any of the spell, item or talent APIs.

## 1.2.5

- Fixes Lua errors from party and raid frames ("attempt to perform boolean test on field 'outOfRange' (a secret boolean value, while execution tainted by 'WaypointTracker')"). Opening Edit Mode from Waypoint Tracker (Settings, the quick menu or `/wp editmode`) now opens it the same way the game menu does, so the game's own frames are no longer affected. If you saw the errors, `/reload` once after updating.
- Open Window in Waypoint Tracker's settings now shows the window above the Settings panel instead of closing it from the addon. Open Edit Mode from Settings opens Edit Mode behind the panel and tells you; close Settings to move things.
- New regression tests model the game's taint rules for Edit Mode and the Settings panel, and a code check refuses the calls that caused this.

## 1.2.4

- Click the quest icon in front of a quest in your objective tracker (the "..." or "?") and the arrow points at that quest's current objective, then moves on to the next one as you progress. Click the icon again to let go. On by default; **Settings → Maps → Track quests with a click** turns it off.
- Nearest is back as one-click buttons in the Find tab, now with more places: Mailbox, Innkeeper, Flight Master, Repair, Merchant, Bank, Auction House, Stable Master, Spirit Healer, Battlemaster and Meeting Stone. They are also in the quick menu (right-click the minimap button) under **Nearest...**.
- New **Settings → Maps → Pin colour**: gold, green, pink, purple, red or white for the active waypoint's pin on the world map and minimap, so it stands out from quest ! and ? icons.
- New regression tests cover the quest icon, every Nearest service for both factions, pin colour, every key binding, `/cway` and the arrival settings.

## 1.2.3

- Data update for the current WoW Forever client (build 1.60.1.70862, Nov 7). Find knows the 17 items added since launch, including the Endless elixirs and scrolls, Noggenfogger Elixir and the new copies of Thunderfury, Sulfuras, Benediction, Anathema and Rhok'delar, with names in all ten languages.
- 10 new Forever quests are recognised; their names come from the game while you play.

## 1.2.2

- Fixes the "exceeded its time limit" Lua warning while the Settings panel is open (#13). Changing a Waypoint Tracker setting no longer makes the game search every setting and redraw the whole list, and changes made in the panel redraw it only once.

## 1.2.1

- Route sharing & votes (beta) is now off by default, including when updating from 1.2.0. Enable it in Settings → Routes or with Enable (beta) in the Routes tab; your opt-in is remembered.
- While it is off, no route lists or votes are sent or received. Ready-made and personal routes, following, text import/export and local votes still work. Real routes (beta) keeps its separate walked-path sharing setting.
- Routes and Settings clearly label the sharing beta in every supported language.

## 1.2.0

- Ready for the WoW Forever launch (client 1.60.1, interface 16001). Install into `_forever_\Interface\AddOns`.
- Find's quest markers, flight paths, towns and item names come from the live launch build (1.60.1.70755), with refreshed All The Things quest data.
- Works with the live client's newer spell, item, chat and Edit Mode behaviour: known teleports and your hearthstone are detected reliably, route sharing pauses and retries while the game restricts addon messages, and the arrow, text and other screen elements remember their place separately for each Edit Mode layout style.
- Real routes (beta) uses the corrected Steamwheedle Port and Powderfuse boat docks and no longer sends Horde characters through Dalaran.
- Players' discoveries add 234 NPCs, 117 quests, 21 objects and the stock and drops of 260 items, with more observed locations for existing entries.
- One window for Waypoints, Find and Routes. Editors, imports and help open as pages inside the tabs, with Back to return.
- Ready-made route names describe what you get or do; levels and faction restrictions move into the details and tooltips. Two-line rows show the map and category, and For my level sorting puts suitable routes first.
- Click a route for an area, continent or world map preview with stop pins and route lines. Click the preview to open it on the world map, with Set This Route and Back to Routes. Set uses your existing replace-or-add choice; closing the map clears the preview.
- Route details include a scrolling numbered stop list. Start/Stop, Share/Skip and More keep the actions in one row, with editing, copying and removal in More.
- Settings live in Blizzard Settings. Move the arrow, its text, the coordinates box and the route recorder in Edit Mode, with positions saved per layout.
- Left-click the minimap button to open the window; right-click for the quick menu; Shift + left-click to add a waypoint here. The Addon Compartment and world-map button offer quick access too.
- Feedback appears below the title. Clicks in the window keep chat quiet; the Real routes notice offers a button to turn it on. World-map coordinates respect Blizzard's saved settings.
- Real routes (beta): the arrow guides you through passes and gates, with flight paths, boats, zeppelins, the tram, hearthstone and teleports when quicker. Enable it in Routes or the quick menu; tune it in Settings → Routes.
- Real routes corrects transport eligibility and timings, replaces blocked walking shortcuts with verified paths where available, and labels needed unmeasured passages. Unresolved quest positions are removed while their names and definitions stay available in Find. The incomplete shipped corpse trace is dropped; corpse routing uses the general planner with checks for blocked legs and backward steering.
- Zone-border roads use corrected ground anchors and verified bends or tunnel floors, recovering connections rejected by straight shortcuts across nearby slopes.
- Treasure hunt remains beta, with its controls in Settings and the quick menu.

## 1.1.1

- Spots you share in chat now start with **[Waypoint Tracker]**, followed by the map pin and coordinates. Turn it off under the former advanced panel (now **Settings → Find & Sharing → Start shared spots with [Waypoint Tracker]**).
- Stability fixes and improvements.

## 1.1.0

**Treasure hunt (beta)**
- Tick **Treasure hunt** in the window, type `/wp treasure`, or set a key binding. Chests, rare spawns and other markers the game shows near you get a ping the moment they appear: a sound, a message on screen and a blinking taskbar icon if you're in another window.
- The arrow points straight at it, follows a rare that wanders, and lets go once it's taken, killed or gone, then returns to your own waypoint.
- Rares come from your minimap, nameplates and target, placed at their known spawn. Ones someone else is already fighting are left out.
- A chest right in front of you pings too, and looting it clears it.
- `/wp treasure status` lists the markers the game shows around you and your most recent finds, with how each was found.
- **Lead me to known chest spots** walks you from one known chest spawn to the next while nothing has appeared.
- Each part has its own switch under the former advanced panel (now **Settings → Treasure Hunt (beta)**).

**Everything else**
- Find's database is refreshed with the latest WoW Forever data: more of Zephras Isle, the Skyborne arrival in Mulgore, and new NPCs, quests and items across Azeroth.
- Players' discoveries add 372 NPCs, 166 quests and the stock and drops of 463 items across WoW Forever, like Yorn Grimtotem of the Earthen Ring in Mulgore.
- **This zone only** recognises every map the game uses for a zone, including both of Zephras Isle's.
- Find searches smoothly for any name, including ones it hasn't learned yet, and places every spot cleanly on the map in WoW Forever's zones.
- `/way`, `/wayb` and `/cway` go to whichever addon already uses them, and `/wp` does the same things.
- Each release includes a `release.json`, so addon managers install the WoW Forever build directly.

## 1.0.0

First release for WoW Forever.

**The arrow**
- A 3D arrow over your character points to your waypoint, with its name, distance and time to arrive underneath. It turns from gold to green as you get closer.
- It never catches mouse clicks, so right-click to attack always works.
- Move it with the button formerly called **Move Arrow** in the window or in the game's **Edit Mode** (Esc > Edit Mode), where each layout keeps its own spot. **Reset** brings back its default place, size and visibility.
- The arrow and its text have their own size and visibility. Tick **Move the text separately** to place the text anywhere.
- Arriving plays a sound, removes the waypoint and moves on to the next closest one. A waypoint set where you stand says "You're here" until you walk away.
- **Your corpse:** when you die, the arrow points to your body, then goes back to your waypoint once you're alive (on by default).

**Setting waypoints**
- A simple window: search a zone (typos are fine), type X and Y, and set it. Pasting "45.2 67.8" fills both boxes, and **Use My Position** fills in where you are.
- `/way Elwynn Forest 42 65 Goldshire`, `/way 42 65`, `/wp here`, and `/way hogger` to go straight to something by name.
- Ctrl + Right-click the world map to drop a waypoint. Pins on the world map and minimap, with the arrow's waypoint riding the minimap edge.
- The arrow follows the game's own map pin, including map pin links clicked in chat, and can follow the quest you're tracking.
- Quest guides and other addons can send their waypoints to the arrow.

**Sharing**
- **Share** on any waypoint, or on typed coordinates without setting a waypoint: pick Party, Raid, Guild, Say or whisper your target. The chat box opens with a clickable map pin that works for everyone, even without the addon.
- `/wp share` shares where you stand, and there's a key binding for it.

**Find**
- Search quests, friendly NPCs, enemies (with level and elite/rare/boss), objects, items, flight paths and towns, then double-click to point the arrow at the closest one.
- Quests show who gives and takes them, with **Go to quest giver / objective / hand in**. For quests in your log, it uses where the game's map shows them.
- Items show their quality, level, description, which quests need them and what drops them.
- **Nearest** buttons for the closest mailbox, innkeeper, flight master, repair, bank and auction house.
- Built for WoW Forever: its flight paths, towns, quest markers and reshaped maps (Stormwind with its harbour, Mulgore, Redridge, the Eastern Plaguelands), a curated Forever database (up to date with WoW Forever 1.60.1, including the Season of Discovery quests Forever kept), and Forever's new quests by name, learned from the game in the background (Find shows the progress).
- **Learns as you play:** the NPCs and enemies around you with their titles (search **blacksmith** to find the blacksmiths you've seen), what vendors sell, quest givers and hand-ins, mailboxes, and what drops from the enemies and objects you loot. Only what's new or different from the database is kept, on your computer. **Share discoveries** copies it when you choose to share; swap with friends through **Import**, or send it in for everyone.
- **Correct a spot:** press **Wrong spot? Correct it** on an NPC or object in Find, stand where it really is and save (or type the coordinates). **It's not there** removes a wrong spot; **Remove my correction** undoes it.

**Everything else**
- The former advanced panel held the rest: fade when on course, hide in combat or on flight paths, colour styles, arrival distance, metres, a coordinates box, the game's own map pin, and more.
- Translated into German, French, Spanish, Portuguese, Russian, Korean and Chinese (Simplified and Traditional).
