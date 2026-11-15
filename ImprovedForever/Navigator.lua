-- A cursor for another addon's window (Baganator's bags, ...): the D-pad
-- moves it between what can be pressed there (item slots, buttons, check
-- boxes, edit boxes) by where each sits on screen, A presses it. Drawn as
-- ours (IF.Focus.Cursor, only while the window's glow is on); the element
-- is hovered as by the mouse (its OnEnter: an item's tooltip at it).
-- A runs through a secure button of ours, bound to PAD1 by a priority
-- override binding (the game's own stays on top without it), its
-- attributes set out of combat: an item slot used (type "item": use or
-- equip, at the bank moved, as a right click; at a merchant sold), a button
-- clicked (type "click"), an edit box given the focus.
--   IF.Navigator.New(win) -> nav
--   nav:Set(on): on while win has the pad (IF.Focus), never in combat
--   nav:Press(button, down) -> true when it took the press (the D-pad)
--   nav:Passes(button) -> true for PAD1 while on: the window's catcher lets
--     it through to the binding (SetPropagateKeyboardInput)
-- Combat start frees PAD1 at once (PLAYER_REGEN_DISABLED).
local _, IF = ...

local N = {}
IF.Navigator = N

local DIRS = { PADDUP = { 0, 1 }, PADDDOWN = { 0, -1 }, PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 } }
local REPEAT_DELAY, REPEAT_EVERY = 0.35, 0.1

local binder = CreateFrame("Frame")
local active   -- (the nav holding PAD1)

local use = CreateFrame("Button", "ImprovedForeverNavigatorUse", UIParent, "SecureActionButtonTemplate")
use:SetSize(1, 1)
use:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
-- (both registered, acting on the release: a pad press by an override
-- binding sends the game's key-down setting's side, else nothing runs)
use:RegisterForClicks("AnyDown", "AnyUp")
use:SetAttribute("useOnKeyDown", false)
local USE_BINDING = "CLICK " .. use:GetName() .. ":LeftButton"

local function Merchant()
    return _G.MerchantFrame and MerchantFrame:IsShown() or false
end

-- (an item slot's bag and slot, or nil)
local function Slot(f)
    if not f.GetBagID then return nil end
    local ok, bag = pcall(f.GetBagID, f)
    if not (ok and type(bag) == "number") then return nil end
    return bag, f:GetID()
end

-- Where A goes for f: its type and the attribute it reads
local function Want(f)
    local bag, slot = Slot(f)
    if bag then
        if Merchant() then return nil end
        return "item", "item", bag .. " " .. slot
    end
    if f:GetObjectType() == "EditBox" then return nil end
    return "click", "clickbutton", f
end

-- (what the secure button is set to: changed out of combat only)
local set = {}
local function Aim(f)
    if InCombatLockdown() then return end
    local kind, key, value
    if f then kind, key, value = Want(f) end
    if set.kind == kind and set.key == key and set.value == value then return end
    if set.key and set.key ~= key then use:SetAttribute(set.key, nil) end
    use:SetAttribute("type", kind)
    if key then use:SetAttribute(key, value) end
    set.kind, set.key, set.value = kind, key, value
end

-- What A does besides the secure action: an edit box focused, an item sold
use:HookScript("OnClick", function(_, _, down)
    if down then return end
    local f = active and active.sel
    if not (f and f:IsVisible()) then return end
    if f:GetObjectType() == "EditBox" then return f:SetFocus() end
    local bag, slot = Slot(f)
    if bag and Merchant() then C_Container.UseContainerItem(bag, slot) end
end)

local function Bind(on)
    if InCombatLockdown() then return end
    ClearOverrideBindings(binder)
    if on then SetOverrideBindingClick(binder, true, "PAD1", use:GetName()) end
end

local function Center(f)
    local x, y = f:GetCenter()
    if not x then return nil end
    local s = f:GetEffectiveScale()
    return x * s, y * s
end

local function Pressable(f)
    if Slot(f) then return true end
    local kind = f:GetObjectType()
    if kind == "EditBox" then return true end
    if not (kind == "Button" or kind == "CheckButton" or kind == "ItemButton") then return false end
    return f:IsEnabled() and f:IsMouseEnabled()
end

-- What can be pressed in win: shown, inside it on screen
local function Elements(win)
    local list = {}
    local l, b, w, h = win:GetRect()
    if not l then return list end
    local s = win:GetEffectiveScale()
    l, b, w, h = l * s, b * s, w * s, h * s
    local function Walk(f)
        for _, child in ipairs({ f:GetChildren() }) do
            if child:IsShown() and not child.navigatorSkip then
                if Pressable(child) then
                    local x, y = Center(child)
                    if x and child:GetWidth() > 0 and x >= l and x <= l + w and y >= b and y <= b + h then
                        list[#list + 1] = child
                    end
                else
                    Walk(child)
                end
            end
        end
    end
    Walk(win)
    return list
end

-- The one at the top left (of the item slots, when there are any)
local function First(list)
    local best, bx, by, bestSlot
    for _, f in ipairs(list) do
        local x, y = Center(f)
        local slot = Slot(f) ~= nil
        if not best or (slot and not bestSlot) or (slot == bestSlot and (y > by + 2 or (math.abs(y - by) <= 2 and x < bx))) then
            best, bx, by, bestSlot = f, x, y, slot
        end
    end
    return best
end

-- The nearest to x, y (where the lost one was)
local function Nearest(list, x, y)
    local best, dist
    for _, f in ipairs(list) do
        local fx, fy = Center(f)
        local d = (fx - x) ^ 2 + (fy - y) ^ 2
        if not dist or d < dist then best, dist = f, d end
    end
    return best
end

-- The next one from `from` in the direction: the least distance along it
-- plus three times the one across, within about 63° of it
local function Step(list, from, dx, dy)
    local fx, fy = Center(from)
    if not fx then return nil end
    local best, score
    for _, f in ipairs(list) do
        local x, y = Center(f)
        local along = (x - fx) * dx + (y - fy) * dy
        local across = math.abs((x - fx) * dy - (y - fy) * dx)
        if f ~= from and along > 1 and across <= along * 2 then
            local s = along + across * 3
            if not score or s < score then best, score = f, s end
        end
    end
    return best
end

local Nav = {}
Nav.__index = Nav

local function Hover(f, on)
    local script = f and f:GetScript(on and "OnEnter" or "OnLeave")
    if script then pcall(script, f) end
end

function Nav:Select(f)
    if f == self.sel then return end
    Hover(self.sel, false)
    self.sel = f
    if not f then
        self.cursor:Hide()
        Aim(nil)
        return
    end
    self.x, self.y = Center(f)
    self.slotKey = table.concat({ Slot(f) }, " ")
    self.cursor:Point(f)
    Hover(f, true)
    Aim(f)
end

function Nav:Set(on)
    on = on and not InCombatLockdown() or false
    if on == self.on then return end
    self.on = on
    self.held = nil
    if on then
        if active and active ~= self then active:Set(false) end
        active = self
        local keep = self.last
        self:Select((keep and keep:IsVisible() and Pressable(keep) and keep) or First(Elements(self.win)))
        Bind(true)
        self.driver:Show()
    else
        -- (the one to come back to)
        self.last = self.sel
        self:Select(nil)
        self.driver:Hide()
        if active == self then
            active = nil
            Bind(false)
        end
    end
end

function Nav:Move(button)
    local d = DIRS[button]
    local list = Elements(self.win)
    if not (self.sel and self.sel:IsVisible()) then return self:Select(First(list)) end
    local to = Step(list, self.sel, d[1], d[2])
    if to then self:Select(to) end
end

function Nav:Press(button, down)
    if not (self.on and DIRS[button]) then return false end
    if down then
        self.held, self.next = button, GetTime() + REPEAT_DELAY
        self:Move(button)
    elseif self.held == button then
        self.held = nil
    end
    return true
end

function Nav:Passes(button)
    return self.on and button == "PAD1" or false
end

-- Each frame while on: the held direction repeated, the chosen one kept
-- (lost when the window lays itself out again: the nearest instead; the
-- same button showing another item: hovered again), PAD1 bound again when
-- the game's windows bound theirs over it
local function Tick(self)
    if self.held and GetTime() >= self.next then
        self.next = GetTime() + REPEAT_EVERY
        self:Move(self.held)
    end
    local f = self.sel
    if not (f and f:IsVisible() and Pressable(f)) then
        local list = Elements(self.win)
        self.sel = nil
        return self:Select((self.x and Nearest(list, self.x, self.y)) or First(list))
    end
    local key = table.concat({ Slot(f) }, " ")
    if key ~= self.slotKey then
        self.slotKey = key
        Hover(f, true)
    end
    self.x, self.y = Center(f)
    Aim(f)
    local ok, now = pcall(GetBindingAction, "PAD1", true)
    if not (ok and now == USE_BINDING) then Bind(true) end
end

function N.New(win)
    local nav = setmetatable({ win = win, on = false }, Nav)
    nav.cursor = IF.Focus.Cursor(win)
    nav.cursor.navigatorSkip = true
    -- (over the window's own buttons, whatever their levels)
    nav.cursor:SetFrameStrata("FULLSCREEN_DIALOG")
    nav.driver = CreateFrame("Frame")
    nav.driver:Hide()
    nav.driver:SetScript("OnUpdate", function() Tick(nav) end)
    return nav
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    if active then active:Set(false) end
end)
