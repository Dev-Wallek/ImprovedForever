-- The Threat tab (IF.SettingsPage, SettingsPage.lua): the meter, the meter
-- when alone, the warnings. Module.lua does the work.
local IF = ImprovedForever

local TM = IF.ThreatMeter
local Item, OnOff = IF.SettingsItem, IF.SettingsOnOff

local function Setting(key, label, tip)
    return Item({ key = key, group = "meter", label = label, tip = tip }, OnOff(function() return TM.Settings()[key] end,
        function(on)
            TM.Settings()[key] = on
            TM.Refresh()
        end, label))
end

local ITEMS = {
    Setting("meter", "Threat meter", "Under your target in a fight: who of you, your pet and your party has how much threat on it."),
    Setting("solo", "When alone", "The meter also when no one but you is on the enemy's threat list."),
    Setting("warnings", "Aggro warnings", "Over the list: \"Losing aggro!\" while you tank and the next one is close behind, \"Pulling aggro!\" when you near the tank's threat."),
}

local GROUPS = {
    { key = "meter", label = "Meter" },
}

IF.ThreatEditor = IF.SettingsPage({ key = "threat", label = "Threat", module = "threat", order = 36 }, GROUPS, ITEMS)
