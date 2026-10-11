[Home](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki) · [Install & quick start](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Installation-and-Quick-Start) · [Commands & options](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Commands-and-Options) · [Treasure hunt](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Treasure-Hunt) · [Troubleshooting](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Troubleshooting-and-Compatibility) · [Discoveries & privacy](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Discoveries-Privacy-and-Contributing)

# Commands & Settings

Open `/wp` or left-click the minimap button for one window with **Waypoints**, **Find** and **Routes** tabs. Editors, imports and help stay inside the tabs; **Back** returns to the previous page. Feedback appears below the title, above the tab content. Right-click the minimap button for the quick menu; Shift + left-click adds a waypoint where you stand. The Addon Compartment also opens the window or quick menu.

## Commands

| Command | What it does |
|---|---|
| `/wp` | Open or close the window on its last tab |
| `/wp find [text]` · `/wp search [text]` | Open the Find tab and optionally search |
| `/wp routes` · `/wp route` · `/wp lists` | Open the Routes tab; close the window if already on Routes |
| `/wp routes next` · `/wp routes skip` | Skip the current route stop |
| `/wp routes record` · `/wp routes new` · `/wp routes create` | Start recording, or finish recording and open the editor |
| `/wp routes add` · `/wp routes stop` | Add a recording stop here, or stop following a route |
| `/wp routes test` · `/wp routes fast` · `/wp routes status` | Test route sharing, toggle the shorter feedback delay, or show sharing status |
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
| `/wp treasure [status]` · `/wp hunt` | Toggle treasure hunt (beta), or show what it sees with `status` |
| `/wp travel [on\|off\|steps\|status]` · `/wp realroutes` · `/wp rr` | Toggle Real routes (beta), set it on/off, list travel steps or show status |
| `/wp help` · `/wp ?` · `/way` | Show the command list |

`/waypoint` and `/waypointtracker` are aliases for `/wp`. If another addon owns `/way`, `/wayb` or `/cway`, use `/wp` instead. Zone names follow your client language.

## Settings

Open **Settings → AddOns → Waypoint Tracker**, press **Settings** in the window or use `/wp settings`. Root descriptions and the version are in tooltips.

| Settings page | Controls |
|---|---|
| Waypoint Tracker (root) | Open Waypoint Tracker, Open Edit Mode, Key Bindings, Reset All Settings; show the arrow, always point to the closest waypoint, corpse waypoint, remember waypoints, minimap button, chat messages, metres, other addons' waypoints, also show the game's own map pin |
| Arrow — Arrow Display | Arrow size (50–200%), visibility (20–100%), colour style and colour picker, fade when heading the right way, hide during combat or on flight paths |
| Arrow — Arrow Text | Text size and visibility, name, distance, time to arrive, move the text separately |
| Arrow — When You Arrive | Arrival distance (3–50 yards), remove the waypoint, play a sound, point to the next closest waypoint |
| Maps — World map | Pins, coordinates, Ctrl + right-click to add, follow the game's map pins, point to the tracked quest |
| Maps — Minimap | Pins and keeping the arrow's waypoint on the minimap edge |
| Maps — Coordinates box | Show a box with your coordinates; move it in Edit Mode |
| Routes | When starting a route: ask, replace existing waypoints or add to them; share routes and votes; show low-rated routes |
| Routes — Real routes (beta) | Enable Real routes; flight paths; boats, zeppelins and the tram; hearthstone and teleports; map route line; learn walked paths; share paths |
| Treasure Hunt (beta) | Enable treasure hunt; chests, rares and other markers; known chest spots; pings; point the arrow at finds |
| Find & Sharing — Find | Learn NPCs, quests and objects as you play; only your faction; only this zone |
| Find & Sharing — Sharing | Start shared spots with [Waypoint Tracker] |

**Reset All Settings** asks before restoring defaults; waypoints and routes are kept. World-map coordinates use Blizzard's panel and its saved coordinate settings.

## Edit Mode

Open **Esc → Edit Mode**, the quick menu's **Edit Mode**, **Open Edit Mode** in Settings, or `/wp editmode`. Move the arrow, its text, the coordinates box and route recorder with their selection boxes. Each layout keeps its own positions. Changes apply immediately; **Reset to Default** restores the selected element. Enable **Move the text separately** to place text independently. The arrow ignores mouse clicks during play. Settings and Edit Mode cannot open during combat.

## Routes

Follow, create, record, import and share routes from the **Routes** tab. Editors and copy/import pages have a **Back** button. Recording hides the window and shows the recorder strip.

**Real routes (beta)** is new in this release. The arrow guides you through passes and gates, using known flight paths, boats, zeppelins, the tram, your hearthstone or teleports when quicker. Turn it on from the Routes tab notice, the quick menu or Settings → Routes. Open a flight master's map once to learn your available flights. It uses a travel network and learned paths, so it may still miss a better way.

TODO: capture the three tabs, Blizzard Settings and all four Edit Mode selection boxes.
