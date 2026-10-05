local addonName, ns = ...

-- Defaults merged into SavedVariables on load, so new keys appear for existing users.
local DEFAULTS = {
    maps = {},      -- your navigation maps by id (Maps.lua)
    nextMapId = 1,
    hud = {},       -- point = where the on-screen travel panel was dragged (HUD.lua)
    -- finish = { c, x, y }: the destination marker; routes always start where you stand
}

local PREFIX = "|cff33ff99" .. addonName .. "|r: "

function ns.Print(...)
    print(PREFIX .. strjoin(" ", tostringall(...)))
end

-- Debug output: chat, in grey.
function ns.Log(...)
    print(PREFIX .. "|cff999999" .. strjoin(" ", tostringall(...)) .. "|r")
end

local function MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = type(target[key]) == "table" and target[key] or {}
            MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

---------------------------------------------------------------------------
-- Positions. Points are stored in world coordinates (yards, per continent)
-- so one network can span zones and show on the continent map too.
-- Directions are worked out from each map's own axes, so nothing depends on
-- which world axis points north.
---------------------------------------------------------------------------

-- nil for secret values (restricted areas or combat on this client).
local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

function ns.MapToWorld(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and mapID) then return nil end
    local continentID, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not (continentID and world) then return nil end
    local wx, wy = world:GetXY()
    return continentID, wx, wy
end

-- Map position (0-1, may fall outside for points off this map) or nil.
function ns.WorldToMap(continentID, wx, wy, mapID)
    if not (C_Map and C_Map.GetMapPosFromWorldPos) then return nil end
    local _, pos = C_Map.GetMapPosFromWorldPos(continentID, CreateVector2D(wx, wy), mapID)
    if pos then return pos:GetXY() end
end

-- World-space unit vectors pointing north and west on a map, cached per map.
local axes = {}
function ns.MapAxes(mapID)
    if axes[mapID] then return unpack(axes[mapID]) end
    local c0, x0, y0 = ns.MapToWorld(mapID, 0, 0)
    local _, xe, ye = ns.MapToWorld(mapID, 1, 0)   -- map +x = east
    local _, xs, ys = ns.MapToWorld(mapID, 0, 1)   -- map +y = south
    if not (c0 and xe and xs) then return nil end
    local ex, ey, sx, sy = xe - x0, ye - y0, xs - x0, ys - y0
    local el, sl = math.sqrt(ex * ex + ey * ey), math.sqrt(sx * sx + sy * sy)
    if el == 0 or sl == 0 then return nil end
    axes[mapID] = { -sx / sl, -sy / sl, -ex / el, -ey / el }   -- north = -south, west = -east
    return unpack(axes[mapID])
end

-- mapID, continentID, world x, world y, facing (radians, 0 = north, counter-clockwise).
-- Anything after mapID can be nil: some instances have no map, and position is hidden in restricted areas.
function ns.GetPlayerPose()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    local facing = GetPlayerFacing and Plain(GetPlayerFacing())
    if not pos then return mapID, nil, nil, nil, facing end
    local x, y = pos:GetXY()
    x, y = Plain(x), Plain(y)
    if not (x and y) then return mapID, nil, nil, nil, facing end
    local continentID, wx, wy = ns.MapToWorld(mapID, x, y)
    return mapID, continentID, wx, wy, facing
end

function ns.Distance(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- Curves. Each corner of a path is rounded with a quadratic Bezier curve: the path runs
-- straight along each segment, and near a point it leaves the line at a cut, bends toward
-- the point (the curve's control point) and joins the next segment at a matching cut. The
-- curve doesn't touch the point itself, it shortcuts the corner. Points are { x, y } tables
-- in any units.

local CORNER = 0.45             -- each cut sits this fraction of the shorter neighbouring segment from the point

-- n points along the quadratic Bezier from a to b with control point c (a left out, b included).
function ns.QuadBezier(a, c, b, n)
    local out = {}
    for i = 1, n do
        local t = i / n
        local u = 1 - t
        out[i] = { x = u * u * a.x + 2 * u * t * c.x + t * t * b.x,
                   y = u * u * a.y + 2 * u * t * c.y + t * t * b.y }
    end
    return out
end

-- The two cuts where the rounded corner at p leaves the line from prev and joins the line to next.
function ns.CornerCuts(prev, p, next)
    local d1 = ns.Distance(p.x, p.y, prev.x, prev.y)
    local d2 = ns.Distance(p.x, p.y, next.x, next.y)
    local cut = CORNER * math.min(d1, d2)
    if d1 == 0 or d2 == 0 then return p, p end
    return { x = p.x + (prev.x - p.x) * cut / d1, y = p.y + (prev.y - p.y) * cut / d1 },
           { x = p.x + (next.x - p.x) * cut / d2, y = p.y + (next.y - p.y) * cut / d2 }
end

-- A whole path through points with every inner corner rounded into `pieces` short steps.
-- Straight stretches stay single steps. Also returns marks: marks[i] is the index in the
-- result closest to points[i] (the middle of its curve).
function ns.RoundedPath(points, pieces)
    local out, marks = { points[1] }, { 1 }
    for i = 2, #points - 1 do
        local a, b = ns.CornerCuts(points[i - 1], points[i], points[i + 1])
        tinsert(out, a)
        for k, s in ipairs(ns.QuadBezier(a, points[i], b, pieces)) do
            tinsert(out, s)
            if k == math.ceil(pieces / 2) then marks[i] = #out end
        end
    end
    if #points > 1 then
        tinsert(out, points[#points])
        marks[#points] = #out
    end
    return out, marks
end

---------------------------------------------------------------------------
-- Events: one frame, table dispatch, several listeners per event.
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local listeners = {}
local initCallbacks = {}

function ns.RegisterEvent(event, fn)
    if not listeners[event] then
        listeners[event] = {}
        frame:RegisterEvent(event)
    end
    tinsert(listeners[event], fn)
end

function ns.OnInit(fn)
    if ns.db then fn() else tinsert(initCallbacks, fn) end
end

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(listeners[event]) do fn(...) end
end)

ns.RegisterEvent("ADDON_LOADED", function(loadedName)
    if loadedName ~= addonName or ns.db then return end
    PathFinderDB = PathFinderDB or {}
    MergeDefaults(PathFinderDB, DEFAULTS)
    ns.db = PathFinderDB
    ns.db.start = nil   -- the old Start marker, no longer used
    for _, fn in ipairs(initCallbacks) do fn() end
    wipe(initCallbacks)
end)

---------------------------------------------------------------------------
-- Slash commands: other files add theirs with ns.RegisterCommand.
---------------------------------------------------------------------------

local commands, commandOrder = {}, {}

function ns.RegisterCommand(name, usage, fn)
    commands[name] = { usage = usage, fn = fn }
    tinsert(commandOrder, name)
end

ns.RegisterCommand("pos", "- show your map, world position and facing", function()
    local mapID, continentID, wx, wy, facing = ns.GetPlayerPose()
    if not wx then
        ns.Log("position unavailable here (map " .. tostring(mapID) .. ")")
    else
        ns.Log(format("map %d  continent %d  world %.1f, %.1f  facing %s", mapID, continentID, wx, wy,
            facing and format("%.0f deg", math.deg(facing)) or "?"))
    end
end)

SLASH_PATHFINDER1 = "/pathfinder"
SLASH_PATHFINDER2 = "/pf"
SlashCmdList.PATHFINDER = function(msg)
    local name, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    local command = commands[name:lower()]
    if command then
        command.fn(arg)
        return
    end
    ns.Print("commands:")
    for _, key in ipairs(commandOrder) do
        print("  /pf " .. key .. " " .. commands[key].usage)
    end
end
