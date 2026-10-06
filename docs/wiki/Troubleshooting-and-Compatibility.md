[Home](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki) · [Install & quick start](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Installation-and-Quick-Start) · [Commands & options](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Commands-and-Options) · [Treasure hunt](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Treasure-Hunt) · [Troubleshooting](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Troubleshooting-and-Compatibility) · [Discoveries & privacy](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Discoveries-Privacy-and-Contributing)

# Troubleshooting & Compatibility

## Check the installation first

This release targets **World of Warcraft: Forever 1.60.1**, addon interface **16001**. Select the Forever release in your addon manager. During the beta, check the `_classic_beta_/Interface/AddOns` folder rather than another game installation.

Make sure both **WaypointTracker** and **WaypointTracker_Data** are enabled, and that their TOC files sit directly inside those folders. If unzipping made an extra folder around them, move the two folders up into `AddOns`. Restart the game after first installing the folders.

## Showing the arrow

1. Set a destination with `/way 42 65` or **Set Waypoint** in `/wp`.
2. Check **Show the arrow**. Review **Hide during combat** and **Hide on flight paths** if it disappears only in those situations.
3. Use **Reset** or **Esc → Edit Mode** if the arrow has moved off screen.
4. Arriving removes the waypoint by default. Set another destination, or change **When You Arrive** in the options.

While the window is open with no waypoint, a preview arrow lets you adjust placement and size.

## Getting the most from Find

Check that **WaypointTracker_Data** is installed and enabled. The database loads on demand when Find first opens. Try the **All** tab, clear the zone/faction filters and search part of the name. Forever quest names are learned from the game in the background during the first minutes of play.

Find combines shipped data with your local observations and shared discoveries. To correct a spot, select the result and use **Wrong spot? Correct it**. Details are in [Discoveries & Privacy](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Discoveries-Privacy-and-Contributing).

## `/way` and other addons

If another addon already uses `/way`, Waypoint Tracker leaves it to that addon and tells you once. `/wp` does the same things: `/wp find`, `/wp here`, `/wp share` and the rest.

**TomTom:** addons written for TomTom (quest guides, rare and treasure trackers, "Send to TomTom" buttons) send their waypoints to Waypoint Tracker's arrow with no changes. If TomTom itself is installed, Waypoint Tracker steps aside and leaves `/way` and the waypoint API to it.

## How do map pins and integrations work?

The arrow can follow the game's own map pin and pin links clicked in chat. Check **Follow the game's map pins** in the options. Other addons can send waypoints through the supported waypoint API when **Let other addons set waypoints** is enabled. Sharing a chat pin works for recipients without this addon.

## How do I update without losing discoveries?

Update both addon folders from the same release. Keep your `WTF` folder and SavedVariables. Before a manual backup, close the game and copy `WTF/Account/<account>/SavedVariables/WaypointTracker.lua`. That file also contains settings, so review it before attaching it publicly.

## Treasure hunt doesn't ping

Check that **Treasure hunt** is ticked, and that **Ping me when something appears** and the kinds you want are on under **Show more options → Treasure Hunt**. Type `/wp treasure status` to see what it sees: some places share no minimap markers, and rares there are found on nameplates and your target. More in [Treasure Hunt](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Treasure-Hunt).

## Get help

[Open a GitHub issue](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/issues) with your addon version, client build and the steps you took. A screenshot helps. Remove personal details from attachments. For a wrong location, include the zone and coordinates or use the discovery-sharing form.
