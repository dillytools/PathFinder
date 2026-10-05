local _, ns = ...

---------------------------------------------------------------------------
-- Navigation maps: named sets of points and links, each Safe or Dangerous,
-- with the zone it was drawn for. A map:
--   { id, name, kind = "safe" | "fast", zone = uiMapID, zoneName, nodes, nextId, builtin }
-- Two kinds of installed map:
--   yours      drawn in game, saved in PathFinderDB.maps (id "u:<n>")
--   built-in   shipped with the addon in Maps\*.lua files, from the community
--              (id "b:<n>"); editing one saves your own copy
--
-- Maps travel as text (export/import, and the built-in files):
--   PF1~name~kind~zoneID~zoneName~nodes
-- nodes are ";"-separated "id,continent,x,y,town,link:link:...". No "|"
-- anywhere, since the game's text boxes treat it as an escape character.
---------------------------------------------------------------------------

local Maps = {}
ns.Maps = Maps

Maps.KIND_NAMES = { safe = "Safe", fast = "Dangerous" }

local builtin = {}

local function Clean(text)
    return (tostring(text or ""):gsub("[~;,:|]", ""))
end

function Maps.Encode(m)
    local parts = {}
    for id, node in pairs(m.nodes) do
        local links = {}
        for other in pairs(node.links) do tinsert(links, other) end
        sort(links)
        tinsert(parts, format("%d,%d,%.1f,%.1f,%d,%s", id, node.c, node.x, node.y, node.town and 1 or 0,
            table.concat(links, ":")))
    end
    sort(parts, function(a, b) return tonumber(a:match("^%d+")) < tonumber(b:match("^%d+")) end)
    return table.concat({ "PF1", Clean(m.name), m.kind == "fast" and "fast" or "safe", tostring(m.zone or 0),
        Clean(m.zoneName), table.concat(parts, ";") }, "~")
end

-- A map from text, or nil and why not.
function Maps.Decode(text)
    text = strtrim(tostring(text or ""))
    local version, name, kind, zone, zoneName, nodeText = strsplit("~", text)
    if version ~= "PF1" or not nodeText then return nil, "that isn't a PathFinder map" end
    local m = { name = name ~= "" and name or "Unnamed map", kind = kind == "fast" and "fast" or "safe",
        zone = tonumber(zone), zoneName = zoneName, nodes = {}, nextId = 1 }
    for entry in nodeText:gmatch("[^;]+") do
        local id, c, x, y, town, links = strsplit(",", entry)
        id, c, x, y = tonumber(id), tonumber(c), tonumber(x), tonumber(y)
        if not (id and c and x and y) then return nil, "that map's points are damaged" end
        local node = { c = c, x = x, y = y, town = town == "1" or nil, links = {} }
        for other in (links or ""):gmatch("%d+") do node.links[tonumber(other)] = true end
        m.nodes[id] = node
        m.nextId = math.max(m.nextId, id + 1)
    end
    -- Keep only links whose other end exists, both ways.
    for id, node in pairs(m.nodes) do
        for other in pairs(node.links) do
            local n = m.nodes[other]
            if n then n.links[id] = true else node.links[other] = nil end
        end
    end
    return m
end

-- Called from the Maps\*.lua files: ns.AddMapString("PF1~...").
function ns.AddMapString(text)
    local m, err = Maps.Decode(text)
    if not m then
        print("|cff33ff99PathFinder|r: a built-in map couldn't be read: " .. err)
        return
    end
    m.builtin = true
    m.id = "b:" .. (#builtin + 1)
    tinsert(builtin, m)
end

local function Sorted(list)
    sort(list, function(a, b)
        if (a.zoneName or "") ~= (b.zoneName or "") then return (a.zoneName or "") < (b.zoneName or "") end
        if a.kind ~= b.kind then return a.kind == "safe" end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- Every installed map: yours, then built-in, each sorted by zone, Safe first, then name.
function Maps.All()
    local mine, shipped = {}, {}
    for _, m in pairs(ns.db.maps) do tinsert(mine, m) end
    for _, m in ipairs(builtin) do tinsert(shipped, m) end
    Sorted(mine)
    for _, m in ipairs(Sorted(shipped)) do tinsert(mine, m) end
    return mine
end

-- Installed maps with points in a zone (uiMapID), in Maps.All order. Inside a small map (a
-- city or sub-zone) with none, the zone around it counts.
function Maps.ForZone(mapID)
    local list = {}
    for _ = 1, 2 do
        if not mapID then return list end
        for _, m in ipairs(Maps.All()) do
            if ns.Graph.CountOnMap(m, mapID) > 0 then tinsert(list, m) end
        end
        if #list > 0 then return list end
        local info = C_Map.GetMapInfo(mapID)
        local parent = info and info.parentMapID
        local parentInfo = parent and parent ~= 0 and C_Map.GetMapInfo(parent)
        -- Stop at continents: every map on one would count.
        if not parentInfo or (Enum and Enum.UIMapType and parentInfo.mapType <= Enum.UIMapType.Continent) then
            return list
        end
        mapID = parent
    end
    return list
end

-- The first Safe map for the zone, else the first Dangerous one (unused by the commands now: they ask).
function Maps.Default(mapID)
    local list = Maps.ForZone(mapID)
    for _, m in ipairs(list) do
        if m.kind == "safe" then return m end
    end
    return list[1]
end

function Maps.Label(m)
    return format("%s  (%s%s)", m.name or "Unnamed map", Maps.KIND_NAMES[m.kind] or "Safe",
        m.zoneName and m.zoneName ~= "" and (", " .. m.zoneName) or "")
end

function Maps.Find(id)
    if not id then return nil end
    if ns.db.maps[id] then return ns.db.maps[id] end
    for _, m in ipairs(builtin) do
        if m.id == id then return m end
    end
end

function Maps.New()
    return { name = "", kind = "safe", nodes = {}, nextId = 1 }
end

-- Saves a map as one of yours. A built-in map, or one without an id, gets a new id.
function Maps.Save(m)
    if not m.id or m.builtin then
        m.id = "u:" .. ns.db.nextMapId
        ns.db.nextMapId = ns.db.nextMapId + 1
    end
    m.builtin = nil
    ns.db.maps[m.id] = m
    return m
end

function Maps.Delete(m)
    if m and ns.db.maps[m.id] then ns.db.maps[m.id] = nil return true end
    return false
end

-- Points from before there were named maps become your maps, one per old network.
ns.OnInit(function()
    local old = ns.db.nodes
    if type(old) ~= "table" or not next(old) then ns.db.nodes, ns.db.nextId = nil, nil return end
    local byNet = {}
    for id, node in pairs(old) do
        local net = node.net == "fast" and "fast" or "safe"
        byNet[net] = byNet[net] or { name = net == "fast" and "My Fast & Dangerous paths" or "My Safest paths",
            kind = net, nodes = {}, nextId = ns.db.nextId or 1 }
        node.net = nil
        byNet[net].nodes[id] = node
    end
    for _, m in pairs(byNet) do
        local _, first = next(m.nodes)
        if first and C_Map and C_Map.GetMapPosFromWorldPos then
            local zone = C_Map.GetMapPosFromWorldPos(first.c, CreateVector2D(first.x, first.y))
            local info = zone and C_Map.GetMapInfo(zone)
            m.zone, m.zoneName = zone, info and info.name
        end
        Maps.Save(m)
    end
    ns.db.nodes, ns.db.nextId = nil, nil
end)
