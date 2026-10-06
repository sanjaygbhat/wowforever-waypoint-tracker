[Home](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki) · [Install & quick start](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Installation-and-Quick-Start) · [Commands & options](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Commands-and-Options) · [Treasure hunt](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Treasure-Hunt) · [Troubleshooting](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Troubleshooting-and-Compatibility) · [Discoveries & privacy](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Discoveries-Privacy-and-Contributing)

# Treasure Hunt (beta): rare and chest alerts for WoW Forever

Treasure hunt turns Waypoint Tracker into a rare scanner and treasure finder. The moment a chest, a rare spawn or an event appears near you, you get a ping and the arrow points straight at it. New in version **1.1.0** and still in beta: please [report](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/issues) what it catches and what it misses, with `/wp treasure status` output if you can.

![Illustration of treasure hunt: a chest marker appears with a ping, the alert reads Treasure nearby, and the arrow turns to it and closes the distance](https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/images/treasure-hunt.gif)

*Treasure hunt, illustrated with the addon's own arrow.*

## Turn it on

Any of these:

- Tick **Treasure hunt** in the window (`/wp`).
- Type `/wp treasure`.
- Bind a key under **Key Bindings → AddOns → Turn treasure hunt on or off**.

It's off until you turn it on, and stays on across sessions.

## What it watches for

| Kind | Where it comes from |
|---|---|
| **Chests and treasure** | Treasure the game marks on your minimap, and a chest right in front of you |
| **Rare spawns** | Rare and rare elite enemies on your minimap, nameplates, target or under your mouse, placed at their known spawn |
| **Events and other markers** | Anything else the game marks on your minimap, like events |

Rares someone else is already fighting are left out, so you don't run across the zone for a kill that's already taken.

## What happens when something appears

1. **A ping:** a sound, a message on screen ("Treasure nearby: …" with the distance) and a blinking taskbar icon if you're in another window.
2. **The arrow points at it** right away. A rare that wanders is followed.
3. **It lets go** once the chest is looted, the rare is killed or the marker is gone ("… is gone."), then the arrow goes back to your own waypoint.

Prefer to keep the arrow where it is? Turn off **Point the arrow at it right away**: finds are added to your waypoint list instead.

## Lead me to known chest spots

With **Lead me to known chest spots** on, and while nothing has appeared, the arrow points at the nearest spot where a chest can spawn, then at the next one once you've checked it. Handy for farming chests in a zone.

## See what it sees

`/wp treasure status` lists:

- how many minimap markers the game shows where you are (and how many are on the world map only),
- what it's tracking now,
- your recent finds this session, with how each was found (minimap, nameplate or target, or in front of you).

Some places share no minimap markers. There, rares are still found on nameplates and your target. Turning on enemy nameplates (**V**) helps it notice more rares.

## Settings

Under **Show more options → Treasure Hunt**:

| Option | Default |
|---|---|
| Treasure hunt | Off |
| Chests and treasure | On |
| Rare spawns | On |
| Events and other markers | On |
| Lead me to known chest spots | Off |
| Ping me when something appears | On |
| Point the arrow at it right away | On |

## Questions

**Does it replace RareScanner or SilverDragon?** Not yet: it's a lighter, beta take on alerts for rares, chests and events near you, with an arrow to get there. If you already use a rare or treasure addon that sends TomTom waypoints, those waypoints land on Waypoint Tracker's arrow too.

**Does it scan the whole zone?** No. It sees what the game shows you: minimap markers, nameplates, your target and the object in front of you. Nothing is sent or fetched from outside the game.

**Will it interrupt my current waypoint?** Only while something is up. Once it's taken, killed or gone, the arrow returns to your waypoint.

Next: [Troubleshooting & Compatibility](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Troubleshooting-and-Compatibility).
