# Changelog

## 1.1.0

**Treasure hunt**
- Tick **Treasure hunt** in the window, type `/wp treasure`, or set a key binding. Chests, rare spawns and other markers the game shows near you get a ping the moment they appear: a sound, a message on screen and a blinking taskbar icon if you're in another window.
- The arrow points straight at it, follows a rare that wanders, and lets go once it's taken, killed or gone, then returns to your own waypoint.
- Rares come from your minimap, nameplates and target, placed at their known spawn. Ones someone else is already fighting are left out.
- A chest right in front of you pings too, and looting it clears it.
- **Lead me to known chest spots** walks you from one known chest spawn to the next while nothing has appeared.
- Each part has its own switch under **Show more options → Treasure Hunt**.

**Everything else**
- Find searches smoothly for any name, including ones it hasn't learned yet, and places every spot cleanly on the map in WoW Forever's zones.
- `/way`, `/wayb` and `/cway` go to whichever addon already uses them, and `/wp` does the same things.
- Each release includes a `release.json`, so addon managers install the WoW Forever build directly.

## 1.0.0

First release for WoW Forever.

**The arrow**
- A 3D arrow over your character points to your waypoint, with its name, distance and time to arrive underneath. It turns from gold to green as you get closer.
- It never catches mouse clicks, so right-click to attack always works.
- Move it with **Move Arrow** in the window or in the game's **Edit Mode** (Esc > Edit Mode), where each layout keeps its own spot. **Reset** brings back its default place, size and visibility.
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
- "Show more options" for the rest: fade when on course, hide in combat or on flight paths, colour styles, arrival distance, metres, a coordinates box, the game's own map pin, and more.
- Translated into German, French, Spanish, Portuguese, Russian, Korean and Chinese (Simplified and Traditional).
