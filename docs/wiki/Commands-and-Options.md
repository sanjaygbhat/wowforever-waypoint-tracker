[Home](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki) · [Install & quick start](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Installation-and-Quick-Start) · [Commands & options](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Commands-and-Options) · [Treasure hunt (beta)](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Treasure-Hunt) · [Troubleshooting](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Troubleshooting-and-Compatibility) · [Discoveries & privacy](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Discoveries-Privacy-and-Contributing)

# Commands & Settings

Open `/wp` or left-click the minimap button for one window with **Waypoints**, **Find**, **Routes** and **Treasure (beta)** tabs. Editors, imports and help stay inside the tabs; **Back** returns to the previous page. Feedback appears below the title, above the tab content. Right-click the minimap button for the quick menu; Shift + left-click adds a waypoint where you stand. The Addon Compartment also opens the window or quick menu.

## Commands

| Command | What it does |
|---|---|
| `/wp` | Open or close the window on its last tab |
| `/wp find [text]` · `/wp search [text]` | Open the Find tab and optionally search |
| `/wp routes` · `/wp route` · `/wp lists` | Open the Routes tab; close the window if already on Routes |
| `/wp routes next` · `/wp routes skip` | Skip the current route stop |
| `/wp routes record` · `/wp routes new` · `/wp routes create` | Start recording, or finish recording and open the editor |
| `/wp routes add` · `/wp routes stop` | Add a recording stop here, or stop following a route |
| `/wp routes test` · `/wp routes fast` · `/wp routes status` | Test Route sharing & votes (beta), toggle the shorter feedback delay, or show sharing status |
| `/wp settings` · `/wp options` · `/wp config` | Open Blizzard Settings for Waypoint Tracker |
| `/wp editmode` | Enter the game's Edit Mode |
| `/way [zone] x y [name]` | Set a waypoint; leave the zone out to use your current zone |
| `/way hogger` | Go to an exact name match, or open Find with that search |
| `/wp here [name]` · `/wayb [name]` | Add a waypoint where you stand |
| `/wp share [zone x y] [name]` | Prepare a map pin in chat; without coordinates, share where you stand |
| `/wp clear` · `/wp reset` · `/wp remove` | Remove the arrow's waypoint; add `all` to remove every waypoint |
| `/wp list` | List waypoints and distances in chat |
| `/wp arrow` | Show or hide the arrow |
| `/wp closest` · `/cway` | Point to the closest waypoint |
| `/wp treasure` · `/wp hunt` | Toggle Treasure hunt (beta) |
| `/wp treasure show` | Open the Treasure (beta) tab without toggling |
| `/wp treasure status` | Report what it sees and recent finds |
| `/wp travel [on\|off\|steps\|status]` · `/wp realroutes` · `/wp rr` | Toggle Real routes, set it on/off, list travel steps or show status |
| `/wp help` · `/wp ?` · `/way` | Show the command list |

`/waypoint` and `/waypointtracker` are aliases for `/wp`. If another addon owns `/way`, `/wayb` or `/cway`, use `/wp` instead. Zone names follow your client language.

## Settings

Open **Settings → AddOns → Waypoint Tracker**, press **Settings** in the window or use `/wp settings`. Root descriptions and the version are in tooltips.

| Settings page | Controls |
|---|---|
| Waypoint Tracker (root) | Open Waypoint Tracker, Open Edit Mode, Key Bindings, Reset All Settings; show the arrow, always point to the closest waypoint, corpse waypoint, remember waypoints, minimap button, chat messages, metres, other addons' waypoints, also show the game's own map pin |
| Arrow — Arrow Display | Arrow size (50–200%), visibility (20–100%), colour style and colour picker, fade when heading the right way, hide during combat or on flight paths |
| Arrow — Arrow Text | Text size and visibility, name, distance, Show time to arrive (off by default), move the text separately |
| Arrow — When You Arrive | Arrival distance (3–50 yards), remove the waypoint, play a sound, point to the next closest waypoint |
| Maps — World map | Pins, coordinates, Ctrl + right-click to add, follow the game's map pins, point to the tracked quest |
| Maps — Minimap | Pins and keeping the arrow's waypoint on the minimap edge |
| Maps — Coordinates box | Show a box with your coordinates; move it in Edit Mode |
| Routes | When starting a route: ask, replace existing waypoints or add to them; Route sharing & votes (beta), off by default; show low-rated routes |
| Routes — Real routes | Real routes (on by default); Route preference (Safe route by default; Always fastest available); flight paths; boats, zeppelins and the tram; hearthstone and teleports; map route line; learn walked paths; share paths |
| Treasure Hunt (beta) | Open the Treasure (beta) tab; enable Treasure hunt (beta), off by default; chests, rares and events; known chest spots and rare spawns; pings; immediate arrow focus |
| Find & Sharing — Find | Learn NPCs, quests and objects as you play; only your faction; only this zone |
| Find & Sharing — Sharing | Start shared spots with [Waypoint Tracker] |

**Reset All Settings** asks before restoring defaults; waypoints and routes are kept. World-map coordinates use Blizzard's panel and its saved coordinate settings.

## Edit Mode

Open **Esc → Edit Mode**, the quick menu's **Edit Mode**, **Open Edit Mode** in Settings, or `/wp editmode`. Move the arrow, its text, the coordinates box and route recorder with their selection boxes. Each layout keeps its own positions. Changes apply immediately; **Reset to Default** restores the selected element. Enable **Move the text separately** to place text independently. The arrow ignores mouse clicks during play. Settings and Edit Mode cannot open during combat.

## Routes

Follow, create, record, import and share routes from the **Routes** tab. Editors and copy/import pages have a **Back** button. Recording hides the window and shows the recorder strip.

Ready-made names describe what you get or do, with the map and category on a second line. Levels and faction restrictions appear in the details and row tooltip; **For my level** sorts suitable routes first. Ready-made names and notes are in English; generated gathering names use your client language.

Click a row to select it and see a map preview on the right. It picks an area, continent or world map to show the stops, with a green start pin and lines in route order. Hover a pin for its name and coordinates; scroll the details for the numbered stop list. Stops that cannot project onto the map, such as dungeon floors, are reported beneath it. Missing map art uses a dark grid with pins.

Click the preview or a pin to open the route on the normal world map, outside combat. **Set This Route** starts following it. If you have waypoints already, the Replace / Add / Cancel question appears unless you set a preference in Settings. **Back to Routes** returns to the selected route. If you browse to a map with no stops, **Show Them** returns to the route's map. The close button ends the preview and leaves the map open; closing the map ends the preview without reopening Routes.

**Start Route** or a row double-click also starts the route. While running, use **Stop Route** and **Skip This Point**. **Share...** opens sharing choices; **More...** contains Copy text, Edit and Delete for your routes, or Copy text, Remove and Hide This Author for shared routes. Ready-made routes offer Copy text.

**Route sharing & votes (beta)** is off by default. Enable it in **Settings → Routes** or with **Enable (beta)** in the **Routes** tab to exchange shared route lists and votes with other Waypoint Tracker players in your guild, group and addon channel. Updating from 1.2.0 turns it off once; later opt-ins are remembered. Local routes, following, text import/export and local votes work while it is off. Walked-path sharing for Real routes has a separate setting, off by default.

### Fastest route (Real routes)

The arrow guides you through passes and gates and onto flight paths, boats, zeppelins or the tram when they save time. It also considers your hearthstone, Astral Recall, mage and druid teleports and engineering transporters, with your riding skill and travel forms included in the travel time. Real routes is on by default and works for every destination, including Nearest results, using the travel links and paths it knows.

**Safe or fastest, your choice.** The default **Safe route** preference is danger-aware. When a quicker, riskier route saves at least 15 seconds and 5% of the trip, the arrow offers it for ten seconds and you decide. Choose **Settings → Routes → Route preference → Always fastest** to take the quickest route every time without asking.

It checks the travel abilities you have and their cooldowns. Open a flight master's map to learn your available flights. Distance appears under the arrow. For time to arrive too, turn on **Settings → Arrow → Show time to arrive** (off by default). As you move, it re-plans and works the route out a little at a time in the background, so the game stays smooth while you follow the current route.

Turn Real routes off in **Settings → Routes** for a straight arrow.

## Nearest

Open the **Find** tab and click a **Nearest** button. Or right-click the minimap button and open **Nearest...**. Each choice sets a waypoint for your faction, and the arrow takes you there by the fastest route.

| Button | Where it takes you |
|---|---|
| Mailbox | The nearest known mailbox |
| Innkeeper | An innkeeper to set your home |
| Flight Master | A flight master |
| Repair | A vendor who repairs gear |
| Merchant | A vendor to buy or sell items |
| Bank | A banker |
| Auction House | An auctioneer |
| Stable Master | A stable master for your pets |
| Spirit Healer | A spirit healer |
| Battlemaster | A battlemaster |
| Meeting Stone | A dungeon meeting stone |
| Class Trainer | The nearest trainer for **your class**, picked automatically |
| Profession Trainer | A menu of **Alchemy, Blacksmithing, Enchanting, Engineering, Herbalism, Leatherworking, Mining, Skinning, Tailoring, Cooking, First Aid and Fishing**; pick one to find the nearest trainer it knows |
| Weapon Master | The nearest known weapon master |
| Riding Trainer | The nearest known riding trainer |

Trainers come from what players have seen in WoW Forever, capital cities and towns alike, and every trainer you talk to is added to your own list.

## Treasure hunt (beta)

**Off by default. How to turn it on:**

1. Type `/wp`.
2. Open the **Treasure (beta)** tab.
3. Click **Enable treasure hunt (beta)**.

You can also type `/wp treasure` to toggle it, or enable **Treasure hunt (beta)** under **Esc → Options → AddOns → Waypoint Tracker → Treasure Hunt (beta)**. `/wp treasure show` opens the tab without changing whether it is on.

The tab has option checkboxes, **Nearby now** with distance and double-click/right-click actions, **In this zone** with known spots and recent rare sighting times, and **Recent finds** with 50 saved finds per character. See the [guide](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Treasure-Hunt) for every option.
