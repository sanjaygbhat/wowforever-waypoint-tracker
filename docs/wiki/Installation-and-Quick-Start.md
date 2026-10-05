[Home](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki) · [Install & quick start](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Installation-and-Quick-Start) · [Commands & options](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Commands-and-Options) · [Troubleshooting](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Troubleshooting-and-Compatibility) · [Discoveries & privacy](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Discoveries-Privacy-and-Contributing)

# Installation & Quick Start

## Install both folders

Download the **WaypointTracker** zip from [the latest GitHub release](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/releases/latest), or install it with the [CurseForge](https://www.curseforge.com/wow/addons/waypoint-tracker) app (World of Warcraft > **Forever**) or from [Wago](https://addons.wago.io/addons/waypoint-tracker).

1. Extract the ZIP into your Forever **Interface/AddOns** folder. During the beta this is `World of Warcraft/_classic_beta_/Interface/AddOns/`.
2. Check that these files are directly inside the two addon folders:

```text
Interface/AddOns/WaypointTracker/WaypointTracker.toc
Interface/AddOns/WaypointTracker_Data/WaypointTracker_Data.toc
```

3. Start or restart the game. In the character-selection **AddOns** list, enable **Waypoint Tracker** and **Waypoint Tracker (database)**.
4. Type `/wp` in game. After updating an existing installation, `/reload` reloads it.

The data folder supplies Find's database. It loads when you first open Find. Keep both folders from the same release. Your personal settings and discoveries live separately in SavedVariables; keep those when updating.

## Install through WowUp

WowUp's [2.24 beta releases](https://github.com/WowUp/WowUp/releases) support WoW Forever. Select your Forever installation, open **Get Addons → Install from URL**, and paste:

```text
https://github.com/sanjaygbhat/wowforever-waypoint-tracker
```

The [official WowUp guide](https://wowup.io/guide/get-addons/overview) documents GitHub installation from a tagged release with a packaged ZIP. Waypoint Tracker supplies that ZIP with both addon folders. Select the repository URL rather than a direct ZIP URL so WowUp can track releases. Check that both addon folders are enabled after installation.

## Set your first waypoint

- **Coordinates:** `/way 42 65` uses your current zone. For another zone: `/way Westfall 56.3 47.1 Sentinel Hill`.
- **Window:** type `/wp`, choose a zone, enter X/Y and press **Set Waypoint**. Pasting `45.2 67.8` into X fills both boxes.
- **Map:** hold **Ctrl** and **right-click** the world map.
- **Where you stand:** `/wp here`.

The arrow shows your destination and distance. On arrival it can play a sound, remove the waypoint and select the next closest one; adjust these in **Show more options**.

[![A green waypoint arrow over a flying character near Grol'dom Farm, showing Trade Rep, 932 yds and About 0:30](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/01-arrow.jpg)](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/01-arrow.jpg)

*In the game: destination, distance and estimated travel time beneath the arrow. Open the image for a full-size view.*

### Place a waypoint on the map

Open the world map, select your zone, then hold **Ctrl** and **right-click** the destination. The map pin marks the spot and the arrow points the way.

[![The Silverpine Forest world map with waypoint pins and the gold arrow pointing toward Lady Sylvanas Windrunner, 777 yds away](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/02-map.jpg)](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/02-map.jpg)

*In the game: waypoint pins on the Silverpine Forest world map; the arrow points toward Lady Sylvanas Windrunner, 777 yds away. Open the image for a full-size view.*

## Find a destination

Open **Find** with `/wp find` or the window's **Quests**, **NPCs**, **Enemies** or **Objects** buttons. Search, select a result and double-click it or press **Take me there**. Use the faction and zone filters to narrow results. The **Nearest** buttons find services such as a mailbox, innkeeper or repair vendor.

## Share a spot

Press **Share** beside a waypoint, or use `/wp share` for your current position. Choose a chat channel; the chat box opens with a clickable map pin ready for you to send. Friends can use that pin without installing the addon.

Find learns from your observations during play. See [Discoveries & Privacy](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Discoveries-Privacy-and-Contributing) for correcting a location and sharing discoveries.

Next: [Commands & Options](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Commands-and-Options).
