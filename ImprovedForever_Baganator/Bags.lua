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
-- Baganator. No global is replaced.
local IF = ImprovedForever

local BG = IF.Baganator

local LOG_MAX = 300

local function BackpackShown()
    for _, details in ipairs(Baganator.API.Skins.GetAllFrames() or {}) do
        if details.region:IsShown() and tContains(details.tags or {}, "backpack") then return true end
    end
    return false
end

-- (while testing: a line per bag event in IF.db.bagsLog, a fresh log each
-- session; the stack's callers, Baganator's backpack before, after and a
-- frame later)
local logStarted
local function Log(hook, decision, before, stack)
    if not IF.db then return end
    if not logStarted then
        logStarted = true
        IF.db.bagsLog = { date("%H:%M:%S") }
    end
    local log = IF.db.bagsLog
    if #log >= LOG_MAX then return end
    local callers = (stack or debugstack(3)):gsub("Interface/AddOns/", ""):gsub("%[string \"@?([^\"]+)\"%]", "%1")
    callers = callers:gsub("\n", " | "):sub(1, 400)
    local at = GetTime() % 1000
    local line = #log + 1
    log[line] = format("%.2f %s %s before=%s after=%s | %s", at, hook, decision, tostring(before),
        tostring(BackpackShown()), callers)
    C_Timer.After(0, function() log[line] = log[line] .. " | next=" .. tostring(BackpackShown()) end)
end

-- Hide sets a property of the game's frames, which CLAUDE.md forbids. These
-- are an exception: with Baganator the game's own bags are never used, and
-- Escape and combat after it stay unblocked (measured).
local function OnGenerated(frame)
    if not BG.Settings().radial then return end
    local before = BackpackShown()
    local stack = debugstack(2)
    local name = frame and frame.GetName and frame:GetName() or "?"
    if not (frame and frame:IsShown() and not frame:IsVisible()) then
        return Log("GenerateFrame " .. name, "visible: kept", before, stack)
    end
    frame:Hide()
    -- ponytail: the radial has no hookable entry point, so its file in the
    -- stack is the signal; swap for a hook if Forever ever exposes one.
    -- (Baganator's ToggleAllBags ignores a second call in the same frame, so
    -- the character entry, whose ToggleBackpack Baganator toggles, isn't undone)
    if stack:find("GamepadRadial") then
        ToggleAllBags()
        return Log("GenerateFrame " .. name, "hidden, radial: toggled", before, stack)
    end
    Log("GenerateFrame " .. name, "hidden", before, stack)
end

IF.OnLogin(function()
    hooksecurefunc("ContainerFrame_GenerateFrame", OnGenerated)
    for _, fn in ipairs({ "ToggleBackpack", "ToggleBag", "OpenAllBags", "CloseAllBags" }) do
        hooksecurefunc(fn, function(arg)
            local opener = type(arg) == "table" and arg.GetName and arg:GetName() or tostring(arg)
            Log(fn .. " " .. opener, "-", nil)
        end)
    end
end)
