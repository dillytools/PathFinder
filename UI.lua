local _, ns = ...

---------------------------------------------------------------------------
-- Small windows: a list to pick a navigation map from, the save dialog
-- shown when drawing is done, and a text box for exporting and importing
-- maps. All close with Escape, and sit above the world map.
---------------------------------------------------------------------------

local STRATA = "FULLSCREEN_DIALOG"
local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function NewWindow(name, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata(STRATA)
    f:SetToplevel(true)
    f:SetBackdrop(BACKDROP)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, name)   -- Escape closes it
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -18)
    return f
end

local function NewButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

---------------------------------------------------------------------------
-- Picker: ns.ShowPicker(title, rows, anchor) with rows = { { text, onClick } or { text, header = true }, ... }.
-- Header rows are gold section titles, not clickable. With anchor, it drops down below that frame.
---------------------------------------------------------------------------

local ROW_HEIGHT, MAX_ROWS = 22, 20
local picker = NewWindow("PathFinderPicker", 380, 100)
local pickerRows = {}
local pickerCancel = NewButton(picker, CANCEL, 100)
pickerCancel:SetPoint("BOTTOM", 0, 16)
pickerCancel:SetScript("OnClick", function() picker:Hide() end)

function ns.ShowPicker(title, rows, anchor)
    picker.title:SetText(title)
    for i = 1, math.max(#rows, #pickerRows) do
        local row = pickerRows[i]
        if not row and rows[i] then
            row = CreateFrame("Button", nil, picker)
            row:SetSize(340, ROW_HEIGHT)
            row:SetPoint("TOP", 0, -40 - (i - 1) * ROW_HEIGHT)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", 8, 0)
            row.text:SetPoint("RIGHT", -8, 0)
            row.text:SetJustifyH("LEFT")
            pickerRows[i] = row
        end
        if row then
            local entry = i <= MAX_ROWS and rows[i]
            row:SetShown(entry and true or false)
            if entry then
                row.text:SetText(entry.text)
                row.text:SetFontObject(entry.header and "GameFontNormal" or "GameFontHighlight")
                row.text:SetPoint("LEFT", entry.header and 8 or 20, 0)
                row:EnableMouse(not entry.header)
                row:SetScript("OnClick", function()
                    picker:Hide()
                    entry.onClick()
                end)
            end
        end
    end
    picker:SetHeight(40 + math.min(#rows, MAX_ROWS) * ROW_HEIGHT + 50)
    picker:ClearAllPoints()
    if anchor then picker:SetPoint("TOP", anchor, "BOTTOM", 0, -4) else picker:SetPoint("CENTER", 0, 80) end
    picker:Show()
end

---------------------------------------------------------------------------
-- Save dialog: ns.ShowSaveDialog(map, zoneName, onSave(name, kind), onDelete)
---------------------------------------------------------------------------

local save = NewWindow("PathFinderSave", 340, 210)
save.title:SetText("Save navigation map")

-- Shows the name and type set in the drawing box; they're edited there, not here.
local summary = save:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
summary:SetPoint("TOPLEFT", 24, -46)
summary:SetPoint("RIGHT", -24, 0)
summary:SetJustifyH("LEFT")
summary:SetSpacing(6)
local saveButton = NewButton(save, SAVE or "Save", 90)
saveButton:SetPoint("BOTTOMLEFT", 20, 18)
local deleteButton = NewButton(save, "Delete map", 100)
deleteButton:SetPoint("BOTTOM", 0, 18)
local cancelButton = NewButton(save, CANCEL, 90)
cancelButton:SetPoint("BOTTOMRIGHT", -20, 18)
cancelButton:SetScript("OnClick", function() save:Hide() end)

StaticPopupDialogs["PATHFINDER_DELETE_DRAWING"] = {
    text = "Delete the navigation map \"%s\"?",
    button1 = DELETE,
    button2 = CANCEL,
    OnAccept = function(_, onDelete) onDelete() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Save, or Delete map (after confirming), or Cancel (back to drawing; neither callback runs).
-- The name and type come from the drawing box; a map without a name uses its zone's.
function ns.ShowSaveDialog(m, zoneName, onSave, onDelete)
    local name = m.name and m.name ~= "" and m.name or zoneName or ""
    summary:SetText(format("|cffffd100Name|r     %s\n|cffffd100Type|r      %s\n|cffffd100Path|r      %s\n|cffffd100Zone|r      %s",
        name ~= "" and name or "|cffff4040no name yet|r", ns.Maps.KIND_NAMES[m.kind] or "Safe",
        m.curved and "Curved" or "Exact", zoneName or "unknown"))
    saveButton:SetEnabled(name ~= "")
    saveButton:SetScript("OnClick", function()
        save:Hide()
        onSave(name, m.kind or "safe")
    end)
    deleteButton:SetScript("OnClick", function()
        save:Hide()
        local dialog = StaticPopup_Show("PATHFINDER_DELETE_DRAWING", name ~= "" and name or "this map")
        if dialog then dialog.data = onDelete end
    end)
    save:Show()
end

---------------------------------------------------------------------------
-- Text box: ns.ShowTextBox(title, text, buttonText, onButton(text))
-- For export (text filled in and selected, Ctrl+C to copy) and import
-- (empty, paste with Ctrl+V, then the button).
---------------------------------------------------------------------------

local box = NewWindow("PathFinderText", 460, 260)
local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 22, -42)
scroll:SetPoint("BOTTOMRIGHT", -40, 50)
local edit = CreateFrame("EditBox", nil, scroll)
edit:SetMultiLine(true)
edit:SetFontObject("ChatFontNormal")
edit:SetWidth(390)
edit:SetAutoFocus(false)
edit:SetScript("OnEscapePressed", function() box:Hide() end)
scroll:SetScrollChild(edit)
local boxButton = NewButton(box, OKAY, 100)
boxButton:SetPoint("BOTTOMLEFT", 22, 16)
local boxClose = NewButton(box, CLOSE, 100)
boxClose:SetPoint("BOTTOMRIGHT", -22, 16)
boxClose:SetScript("OnClick", function() box:Hide() end)

function ns.ShowTextBox(title, text, buttonText, onButton)
    box.title:SetText(title)
    edit:SetText(text or "")
    boxButton:SetShown(onButton ~= nil)
    if onButton then
        boxButton:SetText(buttonText)
        boxButton:SetScript("OnClick", function()
            if onButton(edit:GetText()) ~= false then box:Hide() end
        end)
    end
    box:Show()
    edit:SetFocus()
    edit:HighlightText()
end
