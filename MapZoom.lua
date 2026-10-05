local _, ns = ...

---------------------------------------------------------------------------
-- Deeper zoom on the world map, for a closer look at navigation points.
-- The map's scroll container builds a list of zoom levels each time a map
-- is shown (CreateZoomLevels); this adds EXTRA_LEVELS more past the last,
-- each ZOOM_STEP times closer. The map art just gets bigger (and softer)
-- past Blizzard's own maximum; points and lines stay sharp. Off with the
-- "Zoom in further on the world map" option, from the next map shown.
---------------------------------------------------------------------------

local EXTRA_LEVELS = 3
local ZOOM_STEP = 1.5

local function AddZoomLevels(container)
    if not (ns.db and ns.db.options.extraZoom) then return end
    local levels = container.zoomLevels
    local last = levels and levels[#levels]
    if not (last and last.scale) then return end
    for i = 1, EXTRA_LEVELS do
        tinsert(levels, { scale = last.scale * ZOOM_STEP ^ i, layerIndex = last.layerIndex })
    end
end

local function Setup()
    local container = WorldMapFrame and (WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer() or WorldMapFrame.ScrollContainer)
    if not (container and container.CreateZoomLevels) then return end
    hooksecurefunc(container, "CreateZoomLevels", AddZoomLevels)
end

ns.RegisterEvent("PLAYER_LOGIN", Setup)
