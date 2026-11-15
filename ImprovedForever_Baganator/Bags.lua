-- The gamepad radial's Bags toggles Baganator's bags. The radial calls
-- ToggleBackpack_Combined through a reference of its own (a hook on the
-- global never fires), which reaches OpenBackpack and opens the game's
-- bags; Baganator keeps those under a hidden parent, so they open unseen
-- and swallow the next Escape. A hook on OpenBackpack closes them and, for
-- the radial's call, toggles Baganator instead. No global is replaced.
local IF = ImprovedForever

local BG = IF.Baganator

local BAG_FRAMES = { "ContainerFrameCombinedBags" }
for i = 1, 6 do BAG_FRAMES[#BAG_FRAMES + 1] = "ContainerFrame" .. i end

-- ponytail: Hide on the game's frames can taint them; measured harmless for
-- these (Escape and combat after it unblocked), since they are never
-- visible here and none of their OnHide code runs.
local function CloseHiddenBags()
    for _, name in ipairs(BAG_FRAMES) do
        local frame = _G[name]
        if frame and frame:IsShown() and not frame:IsVisible() then frame:Hide() end
    end
end

IF.OnLogin(function()
    hooksecurefunc("OpenBackpack", function()
        if not BG.Settings().radial then return end
        -- Closed on every path, so the game's backpack always counts as shut
        -- and each radial press reaches OpenBackpack again.
        CloseHiddenBags()
        -- ponytail: the radial has no hookable entry point, so its file in the
        -- stack is the signal; swap for a hook if Forever ever exposes one.
        if debugstack(2, 6, 0):find("GamepadRadial") then
            -- (Baganator's ToggleAllBags ignores a second call in the same frame)
            ToggleAllBags()
        end
    end)
end)
