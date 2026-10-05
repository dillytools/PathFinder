local _, ns = ...

---------------------------------------------------------------------------
-- The link to AHK\PathFinder.ahk (in this addon's folder), which does the
-- input. Addons can't start programs, so you start it yourself and leave it
-- running; it idles until the command dot asks for something.
--
-- It reports back the only way a program can reach the game, with a key
-- press: Ctrl+Alt+Shift+F9 every few seconds while WoW has focus, which this
-- file binds (an override binding, never saved) to a hidden button. Starting
-- a route without hearing from it shows where to find it.
---------------------------------------------------------------------------

local SIGNAL_KEY = "CTRL-ALT-SHIFT-F9"      -- PathFinder.ahk HeartbeatKey must match
local ALIVE_TIMEOUT = 8                      -- seconds without a report before it counts as not running
local CHECK_DELAY = 3                        -- seconds after starting a route to check
-- Where PathFinder.ahk is, shown in the popup. Addons can't find out where the game is installed
-- (no API gives a disk path), so this is the usual install for the Forever beta, and
-- /pf ahkpath <folder> sets your own once (saved). The script's spot inside the addon,
-- Interface\AddOns\PathFinder\AHK, is the same on every machine.
local DEFAULT_PATH = "C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_\\Interface\\AddOns\\PathFinder\\AHK"

local function ScriptPath()
    return ns.db and ns.db.ahkFolder or DEFAULT_PATH
end

local seen                  -- GetTime() of the last report

function ns.AHKAlive()
    return seen ~= nil and GetTime() - seen < ALIVE_TIMEOUT
end

local signal = CreateFrame("Button", "PathFinderAHKSignal", UIParent)
signal:SetScript("OnClick", function() seen = GetTime() end)

local bindOwner = CreateFrame("Frame")
local pending = false

-- Bindings can't change in combat; retried when it ends.
local function Bind()
    if InCombatLockdown() then pending = true return end
    pending = false
    ClearOverrideBindings(bindOwner)
    SetOverrideBindingClick(bindOwner, false, SIGNAL_KEY, signal:GetName())
end
ns.RegisterEvent("PLAYER_ENTERING_WORLD", Bind)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if pending then Bind() end end)

StaticPopupDialogs["PATHFINDER_START_AHK"] = {
    text = "PathFinder.ahk isn't running, so nothing will press the keys. The game can't start it for you.\n\n"
        .. "Install AutoHotkey v2, then right-click |cffffd100PathFinder.ahk|r and choose |cffffd100Run script|r. It's in this folder:\n\n%s\n\nLeave it running; it idles between routes.",
    button1 = "Copy path",
    button2 = OKAY,
    OnAccept = function() ns.ShowTextBox("PathFinder.ahk folder  (Ctrl+C to copy)", ScriptPath()) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- After a route starts: if the script still hasn't reported, say where it is.
function ns.CheckAHK()
    C_Timer.After(CHECK_DELAY, function()
        if ns.Navigator.IsActive() and not ns.AHKAlive() then
            StaticPopup_Show("PATHFINDER_START_AHK", ScriptPath())
        end
    end)
end

ns.RegisterCommand("ahkpath", "<folder> - where PathFinder.ahk is on this PC, for the popup (empty: back to the default)", function(arg)
    arg = strtrim(arg or ""):gsub("[\\/]+$", "")
    ns.db.ahkFolder = arg ~= "" and arg or nil
    ns.Print("PathFinder.ahk folder:", ScriptPath())
end)

ns.RegisterCommand("ahk", "- is PathFinder.ahk running?", function()
    if ns.AHKAlive() then
        ns.Print("PathFinder.ahk is running")
    else
        StaticPopup_Show("PATHFINDER_START_AHK", ScriptPath())
    end
end)
