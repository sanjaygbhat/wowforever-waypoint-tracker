# Follow-up after the launch (October 2, 2026)

A short runbook for an agent with a web browser (or the owner), after the 1.0.0 launch. Do the steps in order. The ground rules of [`CURSEFORGE_AGENT_PACK.md`](CURSEFORGE_AGENT_PACK.md) still apply:
- never paste a token anywhere
- public text says what works
- no other addons named
- stop and ask the owner for any login, 2FA code or decision

## Where things stand

| | |
|---|---|
| GitHub | Public. `main` is the default branch. Release **v1.0.0** (tag on commit `39fa4b6`) holds `WaypointTracker-v1.0.0.zip` |
| CurseForge | Project **1722148**, file **9036099**, **Under Review** on October 2 |
| Wago | Project **ZKxOb36k**, v1.0.0 Stable, Forever 1.60.1 |
| Branch `claude/amazing-brahmagupta-nc13sl` | One commit ahead of `main`: the website, wiki sources, release fixes and search improvements below. **Don't delete it before step 1 is done** |

## 1. Bring the new commit into `main`

1. Open https://github.com/sanjaygbhat/wowforever-waypoint-tracker/compare/main...claude/amazing-brahmagupta-nc13sl
2. Check that it says **Able to merge**, and that the commit list holds only the one new commit.
3. Press **Create pull request** with title `Website, wiki sources and release fixes`, then wait for the **Tests** check to turn green.
4. Press **Merge pull request** → **Confirm merge**.
5. Don't delete the branch from that page; the owner decides.

## 2. Turn on the website (GitHub Pages)

The repository wiki doesn't appear in search engines: GitHub only lets them index wikis of repositories with 500+ stars. The website is the page that search engines and AI assistants find.

1. **Settings → Pages → Build and deployment → Source:** choose **GitHub Actions**. Nothing else to set.
2. **Actions → Website → Run workflow** (branch `main`) → **Run workflow**. Wait for both jobs to turn green.
3. Open https://sanjaygbhat.github.io/wowforever-waypoint-tracker/ and check:
   - the demo GIF and both screenshots load
   - the three buttons open CurseForge, Wago and GitHub Releases. CurseForge shows its page only after approval
4. Also open `robots.txt`, `sitemap.xml` and `llms.txt` at that address. Each should load as plain text or XML.

## 3. Attach `release.json` to the v1.0.0 release

This file tells addon managers like WowUp that the zip is for WoW Forever, so they install it without a warning. Later releases get it automatically.

1. On your computer, make a text file named exactly `release.json` with this content:

   ```json
   {"releases":[{"name":"WaypointTracker","version":"v1.0.0","filename":"WaypointTracker-v1.0.0.zip","nolib":false,"metadata":[{"flavor":"forever","interface":16001}]}]}
   ```

2. Open https://github.com/sanjaygbhat/wowforever-waypoint-tracker/releases/tag/v1.0.0 → the pencil (**Edit**).
3. Drag `release.json` onto **Attach binaries**. Change nothing else, then **Update release**.
4. Check that the release now lists two files, the zip and `release.json`.

## 4. Update the wiki pages

The corrected pages are in [`docs/wiki/`](../wiki). They fix:
- the options sections, so they match the game
- the `/way` wording
- the install line
- some wording, so the pages say what works

For each file below:
1. Open the raw link and copy all of it.
2. Open the wiki page → **Edit**.
3. Select all, paste, and **Save page** with the message `Match the addon`.

| Wiki page | Raw text |
|---|---|
| Home | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Home.md |
| Installation and Quick Start | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Installation-and-Quick-Start.md |
| Commands and Options | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Commands-and-Options.md |
| Troubleshooting and Compatibility | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Troubleshooting-and-Compatibility.md |
| Discoveries Privacy and Contributing | https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/wiki/Discoveries-Privacy-and-Contributing.md |

## 5. Wago listing

1. **Description:** replace it with https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/WAGO.md (Markdown). It names the Wago app in the install line, adds a short Questions section, and has no Sponsors line: the project keeps that link to the README and CurseForge.
2. **Screenshots:** a read-only check found no gallery images on the public Wago page, even though the launch report lists three. Open the project's media settings. If the gallery is empty, upload `01-arrow.jpg`, `02-map.jpg` and `03-window.jpg` with the titles and descriptions from phase B of the launch pack.

## 6. CurseForge, after approval

Wait for approval: editing during review can restart it.

1. Run phase F's checks from the launch pack.
2. **Description:** replace it with https://raw.githubusercontent.com/sanjaygbhat/wowforever-waypoint-tracker/main/docs/CURSEFORGE.md (Markdown). It adds the website link, the beta install path and a short Questions section.
3. Leave the file `WaypointTracker-v1.0.0 (5).zip` as it is. Its display name is right, and replacing it would restart review. Later releases upload with clean names.

## 7. Search engines (optional, the owner's Google and Microsoft accounts)

1. Google Search Console → **Add property → URL prefix** `https://sanjaygbhat.github.io/wowforever-waypoint-tracker/`. For verification, choose **HTML tag** and send the owner the `content="…"` value. A developer adds it to `site/index.html`; then press **Verify**.
2. Once verified, submit `sitemap.xml` under **Sitemaps**, and **URL inspection → Request indexing** for the home page.
3. Bing Webmaster Tools → **Import from Google Search Console**.

## 8. Report back

List each step's result, with the website URL, the release's file list and anything that differed from this page.
