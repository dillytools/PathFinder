local _, ns = ...

---------------------------------------------------------------------------
-- Minimap button. Click it for a menu:
--   Start travel / Stop          walk to the destination (Navigator.lua)
--   Go to the nearest town       /goto town
--   Go to the quest objective    /goto objective
--   Draw navigation maps         the world map in path drawing mode
--   PathFinder.ahk: ...          whether the script is running; if not, where it
--                                is and how to start it (the game can't start it)
--   Options                      Options > AddOns > PathFinder
-- Drag the button around the minimap's edge to move it. Hide it in the options
-- (or /pf minimap).
---------------------------------------------------------------------------

local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local EDGE_PADDING = 10         -- distance outside the minimap's edge
local ROW_HEIGHT = 20
local MENU_WIDTH = 230
local HIDE_DELAY = 0.6          -- seconds off the button and menu before the menu closes

local button, menu
local rows = {}

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

local GREY = "|cff808080"

-- Each entry: text() and onClick(); a nil text hides the row. Built fresh each time the menu opens.
local ENTRIES = {
    { text = function()
        if ns.Navigator.IsActive() then return "Stop travelling" end
        return ns.db.finish and "Start travel" or (GREY .. "Start travel (Alt+click the world map to set a destination)|r")
      end,
      onClick = function()
        if ns.Navigator.IsActive() then ns.Navigator.Stop("stopped") else ns.Navigator.Start() end
      end },
    { text = function() return "Go to the nearest town" end, onClick = function() ns.Navigator.GoTown() end },
    { text = function() return "Go to the quest objective" end, onClick = function() ns.GoObjective() end },
    { text = function() return "Draw navigation maps" end,
      onClick = function() SlashCmdList.PATHFINDER("draw") end },
    { text = function()
        return ns.AHKAlive() and "PathFinder.ahk: |cff40ff40running|r"
            or "PathFinder.ahk: |cffff4040not running|r - how to start it"
      end,
      onClick = function() SlashCmdList.PATHFINDER("ahk") end },
    { text = function() return "Options" end, onClick = function() ns.OpenOptions() end },
}

local function CreateMenu()
    menu = CreateFrame("Frame", nil, button, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 8, 8)
    menu:SetSize(MENU_WIDTH, 32 + #ENTRIES * ROW_HEIGHT)
    menu:EnableMouse(true)

    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("PathFinder")

    for i, entry in ipairs(ENTRIES) do
        local row = CreateFrame("Button", nil, menu)
        row:SetSize(MENU_WIDTH - 16, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 8, -26 - (i - 1) * ROW_HEIGHT)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function()
            menu:Hide()
            entry.onClick()
        end)
        rows[i] = row
    end

    -- Close once the mouse has been off both the button and the menu for HIDE_DELAY.
    local away = 0
    menu:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() or button:IsMouseOver() then
            away = 0
        else
            away = away + elapsed
            if away >= HIDE_DELAY then self:Hide() end
        end
    end)
    menu:SetScript("OnShow", function() away = 0 end)
end

local function ToggleMenu()
    if not menu then CreateMenu() end
    if menu:IsShown() then menu:Hide() return end
    for i, entry in ipairs(ENTRIES) do rows[i].text:SetText(entry.text()) end
    menu:Show()
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------

local function UpdatePosition()
    local angle = math.rad(ns.db.minimap.angle)
    local radius = Minimap:GetWidth() / 2 + EDGE_PADDING
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.minimap.angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
    UpdatePosition()
end

local function CreateButton()
    button = CreateFrame("Button", "PathFinderMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function()
        GameTooltip_Hide()
        ToggleMenu()
    end)
    button:SetScript("OnEnter", function(self)
        if menu and menu:IsShown() then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("PathFinder", 1, 1, 1)
        GameTooltip:AddLine("Click for the menu. Drag to move.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnDragStart", function(self)
        if menu then menu:Hide() end
        GameTooltip_Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
end

function ns.ApplyMinimapButton()
    if ns.db.minimap.shown then
        if not button then CreateButton() end
        UpdatePosition()
        button:Show()
    elseif button then
        button:Hide()
    end
end

ns.RegisterEvent("PLAYER_LOGIN", ns.ApplyMinimapButton)

ns.RegisterCommand("minimap", "- show or hide the minimap button", function()
    ns.db.minimap.shown = not ns.db.minimap.shown
    ns.ApplyMinimapButton()
    ns.Print("minimap button", ns.db.minimap.shown and "shown" or "hidden")
end)
