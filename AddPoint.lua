local _, ns = ...

---------------------------------------------------------------------------
-- Adding navigation points from the game world: walk to a spot, press the
-- "Add navigation point here" key (Key Bindings > AddOns > PathFinder) or
-- /pf addpoint, pick which of your maps it goes on, and the point is added
-- where you stand and saved.
--
-- The game's ping system would be the natural way to mark a spot ahead of
-- you, but it doesn't tell addons where a ping lands (only that one appeared
-- and where it sits on screen), so the point goes where you are instead.
--
-- A built-in map gets your own copy the first time (it's used from then on);
-- points added this way chain: each links to the one added before it on the
-- same map this session; the first links to the map's nearest point. If the
-- map is open in drawing mode, the point is added there (save as usual).
---------------------------------------------------------------------------

BINDING_HEADER_PATHFINDER = "PathFinder"
BINDING_NAME_PATHFINDER_ADDPOINT = "Add navigation point here"

local lastPoint = {}        -- map id -> id of the point last added to it this way
local lastMapId             -- the map picked last time, listed first

local function AddTo(m, c, wx, wy)
    -- Drawing mode has its own working copy of the map; add there so the drawing stays in step.
    if ns.AddPointToDrawing and ns.AddPointToDrawing(m, c, wx, wy) then
        lastMapId = m.id
        return
    end
    -- A built-in map can't change; its points go into your own copy of it (made the first time).
    if m.builtin then
        local copy
        for _, mine in pairs(ns.db.maps) do
            if mine.copyOf == m.id then copy = mine break end
        end
        if not copy then
            copy = ns.DeepCopy(m)
            copy.copyOf = m.id
            ns.Maps.Save(copy)
            ns.Print(format("made your own copy of the built-in map \"%s\"", m.name))
        end
        m = copy
    end
    -- Straight into the saved map (not through Graph, so a drawing's undo history isn't touched).
    local linkTo = lastPoint[m.id] and m.nodes[lastPoint[m.id]] and m.nodes[lastPoint[m.id]].c == c and lastPoint[m.id]
    if not linkTo then
        local best
        for id, node in pairs(m.nodes) do
            local d = node.c == c and ns.Distance(wx, wy, node.x, node.y)
            if d and (not best or d < best) then linkTo, best = id, d end
        end
    end
    local id = m.nextId or 1
    m.nextId = id + 1
    m.nodes[id] = { c = c, x = wx, y = wy, links = {} }
    if linkTo then m.nodes[id].links[linkTo], m.nodes[linkTo].links[id] = true, true end
    lastPoint[m.id], lastMapId = id, m.id
    ns.Print(format("point added to \"%s\" (%s)", m.name, ns.Maps.KIND_NAMES[m.kind] or "Safe"))
end

function ns.AddPointHere()
    local _, c, wx, wy = ns.GetPlayerPose()
    if not wx then ns.Print("your position isn't available here") return end

    local rows, listed = {}, {}
    local function Row(m)
        if listed[m] then return end
        listed[m] = true
        tinsert(rows, { text = format("%s  (%s)%s", m.name, ns.Maps.KIND_NAMES[m.kind] or "Safe",
            m.builtin and "  |cff888888built-in: adds to your copy|r" or ""),
            onClick = function() AddTo(m, c, wx, wy) end })
    end
    local last = ns.Maps.Find(lastMapId)
    if last then Row(last) end
    for _, m in ipairs(ns.Maps.ForZone(C_Map.GetBestMapForUnit("player"))) do Row(m) end
    for _, m in ipairs(ns.Maps.All()) do Row(m) end
    tinsert(rows, { text = "|cff33ff99New map|r", onClick = function()
        local m = ns.Maps.New()
        m.name = "Unnamed Map"
        local zone = C_Map.GetBestMapForUnit("player")
        local info = zone and C_Map.GetMapInfo(zone)
        m.zone, m.zoneName = zone, info and info.name
        ns.Maps.Save(m)
        AddTo(m, c, wx, wy)
    end })
    ns.ShowPicker("Add this spot to which navigation map?", rows)
end

ns.RegisterCommand("addpoint", "- add a navigation point where you stand (pick the map)", function() ns.AddPointHere() end)
