local _, ns = ...

---------------------------------------------------------------------------
-- Walks a route from where you stand to the destination marker placed in
-- MapEditor.lua, or to the nearest town (/goto town): to the point nearest
-- you, along linked points to the one nearest the goal, then straight to it.
-- If the goal is closer than any point, straight there. Routes run on one
-- navigation map (Maps.lua): Start travel lists the maps installed for the
-- zone you're in to pick from; /goto commands use the first Safe one (else
-- the first Dangerous one). No map for the zone: "This zone has no
-- navigational pathways."
--
-- Lua decides; AHK\PathFinder.ahk (in this addon's folder, started by you, see AHKLink.lua) does the input. Each tick, the heading
-- error to the next target picks a command, shown as the color of one dot
-- in the second row of the game window's top-left corner (below where APIHelper's script dots go, if that addon is installed). Walking
-- is W; turning is mouse look: AHK holds the right mouse button for the whole
-- route, so the camera stays behind you facing the way you walk, and moves
-- the mouse sideways to turn, easing its speed toward how hard the dot says
-- to turn. Each channel is one of four levels (0, 85, 170, 255):
--   green  0 none (let go of everything), 1 steering without W, 2 W + Space, 3 W
--   red    how hard to turn left, 0-3
--   blue   how hard to turn right, 0-3
-- Turn strength follows the heading error, so small errors turn gently.
-- PathFinder.ahk must use the same levels and position. The dot is always
-- shown (black when idle), so AHK never reads the game world there.
--
-- Stops on arrival, combat, death, a taxi, a loading screen, or when stuck:
-- no progress for a second makes it jump; four of those on one leg ends it.
-- While a chat box has focus it pauses, so keys don't type into it.
---------------------------------------------------------------------------

local Navigator = {}
ns.Navigator = Navigator

local TICK = 0.03               -- seconds between steering updates
local CURVE_PIECES = 6          -- steering steps around each rounded corner
local LOOKAHEAD = 7             -- yards: steer at the first step at least this far ahead, so small bends don't make it turn
local END_RADIUS = 1.5          -- yards: this close to the pin, done
local TURN_DEADBAND = math.rad(4) -- heading error left alone
local TURN_STEP = math.rad(10)  -- each this much more error is one more level of turn strength (1-3)
local WALK_CONE = math.rad(50)  -- walk while the error is under this, else turn in place
local NEAR_CONE = math.rad(25)  -- tighter cone close to a target, so it doesn't circle it
local NEAR = 6                  -- yards
local STUCK_WINDOW = 1          -- seconds of walking to check progress over
local STUCK_MOVE = 1            -- yards: less than this in a window counts as stuck
local STUCK_JUMP = 0.4          -- seconds to hold jump
local STUCK_LIMIT = 4           -- stuck windows on one leg before giving up
local EXPECT_KEY = 0.6          -- seconds after asking AHK for Space that a Space press counts as AHK's

local MARKER_PIXELS = 4         -- dot size; PathFinder.ahk DotSize must match
local REFERENCE_HEIGHT = 768

local MODES = { none = 0, steer = 1, jump = 2, walk = 3 }   -- green level


---------------------------------------------------------------------------
-- Command dot
---------------------------------------------------------------------------

local dot = CreateFrame("Frame", "PathFinderSteerDot")   -- no parent: stays visible with the UI hidden (Alt+Z)
dot:SetFrameStrata("TOOLTIP")
dot:SetScale(1)
local dotTexture = dot:CreateTexture(nil, "OVERLAY")
dotTexture:SetAllPoints()
dot:Hide()

local function LayoutDot()
    local _, physicalHeight = GetPhysicalScreenSize()
    local size = MARKER_PIXELS * REFERENCE_HEIGHT / physicalHeight
    dot:ClearAllPoints()
    dot:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT", 0, -size)   -- second row (APIHelper's script dots use the first)
    dot:SetSize(size, size)
    dot:Show()
end
ns.RegisterEvent("PLAYER_LOGIN", LayoutDot)
ns.RegisterEvent("DISPLAY_SIZE_CHANGED", LayoutDot)
ns.RegisterEvent("UI_SCALE_CHANGED", LayoutDot)

local WALKS = { walk = true, jump = true }
local mode, turn = "none", 0     -- the command shown now: mode, and turn -3 (hard right) .. 3 (hard left)
-- Until when the next W / Space press is AHK's own, not yours. W waits however long AHK takes
-- to start (the launcher needs a moment), and either is used up by the press it expects.
local expectW, expectSpace = 0, 0

local function SetCommand(newMode, newTurn)
    newTurn = newTurn or 0
    if newMode == mode and newTurn == turn then return end
    if WALKS[newMode] and not WALKS[mode] then expectW = math.huge end
    if newMode == "jump" and mode ~= "jump" then expectSpace = GetTime() + EXPECT_KEY end
    mode, turn = newMode, newTurn
    dotTexture:SetColorTexture(math.max(turn, 0) / 3, MODES[mode] / 3, math.max(-turn, 0) / 3)
end
mode = "walk"   -- so the first call below changes something and paints the dot
SetCommand("none")

---------------------------------------------------------------------------
-- Route state
---------------------------------------------------------------------------

local active = false
local targets = {}              -- { x, y, final } in world yards
local routeNodes                -- point ids on the route, for the map highlight
local markers = {}              -- { index, x, y }: each navigation point and the goal, with its steering point index
local index = 1
local stuckX, stuckY, stuckT, stuckCount = nil, nil, 0, 0
local jumpUntil = 0
local warnedNoPose = false

function Navigator.IsActive() return active end
function Navigator.RouteNodes() return active and routeNodes or nil end

function Navigator.Stop(reason)
    if not active then return end
    active = false
    routeNodes = nil
    SetCommand("none")
    ns.Print("route ended:", reason)
    ns.RedrawMap()
    ns.RefreshMapButtons()
end

local NO_DESTINATION = "set a destination first: Alt+click the world map"
local NO_PATHWAYS = "This zone has no navigational pathways."

local routeMap              -- the navigation map the route was planned on

-- Starts walking to goal = { c, x, y } on navigation map navMap: to the point nearest you,
-- along links to the point nearest the goal (or to goalId), then straight to the goal. If the
-- goal is closer than any point, straight there. label names the goal in chat.
local function Travel(navMap, goal, label, goalId)
    if InCombatLockdown() then ns.Print("can't start a route in combat") return end
    local _, c, px, py, facing = ns.GetPlayerPose()
    if not (px and facing) then ns.Print("your position isn't available here") return end
    if goal.c ~= c then ns.Print("the " .. label .. " is on another continent") return end

    local previous = ns.Graph.Use(navMap)
    local newTargets, path = {}, {}
    local startId, startDist = ns.Graph.Nearest(c, px, py)
    if startId and (goalId or ns.Distance(px, py, goal.x, goal.y) > startDist) then
        local endId = goalId or ns.Graph.Nearest(c, goal.x, goal.y)
        path = ns.Graph.ShortestPath(startId, endId)
        if path then
            for _, id in ipairs(path) do
                local node = ns.Graph.Get(id)
                tinsert(newTargets, { x = node.x, y = node.y })
            end
        end
    end
    ns.Graph.Use(previous)
    if not path then
        ns.Print("on \"" .. navMap.name .. "\", the point nearest you isn't linked to the point nearest the " .. label)
        return
    end
    if not goalId then tinsert(newTargets, { x = goal.x, y = goal.y }) end

    -- Round each corner with a curve rather than turning sharply at the points.
    tinsert(newTargets, 1, { x = px, y = py })
    local curve, marks = ns.RoundedPath(newTargets, CURVE_PIECES)
    targets = {}
    for i = 2, #curve do tinsert(targets, { x = curve[i].x, y = curve[i].y }) end
    targets[#targets].final = true
    -- Each navigation point (and the goal) with the steering step nearest it, for the world view marker.
    wipe(markers)
    for i = 2, #marks do tinsert(markers, { index = marks[i] - 1, x = newTargets[i].x, y = newTargets[i].y }) end

    local yards, lx, ly = 0, px, py
    for _, t in ipairs(targets) do
        yards = yards + ns.Distance(lx, ly, t.x, t.y)
        lx, ly = t.x, t.y
    end

    routeNodes, routeMap = path, navMap
    active, index = true, 1
    stuckX, stuckCount, jumpUntil, warnedNoPose = nil, 0, 0, false
    ns.CheckAHK()
    ns.Print(format("walking to the %s on %s: %d points, %.0f yards", label, ns.Maps.Label(navMap), #path, yards))
    ns.RedrawMap()
    ns.RefreshMapButtons()
    -- Out of the way, so you can see where you're walking.
    if ns.db.options.closeMap and WorldMapFrame and WorldMapFrame:IsShown() then ToggleWorldMap() end
end

-- The zone you're in.
local function PlayerZone()
    return C_Map.GetBestMapForUnit("player")
end

-- Asks which navigation map to use: the maps installed for your zone, built-in ones first, then
-- yours. Says so if there are none. onPick(map) runs with the choice.
local function PickMap(title, onPick)
    local maps = ns.Maps.ForZone(PlayerZone())
    if #maps == 0 then ns.Print(NO_PATHWAYS) return end
    local rows = {}
    for _, builtinFirst in ipairs({ true, false }) do
        for _, m in ipairs(maps) do
            if (m.builtin and true or false) == builtinFirst then
                tinsert(rows, { text = ns.Maps.Label(m) .. (m.builtin and "  |cff888888built-in|r" or ""),
                    onClick = function() onPick(m) end })
            end
        end
    end
    ns.ShowPicker(title, rows)
end

Navigator.Travel, Navigator.PickMap, Navigator.NO_PATHWAYS = Travel, PickMap, NO_PATHWAYS

function Navigator.RouteMapID() return active and routeMap and routeMap.id or nil end
function Navigator.RouteMap() return active and routeMap or nil end

-- Start travel: pick a navigation map, then walk to the destination on it.
function Navigator.Start()
    if not ns.db.finish then ns.Print(NO_DESTINATION) return end
    PickMap("Travel using which navigation map?", function(m) Travel(m, ns.db.finish, "destination") end)
end

-- Walks to the nearest town (by walking distance along the links) on a map you pick.
local function GoTownOn(navMap)
    local _, c, px, py = ns.GetPlayerPose()
    if not px then ns.Print("your position isn't available here") return end
    local previous = ns.Graph.Use(navMap)
    local startId = ns.Graph.Nearest(c, px, py)
    local dist = startId and ns.Graph.Distances(startId) or {}
    ns.Graph.Use(previous)
    local best, bestDist
    for id, d in pairs(dist) do
        if navMap.nodes[id].town and (not bestDist or d < bestDist) then best, bestDist = id, d end
    end
    if not best then
        ns.Print("no town is linked to the points near you on " .. ns.Maps.Label(navMap)
            .. ". Ctrl+click a point in path drawing mode to make it a town.")
        return
    end
    if active then Navigator.Stop("heading to a town instead") end
    local town = navMap.nodes[best]
    Travel(navMap, { c = town.c, x = town.x, y = town.y }, "town", best)
end

function Navigator.GoTown()
    PickMap("Go to the nearest town using which map?", GoTownOn)
end
-- For the on-screen panel: the map, and yards left along the route.
function Navigator.Status()
    if not active then return nil end
    local _, _, px, py = ns.GetPlayerPose()
    local yards, lx, ly = 0, px, py
    for i = index, #targets do
        if lx then yards = yards + ns.Distance(lx, ly, targets[i].x, targets[i].y) end
        lx, ly = targets[i].x, targets[i].y
    end
    return routeMap, px and yards or nil
end

-- For the world view marker: the next navigation point (or the goal) not yet reached.
function Navigator.NextMarker()
    if not active then return nil end
    for _, m in ipairs(markers) do
        if m.index >= index then return m end
    end
end

-- For the minimap line: the targets left to walk, in order.
function Navigator.Remaining()
    if not active then return nil end
    local left = {}
    for i = index, #targets do tinsert(left, targets[i]) end
    return left
end

---------------------------------------------------------------------------
-- Steering
---------------------------------------------------------------------------

local function Steer(now)
    if UnitIsDeadOrGhost("player") then Navigator.Stop("dead") return "none" end
    if UnitOnTaxi("player") then Navigator.Stop("on a taxi") return "none" end
    if GetCurrentKeyBoardFocus() then return "none" end   -- typing: let go, so nothing types into the box

    local mapID, _, px, py, facing = ns.GetPlayerPose()
    local nx, ny, wx, wy
    if mapID then nx, ny, wx, wy = ns.MapAxes(mapID) end
    if not (px and facing and nx) then
        if not warnedNoPose then ns.Log("position or facing unavailable; paused") warnedNoPose = true end
        return "none"
    end
    warnedNoPose = false

    -- Steer at the first step at least LOOKAHEAD away (or the goal), skipping steps passed or
    -- close by, so the heading changes smoothly instead of with every small step of a curve.
    local target, vx, vy, d
    while true do
        target = targets[index]
        vx, vy = target.x - px, target.y - py
        d = math.sqrt(vx * vx + vy * vy)
        if target.final then
            if d <= END_RADIUS then Navigator.Stop("arrived") return "none" end
            break
        end
        if d > LOOKAHEAD then break end
        index, stuckCount, stuckX = index + 1, 0, nil
    end

    -- Bearing from north, counter-clockwise like GetPlayerFacing; err > 0 means the target is to the left.
    local bearing = math.atan2(vx * wx + vy * wy, vx * nx + vy * ny)
    local err = (bearing - facing + math.pi) % (2 * math.pi) - math.pi
    local absErr = math.abs(err)

    -- How hard to turn: 0 inside the deadband, then 1-3 as the error grows; positive is left.
    local strength = absErr < TURN_DEADBAND and 0 or math.min(3, 1 + math.floor((absErr - TURN_DEADBAND) / TURN_STEP))
    local turnLevel = err > 0 and strength or -strength
    local walk = absErr < (d < NEAR and NEAR_CONE or WALK_CONE)

    if walk then
        if not stuckX then
            stuckX, stuckY, stuckT = px, py, now
        elseif now - stuckT >= STUCK_WINDOW then
            if ns.Distance(px, py, stuckX, stuckY) < STUCK_MOVE then
                stuckCount = stuckCount + 1
                if stuckCount >= STUCK_LIMIT then
                    Navigator.Stop(format("stuck %.0f yards from the next point", d))
                    return "none"
                end
                jumpUntil = now + STUCK_JUMP
            end
            stuckX, stuckY, stuckT = px, py, now
        end
    else
        stuckX = nil
    end

    if now < jumpUntil then return "jump", turnLevel end
    if walk then return "walk", turnLevel end
    return "steer", turnLevel
end

local elapsedSince = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < TICK then return end
    elapsedSince = 0
    local now = GetTime()
    if active then
        local name, level = Steer(now)
        SetCommand(name, level)
    end
end)

---------------------------------------------------------------------------
-- Your own movement ends the route: Escape, or any key bound to moving (forward, back,
-- turning, strafing, jumping, autorun), read from your keybindings. Everything else
-- (spells, other keys, mouse clicks and mouse movement) is fine. Keys AHK presses reach the
-- game like yours, so the one W or Space press this file is waiting for after asking AHK
-- for it (AHK presses each once, not repeatedly) doesn't count. The frame passes every key
-- on to the game; its pass-through is set once, out of combat.
---------------------------------------------------------------------------

local MOVE_ACTIONS = { "MOVEFORWARD", "MOVEBACKWARD", "TURNLEFT", "TURNRIGHT", "STRAFELEFT",
    "STRAFERIGHT", "JUMP", "TOGGLEAUTORUN", "MOVEANDSTEER" }

-- Movement keys from your current bindings (the bare key: Shift+W still counts as W).
local function MovementKeys()
    local keys = { ESCAPE = true }
    for _, action in ipairs(MOVE_ACTIONS) do
        for _, binding in ipairs({ GetBindingKey(action) }) do
            keys[binding:match("([^%-]+)$")] = true
        end
    end
    return keys
end

local keyWatch = CreateFrame("Frame")
keyWatch:EnableKeyboard(true)
keyWatch:SetPropagateKeyboardInput(true)
keyWatch:SetScript("OnKeyDown", function(_, key)
    if not active then return end
    local now = GetTime()
    if key == "W" and now < expectW then expectW = 0 return end
    if key == "SPACE" and now < expectSpace then expectSpace = 0 return end
    if key == "ESCAPE" or (ns.db.options.stopOnMoveKeys and MovementKeys()[key]) then
        Navigator.Stop("you took over (" .. key .. ")")
    end
end)

ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() Navigator.Stop("entered combat") end)
ns.RegisterEvent("PLAYER_LEAVING_WORLD", function() Navigator.Stop("loading screen") end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

ns.RegisterCommand("go", "- walk to the destination (pick a navigation map)", function() Navigator.Start() end)
ns.RegisterCommand("town", "- walk to the nearest town (same as /goto town)", function() Navigator.GoTown() end)

SLASH_PATHFINDERGOTO1 = "/goto"
SlashCmdList.PATHFINDERGOTO = function(msg)
    local what = strtrim(msg or ""):lower()
    if what == "town" then
        Navigator.GoTown()
    elseif what == "destination" or what == "dest" then
        Navigator.Start()
    elseif what == "objective" then
        ns.GoObjective()
    else
        ns.Print("usage: /goto town, /goto destination, /goto objective")
    end
end
ns.RegisterCommand("stop", "- stop walking", function() Navigator.Stop("stopped") end)
