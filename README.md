# PathFinder

Walks you from where you stand to:

- A destination marker you place on the world map
- The nearest town (`/goto town`) or 
- Your current quest objective (`/goto objective`)

The addon uses **navigation map assets**: a named set of linked points, marked Safe or Dangerous, drawn on each zone's map. The addon comes with some default maps you can use to start walking immediately, or you can create your own maps for local use or push them to the official repo and I will review them for inclusion. As navigation maps are their own distinct asset, they can be easily shared. 

<img width="3840" height="2160" alt="21" src="https://github.com/user-attachments/assets/2e6517d0-0d2a-4c03-b539-b8b4c28af4b7" />

While some WoW path finding solutions rely on complex C++ libraries and external geometry-reading tools, this addon relies solely on WoW's own Lua and tried and tested AHK. It is intended primarily for casual, ease-of-use cases and not highly specific navigational needs.

## Preview

https://github.com/user-attachments/assets/8255db6e-b6b7-4bc4-9bbd-b695b33e1cb8


## Install
1. Copy this `PathFinder` folder into `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`.
2. Install [AutoHotkey v2](https://www.autohotkey.com/).
3. Right-click `Interface\AddOns\PathFinder\AHK\PathFinder.ahk` and choose **Run script**. If you try to run the path finder without running the script it will prompt you with a directory where the script is likely located and you can run it there. Due to Blizzard's API limitations the addon is unable to run the script from the game, you must do it yourself.


## Quick Use
The **minimap button** has the following options: 
- Start travel to destination (if one has been set on the map, using alt+left click)
- Go to the nearest town
- Go to the current quest objective
- Open map editor for drawing navigation maps for the current zone
- Whether `PathFinder.ahk` is running (which is required for the addon to work)
- In addition to the minimap button, you can use commands like (`/goto town`), (`/goto objective`), (`/goto destination`) and/or create macros for them if you prefer that over commands or the minimap icon. 

## Nav Map Creation
Although the addon comes with default provided navigational maps, you can also create your own for your own use-cases and scenarios.
- To create a map, open the map and zone you want and press the PathFinder icon in the top right corner.
- Read the instructions on point/node placement.
- Left clicking will place a navigation node. The placed node will become 'selected', causing it to turn white. White indicates the currently selected node.
- Left clicking again places a new node and connects the previous node. The new node will now become the 'selected' white node and the previous node will be blue, which is the color of normal/unselected nodes. This allows for rapidly creating point splines.
- You can click and drag existing nodes to move/refine them.
- The addon allows zooming in far more on maps for more precise node placement.
- Right clicking a node will delete it.
- Selecting a node and shift clicking another node will connect disjointed nodes.
- Ctrl+Z will undo up to 20 placed nodes (as well as the undo button).
- If you ctrl+left click a node, it registers it as a "town" node and turns it yellow. The path finder will attempt to route to these nodes when you select /goto town, so place them closest to towns.
- Sometimes node placement on maps isn't precise enough for things like stairs or thin walkways. For this, there is a hotkey you can add under Keybindings -> Addons (I set mine to F5).
- When you stand at a location and press F5, it will prompt you to add a node at that location to a particular map. If you open that map in map edit mode, the node will appear. This can be used for precise navigation up stairs, over ledges etc.

## Saving Your Map
Once your map is completed, you should save it.
- Give your map a name. It could be something like "Custom [Zone] Map" or "My Durotar Map" or just the name of the zone, etc. 
- Select whether your map is safe (follows roads, unlikely to encounter hostile mobs) or dangerous (likely to encounter hostile mobs)
- Select whether your map navigation spline uses linear or curved/bezier nodes. In most cases this doesn't make a difference, bezier splines can offer slightly smoother routing but linear may be required for precise movement so it is the default.
- Click the save button. All your information should be filled in already. Save the map.
- Your map is now accessible any time you use path finding features. For instance, if you were to use /goto town, the dropdown menu would now include your map.

## Sharing Your Map
I intend to take the approach of 1 file per map, so that nav maps can be easily shared among the community, as well as pushed to this repo so I can review and include them since creating paths for every zone is a lot of work, not to mention variations. This is currently possible using the addon but I intend to streamline it and will further explain the steps then.

## Future Functionality
I plan to make the path finding features as practical and easy to use as can be done using the Lua API and AHK. Intended features include:
- Incorporation of flight paths into routes
- Use of consumables/abilities for movement speed
- Evasive maneuvers for hostile mobs
- Support for methods of travel such as zeppelin, boats, and elevators
- Enhanced commands for specific game locations (`/goto [class] trainer`), (`/goto [profession] trainer`), (`/goto mailbox`), (`/goto repair`), (`/goto org`), (`/goto orgrimmar`), (`/goto stormwind`)

## Todo: Editing existing maps

## Blizzard ToS
This addon violates numerous ToS provisions and thus using it puts your account at risk of being banned. It may be more or less likely based on the fact that it is mostly driven by Blizzard's own addon tooling. Use it under the assumption that you will be banned for using it and that way you will never be upset. 
