local _, ns = ...

---------------------------------------------------------------------------
-- /goto objective: walks toward the objective of the quest you have
-- selected (Blizzard's tracked quest: click it in the quest tracker or log).
--
-- The objective's area comes from Questie, when it's loaded: the spawn
-- points of the quest's unfinished objectives on your continent. Their
-- centre and furthest spread make a circle, and the route goes to the
-- navigation point nearest that circle's edge (one you can reach). With no
-- area (a single spot, or no Questie data) it goes to the objective's
-- coordinates: the Questie spawn, or Blizzard's quest waypoint (which is
-- also where an all-done quest is handed in).
--
-- Questie has no public API for this; its spawn data is read defensively and
-- anything unexpected just means "no area".
---------------------------------------------------------------------------

local MIN_AREA_RADIUS = 10      -- yards: spawns closer together than this count as one spot

local function SelectedQuest()
    local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    if questID and questID ~= 0 then return questID end
end

-- World positions of the quest's unfinished objective spawns on continent c, from Questie.
local function QuestieSpawns(questID, c)
    local points = {}
    if not (QuestieLoader and QuestieLoader.ImportModule) then return points end
    pcall(function()
        local player = QuestieLoader:ImportModule("QuestiePlayer")
        local zoneDB = QuestieLoader:ImportModule("ZoneDB")
        local quest = player.currentQuestlog[questID]
        if type(quest) ~= "table" then return end
        for _, objective in pairs(quest.Objectives or {}) do
            if not objective.Completed then
                for _, spawnData in pairs(objective.spawnList or {}) do
                    for zone, spawns in pairs(spawnData.Spawns or {}) do
                        local uiMapID = zoneDB:GetUiMapIdByAreaId(zone)
                        for _, spawn in pairs(spawns) do
                            if uiMapID and spawn[1] and spawn[2] then
                                local sc, wx, wy = ns.MapToWorld(uiMapID, spawn[1] / 100, spawn[2] / 100)
                                if sc == c then tinsert(points, { x = wx, y = wy }) end
                            end
                        end
                    end
                end
            end
        end
    end)
    return points
end

-- Blizzard's next waypoint for the quest, as a world position on continent c.
local function BlizzardPoint(questID, c)
    if not (C_QuestLog and C_QuestLog.GetNextWaypoint) then return nil end
    local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
    if not (mapID and x) then return nil end
    local pc, wx, wy = ns.MapToWorld(mapID, x, y)
    if pc == c then return { c = c, x = wx, y = wy } end
end

local function Circle(points)
    local cx, cy = 0, 0
    for _, p in ipairs(points) do cx, cy = cx + p.x, cy + p.y end
    cx, cy = cx / #points, cy / #points
    local r = 0
    for _, p in ipairs(points) do r = math.max(r, ns.Distance(cx, cy, p.x, p.y)) end
    return cx, cy, r
end

function ns.GoObjective()
    local questID = SelectedQuest()
    if not questID then
        ns.Print("select a quest first: click it in the quest tracker or quest log")
        return
    end
    local _, c, px, py = ns.GetPlayerPose()
    if not px then ns.Print("your position isn't available here") return end
    local navMap = ns.Navigator.DefaultMap()
    if not navMap then return end

    local spawns = QuestieSpawns(questID, c)
    local cx, cy, r
    if #spawns > 0 then cx, cy, r = Circle(spawns) end

    if r and r >= MIN_AREA_RADIUS then
        -- An area: the reachable navigation point nearest its edge.
        local previous = ns.Graph.Use(navMap)
        local startId = ns.Graph.Nearest(c, px, py)
        local reachable = startId and ns.Graph.Distances(startId) or {}
        ns.Graph.Use(previous)
        local best, bestGap
        for id in pairs(reachable) do
            local node = navMap.nodes[id]
            local gap = math.abs(ns.Distance(cx, cy, node.x, node.y) - r)
            if not bestGap or gap < bestGap then best, bestGap = id, gap end
        end
        if best then
            local node = navMap.nodes[best]
            ns.Navigator.Travel(navMap, { c = c, x = node.x, y = node.y }, "objective area", best)
            return
        end
    end

    -- No area: straight to the objective's spot.
    local spot = (cx and { c = c, x = cx, y = cy }) or BlizzardPoint(questID, c)
    if not spot then
        ns.Print("can't find where that quest's objective is on this continent")
        return
    end
    ns.Navigator.Travel(navMap, spot, "objective")
end

ns.RegisterCommand("objective", "- walk to the selected quest's objective (same as /goto objective)", function() ns.GoObjective() end)
