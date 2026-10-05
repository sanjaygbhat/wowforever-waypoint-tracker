# Release checklist: test everything, shoot the store screenshots

One file for the whole release check:

- **Part B, the tests (about 2 hours):** every feature, on your **level 20 undead paladin**, mostly around **Brill** in Tirisfal Glades.
- **Part C, the photo tour (about 1½ hours):** the **6 CurseForge screenshots**, taken at famous places that level 20 players visit. Each shot has a **Horde option** for your paladin and an **Alliance option** for your level 20 mage. Shoot both if you can, then pick the best 6. Three of each faction is ideal, so both sides see themselves on the page.

Tick boxes as you go.

| Mark | Meaning |
|---|---|
| ☐ | A test step. **Expect:** is what should happen. |
| 📸 | A screenshot. Set up exactly as described, then press your **screenshot key** (see A2). |
| 🟥 / 🟦 | The Horde (paladin) or Alliance (mage) version of a shot. |
| ⚠️ | Something to watch out for. |

If a test fails, write down the step number, what you did, what you saw, and the Lua error text if there was one (details at the end). Then carry on.

> ⚠️ **Beta terms:** if the WoW Forever beta still has an NDA or a no-screenshots rule, keep the screenshots private until launch.

---

## Part A: Get ready (15 min, before you start)

### A1. Install fresh

- ☐ A1.1 Quit the game. In `World of Warcraft\_classic_beta_\Interface\AddOns\`, delete the old `WaypointTracker` and `WaypointTracker_Data` folders. Unzip `WaypointTracker-v1.0.0.zip` there. **Expect:** exactly two folders, and no `WaypointTracker\WaypointTracker` nesting.
- ☐ A1.2 To test a first install, also delete `WTF\Account\<ACCOUNT>\SavedVariables\WaypointTracker.lua` and `WTF\Account\<ACCOUNT>\<Realm>\<YourPaladin>\SavedVariables\WaypointTracker.lua`.
- ☐ A1.3 Turn off any other waypoint-arrow or quest-arrow addon. You'll turn one back on in section 11.
- ☐ A1.4 Log your paladin out **in Brill** (Tirisfal Glades), where the tests start.

### A2. Make screenshots look their best (do once per character)

**Display** (`Esc > Options > Graphics`):

| Setting | Value | Why |
|---|---|---|
| Display Mode | Fullscreen (or Windowed Fullscreen) | No window border in the shot |
| Resolution | 1920×1080 or 2560×1440 (16:9) | CurseForge shows 16:9 best. Avoid ultrawide, or crop to 16:9 later |
| Graphics Quality | 10 (or as high as stays smooth) | Sharper world, better shadows |
| Render Scale | 100%, or higher if your FPS allows | Only the 3D world gets sharper; the UI stays crisp either way |
| View Distance | Max | Distant landmarks (Stormwind's gate, Thunder Bluff's mesas) show up |
| Anti-Aliasing | Highest available | No jagged edges |
| Vertical Sync | On | No tearing in the shot |
| UI Scale | On, about **0.9 at 1080p** or **1.0 at 1440p** | The addon's text is readable in a thumbnail |

**Hide clutter, but not the whole UI:**

- ⚠️ **Don't use Alt+Z** (hide UI). It hides the arrow too.
- At character select, press **AddOns** and untick your other addons (damage meters, bug reporters and so on) for the photo session, so only Waypoint Tracker shows. Tick them again afterwards.
- `Esc > Options > Interface > Names`: turn off **My Name**, **Guild Names** and **Friendly Players** (privacy, and no strangers' names in busy cities).
- `Esc > Options > Combat`: turn off **Floating Combat Text**.
- Press **Shift+V** and **Ctrl+V** until no nameplates show.
- Collapse the quest tracker (the **−** on its header) and close your bags.
- For a clean shot with only the arrow, don't use scripts. Crop instead. The portraits, minimap, chat and action bars sit in the corners and along the bottom, and the arrow sits in the middle. Keep the arrow near the centre of the screen and crop out the middle at 16:9: **1920×1080 from a 1440p screen**, or **1280×720 from a 1080p screen**. Before you shoot:
  - Clear your target (Esc), so the target portrait goes away.
  - Keep the mouse off the chat box and wait a minute. The chat text fades out by itself.
  - In Edit Mode, untick the extra action bars you don't need on screen.

**Screenshot quality, in chat:**

```
/console screenshotQuality 10
/console screenshotFormat png
/console cameraDistanceMaxZoomFactor 2.6
/console scriptErrors 1
```

- If the client refuses `screenshotFormat png`, ignore it. JPG at quality 10 is fine.
- `cameraDistanceMaxZoomFactor` lets you zoom out further for scenic shots.
- `scriptErrors 1` shows Lua errors while you test.

**Your screenshot key:** WoW's own screenshot key is **Print Screen** by default. It saves the picture at full size. To check it or change it, go to `Esc > Options > Keybindings` and search for **Screenshot**. It's usually under **Miscellaneous** or **Other**. If your keyboard has no Print Screen key, click the box next to it and press a key you don't use, for example **F11**, **Ctrl+F12** or a spare mouse button. On some laptops Print Screen is **Fn** plus another key; look for a key marked *PrtSc*. Wherever these steps say **Print Screen**, press your screenshot key.

**Where screenshots go:** `World of Warcraft\_classic_beta_\Screenshots\`. Rename each one as you take it, with the faction: `01-arrow-horde.png`, `01-arrow-alliance.png`, `02-green-horde.png` … `06-find-alliance.png`.

**A clean chat for the shots** (so it shows no other players' names), without any script: right-click the **General** chat tab > **Create New Window**, name it `Shot`. In its settings (right-click the tab > **Settings**), untick every channel and message type except **Say**. The new tab starts empty and only shows your own Say line. Click the **Shot** tab before each shot, and **General** afterwards.

### A3. What makes a great store screenshot

- **One idea per picture.** Each of the 6 shots shows one feature, and the caption says what it is.
- **The addon is the subject.** Keep its window or arrow big and in the middle. Move other windows out of the way.
- **The world is the backdrop.** A famous place (Stormwind's gate, Thunder Bluff, the Barrens) says "this is WoW" at a glance. WoW Forever's new places (the Ruins of Lordaeron and Hall of Thanes dungeons, Stormwind Harbor, the expanded Wetlands) also show the addon is made for Forever.
- **Readable at thumbnail size.** If you can't read the arrow's distance with the image scaled to a quarter, raise UI Scale or the arrow's Size.
- **Real, not edited.** Crop and resize only. CurseForge requires real in-game screenshots.

---

## Part B: The tests (paladin, Tirisfal Glades)

### 1. First login (5 min)

- ☐ 1.1 In the character select **AddOns** list: **Expect** "Waypoint Tracker" with the arrow icon, the database **grouped under it**, and neither marked "out of date".
- ☐ 1.2 Log in. **Expect:** no Lua errors, and exactly one hello line ("Waypoint Tracker is ready. Type /wp to open it…"). `/reload`: **Expect** no hello the second time.
- ☐ 1.3 No waypoint yet, so **no arrow** on screen.
- ☐ 1.4 Hover the minimap button. **Expect:** a Left-click / Right-click / Drag tooltip.
- ☐ 1.5 In the addon compartment (the button by the minimap), **Expect** Waypoint Tracker listed. Clicking it opens the window.
- ☐ 1.6 `Esc > Options > AddOns > Waypoint Tracker`. **Expect:** a short panel whose **Open Waypoint Tracker** button works.

### 2. The main window (10 min, in Brill)

- ☐ 2.1 `/wp` opens the window, `/wp` again closes it, and **Esc** closes it too.
- ☐ 2.2 Drag the window by its title, then `/reload`. **Expect:** it reopens where you left it.
- ☐ 2.3 Press **Use My Position** (the small button right of the Y box), then **Set Waypoint**. **Expect:**
  - Zone shows Tirisfal Glades, and X/Y are filled in.
  - The arrow appears and the row is added to **Your Waypoints**.
  - One chat line: "Waypoint added: …".
- ☐ 2.4 Type `Silverpine` in Zone. **Expect:** suggestions as you type, and picking one fills the zone.
- ☐ 2.5 Try partial or misspelled names: `tirisfal`, `undercty`, `barrens`, and a Forever zone such as `Riverglades`. **Expect:** sensible matches.
- ☐ 2.6 Type the name of a quest from your log, then `Brill`, then a dungeon (`Scarlet`). **Expect:** tagged results (Quest / Flight master / Dungeon). Clicking one sets a waypoint.
- ☐ 2.7 Paste `45.2 67.8` into X. **Expect:** it splits into X 45.2, Y 67.8. Also try `45,2 67,8` and `45.2, 67.8`.
- ☐ 2.8 X = `150`, then **Set Waypoint**. **Expect:** "X and Y must be numbers from 0 to 100…", fully readable. With X and Y empty: "Type X and Y first."
- ☐ 2.9 Empty the Zone box, type X and Y, then **Set Waypoint**. **Expect:** "Pick a zone first."
- ☐ 2.10 Set a waypoint with Name "Test spot". **Expect:** the name shows in the list and under the arrow.
- ☐ 2.11 Add 8 or more waypoints. **Expect:** the list scrolls with the mouse wheel, and "Scroll for more" shows next to **Remove All**.
- ☐ 2.12 Hover a row for its tooltip, click the row (the arrow points there), then click its **✕** (it's removed).
- ☐ 2.13 **Remove All** with 2 or more waypoints. **Expect:** "Remove all N waypoints?". **No** keeps them. **Yes** clears them, and the arrow goes away. With one waypoint, it's removed without asking.
- ☐ 2.14 Untick and tick **Show the arrow**. Also try minimap right-click and `/wp arrow`. **Expect:** "Arrow off." / "Arrow on."
- ☐ 2.15 Drag **Arrow size** and **Arrow visibility**, then `/reload`. **Expect:** live changes to the arrow only (not its text) that stick.
- ☐ 2.16 Tick **Show more options**. **Expect:** the options panel opens beside the window, and nothing overlaps.

### 3. Slash commands (10 min)

- ☐ 3.1 `/way 42 65`. **Expect:** a waypoint in your current zone.
- ☐ 3.2 `/way Tirisfal Glades 61.7 52.1 Gallows' End Tavern`. **Expect:** a named waypoint in Brill.
- ☐ 3.3 `/way tirisfl 60 50`. **Expect:** it still finds Tirisfal ("Using Tirisfal Glades.") or suggests it.
- ☐ 3.4 `/way Nowhereland 10 10`. **Expect:** "Couldn't find a zone called …".
- ☐ 3.5 `/way 120 50`. **Expect:** a message about the coordinates, no waypoint, no Lua error. `/way abc 50`: **Expect** Find opens on the **All** tab with "abc 50" searched.
- ☐ 3.6 `/way Innkeeper Renee`. **Expect:** exactly one NPC has that name, so the arrow goes straight to her.
- ☐ 3.7 `/way renee`. **Expect:** not exact, so Find opens with "renee" searched.
- ☐ 3.8 `/way Mailbox`. **Expect:** many share the name, so Find opens with the list.
- ☐ 3.9 `/way` alone. **Expect:** the help list.
- ☐ 3.10 `/wp here My camp`. **Expect:** a waypoint where you stand.
- ☐ 3.11 `/wp list`. **Expect:** every waypoint with zone, coordinates and distance.
- ☐ 3.12 `/wp closest` (with 3 or more waypoints). **Expect:** it points to the nearest.
- ☐ 3.13 `/wp clear`, `/wp clear all`, then `/wp clear all` again. **Expect:** removes one, removes all, then "No waypoints yet…".
- ☐ 3.14 `/wp find innkeeper`. **Expect:** Find opens with that search.
- ☐ 3.15 `/wp help`. **Expect:** a readable list of commands.
- ☐ 3.16 `/wayb Test` and `/cway`.
- ☐ 3.17 `Esc > Options > Keybindings > AddOns > Waypoint Tracker`. Bind all 7 actions (including **Share my location in chat**) and try each one.

### 4. The arrow (15 min, Tirisfal Glades)

- ☐ 4.1 Walk south out of Brill on the road toward the Undercity, to about **60.8, 58.0**. The coordinates are under the world map and in the Find box.
- ☐ 4.2 Type:
  ```
  /way Tirisfal Glades 61.9 66.0 Ruins of Lordaeron
  ```
  Open the world map. **Expect:** the pin sits on the ruins.
- ☐ 4.3 Turn on the spot. **Expect:** the arrow turns smoothly and points the right way. The distance (a few hundred yards) shows under it.
- ☐ 4.4 Walk toward the Ruins. **Expect:** the colour moves from gold to green, the distance counts down, and after a moment "About …" shows how long until you arrive. It only shows while you're heading toward the waypoint.
- ☐ 4.5 On arrival. **Expect:** a sound, "You have arrived!" with the spinning arrow, and the waypoint removed with "You reached Ruins of Lordaeron."
- ☐ 4.6 With a mob behind the arrow on screen, right-click it. **Expect:** you target or attack it, because the arrow never takes clicks.
- ☐ 4.7 `/way Silverpine Forest 45 42`. **Expect:** it points across the zone border with a distance.
- ☐ 4.8 `/way Durotar 52 43`. **Expect:** "On another continent", and no wrong direction.
- ☐ 4.9 Take a flight path. **Expect:** the arrow keeps pointing, or hides if **Hide on flight paths** is on.
- ☐ 4.10 Enter a dungeon (the Ruins of Lordaeron or Shadowfang Keep). **Expect:** "Can't track from here" or the arrow hides, with no errors.
- ☐ 4.11 **Move Arrow** in the window: drag it, click **Done**, then `/reload`. **Expect:** it stays put. Dragging the text moves the arrow with it.
- ☐ 4.12 Change **Arrow size** and **Arrow visibility**, then press **Reset** in the window. **Expect:** the arrow goes back over your character **and** back to 100% size and 80% visibility.
- ☐ 4.13 **Use My Position**, then **Set Waypoint** (or `/wp here`). **Expect:** the waypoint is **not** removed. The arrow shows a pin and "You're here".
- ☐ 4.14 Walk about 30 yds away. **Expect:** the arrow points back at it. Walk back onto it. **Expect:** now "You have arrived!" and it's removed.

### 5. Edit Mode (10 min, Brill square)

- ☐ 5.1 `Esc > Edit Mode`. **Expect:** the arrow gets the game's blue box labelled "Waypoint Arrow", and spins as a preview even without a waypoint.
- ☐ 5.2 Click the arrow's box. **Expect:** it turns yellow, and a panel opens beside it with **Arrow size**, **Arrow visibility**, **Text size**, **Text visibility**, **Move the text separately**, **Reset** and **More Options**.
- ☐ 5.3 Click Blizzard's minimap box. **Expect:** the arrow deselects and its panel closes.
- ☐ 5.4 Drag the arrow to a corner. **Expect:** smooth movement, and the panel follows.
- ☐ 5.5 Change Size and Visibility in the panel. **Expect:** the arrow changes live, and the main window's sliders match.
- ☐ 5.6 **More Options** in the panel. **Expect:** the main window opens with the options panel.
- ☐ 5.7 Exit Edit Mode (with or without **Save**). **Expect:** the arrow keeps its spot and settings, because they apply the moment you change them (Save is only needed for Blizzard's own frames). The blue box is gone, and clicks pass through the arrow again.
- ☐ 5.8 Switch layouts (Modern ↔ Classic, or make a new one). **Expect:** each layout remembers its own arrow spot.
- ☐ 5.9 `/reload` on each layout. **Expect:** the right spot for the active layout.
- ☐ 5.10 **Taint check:**
  1. `/console taintLog 1`, then `/reload`.
  2. Enter Edit Mode, select the arrow, click an action bar, save and exit.
  3. Fight something, open your spellbook and talents, and use your bars.

  **Expect:** nothing unusual. Your bars work, and no "Interface action failed because of an AddOn" message appears. If everything just works, that's a **pass**. For extra certainty, open `World of Warcraft\_classic_beta_\Logs\taint.log` after logging out: it shouldn't mention WaypointTracker. Then `/console taintLog 0`.
- ☐ 5.11 In the panel, tick **Move the text separately**. **Expect:** the text stays where it is, and gets its own blue box ("Waypoint Text"). Drag the text box somewhere else. **Expect:** only the text moves; the arrow stays.
- ☐ 5.12 Click the text's box. **Expect:** it's selected, with the same panel. Change **Text size** and **Text visibility**. **Expect:** only the text changes.
- ☐ 5.13 Untick **Move the text separately**. **Expect:** the text's box goes away and the text jumps back under the arrow. Tick it again. **Expect:** the text goes back to where you dragged it.
- ☐ 5.14 Switch layouts. **Expect:** the text, like the arrow, has its own spot per layout.
- ☐ 5.15 Press **Reset** in the panel. **Expect:** the arrow back over your character, the text under it (Move the text separately unticked), and every size and visibility back to its default (arrow 100% / 80%, text 100% / 90%).

### 6. Maps and more options (20 min)

Keep **Show more options** open while you test. Each option should work **and still apply after `/reload`**.

- ☐ 6.1 **Show the waypoint name** · **Show the distance** · **Show time to arrive**: each turns its line on and off.
- ☐ 6.2 **Fade when heading the right way**: on, facing the waypoint makes the arrow faint.
- ☐ 6.3 **Hide during combat** (start a fight) · **Hide on flight paths**.
- ☐ 6.3a **Arrow Text** section: **Text size**, **Text visibility** and **Move the text separately** match the Edit Mode panel, and change the text live.
- ☐ 6.4 **Colour**: try *Gold far away, green close* · *Green when facing it* · *One colour* with **Pick colour** (the colour should stick after `/reload`). End on *Gold far away, green close*.
- ☐ 6.5 **Arrival distance** at 50 yds. **Expect:** you arrive earlier. Put it back to 10.
- ☐ 6.6 **Remove the waypoint** off: it stays after arriving. **Play a sound** off: silent. Turn both back on.
- ☐ 6.7 **Then point to the next closest waypoint**: with 3 waypoints, arriving moves the arrow to the nearest remaining one.
- ☐ 6.8 Set up a route:
  ```
  /wp clear all
  /way Tirisfal Glades 32.0 65.0 Deathknell
  /way Tirisfal Glades 61.7 52.1 Gallows' End Tavern
  /way Tirisfal Glades 61.9 66.0 Ruins of Lordaeron
  ```
  **World map pins**: hover for a tooltip (name, zone, coordinates, distance, "Click: point the arrow here / Alt-click: remove"), click to point the arrow, **Alt-click** to remove. Shift-click does **not** remove.
- ☐ 6.9 **Minimap pins** · **Keep the arrow's waypoint on the minimap edge** (walk away and the pin rides the edge).
- ☐ 6.10 **Coordinates on the world map**: You and Cursor show at the bottom.
- ☐ 6.11 **Ctrl + Right-click the map** adds a waypoint there. Turn the option off and it doesn't.
- ☐ 6.12 **Show a box with my coordinates**: a movable box that updates as you walk.
- ☐ 6.13 **Follow the game's map pins**: place Blizzard's pin on the map, and the arrow follows it.
- ☐ 6.14 **Point to the quest I'm tracking**: track a quest, and the arrow goes to its objective or hand-in.
- ☐ 6.14a **Point to my corpse when I die** (on by default): set a waypoint, then die (fight something far above your level, or jump from a height). **Expect:** a waypoint "Your corpse" on your body, and the arrow points at it. Release your spirit. **Expect:** the arrow leads you back to your body. Resurrect. **Expect:** the corpse waypoint is gone and the arrow points to the waypoint you had before.
- ☐ 6.14b Turn it off and die again. **Expect:** no corpse waypoint. Turn it back on.
- ☐ 6.15 **Always point to the closest waypoint**: walk around the route, and it switches to the nearest.
- ☐ 6.16 **Remember waypoints after logging out**: log out and in, and they're kept. Turn it off, log out and in, and they're gone. Turn it back on.
- ☐ 6.17 **Show the minimap button** off: the button hides, and `/wp` still works.
- ☐ 6.18 **Show chat messages** off: no chat lines. Turn it back **on**.
- ☐ 6.19 **Use metres**: m and km.
- ☐ 6.20 **Let other addons set waypoints**: toggling it prints "Type /reload for this change to take effect."
- ☐ 6.21 **Also show the game's own map pin**: Blizzard's pin and floating marker appear on the arrow's waypoint.
- ☐ 6.22 **Reset All Settings** is covered at the very end (Part D), so the shoot settings survive until then.

### 7. Sharing (15 min, Brill)

- ☐ 7.1 **Share** on a waypoint row. **Expect:** a menu with Party / Raid / Guild (only the ones you can use) / Say / Whisper *target* / Just put it in my chat box.
- ☐ 7.2 **Just put it in my chat box**, then send in **Say**. **Expect:** a clickable map pin link, and no error or disconnect.
- ☐ 7.3 Shift-click a row. **Expect:** it goes into the open chat box.
- ☐ 7.4 `/reload`, then click the map pin link in chat. **Expect:** no Lua error, even on this first click. The game's pin is set with its floating marker, the map opens on it, and the arrow points there. If you can, have a friend who uses the addon click it too.
- ☐ 7.5 A waypoint named `Test | "quote" 😀`: share it. **Expect:** it sends fine, with no disconnect.
- ☐ 7.6 **Share without a waypoint:**
  1. In the window, type Zone `Tirisfal Glades`, X `61.7`, Y `52.1`, Name `Meet at Gallows' End Tavern`.
  2. Press **Share** (next to Set Waypoint), pick **Say** and send.

  **Expect:** "Meet at Gallows' End Tavern: [map pin] Tirisfal Glades (61.7, 52.1)", with **no new row** in Your Waypoints.
- ☐ 7.7 Empty X and Y, then **Share**. **Expect:** your current spot is shared, with no waypoint added.
- ☐ 7.8 X = 150, then **Share**. **Expect:** the error, and no menu.
- ☐ 7.9 Type each of these in chat and press Enter: `/wp share`, then `/wp share Tirisfal Glades 62 66 Meet at the Ruins`, then `/wp share Here!`. **Expect:** after each one, the chat box opens again with the message ready (your spot, "Meet at the Ruins: …", then "Here!: …"). Press Enter to send it, or Esc to drop it.
- ☐ 7.10 In a dungeon, `/wp share` and **Share** with empty X/Y. **Expect:** "The game doesn't share your position here…", and no error.

### 8. Find (20 min)

- ☐ 8.1 Click **Quests** next to "Find:". **Expect:** Find opens on the Quests tab. The first open may take a second while the database loads. Close it, then `/wp find`. **Expect:** it opens on **All**.
- ☐ 8.2 Type `renee`. **Expect:** results as you type, with distances. The typo `renne` still finds her.
- ☐ 8.3 Tabs: All · Quests · NPCs (friendly) · Enemies (with level and elite/rare/boss) · Objects · Items. **All** also lists flight paths and towns.
- ☐ 8.4 **Only my faction** on. **Expect:** no Alliance quests or friendly Alliance NPCs.
- ☐ 8.5 **Only this zone**. **Expect:** only Tirisfal things.
- ☐ 8.6 Enemies tab, type `ressan`. **Expect:** Ressan the Needler, a level 11 Tirisfal rare, tagged **Rare**. Double-click: the arrow points to his spawn (around 43.6, 67.0).
- ☐ 8.7 Items tab, type `Scarlet Armband`. **Expect:** its quality colour and type, "Needed for: The Scarlet Crusade", and "Dropped by: Scarlet Convert, Scarlet Initiate, Meven Korgal". **Go to nearest source** points the arrow at the closest of them.
  - Then type `Runes of the Sorcerer-Kings`, a Season of Discovery item. **Expect:** its description, and "No drop source is known for this yet…". That's correct: Find only knows item sources from its database and from what you loot yourself, and neither has this one. It's needed by a Mage quest, so a paladin won't see a "Needed for" line.
- ☐ 8.8 All six **Nearest** buttons (Mailbox, Innkeeper, Flight Master, Repair, Bank, Auction House). **Expect:** each points to the closest Horde one, or says none is known.
- ☐ 8.9 Pick a quest in your log, ideally a WoW Forever one such as "Watching the Roads". Click it on the Quests tab. **Expect:** "In your quest log", and **Go to objective** (or **Go to hand in**, when it's complete) is clickable and points where the game's map shows the quest. **Go to quest giver** works when the giver is known. When nothing is known yet, a grey line explains when the buttons light up.
- ☐ 8.10 **The quest-name scan:** the first time you log in with the addon (and again if you change the game's language), it learns WoW Forever's quest names in the background. It starts about 20 seconds after login and takes roughly 10 minutes.
  - While it runs, open Find. **Expect:** the line at the bottom says "Learning WoW Forever's quest names in the background (NN%)…" and the number goes up. A search that finds nothing adds "Still learning WoW Forever's quest names…".
  - When it's done, search a WoW Forever-only quest name. **Expect:** found, in your language. The bottom line goes back to the tip about double-clicking.
  - After `/reload`, the progress line doesn't come back. Later scans only pick up names the game didn't know before, and run quietly.
  - ⚠️ You've already finished a scan in earlier sessions, but the addon only started remembering that in this build. So you'll see the progress line one more time, and after that never again.
- ☐ 8.11 Search `zzzzqqq`. **Expect:** "Nothing found. Try fewer letters, the All tab, or untick Only this zone."
- ☐ 8.12 Search `sword of thunderfurry`. **Expect:** results in well under a second, and no stutter while typing.
- ☐ 8.13 In the AddOns list, disable **WaypointTracker_Data**, then `/reload` and open Find. **Expect:** a readable message in the list area explaining the database is missing and how to fix it, and your discoveries still search. Enable it again and `/reload`.

### 9. Learning, correcting and sharing discoveries (30 min)

Before you start: close the game and copy `WTF/Account/<account>/SavedVariables/WaypointTracker.lua` somewhere safe (copy it back afterwards to undo the test). In game, make sure **Learn NPCs, quests and objects as I play** is ticked in **Show more options**, press **Shift+V** so friendly nameplates show, and open Find once (`/wp find`) so its database is loaded. Note the number after **Discoveries:** at the bottom of Find.

**Recording (stays on your computer)**
- ☐ 9.1 Walk past a WoW Forever NPC that Find doesn't know yet, within about 25 yards, without clicking it (Horde: Gor'mak, The Barrens 49.8, 29.6, just outside the Crossroads' west gate). Wait 3 seconds, then search it in Find > **NPCs**. **Expect:** found, with its title in grey (`<Blacksmith>`), its zone, and blue "Discovered by you". **Discoveries** went up by 1.
- ☐ 9.2 Walk right up to it (a few yards), then double-click it in Find from 100+ yards away. **Expect:** the arrow leads to within about 10 yards of it.
- ☐ 9.3 Search `blacksmith`. **Expect:** it's listed, with other titled NPCs you've passed.
- ☐ 9.4 Open its vendor window, close it, and search one of its items in Find > **Items**. **Expect:** "Sold by: <the vendor>", and double-clicking points the arrow at the vendor.
- ☐ 9.5 Walk past a city guard with no title, standing where Find already has guards. Wait 10 seconds. **Expect:** **Discoveries** doesn't go up for it, and its name isn't in the **Share discoveries** text (only what's new is kept).
- ☐ 9.6 Stand near other players, their pets, and a rabbit or squirrel. **Expect:** none of them in Find or in the share text.
- ☐ 9.7 Fight a few enemies next to NPCs in a town or camp. **Expect:** no error, no "blocked" message, no stutter. After the fight, nearby new NPCs show up in Find.
- ☐ 9.8 Untick learning, walk past another new NPC, search it. **Expect:** not found; **Discoveries** unchanged. Tick it again.
- ☐ 9.9 `/reload`, then search the NPC from 9.1. **Expect:** still found with its title.

**Correcting a spot**
- ☐ 9.10 In Find, select any NPC you can see nearby and press **Wrong spot? Correct it**. **Expect:** a box saying where Find has it (zone, X, Y).
- ☐ 9.11 Walk 30+ yards away, press **Use My Position**, then **Save correction**. **Expect:** "Saved…", blue "Spot corrected by you" in the details, and double-clicking it sends the arrow to where you stood.
- ☐ 9.12 Open the box again, type `45,2` and `67.8`, save. **Expect:** the arrow goes to 45.2, 67.8 on that map.
- ☐ 9.13 Type `abc` in X and save. **Expect:** "Type X and Y from 0 to 100…", nothing changes.
- ☐ 9.14 **It's not there**. **Expect:** that spot is gone from Find (no location if it was the only one).
- ☐ 9.15 **Remove my correction**. **Expect:** Find's own spot is back; the blue line is gone.
- ☐ 9.16 Make one correction again and `/reload`. **Expect:** still corrected.

**Sharing (only when you choose)**
- ☐ 9.17 Play for a while. **Expect:** nothing is ever posted to chat or sent anywhere, and no window opens by itself.
- ☐ 9.18 **Share discoveries**. **Expect:** the text is pre-selected and starts with `WTL1`. It has a line for the NPC from 9.1 ending in its title, a line for the vendor's items, and a line starting with `C` for your correction. Ctrl+C copies it.
- ☐ 9.19 Paste it into a text editor. **Expect:** only NPC, item and quest names, numbers and places: no character name, realm or account.
- ☐ 9.20 Open the "Share discoveries" issue form on GitHub in your browser and paste it. **Expect:** it fits (you can close the page without submitting).
- ☐ 9.21 **Import** your own share text. **Expect:** "Discoveries added: N", and **Discoveries** doesn't change (nothing doubles up).
- ☐ 9.22 Import `hello world`. **Expect:** "That doesn't look like shared discoveries."
- ☐ 9.23 Close the game and open the saved file in a text editor. **Expect:** your new NPC (with `"title"`), the vendor's items, and `"fixes"` for your correction; no guards or other things Find already had.

### 10. Saving and reloading (10 min)

- ☐ 10.1 Set 3 waypoints, change 3 settings, move the arrow, then `/reload`. **Expect:** all kept.
- ☐ 10.2 Log out and in. **Expect:** all kept.
- ☐ 10.3 Log in on an alt. **Expect:** settings shared, waypoints per character.
- ☐ 10.4 **Quit the game completely** and start it again. **Expect:** all kept. This catches saved-file bugs.

### 11. Other addons (10 min)

- ☐ 11.1 Turn on the other waypoint-arrow addon you use (the one that owns `/way`) and `/reload`. **Expect:**
  - One line: "Another addon already uses /way, so use /wp instead."
  - No double arrow.
  - `/wp help` shows `/wp …` commands instead of `/way …`.
- ☐ 11.2 Turn that addon off again. With a quest guide that can send waypoints to an arrow, send one. **Expect:** it appears in Waypoint Tracker.
- ☐ 11.3 **Let other addons set waypoints** off (and `/reload`). **Expect:** the guide's waypoints don't arrive.
- ☐ 11.4 Play 10 minutes with your usual addons. **Expect:** no errors, and the arrow stays visible.

### 12. Languages and performance (15 min)

- ☐ 12.1 Switch the game language (Battle.net → Game Settings → Text Language), e.g. Deutsch. **Expect:**
  - Everything is translated: window, Find, Edit Mode panel, tooltips and chat.
  - Nothing is cut off or overlapping (check the Find tabs and the Nearest row).
- ☐ 12.2 In German: `/way Tirisfal 60 50`, and search an NPC by its German name. **Expect:** both work.
- ☐ 12.3 `Ctrl+R` in the Undercity. **Expect:** no FPS drop with the arrow showing, compared with the addon off.
- ☐ 12.4 Add 50 waypoints (paste `/way 1 1` repeatedly). **Expect:** no lag, and `/wp clear all` handles it.
- ☐ 12.5 Play 30 minutes normally. **Expect:** no errors or slowdown.

---

## Part C: The photo tour (about 1½ hours)

Six shots, each with a 🟥 **Horde** option for your paladin and a 🟦 **Alliance** option for your mage. The places are the ones level 20 players actually spend time in: the capitals, the Barrens, the Wetlands, and WoW Forever's two new low-level dungeons. The coordinates come from the WoW Forever game files.

**The two routes** (each follows the order of travel, not the shot numbers):

| | Route | Shots |
|---|---|---|
| 🟥 Paladin | Brill → **Ruins of Lordaeron** → zeppelin to **Orgrimmar** → fly to **the Crossroads** → fly to **Thunder Bluff** | 2 → 5 → 4 and 6 → 1 and 3 |
| 🟦 Mage | Teleport: Stormwind → **Stormwind's gate** and **Stormwind Harbor** → Teleport: Ironforge → **Hall of Thanes** → fly to **Menethil Harbor** | 1, 3 and 5 → 2 → 4 and 6 |

**Addon settings for the whole tour.** On each character, open `/wp`, tick **Show more options** and set:

- **Arrow size 125%** and **Arrow visibility 100%**
- In the **Arrow Text** section: **Text size 110%** and **Text visibility 100%**, so the name and distance read well in a thumbnail
- **Show time to arrive**: on
- **Fade when you're heading the right way**: **off** (otherwise the arrow goes faint in exactly the pose you want)
- Colour: **Gold far away, green close**

Then close both windows.

**The trick for perfect arrow shots: mark first, then back off.** Stand exactly on the landmark and type `/wp here <name>`. The waypoint is now precisely on it. Then walk or ride back to where the camera should be. This beats typed coordinates, because it lands on the exact spot you want in the picture.

**Every arrow shot, the same way:**

1. Put the landmark **slightly right of centre**, so the arrow points forward-right. It looks more alive than straight up.
2. Hold the right mouse button and orbit the camera **behind and a little above** your character. Scroll out until your character fills the bottom third and the landmark sits in the top third.
3. Close every window. Click the **Shot** chat tab (A2).
4. Walk toward the landmark (**Num Lock** keeps you walking with your hands free). "About …" only shows while you're heading toward the waypoint. Check that the name, distance and "About …" are readable, and that the arrow sits clear of your character's body. If it doesn't, scroll out, or drag the arrow just above your head in Edit Mode.
5. **Print Screen** while you're walking. Take 3–4 variations (closer or wider, mounted or on foot). Keep the best.

⚠️ Daylight looks best. Hover the minimap clock; if it's night, do the city shots (3 and 5) first and come back.

---

### 📸 1: "The arrow" (the hero shot)

**Goal:** a big **gold** arrow over your character, pointing at a famous landmark on the horizon, with name, distance and time to arrive.

> **🟦 Alliance: Stormwind's main gate** (the most famous view in WoW; the best hero shot)
>
> 1. Ride out of Stormwind through the main gate into Elwynn Forest. Stop in the middle of the road right in front of the gate. The Elwynn Forest map labels it "Stormwind" at about **33.7, 52.5**.
> 2. `/wp here Stormwind Gate`
> 3. Ride south down the road about **150–200 yds**, until the gate, the walls and the towers fit in the top half of the screen. Turn to face the gate.
> 4. Shoot as above. Save as `01-arrow-alliance`.

> **🟥 Horde: Thunder Bluff from the plains of Mulgore**
>
> 1. Fly to Thunder Bluff and take a lift down to Mulgore. Stand at the foot of the lift. The Mulgore map labels Thunder Bluff at about **39.8, 35.9**. WoW Forever reshaped Mulgore's map, so trust what you see over any old guide.
> 2. `/wp here Thunder Bluff`
> 3. Ride away (south-east, along the road) about **200 yds**, until the mesas with their bridges and totems fill the top of the screen. Turn to face them.
> 4. Mulgore's golden grass can swallow a gold arrow. Raise the camera a little so the arrow sits against the cliffs or the sky.
> 5. Shoot as above. Save as `01-arrow-horde`.

### 📸 2: "Gold to green"

**Goal:** close to the landmark. A bright **green** arrow reading about **15–25 yds**, with the landmark towering behind.

> **🟥 Horde: the Ruins of Lordaeron** (WoW Forever's new level 15–20 dungeon, above the Undercity)
>
> 1. Walk up to the ruins' front gate (Tirisfal Glades, about **61.9, 66.0**). `/wp here Ruins of Lordaeron`
> 2. Walk back out about 40 yds, then walk toward the gate again. Stop when the arrow is bright green at 15–25 yds.
> 3. Turn the camera so the gate and broken walls fill the background, with your paladin lower-centre.
> 4. **Print Screen**. Save as `02-green-horde`.

> **🟦 Alliance: the Hall of Thanes** (WoW Forever's new level 13–18 dungeon, beneath Ironforge)
>
> 1. Teleport to Ironforge. Enter the High Seat (King Magni, Ironforge **39.4, 55.8**), take the open passage on the left, and go down through Old Ironforge to the dungeon portal.
> 2. Stand at the portal: `/wp here Hall of Thanes`
> 3. Walk back up the passage about 40 yds, then walk toward the portal again. Stop at 15–25 yds, bright green.
> 4. Frame the portal and the old stonework behind your mage. If the camera bumps into walls indoors, zoom in a little.
> 5. **Print Screen**. Save as `02-green-alliance`.
>
> *If Old Ironforge is too dark or cramped:* do the same at the door of the Lion's Pride Inn in Goldshire (Elwynn Forest **43.8, 65.9**).

**Bonus for either:** keep walking onto the spot. "You have arrived!" appears with the spinning arrow. Grab it as `02b-arrived-horde` or `02b-arrived-alliance`; it may beat the green shot.

### 📸 3: "Built into Edit Mode"

**Goal:** Edit Mode open, the arrow **selected** (yellow) with its settings panel, and Blizzard's frames showing blue boxes around it, over a scenic backdrop. It shows the addon is a native part of the HUD.

> **🟥 Horde: the edge of Thunder Bluff.** Stand at the edge of the High Rise, near Cairne Bloodhoof (Thunder Bluff **59.8, 51.6**), and turn the camera out over the edge so the plains of Mulgore fill the background.

> **🟦 Alliance: Stormwind Harbor**, WoW Forever's rebuilt harbour (Stormwind City **42.2, 49.9**). Stand on a quay with a ship behind you.

Then, for either:

1. `Esc > Edit Mode`, and click the arrow's box. It turns yellow, and its panel (arrow and text sliders, Move the text separately, Reset, More Options) opens beside it.
2. Drag the arrow a little up and right of your character, so the panel doesn't cover the player frame.
3. **Print Screen**. Save as `03-editmode-horde` or `03-editmode-alliance`.
4. Drag the arrow back over your character (don't press **Reset**: it would also undo the tour's size settings). Then exit Edit Mode.

### 📸 4: "Your route on the map"

**Goal:** a whole zone's world map with 5 named pins spread across it, one pin's tooltip showing, and the **You / Cursor** coordinates at the bottom.

> **🟥 Horde: the Barrens**, from the Crossroads. Paste:
> ```
> /wp clear all
> /way The Barrens 52.1 30.6 The Crossroads
> /way The Barrens 46.0 36.3 Wailing Caverns
> /way The Barrens 62.2 37.9 Ratchet
> /way The Barrens 49.3 50.3 Mankrik's wife
> /way The Barrens 44.8 58.7 Camp Taurajo
> ```
> Stand in the Crossroads and hover the **Mankrik's wife** pin. Every Horde player knows that joke.

> **🟦 Alliance: the Wetlands** (WoW Forever added 25+ quests here), from Menethil Harbor. Paste:
> ```
> /wp clear all
> /way Wetlands 10.6 55.3 Menethil Harbor
> /way Wetlands 47.4 16.8 Dun Modr
> /way Wetlands 48.0 74.1 Dun Algaz
> /way Wetlands 74.0 69.2 Grim Batol
> ```
> For a fifth pin, type `Excavation` in the window's **Zone** box. If the list offers WoW Forever's new **Excavation Site** dungeon, click it. If not, 4 pins are fine. Stand in Menethil Harbor and hover the **Grim Batol** pin.

Then, for either:

1. Open the map (**M**) and check each pin sits on its place. If one is off, hover the right spot, read **Cursor** at the bottom of the map, **Alt-click** the wrong pin, and redo that `/way` with the right numbers.
2. Show the whole zone at a comfortable size, and hover the pin named above until its tooltip shows name, zone, coordinates, distance, and "Click: point the arrow here / Alt-click: remove".
3. Check the minimap (top right) shows nearby pins too.
4. **Print Screen**. Save as `04-map-horde` or `04-map-alliance`.

### 📸 5: "Share any spot, no waypoint needed"

**Goal:** the window with a far-away spot typed in, the **Share menu open** next to it, and the sent message with its clickable map pin in chat. The typed spot is in another zone, which shows you can share any place without going there.

> **🟥 Horde: Orgrimmar**, in the Valley of Strength by the inn (Orgrimmar **54.1, 68.4**). Type Zone `Stranglethorn Vale`, X `26.8`, Y `77.0`, Name `Meet me in Booty Bay`.

> **🟦 Alliance: Stormwind Harbor** (Stormwind City **42.2, 49.9**). Type Zone `Wetlands`, X `10.6`, Y `55.3`, Name `Meet at Menethil Harbor`.

Then, for either:

1. Find a quiet corner, away from other players. Click the **Shot** chat tab (A2).
2. Press **Share**, pick **Say** and send, so exactly one clean line with the map pin is in chat.
3. Keep the same zone, X, Y and Name in the window. Make sure **Your Waypoints** shows 2–3 tidy named rows (the route from 📸 4 is ideal, or `/wp here` a couple of spots).
4. Move the window so it and the chat box are both on screen, with the arrow visible over your character.
5. Press **Share** again so the menu opens. Hover **Say** so it's highlighted.
6. **Print Screen**. Save as `05-share-horde` or `05-share-alliance`.

⚠️ Your character name shows in the chat line ("[Name] says:"). Keep it, or crop it out.

### 📸 6: "Find anything, and go to it"

**Goal:** the Find window with a quest selected. The details show "In your quest log", who gives it, what it needs, and the three buttons (**Go to quest giver**, **Go to objective**, **Go to hand in**), while the arrow points the way in the world behind it.

> **🟥 Horde: "Lost in Battle"** (Mankrik's wife), from the Crossroads. `/wp find lost in battle`. It's even better if it's in your quest log. If you've done it, pick a quest from your log in the Barrens, Stonetalon or Ashenvale.

> **🟦 Alliance: a Wetlands quest from your log**, ideally one of WoW Forever's new ones, from Menethil Harbor. `/wp find <the quest's name>`.

⚠️ If the line at the bottom of Find says "Learning WoW Forever's quest names…", wait until it's gone (about 10 minutes after logging in) so the shot shows the usual tip.

Then, for either:

1. On the **Quests** tab, click the quest. Search only 1–2 words of its name, so a few similar quests show in the list too.
2. Press **Go to objective**. The arrow now points there.
3. Keep **Only my faction** ticked. The **Nearest:** buttons show at the top.
4. Drag Find so it covers the left or right two thirds of the screen, and the arrow over your character stays visible.
5. **Print Screen**. Save as `06-find-horde` or `06-find-alliance`.

---

### Extra places, for swaps or bonus shots

All of these are flight paths or towns. The coordinates come from the game files. Where the zone is above level 20, fly in and stay in town.

| Place | Who | Where | Good for |
|---|---|---|---|
| **Booty Bay**, Stranglethorn Vale | Both | Flight master **26.8, 77.0** (Horde) or **27.5, 77.7** (Alliance) | A hero shot pointing across the bay. The zone is level 30–45, so stay inside the town. |
| **Orgrimmar's front gate**, Durotar | 🟥 | Durotar **45.6, 12.1** | A red-canyon hero shot, mark first then back off down the road |
| **Ironforge's gate**, Dun Morogh | 🟦 | Dun Morogh **53.5, 34.8** | A snowy hero shot. The gold arrow stands out well on snow. |
| **Bandarion Keep**, Tirisfal Glades | 🟥 paladin | North-west Tirisfal, in the Whispering Wood | The Forsaken paladins' keep, which is new in WoW Forever and a great fit for your character |
| **Desolace** | Both | **Shadowprey Village** flight master **21.6, 74.0** (Horde), **Nijel's Point** **64.7, 10.4** (Alliance), **Maraudon** **29.2, 62.5** | A striking barren landscape. The zone is level 30–40, so stay near town. |
| **Grom'gol**, Stranglethorn Vale | 🟥 | **32.5, 29.3** | Jungle backdrop, with the zeppelin to Orgrimmar |
| **Freewind Post**, Thousand Needles | 🟥 | **45.0, 49.1** | Tall mesas with rope bridges |
| **Tidegear Coast**, Dun Morogh | 🟦 | Flight master **19.0, 15.2** | A flight path that's new in WoW Forever |
| **The boat from Stormwind Harbor to Auberdine** | 🟦 | Auberdine, Darkshore **36.4, 45.6** | A new WoW Forever route. Point the arrow at Auberdine from the deck. |

---

## Part D: After the shoot

### Put things back (5 min, on each character)

- ☐ D.1 **Reset All Settings** (in the options). **Expect:** it asks first. **No** changes nothing. **Yes** restores the defaults (arrow 100% / 80%, text 100% / 90%, text under the arrow, fade on) and keeps your waypoints.
- ☐ D.2 Turn **My Name**, **Friendly Players** names, nameplates (Shift+V / Ctrl+V) and floating combat text back on.

### Choose and prepare the 6 images

Pick the better faction version of each shot. Aim for a mix, three Horde and three Alliance, so both sides see themselves on the page. A good default:

| Order on CurseForge | Pick | Title | Description |
|---|---|---|---|
| 1 | `01-arrow-alliance` (Stormwind's gate) | The arrow | A solid 3D arrow over your character points to your waypoint, with its distance and time to arrive. |
| 2 | `05-share-alliance` | Share any spot | Share coordinates or where you are in chat, with a clickable map pin. No waypoint needed. |
| 3 | `06-find-horde` | Find anything | Search quests, NPCs, enemies, objects and items, and go straight to the closest one. |
| 4 | `04-map-horde` (the Barrens) | Your route on the map | Your waypoints on the world map and minimap, with coordinates under the map. |
| 5 | `02-green-horde` (or `02b-arrived-horde`) | Gold to green | The arrow turns from gold to green as you get close, and tells you when you've arrived. |
| 6 | `03-editmode-alliance` or `-horde` | Built into Edit Mode | Move and size the arrow in the game's own Edit Mode, with a spot for each layout. |

- **Crop only.** Keep 16:9. The arrow or window should be the clear subject.
- **Size:** keep the full resolution. If a PNG is over about 5 MB, save it as JPG at quality 90–95.
- **No edits** to the UI or the world. They must stay real in-game screenshots.
- Check each image at a quarter of its size. The arrow's distance and the window titles should still be readable.
- `docs/screenshots/` already has `01-arrow.jpg`, `02-map.jpg` and `03-window.jpg`. Add new shots after them (`04-share.jpg`, `05-find.jpg` and so on), list them in `docs/screenshots/README.md`, and add them to the README and the CurseForge gallery.

### Reporting a failure

For each failure write: **step number · where (zone, coordinates) · what you did · what you expected · what happened · the Lua error text, if any**. Attach a screenshot for layout problems.

**Copying a Lua error:** in the error window, click in the text, press **Ctrl+A** then **Ctrl+C**, and paste it into your notes. If that doesn't work, take a screenshot of the window. The first few lines are the part that matters: the message and the file names with line numbers. The addon shows each different error only once per session, so a problem that repeats may not show the window again.

---

## Quick reference: every command

| Command | What it does |
|---|---|
| `/wp` `/waypoint` `/waypointtracker` | Open or close the window |
| `/wp help` or `/way` | The help list |
| `/way X Y [name]` | Waypoint in your current zone |
| `/way <zone> X Y [name]` | Waypoint in a zone |
| `/way <name>` | Exact name goes straight there, otherwise Find opens |
| `/wp here [name]`, `/wayb [name]` | Waypoint where you stand |
| `/wp share [zone X Y] [name]` | Share a spot (or where you are) in chat, with no waypoint |
| `/wp list` | List your waypoints |
| `/wp clear`, `/wp clear all` | Remove one, or all |
| `/wp closest`, `/cway` | Point to the nearest waypoint |
| `/wp arrow` | Show or hide the arrow |
| `/wp find [name]` | Open Find |
| `/wp options` | Open the window |
