# Follow-up after a release (1.1.0, October 2026)

A short runbook for an agent with a web browser (or the owner), after a version is tagged. Do the steps in order. The ground rules of [`CURSEFORGE_AGENT_PACK.md`](CURSEFORGE_AGENT_PACK.md) still apply:
- never paste a token anywhere
- public text says what works
- no other addons named
- stop and ask the owner for any login, 2FA code or decision

## What the tag already did

Pushing the tag `v1.1.0` runs **Actions → Release**, which:
- tests the addon, builds `WaypointTracker-v1.1.0.zip` and `release.json`
- makes the GitHub release with the 1.1.0 notes from `CHANGELOG.md`
- uploads the zip with the same notes to CurseForge (project 1722148, Forever 1.60.1) and Wago (project ZKxOb36k, `supported_forever_patches` 1.60.1)

Pushing to `main` also runs **Actions → Website**, which republishes https://sanjaygbhat.github.io/wowforever-waypoint-tracker/ with the new version.

## 1. Check the release

1. **Actions → Release** for `v1.1.0`: every step green, including both uploads.
2. https://github.com/sanjaygbhat/wowforever-waypoint-tracker/releases/latest lists `WaypointTracker-v1.1.0.zip` and `release.json`.
3. CurseForge → project → **Files**: `Waypoint Tracker v1.1.0` for Forever 1.60.1 (it may sit in review for a while).
4. Wago → project → **Versions**: `v1.1.0`, Stable, Forever 1.60.1.

## 2. Descriptions (pasted by hand: neither site's upload API changes them)

Wait until CurseForge has approved the file: editing during review can restart it.

1. **CurseForge:** replace the description with https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/CURSEFORGE.md (Markdown). New in it: the **Treasure hunt** section and two command rows.
2. **Wago:** replace the description with https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/WAGO.md (Markdown). Same text with the Wago install line and no Sponsors line.

## 3. Wiki pages

For each page: open the raw link, copy all of it, open the wiki page → **Edit**, select all, paste, **Save page** with the message `1.1.0`.

| Wiki page | Raw text |
|---|---|
| Home | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Home.md |
| Installation and Quick Start | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Installation-and-Quick-Start.md |
| Commands and Options | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Commands-and-Options.md |

## 4. Website

1. Open https://sanjaygbhat.github.io/wowforever-waypoint-tracker/ and check it says Version 1.1.0 and the **Spyglass of Plunder** (treasure hunt) card comes first.
2. If the version is still 1.0.0: **Actions → Website → Run workflow** (branch `main`).

## 5. Report back

List each step's result, with the release's file list, the CurseForge and Wago file names, and anything that differed from this page.
