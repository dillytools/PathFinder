local addonName, ns = ...

---------------------------------------------------------------------------
-- Options > AddOns > PathFinder: checkboxes for what shows while travelling
-- and how a route ends, plus shortcuts. Opened from the minimap button's
-- menu or /pf options. Built at login, from the saved values in
-- PathFinderDB.options and .minimap.
---------------------------------------------------------------------------

local LEFT_MARGIN = 16
local ROW_HEIGHT = 30

local SECTIONS = {
    { title = "While travelling", rows = {
        { label = "Show the route on the minimap",
          tooltip = "Draws the rest of the route as a green line on the minimap.",
          get = function() return ns.db.options.minimapRoute end,
          set = function(on) ns.db.options.minimapRoute = on end },
        { label = "Show the travel panel",
          tooltip = "The panel near the top of the screen with the navigation map's name, the time left and the yards left.",
          get = function() return ns.db.options.hud end,
          set = function(on) ns.db.options.hud = on end },
        { label = "Mark the next point in the world",
          tooltip = "Moves Blizzard's floating map-pin marker along the route, one point at a time. Your own map pin comes back when the route ends.",
          get = function() return ns.db.options.worldMarker end,
          set = function(on) ns.db.options.worldMarker = on end },
        { label = "Close the world map when travel starts",
          get = function() return ns.db.options.closeMap end,
          set = function(on) ns.db.options.closeMap = on end },
    } },
    { title = "Stopping", rows = {
        { label = "Stop when I press a movement key",
          tooltip = "Whatever you have bound to forward, back, turn, strafe, jump or autorun. Escape always stops the route.",
          get = function() return ns.db.options.stopOnMoveKeys end,
          set = function(on) ns.db.options.stopOnMoveKeys = on end },
    } },
    { title = "Interface", rows = {
        { label = "Show the minimap button",
          get = function() return ns.db.minimap.shown end,
          set = function(on)
              ns.db.minimap.shown = on
              ns.ApplyMinimapButton()
          end },
    } },
}

local category

local function CreateCheck(parent, row)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(row.label)
    check:SetHitRectInsets(0, -label:GetStringWidth() - 4, 0, 0)
    check:SetScript("OnClick", function(self) row.set(self:GetChecked() and true or false) end)
    if row.tooltip then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(row.label, 1, 1, 1)
            GameTooltip:AddLine(row.tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", GameTooltip_Hide)
    end
    return check
end

local function CreatePanel()
    local panel = CreateFrame("Frame")
    local checks = {}

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetText(addonName)
    title:SetPoint("TOPLEFT", LEFT_MARGIN, -16)

    local y = -56
    for _, section in ipairs(SECTIONS) do
        local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        header:SetText(section.title)
        header:SetPoint("TOPLEFT", LEFT_MARGIN, y)
        y = y - 26
        for _, row in ipairs(section.rows) do
            local check = CreateCheck(panel, row)
            check:SetPoint("TOPLEFT", LEFT_MARGIN + 8, y)
            tinsert(checks, { check = check, row = row })
            y = y - ROW_HEIGHT
        end
        y = y - 12
    end

    -- Shortcuts.
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetText("Shortcuts")
    header:SetPoint("TOPLEFT", LEFT_MARGIN, y)
    y = y - 30
    local previous
    for _, entry in ipairs({
        { "Draw navigation maps", function() SlashCmdList.PATHFINDER("draw") end },
        { "Check PathFinder.ahk", function() SlashCmdList.PATHFINDER("ahk") end },
        { "Import a map", function() SlashCmdList.PATHFINDER("import") end },
        { "Export a map", function() SlashCmdList.PATHFINDER("export") end },
    }) do
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(160, 22)
        b:SetText(entry[1])
        b:SetScript("OnClick", entry[2])
        if previous then b:SetPoint("LEFT", previous, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", LEFT_MARGIN + 8, y) end
        previous = b
    end

    panel:SetScript("OnShow", function()
        for _, entry in ipairs(checks) do entry.check:SetChecked(entry.row.get() and true or false) end
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, addonName)
    Settings.RegisterAddOnCategory(category)
end

ns.RegisterEvent("PLAYER_LOGIN", function()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        CreatePanel()
    end
end)

function ns.OpenOptions()
    if not category then ns.Print("the options panel isn't available on this client") return end
    if InCombatLockdown() then ns.Print("can't open options in combat") return end
    local id = category.GetID and category:GetID() or category.ID
    if not (Settings.OpenToCategory and pcall(Settings.OpenToCategory, id)) then
        ns.Print("open it from Options > AddOns >", addonName)
    end
end

ns.RegisterCommand("options", "- open Options > AddOns > PathFinder", function() ns.OpenOptions() end)
