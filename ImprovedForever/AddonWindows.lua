-- Other addons' windows in L2 / R2, beside the game's windows, as ours
-- (Focus.lua): each one its own place in the row by where it sits on screen,
-- its focus glow on while it has the pad (a window without FrameGlow has
-- none: the cursor alone shows it), the game's focus dimmed meanwhile, the
-- navigator's cursor in it (Navigator.lua: D-pad, A, X, Y on an item, Select
-- for the search box, Select again lets the pad go with the window left
-- open: Away below), Circle closes it. The game's frame manager never lists
-- them, so the pad is taken by a catcher frame of ours on each. Never in
-- combat: combat lets the pad go.
-- Which windows: those a module hands in (Baganator's, ImprovedForever_Baganator),
-- and every frame another addon put in UISpecialFrames (the list Escape closes),
-- told from the game's by issecurevariable: what lies beyond that list is the
-- addon's to offer.
--   W.Watch(win, opts?): win joins the row; opts.close() its B (default: hide),
--     opts.root where its elements are (Navigator.New), opts.enabled() false
--     while its module's switch setting is off, opts.itemEntries the
--     navigator's extra item entries
--   W.Watched(win) -> true once it joined
--   W.Back(only) -> true when a window let go by Select (only(win): which
--     ones) took the pad back (false in combat)
--   W.Refresh(): every window whose opts.enabled() is false lets the pad go
--   W.Claim(addon): its UISpecialFrames entries are left to the module that
--     hands its windows in
--   W.Scanned() -> false while the General tab's switch keeps the found ones out
local _, IF = ...

local W = {}
IF.AddonWindows = W

local F = IF.Focus

local places = {}   -- win -> { sw, catcher, nav, enabled, ... }

local function X(f)
    return f:GetCenter() * f:GetEffectiveScale()
end

-- (on screen: a window kept shown under a hidden parent isn't)
local function Shown(win)
    return win:IsVisible() and F.Shown(win)
end

local function ShownPlaces()
    local list = {}
    for win in pairs(places) do
        if Shown(win) then list[#list + 1] = win end
    end
    return list
end

-- The next of these along from win towards the game's window (with none
-- open: the nearest), or nil
local function Neighbour(win)
    if not Shown(win) then return nil end
    local game, x = F.GameWindow(win), X(win)
    local gx = game and X(game)
    local best, dist
    for _, other in ipairs(ShownPlaces()) do
        local ox = X(other)
        if other ~= win and (not gx or (ox - x) * (gx - ox) > 0) and (not dist or math.abs(ox - x) < dist) then
            best, dist = other, math.abs(ox - x)
        end
    end
    return best
end

-- The nearest of these still shown, other than win, or nil
local function Nearest(win)
    local x = win:GetCenter() and X(win) or 0
    local best, dist
    for _, other in ipairs(ShownPlaces()) do
        local d = math.abs(X(other) - x)
        if other ~= win and (not dist or d < dist) then best, dist = other, d end
    end
    return best
end

-- (the sticks too while the window can scroll: the right one scrolls, the
-- character and camera stay still)
local function TakeSticks(v, on)
    local stick = on and v.nav:Scrolls()
    if stick == v.stick or IF.InCombat() then return end
    v.stick = stick
    v.catcher:EnableGamePadStick(stick)
end

local function TakePad(v, on)
    if IF.InCombat() then return end
    v.catcher:EnableGamePadButton(on)
    TakeSticks(v, on)
end

-- The place's look and pad as its switch has it; the bind panel's while
-- that is up (opened from the navigator's menu: its override bindings
-- would be behind our catcher)
local function Apply(win)
    local v = places[win]
    local ours = v.sw.focus == "ours" and win:IsVisible() and not IF.BindPanel.Shown()
    F.Glow(win, ours)
    F.DimNative(win, ours)
    v.nav:Set(ours)
    TakePad(v, ours)
end

-- Select while away with no window of the game's shown: the game's
-- TOGGLEUIFOCUS would only say it has none to focus. A button of ours that
-- does nothing takes PADBACK meanwhile (WhileAway sees the press by
-- IsKeyDown), out of combat, unless another click of an addon is on it
-- (the touchpad's, Touchpad.lua).
local SELECT = "PADBACK"
local hush = CreateFrame("Button", "ImprovedForeverWindowSelect")
local HUSH = "CLICK " .. hush:GetName() .. ":LeftButton"

local function Hush(v, on)
    if on == (v.hush or false) or InCombatLockdown() then return end
    v.hush = on
    if on then
        SetOverrideBindingClick(v.catcher, true, SELECT, hush:GetName())
    else
        ClearOverrideBindings(v.catcher)
    end
end

-- Lets the pad go (to the game's or, by the switch, the next of ours)
local function Release(win)
    places[win].sw.focus = "game"
    Hush(places[win], false)
    Apply(win)
end

-- Away, as the game's TOGGLEUIFOCUS (Select, no window's own) unfocuses its
-- windows: the window stays open behind, the pad is the game's (the
-- character's, or its focused window's) and none of ours takes it. It comes
-- back with Select while the game's windows don't have the pad (the game's
-- TOGGLEUIFOCUS on the same press), W.Back (the radial's Bags, for the
-- bags), or L2 / R2 from a game window beside it.
local function Away(win)
    local v = places[win]
    v.away = true
    -- (not by sw:Set: that hands the pad on to the next of ours)
    v.sw.focus = "game"
    v.sw.held.LT, v.sw.held.RT = true, true
    v.selectHeld, v.gameFocus = nil, nil
    Apply(win)
end

local function WhileAway(win, v)
    local m = F.Manager()
    local down = IsKeyDown("PADBACK")
    local fresh = down and not v.selectHeld and not v.gameFocus
    v.selectHeld = down
    v.gameFocus = m and m.isUIFocused or false
    local now = GetBindingAction(SELECT, true)
    local taken = now and now:find("^CLICK ") and now ~= HUSH
    Hush(v, m ~= nil and not m.isUIFocused and #(m.shownFrames or {}) == 0 and not taken)
    if fresh then return v.sw:Set("ours") end
    if v.enabled() and F.GameWindow(win) then v.sw:Update() end
end

local function Always() return true end

function W.Watch(win, opts)
    if places[win] then return end
    opts = opts or {}
    local close = opts.close or function() win:Hide() end
    local catcher = CreateFrame("Frame", nil, win)
    catcher:SetAllPoints(win)
    local v = { catcher = catcher, nav = IF.Navigator.New(win, opts.root), enabled = opts.enabled or Always }
    places[win] = v
    v.sw = F.Switch(win, {
        other = function() return Neighbour(win) end,
        -- (the others of ours let go and the pad goes on in Switch:Set)
        onChange = function(focus)
            if focus == "ours" then v.away = false end
            Apply(win)
        end,
    })
    -- (holding nothing till it shows)
    v.sw.focus = "game"
    v.nav.onAway = function() Away(win) end
    v.nav.hint = function() return v.enabled() and v.sw:Hint() or nil end
    v.nav.itemEntries = opts.itemEntries
    -- (A and X go on to the navigator's bindings: a use is protected)
    -- (the press first: it forgets a stale release to swallow, which Passes reads)
    catcher:SetScript("OnGamePadButtonDown", function(self, button)
        local taken = v.nav:Press(button, true)
        self:SetPropagateKeyboardInput(v.nav:Passes(button))
        if taken then return end
        if button == "PADLTRIGGER" then v.sw:Press("LT")
        elseif button == "PADRTRIGGER" then v.sw:Press("RT")
        end
    end)
    -- (Circle on its release, as the game's windows close; an item on the
    -- mouse put back first)
    catcher:SetScript("OnGamePadButtonUp", function(self, button)
        self:SetPropagateKeyboardInput(v.nav:Passes(button))
        if v.nav:Press(button, false) then return end
        if button == "PAD2" then
            if CursorHasItem() then ClearCursor() else close() end
        end
    end)
    catcher:SetScript("OnGamePadStick", function(_, stick, _, y) v.nav:Stick(stick, y) end)
    -- (setting a gamepad handler switches the frame's input on by itself)
    catcher:EnableGamePadButton(false)
    catcher:EnableGamePadStick(false)
    v.stick = false
    local since = 0
    catcher:SetScript("OnUpdate", function(_, elapsed)
        if v.away then
            WhileAway(win, v)
        else
            Hush(v, false)
            if v.enabled() then v.sw:Update() end
        end
        -- (the rest ten times a second: what it follows changes rarely)
        since = since + elapsed
        if since < 0.1 then return end
        since = 0
        -- (the legend's L2 / R2 entry follows the game's windows coming and going;
        -- the switch hands out the same table while its entry stays the same)
        local hint = v.nav.hint()
        if hint ~= v.hint then
            v.hint = hint
            v.nav:ShowLegend()
        end
        local binding = IF.BindPanel.Shown()
        if binding ~= v.binding then
            v.binding = binding
            if v.sw.focus == "ours" then Apply(win) end
        end
        -- (a list that only now has more than fits)
        TakeSticks(v, v.sw.focus == "ours")
    end)
    win:HookScript("OnShow", function()
        if not v.enabled() then return end
        -- (opened together with the game's window that has the pad, or with another of these
        -- windows: the pad stays there; opened from another window of ours: the pad is this one's)
        local holder = F.Holding(win)
        local free = not IF.InCombat() and (holder and not places[holder] or not (holder or F.GameWindow(win)))
        v.away = false
        if free then v.sw:Take() else v.sw.focus = "game" end
        Apply(win)
    end)
    win:HookScript("OnHide", function()
        v.away = false
        local held = v.sw.focus == "ours"
        Release(win)
        -- (straight to the nearest of these left open: its switch would wait for L2 / R2 from the game's window)
        local to = held and places[Nearest(win)]
        if to then to.sw:Set("ours") end
    end)
end

function W.Watched(win)
    return places[win] ~= nil
end

function W.Back(only)
    for win, v in pairs(places) do
        if v.away and Shown(win) and (not only or only(win)) then
            v.sw:Set("ours")
            return v.sw.focus == "ours"
        end
    end
    return false
end

function W.Refresh()
    for win, v in pairs(places) do
        if not v.enabled() then Release(win) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    for win in pairs(places) do Release(win) end
end)

---------------------------------------------------------------------------
-- Every other addon's window in UISpecialFrames: looked for once a second
-- while the list grows or a name in it has no frame yet, out of combat.
---------------------------------------------------------------------------
local seen = 0          -- entries of the list looked at
local waiting = {}      -- names in it whose frame isn't made yet
local claimed = {}      -- addons whose windows a module of ours hands in itself

-- W.Scanned() -> whether the windows found here take part (the General tab's
-- "Other addons' windows in L2 / R2", IF.db.addonWindows)
function W.Scanned()
    return not (IF.db and IF.db.addonWindows == false)
end

-- W.Claim(addon): its windows come through W.Watch from a module (theirs
-- need more: Baganator's glow layout, bag slots bar, setting)
function W.Claim(addon)
    claimed[addon] = true
end

-- (a frame of another addon's that can take a catcher: not ours, not claimed, not protected)
local function Watchable(win, addon)
    return type(win) == "table" and win.GetObjectType and not win:IsForbidden() and not win:IsProtected()
        and win.HookScript and win.GetCenter and not addon:find("^ImprovedForever") and not claimed[addon]
end

local function Take(name, addon)
    local win = _G[name]
    if not win then
        waiting[name] = addon
        return
    end
    waiting[name] = nil
    -- (an addon may list a game frame for Escape: the frame's own name must be an addon's too)
    if places[win] or issecurevariable(name) then return end
    if Watchable(win, addon) then W.Watch(win, { enabled = W.Scanned }) end
end

local function Scan()
    if IF.InCombat() then return end
    local list = _G.UISpecialFrames
    if not list then return end
    for name, addon in pairs(waiting) do Take(name, addon) end
    for i = seen + 1, #list do
        local name = list[i]
        -- (the game's own entries are secure; one an addon added names it)
        local secure, addon = issecurevariable(list, i)
        if type(name) == "string" and not secure and type(addon) == "string" then Take(name, addon) end
    end
    seen = #list
end

IF.OnLogin(function()
    Scan()
    C_Timer.NewTicker(1, function()
        local list = _G.UISpecialFrames
        if (list and #list ~= seen) or next(waiting) then Scan() end
    end)
end)
