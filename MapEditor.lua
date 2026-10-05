local _, ns = ...

---------------------------------------------------------------------------
-- The world map side of PathFinder: the destination marker, which is always
-- shown, and drawing navigation maps (Maps.lua), whose points only show
-- while drawing.
--
-- On the normal map:
--   alt+click the map        set the destination
--   drag the destination     move it
--   Start travel / Stop      walk the route (Navigator.lua)
--   Clear destination        remove it
-- The last two are buttons at the top of the map, shown with a destination.
--
-- The PathFinder icon (top-right of the map, beside other addons' icons) or
-- /pf draw enters path drawing mode: every other map icon is hidden (except
-- your own arrow) and the map doesn't zoom or pan on clicks (the mouse wheel
-- still zooms):
--   left-click empty map     place a point, linked to the selected one
--   left-click a point       select it (the next point branches from it)
--   drag a point             move it
--   shift+left-click a point link or unlink it with the selected one
--   ctrl+left-click a point  make it a town, or not (for /goto town)
--   right-click a point      delete it (a chain through a point stays joined)
-- The bar: Load map (installed maps by zone, yours first, or a new one),
-- Undo, Clear map, Save map. Drawing works on a copy; Save map shows the
-- name and type (set in the box below the bar) and zone, saves, and keeps
-- drawing on it. Closing the map keeps an unsaved drawing for next time.
-- The bordered box names the map, sets its type, lists the controls, and folds away.
--
-- Drawing uses plain textures on the map canvas, not map pins, and a data
-- provider only for its map-changed and zoom callbacks.
---------------------------------------------------------------------------

local NODE_PX = 9           -- point size on screen
local TOWN_PX = 15
local SELECTED_PX = 13
local DEST_PX = 20          -- destination marker
local LINE_PX = 2
local CURVE_PIECES = 8      -- straight pieces per rounded corner
local PICK_PX = 10          -- click this close to a point to hit it
local DRAG_PX = 4           -- move this far with the button down to start a drag
local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
-- Pins that stay while drawing: your own arrow, and the ones that are part of the map picture itself.
local KEEP_PIN = {
    GroupMembersPinTemplate = true,
    MapExplorationPinTemplate = true,    -- explored-area overlays
    FogOfWarPinTemplate = true,
    MapHighlightPinTemplate = true,      -- zone highlight on hover
}

local COLOR = {
    safe     = { 0.2, 0.8, 1 },          -- points and links of a Safe map
    fast     = { 1, 0.45, 0.1 },         -- of a Dangerous map
    town     = { 1, 0.85, 0.1 },
    selected = { 1, 1, 1 },
    route    = { 0.2, 1, 0.3 },
}

local map, canvas, overlay, destPin
local editing, selected = false, nil
local editMap              -- the working copy being drawn (Maps.New shape), kept between drawing sessions
local editSource            -- the installed map it was copied from, nil for a new one
-- editMap as text when it was loaded or last saved. The drawing has unsaved changes only if it
-- differs now, so clicking around (or undoing back) doesn't count as a change.
local baseline
local function IsDirty()
    return editMap ~= nil and ns.Maps.Encode(editMap) ~= baseline
end
local dotPool, linePool = {}, {}
local drawn = {}            -- point id -> { x, y } map position, for clicks
local mapButton, toolbar, help, countText, undoButton, controls   -- built in CreateButtons
local mapPickButton         -- toolbar: picks another map to draw on
local currentText           -- under the toolbar: which map is being drawn
local infoPanel, clearButton, saveMapButton   -- the bordered instructions box; Clear map; Save map
local nameEdit, kindLabel, statusText   -- in the box: map name field, "Type:", notes
local kindButtons = {}      -- Safe / Dangerous buttons in the box

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- A diamond: a solid square turned 45 degrees, with a black edge. No texture file or mask,
-- so nothing can fail to load and leave the points invisible.
local function NewDot(parent, layer)
    local dot = {}
    for _, part in ipairs({ "ring", "fill" }) do
        local t = (parent or overlay):CreateTexture(nil, layer or "OVERLAY", nil, part == "ring" and 1 or 2)
        if t.SetRotation then t:SetRotation(math.pi / 4) end
        dot[part] = t
    end
    dot.ring:SetColorTexture(0, 0, 0)
    return dot
end

local function PlaceDot(dot, x, y, px, c, scale)
    local w, h = canvas:GetSize()
    dot.fill:SetColorTexture(c[1], c[2], c[3])
    dot.fill:SetSize(px, px)
    dot.ring:SetSize(px + 3 / scale, px + 3 / scale)
    for _, part in ipairs({ "ring", "fill" }) do
        dot[part]:ClearAllPoints()
        dot[part]:SetPoint("CENTER", overlay, "TOPLEFT", x * w, -y * h)
        dot[part]:Show()
    end
end

local function AcquireLine(i)
    local line = linePool[i]
    if not line then
        line = overlay:CreateLine(nil, "ARTWORK")
        linePool[i] = line
    end
    return line
end

local function HideAll()
    for _, dot in ipairs(dotPool) do dot.ring:Hide() dot.fill:Hide() end
    for _, line in ipairs(linePool) do line:Hide() end
    wipe(drawn)
end

local function Inside(p)
    return p[1] >= 0 and p[1] <= 1 and p[2] >= 0 and p[2] <= 1
end

-- Points and links on the active route, from Navigator.lua, when it's on the map being drawn.
local function RouteSets()
    local onRoute, edges = {}, {}
    local route = ns.Navigator and ns.Navigator.RouteNodes()
    if route and editSource and ns.Navigator.RouteMapID() == editSource.id then
        for i, id in ipairs(route) do
            onRoute[id] = true
            if route[i + 1] then
                edges[id .. ":" .. route[i + 1]], edges[route[i + 1] .. ":" .. id] = true, true
            end
        end
    end
    return onRoute, edges
end

function ns.ShownPointCount()
    local count = 0
    for _ in pairs(drawn) do count = count + 1 end
    return count
end

local function RefreshControls()
    if not controls then return end
    local travelling = ns.Navigator.IsActive()
    controls:SetShown(not editing and (ns.db.finish ~= nil or travelling))
    controls.travel:SetText(travelling and "Stop" or "Start travel")
end
ns.RefreshMapButtons = RefreshControls

-- The destination marker: its own small frame, so it takes the mouse for dragging
-- even outside drawing mode, where the overlay doesn't.
local function PlaceDestination(mapID, continentID, scale)
    local m = ns.db.finish
    local x, y
    if m and m.c == continentID then x, y = ns.WorldToMap(m.c, m.x, m.y, mapID) end
    if not (x and Inside({ x, y })) then destPin:Hide() return end
    local w, h = canvas:GetSize()
    local px = DEST_PX / scale
    destPin:SetSize(px, px)
    destPin:ClearAllPoints()
    destPin:SetPoint("CENTER", overlay, "TOPLEFT", x * w, -y * h)
    destPin.dot.fill:SetSize(px, px)
    destPin.dot.ring:SetSize(px + 3 / scale, px + 3 / scale)
    destPin.label:SetTextHeight(11 / scale)   -- the canvas zooms by scaling, so counter it
    destPin:Show()
end

function ns.RedrawMap()
    if not (overlay and map:IsShown()) then return end
    HideAll()
    local mapID = map:GetMapID()
    local continentID = mapID and ns.MapToWorld(mapID, 0.5, 0.5)
    if not continentID then destPin:Hide() return end

    local w, h = canvas:GetSize()
    local scale = (map.GetCanvasScale and map:GetCanvasScale()) or 1
    PlaceDestination(mapID, continentID, scale)
    RefreshControls()

    -- Navigation points belong to drawing mode; the normal map stays clean.
    if not editing then
        if countText then countText:SetText("") end
        return
    end

    local onRoute, edges = RouteSets()
    local pos = {}
    local kindColor = COLOR[editMap.kind] or COLOR.safe
    for id, node in pairs(editMap.nodes) do
        if node.c == continentID then
            local x, y = ns.WorldToMap(node.c, node.x, node.y, mapID)
            if x then pos[id] = { x, y } end
        end
    end

    -- Links as curves: a point with exactly two links gets its corner rounded (a quadratic
    -- Bezier between two cuts, like the walked path); links run straight between the cuts.
    -- Ends and junctions (three or more links) stay sharp.
    local lineCount = 0
    local function Line(a, b, c)
        lineCount = lineCount + 1
        local line = AcquireLine(lineCount)
        line:SetColorTexture(c[1], c[2], c[3], 0.75)
        line:SetThickness(LINE_PX / scale)
        line:SetStartPoint("TOPLEFT", overlay, a.x * w, -a.y * h)
        line:SetEndPoint("TOPLEFT", overlay, b.x * w, -b.y * h)
        line:Show()
    end

    local cuts = {}             -- cuts[id][neighbour] = where the link toward that neighbour starts
    for id, p in pairs(pos) do
        local n1, n2, count = nil, nil, 0
        for n in pairs(editMap.nodes[id].links) do
            count = count + 1
            if count == 1 then n1 = n else n2 = n end
        end
        if count == 2 and pos[n1] and pos[n2] then
            local here = { x = p[1], y = p[2] }
            local a, b = ns.CornerCuts({ x = pos[n1][1], y = pos[n1][2] }, here, { x = pos[n2][1], y = pos[n2][2] })
            cuts[id] = { [n1] = a, [n2] = b }
            if Inside(p) then
                local c = (edges[id .. ":" .. n1] and edges[id .. ":" .. n2]) and COLOR.route or kindColor
                local last = a
                for _, s in ipairs(ns.QuadBezier(a, here, b, CURVE_PIECES)) do
                    Line(last, s, c)
                    last = s
                end
            end
        end
    end

    for id, p in pairs(pos) do
        for other in pairs(editMap.nodes[id].links) do
            local q = pos[other]
            if q and other > id and (Inside(p) or Inside(q)) then
                local c = edges[id .. ":" .. other] and COLOR.route or kindColor
                local a = cuts[id] and cuts[id][other] or { x = p[1], y = p[2] }
                local b = cuts[other] and cuts[other][id] or { x = q[1], y = q[2] }
                Line(a, b, c)
            end
        end
    end

    local dotCount = 0
    for id, p in pairs(pos) do
        if Inside(p) then
            dotCount = dotCount + 1
            drawn[id] = p
            dotPool[dotCount] = dotPool[dotCount] or NewDot()
            local isSelected, isTown = id == selected, editMap.nodes[id].town
            local px = isTown and TOWN_PX or isSelected and SELECTED_PX or NODE_PX
            local c = isSelected and COLOR.selected or isTown and COLOR.town
                or (onRoute[id] and COLOR.route) or kindColor
            PlaceDot(dotPool[dotCount], p[1], p[2], px / scale, c, scale)
        end
    end

    if countText then
        countText:SetFormattedText("Points on this map: %d", dotCount)
        undoButton:SetEnabled(ns.Graph.CanUndo())
        clearButton:SetEnabled(dotCount > 0)
        saveMapButton:SetEnabled(next(editMap.nodes) ~= nil)   -- nothing to save without points
        ns.RefreshMapPickButton()   -- "unsaved changes", which also lays out the box
    end
end

---------------------------------------------------------------------------
-- Hiding every other map icon, from Blizzard or any addon, while drawing.
-- They're canvas children; alpha 0 rather than Hide, because the map
-- re-shows pins whenever it refreshes. Reapplied on a ticker for pins the
-- map adds while drawing.
---------------------------------------------------------------------------

local hiddenPins = {}       -- frame -> alpha before hiding
local pinTicker

local function HidePins()
    local children = { canvas:GetChildren() }
    -- The map's own tile layers are canvas children too; they're recognized by detailTilePool.
    -- If this client names that differently, fall back to hiding only real map pins.
    local layersKnown = false
    for _, child in ipairs(children) do
        if child.detailTilePool then layersKnown = true break end
    end
    for _, child in ipairs(children) do
        local hide = child ~= overlay and not KEEP_PIN[child.pinTemplate or ""]
            and (layersKnown and not child.detailTilePool or child.pinTemplate)
        if hide then
            if hiddenPins[child] == nil then hiddenPins[child] = child:GetAlpha() end
            if child:GetAlpha() > 0 then child:SetAlpha(0) end
        end
    end
end

local function RestorePins()
    for child, alpha in pairs(hiddenPins) do child:SetAlpha(alpha) end
    wipe(hiddenPins)
end

---------------------------------------------------------------------------
-- Editing points
---------------------------------------------------------------------------

local function PointUnderCursor(cx, cy)
    local w, h = canvas:GetSize()
    local scale = (map.GetCanvasScale and map:GetCanvasScale()) or 1
    local best, bestDist
    for id, p in pairs(drawn) do
        local d = ns.Distance(cx * w * scale, cy * h * scale, p[1] * w * scale, p[2] * h * scale)
        if d <= PICK_PX and (not bestDist or d < bestDist) then best, bestDist = id, d end
    end
    return best
end

-- Before every change: an undo step, and the drawing needs saving.
local function BeginEdit()
    ns.Graph.Snapshot()
end

-- Dragging a point moves it: press on a point, move a few pixels, release.
local press                 -- { id, x, y, moved } while the left button is down on a point

local function DragUpdate()
    local cx, cy = map:GetNormalizedCursorPosition()
    if not (press and cx) then return end
    if not press.moved then
        local w, h = canvas:GetSize()
        local scale = (map.GetCanvasScale and map:GetCanvasScale()) or 1
        if ns.Distance(cx * w * scale, cy * h * scale, press.x * w * scale, press.y * h * scale) < DRAG_PX then return end
        press.moved = true
        BeginEdit()
        selected = press.id
    end
    local node = ns.Graph.Get(press.id)
    local c, wx, wy = ns.MapToWorld(map:GetMapID(), cx, cy)
    if node and c == node.c then
        node.x, node.y = wx, wy
        ns.RedrawMap()
    end
end

local function OnMouseDown(_, button)
    if button ~= "LeftButton" or IsShiftKeyDown() then return end
    local cx, cy = map:GetNormalizedCursorPosition()
    local hit = cx and PointUnderCursor(cx, cy)
    if not hit then return end
    press = { id = hit, x = cx, y = cy }
    overlay:SetScript("OnUpdate", DragUpdate)
end

local function OnClick(_, button)
    overlay:SetScript("OnUpdate", nil)
    local dragged = press and press.moved
    press = nil
    if dragged then ns.RedrawMap() return end
    local cx, cy = map:GetNormalizedCursorPosition()
    if not cx then return end
    local hit = PointUnderCursor(cx, cy)
    if button == "LeftButton" then
        if hit and IsControlKeyDown() then
            BeginEdit()
            ns.Print(ns.Graph.ToggleTown(hit) and "point marked as a town" or "point is no longer a town")
        elseif hit and IsShiftKeyDown() and selected and selected ~= hit then
            BeginEdit()
            if ns.Graph.ToggleLink(selected, hit) == nil then ns.Print("those points can't be linked") end
        elseif hit then
            selected = (selected ~= hit) and hit or nil
        else
            if ns.MapToWorld(map:GetMapID(), cx, cy) then BeginEdit() end
            local id = ns.Graph.Add(map:GetMapID(), cx, cy, selected)
            if id then selected = id else ns.Print("can't place points on this map. Open a zone or continent map.") end
        end
    elseif button == "RightButton" then
        if hit then
            BeginEdit()
            ns.Graph.Remove(hit)
            if selected == hit then selected = nil end
        else
            selected = nil
        end
    end
    ns.RedrawMap()
end

---------------------------------------------------------------------------
-- The destination
---------------------------------------------------------------------------

local function SetDestination(cx, cy)
    local c, wx, wy
    if cx then c, wx, wy = ns.MapToWorld(map:GetMapID(), cx, cy) end
    if not c then ns.Print("can't place the destination on this map. Open a zone or continent map.") return false end
    ns.db.finish = { c = c, x = wx, y = wy }
    return true
end

function ns.ClearDestination()
    ns.db.finish = nil
    if ns.Navigator.IsActive() then ns.Navigator.Stop("destination cleared") end
    ns.Print("destination cleared")
    ns.RedrawMap()
end

-- Outside drawing mode: Alt+click the map sets the destination.
local function OnMapClick(_, button)
    if editing or button ~= "LeftButton" or not IsAltKeyDown() then return end
    if SetDestination(map:GetNormalizedCursorPosition()) then
        ns.Print("destination set. Press Start travel.")
        ns.RedrawMap()
    end
end

local function CreateDestination()
    destPin = CreateFrame("Button", nil, overlay)
    destPin:SetFrameLevel(overlay:GetFrameLevel() + 2)
    destPin:EnableMouse(true)
    destPin:RegisterForDrag("LeftButton")
    destPin:Hide()

    destPin.dot = NewDot(destPin, "ARTWORK")
    for _, part in ipairs({ "ring", "fill" }) do
        destPin.dot[part]:ClearAllPoints()
        destPin.dot[part]:SetPoint("CENTER")
    end
    destPin.dot.fill:SetColorTexture(0.85, 0.15, 0.15)
    destPin.label = destPin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    destPin.label:SetPoint("CENTER")
    destPin.label:SetText("D")
    destPin.label:SetTextColor(1, 1, 1)

    destPin:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function()
            local cx, cy = map:GetNormalizedCursorPosition()
            if cx then SetDestination(cx, cy) ns.RedrawMap() end
        end)
    end)
    destPin:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        ns.RedrawMap()
    end)
    destPin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Destination", 1, 1, 1)
        GameTooltip:AddLine("Drag to move it.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    destPin:SetScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- "Clear map": deletes every point shown on the map that's open, after asking.
---------------------------------------------------------------------------

local function ClearShown()
    local ids = {}
    for id in pairs(drawn) do tinsert(ids, id) end
    BeginEdit()
    ns.Graph.ResetUndo()        -- clearing is final (it was confirmed): nothing before it to undo
    ns.Graph.RemoveMany(ids)
    if selected and not ns.Graph.Get(selected) then selected = nil end
    ns.Print(#ids .. " points deleted from this map")
    ns.RedrawMap()
end

StaticPopupDialogs["PATHFINDER_CLEAR_MAP"] = {
    text = "Delete all %d navigation points on this map? This can't be undone.",
    button1 = DELETE,
    button2 = CANCEL,
    OnAccept = ClearShown,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.ClearShownMap()
    local count = ns.ShownPointCount()
    if count == 0 then ns.Print("no points on this map") return end
    StaticPopup_Show("PATHFINDER_CLEAR_MAP", count)
end

function ns.UndoPoint()
    if ns.Graph.Undo() then
        if selected and not ns.Graph.Get(selected) then selected = nil end
        ns.RedrawMap()
    else
        ns.Print("nothing to undo")
    end
end

---------------------------------------------------------------------------
-- Drawing mode
---------------------------------------------------------------------------

-- The box under the bar: the map's name (editable) and Safe/Dangerous buttons, with a note for a
-- built-in map, unsaved changes, or how to start an uncreated map.
local function RefreshMapPickButton()
    if not currentText or not editMap then return end
    if not nameEdit:HasFocus() then nameEdit:SetText(editMap.name or "") end
    for kind, b in pairs(kindButtons) do
        if kind == editMap.kind then b:LockHighlight() else b:UnlockHighlight() end
    end
    local notes = {}
    if not editSource then
        tinsert(notes, "|cffccccccUncreated map: place navigation points on the map, then press Save map.|r")
    elseif editSource.builtin then
        tinsert(notes, "|cff888888Built-in map: saving makes your own copy.|r")
    end
    if IsDirty() then tinsert(notes, "|cffff8020Unsaved changes|r") end
    statusText:SetText(table.concat(notes, "   "))
    if ns.LayoutInfoPanel then ns.LayoutInfoPanel() end
end

ns.RefreshMapPickButton = RefreshMapPickButton

-- Starts drawing on a copy of an installed map, or a new one (source nil).
local function UseMap(source)
    editSource = source
    editMap = source and ns.DeepCopy(source) or ns.Maps.New()
    editMap.builtin = nil
    if not source then editMap.name = "Unnamed Map" end   -- rename it in the box
    baseline, selected = ns.Maps.Encode(editMap), nil
    ns.Graph.Use(editMap)
    RefreshMapPickButton()
    ns.RedrawMap()
end

local function SetEditing(on)
    editing = on and true or false
    if editing and not editMap then UseMap(nil) end
    if editing then ns.Graph.Use(editMap) end
    if overlay then overlay:EnableMouse(editing) end
    if pinTicker then pinTicker:Cancel() pinTicker = nil end
    if editing then
        HidePins()
        pinTicker = C_Timer.NewTicker(0.1, HidePins)
    else
        RestorePins()
    end
    if toolbar then
        toolbar:SetShown(editing)
        mapButton.active:SetShown(editing)
    end
    RefreshMapPickButton()
    ns.RedrawMap()
end
ns.SetEditing = SetEditing

-- If the drawing has unsaved changes (or always, with ask, when it has points), shows the save
-- dialog first: name (the zone's name for a new map) and Safe/Dangerous, prefilled for a saved
-- map so it can be renamed or retyped. Then runs andThen after Save or Delete map; Cancel goes
-- back to drawing.
-- The zone a map is for: the zone (not continent) most of its points fall in, found from the
-- map shown; the map shown itself if that's already a zone or it can't tell.
local function MapZone(navMap)
    local shown = map:GetMapID()
    local info = shown and C_Map.GetMapInfo(shown)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    if not (info and zoneType and info.mapType < zoneType and C_Map.GetMapInfoAtPosition) then return shown end
    local votes, best = {}, nil
    for _, node in pairs(navMap.nodes) do
        local x, y = ns.WorldToMap(node.c, node.x, node.y, shown)
        local child = x and C_Map.GetMapInfoAtPosition(shown, x, y)
        if child and child.mapID ~= shown then
            votes[child.mapID] = (votes[child.mapID] or 0) + 1
            if not best or votes[child.mapID] > votes[best] then best = child.mapID end
        end
    end
    return best or shown
end

local function SaveOrDiscard(andThen, ask)
    if not (editMap and next(editMap.nodes) and (ask or IsDirty())) then andThen() return end
    local zone = MapZone(editMap)
    local info = zone and C_Map.GetMapInfo(zone)
    local zoneName = info and info.name or editSource and editSource.zoneName
    ns.ShowSaveDialog(editMap, zoneName, function(name, kind)
        editMap.name, editMap.kind, editMap.zone, editMap.zoneName = name, kind, zone, zoneName
        if editSource and not editSource.builtin then editMap.id = editSource.id else editMap.id = nil end
        local saved = ns.Maps.Save(editMap)
        ns.Print(format("saved \"%s\" (%s, %s)", saved.name, ns.Maps.KIND_NAMES[saved.kind], zoneName or "unknown zone"))
        editSource, editMap = saved, ns.DeepCopy(saved)
        baseline = ns.Maps.Encode(editMap)
        ns.Graph.Use(editMap)
        andThen()
    end, function()
        -- Delete map: your saved map is removed; a new drawing or a built-in map's copy is just dropped.
        if editSource and not editSource.builtin then
            ns.Maps.Delete(editSource)
            ns.Print("deleted " .. ns.Maps.Label(editSource))
        elseif editSource then
            ns.Print("built-in maps can't be deleted; your changes were dropped")
        else
            ns.Print("drawing deleted")
        end
        editMap, editSource, baseline = nil, nil, nil
        ns.Graph.Use(nil)
        andThen()
    end)
end

-- Save map: the save dialog (even with no changes), and drawing carries on.
local function Done()
    SaveOrDiscard(function()
        -- Stay in drawing mode on the saved map; after Delete map, on a new one.
        if not editMap then UseMap(nil) end
        RefreshMapPickButton()
        ns.RedrawMap()
    end, true)
end

-- "Load map": the installed maps grouped by zone, your zone first, under a New map row.
local function LoadMap()
    local rows = { { text = "|cff33ff99New map|r", onClick = function() SaveOrDiscard(function() UseMap(nil) end) end } }
    local function Add(m)
        tinsert(rows, { text = format("%s  (%s)%s", m.name, ns.Maps.KIND_NAMES[m.kind] or "Safe",
            m.builtin and "  |cff888888built-in|r" or ""),
            onClick = function() SaveOrDiscard(function() UseMap(m) end) end })
    end
    local here, shown = ns.Maps.ForZone(C_Map.GetBestMapForUnit("player")), {}
    if #here > 0 then
        local info = C_Map.GetMapInfo(C_Map.GetBestMapForUnit("player"))
        tinsert(rows, { header = true, text = (info and info.name or "Your zone") .. "  |cffccccccyou are here|r" })
        for _, m in ipairs(here) do Add(m) shown[m] = true end
    end
    local zone
    for _, m in ipairs(ns.Maps.All()) do        -- sorted by zone name
        if not shown[m] then
            local name = m.zoneName and m.zoneName ~= "" and m.zoneName or "Unknown zone"
            if name ~= zone then
                zone = name
                tinsert(rows, { header = true, text = name })
            end
            Add(m)
        end
    end
    ns.ShowPicker("Load which navigation map?", rows, toolbar)
end

---------------------------------------------------------------------------
-- Map icon, built and placed the way Questie does its own (Questie uses the
-- Krowi_WorldMapButtons library): a 32 px minimap-style round button,
-- parented to the map at HIGH strata, anchored TOPRIGHT of the canvas
-- container at (-4, -2), one 32 px step further left for each Krowi button
-- already in that row (Questie's, and any other addon using the library).
-- On Forever, Blizzard's own map pin sits on the left side, not in this row.
---------------------------------------------------------------------------

local ICON_X, ICON_Y, ICON_STEP = 4, -2, 32   -- Krowi_WorldMapButtons defaults

-- Shown buttons in Krowi_WorldMapButtons' row, read-only (it's another addon's library, if loaded).
local function KrowiButtonCount()
    local lib = LibStub and LibStub("Krowi_WorldMapButtons-1.4", true)
    local count = 0
    for _, button in ipairs(lib and lib.Buttons or {}) do
        if button ~= mapButton and button:IsShown() then count = count + 1 end
    end
    return count
end

local function PlaceMapButton()
    local container = map.GetCanvasContainer and map:GetCanvasContainer() or map.ScrollContainer or map
    mapButton:ClearAllPoints()
    mapButton:SetPoint("TOPRIGHT", container, "TOPRIGHT", -(ICON_X + ICON_STEP * KrowiButtonCount()), ICON_Y)
end

local function CreateMapButton(level)
    local b = CreateFrame("Button", "PathFinderMapButton", map)
    b:SetSize(32, 32)
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel(level)
    b:RegisterForClicks("LeftButtonUp")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(25, 25)
    bg:SetPoint("TOPLEFT", 2, -4)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 6, -6)
    local mask = b:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    local border = b:CreateTexture(nil, "OVERLAY", nil, 1)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    b.active = b:CreateTexture(nil, "OVERLAY", nil, 2)   -- lit while drawing
    b.active:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Toggle")
    b.active:SetBlendMode("ADD")
    b.active:SetAllPoints()
    b.active:Hide()
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b:SetScript("OnClick", function()
        SetEditing(not editing)
        GameTooltip_Hide()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("PathFinder", 1, 1, 1)
        GameTooltip:AddLine(editing and "Click to leave path drawing mode. Ctrl+click a point to make it a town."
            or "Click for path drawing mode. Alt+click the map to set a destination.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

---------------------------------------------------------------------------
-- Bars at the top of the map: travel controls normally, drawing tools while
-- drawing.
---------------------------------------------------------------------------

local function NewBar(level, width)
    local container = map.ScrollContainer or map
    local bar = CreateFrame("Frame", nil, map)
    bar:SetSize(width, 22)
    bar:SetPoint("TOP", container, "TOP", 0, -6)
    bar:SetFrameLevel(level)
    bar:EnableMouse(true)          -- clicks between its buttons don't reach the map
    bar:Hide()
    return bar
end

local function NewBarButton(bar, text, width, previous)
    local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    if previous then b:SetPoint("LEFT", previous, "RIGHT", 2, 0) else b:SetPoint("LEFT") end
    return b
end

local function CreateControls(level)
    controls = NewBar(level, 100 + 120 + 2)
    controls.travel = NewBarButton(controls, "Start travel", 100)
    controls.travel:SetScript("OnClick", function()
        if ns.Navigator.IsActive() then ns.Navigator.Stop("stopped") else ns.Navigator.Start() end
    end)
    controls.clear = NewBarButton(controls, "Clear destination", 120, controls.travel)
    controls.clear:SetScript("OnClick", ns.ClearDestination)
end

-- The box under the drawing bar: the map's name and type, the controls and the point count, with
-- a border. Its "-" button folds it down to the name and type rows (remembered).
local function LayoutInfoPanel()
    local collapsed = ns.db.helpCollapsed
    help:SetShown(not collapsed)
    countText:SetShown(not collapsed)
    infoPanel.toggle:SetText(collapsed and "+" or "-")
    local hasStatus = statusText:GetText() and statusText:GetText() ~= ""
    statusText:SetShown(hasStatus)
    local width = math.max(currentText:GetStringWidth() + 8 + nameEdit:GetWidth(), statusText:GetStringWidth())
    local top = 84 + (hasStatus and statusText:GetStringHeight() + 8 or 0)   -- below the name, type and note rows
    local height = top
    help:ClearAllPoints()
    help:SetPoint("TOP", infoPanel, "TOP", 0, -top)
    if not collapsed then
        width = math.max(width, help:GetStringWidth(), countText:GetStringWidth())
        height = height + help:GetStringHeight() + countText:GetStringHeight() + 26
    end
    infoPanel:SetWidth(width + 60)
    infoPanel:SetHeight(height)
end
ns.LayoutInfoPanel = LayoutInfoPanel

-- Renaming and retyping happen right here; Save map stores them.
local function CreateMapFields()
    currentText = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    currentText:SetText("Current navigation map:")
    nameEdit = CreateFrame("EditBox", nil, infoPanel, "InputBoxTemplate")
    nameEdit:SetSize(220, 22)
    nameEdit:SetAutoFocus(false)
    nameEdit:SetMaxLetters(40)
    nameEdit:SetFontObject("GameFontHighlightLarge")
    -- Centre the label and box together.
    currentText:SetPoint("TOPLEFT", infoPanel, "TOP", -(currentText:GetStringWidth() + 8 + 220) / 2, -14)
    nameEdit:SetPoint("LEFT", currentText, "RIGHT", 12, 0)
    nameEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and editMap then
            editMap.name = strtrim(self:GetText() or "")
            RefreshMapPickButton()
        end
    end)
    nameEdit:SetScript("OnEnterPressed", nameEdit.ClearFocus)
    nameEdit:SetScript("OnEscapePressed", function(self)
        self:SetText(editMap and editMap.name or "")
        self:ClearFocus()
    end)

    kindLabel = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kindLabel:SetText("Type:")
    kindLabel:SetPoint("TOPLEFT", currentText, "BOTTOMLEFT", 0, -14)
    local previous = kindLabel
    for _, kind in ipairs({ "safe", "fast" }) do
        local b = CreateFrame("Button", nil, infoPanel, "UIPanelButtonTemplate")
        b:SetSize(100, 22)
        b:SetText(ns.Maps.KIND_NAMES[kind])
        b:SetPoint("LEFT", previous, "RIGHT", previous == kindLabel and 12 or 4, 0)
        b:SetScript("OnClick", function()
            if not editMap then return end
            editMap.kind = kind
            ns.RedrawMap()             -- the points take the type's color
        end)
        kindButtons[kind] = b
        previous = b
    end

    statusText = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("TOP", infoPanel, "TOP", 0, -78)
end

local function CreateToolbar(level)
    toolbar = NewBar(level, 100 + 64 + 84 + 100 + 18)
    mapPickButton = NewBarButton(toolbar, "Load map", 100)
    mapPickButton:SetScript("OnClick", LoadMap)
    undoButton = NewBarButton(toolbar, "Undo", 64, mapPickButton)
    undoButton:SetPoint("LEFT", mapPickButton, "RIGHT", 12, 0)
    undoButton:SetScript("OnClick", ns.UndoPoint)
    clearButton = NewBarButton(toolbar, "Clear map", 84, undoButton)
    clearButton:SetScript("OnClick", function() ns.ClearShownMap() end)
    saveMapButton = NewBarButton(toolbar, "Save map", 100, clearButton)
    saveMapButton:SetPoint("LEFT", clearButton, "RIGHT", 12, 0)
    saveMapButton:SetScript("OnClick", Done)

    infoPanel = CreateFrame("Frame", nil, toolbar, "BackdropTemplate")
    infoPanel:SetPoint("TOP", toolbar, "BOTTOM", 0, -6)
    infoPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    infoPanel:SetBackdropColor(0, 0, 0, 0.8)
    infoPanel:EnableMouse(true)    -- clicks on the box don't place points behind it
    infoPanel:SetBackdropBorderColor(1, 0.82, 0)

    CreateMapFields()

    help = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    help:SetSpacing(4)
    help:SetText("|cffffd100Left-click|r the map: place a point     |cffffd100Right-click|r a point: remove it     |cffffd100Drag|r a point: move it\n"
        .. "|cffffd100Click|r a point, then |cffffd100Shift+click|r another: connect them     |cffffd100Ctrl+click|r a point: make it a town     |cffffd100Ctrl+Z|r: undo")

    countText = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countText:SetPoint("TOP", help, "BOTTOM", 0, -8)

    infoPanel.toggle = CreateFrame("Button", nil, infoPanel, "UIPanelButtonTemplate")
    infoPanel.toggle:SetSize(22, 20)
    infoPanel.toggle:SetPoint("TOPRIGHT", -6, -6)
    infoPanel.toggle:SetScript("OnClick", function()
        ns.db.helpCollapsed = not ns.db.helpCollapsed or nil
        LayoutInfoPanel()
    end)
    infoPanel.toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.db.helpCollapsed and "Show the instructions" or "Hide the instructions")
        GameTooltip:Show()
    end)
    infoPanel.toggle:SetScript("OnLeave", GameTooltip_Hide)

    -- Ctrl+Z undoes while drawing (the bar only gets keys while it's shown). Every
    -- other key passes on to the game; the pass-through can't change in combat.
    toolbar:EnableKeyboard(true)
    toolbar:SetScript("OnKeyDown", function(self, key)
        local undo = key == "Z" and IsControlKeyDown()
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(not undo) end
        if undo then ns.UndoPoint() end
    end)
end

local function CreateButtons()
    local level = overlay:GetFrameLevel() + 10
    mapButton = CreateMapButton(level)
    CreateControls(level)
    CreateToolbar(level)
    PlaceMapButton()
    -- Other addons add their icons late, and Krowi re-lays its row on map change; follow both.
    map:HookScript("OnShow", function() C_Timer.After(0, PlaceMapButton) end)
    hooksecurefunc(map, "OnMapChanged", PlaceMapButton)
    SetEditing(false)
end

local function Setup()
    if overlay or not WorldMapFrame then return end
    map = WorldMapFrame
    canvas = map:GetCanvas()

    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    -- Above every map pin and addon layer (Leatrix Maps, Questie...), so points show and drawing clicks land here.
    overlay:SetFrameLevel(math.min(canvas:GetFrameLevel() + 2000, 9000))
    overlay:EnableMouse(false)
    overlay:SetScript("OnMouseDown", OnMouseDown)
    overlay:SetScript("OnMouseUp", OnClick)
    CreateDestination()
    if map.ScrollContainer then map.ScrollContainer:HookScript("OnMouseUp", OnMapClick) end

    if MapCanvasDataProviderMixin and map.AddDataProvider then
        local provider = CreateFromMixins(MapCanvasDataProviderMixin)
        function provider:RefreshAllData() ns.RedrawMap() end
        function provider:OnMapChanged() ns.RedrawMap() end
        function provider:OnCanvasScaleChanged() ns.RedrawMap() end
        function provider:OnCanvasSizeChanged() ns.RedrawMap() end
        function provider:RemoveAllData() HideAll() end
        map:AddDataProvider(provider)
    else
        hooksecurefunc(map, "OnMapChanged", ns.RedrawMap)
        map:HookScript("OnShow", ns.RedrawMap)
    end
    map:HookScript("OnHide", function() if editing then SetEditing(false) end end)

    CreateButtons()
end

ns.RegisterEvent("PLAYER_LOGIN", Setup)
ns.RegisterEvent("ADDON_LOADED", function(name)
    if name == "Blizzard_WorldMap" and ns.db then Setup() end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

ns.RegisterCommand("draw", "- open the world map in path drawing mode", function()
    if not overlay then ns.Print("the world map isn't available") return end
    if not map:IsShown() then ToggleWorldMap() end
    SetEditing(true)
end)

ns.RegisterCommand("here", "[dest] - add a point where you stand to the map being drawn (linked to the selected point), or put the destination there", function(arg)
    local _, continentID, wx, wy = ns.GetPlayerPose()
    if not wx then ns.Print("your position isn't available here") return end
    if arg == "dest" then
        ns.db.finish = { c = continentID, x = wx, y = wy }
        ns.Print("destination placed")
    else
        if not editMap then ns.Print("open path drawing mode first (/pf draw)") return end
        ns.Graph.Use(editMap)
        BeginEdit()
        selected = ns.Graph.AddWorld(continentID, wx, wy, selected)
        RefreshMapPickButton()
        ns.Print("point added")
    end
    ns.RedrawMap()
end)
