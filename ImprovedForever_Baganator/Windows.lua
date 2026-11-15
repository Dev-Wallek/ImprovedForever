-- Baganator's windows in L2 / R2, beside the game's windows, as ours (the
-- core's Focus.lua): its bags, bank and guild bank, its customise dialog, its
-- character list and the bag slots bar above the bags or bank, each one its
-- own place in the row by where it sits on screen, its focus glow on while it
-- has the pad (the bar has none: the cursor alone shows it), the game's focus
-- dimmed meanwhile, the core's cursor in it (Navigator.lua: D-pad, A, X),
-- Circle closes it (the bar by Baganator's own toggle). The game's frame
-- manager never lists them, so the pad is taken by a catcher frame of ours
-- on each. Never in combat: combat lets the pad go.
local IF = ImprovedForever

local F = IF.Focus
local BG = IF.Baganator

-- (Baganator's skin tags for its windows)
local KINDS = { backpack = true, bank = true, guild = true, customise = true }
local CHARACTERS = "^Baganator_CharacterSelectFrame"

local places = {}   -- win -> { sw, catcher, nav }

local function X(f)
    return f:GetCenter() * f:GetEffectiveScale()
end

local function ShownPlaces()
    local list = {}
    for win in pairs(places) do
        if F.Shown(win) then list[#list + 1] = win end
    end
    return list
end

-- The next of ours along from win towards the game's window (with none
-- open: the nearest of ours), or nil
local function Neighbour(win)
    if not F.Shown(win) then return nil end
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

local function TakePad(catcher, on)
    if not IF.InCombat() then catcher:EnableGamePadButton(on) end
end

-- The place's look and pad as its switch has it
local function Apply(win)
    local v = places[win]
    local ours = v.sw.focus == "ours" and win:IsShown()
    TakePad(v.catcher, ours)
    F.Glow(win, ours)
    F.DimNative(win, ours)
    v.nav:Set(ours)
end

-- Lets the pad go (to the game's or, by the switch, the next of ours)
local function Release(win)
    places[win].sw.focus = "game"
    Apply(win)
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
    -- (A and X go on to the navigator's bindings: a use is protected)
    catcher:SetScript("OnGamePadButtonDown", function(self, button)
        self:SetPropagateKeyboardInput(v.nav:Passes(button))
        if v.nav:Press(button, true) then return end
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
    -- (setting a gamepad handler switches the frame's input on by itself)
    catcher:EnableGamePadButton(false)
    catcher:SetScript("OnUpdate", function()
        if BG.Settings().switch then v.sw:Update() end
    end)
    win:HookScript("OnShow", function()
        if not BG.Settings().switch then return end
        -- (the pad stays where it is when a window has it: the game's or another of ours)
        local free = not (IF.InCombat() or F.GameWindow(win) or F.Holding(win))
        v.sw.focus = free and "ours" or "game"
        Apply(win)
    end)
    win:HookScript("OnHide", function() Release(win) end)
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
    if name and name:find(CHARACTERS) then return WatchWindow(win) end
    for _, tag in ipairs(details.tags or {}) do
        if KINDS[tag] then return WatchWindow(win, tag == "backpack" or tag == "bank") end
    end
end
for _, details in ipairs(Baganator.API.Skins.GetAllFrames() or {}) do Seen(details) end
Baganator.API.Skins.RegisterListener(Seen)

function BG.SwitchOff()
    for win in pairs(places) do Release(win) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", BG.SwitchOff)
