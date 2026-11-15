-- The Baganator tab, a tab of settings (IF.SettingsPage, SettingsPage.lua):
-- Baganator for the game's bags (Bags.lua) and the windows in L2 / R2 (Windows.lua), each on / off.
local IF = ImprovedForever

local BG = IF.Baganator
local Item, OnOff = IF.SettingsItem, IF.SettingsOnOff

local ITEMS = {
    Item({
        key = "radial", group = "bags", label = "Baganator for the game's bags",
        tip = "Whatever opens the game's bags (Bags in the gamepad radial, a key, the mailbox, a merchant, the bank)"
            .. " opens Baganator's instead; a toggle opens or closes it with one press, and one the mailbox or"
            .. " a merchant opened closes with it. Off: they open the game's bags, which Baganator keeps hidden.",
    }, OnOff(function() return BG.Settings().radial end, function(on)
        BG.Settings().radial = on
    end, "Baganator for the game's bags")),
    Item({
        key = "switch", group = "windows", label = "Windows in L2 / R2",
        tip = "Baganator's bags, bank, guild bank, customise and character windows and its bag slots bar join"
            .. " L2 / R2 beside the game's windows, each by where it sits on screen. The one with the controller"
            .. " glows; Circle closes it. A window opened while another has the controller waits for L2 / R2.",
    }, OnOff(function() return BG.Settings().switch end, function(on)
        BG.Settings().switch = on
        if not on then BG.SwitchOff() end
    end, "Windows in L2 / R2")),
}

local GROUPS = {
    { key = "bags", label = "Bags" },
    { key = "windows", label = "Windows" },
}

IF.BaganatorEditor = IF.SettingsPage({ key = "baganator", label = "Baganator", module = "baganator", order = 57 },
    GROUPS, ITEMS)
