# Waypoint Tracker

**Set a waypoint. Follow the arrow. That's it.**

A solid 3D arrow over your character points to where you need to go and turns from gold to green as you get closer. It never catches your mouse clicks. When you arrive it plays a sound, clears the waypoint and moves on to the next one. Built for World of Warcraft: Forever (WoW Forever).

![Arrow demo](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/images/arrow-demo.gif)

## Ways to set a waypoint

- **The window:** type `/wp` or click the minimap button. Search a zone, type X and Y, press **Set Waypoint**.
- **Chat:** `/way 42 65` for your current zone, or `/way Westfall 56.3 47.1 Sentinel Hill`
- **Search a place:** in the window's Zone box, type a quest from your log, a flight master, a dungeon or a rare and click it.
- **The map:** hold **Ctrl** and **right-click** the world map.

**Share without setting a waypoint:** type the coordinates and press **Share**, or leave them empty to share where you are (also `/wp share`). Every waypoint in your list has a **Share** button too. Pick Party, Raid, Guild, Say or a whisper, and your chat opens with a clickable map pin ready to send, which works even for friends without the addon.

Paste coordinates like `45.2 67.8` or `45,2 67,8` straight into the X box and they fill in by themselves.

## Find anything, including WoW Forever's new content

Next to **Find:** in the window, press **Quests**, **NPCs**, **Enemies** or **Objects** (or type `/way hogger`) to search the database. Search, then double-click to point the arrow at the closest one. One-click **Nearest** buttons find the closest mailbox, innkeeper, flight master, repair, bank and auction house.

The database covers the classic world and WoW Forever's new zones, quests and items, and learns while you play: the NPCs and enemies around you with their titles, what vendors sell, quest givers, hand-ins, objective areas, NPC services, mailboxes, and which enemy or object drops each item you loot. Search a title like **blacksmith** to find every blacksmith you've seen. What you see in the game always wins.

Only what's new is kept, on your computer. Found a spot that's off? Press **Wrong spot? Correct it** in Find and stand where it really is. When you want to help everyone, press **Share discoveries** and paste it into a GitHub issue. It'll be in the next update.

## Move it in Edit Mode

Press **Esc > Edit Mode** and the arrow shows up with the game's blue box, like every other HUD frame. Drag it, or click it for the size and visibility of the arrow and its text, and reset. The text can also move on its own. Each Edit Mode layout keeps its own spot.

## Simple by default

Out of the box you get the arrow, its distance, and a few settings: show, move, size and visibility. Tick **Show more options** for the rest:

- Colour styles: by distance, by facing, or one colour you pick
- Time to arrive, fade when heading the right way, hide in combat or on flight paths
- Points to your corpse when you die, then back to your waypoint once you're alive
- Arrival distance, auto-remove, sound, move on to the next closest waypoint
- World map and minimap pins, coordinates on the map, a coordinates box
- Metres instead of yards, always point to the closest waypoint, and more

## Works with your other addons

Quest guides, treasure maps and other addons that send waypoints to an arrow can send them straight to this one. There's nothing to set up.

## 9 languages

English, Deutsch, Français, Español, Português, Русский, 한국어, 简体中文, 繁體中文. The addon follows your game client's language automatically.

## Commands

| Command | What it does |
|---|---|
| `/wp` | Open the window |
| `/way [zone] X Y [name]` | Set a waypoint |
| `/way [name]` | Go to the thing with that exact name, or search Find |
| `/wp here` | Waypoint where you stand |
| `/wp share [zone X Y]` | Share a spot, or where you are, in chat |
| `/wp find [name]` | Search quests, NPCs, enemies, objects and items |
| `/wp closest` | Point to the closest waypoint |
| `/wp clear` | Remove the arrow's waypoint |
| `/wp list` | List your waypoints |
| `/wp arrow` | Show or hide the arrow |
| `/wp help` | List every command |

## Install

Install with the CurseForge app, or unzip the download into `Interface\AddOns`. You get two folders: `WaypointTracker` and `WaypointTracker_Data` (the Find database, which loads only when you first open Find).

Source, feedback and translations: https://github.com/sanjaygbhat/wowforever-waypoint-tracker

Like it? You can support its development on GitHub Sponsors: https://github.com/sponsors/sanjaygbhat
