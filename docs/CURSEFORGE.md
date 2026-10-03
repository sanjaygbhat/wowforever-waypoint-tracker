# Waypoint Tracker

**Set a waypoint. Follow the arrow. That's it.**

A 3D arrow points the way in World of Warcraft: Forever (WoW Forever). Set coordinates, find a quest, NPC or item by name, and share a spot with friends as a clickable chat pin.

[![A green waypoint arrow over a flying character near Grol'dom Farm, with Trade Rep, 932 yds and About 0:30 beneath it](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/01-arrow.jpg)](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/01-arrow.jpg)

*In the game: flying near Grol'dom Farm with “Trade Rep”, distance and estimated travel time beneath the arrow. Open the image for a full-size view.*

## Your first waypoint

1. Type `/wp` to open the window.
2. Type `/way 42 65` to set a destination in your current zone.
3. Follow the arrow. It turns from gold to green as you get closer and never catches mouse clicks. On arrival it plays a sound, clears the waypoint and points to the next closest one.

## Set, find and share

### Set a spot on the map

Hold **Ctrl** and **right-click** the world map. Or use `/way Westfall 56.3 47.1 Sentinel Hill` to set a named waypoint in another zone. In the window, choose a zone, enter X/Y and press **Set Waypoint**. Paste `45.2 67.8` or `45,2 67,8` into X to fill both fields.

[![Silverpine Forest world map with waypoint pins and a gold arrow pointing toward Lady Sylvanas Windrunner, 777 yds away](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/02-map.jpg)](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/02-map.jpg)

*In the game: waypoint pins on the Silverpine Forest world map, with the arrow pointing toward Lady Sylvanas Windrunner, 777 yds away. Open the image for a full-size view.*

### Find your destination

Press **Quests**, **NPCs**, **Enemies** or **Objects** beside **Find:**, or type `/wp find hogger`. Search quests, NPCs, enemies, objects and items, then double-click a result to point the arrow at the closest spot. **Nearest** buttons find a mailbox, innkeeper, flight master, repair vendor, bank or auction house.

Find covers the classic world and WoW Forever's new zones, quests and items. It learns the NPCs you pass, their titles, vendor stock, quest givers and loot sources while you play. Search a title like **blacksmith** to find blacksmiths you've seen. What you see in the game takes precedence.

### Share with your party

Press **Share** beside a saved waypoint, or type `/wp share` to share where you stand. Choose Party, Raid, Guild, Say or a whisper; your chat opens with a clickable map pin ready to send. Friends can use the pin without installing the addon. You can also enter coordinates and press **Share** without setting a waypoint.

[![Waypoint Tracker's coordinate fields, Find buttons and saved waypoints with Share buttons, beside the open More Options panel](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/03-window.jpg)](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/03-window.jpg)

*In the game: coordinate fields, Find buttons and Share buttons beside saved waypoints. More Options is open alongside the window, showing arrow display, text and arrival settings. Open the image for a full-size view.*

## Make it yours

Start with a few settings for arrow visibility, movement and size. **Show more options** adds colour styles, time to arrive, fading, hiding in combat or on flight paths, arrival distance and sound, world map and minimap pins, map coordinates and metres instead of yards. The arrow can point to your corpse when you die, then return to your waypoint.

Use **Esc → Edit Mode** to drag or resize the arrow. Its text can move separately, and each layout keeps its own placement. Quest guides and other addons that send waypoints to an arrow can send them here with nothing to set up.

![Illustrated arrow demo, rendered from the addon's textures: the arrow turns, changes from gold to green and displays arrival text](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/images/arrow-demo.gif)

*Illustrated arrow demo, rendered from the addon's textures.*

The addon follows your client's language: English, Deutsch, Français, Español, Português, Русский, 한국어, 简体中文 or 繁體中文.

## Install

Install with the CurseForge app (World of Warcraft → **Forever**), or unzip the download from this page into `Interface\AddOns` in your WoW Forever folder (during the beta: `World of Warcraft\_classic_beta_\Interface\AddOns`). Keep both folders: `WaypointTracker` and `WaypointTracker_Data`. The Find database loads only when you first open Find. Start or restart the game, enable both folders in the AddOns list, then type `/wp`.

## Useful commands

| Command | What it does |
|---|---|
| `/wp` | Open or close the window |
| `/way 42 65` | Set a waypoint in your current zone |
| `/wp find [name]` | Open Find and optionally search |
| `/wp share` | Prepare your current location in chat |
| `/wp clear` | Remove the current waypoint |

See [Commands & Options](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Commands-and-Options) for named waypoints, other zones and every setting.

## Questions

**How do I set a waypoint in another zone?** Type `/way Westfall 56.3 47.1 Sentinel Hill`, or choose the zone in `/wp` and enter its coordinates.

**How do I find an NPC or quest giver?** Type `/wp find` and a name (or a title like `blacksmith`), then double-click a result. The arrow points to the closest spot.

**Does it send my data anywhere?** What it learns stays on your computer. To contribute, press **Share discoveries** in Find and paste the export into a GitHub issue. See [Discoveries & Privacy](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Discoveries-Privacy-and-Contributing), including how to correct a spot.

**Does it work with my quest guide?** Yes. Addons that send waypoints to an arrow send them here, with nothing to set up.

[Website](https://sanjaygbhat.github.io/wowforever-waypoint-tracker/) · [Wiki](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki) · [Questions, feedback and translations](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/issues)

Like it? You can support its development on GitHub Sponsors: https://github.com/sponsors/sanjaygbhat
