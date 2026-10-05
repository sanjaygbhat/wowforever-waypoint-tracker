# Release 1.1.0: what's left (October 2026)

A runbook for an agent with a web browser, signed in as the owner. Do the steps in order. The ground rules of [`CURSEFORGE_AGENT_PACK.md`](CURSEFORGE_AGENT_PACK.md) still apply:
- never paste a token anywhere
- public text says what works
- no other addons named
- stop and ask the owner for any login, 2FA code or decision

## Where things stand

| | |
|---|---|
| `main` | Holds 1.1.0: merge commit `b4f31b8` ("Waypoint Tracker 1.1.0 (#4)"). Tests green |
| Website | Live with Version 1.1.0 |
| Tag `v1.1.0` | **Not created yet** (step 1) |
| CurseForge | Project 1722148, still on 1.0.0 |
| Wago | Project ZKxOb36k, still on 1.0.0 |

## 1. Publish the release (this starts everything else)

1. Open https://github.com/sanjaygbhat/wowforever-waypoint-tracker/releases/new
2. **Choose a tag:** type `v1.1.0` exactly, then choose **Create new tag: v1.1.0 on publish**.
3. **Target:** `main`.
4. Leave the title and the description **empty**, and don't press **Generate release notes**. The workflow writes both from `CHANGELOG.md`.
5. Leave **Set as a pre-release** unticked and **Set as the latest release** ticked.
6. Press **Publish release**.

Publishing creates the tag, and the tag runs **Actions → Release**. That workflow:
- tests the addon, builds `WaypointTracker-v1.1.0.zip` and `release.json`
- fills in the release with the 1.1.0 notes and attaches both files
- uploads the zip with the same notes to CurseForge (Forever 1.60.1) and Wago (Forever 1.60.1)

## 2. Check the release

1. Open https://github.com/sanjaygbhat/wowforever-waypoint-tracker/actions/workflows/release.yml and wait for the `v1.1.0` run to finish (a few minutes). Every step should be green, including **Upload to CurseForge** and **Upload to Wago Addons**.
   - If a step is red, stop: copy the step's name and the last 30 lines of its log into your report. Don't re-run anything.
2. https://github.com/sanjaygbhat/wowforever-waypoint-tracker/releases/latest is **v1.1.0**, starts with "**Waypoint Tracker** is a free World of Warcraft addon…", and lists `WaypointTracker-v1.1.0.zip` and `release.json`.
3. CurseForge → project → **Files**: `Waypoint Tracker v1.1.0` for Forever 1.60.1. It may sit in review for a while.
4. Wago → project → **Versions**: `v1.1.0`, Stable, Forever 1.60.1.

## 3. Wiki pages

For each page: open the raw link, copy all of it, open the wiki page → **Edit**, select all, paste, **Save page** with the message `1.1.0`.

| Wiki page | Raw text |
|---|---|
| [Home](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki) | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Home.md |
| [Installation and Quick Start](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Installation-and-Quick-Start) | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Installation-and-Quick-Start.md |
| [Commands and Options](https://github.com/sanjaygbhat/wowforever-waypoint-tracker/wiki/Commands-and-Options) | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Commands-and-Options.md |

The other two wiki pages already match.

## 4. Descriptions (pasted by hand: neither site's upload changes them)

1. **Wago** (no review, do it now): project settings → description → replace it with https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/WAGO.md (Markdown). It has the Wago install line and no Sponsors line.
2. **CurseForge**: only once the 1.1.0 file shows **Approved** (editing during review can restart it). Project → **Description** → replace it with https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/CURSEFORGE.md (Markdown). If the file is still in review, skip this, and say so in your report.

What's new in both texts: a **Treasure hunt** section, and `/wp treasure` and `/wp treasure status` in the commands table.

## 5. Website (check only)

Open https://sanjaygbhat.github.io/wowforever-waypoint-tracker/: it says Version 1.1.0, and the **Spyglass of Plunder** (treasure hunt) card comes first. If it doesn't: **Actions → Website → Run workflow** (branch `main`).

## 6. Report back

List each step's result:
- the release's file list
- the CurseForge file name and its status
- the Wago version
- which wiki pages you saved
- whether each description was replaced (or why not)
- anything that differed from this page
