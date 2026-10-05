local _, ns = ...

---------------------------------------------------------------------------
-- While travelling: a small panel near the top of the screen with the
-- navigation map's name and type, the time left until arrival, and the
-- yards left. Drag it to move it (remembered).
--
-- Time left is yards left along the route divided by your speed: your
-- current speed while moving (GetUnitSpeed), smoothed so it doesn't jump,
-- or your run speed while stopped.
---------------------------------------------------------------------------

local TICK = 0.25
local SMOOTHING = 0.2           -- share of each new speed reading blended in

local hud = CreateFrame("Frame", "PathFinderHUD", UIParent, "BackdropTemplate")
hud:SetSize(260, 44)
hud:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
hud:SetBackdropColor(0, 0, 0, 0.7)
hud:SetMovable(true)
hud:SetClampedToScreen(true)
hud:EnableMouse(true)
hud:RegisterForDrag("LeftButton")
hud:Hide()

local title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -8)
local detail = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
detail:SetPoint("TOP", title, "BOTTOM", 0, -3)

local function Place()
    hud:ClearAllPoints()
    local p = ns.db.hud.point
    if p then
        hud:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        hud:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
end
ns.OnInit(Place)

hud:SetScript("OnDragStart", hud.StartMoving)
hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.hud.point = { point, relPoint, x, y }
end)

local function Clock(seconds)
    seconds = math.floor(seconds + 0.5)
    if seconds >= 3600 then return format("%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60) end
    return format("%d:%02d", seconds / 60, seconds % 60)
end

local speed                 -- smoothed yards per second
local since = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < TICK then return end
    since = 0
    local navMap, yards = ns.Navigator.Status()
    if not navMap then
        hud:Hide()
        speed = nil
        return
    end
    local current, run = GetUnitSpeed("player")
    local reading = (current and current > 0) and current or run or 7
    speed = speed and (speed + (reading - speed) * SMOOTHING) or reading

    title:SetText(format("%s  |cff%s%s|r", navMap.name or "Navigation map",
        navMap.kind == "fast" and "ff7020" or "40c0ff", ns.Maps.KIND_NAMES[navMap.kind] or "Safe"))
    if yards then
        detail:SetText(format("Arriving in %s   %d yd", Clock(yards / math.max(speed, 0.1)), yards))
    else
        detail:SetText("Position unavailable")
    end
    hud:SetWidth(math.max(200, title:GetStringWidth() + 30, detail:GetStringWidth() + 30))
    hud:Show()
end)
