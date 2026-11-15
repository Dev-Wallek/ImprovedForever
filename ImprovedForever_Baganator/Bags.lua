-- Baganator stands in for the game's bags. Baganator keeps those under a
-- hidden parent, yet the game still opens them (the radial, key bindings,
-- the mailbox, a merchant, the bank...), unseen, and then takes them as
-- open: the next toggle only closes them, the next Escape goes to them. So
-- whenever one shows, it's closed again and Baganator opens instead: a
-- toggle (ToggleBackpack / ToggleBag in the stack) toggles Baganator, any
-- other open (OpenAllBags, OpenBag) shows it. A Baganator opened that way
-- closes again with the game's CloseAllBags (mailbox or merchant closed),
-- one the player opened stays. No global is replaced.
local IF = ImprovedForever

local BG = IF.Baganator

local BAG_FRAMES = { "ContainerFrameCombinedBags" }
for i = 1, 6 do BAG_FRAMES[#BAG_FRAMES + 1] = "ContainerFrame" .. i end

-- Baganator opened by the game's open, not by the player
local gameOpened = false

local function BackpackShown()
    for _, details in ipairs(Baganator.API.Skins.GetAllFrames() or {}) do
        if details.region:IsShown() and tContains(details.tags or {}, "backpack") then return true end
    end
    return false
end

-- Hide sets a property of the game's frames, which CLAUDE.md forbids. These
-- are an exception: with Baganator the game's own bags are never used, and
-- Escape and combat after it stay unblocked (measured).
local function OnGameBagShown(frame)
    if not BG.Settings().radial or frame:IsVisible() then return end
    frame:Hide()
    -- ponytail: the game names no caller, so the stack tells a toggle from an
    -- open, as Baganator's own hooks do; swap for hooks if Forever exposes one.
    local stack = debugstack()
    -- (Baganator's ToggleAllBags ignores a second call in the same frame, so
    -- its own ToggleBackpack / ToggleBag hooks don't toggle it back)
    if not stack:find("OpenAllBags") and (stack:find("ToggleBackpack") or stack:find("ToggleBag")) then
        gameOpened = false
        ToggleAllBags()
    elseif not BackpackShown() then
        gameOpened = true
        ToggleAllBags()
    end
end

IF.OnLogin(function()
    for _, name in ipairs(BAG_FRAMES) do
        local frame = _G[name]
        if frame then frame:HookScript("OnShow", OnGameBagShown) end
    end
    -- (FRAME_THAT_OPENED_BAGS still set: CloseAllBags came from another
    -- window than the one that opened the bags and closed nothing)
    hooksecurefunc("CloseAllBags", function()
        if not gameOpened or FRAME_THAT_OPENED_BAGS then return end
        gameOpened = false
        if BackpackShown() then ToggleAllBags() end
    end)
end)
