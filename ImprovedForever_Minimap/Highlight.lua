-- What can be looted or gathered, easier to see:
-- - every interact icon (the game's "Interact icons: show all": corpses,
--   chests, herbs, ore, quest objects), over what the interact key would
--   reach, not over everything in sight. The values before are kept and
--   set back when it's turned off. Forever's Gamepad UI sets these as it
--   starts and stops (Blizzard_Gamepad/Core.lua), so they're set again
--   after a login and a switch of the pad.
-- - Find Herbs / Find Minerals on, for the gathering skills you have (the
--   tracking list only has those), whatever their level.
local IF = ImprovedForever
local MM = IF.Minimap
local N = IF.NodeScan

local H = {}
MM.Highlight = H

local ICONS = { "SoftTargetIconEnemy", "SoftTargetIconInteract", "SoftTargetIconGameObject", "SoftTargetLowPriorityIcons" }

local function ApplyIcons()
    local s = MM.Settings()
    if s.interactIcons then
        if not s.iconsBefore then
            s.iconsBefore = {}
            for _, cvar in ipairs(ICONS) do s.iconsBefore[cvar] = GetCVar(cvar) end
        end
        for _, cvar in ipairs(ICONS) do SetCVar(cvar, "1") end
    elseif s.iconsBefore then
        for cvar, value in pairs(s.iconsBefore) do SetCVar(cvar, value) end
        s.iconsBefore = nil
    end
end

local function ApplyTracking()
    if not MM.Settings().trackGathering then return end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        local spell = info and info.spellID
        if spell and not IF.Secret(spell) and N.FIND_SPELLS[spell] and not info.active then
            C_Minimap.SetTracking(i, true)
        end
    end
end

function H.Apply()
    if not IF.db then return end
    ApplyIcons()
    ApplyTracking()
end

-- (a moment after: the Gamepad UI sets its values in the same events)
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GAME_PAD_ACTIVE_CHANGED", "SKILL_LINES_CHANGED" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function() C_Timer.After(1, H.Apply) end)
