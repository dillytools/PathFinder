local _, ns = ...

---------------------------------------------------------------------------
-- While travelling, draws the rest of the route on the minimap: a line from
-- you through each remaining point to the goal, cut off at the minimap's
-- edge. Works with a rotating minimap and a square one (GetMinimapShape).
--
-- The minimap shows a fixed number of yards across per zoom level, smaller
-- indoors; these are the standard figures (as HereBeDragons uses).
---------------------------------------------------------------------------

local MINIMAP_YARDS = {
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
}
local LINE_PX = 2
local COLOR = { 0.2, 1, 0.3, 0.9 }
local TICK = 0.05

local frame = CreateFrame("Frame", nil, Minimap)
frame:SetAllPoints(Minimap)
frame:SetFrameLevel(Minimap:GetFrameLevel() + 5)
local lines = {}

local function HideLines(from)
    for i = from, #lines do lines[i]:Hide() end
end

-- Clips segment a-b (minimap pixels from the centre) to a circle of radius r, or a square of
-- half-size r. Returns the clipped ends, or nil if none of it is inside.
local function Clip(ax, ay, bx, by, r, square)
    local dx, dy = bx - ax, by - ay
    local t0, t1 = 0, 1
    if square then
        -- Liang-Barsky against |x| <= r, |y| <= r.
        for _, pq in ipairs({ { -dx, ax + r }, { dx, r - ax }, { -dy, ay + r }, { dy, r - ay } }) do
            local p, q = pq[1], pq[2]
            if p == 0 then
                if q < 0 then return nil end
            else
                local t = q / p
                if p < 0 then t0 = math.max(t0, t) else t1 = math.min(t1, t) end
            end
        end
    else
        -- Solve |a + t*d| = r for t.
        local A = dx * dx + dy * dy
        local B = 2 * (ax * dx + ay * dy)
        local C = ax * ax + ay * ay - r * r
        if A == 0 then return nil end
        local disc = B * B - 4 * A * C
        if disc < 0 then return nil end
        local s = math.sqrt(disc)
        t0 = math.max(t0, (-B - s) / (2 * A))
        t1 = math.min(t1, (-B + s) / (2 * A))
    end
    if t0 > t1 then return nil end
    return ax + t0 * dx, ay + t0 * dy, ax + t1 * dx, ay + t1 * dy
end

local function Draw()
    local remaining = ns.Navigator.Remaining()
    local mapID, _, px, py, facing = ns.GetPlayerPose()
    local nx, ny, wx, wy
    if mapID then nx, ny, wx, wy = ns.MapAxes(mapID) end
    if not (remaining and px and nx) then HideLines(1) return end

    local zoom = Minimap:GetZoom()
    local yards = MINIMAP_YARDS[IsIndoors() and "indoor" or "outdoor"][zoom] or MINIMAP_YARDS.outdoor[0]
    local size = Minimap:GetWidth()
    local pxPerYard = size / yards
    local r = size / 2 - 2
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local rotate = GetCVar("rotateMinimap") == "1"

    -- Minimap pixels from the centre for a world point: up = north (or your facing when rotating).
    local function ToMinimap(t)
        local vx, vy = t.x - px, t.y - py
        local north, west = vx * nx + vy * ny, vx * wx + vy * wy
        if rotate and facing then
            local cosF, sinF = math.cos(-facing), math.sin(-facing)
            north, west = north * cosF - west * sinF, north * sinF + west * cosF
        end
        return -west * pxPerYard, north * pxPerYard
    end

    local count = 0
    local ax, ay = 0, 0
    for _, t in ipairs(remaining) do
        local bx, by = ToMinimap(t)
        local x1, y1, x2, y2 = Clip(ax, ay, bx, by, r, square)
        if x1 then
            count = count + 1
            local line = lines[count]
            if not line then
                line = frame:CreateLine(nil, "OVERLAY")
                line:SetThickness(LINE_PX)
                line:SetColorTexture(unpack(COLOR))
                lines[count] = line
            end
            line:SetStartPoint("CENTER", Minimap, x1, y1)
            line:SetEndPoint("CENTER", Minimap, x2, y2)
            line:Show()
        end
        ax, ay = bx, by
    end
    HideLines(count + 1)
end

local sinceDraw = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    sinceDraw = sinceDraw + elapsed
    if sinceDraw < TICK then return end
    sinceDraw = 0
    if ns.Navigator.IsActive() and ns.db.options.minimapRoute then Draw() elseif lines[1] and lines[1]:IsShown() then HideLines(1) end
end)
