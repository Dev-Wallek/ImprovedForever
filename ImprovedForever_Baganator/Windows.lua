-- Baganator's windows in L2 / R2, beside the game's windows, as ours (the
-- core's Focus.lua): its bags, bank and guild bank, its customise dialog, its
-- character list, its search help and the bag slots bar above the bags or bank, each one its
-- own place in the row by where it sits on screen, its focus glow on while it
-- has the pad (the bar has none: the cursor alone shows it), the game's focus
-- dimmed meanwhile, the core's cursor in it (Navigator.lua: D-pad, A, X,
-- Y for an item's menu, Select for the search box, Select again lets the
-- pad go with the window left open: Away below),
-- Circle closes it (the bar by Baganator's own toggle). The game's frame
-- manager never lists them, so the pad is taken by a catcher frame of ours
-- on each. Never in combat: combat lets the pad go.
local IF = ImprovedForever

local F = IF.Focus
local BG = IF.Baganator

-- (Baganator's skin tags for its windows)
local KINDS = { backpack = true, bank = true, guild = true, customise = true }
local CHARACTERS = "^Baganator_CharacterSelectFrame"
-- (its skin sees the search help with no tag)
local HELP = "Baganator_SearchHelpFrame"

local places = {}   -- win -> { sw, catcher, nav }

local function X(f)
    return f:GetCenter() * f:GetEffectiveScale()
end

-- (on screen: the bag slots bar stays shown under a hidden bags window)
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

-- The next of ours along from win towards the game's window (with none
-- open: the nearest of ours), or nil
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

-- The nearest of ours still shown, other than win, or nil
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
local hush = CreateFrame("Button", "ImprovedForeverBaganatorSelect")
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
-- TOGGLEUIFOCUS on the same press), the radial's Bags (BG.Back), or L2 / R2
-- from a game window beside it.
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
    if BG.Settings().switch and F.GameWindow(win) then v.sw:Update() end
end

-- An item's menu, with KeepOrSell loaded: its keep mark, by its /kos keep | unkeep
-- (KeepOrSellDB.keep: it has no Lua API)
local function KeepOrSell(id, Add)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("KeepOrSell")) then return end
    local db, kos = _G.KeepOrSellDB, SlashCmdList.KEEPORSELL
    if not (db and kos) then return end
    local kept = db.keep and db.keep[id]
    Add(kept and "KeepOrSell: don't keep" or "KeepOrSell: keep", function() kos((kept and "unkeep " or "keep ") .. id) end)
end

-- win joins the row: close() is its B, root (optional) where its elements are
local function Watch(win, close, root)
    if places[win] then return end
    local catcher = CreateFrame("Frame", nil, win)
    catcher:SetAllPoints(win)
    local v = { catcher = catcher, nav = IF.Navigator.New(win, root) }
    places[win] = v
    v.sw = F.Switch(win, {
        other = function() return Neighbour(win) end,
        onChange = function(focus)
            if focus == "ours" then
                v.away = false
                -- (one of ours at a time; the one letting go first, so its dim is put back before ours)
                for other, o in pairs(places) do
                    if other ~= win and o.sw.focus == "ours" then Release(other) end
                end
                Apply(win)
            else
                Apply(win)
                local to = places[v.sw:Other()]
                if to then to.sw:Set("ours") end
            end
        end,
    })
    -- (holding nothing till it shows)
    v.sw.focus = "game"
    v.nav.onAway = function() Away(win) end
    v.nav.hint = function() return BG.Settings().switch and v.sw:Hint() or nil end
    v.nav.itemEntries = KeepOrSell
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
    catcher:SetScript("OnUpdate", function()
        if v.away then
            WhileAway(win, v)
        else
            Hush(v, false)
            if BG.Settings().switch then v.sw:Update() end
        end
        -- (the legend's L2 / R2 entry follows the game's windows coming and going)
        local hint = v.nav.hint()
        local hintId = hint and hint[1] .. hint[3]
        if hintId ~= v.hintId then
            v.hintId = hintId
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
        if not BG.Settings().switch then return end
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
        -- (straight to the nearest of ours left open: its switch would wait for L2 / R2 from the game's window)
        local to = held and places[Nearest(win)]
        if to then to.sw:Set("ours") end
    end)
end

-- The bag slots bar above a bags or bank view: Baganator keeps its frame
-- shown, 0 high while off; a frame of ours over its slots is the place,
-- shown while the bar has height.
local function WatchBagSlots(view)
    local owner = view.BagSlots and view or view.Character
    local slots = owner and owner.BagSlots
    if not (slots and slots.liveBagSlots and owner.ToggleBagSlots) then return end
    local bar = CreateFrame("Frame", nil, slots)
    bar:SetPoint("BOTTOMLEFT", slots, "BOTTOMLEFT")
    bar:SetPoint("TOPRIGHT", slots.liveBagSlots[#slots.liveBagSlots], "TOPRIGHT")
    bar:SetShown(slots:GetHeight() > 0)
    hooksecurefunc(slots, "SetHeight", function(_, h) bar:SetShown(h > 0) end)
    Watch(bar, function() owner:ToggleBagSlots() end, slots)
end

-- A Baganator window: its FrameGlow laid itself out for the template's
-- portrait border; each of these hides the portrait, so the glow is laid
-- out again for that border.
local function WatchWindow(win, bags)
    if places[win] then return end
    if win.FrameGlow then
        win.FrameGlow.layoutType = "ButtonFrameTemplateNoPortrait"
        win.FrameGlow:OnLoad()
    end
    Watch(win, function() win:Hide() end)
    if bags then WatchBagSlots(win) end
end

-- Baganator's skins see each of its frames as it's made (and the ones made before)
local function Seen(details)
    if details.regionType ~= "ButtonFrame" then return end
    local win = details.region
    local name = win.GetName and win:GetName()
    if name and (name == HELP or name:find(CHARACTERS)) then return WatchWindow(win) end
    for _, tag in ipairs(details.tags or {}) do
        if KINDS[tag] then return WatchWindow(win, tag == "backpack" or tag == "bank") end
    end
end
for _, details in ipairs(Baganator.API.Skins.GetAllFrames() or {}) do Seen(details) end
Baganator.API.Skins.RegisterListener(Seen)

-- The radial's Bags while one of ours is away: its pad back, true (false in combat)
function BG.Back()
    for win, v in pairs(places) do
        if v.away and Shown(win) then
            v.sw:Set("ours")
            return v.sw.focus == "ours"
        end
    end
    return false
end

function BG.SwitchOff()
    for win in pairs(places) do Release(win) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", BG.SwitchOff)
