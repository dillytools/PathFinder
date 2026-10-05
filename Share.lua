local _, ns = ...

---------------------------------------------------------------------------
-- Sharing navigation maps:
--   /pf export   pick a map, copy its text (Ctrl+C) to post or send
--   /pf import   paste a map's text (Ctrl+V) to install it as one of yours
--   /pf delete   pick one of your maps to delete
-- To ship a map with the addon for everyone, its text goes in a file in
-- Maps\ (see Maps\Community.lua).
---------------------------------------------------------------------------

ns.RegisterCommand("export", "- copy a navigation map's text to share it", function()
    local rows = {}
    for _, m in ipairs(ns.Maps.All()) do
        tinsert(rows, { text = ns.Maps.Label(m), onClick = function()
            ns.ShowTextBox("Export: " .. m.name .. "  (Ctrl+C to copy)", ns.Maps.Encode(m))
        end })
    end
    if #rows == 0 then ns.Print("no navigation maps installed yet") return end
    ns.ShowPicker("Export which map?", rows)
end)

ns.RegisterCommand("import", "- paste a navigation map's text to install it", function()
    ns.ShowTextBox("Import a navigation map  (Ctrl+V to paste)", "", "Import", function(text)
        local m, err = ns.Maps.Decode(text)
        if not m then ns.Print("couldn't import: " .. err) return false end
        ns.Maps.Save(m)
        ns.Print("installed " .. ns.Maps.Label(m))
    end)
end)

StaticPopupDialogs["PATHFINDER_DELETE_MAP"] = {
    text = "Delete the navigation map \"%s\"?",
    button1 = DELETE,
    button2 = CANCEL,
    OnAccept = function(_, m)
        ns.Maps.Delete(m)
        ns.Print("deleted " .. ns.Maps.Label(m))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

ns.RegisterCommand("delete", "- delete one of your navigation maps", function()
    local rows = {}
    for _, m in ipairs(ns.Maps.All()) do
        if not m.builtin then
            tinsert(rows, { text = ns.Maps.Label(m), onClick = function()
                local dialog = StaticPopup_Show("PATHFINDER_DELETE_MAP", m.name)
                if dialog then dialog.data = m end
            end })
        end
    end
    if #rows == 0 then ns.Print("you have no navigation maps of your own to delete") return end
    ns.ShowPicker("Delete which map?", rows)
end)

ns.RegisterCommand("maps", "- list installed navigation maps", function()
    local all = ns.Maps.All()
    if #all == 0 then ns.Print("no navigation maps installed yet") return end
    for _, m in ipairs(all) do
        ns.Print(ns.Maps.Label(m) .. (m.builtin and " - built-in" or ""))
    end
end)
