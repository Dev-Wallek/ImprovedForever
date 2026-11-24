-- What can be looted or gathered, easier to see:
-- - every interact icon (the game's "Interact icons: show all": corpses,
--   chests, herbs, ore, quest objects), over what the interact key would
--   reach, not over everything in sight. Set as temporary values over the
--   saved ones, as Forever's Gamepad UI sets its own (Blizzard_Gamepad/Core.lua:
--   SetupTempCVar), so the player's saved choice stays; set again after a
--   login and a switch of the pad, which put the game's back.
-- - Find Herbs / Find Minerals on, for the gathering skills you have (the
--   tracking list only has those), whatever their level.
local IF = ImprovedForever
local MM = IF.Minimap
local N = IF.NodeScan

local H = {}
MM.Highlight = H

local ICONS = { "SoftTargetIconEnemy", "SoftTargetIconInteract", "SoftTargetIconGameObject", "SoftTargetLowPriorityIcons" }
-- (the Gamepad UI's own temporary values, put back when turned off with it on)
local PAD_VALUES = { SoftTargetIconEnemy = "0", SoftTargetIconInteract = "1", SoftTargetIconGameObject = "1" }

local applied

local function ApplyIcons()
    if MM.Settings().interactIcons then
        for _, cvar in ipairs(ICONS) do
            if GetCVar(cvar) ~= "1" then C_CVar.SetTempCVar(cvar, "1") end
        end
        applied = true
    elseif applied then
        local pad = GetCVarBool("GamePadEnable")
        for _, cvar in ipairs(ICONS) do
            if pad and PAD_VALUES[cvar] then
                C_CVar.SetTempCVar(cvar, PAD_VALUES[cvar])
            else
                C_CVar.RemoveTempCVar(cvar)
            end
        end
        applied = false
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

-- (a moment after: the Gamepad UI sets its values in the same events; a
-- skill learnt only changes the tracking)
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GAME_PAD_ACTIVE_CHANGED", "SKILL_LINES_CHANGED" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event)
    if event == "SKILL_LINES_CHANGED" then
        if IF.db then ApplyTracking() end
        return
    end
    C_Timer.After(1, H.Apply)
end)
