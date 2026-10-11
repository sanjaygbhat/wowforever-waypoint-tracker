# Waypoint Tracker — UX redesign (implementation-ready spec)

Branch: `ux-redesign` (based on `real-routes`). Client: WoW Forever 1.60.1, Interface 16001.
Scope: UX only. All existing functionality is kept; this document says where every piece goes.

Companion file: `PARCELS.md` (work split for concurrent coding agents).

---

## 0. Executive summary (the decisions)

1. **One window.** `WaypointTrackerFrame`, a Blizzard `ButtonFrameTemplate` panel (portrait = addon icon, bottom tabs), registered with Blizzard's UI-panel manager (`RegisterUIPanel`, area `left`, pushable) so it slides in next to the Character/Spellbook/Map frames and **can never overlap another panel**. Three tabs: **Waypoints** (home), **Find**, **Routes**.
2. **No second floating window, ever.** Secondary content (route editor, create route, import/copy text, fix a spot, share/import discoveries, help) is an **in-tab page** with a `< Back` header. Yes/no questions are Blizzard `StaticPopup`s. Pick-one actions are `MenuUtil` context menus. Nothing else floats.
3. **Settings live in Blizzard's Settings panel** (`Settings.RegisterVerticalLayoutCategory` + 5 subcategories). The in-window "More options" panel is gone. `/wp settings` and a bottom-bar **Settings** button open it.
4. **Edit Mode owns every HUD element**: the arrow, its text, the coordinates box and the route-recorder strip each get a Blizzard selection box; clicking one opens one shared settings dialog built from Blizzard's own Edit Mode widget templates. Each Edit Mode layout keeps its own positions. The in-window "Move Arrow" mode is removed (kept in code only as a feature-detected fallback for a client without Edit Mode).
5. **The arrow is never a click target** (unchanged); it ignores the mouse outside Edit Mode.
6. **Entry points**: `/wp` toggles the window; minimap button left-click = window, right-click = quick menu (toggles for Show arrow / Treasure hunt / Real routes, Add waypoint here, Share my location, Edit Mode, Settings); the Addon Compartment does the same; key bindings for every frequent action; Settings panel; world map (pins, Ctrl+right-click, a small Waypoint Tracker overlay button next to Blizzard's map buttons).
7. **Chat is quiet.** Chat lines are only (a) direct replies to something the player typed, (b) ambient notices gated by *Show chat messages*, (c) treasure pings (their own switch). One-time "hello / new feature" lines become in-window notices or HelpTips.
8. **Combat-safe**: showing/hiding a UI panel is protected in combat; in combat the window shows/hides directly at the left-panel position, no taint, no errors.

---

## 1. Diagnosis of today's UX

### 1.1 "/wp opens 2 windows which slightly overlap"
- `Slash.lua:141-147` — `/wp` with no args calls `ns.Find.ToggleBoth()`.
- `Find.lua:1102-1123` — `ToggleBoth` shows **both** `WaypointTrackerFindFrame` (720×556, `Find.lua:11,501`) and `WaypointTrackerFrame` (420×590, `UI.lua:12,774`) and only arranges them side by side when neither has ever been moved and `windowPos` is nil (`Find.lua:1115-1120`). The moment the player drags either, they overlap forever after. Both are `DIALOG` strata + `SetToplevel(true)` (`UI.lua:754-755`, `Find.lua:493-494`), so they fight for the top.
- `UI.lua:1082-1089` — "Show more options" opens a **third** 400×590 panel anchored to the main frame's right edge, i.e. directly over Find.
- Cross-links multiply windows: Find's title bar has **Waypoints** and **Routes** buttons (`Find.lua:520-531`), the main window has a **Routes** button (`UI.lua:787-792`) and four **Find** buttons (`UI.lua:847-873`).
- Minimap button and compartment: left = Find, right = main window (`MinimapButton.lua:72-78,111-117`) — two different "homes".

### 1.2 "clicking routes opens 2 windows more overlapping each other"
- `RoutesUI.lua:425-441` — Routes is an 800×592 `DIALOG` window centred at (0,30), on top of whatever is open.
- `RoutesUI.lua:730-737` — on its first open it immediately opens the **"How it works"** dialog (500×370, centred) on top (`ShowHelp`, `RoutesUI.lua:1070-1096`).
- Every Routes action is another centred floating dialog built by `Dialog()` (`RoutesUI.lua:123-146`): editor (440×330), copy/import text (520×360), replace-or-add ask (420×170), feedback (420×150, top of screen), create (460×300), share (460×290), plus the recorder strip (430×106, `RoutesUI.lua:1166-1218`). Find adds two more: share/import box (520×380, `Find.lua:807-880`) and fix-spot box (460×284, `Find.lua:930-1020`). Saving a route opens the editor → then the share dialog (`RoutesUI.lua:808-822`).
- Inventory: **15 addon frames** can be on screen: main, more-options, Find, Find share box, fix box, Routes, editor, text box, ask, feedback, help, create, share, recorder, Edit Mode dialog; plus arrow, arrow text, coords box, minimap button.

### 1.3 Other problems
- Settings are scattered and duplicated: *Treasure hunt* is in the main window (`UI.lua:1010`) **and** in More options (`UI.lua:1186`); *Share my routes* is in the Routes footer (`RoutesUI.lua:693-699`) **and** in General (`UI.lua:1201`); *This zone only* and *Show low-rated* in the Routes footer are also settings.
- The Blizzard Settings entry is a canvas with one button that **closes Settings and opens our window** (`UI.lua:1330-1359`) — the opposite of native.
- The arrow has two move systems: Edit Mode (`EditMode.lua`) and the in-window "Move Arrow / Done" mode (`UI.lua:989-1003`, `Arrow.lua:245-258`). The coordinates box drags on its own (`CoordsBox.lua:37-46`) and is not in Edit Mode; the recorder strip drags on its own (`RoutesUI.lua:1176-1177`).
- Chat noise: welcome (`Slash.lua:275-278`), *Real routes* teaser 12 s after login (`Travel.lua:1119-1127`), `/way` taken notice (`Slash.lua:285-288`), "Now pointing to", "Waypoint added/removed", route started/stopped/lap, treasure found/gone, route received, "Fly to X" hint (`TravelMap.lua:163`).
- World map: our coordinates line (`MapPins.lua:191-218`) duplicates the client's built-in coordinates panel (`WorldMapCoordsPanelTemplate`, CVars `worldMapShowPlayerCoords`, `worldMapShowCursorCoords`).
- Lists are hand-rolled row pools with a bare `Slider` as scrollbar (`RoutesUI.lua:592-608`); the main window list has no scrollbar at all (`UI.lua:974-982`, 6 rows). Tabs are hand-drawn text buttons with a gold underline (`RoutesUI.lua:477-507`, `Find.lua:587-631`).
- Window position is remembered per screen (`windowPos`, `UI.lua:744-749`); Find and Routes are not remembered; nothing respects Blizzard's panel layout, so our windows cover the map, the quest log, the bags.

---

## 2. What the client offers (verified in `Gethe/wow-ui-source`, branch `forever`)

Everything below exists in WoW Forever's FrameXML. Each row says the fallback to implement with `pcall`/feature-detection (the `tests/run_bare.lua` suite removes optional globals and must still pass).

| Need | Blizzard API / template (exists in `forever`) | Fallback when missing |
|---|---|---|
| Panel that never overlaps other panels | `RegisterUIPanel(frame, {area="left", pushable=5, whileDead=1, width=W, checkFit=1})` (global in `Blizzard_UIParentPanelManager`); `ShowUIPanel(frame)`, `HideUIPanel(frame)`. Protected in combat for insecure code (prints "action blocked", no error). | If `RegisterUIPanel`/`ShowUIPanel` missing **or `InCombatLockdown()`**: `frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116); frame:Show()` / `frame:Hide()`. |
| Esc closes | `tinsert(UISpecialFrames, "WaypointTrackerFrame")` (works for both paths). | — |
| Window chrome | `CreateFrame("Frame", "WaypointTrackerFrame", UIParent, "ButtonFrameTemplate")` → children `.TitleContainer.TitleText`, `.CloseButton`, `.Inset`, `.Bg`, `.TopTileStreaks`, `.PortraitContainer.portrait`; `frame:SetTitle(text)`, `frame:SetPortraitToAsset(path)` (PortraitFrameMixin); `ButtonFrameTemplate_HideAttic(frame)`; `ButtonFrameTemplate_ShowButtonBar(frame)`. Default size 338×424 — we `SetSize(640, 540)`. | `BackdropTemplate` with the current `BACKDROP_DIALOG`, our own title text, icon and `UIPanelCloseButton`. Keep the same child keys (`TitleText`, `CloseButton`, `Inset`) on the frame so tab code is identical. |
| Bottom tabs | `CreateFrame("Button", "WaypointTrackerFrameTab"..i, frame, "PanelTabButtonTemplate")`, `frame.Tabs = {...}`, `tab:SetID(i)`, `tab:SetText()`, `PanelTemplates_SetNumTabs(frame, n)`, `PanelTemplates_SetTab(frame, i)`, `PanelTemplates_TabResize(tab, 0)`; first tab anchored `("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)`. | Plain `Button`s with the current gold-underline look (`RoutesUI.lua:477-507`). |
| Bottom-bar buttons | `MagicButtonTemplate` anchored to `frame` `BOTTOMLEFT`/`BOTTOMRIGHT` (4, 4). | `UIPanelButtonTemplate`. |
| Lists | Own row pool (fixed-height rows) + a `Slider` scrollbar skinned like Blizzard's (`Interface\Buttons\UI-ScrollBar-Knob`). We deliberately **do not** use `ScrollBox`/`ScrollUtil` yet: the test mock drives rows directly and a single code path is safer for 20 agents. (Templates exist for a later swap: `WowScrollBoxList`, `MinimalScrollBar`, `CreateScrollBoxListLinearView`, `ScrollUtil.InitScrollBoxListWithScrollBar`.) | — |
| Search box | `CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")` (`.Instructions`, `.clearButton`, magnifier icon). Plain fields: `InputBoxTemplate`. | Current `Box()` (`UI.lua:170-206`). |
| Multi-line copy/paste | `CreateFrame("ScrollFrame", nil, parent, "InputScrollFrameTemplate")` → `.EditBox`, `.ScrollBar`, `InputScrollFrame_SetInstructions`. | `UIPanelScrollFrameTemplate` + `EditBox` (current `CreateTextBox`, `RoutesUI.lua:861-923`). |
| Dropdowns | `CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")` with `dropdown:SetupMenu(function(dropdown, root) root:CreateRadio(...) end)`, `dropdown:SetDefaultText(text)`/`:OverrideText(text)`. | Current `< text >` `Picker` (`RoutesUI.lua:61-107`). |
| Context menus | `MenuUtil.CreateContextMenu(owner, function(owner, root) root:CreateTitle(); root:CreateButton(text, fn); root:CreateCheckbox(text, isSelected, setSelected); root:CreateDivider() end)` (already used in `Share.lua:146-163`). | Current behaviour: run the first/only action directly (as `Share.ShowMenu` does). |
| Checkbox | `UICheckButtonTemplate` (exists; also `MinimalCheckboxTemplate`). | — |
| Yes/No, 3-way questions | `StaticPopupDialogs[id] = { text, button1, button2, button3, OnAccept, OnCancel, OnAlt, timeout=0, whileDead=1, hideOnEscape=1, preferredIndex=3 }`, `StaticPopup_Show(id, a1, a2, data)`. | Run `OnAccept` directly (current code already does this when `StaticPopup_Show` is nil). |
| Settings panel | `Settings.RegisterVerticalLayoutCategory(name)`, `Settings.RegisterVerticalLayoutSubcategory(cat, name)`, `Settings.RegisterAddOnCategory(cat)`, `Settings.RegisterProxySetting(cat, variable, Settings.VarType.Boolean|Number|String, name, default, getFn, setFn)`, `Settings.CreateCheckbox(cat, setting, tooltip)`, `Settings.CreateSliderOptions(min,max,step)` + `options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fn)` + `Settings.CreateSlider(cat, setting, options, tooltip)`, `Settings.CreateDropdown(cat, setting, function() local c = Settings.CreateControlTextContainer(); c:Add(value, text); return c:GetData() end, tooltip)`, `layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))`, `layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))`, `initializer:SetParentInitializer(parentInit, predicateFn)`, `Settings.OpenToCategory(cat:GetID())`, `Settings.NotifyUpdate(variable)`. `SettingsPanel:GetCategory...`; layout via `SettingsPanel:GetLayout(category)`. Registration must happen inside `SettingsRegistrar` timing — do it on `PLAYER_LOGIN`, wrapped in pcall. | Keep today's canvas category (`Settings.RegisterCanvasLayoutCategory`) **with the same controls drawn by our widgets** (a scrolling frame of checkboxes/sliders), i.e. the old More-options content moves into the canvas. If `Settings` is nil entirely: nothing registered; `/wp settings` opens the window and prints `L.SETTINGS_UNAVAILABLE`. |
| Key bindings | `Bindings.xml` + `BINDING_HEADER_*`/`BINDING_NAME_*` (existing). Settings button "Key Bindings" → `Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)` (retail constant; pcall). | Hide the button. |
| Edit Mode | `EventRegistry:RegisterCallback("EditMode.Enter"/"EditMode.Exit")`, `EditModeManagerFrame:GetActiveLayoutInfo().layoutName`, `EditModeManagerFrame:ClearSelectedSystem()`, `hooksecurefunc(EditModeManagerFrame, "SelectSystem", ...)`, selection box `CreateFrame("Frame", name, owner, "EditModeSystemSelectionTemplate")` with `:ShowHighlighted()`, `:ShowSelected()`, `.system = { GetSystemName = fn }`, `.Label`. Dialog widgets: `CreateFrame("Frame", nil, dialog, "EditModeSettingSliderTemplate")` (`.Label`, `.Slider` = `MinimalSliderWithSteppersTemplate`, `settingFrame:SetupSetting{ displayInfo = {setting=id, type=Enum.EditModeSettingDisplayType.Slider, minValue, maxValue, stepSize, formatter}, currentValue, settingName }`; it calls `self:GetParent():OnSettingValueChanged(setting, value)` and `OnSettingInteractStart/End`), `EditModeSettingCheckboxTemplate` (`.Button`, `.Label`; value 0/1), `EditModeSettingDropdownTemplate`. Dialog chrome: `DialogBorderTranslucentTemplate` child + `UIPanelCloseButton` + `GameFontHighlightLarge` title, like `EditModeSystemSettingsDialog`. `EditModeManagerFrame:EnterEditMode()`/`ShowUIPanel(EditModeManagerFrame)` to enter (out of combat, pcall). | No Edit Mode: our own highlight boxes + the existing `Arrow.SetMoving` drag mode, reachable from Settings ("Move arrow" button). Dialog widgets: our `Widgets.Slider`/`Widgets.Check`. |
| World map | `MapCanvasDataProviderMixin`, `WorldMapFrame:AddDataProvider`, `AddCanvasClickHandler` (existing). Overlay button: `WorldMapFrame:AddOverlayFrame(templateName, "BUTTON", point, relativeFrame, relativePoint, x, y)` or simply `CreateFrame("Button", nil, WorldMapFrame:GetCanvasContainer())` anchored under `WorldMapFrame.WorldMapTrackingPinButton`. Coordinates: CVars `worldMapShowPlayerCoords`, `worldMapShowCursorCoords` (and `coordsByTenths`) drive Blizzard's `WorldMapCoordsPanelTemplate`. | Coordinates: our own line (current `CreateCoords`). Overlay button: anchor `TOPRIGHT` of `ScrollContainer` (-4, -60). |
| Minimap button | Custom button on `Minimap` (LibDBIcon convention; keep). `Minimap:GetWidth()`, `GetMinimapShape`. | — |
| Addon compartment | TOC `AddonCompartmentFunc` is called as `fn(addonName, buttonName)`; `OnEnter(addonName, menuButtonFrame)`. | — |
| First-run hints | `HelpTip:Show(parent, { text=, buttonStyle=HelpTip.ButtonStyle.Close, targetPoint=HelpTip.Point.BottomEdgeCenter, alignment=HelpTip.Alignment.Center, onAcknowledgeCallback=fn, system="WaypointTracker" }, relativeRegion)`. | Print nothing; show the hint text in the tab's status line once. |
| Tooltips | `GameTooltip:SetOwner(w, "ANCHOR_RIGHT")`, `AddLine`, `Show` (existing). | — |
| Colour picker | `ColorPickerFrame:SetupColorPickerAndShow{...}` (existing). | Hide the button. |

---

## 3. Principles

1. One home. Everything is reachable from the window or the quick menu; nothing requires remembering a slash command.
2. Never two of our windows on screen. Pages inside tabs, popups for questions, menus for choices.
3. Native first: Blizzard templates, Blizzard panel placement, Blizzard Settings, Blizzard Edit Mode, Blizzard popups and menus. Our own drawing only where Blizzard has nothing (lists, the 3D arrow).
4. The arrow is a guide, not a widget: never clickable, moved only in Edit Mode.
5. Quiet: chat only when asked or when the player opted in.
6. Nothing lost: §7 maps every existing control to its new place.

---

## 4. Information architecture

```
WaypointTrackerFrame (ButtonFrameTemplate, UIPanel "left", 640x540)
├── Title bar: [icon] Waypoint Tracker                                   [x]
├── Content (Inset)        ← exactly one of:
│     ├── Tab root page                 (Waypoints | Find | Routes)
│     └── Pushed page(s) on that tab    (with "< Back" header)
├── Bottom bar: [tab-specific left button]           [Settings] (MagicButtons)
└── Bottom tabs: [Waypoints] [Find] [Routes]     (PanelTabButtonTemplate)

Blizzard Settings > AddOns > Waypoint Tracker
├── (root) General + buttons: Open Waypoint Tracker · Edit Mode · Key Bindings · Reset All Settings
├── Arrow            (display, text, arrival)
├── Maps             (world map, minimap, coordinates box, following pins/quests)
├── Routes           (player routes + Real routes (beta))
├── Treasure Hunt (beta)
└── Find & Sharing   (learning, discoveries, chat & share options, other addons)

HUD (each is an Edit Mode system):   Arrow · Arrow Text · Coordinates · Route Recorder
Minimap button (+ quick menu) · Addon Compartment · Key bindings · /wp · World map
```

### 4.1 Pages per tab (page stack)
| Tab | Root page | Pushable pages |
|---|---|---|
| Waypoints | Add row + status strip + your waypoints list | — (all actions are rows, menus, popups) |
| Find | search + filters + results list + detail pane | **Correct the spot** (fix), **Share discoveries** (copy), **Import discoveries** (paste) |
| Routes | filters + list + detail pane | **How routes work**, **Create a route**, **Edit route / New route** (editor), **Copy route**, **Import a route** |

Only one page is shown per tab at a time. Switching tabs keeps each tab's page stack. `Back` pops; closing the window pops every stack to the root (so reopening never lands on a stale editor; the editor draft is discarded — the same as closing the dialog today).

---

## 5. Screens (ASCII wireframes)

Sizes are in UI units at scale 1. The frame is 640×540; the Inset is roughly 626×420 (y from −60 to +26 per `ButtonFrameTemplate`, minus the button bar). All text is left-aligned, `GameFontHighlight` body, `GameFontNormal` labels, `GameFontNormalLarge` page titles — exactly the fonts Blizzard's own panels use.

### 5.1 Waypoints tab (home) — normal state
```
┌─(portrait)──────────────────────────────────────────────────────────────┐
│ ◉  Waypoint Tracker                                                  [X] │
├──────────────────────────────────────────────────────────────────────────┤
│  ┃ Pointing to: Sentinel Hill · 412 yds                                 │  ← status strip (1 line; 2 with route)
│  ┃ Following Westfall ore loop: 3 of 12 · 7 min      [Skip] [Stop]      │  ← only while a route runs
│                                                                          │
│  [🔍 Zone or place, or coordinates like 42 65           ] [Name (opt.)] │
│  [Here]  [Set]      Westfall: now type X and Y, like 45 60              │  ← status text (green ok / red error)
│   ┌ dropdown while typing ─────────────────────────────────────────┐    │
│   │ Westfall                                     Eastern Kingdoms  │    │
│   │ Hogger                                   Quest - Elwynn Forest │    │
│   │ Sentinel Hill                        Flight master - Westfall  │    │
│   └────────────────────────────────────────────────────────────────┘    │
│  Your waypoints                                                  (7)    │
│  ┌──────────────────────────────────────────────────────────────┬─┐    │
│  │ ▲ Sentinel Hill            Westfall 56.3, 47.1      412 yds   │▒│    │  ← active row: gold pin, soft gold bg
│  │ ▲ 2/12 Westfall ore loop   Westfall 52.0, 40.1      690 yds   │ │    │
│  │ ▲ Treasure: Solid Chest    Westfall 44.9, 61.0      1.2 km    │ │    │
│  │ ▲ Map pin                  Duskwood 20.0, 30.0   another cont.│ │    │
│  │ ...                                                           │ │    │
│  └──────────────────────────────────────────────────────────────┴─┘    │
├──────────────────────────────────────────────────────────────────────────┤
│ [Remove All]                                              [Settings]     │  ← MagicButtons
└─[Waypoints]─[Find]─[Routes]──────────────────────────────────────────────┘
```
- **Add row**: one `SearchBoxTemplate` (width 360) with the same grammar as `/way` (`Geo.ParseWayArgs`): `zone x y`, `x y`, `#mapID x y`, or a name. Pasting `45.2 67.8` works because it is just text. Beside it an `InputBoxTemplate` **Name** (140). Buttons **Here** (fills the box with your zone and coordinates, like *Use My Position*) and **Set**.
  - Typing shows the existing zone/place dropdown (`UI.lua:320-482` logic unchanged: nothing typed = where you are, your quests, every zone; typed = best matches). Up/Down/Enter navigate. Picking a **zone** writes `"<Zone> "` into the box and focuses it (status: `L.ZONE_PICKED_HINT`). Picking a **place** sets the waypoint immediately.
  - Enter / **Set**: if coordinates parse → `WP.Add` (status `L.ADDED`). If only a name → `Find.Way(text)` (exact single match sets the arrow; otherwise the Find tab opens with that search). Errors use the existing strings (`INVALID_COORDS`, `UNKNOWN_ZONE`, `DID_YOU_MEAN`, `NO_ZONE_SELECTED`, `NO_COORDS`).
  - Share without a waypoint ("Share" button on typed coordinates, `UI.lua:561-578`) moves to: the **Share** entry in the Add box's right-click menu is unnecessary — instead the **Set** button has a right-click: *Share this spot instead* (tooltip says so). Also `/wp share …` and the keybinding stay.
- **Status strip**: active waypoint name + live distance (`L.POINTING_TO`), or `L.ACTIVE_NONE`. Second line only while a route runs, with small **Skip** / **Stop** buttons (`Routes.Skip()`, `Routes.Stop()`).
- **List** (`Widgets.List`, row height 22, as many rows as fit, scrollbar on the right): newest first (today's order). Row: pin icon (gold = active, blue = other), title, grey zone + coords, right-aligned distance. Hover highlight. Tooltip as today (`ROW_TOOLTIP_CLICK`, `ROW_TOOLTIP_SHARE`, `ROW_TOOLTIP_MENU`).
  - Left-click = `WP.SetActive`. Shift-click = `Share.ToChatBox`. Right-click = `MenuUtil` menu: *Point the arrow here*, *Share* → submenu (Party/Raid/Guild/Say/Whisper <target>/Just put it in my chat box — `Share.Channels()`), *Remove*. (The per-row **Share** button and **X** button are replaced by this menu; both actions keep keyboard-free one-click equivalents: shift-click shares, and the menu is one right-click.)
- **Remove All**: `StaticPopup WAYPOINTTRACKER_CLEAR_ALL` (existing) when ≥2.
- **Empty state** (list area): `L.NO_WAYPOINTS_LONG`.
- Arrow preview: while the window is on the Waypoints tab and there is no waypoint, the arrow shows its turning preview (today's `Arrow.SetPreview`), so new players see what they are setting.

### 5.2 Find tab
```
│  [🔍 Search NPCs, quests, objects, items...        ] [All        ▾] [Nearest… ▾]  │
│  ☐ Only my faction   ☐ Only this zone                            Discoveries ▾    │
│  ┌──────────────────────────────┬─┐ ┌──────────────────────────────────────────┐  │
│  │ Hogger                 310 yd│▒│ │ Hogger                                   │  │
│  │ Kobold Vermin           40 yd│ │ │ Enemy  -  Level 11  -  Elite             │  │
│  │ [12] Riverpaw Gnoll Bounty…  │ │ │                                          │  │
│  │ Marshal Dughan <Elwynn…>     │ │ │ Found in: Elwynn Forest                  │  │
│  │ ...                          │ │ │ Closest one: 310 yds away                │  │
│  │                              │ │ │                                          │  │
│  │                              │ │ │                                          │  │
│  │                              │ │ │ [Take me there                        ]  │  │
│  │                              │ │ │ [Wrong spot? Correct it               ]  │  │
│  └──────────────────────────────┴─┘ └──────────────────────────────────────────┘  │
│  23 near you                      Tip: double-click a result, or press Enter…     │
├───────────────────────────────────────────────────────────────────────────────────┤
│                                                                   [Settings]      │
```
- **Kind dropdown** replaces the 6 inner tabs: All / Quests / NPCs / Enemies / Objects / Items (`TAB_*` strings; setting `findTab`).
- **Nearest… ▾** replaces the six buttons: Mailbox, Innkeeper, Flight Master, Repair, Bank, Auction House (`DB.ServiceEntries`). One click opens, one click picks.
- **Discoveries ▾** (right side, `GameFontDisableSmall` label "Discoveries: N" is its text): *Share discoveries* → page, *Import discoveries* → page.
- Filters are the existing settings `findFaction`, `findThisZone`.
- Results list and detail pane behave exactly as today (`Find.lua:153-331`), including the quest scan note in the footer (`SCAN_PROGRESS`) and `Enter` = activate first/selected.
- Empty states: `FIND_START` (changed text), `NEARBY_NONE`, `NO_RESULTS`, `DB_MISSING`, `DB_BROKEN` — unchanged keys.

**Find pages**
```
│  < Back      Correct the spot                                                     │
│  Find has Hogger at Elwynn Forest 24.8, 71.2. Stand where it really is and press  │
│  Use My Position, or type its coordinates on that map. Saved on your computer only.│
│  X [     ]  Y [     ]  [Use My Position]        Elwynn Forest                     │
│  [Save correction]  [It's not there]                                              │
│  [Remove my correction]                                                           │
│  (result line)                                                                    │
```
```
│  < Back      Share discoveries                                                    │
│  Press Ctrl+C to copy (it's already selected). Send it to friends, or paste it …  │
│  ┌──────────────────────────────────────────────────────────────────────────┬─┐   │
│  │ WTL1:...                                                                  │▒│   │
│  └──────────────────────────────────────────────────────────────────────────┴─┘   │
│  (Import page: same box empty + [Import] button + result line)                    │
```

### 5.3 Routes tab
```
│  [🔍 Search routes...      ] [All sources ▾] [All categories ▾] [Nearest ▾] ☐ This zone │
│  ┌────────────────────────────────┬─┐ ┌──────────────────────────────────────────┐  │
│  │ > Westfall ore loop   Westfall │▒│ │ Westfall ore loop                        │  │
│  │   Hillsbrad iron loop  Hillsb. │ │ │ by Thrall  ·  Mining  ·  Westfall        │  │
│  │   Treasure chests - Westfall   │ │ │ 12 points  ·  Loop  ·  1.2 km away       │  │
│  │ ...                            │ │ │ [▲ 14] [▼ 2]  You voted up               │  │
│  │                                │ │ │                                          │  │
│  │                                │ │ │ Following: 3 laps · 14 min               │  │
│  │                                │ │ │ note text...                             │  │
│  │                                │ │ │                                          │  │
│  │                                │ │ │ [Stop route    ] [Skip this point     ]  │  │
│  │                                │ │ │ [Share…        ] [Edit  ] [Delete     ]  │  │
│  └────────────────────────────────┴─┘ └──────────────────────────────────────────┘  │
│  38 routes · Sharing is on · 12 players seen                                   (?)  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ [Create route]  [Import]                                           [Settings]       │
```
- **Sources dropdown** = old tabs All / Ready-made / From players / Mine. **Category** and **Sort** dropdowns as today. **This zone** = `routeThisZone`.
- The footer checkboxes *Share my routes and votes* and *Show low-rated routes* move to Settings > Routes (the footer line still says whether sharing is on; clicking the line opens Settings > Routes).
- **(?)** = `UIPanelInfoButton` → pushes **How routes work** page (`ROUTES_HELP_TITLE`/`ROUTES_HELP_TEXT`, with a **Create route** button). First open of the tab: the detail pane shows the help text instead of `ROUTES_PICK` until a route is selected (`routesHelpShown` flag) — no popup.
- Detail actions (same set as today): Start/Stop, Skip, **Share…** (menu: *Post in Party/Raid/Guild/Say/Whisper <target>*, *Send to my target*, *Copy text…*), Edit, Delete / Remove / Hide this author. Double-click a row = Start.
- **Start** → `Routes.Start(id)`. If the player has other waypoints: `StaticPopup WAYPOINTTRACKER_ROUTE_ASK` (button1 *Replace them*, button3 *Add to them*, button2 Cancel; text `ROUTE_ASK_TEXT` + `ROUTE_ASK_FOOTER`). The "remember my choice" checkbox becomes the Settings dropdown **When you start a route and have waypoints: Ask me / Replace them / Add the route to them** (`routeApply`).
- **How was it?** → `StaticPopup WAYPOINTTRACKER_ROUTE_FEEDBACK` (button1 *Good*, button3 *Not good*, button2 *Not now*), text `ROUTE_FEEDBACK_TEXT` (+ `_WAS_UP/_WAS_DOWN`). Sound as today.

**Routes pages**
```
│  < Back      Create a route                                                        │
│  [Record as I go       ]  Walk your route. A stop is added each time you gather…    │
│  [From my waypoints    ]  Turns your 7 waypoints into a route, in the order…        │
│  [Paste /way lines     ]  Paste a route a friend copied for you, or /way lines…     │
│  Next you name it and save it. Shared routes reach every Waypoint Tracker player…   │
```
```
│  < Back      New route                                                              │
│  Name      [Hillsbrad iron loop                    ]                                 │
│  Note      [optional: level, tips...               ]                                 │
│  Category  [Mining            ▾]     Follow  [Loop              ▾]                   │
│  ☑ Share with everyone (recommended)                                                 │
│  12 points  ·  Hillsbrad Foothills                                                   │
│                                                        [Cancel] [Save]               │
```
Save → pops to the root with the route selected under *Mine*, status `ROUTE_SAVED`, and opens the **Share…** menu anchored to the Share button (replaces the post-save share dialog; `ROUTE_SHARE_SAVED_TITLE` becomes the menu title).
```
│  < Back      Copy this route            |   < Back      Import a route              │
│  help text                              |   help text                               │
│  ┌ InputScrollFrame (selected) ──────┐  |   ┌ InputScrollFrame (empty) ──────────┐  │
│  └───────────────────────────────────┘  |   └────────────────────────────────────┘  │
│                                         |   (result line)             [Import]      │
```
- **Record as I go** hides the window and starts recording; the **Route Recorder** HUD strip appears (§5.7). Finish → window opens on Routes with the editor page.

### 5.4 Empty states
| Where | Text key |
|---|---|
| Waypoints list, none | `NO_WAYPOINTS_LONG` |
| Status strip, no active waypoint | `ACTIVE_NONE` |
| Find, nothing typed, nothing near | `NEARBY_NONE` / `FIND_START` |
| Find, no results | `NO_RESULTS` (+ `SCAN_SEARCH_NOTE`) |
| Find, data addon missing/broken | `DB_MISSING` / `DB_BROKEN` |
| Routes, no matches | `ROUTES_EMPTY` / `ROUTES_EMPTY_MINE` / `ROUTES_EMPTY_SHARED` |
| Routes detail, nothing picked | first time `ROUTES_HELP_TEXT`, after that `ROUTES_PICK` |
| Create route, no waypoints | **From my waypoints** disabled + `ROUTE_NEW_NONE` |

### 5.5 Settings panel (Blizzard Settings > AddOns > Waypoint Tracker)
```
Waypoint Tracker                         (root, vertical layout)
  Set waypoints and follow the arrow. Open the window with /wp or the minimap button;
  move the arrow and its text in Edit Mode.                       ← OPTIONS_PANEL_DESC
  [Open Waypoint Tracker]   Open Waypoint Tracker                 ← button initializer
  [Edit Mode]               Move the arrow, its text, the coordinates box…
  [Key Bindings]            Key Bindings
  ── General ──
  ☑ Show the arrow
  ☐ Always point to the closest waypoint
  ☑ Point to my corpse when I die
  ☑ Remember waypoints after logging out
  ☑ Show the minimap button
  ☑ Show chat messages
  ☐ Use metres instead of yards
  ☑ Let other addons set waypoints          (tooltip: needs /reload)
  ☐ Also show the game's own map pin
  [Reset All Settings]      Reset all settings (keeps your waypoints)   → StaticPopup WAYPOINTTRACKER_RESET

  ▸ Arrow
      ── Arrow Display ──  Arrow size (slider 50–200 %), Arrow visibility (20–100 %),
         Colour (dropdown: Gold far away, green close / Green when facing it / One colour),
         [Pick colour…] (button; shown only when Colour = One colour → parent initializer),
         ☑ Fade when you're heading the right way, ☐ Hide during combat, ☐ Hide on flight paths
      ── Arrow Text ──     Text size, Text visibility, ☑ Show the waypoint name, ☑ Show the distance,
         ☐ Show time to arrive, ☐ Move the text separately
      ── When You Arrive ── Arrival distance (3–50 yds), ☑ Remove the waypoint, ☑ Play a sound,
         ☑ Then point to the next closest waypoint
  ▸ Maps
      ── World map ──  ☑ Show pins on the world map, ☑ Show coordinates on the world map,
         ☑ Ctrl + Right-click the world map to add a waypoint, ☑ Follow the game's map pins,
         ☐ Point to the quest I'm tracking
      ── Minimap ──    ☑ Show pins on the minimap, ☑ Keep the arrow's waypoint on the minimap edge
      ── Coordinates box ── ☐ Show a box with my coordinates   (position: Edit Mode)
  ▸ Routes
      ── Routes ──  When you start a route and have waypoints (dropdown Ask me / Replace them / Add the route to them),
         ☑ Share my routes and votes with other players, ☐ Show low-rated routes
      ── Real routes (beta) ──  ☐ Real routes (beta), ☑ Use flight paths, ☑ Use boats, zeppelins and the tram,
         ☑ Use your hearthstone and teleports, ☑ Show the route on the world map,
         ☑ Learn paths as you walk, ☑ Share paths with other players
  ▸ Treasure Hunt (beta)
      ☐ Treasure hunt; then (children of it): ☑ Chests and treasure, ☑ Rare spawns, ☑ Events and other markers,
         ☐ Lead me to known chest spots, ☑ Ping me when something appears, ☑ Point the arrow at it right away
  ▸ Find & Sharing
      ── Find ──   ☑ Learn NPCs, quests and objects as I play, ☑ Only my faction, ☐ Only this zone
      ── Sharing ── ☑ Start shared spots with [Waypoint Tracker]
```
- Every control is a **proxy setting** over `ns.Get/ns.Set` (variable `WAYPOINTTRACKER_<key>`), so slash commands, the quick menu and the window stay in sync; `ns.On("SETTING_CHANGED")` → `Settings.NotifyUpdate(variable)`.
- Tooltips = existing `*_DESC` strings. Search works for free (Blizzard indexes names).
- Resolution: Blizzard's panel. Nothing to size.

### 5.6 Edit Mode
```
   Edit Mode open (Esc > Edit Mode):

        ┌─────────────────────┐          ┌──────────────── Waypoint Arrow ──────────[x]┐
        │   Waypoint Arrow    │  ←blue   │  Arrow size            [–]━━━━●━━━━[+] 100% │
        │        ▲            │   box    │  Arrow visibility      [–]━━━━━━━●━[+]  80% │
        │   Sentinel Hill     │          │  Text size             [–]━━━━●━━━━[+] 100% │
        │     412 yds         │          │  Text visibility       [–]━━━━━━━●━[+]  90% │
        └─────────────────────┘          │  ☐ Move the text separately                 │
                                         │  ──────────────────────────────────────────  │
        ┌───────────┐                    │  [Reset to default]                          │
        │ 45.2, 67.8│ ← Coordinates box  └──────────────────────────────────────────────┘
        └───────────┘  (its own blue box)
        ┌──────────────────────────────┐
        │ ● Recording: 0 stops  [Add stop] [Finish] [Cancel] │ ← Route Recorder preview (its own box)
        └──────────────────────────────┘
```
- Systems: **Waypoint Arrow** (`ARROW_EDIT_NAME`), **Waypoint Text** (`TEXT_EDIT_NAME`, own box only when *Move the text separately* is on — as today), **Coordinates** (`COORDS_EDIT_NAME`), **Route Recorder** (`RECORDER_EDIT_NAME`). All four are shown while Edit Mode is open even if normally hidden (coords box greyed if its setting is off; recorder shows a preview strip).
- One dialog, `WaypointTrackerEditModeDialog`, styled like `EditModeSystemSettingsDialog` (translucent dialog border, large title, close button), placed beside the selected box on the side with room (today's `PlaceDialog`). Content per system:
  - Arrow: sliders `arrowScale`, `arrowAlpha`, `textScale`, `textAlpha`; checkbox `textSeparate`; **Reset to default** (today's `Arrow.Reset`).
  - Text (when separate): sliders `textScale`, `textAlpha`; checkbox `textSeparate`; Reset.
  - Coordinates: checkbox `coordsBox` ("Show a box with my coordinates"); Reset (position).
  - Route Recorder: Reset (position) only, plus a line *Shown while you record a route*.
- Changes apply immediately (as Blizzard). Positions saved per layout under `arrowLayouts`, `textLayouts`, `coordsLayouts`, `recorderLayouts` (+ the layout-less fallback keys `arrowPos`, `textPos`, `coordsPos`, `recorderPos`). Dragging a box drags the element; clicking a Blizzard frame deselects ours (existing hook).
- Outside Edit Mode none of the four accepts the mouse, except the recorder's buttons (it is a toolbar) and the coords box (no mouse at all).

### 5.7 HUD: Route Recorder strip
```
   ┌──────────────────────────────────────────────────────────────┐
   │ ● Recording: 3 stops   ☑ Add a stop when I gather…           │
   │ [Add stop here] [Finish] [Cancel]                            │
   └──────────────────────────────────────────────────────────────┘   default: TOP of screen, y -120
```
Same controls as today (`RoutesUI.lua:1157-1222`). Not draggable outside Edit Mode. Frame `WaypointTrackerRouteRecorder`.

### 5.8 Minimap button, tooltip and quick menu
```
  Tooltip:                               Right-click menu (MenuUtil):
  ┌ Waypoint Tracker ───────────────┐    ┌ Waypoint Tracker ─────────────────┐
  │ Pointing to: Sentinel Hill 412y │    │ ☑ Show the arrow                  │
  │ Left-click: open Waypoint Tracker│   │ ☐ Treasure hunt (beta)            │
  │ Right-click: quick menu          │   │ ☐ Real routes (beta)              │
  │ Drag: move this button           │   │ ───────────────────────────────── │
  └─────────────────────────────────┘    │   Add a waypoint where you stand  │
                                         │   Share my location in chat       │
                                         │   Remove the arrow's waypoint     │
                                         │ ───────────────────────────────── │
                                         │   Edit Mode                       │
                                         │   Settings                        │
                                         └───────────────────────────────────┘
```
The compartment entry uses the same tooltip (minus the drag line) and the same click mapping.

### 5.9 World map
```
   WorldMapFrame canvas                                          [⚙ filters] ← Blizzard
                                                                 [📍 pin   ] ← Blizzard
                                                                 [▲ WT     ] ← ours (24x24, Pin icon)
   ▲ gold pin = arrow's waypoint      ▲ blue pins = others
   (Ctrl + right-click anywhere: add a waypoint)
   Bottom-left: Blizzard's own coordinates panel (player / cursor) — we switch it on via CVars
```
- Our overlay button tooltip: `MAP_BUTTON_TOOLTIP` + hints. Click → menu: title *Waypoint Tracker*; one entry per waypoint on this map ("Point the arrow here" semantics; the active one checked); divider; *Show pins on the world map* (checkbox = `worldPins`); *Show coordinates* (checkbox = `worldCoords`); *Remove All*.
- Pin tooltip and clicks unchanged (`MapPins.lua:44-91`); Real routes steps still listed in the active pin's tooltip; the Real routes line on the map unchanged (`TravelMap.lua`).
- `worldCoords` now means: when the CVars exist, set `worldMapShowPlayerCoords` and `worldMapShowCursorCoords` to `1`/`0` (and do not draw our line); otherwise draw our line as today.

### 5.10 Popups (all `StaticPopupDialogs`)
| id | text | buttons | notes |
|---|---|---|---|
| `WAYPOINTTRACKER_CLEAR_ALL` | `CLEAR_ALL_CONFIRM` (%d) | Yes / No | existing |
| `WAYPOINTTRACKER_RESET` | `RESET_CONFIRM` | Yes / No | existing |
| `WAYPOINTTRACKER_ROUTE_ASK` | `ROUTE_ASK_TITLE`-style text: `ROUTE_ASK_TEXT` (%d) + "\n\n" + `ROUTE_ASK_FOOTER` | button1 `ROUTE_ASK_REPLACE`, button3 `ROUTE_ASK_ADD`, button2 `CANCEL` | `OnAccept`→Apply "replace", `OnAlt`→Apply "add" |
| `WAYPOINTTRACKER_ROUTE_FEEDBACK` | `ROUTE_FEEDBACK_TITLE` (%s) + "\n" + `ROUTE_FEEDBACK_TEXT` (%d) [+ was up/down] | button1 `ROUTE_FEEDBACK_GOOD`, button3 `ROUTE_FEEDBACK_BAD`, button2 `ROUTE_FEEDBACK_LATER` | plays `IG_QUEST_LIST_OPEN` |
| `WAYPOINTTRACKER_ROUTE_DELETE` | `ROUTE_DELETE_CONFIRM` (%s) | Delete / Cancel | new: deleting your own route asks first |
All: `timeout = 0`, `whileDead = 1`, `hideOnEscape = 1`, `preferredIndex = 3`. Fallback without `StaticPopup_Show`: run the primary action.

---

## 6. Entry-point matrix

### 6.1 Slash commands (`/wp`, `/waypoint`, `/waypointtracker`; `/way`, `/wayb`, `/cway` unless another addon owns them)
| Command | Behaviour |
|---|---|
| `/wp` | **Toggle the window** on its last tab (`uiLastTab`, default Waypoints). In combat: direct Show/Hide (no UI-panel call). |
| `/wp find [text]` · `/wp search [text]` | Show window → Find tab; with text, run that search (Find tab search box filled, focus kept out of the box so Esc closes the window). |
| `/wp routes` · `/wp route` · `/wp lists` | Show window → Routes tab (toggle if already on Routes). |
| `/wp routes next|skip|record|new|create|add|stop|test|fast|status` | Unchanged (`Slash.lua:170-199`). `record` with the window open: hides the window first. |
| `/wp settings` · `/wp options` · `/wp config` | `ns.Options.Open()` → `Settings.OpenToCategory(ourCategoryID)`. Fallback: show window + `SETTINGS_UNAVAILABLE`. |
| `/wp editmode` | Enter Edit Mode (`EditModeManagerFrame:EnterEditMode()` via pcall; refuses in combat with `IN_COMBAT_NO_PANELS`). |
| `/wp here [name]` · `/wayb [name]` | Unchanged. |
| `/wp share [zone x y] [name]` | Unchanged. |
| `/wp clear [all]` · `/wp reset` · `/wp remove` | Unchanged. |
| `/wp list` | Unchanged (chat list — an explicit request). |
| `/wp arrow` | Unchanged (toggle + one reply line). |
| `/wp closest` · `/cway` | Unchanged. |
| `/wp treasure [status]` · `/wp hunt` | Unchanged. |
| `/wp travel [on|off|steps|status]` · `/wp realroutes` · `/wp rr` | Unchanged. |
| `/wp help` · `/wp ?` · `/way` (no args) | Help list (updated lines: `HELP_OPEN`, `HELP_OPTIONS`, new `HELP_EDITMODE`). |
| `/way …` / anything else | `AddFromText` (unchanged): coordinates set a waypoint; a bare name → `Find.Way`. |

### 6.2 Minimap button
| Input | Behaviour |
|---|---|
| Left-click | Toggle window (last tab). |
| Right-click | Quick menu (§5.8). |
| Shift + Left-click | Add a waypoint where you stand (`WP.AddHere()`); tooltip line `MINIMAP_TOOLTIP_SHIFT`. |
| Drag (left) | Move around the minimap (angle saved, `minimapAngle`). |
| Hover | Tooltip: title; *Pointing to: X · dist* (or nothing); the three hint lines. |
Setting `minimapButton` hides it (the compartment and `/wp` remain).

### 6.3 Addon Compartment (TOC `AddonCompartmentFunc`)
| Input | Behaviour |
|---|---|
| Left-click | Toggle window. |
| Right-click | Quick menu anchored to the compartment button (`menuButtonFrame` from OnEnter is cached; fallback anchor `UIParent` cursor). |
| Hover | Same tooltip as the minimap button without the drag line. |

### 6.4 Key bindings (`Bindings.xml`, header `BINDING_HEADER_WAYPOINTTRACKER`)
| Binding | Global | Behaviour |
|---|---|---|
| `WAYPOINTTRACKER_TOGGLE` | `WaypointTracker_ToggleWindow` | toggle window |
| `WAYPOINTTRACKER_FIND` | `WaypointTracker_ToggleFind` | toggle window on Find tab (closes if already open on Find; switches if open elsewhere) |
| `WAYPOINTTRACKER_ROUTES` | `WaypointTracker_ToggleRoutes` | same for Routes |
| `WAYPOINTTRACKER_HERE` | `WaypointTracker_AddHere` | unchanged |
| `WAYPOINTTRACKER_SHARE` | `WaypointTracker_ShareHere` | unchanged |
| `WAYPOINTTRACKER_CLEAR` | `WaypointTracker_ClearActive` | unchanged |
| `WAYPOINTTRACKER_CLOSEST` | `WaypointTracker_SetClosest` | unchanged |
| `WAYPOINTTRACKER_ARROW` | `WaypointTracker_ToggleArrow` | unchanged |
| `WAYPOINTTRACKER_TREASURE` | `WaypointTracker_ToggleTreasure` | unchanged |
| `WAYPOINTTRACKER_TRAVEL` **(new)** | `WaypointTracker_ToggleTravel` | Real routes on/off (same as `/wp travel`) |
| `WAYPOINTTRACKER_ROUTE_NEXT` | `WaypointTracker_RouteNext` | unchanged |
| `WAYPOINTTRACKER_ROUTE_RECORD_ADD` | `WaypointTracker_RouteRecordAdd` | unchanged |

### 6.5 Settings panel
Options > AddOns > **Waypoint Tracker** (§5.5). Buttons there: Open Waypoint Tracker (closes Settings via `HideUIPanel(SettingsPanel)`, then shows the window), Edit Mode, Key Bindings, Reset All Settings, Pick colour.

### 6.6 Edit Mode
Esc > Edit Mode: four systems (§5.6). Also reachable from the quick menu, Settings and `/wp editmode`.

### 6.7 World map
Pins (click = point arrow, alt-click = remove), Ctrl + right-click = add, overlay button menu (§5.9), Blizzard coordinates panel via CVars, Real routes line, taxi "Fly to X" button (unchanged, `TravelMap.lua:136-164`).

### 6.8 Window chrome
| Input | Behaviour |
|---|---|
| Esc | closes the window (`UISpecialFrames`); in a pushed page Esc still closes the whole window (Blizzard behaviour; Back is a button) |
| Close button | `HideUIPanel` (or `Hide` in combat) |
| Tab click | `Window.ShowTab(key)`, saved to `uiLastTab` |
| `< Back` | pops the page |
| Drag | not movable: Blizzard places UI panels |

---

## 7. Feature relocation table (nothing dropped)

| Today | Where (file:line) | New home |
|---|---|---|
| Main window: zone/X/Y/name boxes, Set Waypoint, Use My Position, smart paste, zone/place dropdown | `UI.lua:794-932` | Waypoints tab Add row (§5.1): one box + Name + Here + Set; dropdown kept |
| Share (typed spot / my spot) | `UI.lua:561-578, 836-839` | Right-click on **Set** (*Share this spot instead*); `/wp share`; keybinding |
| Find buttons Quests/NPCs/Enemies/Objects | `UI.lua:847-873` | Find tab + Kind dropdown |
| Your waypoints list (6 rows, click/shift-click/X/Share) | `UI.lua:621-742, 937-982` | Waypoints tab list (scrollable; click, shift-click, right-click menu with Share submenu and Remove) |
| Remove All (+confirm) | `UI.lua:939-960` | Waypoints tab bottom-left button + same popup |
| Show the arrow | `UI.lua:986` | Settings > General; quick menu; `/wp arrow`; keybinding |
| Move Arrow / Done, Reset | `UI.lua:989-1004` | Edit Mode (dialog **Reset to default**); Settings > root **Edit Mode** button; fallback drag mode only without Edit Mode |
| Arrow size / visibility sliders | `UI.lua:1005-1006` | Edit Mode dialog **and** Settings > Arrow |
| Show more options / Treasure hunt check | `UI.lua:1009-1015` | gone / Settings > Treasure Hunt + quick menu |
| Version text | `UI.lua:1017-1019` | Settings root description line "Version x.y.z" (`VERSION_FMT`) |
| More options: Arrow Display (colour cycler + swatch, fade, hide in combat, hide on taxi) | `UI.lua:1121-1148` | Settings > Arrow (dropdown + Pick colour button) |
| More options: Arrow Text (size, visibility, separate, name, distance, ETA) | `UI.lua:1150-1158` | Settings > Arrow; size/visibility/separate also in Edit Mode dialog |
| More options: When You Arrive | `UI.lua:1160-1165` | Settings > Arrow |
| More options: Real routes (7 options) | `UI.lua:1167-1174` | Settings > Routes > Real routes (beta); on/off also in quick menu, `/wp travel`, keybinding |
| More options: Maps (7 options) | `UI.lua:1176-1183` | Settings > Maps; worldPins/worldCoords also in map overlay menu |
| More options: Treasure Hunt (7 options) | `UI.lua:1185-1192` | Settings > Treasure Hunt; on/off also quick menu/slash/keybind |
| More options: General (13 options) | `UI.lua:1194-1207` | Settings > General (followQuest → Maps; learn, sharePrefix → Find & Sharing; routeSharing, routeAsk → Routes) |
| Reset All Settings | `UI.lua:1210-1230` | Settings > General button + same popup |
| Options > AddOns canvas with "Open" button | `UI.lua:1330-1359` | Replaced by the vertical-layout category; the canvas remains only as the fallback |
| Find window (search, 6 tabs, filters, nearest ×6, list, detail, status, note, learned count, share/import buttons) | `Find.lua:489-800` | Find tab (§5.2): Kind dropdown, Nearest menu, Discoveries menu |
| Find share/import box | `Find.lua:805-905` | Find pages Share discoveries / Import discoveries |
| Fix spot box | `Find.lua:910-1049` | Find page Correct the spot |
| `Find.Way`, `/way name` | `Find.lua:1140-1158` | unchanged; opens the Find tab when needed |
| Routes window (tabs, search, category, sort, this zone, list, detail, votes, actions, status, sharing/low-rated checks, net text) | `RoutesUI.lua:425-745` | Routes tab (§5.3); sharing/low-rated → Settings > Routes |
| Routes: Create route / Import / How it works buttons | `RoutesUI.lua:459-475` | bottom bar Create route, Import; (?) info button |
| Route editor dialog | `RoutesUI.lua:750-855` | Routes page Edit/New route |
| Copy / import text dialog | `RoutesUI.lua:860-950` | Routes pages Copy this route / Import a route |
| Replace-or-add dialog + Remember my choice | `RoutesUI.lua:955-1005` | `StaticPopup WAYPOINTTRACKER_ROUTE_ASK` + Settings > Routes dropdown `routeApply` |
| How was it? dialog | `RoutesUI.lua:1010-1064` | `StaticPopup WAYPOINTTRACKER_ROUTE_FEEDBACK` |
| How it works dialog (+ first-open auto show) | `RoutesUI.lua:1069-1096` | Routes page via (?); first time shown inline in the detail pane |
| Create a route dialog | `RoutesUI.lua:1101-1152` | Routes page Create a route |
| Recorder strip | `RoutesUI.lua:1157-1222` | `Recorder.lua` HUD strip, Edit Mode system |
| Share route dialog (post in chat ×N, send to target, copy) | `RoutesUI.lua:1227-1325` | **Share…** context menu on the detail pane; Copy text → page |
| Minimap button: L = Find, R = window, drag | `MinimapButton.lua:72-78` | L = window, R = quick menu, Shift-L = add here, drag |
| Compartment: L = Find, R = window | `MinimapButton.lua:111-117` | L = window, R = quick menu |
| Coords box (own drag) | `CoordsBox.lua` | Edit Mode system Coordinates; setting in Settings > Maps and its Edit Mode dialog |
| Edit Mode dialog (sliders, separate text, Reset, More Options) | `EditMode.lua:35-81` | Blizzard-styled dialog; **More Options** button removed (Settings is one click away via quick menu / `/wp settings`) |
| World map coords line | `MapPins.lua:166-218` | Blizzard coords panel via CVars when available; our line otherwise |
| World map pins, Ctrl+right-click | `MapPins.lua` | unchanged + overlay button menu |
| Welcome line (once) | `Slash.lua:275-278` | kept (one line, once) — it is the only hint a brand-new player gets |
| `/way` taken notice | `Slash.lua:285-288` | kept (once; it explains a missing command) |
| Real routes teaser 12 s after login | `Travel.lua:1119-1127` | removed from chat; the text (`TRAVEL_NEW`) is a one-time dismissible notice line at the top of the Routes tab (flag `travelNoticeShown`) and the subcategory description in Settings |
| "Fly to X" chat hint | `TravelMap.lua:163` | gated by `chatMessages` (was unconditional) |
| Route received line | `RoutesNet.lua:296` | unchanged (gated) |
| Treasure pings / gone lines | `Treasure.lua` | unchanged (`treasurePing`, `chatMessages`) |
| Keybindings ×11 | `Bindings.xml` | kept + `WAYPOINTTRACKER_TRAVEL` |
| TomTom bridge, Follow, Places, Learn, Travel, Trails, Routes, Database | — | untouched |

Settings keys: all existing keys keep their names and meaning except
- `routeAsk` + `routeApply` → single `routeApply ∈ {"ask","replace","add"}` (migration in `Core.lua`: `routeAsk == false` → keep `routeApply` ("replace"/"add"), else `"ask"`; then delete `routeAsk`).
- `showAdvanced`, `windowPos` → removed (deleted from saved settings on load).
- New: `uiLastTab` ("waypoints"|"find"|"routes"), `coordsLayouts`, `recorderPos`, `recorderLayouts`, `tipsShown` (table of acknowledged HelpTips), `routesHelpShown` (already used ad hoc) and `travelNoticeShown` (exists) become declared defaults.
- `worldCoords` gains CVar behaviour (§5.9).

---

## 8. Behaviour details

### 8.1 Window lifecycle
- Created lazily on first show (as today). `Window.Show(tab)`: out of combat and `ShowUIPanel` available → `ShowUIPanel(frame)`; else direct `Show()` at `("TOPLEFT", UIParent, 16, -116)`. `Window.Hide()` mirrors with `HideUIPanel`.
- `RegisterUIPanel(frame, { area = "left", pushable = 5, whileDead = 1, width = 640, checkFit = 1 })` right after creation (pcall). The frame **must** have the global name `WaypointTrackerFrame` (the manager looks it up by name).
- When the world map (a doublewide panel) opens, Blizzard pushes or closes our panel per its rules — accepted; that is native behaviour.
- `OnShow`: refresh the current tab; `Arrow.SetPreview(tab == "waypoints")`. `OnHide`: pop all pages, preview off, hide dropdown lists, `GameTooltip:Hide()`.
- Refresh cadence: tabs refresh on `WAYPOINTS_CHANGED`, `ACTIVE_CHANGED`, `ROUTES_CHANGED`, `SETTING_CHANGED` and a 0.5 s `OnUpdate` tick for distances (only the visible tab).

### 8.2 Combat
- No protected calls in combat: `ShowUIPanel`/`HideUIPanel`/`Settings.OpenToCategory`/`EditModeManagerFrame:EnterEditMode` are skipped; the window still opens (direct Show). `/wp settings` and `/wp editmode` in combat print `IN_COMBAT_NO_PANELS` (reply to a typed command) and do nothing.
- `PLAYER_REGEN_DISABLED`: nothing closes (our frame is unprotected). The legacy move mode (fallback only) still ends on combat as today.
- Map pins: unchanged (`SetPassThroughButtons` guard stays).

### 8.3 Small screens / scale
- `checkFit = 1` lets Blizzard scale the panel down when UIParent is too small. The Inset content anchors to the frame edges; lists compute row count from their height on `OnSizeChanged`. Minimum usable size 640×540 at UI scale ≤ 1 on 1024×768 is satisfied (Blizzard's own panels are up to 830 wide).

### 8.4 Chat output policy
- `ns.Print(msg)` (gated by `chatMessages`): waypoint added/removed/reached/now pointing (unchanged), route started/stopped/lap/complete, route received, treasure gone, Fly-to hint.
- `ns.Print(msg, true)` (always): replies to typed commands and their errors; the one-time welcome; the one-time `/way` notice; `RELOAD_NEEDED`.
- Removed from chat: Real routes teaser, "Routes help shown" style prompts, `ROUTE_VOTED` (status line only).
- Status lines inside the window (`Window.SetStatus`) take over everything that used to be a chat line as a result of a click in the window.

### 8.5 First-run
- Login: `WELCOME` once (existing).
- First window open: `HelpTip` on the Add box (`TIP_ADD_BOX`), Close button, acknowledged → `tipsShown.add = true`. One tip only; no tour.
- Routes tab first open: inline help in the detail pane (no popup).
- Real routes: notice line in Routes tab until dismissed.

### 8.6 Tooltips
Every button, checkbox and dropdown has a tooltip (`Widgets.Tooltip(widget, title, body)`) using the existing `*_DESC` strings. Rows: existing row tooltips plus `ROW_TOOLTIP_MENU`.

### 8.7 Keyboard
Enter in the Add box sets; Up/Down walk the dropdown; Tab moves Add → Name; Esc in any edit box clears focus (Esc again closes the window). Enter in Find's search activates the selected result (as today).

---

## 9. Strings

### 9.1 New keys (English)
```
L.TAB_WAYPOINTS = "Waypoints"
L.BACK = "Back"
L.SETTINGS = "Settings"
L.SET = "Set"
L.HERE = "Here"
L.ADD_HINT = "Zone or place, or coordinates like 42 65"
L.NAME_HINT = "Name (optional)"
L.ZONE_PICKED_HINT = "%s: now type X and Y, like 45 60"
L.SHARE_INSTEAD = "Right-click: share this spot in chat instead of setting a waypoint"
L.POINTING_TO = "Pointing to: %s"
L.ACTIVE_NONE = "The arrow has nowhere to point yet. Set a waypoint below."
L.FOLLOWING_ROUTE = "Following %s: %d of %d"
L.FOLLOWING_LOOP = "Following %s: lap %d"
L.NO_WAYPOINTS_LONG = "No waypoints yet. Type a zone and coordinates above, Ctrl + right-click the world map, or search in Find."
L.ROW_TOOLTIP_MENU = "Right-click: share or remove"
L.ROW_MENU_POINT = "Point the arrow here"
L.WAYPOINT_COUNT = "(%d)"
L.TIP_ADD_BOX = "Type a place or coordinates here and press Enter. The arrow does the rest."
L.NEAREST_MENU = "Nearest..."
L.DISCOVERIES_MENU = "Discoveries"
L.IMPORT_DISCOVERIES = "Import discoveries"
L.ROUTES_SOURCE_ALL = "All sources"
L.ROUTES_SHARING_LINE = "Sharing is on · %d players seen"
L.ROUTES_SHARING_OFF_LINE = "Sharing is off (change it in Settings)"
L.ROUTE_SHARE_POST = "Post in %s"
L.ROUTE_ASK_FOOTER = "Change what happens here any time in Settings: Waypoint Tracker > Routes."
L.ROUTE_APPLY_OPTION = "When you start a route and have waypoints"
L.ROUTE_APPLY_OPTION_DESC = "Ask me: a question each time. Replace them: the route takes the place of your waypoints. Add the route to them: keep both."
L.ROUTE_APPLY_ASK = "Ask me"
L.ROUTE_APPLY_REPLACE = "Replace them"
L.ROUTE_APPLY_ADD = "Add the route to them"
L.ROUTE_DELETE_CONFIRM = "Delete the route %s? Other players who already have it keep their copy."
L.RECORDER_EDIT_NAME = "Route Recorder"
L.RECORDER_EDIT_HINT = "Shown while you record a route."
L.COORDS_EDIT_NAME = "Coordinates"
L.RESET_DEFAULT = "Reset to default"
L.SETTINGS_FIND_SHARING = "Find & Sharing"
L.SETTINGS_FIND_HEADER = "Find"
L.SETTINGS_SHARING_HEADER = "Sharing"
L.SETTINGS_WORLD_MAP_HEADER = "World map"
L.SETTINGS_MINIMAP_HEADER = "Minimap"
L.SETTINGS_COORDS_HEADER = "Coordinates box"
L.OPEN_EDIT_MODE = "Edit Mode"
L.OPEN_EDIT_MODE_DESC = "Move and resize the arrow, its text and the coordinates box in the game's Edit Mode. Each layout keeps its own spots."
L.OPEN_KEYBINDINGS = "Key Bindings"
L.OPEN_KEYBINDINGS_DESC = "Keys for opening the window, adding a waypoint where you stand, sharing your spot and more."
L.RESET_SETTINGS_DESC = "Puts every setting back to its default. Your waypoints and routes are kept."
L.VERSION_FMT = "Version %s"
L.SETTINGS_UNAVAILABLE = "This game client has no settings panel for addons; the window is open instead."
L.IN_COMBAT_NO_PANELS = "Not during combat. Try again when the fight is over."
L.MINIMAP_TOOLTIP_SHIFT = "Shift + Left-click: add a waypoint where you stand"
L.MENU_QUICK_TITLE = "Waypoint Tracker"
L.MAP_BUTTON_TOOLTIP = "Waypoint Tracker: your waypoints on this map"
L.MAP_BUTTON_CLICK = "Click: pick a waypoint, pins and coordinates"
L.HELP_EDITMODE = "/wp editmode - move the arrow, its text and the coordinates box"
L.BINDING_TRAVEL = "Turn Real routes (beta) on or off"
L.TRAVEL_NOTICE_DISMISS = "Got it"
L.ROUTE_REC_HUD = "Recording: %d stops"
```

### 9.2 Changed English text (same keys)
```
L.FIND_START = "Type a name above, or pick something under Nearest."
L.MINIMAP_TOOLTIP_LEFT = "Left-click: open Waypoint Tracker"
L.MINIMAP_TOOLTIP_RIGHT = "Right-click: quick menu"
L.OPTIONS_PANEL_DESC = "Set a waypoint and follow the arrow. Open the window with /wp or the minimap button; move the arrow and its text in Edit Mode."
L.HELP_OPEN = "/wp - open or close Waypoint Tracker"
L.HELP_OPTIONS = "/wp settings - open the settings"
L.TREASURE_HEADER = "Treasure Hunt (beta)"
L.TREASURE_HUNT = "Treasure hunt (beta)"
L.WORLD_COORDS_DESC = "Show your coordinates and the mouse cursor's coordinates at the bottom of the world map (the game's own coordinates panel where the client has one)."
L.COORDS_BOX_DESC = "A small box that always shows where you are. Move it in Edit Mode."
L.TEXT_SEPARATE_DESC = "Off: the text stays under the arrow and moves with it. On: place the text anywhere on its own in Edit Mode. Turn it off to put the text back under the arrow."
L.ROUTES_EMPTY = "No routes match. Clear the search, pick All sources and All categories, or untick This zone."
L.ROUTE_COPY_HELP = "Press Ctrl+C to copy (it's already selected), then paste it anywhere: a friend presses Import in their Routes tab."
L.ROUTE_RECEIVED = "%s received from %s. It's under Routes > From players."
L.ROUTE_CHAT_LINE = "Route: %s - %d stops in %s. Find it in Waypoint Tracker: /wp routes"   (unchanged text, listed for completeness)
L.EDIT_MODE_HINT = "Move it in Edit Mode (Esc > Edit Mode), with a spot for each layout."
L.MOVE_ARROW_DESC = "Drag the arrow where you like, then click Done. (Only offered on a client without Edit Mode.)"
```

### 9.3 Removed keys (delete from all 9 locale files)
`SHOW_MORE_OPTIONS`, `MORE_OPTIONS`, `FIND_LABEL`, `FIND_TAB_DESC`, `OPEN_WAYPOINTS`, `OPEN_WAYPOINTS_DESC`, `ROUTE_ASK_REMEMBER`, `ROUTE_ASK_OPTION`, `ROUTE_ASK_OPTION_DESC`, `ROUTES_SUBTITLE`, `ROUTE_SHARE_CHAT`, `ROUTE_SHARE_PUBLIC`, `ROUTE_SHARE_PRIVATE`, `ROUTE_SHARE_READY`, `ROUTE_SHARE_OTHER`, `ROW_TOOLTIP_REMOVE`, `SHARE_SPOT_DESC`.
**Keep** (still used): `NO_WAYPOINTS` (chat `/wp list`), `MORE_BELOW` (zone/place dropdown), `ROUTES_HOWTO` (tooltip of the (?) button), `ROUTES_PICK`, and `MOVE_ARROW`, `DONE_MOVING`, `MOVING_HINT`, `MOVE_ARROW_DESC` for the no-Edit-Mode fallback.

Rule for implementers: wave-2 parcels may only use keys listed in `enUS.lua` after wave 1. A key you still need goes into your parcel's `strings-<id>.md` request file (see PARCELS.md); the wave-3 Locales parcel adds it. Never add a key to `enUS.lua` without adding it to the other eight files in the same commit (`tests/check_locales.lua` fails otherwise).

---

## 10. Module/API contract (what every agent can rely on)

```lua
-- Window.lua (ns.Window)                                  global frame: WaypointTrackerFrame
Window.RegisterTab{ key, order, title, build = function(content) end,
                    onShow = fn, onHide = fn, onUpdate = function(elapsed) end,
                    leftButton = { text, onClick, tooltip } | nil }
Window.Show(tabKey?)  Window.Hide()  Window.Toggle(tabKey?)  Window.IsShown()
Window.ShowTab(key)   Window.GetTab() -> key
Window.PushPage(tabKey, { title, build = function(pageFrame) end, onShow, onHide }) -> pageFrame
Window.PopPage(tabKey)   Window.PopAll(tabKey)   Window.CurrentPage(tabKey) -> page|nil
Window.SetStatus(text, good)                      -- bottom status line of the window
Window.frame, Window.tabs[key].content            -- for tests
ns.Fire("UI_TAB_SHOWN", key) on tab change; ns.Fire("UI_SHOWN") / ns.Fire("UI_HIDDEN")
WaypointTracker_ToggleWindow(), WaypointTracker_ToggleFind(), WaypointTracker_ToggleRoutes()  (globals)

-- Widgets.lua (ns.Widgets; ns.UI.W is an alias kept for old call sites)
Widgets.Button(parent, text, w, h) ; Widgets.MagicButton(parent, text, w)
Widgets.Check(parent, label, keyOrAccessor, tooltip, labelWidth)   -- accessor = { get=fn, set=fn }
Widgets.Slider(parent, label, key, min, max, step, w, format, tooltip)
Widgets.EditBox(parent, w, { placeholder, search = true|false, maxLetters, numeric })  -> frame with .edit
Widgets.TextArea(parent, { placeholder })  -> frame with .edit (multi-line, scrolls)
Widgets.Dropdown(parent, w, { text = fn() -> string, menu = function(root) end })  -> frame with :Refresh()
Widgets.Menu(owner, function(root) end)      -- MenuUtil.CreateContextMenu with fallback
Widgets.List(parent, { rowHeight, rowInit = fn(row), rowUpdate = fn(row, item, index, selected),
                       onClick = fn(row, item, button), onDoubleClick = fn(row, item), emptyText })
     list:SetItems(items)  list:SetSelected(item)  list:GetSelected()  list:ScrollTo(index)  list.rows  list:Refresh()
Widgets.Header(parent, text)   Widgets.Label(parent, text, font)   Widgets.Tooltip(widget, title, body)
Widgets.Confirm(id, { text, button1, button2, button3, onAccept, onAlt, onCancel, sound }) ; Widgets.Ask(id, ...fmtArgs)
Widgets.Percent(v)  Widgets.Yards(v)
Widgets.Refresh()  -- re-reads settings into every bound widget (old UI.RefreshWidgets)

-- EditMode.lua (ns.EditMode)
EditMode.RegisterSystem{ key = "arrow"|"text"|"coords"|"recorder", frame, name = L.X,
   settings = { { type = "slider", key, label, min, max, step, format }, { type = "checkbox", key, label }, { type = "dropdown", key, label, options = {{value, text}} } },
   hint = L.X | nil, onReset = fn, defaultPoint = { point, relPoint, x, y }, shouldShow = fn() -> bool,
   selectionInsets = { left, right, top, bottom } }
EditMode.SavedPosition(key) -> pos|nil   EditMode.SavePosition(key, pos)   EditMode.ApplyPosition(key)
EditMode.Select(key)  EditMode.Deselect()  EditMode.IsActive()  EditMode.Enter() -> ok, reason
dialog global: WaypointTrackerEditModeDialog with .reset (Button) and .controls[key]
selection globals: WaypointTrackerArrowSelection, WaypointTrackerTextSelection, WaypointTrackerCoordsSelection, WaypointTrackerRecorderSelection

-- Options.lua (ns.Options)
Options.Open(subKey?)  -- "arrow"|"maps"|"routes"|"treasure"|"find"; nil = root
Options.IsAvailable() -> bool ; Options.categoryID

-- QuickMenu.lua (ns.QuickMenu)
QuickMenu.Show(owner)        QuickMenu.Build(root)      QuickMenu.Tooltip(owner, withDrag)

-- Recorder.lua (ns.Recorder)  frame global WaypointTrackerRouteRecorder
Recorder.Refresh()  Recorder.frame

-- Find.lua (ns.Find)  keeps: Find.Show(text, kind)  Find.Toggle()  Find.IsShown()  Find.Way(text)  Find.Activate(e)
                       Find.ShowFixBox(e)  Find.ShowShareBox(mode)  Find.IsNearby()  Find.widgets
-- RoutesUI.lua (ns.RoutesUI) keeps: Show()  Toggle()  IsShown()  Select(id)  SetTab(sourceKey)  ShowEditor(r)  ShowText(mode, text)
                       ShowShare(r, justSaved)  ShowCreate()  ShowHelp()  Refresh()  Frames()  widgets
-- UI.lua (ns.UI) compat: UI.Show() UI.Hide() UI.Toggle() UI.IsShown() UI.Refresh() UI.RefreshWidgets() UI.W UI.widgets
```

Setting-change propagation: `ns.Set(key, v)` → `SETTING_CHANGED` → (Options) `Settings.NotifyUpdate("WAYPOINTTRACKER_"..key)`; (Widgets) `Widgets.Refresh()`; (EditMode) dialog refresh.
