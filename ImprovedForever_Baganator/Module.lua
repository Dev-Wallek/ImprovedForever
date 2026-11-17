-- Improved Forever: Baganator. Baganator's windows with the controller: it
-- opens wherever the game's bags would (Bags.lua), L2 / R2 reach them
-- (Windows.lua), its Auto Open left out at the auction house while our
-- auction window is on (AutoOpen.lua), set up in its tab (BaganatorEditor.lua), its junk is the
-- core's verdict. Loaded only with
-- Baganator (its TOC's dependency).
local IF = ImprovedForever

-- (badge: Baganator's own logo, read from its folder at runtime; its license doesn't let us ship a copy)
IF.AddModule({ key = "baganator", label = "Baganator", icon = IF.TEX .. "ic_mod_baganator",
    badge = "Interface\\AddOns\\Baganator\\Assets\\logo", addon = ... })

local BG = {}
IF.Baganator = BG

local DEFAULTS = { radial = true, switch = true }

-- (filled once: the saved table is only replaced at login, and nothing sets a key to nil to mean its default)
local settings
function BG.Settings()
    if settings then return settings end
    local db = IF.db
    -- (a test's log, left in saved variables)
    db.bagsLog = nil
    db.baganator = db.baganator or {}
    settings = db.baganator
    for key, value in pairs(DEFAULTS) do
        if settings[key] == nil then settings[key] = value end
    end
    return settings
end

-- Baganator's junk (its junk category, grey icons) is the core's verdict (ItemValue.lua),
-- redrawn on every change.
-- Baganator picks this plugin by itself unless its junk setting names another registered one,
-- which its default (grey items only) isn't.
Baganator.API.RegisterJunkPlugin("Improved Forever", "improvedforever", function(bag, slot)
    return IF.ItemValue.IsJunk(bag, slot)
end)
IF.ItemValue.OnChange(function() Baganator.API.RequestItemButtonsRefresh() end)
