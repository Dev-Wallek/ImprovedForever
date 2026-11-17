-- Baganator stands in for the game's bags. Baganator keeps those under a
-- hidden parent, so none of their OnShow scripts runs, yet the game still
-- opens them (the radial, the mailbox, a merchant, the bank...), unseen,
-- and then takes them as open: the radial's next Bags only closes them, the
-- next Escape goes to them. Every open builds the frame with
-- ContainerFrame_GenerateFrame, so a hook there closes it again at once.
-- Baganator opens by itself on ToggleBackpack / ToggleBag (a key, the
-- character window) and by its Auto Open settings (mailbox, merchant, bank,
-- trade...). The radial's Bags calls ToggleBackpack_Combined, which reaches
-- neither, so for that one (GamepadRadial in the stack) the hook toggles
-- Baganator, or gives the pad back to a window of it that let it go
-- (Windows.lua: BG.Back). No global is replaced.
local IF = ImprovedForever

local BG = IF.Baganator

-- Hide sets a property of the game's frames: allowed here only as one of
-- the exceptions in docs/taint.md (the game's bag frames under Baganator's hidden parent).
local function OnGenerated(frame)
    if not BG.Settings().radial then return end
    if not (frame and frame:IsShown() and not frame:IsVisible()) then return end
    frame:Hide()
    -- ponytail: the radial has no hookable entry point, so its file in the
    -- stack is the signal; swap for a hook if Forever ever exposes one.
    -- (Baganator's ToggleAllBags ignores a second call in the same frame, so
    -- the character entry, whose ToggleBackpack Baganator toggles, isn't undone)
    if debugstack(2):find("GamepadRadial") and not BG.Back() then ToggleAllBags() end
end

IF.OnLogin(function()
    hooksecurefunc("ContainerFrame_GenerateFrame", OnGenerated)
end)
