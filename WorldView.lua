local _, ns = ...

---------------------------------------------------------------------------
-- While travelling, marks the next navigation point (then the goal) in the
-- 3D world view. Addons can't draw lines in the world: there's no way to
-- turn a world position into a screen position. The one thing the game
-- draws in the world for an addon is Blizzard's own map pin when it's
-- tracked (the floating marker with a distance), so this moves that pin
-- along the route, one point at a time. Whatever pin you had before comes
-- back when the route ends.
---------------------------------------------------------------------------

local TICK = 0.2

local available = C_Map and C_Map.SetUserWaypoint and C_Map.ClearUserWaypoint and C_Map.GetUserWaypoint
    and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates

local saved                 -- { pin, tracked } from before the route, or false once taken
local current               -- the marker shown now

local function Restore()
    if saved == nil then return end
    if saved.pin then
        C_Map.SetUserWaypoint(saved.pin)
        C_SuperTrack.SetSuperTrackedUserWaypoint(saved.tracked)
    else
        C_Map.ClearUserWaypoint()
    end
    saved, current = nil, nil
end

local function Show(marker)
    -- Your zone's map, or the next map up (the continent) for a point beyond the zone's edge.
    local continentID = select(2, ns.GetPlayerPose())
    local mapID, x, y = C_Map.GetBestMapForUnit("player"), nil, nil
    while mapID and continentID do
        if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) then
            x, y = ns.WorldToMap(continentID, marker.x, marker.y, mapID)
            if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then break end
        end
        x = nil
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID ~= 0 and info.parentMapID or nil
    end
    if not x then return end
    if saved == nil then
        saved = { pin = C_Map.GetUserWaypoint(),
                  tracked = C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint() }
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    current = marker
end

local frame = CreateFrame("Frame")
local since = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    if not available then return end
    since = since + elapsed
    if since < TICK then return end
    since = 0
    local marker = ns.Navigator.NextMarker()
    if marker then
        -- The game may clear the pin itself when you get close; put it back until the route moves on.
        if marker ~= current or not C_Map.GetUserWaypoint() then Show(marker) end
    elseif saved ~= nil then
        Restore()
    end
end)
