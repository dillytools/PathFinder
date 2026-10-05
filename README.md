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


## Use
The **minimap button** (drag it around the minimap's edge) opens a menu: Start travel / Stop, Go to the nearest town, Go to the quest objective, Draw navigation maps, whether `PathFinder.ahk` is running (and how to start it if not; the game can't start programs), and Options. **Options > AddOns > PathFinder** has checkboxes for extra world map zoom (three steps past the normal maximum, for a closer look at points), the minimap route line, the travel panel, the world marker, closing the world map on travel, stopping on movement keys, and the minimap button, plus shortcuts to draw, check the script, import and export

## Wrote up a whole page yesterday and accidentally closed my browser so I'll do it tomorrow

## Blizzard ToS
This addon violates the One Key Per Action paradigm as well as numerous other ToS violations and thus using it puts your account at risk of being banned. It may be more or less likely based on the fact that it is mostly driven by Blizzard's own addon tooling, but I can't say for sure. 
