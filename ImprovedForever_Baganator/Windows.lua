-- Baganator's bags, bank and guild bank windows in L2 / R2, beside the
-- game's windows, as ours (the core's Focus.lua): each one its own place in
-- the row by where it sits on screen, its focus glow on while it has the
-- pad, the game's focus dimmed meanwhile, Circle closes it. The game's frame
-- manager never lists them, so the pad is taken by a catcher frame of ours
-- on each. Never in combat: combat lets the pad go.
local IF = ImprovedForever

local F = IF.Focus
local BG = IF.Baganator

-- (Baganator's skin tags for its views)
local KINDS = { backpack = true, bank = true, guild = true }

local views = {}   -- view -> { sw, catcher }

local function X(f)
    return f:GetCenter() * f:GetEffectiveScale()
end

local function ShownViews()
    local list = {}
    for view in pairs(views) do
        if F.Shown(view) then list[#list + 1] = view end
    end
    return list
end

-- The next of ours along from view towards the game's window (with none
-- open: the nearest of ours), or nil
local function Neighbour(view)
    if not F.Shown(view) then return nil end
    local game, x = F.GameWindow(view), X(view)
    local gx = game and X(game)
    local best, dist
    for _, other in ipairs(ShownViews()) do
        local ox = X(other)
        if other ~= view and (not gx or (ox - x) * (gx - ox) > 0) and (not dist or math.abs(ox - x) < dist) then
            best, dist = other, math.abs(ox - x)
        end
    end
    return best
end

local function TakePad(catcher, on)
    if not IF.InCombat() then catcher:EnableGamePadButton(on) end
end

-- The view's look and pad as its switch has it
local function Apply(view)
    local v = views[view]
    local ours = v.sw.focus == "ours" and view:IsShown()
    TakePad(v.catcher, ours)
    F.Glow(view, ours)
    F.DimNative(view, ours)
end

-- Lets the pad go (to the game's or, by the switch, the next of ours)
local function Release(view)
    views[view].sw.focus = "game"
    Apply(view)
end

local function Watch(view)
    if views[view] then return end
    -- Its FrameGlow laid itself out for the template's portrait border; every
    -- view hides the portrait, so lay the glow out again for that border.
    if view.FrameGlow then
        view.FrameGlow.layoutType = "ButtonFrameTemplateNoPortrait"
        view.FrameGlow:OnLoad()
    end
    local catcher = CreateFrame("Frame", nil, view)
    catcher:SetAllPoints(view)
    local v = { catcher = catcher }
    views[view] = v
    v.sw = F.Switch(view, {
        other = function() return Neighbour(view) end,
        onChange = function(focus)
            if focus == "ours" then
                -- (one of ours at a time; the one letting go first, so its dim is put back before ours)
                for other, o in pairs(views) do
                    if other ~= view and o.sw.focus == "ours" then Release(other) end
                end
                Apply(view)
            else
                Apply(view)
                local to = views[v.sw:Other()]
                if to then to.sw:Set("ours") end
            end
        end,
    })
    -- (holding nothing till it shows)
    v.sw.focus = "game"
    catcher:SetScript("OnGamePadButtonDown", function(_, button)
        if button == "PADLTRIGGER" then v.sw:Press("LT")
        elseif button == "PADRTRIGGER" then v.sw:Press("RT")
        end
    end)
    -- (Circle on its release, as the game's windows close)
    catcher:SetScript("OnGamePadButtonUp", function(_, button)
        if button == "PAD2" then view:Hide() end
    end)
    -- (setting a gamepad handler switches the frame's input on by itself)
    catcher:EnableGamePadButton(false)
    catcher:SetScript("OnUpdate", function()
        if BG.Settings().switch then v.sw:Update() end
    end)
    view:HookScript("OnShow", function()
        if not BG.Settings().switch then return end
        -- (the pad stays where it is when a window has it: the game's or another of ours)
        local free = not (IF.InCombat() or F.GameWindow(view) or F.Holding(view))
        v.sw.focus = free and "ours" or "game"
        Apply(view)
    end)
    view:HookScript("OnHide", function() Release(view) end)
end

-- Baganator's skins see each of its frames as it's made (and the ones made before)
local function Seen(details)
    if details.regionType ~= "ButtonFrame" then return end
    for _, tag in ipairs(details.tags or {}) do
        if KINDS[tag] then return Watch(details.region) end
    end
end
for _, details in ipairs(Baganator.API.Skins.GetAllFrames() or {}) do Seen(details) end
Baganator.API.Skins.RegisterListener(Seen)

function BG.SwitchOff()
    for view in pairs(views) do Release(view) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", BG.SwitchOff)
