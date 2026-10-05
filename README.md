# PathFinder

Walks you from where you stand to:

• A destination marker you place on the world map

• The nearest town (`/goto town`) or 

• Your current quest objective (`/goto objective`)

The addon uses **navigation map assets**: a named set of linked points, marked Safe or Dangerous, drawn on each zone's map. The addon comes with some default maps you can use to start walking immediately, or you can create your own maps for local use or push them to the official repo and I will review them for inclusion. As navigation maps are their own distinct asset, they can be easily shared. 

While some WoW path finding solutions rely on complex C++ libraries and external geometry-reading tools, this addon relies solely on WoW's own Lua and tried and tested AHK. It is intended primarily for casual, ease-of-use cases and not highly specific navigational needs.

## Install
1. Copy this `PathFinder` folder into `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`.
2. Install [AutoHotkey v2](https://www.autohotkey.com/).
3. Right-click `Interface\AddOns\PathFinder\AHK\PathFinder.ahk` and choose **Run script**. If you try to run the path finder without running the script it will prompt you with a directory where the script is likely located and you can run it there. Due to Blizzard's API limitations the addon is unable to run the script from the game, you must do it yourself.


## Use
The **minimap button** (drag it around the minimap's edge) opens a menu: Start travel / Stop, Go to the nearest town, Go to the quest objective, Draw navigation maps, whether `PathFinder.ahk` is running (and how to start it if not; the game can't start programs), and Options. **Options > AddOns > PathFinder** has checkboxes for the minimap route line, the travel panel, the world marker, closing the world map on travel, stopping on movement keys, and the minimap button, plus shortcuts to draw, check the script, import and export.

1. Make sure `AHK/PathFinder.ahk` is running (see Install).
2. **Draw a map.** Open the world map and left-click the PathFinder icon (top-right of the map, just left of Questie's icon), or type `/pf draw`. Other map icons hide while drawing (your arrow stays).
   - The bar: **Load map** (installed maps grouped by zone, your current zone first, plus **New map**; a built-in map becomes your own copy when saved), **Undo** (or Ctrl+Z; last 20 edits of this map, this session), **Clear map** (deletes the points on the open map, after asking; it can't be undone, so Undo greys out after it), **Save map** (shows the map's name, type and zone, not editable there; **Save** stores it with its zone (the zone most of its points are in, e.g. The Barrens) and you keep drawing on it; **Delete map** deletes it after confirming (a new drawing is just dropped; a built-in map can't be deleted); **Cancel** goes back to drawing). Undo, Clear map and Save map grey out when there's nothing to undo, clear or save (a map with no points can't be saved; delete an emptied saved map with `/pf delete`).
   - Under the bar, a bordered box shows **Current navigation map** with a text field to name or rename the map (a new map starts as "Unnamed Map"), **Type** with **Safe** and **Dangerous** buttons, a note for an uncreated map (how to start one), a built-in map or unsaved changes, then the mouse controls and the point count. Its **-** button folds it down to the name and type rows; **+** brings it back (remembered).
   - Left-click to place a point; each links to the selected (white) point. Click a point to select it, then Shift+click another to link or unlink them. Ctrl+click a point to make it a town (gold, larger) or not, right-click a point to delete it, drag a point to move it.
   - Loading another map or starting a new one only asks to save if the current map actually changed (the same as when it was loaded or last saved counts as unchanged, even after undoing back). Closing the world map keeps an unsaved drawing for next time.
3. Outside drawing mode, Alt+click the map to set the destination, and drag it to move it.
4. With a destination set, the top of the map has **Start travel** and **Clear destination**. Start travel lists the navigation maps installed for the zone you're in (name, Safe/Dangerous, zone); pick one and it closes the map and walks you there, stopping on arrival. The button becomes **Stop**. With no map for your zone it says "This zone has no navigational pathways."
5. While travelling, a panel near the top of the screen shows the map's name and type, the time left and the yards left (drag to move it); the rest of the route is drawn on the minimap; and the next navigation point (then the goal) is marked in the 3D world with Blizzard's floating map-pin marker. Addons can't draw lines in the 3D world, so one marker at a time is the most the game allows. Any map pin you had comes back when the route ends.
6. `/goto town` and `/goto objective` use the first Safe map installed for your zone (else the first Dangerous one); `/goto destination` is the same as Start travel. `/goto town` walks to the nearest town by walking distance along the links. `/goto objective` walks toward the objective of the quest you've selected (click it in the quest tracker or log): with Questie loaded, the unfinished objectives' spawn points make a circle (their centre and furthest spread), and the route ends at the reachable point nearest that circle's edge; with no area it goes straight to the objective (the Questie spawn, or Blizzard's quest waypoint, which is also the hand-in for a finished quest).

It stops when you press Escape or one of your movement keys (whatever you have bound to forward, back, turn, strafe, jump or autorun); spells, other keys and the mouse don't stop it. It also stops on arrival, combat, death, a taxi, a loading screen, or when stuck (it jumps after a second without progress and gives up after four). It pauses while a chat box has focus. Turn strength follows the heading error (three levels each way), and the AHK script glides the mouse speed between levels with an exponential ease. If turns wobble past the target, lower `TurnSpeed` near the top of `AHK/PathFinder.ahk`; if they crawl, raise it; raise `TurnEase` for softer changes.

Points are stored in world coordinates, so a map can cross zone borders. Position isn't available in instances. Points from before named maps existed became your maps "My Safest paths" and "My Fast & Dangerous paths".

## Sharing maps
- `/pf export`: pick a map, then copy its text (Ctrl+C) to post or send.
- `/pf import`: paste a map's text (Ctrl+V) to install it as one of yours.
- `/pf delete`: delete one of your maps. `/pf maps` lists everything installed.
- PathFinder ships with one built-in map, **Thousand Needles** (Safe).
- **Contributing to the addon:** add the exported text as a line in `Maps/Community.lua` (`ns.AddMapString("PF1~...")`). Those maps are installed for everyone and listed as built-in. The format is plain data, `PF1~name~safe or fast~zoneID~zone name~points`, with points as `id,continent,x,y,town,link:link` separated by `;`. Nothing in it runs as code, and a damaged line only skips that map.

## Files
| File | What it does |
|---|---|
| `PathFinder.toc` | Addon manifest. |
| `AHK/PathFinder.ahk` | The AutoHotkey v2 script that does the input: reads the command dot, holds W, mouse-look turning with eased speed, taps Space, heartbeat key. |
| `AHKLink.lua` | Knowing whether `PathFinder.ahk` is running (its Ctrl+Alt+Shift+F9 heartbeat, override-bound to a hidden button), the "isn't running" popup with its location, `/pf ahk`. |
| `Core.lua` | SavedVariables (`maps`, `nextMapId`, `finish`, `hud`, `minimap`, `options`), event bus, rounded-corner curves (`ns.QuadBezier`, `ns.CornerCuts`, `ns.RoundedPath`), `ns.Log`, map/world conversions, `ns.MapAxes` (north/west per map, so no world-axis assumption), `ns.GetPlayerPose()`, slash command registry, `/pf pos`. |
| `Graph.lua` | Points and two-way links of the map chosen with `Graph.Use(map)`: add, remove (rejoins a chain), link/unlink, towns, count on a uiMap, nearest, Dijkstra distances and shortest path, 20-step undo. |
| `Maps.lua` | Navigation map assets: your maps (SavedVariables) and built-in ones, text encode/decode, lists for a zone, the default (first Safe) map, save/delete, migration from the old single network. |
| `Maps/Community.lua` | Built-in maps contributed by players, one `ns.AddMapString` line each. |
| `UI.lua` | The map picker list, the save dialog (name, Safe/Dangerous, zone), and the export/import text box. |
| `MapEditor.lua` | World map: the draggable destination, path drawing mode (draws the map being edited; hides every other canvas child, Blizzard or addon, via alpha, keeping your arrow, the tile layers and the map's own exploration/highlight layers), the map icon (placed like Questie's: TOPRIGHT of the canvas container, left of any Krowi_WorldMapButtons icons), the travel bar (Start travel / Clear destination) and the drawing bar (Load map / Undo / Clear map / Save map) with its foldable instructions box, `/pf draw`, `/pf here [dest]`. |
| `Navigator.lua` | Map choice for Start travel, route building to the destination or nearest town, steering, the command dot (second row, first column at the window's top-left; each channel one of four levels 0/85/170/255: green = none / steering / W+Space / W, red = turn left strength, blue = turn right strength), stuck handling, stopping on Escape or your movement keys, `/pf go`, `/pf town`, `/pf stop`, `/goto`. |
| `Objective.lua` | `/goto objective`: selected quest (`C_SuperTrack`), objective area from Questie's spawn data or Blizzard's `C_QuestLog.GetNextWaypoint`, navigation point nearest the area's edge. |
| `Share.lua` | `/pf export`, `/pf import`, `/pf delete`, `/pf maps`. |
| `HUD.lua` | While travelling, the panel with the map's name and type, time left and yards left. |
| `Minimap.lua` | While travelling, the rest of the route as a line on the minimap, clipped to its edge; handles rotating and square minimaps. |
| `MinimapButton.lua` | The minimap button and its menu, `/pf minimap`. |
| `Options.lua` | Options > AddOns > PathFinder (`PathFinderDB.options`, `.minimap.shown`), `/pf options`. |
| `WorldView.lua` | While travelling, moves Blizzard's tracked map pin to the next navigation point (zone map, or the continent for points past its edge) so it shows in the 3D world; restores your own pin afterwards. |

## Slash
`/pf` or `/pathfinder`: `options`, `minimap`, `pos`, `ahk`, `ahkpath <folder>`, `draw`, `here [dest]`, `go`, `town`, `objective`, `stop`, `maps`, `export`, `import`, `delete`. `/goto town`, `/goto destination`, `/goto objective`.

## Blizzard ToS
Automated movement driven by game state is what Blizzard bans for, even with you watching. Keep testing short and attended, ideally on a beta or throwaway account.
