[Home](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki) · [Install & quick start](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Installation-and-Quick-Start) · [Commands & options](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Commands-and-Options) · [Treasure hunt](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Treasure-Hunt) · [Troubleshooting](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Troubleshooting-and-Compatibility) · [Discoveries & privacy](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Discoveries-Privacy-and-Contributing)

# Discoveries, Privacy & Contributing

## What the addon learns

During play, Waypoint Tracker notices NPCs and enemies, their titles and locations, vendor stock, quest givers and hand-ins, services, mailboxes and item drops. Find combines the shipped database, shared discoveries included in releases and your observations. What you see in game takes precedence.

Only new or changed information is kept locally. Learning is the **Learn NPCs, quests and objects as I play** setting under **Find** in **Settings → Find & Sharing**.

Routes and votes can be shared in game with other players when route sharing is enabled. Real routes (beta) has a separate switch for sharing learned paths in **Settings → Routes**. Discovery exports remain a manual choice.

## What stays private

The addon sends nothing to a website automatically. Settings and discoveries remain in your game's SavedVariables until you choose to share them. The **Share discoveries** export contains names and places, rather than your character or account details. Review any text before posting.

The complete SavedVariables file also holds settings. Prefer the compact export for routine submissions; review a full-file attachment before making it public.

## Correct a location

1. Select the NPC or object in **Find**.
2. Press **Wrong Spot? Correct It**.
3. Stand at the correct spot, press **Use My Position** and **Save Correction**, or enter its coordinates.

Use **It's Not There** for a wrong spot, **Remove My Correction** to undo your correction, or **Add Where It Is** when no location is known. Find uses your correction immediately and includes it in your discovery export.

## Share with the project

1. Open **Find → Discoveries → Share discoveries**.
2. Copy the selected export text.
3. [Open a Share discoveries issue](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/issues/new?template=discoveries.yml) and paste it into the form. Add useful context such as the zone or what you corrected.

Shared findings can be reviewed and merged into a later database update. No separate upload happens from the addon.

## Swap with a friend

One player copies the **Share discoveries** export. The other opens **Discoveries → Import discoveries** in Find and pastes it. Import the discovery text, rather than replacing your settings file with someone else's SavedVariables.

## Back up and contribute

Close the game before backing up `WTF/Account/<account>/SavedVariables/WaypointTracker.lua`. Keep a copy of your own file before making manual changes.

[GitHub issues](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/issues) are also the place for questions, translation suggestions and feature ideas. Remove private information from screenshots or attachments. Source is available under the [MIT licence](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/blob/main/LICENSE).
