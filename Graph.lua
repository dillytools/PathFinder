local _, ns = ...

---------------------------------------------------------------------------
-- Points (nodes) and two-way links of one navigation map (Maps.lua). Every
-- function works on the map chosen with Graph.Use(map): the map being drawn,
-- or the one a route is being planned on. A map's nodes:
--   [id] = { c = continentID, x, y = world position (yards), links = { [id] = true }, town = true? }
-- Links only join points on the same continent. node.town marks a town, for
-- /goto town.
---------------------------------------------------------------------------

local Graph = {}
ns.Graph = Graph

local owner                 -- the map worked on
local nodes = {}            -- owner.nodes

-- Works on map from now on. Returns the map used before, to switch back.
function Graph.Use(map)
    local previous = owner
    if map ~= owner then Graph.ResetUndo() end
    owner, nodes = map, map and map.nodes or {}
    return previous
end

function Graph.Get(id)
    return nodes[id]
end

function Graph.Link(a, b)
    local na, nb = nodes[a], nodes[b]
    if not (na and nb) or a == b or na.c ~= nb.c then return false end
    na.links[b], nb.links[a] = true, true
    return true
end

-- true = now linked, false = now unlinked, nil = can't be linked (another continent).
function Graph.ToggleLink(a, b)
    local na, nb = nodes[a], nodes[b]
    if not (na and nb) then return end
    if na.links[b] then
        na.links[b], nb.links[a] = nil, nil
        return false
    end
    return Graph.Link(a, b) or nil
end

-- New point at a map position, linked to linkTo if given. Returns its id, or nil off any continent.
function Graph.Add(mapID, x, y, linkTo)
    local continentID, wx, wy = ns.MapToWorld(mapID, x, y)
    if not continentID then return nil end
    return Graph.AddWorld(continentID, wx, wy, linkTo)
end

function Graph.AddWorld(continentID, wx, wy, linkTo)
    local id = owner.nextId or 1
    owner.nextId = id + 1
    nodes[id] = { c = continentID, x = wx, y = wy, links = {} }
    if linkTo then Graph.Link(id, linkTo) end
    return id
end

-- Removing a point in the middle of a chain joins its two neighbours, so the chain stays whole.
function Graph.Remove(id)
    local node = nodes[id]
    if not node then return end
    local neighbours = {}
    for other in pairs(node.links) do
        tinsert(neighbours, other)
        if nodes[other] then nodes[other].links[id] = nil end
    end
    nodes[id] = nil
    if #neighbours == 2 then Graph.Link(neighbours[1], neighbours[2]) end
end

-- Deletes several points at once (no chain rejoining between them).
function Graph.RemoveMany(ids)
    for _, id in ipairs(ids) do
        local node = nodes[id]
        if node then
            for other in pairs(node.links) do
                if nodes[other] then nodes[other].links[id] = nil end
            end
            nodes[id] = nil
        end
    end
end

function Graph.ToggleTown(id)
    local node = nodes[id]
    if not node then return end
    node.town = (not node.town) or nil
    return node.town
end

function Graph.Count()
    local n = 0
    for _ in pairs(nodes) do n = n + 1 end
    return n
end

-- Number of a map's points that fall on a uiMap (0-1 on it). Takes any map, not just the one in use.
function Graph.CountOnMap(navMap, mapID)
    local continentID = ns.MapToWorld(mapID, 0.5, 0.5)
    local n = 0
    for _, node in pairs(navMap.nodes) do
        if node.c == continentID then
            local x, y = ns.WorldToMap(node.c, node.x, node.y, mapID)
            if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then n = n + 1 end
        end
    end
    return n
end

-- Closest point on the continent to a world position: id, distance.
function Graph.Nearest(continentID, x, y)
    local best, bestDist
    for id, node in pairs(nodes) do
        if node.c == continentID then
            local d = ns.Distance(x, y, node.x, node.y)
            if not bestDist or d < bestDist then best, bestDist = id, d end
        end
    end
    return best, bestDist
end

-- Dijkstra from one point over the links: distance and previous point for every reachable point.
function Graph.Distances(from)
    local dist, prev, done = { [from] = 0 }, {}, {}
    while true do
        local current, currentDist
        for id, d in pairs(dist) do
            if not done[id] and (not currentDist or d < currentDist) then current, currentDist = id, d end
        end
        if not current then break end
        done[current] = true
        local node = nodes[current]
        for other in pairs(node.links) do
            local n = nodes[other]
            if n and not done[other] then
                local d = currentDist + ns.Distance(node.x, node.y, n.x, n.y)
                if not dist[other] or d < dist[other] then dist[other], prev[other] = d, current end
            end
        end
    end
    return dist, prev
end

-- Chain of point ids from a Distances result, from `from` to `to`, or nil if `to` isn't reachable.
function Graph.PathTo(prev, from, to)
    if to ~= from and not prev[to] then return nil end
    local path, id = {}, to
    while id do
        tinsert(path, 1, id)
        id = prev[id]
    end
    return path
end

function Graph.ShortestPath(from, to)
    local _, prev = Graph.Distances(from)
    return Graph.PathTo(prev, from, to)
end

---------------------------------------------------------------------------
-- Undo: a copy of the map's points is kept before each edit, the last
-- UNDO_LIMIT of them, for this session and this map only.
---------------------------------------------------------------------------

local UNDO_LIMIT = 20
local undo = {}

function ns.DeepCopy(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = type(v) == "table" and ns.DeepCopy(v) or v end
    return copy
end

-- Call before changing points or links.
function Graph.Snapshot()
    tinsert(undo, ns.DeepCopy(nodes))
    if #undo > UNDO_LIMIT then tremove(undo, 1) end
end

function Graph.CanUndo()
    return #undo > 0
end

function Graph.ResetUndo()
    wipe(undo)
end

-- Restores the points as they were before the last edit. nextId isn't rolled back, so ids never repeat.
function Graph.Undo()
    local restored = tremove(undo)
    if not restored then return false end
    owner.nodes, nodes = restored, restored
    return true
end
