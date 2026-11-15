-- The Baganator tab, a tab of settings (IF.SettingsPage, SettingsPage.lua):
-- the radial's Bags on / off. Bags.lua does the work.
local IF = ImprovedForever

local BG = IF.Baganator
local Item, OnOff = IF.SettingsItem, IF.SettingsOnOff

local ITEMS = {
    Item({
        key = "radial", group = "bags", label = "Bags from the radial",
        tip = "Bags in the gamepad radial opens and closes Baganator's bags. Off: it opens the game's bags,"
            .. " which Baganator keeps hidden.",
    }, OnOff(function() return BG.Settings().radial end, function(on)
        BG.Settings().radial = on
    end, "Bags from the radial")),
}

local GROUPS = {
    { key = "bags", label = "Bags" },
}

IF.BaganatorEditor = IF.SettingsPage({ key = "baganator", label = "Baganator", module = "baganator", order = 57 },
    GROUPS, ITEMS)
