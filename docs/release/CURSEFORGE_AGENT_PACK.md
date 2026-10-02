# Launch pack: Waypoint Tracker 1.0.0

> **Launched October 2, 2026.** CurseForge project 1722148, Wago project ZKxOb36k, GitHub release v1.0.0. The follow-up steps are in [`FOLLOW_UP.md`](FOLLOW_UP.md). This pack stays as the record of the launch and for section 11 (later releases).

A step-by-step runbook for an agent with a web browser (or a person) to launch **Waypoint Tracker**, an addon for **World of Warcraft: Forever** (WoW Forever). It covers:

- making the GitHub repository ready
- publishing on CurseForge (and optionally Wago Addons)
- releasing version 1.0.0
- announcing it

Do the phases in order, and don't skip the checks: each phase depends on the one before. Everything to type or paste is in this file, or at a link it gives. Written October 2, 2026, for WoW Forever beta build 1.60.1.70170 (beta level cap 30). Sources are at the end. Where a website's form differs from what's written here, follow the form and note the difference in your report.

---

## 0. Context: what you're launching and where things stand

| Fact | Value |
|---|---|
| Addon name | **Waypoint Tracker** |
| Tagline | **Set a waypoint. Follow the arrow. That's it.** |
| What it does | A 3D waypoint arrow, `/way` coordinates, a built-in quest/NPC/item finder (Find) that learns as you play, and map pins you can share in chat |
| Game | World of Warcraft: Forever (WoW Forever). The beta runs until **October 21, 2026**; launch is **November 4, 2026, 3:00 PM PST** |
| Game version names | Client **1.60.1**, addon interface **16001**. On CurseForge the game flavour is **Forever** (internal id 88568) |
| Version to release | **1.0.0** (the first public release) |
| Owner | GitHub user **sanjaygbhat** |
| Repository | https://github.com/sanjaygbhat/wowforever-waypoint-tracker |
| Repository state on October 2, 2026 | **Private**. One branch, `claude/amazing-brahmagupta-nc13sl` (also the default), holding a single commit titled "Waypoint Tracker 1.0.0". No `main` branch, no tags, no releases, no secrets |
| Licence | MIT (file `LICENSE`); bundled third-party data credited in `WaypointTracker_Data/THIRD-PARTY-LICENSES.txt` |
| Download layout | One zip, `WaypointTracker-v1.0.0.zip`, with two folders: `WaypointTracker` (the addon) and `WaypointTracker_Data` (Find's database, loaded on demand) |
| How releases are built | Publishing a tag `vX.Y.Z` runs the GitHub Actions workflow **Release** (`.github/workflows/release.yml`). It tests, builds the zip, creates the GitHub release and, if the secrets in phase C exist, uploads to CurseForge and Wago |
| Players' discoveries | The addon records new NPCs and spots **on the player's computer only** (addons have no internet access). Players share them by hand: Find → **Share discoveries** → paste into a GitHub issue (template "Share discoveries", label `discoveries`) |

## 1. Ground rules

- **Never** invent account details, tokens or IDs. If you need a login, a 2FA code or a decision, stop and ask the owner.
- **Never** paste an API token anywhere except GitHub's **Secrets** page: not in a file, an issue, a description, a post or your report.
- **Don't edit the repository's files** (no web-editor commits). The only repository changes in this runbook are settings, one branch, one label, secrets and the release. If something in a file looks wrong, report it instead.
- **Don't** use "World of Warcraft", "WoW" or "Forever" in the project **name**. Don't use a Blizzard logo or any other project's art. These words are fine in descriptions.
- **Don't mention or compare with other addons** in any text you write.
- **Public text says what works.** Don't add limitations, "not supported", "coming soon" or apologies to descriptions or posts.
- **Don't** delete and re-create a CurseForge project to get around moderation. Fix what was asked and resubmit.
- Post announcements only **after** CurseForge has approved the project, and only where the place's rules allow it.
- Keep a log for the final report (section 12).

## 2. What the owner provides

| # | Item | Needed for |
|---|---|---|
| 1 | GitHub login for **sanjaygbhat** (admin of the repository) | Phases A, C, E |
| 2 | CurseForge author login (Overwolf account, https://authors.curseforge.com), with 2FA at hand | Phase B |
| 3 | Yes/no: join CurseForge's **Rewards** program | Phase B, step 9 |
| 4 | Optional: Wago Addons login (https://addons.wago.io, sign-in with Patreon, Discord, Twitch or Battle.net) | Phase D |
| 5 | Optional, for announcing: Blizzard forums (Battle.net), Reddit, Discord and X/Bluesky accounts, and an email address for guide sites | Phase G |

## 3. Files you'll need (download links)

These links only work once the repository is **public** (phase A, step 1).

| File | Link | Used in |
|---|---|---|
| Logo, 1024×1024 PNG, transparent | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/release/logo-1024.png | CurseForge and Wago logo |
| Logo on a dark square (fallback) | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/release/logo-1024-dark.png | If the logo above is refused |
| Logo, 400×400 (if a form asks for that size) | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/release/logo-400.png | |
| Screenshot 1 | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/01-arrow.jpg | Gallery |
| Screenshot 2 | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/02-map.jpg | Gallery |
| Screenshot 3 | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/03-window.jpg | Gallery |
| GitHub social preview, 1280×640 | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/release/social-preview.png | Phase A |
| Project description (Markdown) | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/CURSEFORGE.md | CurseForge and Wago description |
| Changelog | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/CHANGELOG.md | Manual upload only (phase E fallback) |
| Licence text | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/LICENSE | Only if a form has no "MIT" choice |

The release zip `WaypointTracker-v1.0.0.zip` is created in phase E. You'll only need it if the automatic upload fails.

---

## Phase A: GitHub repository (about 10 minutes)

Sign in to github.com as **sanjaygbhat** and open https://github.com/sanjaygbhat/wowforever-waypoint-tracker.

1. **Make it public.**
   1. Go to **Settings → General**, scroll to **Danger Zone**, click **Change visibility** and choose **Change to public**.
   2. Confirm, typing the repository name when asked.
   - **Check:** signed out (or in a private window), the repository page loads, and the logo link in section 3 opens the image.
   - **Why:** players open its issues page to share discoveries, the CurseForge description's demo GIF loads from it, and releases are downloaded from it.
2. **Create `main`.**
   1. On the repository's front page, open the branch selector (it shows `claude/amazing-brahmagupta-nc13sl`) and type `main`.
   2. Click **Create branch main from claude/amazing-brahmagupta-nc13sl**.
   - **Check:** the branch selector lists `main`.
3. **Make `main` the default.** In **Settings → General → Default branch**, click the switch icon, pick `main`, then **Update** and confirm.
   - **Check:** the front page opens on `main`.
   - Don't delete the old branch yet (phase F does that).
4. **Allow the release workflow.** Go to **Settings → Actions → General**:
   - **Actions permissions** must allow all actions. The workflow uses `actions/checkout`, `actions/upload-artifact` and `softprops/action-gh-release`, so "Allow all actions and reusable workflows" is simplest.
   - Leave **Workflow permissions** as it is; the workflow asks for write access itself.
   - Then open the **Actions** tab. If it asks to enable workflows, enable them.
   - **Check:** the Actions tab lists the workflows **Tests** and **Release**.
5. **Make sure Tests passes on `main`.** In **Actions → Tests**:
   - If there is no run for `main` yet, open the latest run, click **Re-run all jobs**, or wait for the run that creating `main` starts.
   - **Check:** a green tick for `main`. If it's red, stop and report the failed step's log to the owner.
6. **Create the `discoveries` label.** Go to **Issues → Labels → New label**: name `discoveries`, description `Players' shared discoveries for the database`, any colour → **Create label**.
   - The "Share discoveries" issue form adds this label automatically.
   - **Check:** **Issues → New issue** shows the templates, including **Share discoveries**.
7. **About box.** On the front page, click the gear next to **About**:
   - **Description:** `Free 3D waypoint arrow, /way coordinates, quest and NPC finder, and map pin sharing for World of Warcraft: Forever (WoW Forever).`
   - **Website:** leave empty for now (phase F).
   - **Topics** (20, GitHub's maximum): `world-of-warcraft`, `wow`, `world-of-warcraft-addon`, `wow-addon`, `warcraft-addon`, `wowaddon`, `wow-forever`, `worldofwarcraft`, `warcraft`, `lua`, `addon`, `waypoint`, `waypoints`, `navigation`, `coordinates`, `quest-helper`, `curseforge`, `classic-plus`, `wow-classic`, `map`
   - **Include in the home page:** tick **Releases**; untick **Packages** and **Deployments**.
   - **Save changes**.
8. **Social preview.** Go to **Settings → General → Social preview → Edit → Upload an image** and upload `social-preview.png` (section 3). This is the picture shown when the link is shared on Discord, Reddit or X.
9. **Check the GitHub Sponsors page.** Open https://github.com/sponsors/sanjaygbhat.
   - If it shows a sponsor page, use it as the donation link below.
   - If it's a 404 or a "join the waitlist" page, there's **no donation link**:
     - leave CurseForge's donation field empty
     - delete the last line of the description ("Like it? You can support…") when pasting it in phase B
     - tell the owner in the report

## Phase B: CurseForge project (about 20 minutes, then moderation)

1. **Preview the description first.**
   1. Open the CURSEFORGE.md link in section 3 and copy its entire text.
   2. Open https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/images/arrow-demo.gif and check that it loads (it's embedded in the description).
2. **Start the project.** Sign in at https://authors.curseforge.com, open https://authors.curseforge.com/#/projects/create/choose-game and choose **World of Warcraft**. Fill in:

   | Field | Value |
   |---|---|
   | Class / project type | **Addons** |
   | Name | `Waypoint Tracker`. If it's taken: `Waypoint Tracker Arrow`. Never add "WoW", "Forever", "addon" or a version number. |
   | Summary | `Set a waypoint and follow a clear 3D arrow. Find quests, NPCs, enemies, objects and items, and share spots in chat.` If that's too long: `A clear 3D waypoint arrow with a built-in quest, NPC and item finder.` |
   | Main category | **Map & Minimap** |
   | Additional categories | **Quests & Leveling** only. Unrelated categories get projects sent back. |
   | Logo / avatar | `logo-1024.png`. If refused, or it looks wrong on a light background: `logo-1024-dark.png`. Use `logo-400.png` if the form wants 400×400. Not WebP. |
   | Allow comments | On |
   | Experimental | **Off** (an experimental project doesn't show in search or the CurseForge app) |
   | Description | Switch the editor to **Markdown** first, then paste the whole CURSEFORGE.md text. Don't add any download links. Check the preview: headings, lists and the table render, and the demo GIF shows. If the GIF doesn't show, delete just that line; don't upload it anywhere else. |
   | Licence | **MIT License**. If there's no MIT choice: **Custom**, with the text of `LICENSE`. |
   | Distribution toggle | **On** (lets the CurseForge app and other launchers install it) |

   The project's address should come out as `https://www.curseforge.com/wow/addons/waypoint-tracker`. It was free on September 27, 2026; the form shows whether it still is.
3. **Save / create the project.** Write down the **Project ID** from the "About Project" box on the project page.
4. **Gallery (Images tab).** Upload these real in-game screenshots, in this order, with these titles and descriptions. Make the first one the featured image if the form offers that.

   | # | File | Title | Description |
   |---|---|---|---|
   | 1 | `01-arrow.jpg` | The arrow | A 3D arrow over your character points to your waypoint, with its name, distance and time to arrive. |
   | 2 | `02-map.jpg` | Waypoints on the map | Your waypoints show on the world map and minimap while the arrow points the way. |
   | 3 | `03-window.jpg` | Simple window, every option one click away | Set a waypoint from coordinates, find quests, NPCs and objects, share spots in chat, and open More Options for the rest. |

   - Only these real screenshots. Never upload drawings, renders, the banner or the logo as screenshots.
   - If the owner adds more later (`04-share.jpg`, `05-find.jpg`, `06-learn.jpg`), they go after these, with the titles in `docs/screenshots/README.md`.
5. **Project settings:**

   | Setting | Value |
   |---|---|
   | Source | `https://github.com/sanjaygbhat/wowforever-waypoint-tracker`. If there's a packaging option, choose **no automatic packaging**: GitHub Actions uploads the files. |
   | Issues | External: `https://github.com/sanjaygbhat/wowforever-waypoint-tracker/issues` |
   | Wiki | Empty |
   | Donation | GitHub Sponsors `https://github.com/sponsors/sanjaygbhat`, only if phase A step 9 found a working page. If the list has no GitHub option, leave it empty: the link is already the description's last line. |
   | Members | Only the owner |

6. **Find the exact game version name.** Open the project's **Files → Upload file** page, but **don't upload anything**. In its game version picker, find the **Forever** flavour and note the exact version name (expected `1.60.1`; if there are several, note the newest). Leave the page without uploading.
7. **API token.**
   1. Open https://authors.curseforge.com/#/settings/api-tokens and create a token named `github-actions`.
   2. Copy it **straight into phase C**: don't save it anywhere else, and don't put it in your report.
8. **Leave the project unsubmitted for now** if the site has a separate "submit for review" step. Phase E uploads the first file, and moderation reviews project and file together. If the site submits on creation, that's fine too.
9. **Rewards:** only if the owner said yes. Go to account settings → **Rewards**, opt in and accept the terms.

## Phase C: GitHub secrets and variables (about 5 minutes)

On GitHub, go to **Settings → Secrets and variables → Actions**.

1. **Secrets** tab → **New repository secret**: name `CF_API_TOKEN`, value the CurseForge token.
2. **Variables** tab → **New repository variable**:
   - `CF_PROJECT_ID`, value the CurseForge Project ID (digits only)
   - `CF_GAME_VERSION`, value the exact Forever version name from phase B step 6 (normally `1.60.1`)
3. If you did phase D: secret `WAGO_API_TOKEN` and variable `WAGO_PROJECT_ID`.
- **Check:** the secrets list shows `CF_API_TOKEN` (values are hidden), and the variables list shows `CF_PROJECT_ID` and `CF_GAME_VERSION` with their values.

## Phase D: Wago Addons (optional, about 10 minutes)

Do this **before** phase E, so the release uploads there too.

1. Sign in at https://addons.wago.io and create a new project:
   - Name `Waypoint Tracker`, with the same summary, description (Markdown), logo and screenshots as on CurseForge.
   - Game flavour **Forever** (Wago lists WoW Forever 1.60.1).
   - Category: maps or navigation (closest match).
   - Source link: the GitHub repository.
2. Copy the 8-character **project ID** from the project's developer dashboard.
3. Create an API key at https://addons.wago.io/account/apikeys.
4. Put both into GitHub (phase C step 3).

## Phase E: Release 1.0.0 (about 10 minutes)

1. **Check the data is the newest.** Open https://wago.tools/api/builds in the browser and look at the `wow_classic_beta` list.
   - If its newest `1.60.1.x` build is newer than **1.60.1.70170**, stop: the database should be rebuilt by a developer first (see "Later releases"). Report this to the owner.
   - Otherwise continue.
2. **Publish the release.** This creates the tag `v1.0.0`, which starts the Release workflow.
   1. Go to **Releases → Draft a new release** (https://github.com/sanjaygbhat/wowforever-waypoint-tracker/releases/new).
   2. **Choose a tag:** type `v1.0.0` and pick **Create new tag: v1.0.0 on publish**.
   3. **Target:** `main`.
   4. **Release title:** `Waypoint Tracker v1.0.0`.
   5. **Description:** `Waypoint Tracker 1.0.0`. The workflow replaces it with the full release notes and install steps.
   6. Leave "Set as a pre-release" unticked and "Set as the latest release" ticked, then click **Publish release**.
3. **Watch the workflow.** Open **Actions → Release**. A run for `v1.0.0` starts within a minute and takes about 2–5 minutes.
   - If no run appears within 3 minutes, report it: publishing a release normally fires the tag event.
   - **Green:** go on.
   - **Red at "Test before packaging":** report the log; nothing was published.
   - **Red at "Upload to CurseForge":**
     - "CurseForge has no Forever game version named …": fix `CF_GAME_VERSION` to the exact name from phase B step 6, then **Re-run all jobs** on the same run.
     - **401 or 403:** the token is wrong. Make a new one, update the secret, and re-run.
     - Anything else: copy the error from the log (it never contains the token) and use the manual upload below.
4. **Checks:**
   - The release page https://github.com/sanjaygbhat/wowforever-waypoint-tracker/releases/tag/v1.0.0 has:
     - a first line describing the addon
     - the 1.0.0 changes
     - an "Install" section
     - the asset `WaypointTracker-v1.0.0.zip`
   - Download the zip and look inside:
     - exactly two top-level folders, `WaypointTracker` and `WaypointTracker_Data`
     - `WaypointTracker/LICENSE.txt` and `WaypointTracker_Data/THIRD-PARTY-LICENSES.txt` exist
     - no `.git`, `tests`, `tools` or `docs` folders
   - On CurseForge, the project's **Files** tab lists **Waypoint Tracker v1.0.0**: type Release, game version Forever 1.60.1, with the changelog filled in.
   - If phase D was done: Wago lists version `v1.0.0`.

**Manual upload (only if the automatic CurseForge upload failed).** Go to the project's **Files → Upload file**:

| Field | Value |
|---|---|
| File | `WaypointTracker-v1.0.0.zip` from the GitHub release |
| Display name | `Waypoint Tracker v1.0.0` |
| Release type | Release |
| Game version | Flavour **Forever**, version from phase B step 6 (tick every current Forever version) |
| Changelog | Markdown: the `## 1.0.0` section of CHANGELOG.md, without the heading line |
| Relations / dependencies | None. The database is inside the same zip; don't mark any other addon as required or incompatible. |

## Phase F: Moderation and after approval

1. **Submit the project for review** if it's waiting for that.
   - CurseForge moderates WoW projects 08:00–15:00 CET, seven days a week, first in first out.
   - Watch https://www.curseforge.com/my-notifications.
2. **If moderation sends it back:**

   | Reason given | What to do |
   |---|---|
   | Description too short or unclear | Make sure it was pasted in **Markdown** mode, so headings and lists render. |
   | Name too similar, or contains the game's name | Rename to `Waypoint Tracker Arrow`. |
   | Logo not acceptable | Switch to `logo-1024-dark.png`. |
   | Missing credit or licence for third-party content | The zip ships `WaypointTracker_Data/THIRD-PARTY-LICENSES.txt`; tell the moderator. If they still want a mention, add this line at the very bottom of the description: `Includes MIT-licensed data; see THIRD-PARTY-LICENSES.txt in the download.` |
   | Screenshots | Confirm they're real in-game screenshots, cropped only (they are). |
   | Anything else | Do what's asked if it's within these rules; otherwise report it to the owner. |

3. **Once approved:**
   - Open the public project page (signed out) and check: the description renders, the GIF and gallery show, and the file is downloadable.
   - Set GitHub's **About → Website** to the CurseForge project URL.
   - If the owner can check in the CurseForge app: World of Warcraft → **Forever** → search "Waypoint Tracker" → it installs both folders.
   - Delete the old branch: GitHub → **Branches** → `claude/amazing-brahmagupta-nc13sl` → delete. Only once `main` is the default and the release is out.

## Phase G: Announce

**When:**

| When | What |
|---|---|
| Right after approval (during the beta) | First posts, in the places below. Beta testers are the most active addon users right now. |
| Launch week, from November 4 | A second, short post where allowed: most players install addons in the first days after launch. |

**Before posting anywhere:** read the place's rules (sidebar, pinned post, channel description). Skip it if self-promotion isn't allowed, or the owner's account doesn't meet its requirements (account age, karma). Post each text once per place, as the owner, and don't cross-post the same text in quick succession. Replace `<CurseForge URL>` with the real project URL.

**Where:**

| Place | How |
|---|---|
| Blizzard forums: the "WoW Forever addons" thread, https://us.forums.blizzard.com/en/wow/t/wow-forever-addons/2362999 | **Reply** in that thread rather than starting a new one. Text A. |
| Blizzard forums, UI and Macro: https://us.forums.blizzard.com/en/wow/c/guides/ui-macro/35 | Only if that thread is closed: a new topic with title B and text A. |
| WoWUIDev Discord: https://discord.com/invite/sVQCHr5 | Post in a showcase or release channel if there is one, asking for feedback. Text C. |
| Reddit: r/wowaddons, r/classicwow, r/wow | One post per subreddit, with the addon or "Addon release" flair if there is one. Title B, text A. Answer comments. |
| Guide sites that list "best WoW Forever addons": `wofwforever.com`, `wowforeverbuilds.com/addons`, `wow4evernews.com`, `foreverchanges.pro/addons` | Use each site's contact form or email once. Text D. |
| Wowhead Forever hub: https://www.wowhead.com/forever | Their contact form, once. Text D. |
| X / Bluesky | Text E, with the screenshot `01-arrow.jpg` or the demo GIF. |

Skip the community server calling itself the "Official WoW Forever Discord". Players on Blizzard's forums say it isn't official.

**Title B:** `Waypoint Tracker: a free 3D waypoint arrow and quest/NPC finder for WoW Forever`

**Text A (forums and Reddit):**

> **Waypoint Tracker: a free 3D waypoint arrow for WoW Forever**
>
> Set a waypoint and follow the arrow. It shows the distance and time to arrive, turns from gold to green as you get close, and clears itself when you arrive.
>
> - `/way 42 65` or `/way Westfall 56 47 Sentinel Hill`, Ctrl + Right-click the map, or the small window (`/wp`)
> - A built-in Find window: search quests, NPCs, enemies, objects and items, including WoW Forever's new content, and go to the closest one
> - Share any spot in chat as a clickable map pin, even with friends who don't have the addon
> - Learns as you play: the NPCs you pass (with their titles, so `blacksmith` finds the blacksmiths), what vendors sell, quest givers and loot. It stays on your computer, and you can correct any spot in one click
> - Moves and sizes in Edit Mode, 9 languages, free and open source (MIT)
>
> CurseForge: <CurseForge URL> · Source and feedback: https://github.com/sanjaygbhat/wowforever-waypoint-tracker
>
> Found a new NPC or a better spot? Press Find → Share discoveries and paste it into a GitHub issue: it goes into the next update for everyone.

**Text C (Discord, short):**

> Hi! I made **Waypoint Tracker** for WoW Forever: a 3D waypoint arrow with `/way`, a quest/NPC/item finder that learns new NPCs as you play (kept locally), and map pins you can share in chat. Free and MIT. I'd love feedback from other authors: <CurseForge URL> · https://github.com/sanjaygbhat/wowforever-waypoint-tracker

**Text D (email or contact form to guide sites):**

> Subject: Waypoint Tracker, a free waypoint arrow addon for WoW Forever
>
> Hello,
>
> I'm the author of Waypoint Tracker, a free addon for WoW Forever. It's a 3D waypoint arrow with `/way` coordinates, a built-in finder for quests, NPCs, enemies, objects and items (including WoW Forever's new content), and clickable map pins you can share in chat. It's on CurseForge: <CurseForge URL>. The source is at https://github.com/sanjaygbhat/wowforever-waypoint-tracker.
>
> If it fits your addon list, feel free to include it. A screenshot: https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/screenshots/01-arrow.jpg
>
> Thanks,
> sanjaygbhat

**Text E (X / Bluesky):**

> Waypoint Tracker is out for #WoWForever: a free 3D waypoint arrow, /way coordinates, a quest and NPC finder that learns as you play, and map pins you can share in chat. <CurseForge URL>

**Keep it going (for the owner):**
- Answer CurseForge comments and GitHub issues within a few days; active projects rank better.
- Merge shared discoveries into each update and say so in the changelog.

---

## 11. Later releases (needs a developer with a terminal)

Not for the browser agent. Listed so the whole process is in one place.

1. **Refresh the data** when WoW Forever gets a new client build (newest `wow_classic_beta` or launch build on https://wago.tools/api/builds) or All The Things adds WoW Forever data. Rebuild in the order in `CLAUDE.md` and run its checks.
2. **Merge players' discoveries** from the "Share discoveries" issues:
   1. Save each pasted text as a `.txt` file, plus any attached `WaypointTracker.lua`.
   2. Run `python3 tools/merge_discoveries.py <files>` and check the diff of `WaypointTracker_Data/Forever.lua`.
   3. Thank the posters and close the issues.
3. Add a `## X.Y.Z` section at the top of `CHANGELOG.md`. A data-only update is a patch version, like `1.0.1`.
4. Commit to `main`, then publish a release `vX.Y.Z` as in phase E, or run `git tag vX.Y.Z && git push origin vX.Y.Z`. Tags with `-beta` or `-alpha` upload as Beta or Alpha files.
5. **On launch day (November 4):**
   - Refresh the data from the launch build.
   - Check the game's interface number. If it's no longer 16001, update `## Interface:` in both `.toc` files.
   - Run the sanity checks in `docs/RELEASE_CHECKLIST.md`, then release.
   - If CurseForge adds a new Forever game version, update `CF_GAME_VERSION`.
   - Update the install path everywhere it appears: `_classic_beta_` becomes the launch game folder shown in the Battle.net app (README, `docs/CURSEFORGE.md`, `docs/WAGO.md`, `site/`, `docs/wiki/`). Also update the README FAQ's "in beta now".

## 12. Report back to the owner

When you finish, or stop, report:

- What you completed in each phase, and anything that didn't match this pack (with what you did instead).
- These links and IDs:
  - the GitHub release URL
  - the CurseForge project URL and project ID, and the file ID or display name of the first file
  - the Wago project URL, if done
- The moderation status.
- Every place you posted, with links to the posts.
- Anything waiting on the owner: logins, 2FA, decisions, a Sponsors page that wasn't live.
- Never include tokens or passwords.

---

## Sources

- Creating a project: https://support.curseforge.com/support/solutions/articles/9000197241
- Submission guide and tips (logo 400×400+, 1:1, PNG; Markdown description): https://support.curseforge.com/support/solutions/articles/9000199552
- Moderation policies (naming, avatars, AI images, credits): https://support.curseforge.com/support/solutions/articles/9000197279
- File types and syncing (Release/Beta/Alpha): https://support.curseforge.com/support/solutions/articles/9000197242
- Distribution toggle: https://support.curseforge.com/support/solutions/articles/9000207877
- WoW moderation hours: https://support.curseforge.com/support/solutions/articles/9000198422
- Upload API (`X-Api-Token`, `/api/game/wow/versions`, `/api/projects/{id}/upload-file`): https://support.curseforge.com/support/solutions/articles/9000197321
- Rewards: https://support.curseforge.com/support/solutions/articles/9000197902
- Author terms (attribution of open-source material): https://legal.overwolf.com/docs/curseforge/mod-authors-terms/
- Forever flavour on CurseForge (`gameVersionTypeId=88568`): https://www.curseforge.com/wow/search?class=addons&gameVersionTypeId=88568
- Forever TOC details (`_Camelot` suffix, Interface 16001): https://warcraft.wiki.gg/wiki/TOC_format
- Wago API (Forever patches; `forever: 1.60.1` on October 2, 2026): https://addons.wago.io/api/data/game
- WoWInterface compatible versions (no Forever entry on October 2, 2026): https://api.wowinterface.com/addons/compatible.json
- Blizzard's add-on policy (free, not obfuscated, no in-game ads or donation asks): https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534
- World of Warcraft: Forever beta and launch on November 4, 2026: https://news.blizzard.com/en-us/article/24304160/the-world-of-warcraft-forever-beta-now-live and https://news.blizzard.com/en-us/article/24301145/world-of-warcraft-at-blizzcon-2026-discover-whats-next
- Beta level cap 30 from October 1, beta until October 21, launch at 3:00 PM PST: https://us.forums.blizzard.com/en/wow/t/beta-update-maintenance-october-1/2367661, https://www.warcrafttavern.com/forever/news/level-cap-increasing-to-30-tomorrow-in-the-wow-forever-beta/ and https://mmohuts.com/news/wow-forever-beta-level-cap-moves-to-30-after-october-1-maintenance
- Newest client builds: https://wago.tools/api/builds
- A release published in GitHub's web UI creates the tag and fires the tag push event (when the tag is new): https://github.com/orgs/community/discussions/16244
- GitHub topics (20 per repository), social preview (1280×640), visibility and default branch: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics, https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview, https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility and https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-branches-in-your-repository/changing-the-default-branch
- Google on AI search (no special markup; `llms.txt` ignored): https://www.searchenginejournal.com/googles-new-ai-search-guide-calls-aeo-and-geo-still-seo/575026/
- Blizzard forum threads: https://us.forums.blizzard.com/en/wow/t/wow-forever-addons/2362999 and https://us.forums.blizzard.com/en/wow/t/official-wow-forever-discord/2351698
