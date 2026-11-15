-- A cursor for another addon's window (Baganator's bags, ...): the D-pad
-- moves it between what can be pressed there (item slots, buttons, check
-- boxes, edit boxes) by where each sits on screen. Drawn as ours
-- (IF.Focus.Cursor, only while the window's glow is on); the element is
-- hovered as by the mouse (its OnEnter: an item's tooltip at it).
-- The buttons as in the game's own bag windows: A picks an item up, or puts
-- the one held down there (swapping), presses a button, focuses an edit box;
-- X uses or equips an item (at the bank moves it, at a merchant sells it).
-- Both run through a secure button of ours, bound to PAD1 (left click) and
-- PAD3 (right click) by priority override bindings (the game's own stay on
-- top without them), its attributes set out of combat. Select (PADBACK)
-- puts the keyboard in the window's search box, as in the game's bag window
-- (ContainerFrame.lua: SetUpSearchGamepad); Select again (or Select in a
-- window without a search box) leaves the box and calls nav.onAway, where
-- the window lets the pad go as the game's TOGGLEUIFOCUS does. B takes the
-- keyboard out of any edit box of the window. Y on an item opens a menu of
-- more (the game's More Actions): mark it junk or not
-- (ItemValue.lua), keep it in KeepOrSell (when loaded), bind it to the
-- crossbar (BindPanel.lua), destroy it (Cross held, longer for rare and
-- better); while it's up every press is the menu's. The right stick
-- scrolls the window's scroll box, as the game's windows scroll. A legend of
-- the game's look, one prompt a line beside the window on the side toward the
-- screen's centre, names them.
--   IF.Navigator.New(win, root?) -> nav: root, when given, holds the elements
--     (all its shown ones, wherever they sit), else those of win inside it
--   nav:Set(on): on while win has the pad (IF.Focus), never in combat
--   nav.onAway: set by the caller, run on the Select that lets the pad go
--   nav:Press(button, down) -> true when it took the press (the D-pad,
--     Select, Y, B while typing, any while the menu is up, the release of
--     one held as the navigator came on or the menu took it)
--   nav:Passes(button) -> true for A and X while on, an element chosen and
--     our bindings in place: the window's catcher lets those through
--     (SetPropagateKeyboardInput) and nothing else reaches the game's
--   nav:Scrolls() -> true while a scroll box in win can scroll: the catcher
--     takes the sticks then (EnableGamePadStick), passing nav:Stick(stick, y)
-- Combat start frees PAD1 and PAD3 at once (PLAYER_REGEN_DISABLED).
local _, IF = ...

local N = {}
IF.Navigator = N

local DIRS = { PADDUP = { 0, 1 }, PADDDOWN = { 0, -1 }, PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 } }
local REPEAT_DELAY, REPEAT_EVERY = 0.35, 0.1
local LEGEND_GAP = 8
-- (the menu's names for the pad's buttons: Dropdown.lua)
local MENU_KEYS = { PADDUP = "UP", PADDDOWN = "DOWN", PADDLEFT = "LEFT", PADDRIGHT = "RIGHT",
    PAD1 = "A", PAD2 = "B", PAD4 = "B" }
local PRESSES = { "PAD1", "PAD2", "PAD3", "PAD4", "PADBACK", "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }
-- (destroying: Cross held this long, rare and better longer)
local HOLD, HOLD_RARE, RARE = 0.6, 1.5, 3

local binder = CreateFrame("Frame")
local active   -- (the nav holding PAD1)

local use = CreateFrame("Button", "ImprovedForeverNavigatorUse", UIParent, "SecureActionButtonTemplate")
use:SetSize(1, 1)
use:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
-- (both registered, acting on the release: a pad press by an override
-- binding sends the game's key-down setting's side, else nothing runs)
use:RegisterForClicks("AnyDown", "AnyUp")
use:SetAttribute("useOnKeyDown", false)
local BINDS = { PAD1 = "LeftButton", PAD3 = "RightButton" }
local function Action(key)
    return "CLICK " .. use:GetName() .. ":" .. BINDS[key]
end

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

-- The secure attributes for f: A (suffix 1) clicks a button; X (suffix 2)
-- uses an item, as a right click. An item picked up, sold or an edit box
-- focused is our hook's.
local function Wanted(f)
    if not f then return {} end
    local bag, slot = Slot(f)
    if bag then
        if Merchant() then return {} end
        return { type2 = "item", item2 = bag .. " " .. slot }
    end
    if f:GetObjectType() == "EditBox" then return {} end
    return { type1 = "click", clickbutton1 = f }
end

-- (what the secure button is set to: changed out of combat only)
local set = {}
local function Aim(f)
    if InCombatLockdown() then return end
    local want = Wanted(f)
    for key, value in pairs(set) do
        if want[key] ~= value then use:SetAttribute(key, nil) end
    end
    for key, value in pairs(want) do
        if set[key] ~= value then use:SetAttribute(key, value) end
    end
    set = want
end

-- What A and X do besides the secure action: an edit box focused, an item
-- picked up or put down, an item sold
use:HookScript("OnClick", function(_, button, down)
    if down then return end
    local f = active and active.sel
    if not (f and f:IsVisible()) then return end
    if f:GetObjectType() == "EditBox" then
        if button == "LeftButton" then f:SetFocus() end
        return
    end
    local bag, slot = Slot(f)
    if not bag then return end
    if button == "LeftButton" then C_Container.PickupContainerItem(bag, slot)
    elseif Merchant() then C_Container.UseContainerItem(bag, slot) end
end)

local function Bind(on)
    if InCombatLockdown() then return end
    ClearOverrideBindings(binder)
    if not on then return end
    for key, mouse in pairs(BINDS) do SetOverrideBindingClick(binder, true, key, use:GetName(), mouse) end
end

local function Bound()
    for key in pairs(BINDS) do
        local ok, now = pcall(GetBindingAction, key, true)
        if not (ok and now == Action(key)) then return false end
    end
    return true
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

-- (x, y inside win on screen)
local function Inside(win, x, y)
    local l, b, w, h = win:GetRect()
    if not (l and x) then return false end
    local s = win:GetEffectiveScale()
    return x >= l * s and x <= (l + w) * s and y >= b * s and y <= (b + h) * s
end

-- What can be pressed: shown, under root (anywhere), or under win and inside
-- it on screen; not what the game's navigation skips (scroll bars)
local function Elements(win, root)
    local list = {}
    local function Walk(f)
        for _, child in ipairs({ f:GetChildren() }) do
            if child:IsShown() and not child.navigatorSkip and not child.smartNavigationIgnored then
                if Pressable(child) then
                    local x, y = Center(child)
                    if x and child:GetWidth() > 0 and (root or Inside(win, x, y)) then
                        list[#list + 1] = child
                    end
                else
                    Walk(child)
                end
            end
        end
    end
    Walk(root or win)
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

-- The legend's entries for what is chosen (one table each: the legend lays out each once)
local MOVE = { glyph = "DPAD", text = "Move" }
local SCROLL = { "PADRSTICK", "RS", "Scroll" }
local SEARCH = { "PADBACK", "BACK", "Search" }
local MORE = { "PAD4", "Y", "More" }
local LEGENDS = {}
local function Entries(scroll, a, x, b, search, more)
    local key = tostring(scroll) .. "|" .. a .. "|" .. (x or "") .. "|" .. b .. "|" .. tostring(search) .. "|" .. tostring(more)
    if not LEGENDS[key] then
        local defs = { MOVE }
        if scroll then defs[#defs + 1] = SCROLL end
        defs[#defs + 1] = { "PAD1", "A", a }
        if x then defs[#defs + 1] = { "PAD3", "X", x } end
        if more then defs[#defs + 1] = MORE end
        if search then defs[#defs + 1] = SEARCH end
        defs[#defs + 1] = { "PAD2", "B", b }
        LEGENDS[key] = defs
    end
    return LEGENDS[key]
end

-- (typing: an edit box of the window has the keyboard, B leaves it)
local function Legend(f, scroll, search, typing)
    local b = typing and "Back" or CursorHasItem() and "Put back" or "Close"
    search = search and not typing
    if not f then return Entries(scroll, "Select", nil, b, search) end
    if f:GetObjectType() == "EditBox" then return Entries(scroll, "Edit", nil, b, search) end
    if not Slot(f) then return Entries(scroll, "Select", nil, b, search) end
    local held = CursorHasItem()
    return Entries(scroll, held and "Place" or "Pick up", Merchant() and "Sell" or "Use", b, search, not (held or typing))
end

-- The scroll boxes under f (the game's ScrollBox, Baganator's lists and views)
local function Scrollers(f, list)
    list = list or {}
    for _, child in ipairs({ f:GetChildren() }) do
        if child.GetDerivedScrollRange and child.SetScrollPercentage then
            list[#list + 1] = child
        elseif not child.navigatorSkip then
            Scrollers(child, list)
        end
    end
    return list
end

local function Holds(box, f)
    while f do
        if f == box then return true end
        f = f:GetParent()
    end
    return false
end

local Nav = {}
Nav.__index = Nav

local function Hover(f, on)
    local script = f and f:GetScript(on and "OnEnter" or "OnLeave")
    if script then pcall(script, f) end
end

-- The box the right stick scrolls: the chosen element's, else the first that can
function Nav:Box()
    local first
    for _, box in ipairs(self.boxes or {}) do
        if box:IsVisible() and box:HasScrollableExtent() then
            if Holds(box, self.sel) then return box end
            first = first or box
        end
    end
    return first
end

function Nav:Scrolls()
    return self.on and self:Box() ~= nil
end

function Nav:Stick(stick, y)
    if stick == "Right" or stick == "Camera" then self.stickY = y or 0 end
end

-- As the game's right stick scrolls (SmartNavigation: its speed CVar, per second)
function Nav:Scroll(elapsed)
    local y = self.stickY or 0
    if math.abs(y) < 0.2 then return end
    local box = self:Box()
    if not box then return end
    local range = box:GetDerivedScrollRange()
    if range <= 0.01 then return end
    local speed = y * GetCVarNumberOrDefault("SmartNavigationScrollSpeed")
    box:SetScrollPercentage(Clamp((box:GetDerivedScrollOffset() - speed * elapsed) / range, 0, 1))
end

-- The window's search box, shown (Baganator's SearchWidget, the game's SearchBox), or nil
function Nav:SearchBox()
    local widget = self.win.SearchWidget
    local box = self.win.SearchBox or (widget and widget.SearchBox)
    return box and box:IsVisible() and box or nil
end

-- The edit box of the window that has the keyboard, or nil
function Nav:Typing()
    local focus = GetCurrentKeyBoardFocus()
    return focus and Holds(self.win, focus) and focus or nil
end

function Nav:MenuShown()
    return self.menu ~= nil and self.menu:IsShown()
end

-- The menu (IF.Dropdown) beside the chosen item, its own cursor and hint
-- meanwhile: ours and the item's tooltip hidden till it closes
function Nav:OpenMenu(build)
    if not self.menu then
        self.menu = IF.Dropdown(self.win)
        self.menu.frame.navigatorSkip = true
        self.menu.frame:SetFrameStrata("FULLSCREEN_DIALOG")
        self.menu.frame:SetClampedToScreen(true)
    end
    local f = self.sel
    Hover(f, false)
    self.cursor:Hide()
    self.held = nil
    self.menu.frame:ClearAllPoints()
    self.menu.frame:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
    self.menu:Open(build, { onClose = function()
        if self.on and self.sel then
            self.cursor:Point(self.sel)
            Hover(self.sel, true)
        end
    end })
    self:ShowLegend()
end

-- The item's menu: its name; junk or not (not a quest's item); KeepOrSell's keep mark (its /kos keep | unkeep,
-- KeepOrSellDB.keep: it has no Lua API); bind (an item that does something
-- when used); destroy (not locked)
function Nav:ItemEntries(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return {} end
    local id = info.itemID
    local list = { { kind = "title", text = info.hyperlink or "" } }
    local function Add(text, run, hold)
        list[#list + 1] = { kind = "action", text = text, run = run, hold = hold }
    end
    local judged = IF.ItemValue.Judge(bag, slot)
    if judged and judged.tag ~= "Quest" then
        -- (the Junk module's toggle says it in the chat)
        local toggle = IF.Junk and IF.Junk.Toggle or IF.ItemValue.Toggle
        Add(judged.verdict == "junk" and "Not junk" or "Mark as junk", function() toggle(bag, slot) end)
    end
    local db, kos = _G.KeepOrSellDB, SlashCmdList.KEEPORSELL
    if db and kos then
        local kept = db.keep and db.keep[id]
        Add(kept and "KeepOrSell: don't keep" or "KeepOrSell: keep", function() kos((kept and "unkeep " or "keep ") .. id) end)
    end
    local action = IF.Native.Available() and IF.BindPanel.ItemAction(id)
    if action then Add("Bind to action bar", function() IF.BindPanel.Open(action) end) end
    if not info.isLocked then
        list[#list + 1] = { kind = "divider" }
        Add("Destroy (hold " .. IF.GlyphText("A", 16) .. ")", function() IF.DestroyItem(bag, slot, id, true) end,
            (info.quality or 0) >= RARE and HOLD_RARE or HOLD)
    end
    return list
end

-- Y: the chosen item's menu, with nothing on the mouse, out of combat
function Nav:More()
    if not self.sel then return end
    local bag, slot = Slot(self.sel)
    if not bag or CursorHasItem() or InCombatLockdown() or self:Typing() then return end
    self:OpenMenu(function() return self:ItemEntries(bag, slot) end)
end

-- Beside the window, on the side toward the screen's centre, bottoms level
function Nav:ShowLegend()
    local defs = self.on and not self:MenuShown() and Legend(self.sel, self:Box() ~= nil, self:SearchBox() ~= nil, self:Typing() ~= nil) or nil
    if defs == self.legend.defs then return end
    self.legend:Set(defs)
    if not defs then return end
    self.legend:ClearAllPoints()
    local x = Center(self.win)
    local mid = UIParent:GetCenter() * UIParent:GetEffectiveScale()
    if x and x > mid then
        self.legend:SetPoint("BOTTOMRIGHT", self.win, "BOTTOMLEFT", -LEGEND_GAP, 0)
    else
        self.legend:SetPoint("BOTTOMLEFT", self.win, "BOTTOMRIGHT", LEGEND_GAP, 0)
    end
end

function Nav:Select(f)
    if f == self.sel then return end
    Hover(self.sel, false)
    self.sel = f
    if not f then
        self.cursor:Hide()
        Aim(nil)
        return self:ShowLegend()
    end
    self.x, self.y = Center(f)
    self.slotKey = table.concat({ Slot(f) }, " ")
    self.cursor:Point(f)
    Hover(f, true)
    Aim(f)
    self:ShowLegend()
end

function Nav:Set(on)
    on = on and not InCombatLockdown() or false
    if on == self.on then return end
    self.on = on
    self.held = nil
    if on then
        if active and active ~= self then active:Set(false) end
        active = self
        -- (a press still held from before, the bind panel's: its release kept from the window and the game)
        self.swallow = {}
        for _, key in ipairs(PRESSES) do
            if IsKeyDown(key) then self.swallow[key] = true end
        end
        self.boxes = Scrollers(self.root or self.win)
        local keep = self.last
        self:Select((keep and keep:IsVisible() and Pressable(keep) and keep) or First(Elements(self.win, self.root)))
        Bind(true)
        self:ShowLegend()
        self.driver:Show()
    else
        if self.menu then self.menu:Close() end
        -- (the one to come back to)
        self.last = self.sel
        self.stickY = nil
        self:Select(nil)
        self:ShowLegend()
        self.driver:Hide()
        if active == self then
            active = nil
            Bind(false)
        end
    end
end

function Nav:Move(button)
    local d = DIRS[button]
    local list = Elements(self.win, self.root)
    if not (self.sel and self.sel:IsVisible()) then return self:Select(First(list)) end
    local to = Step(list, self.sel, d[1], d[2])
    if to then self:Select(to) end
end

-- Select (PADBACK) and B as in the game's bag window: Select puts the
-- keyboard in the search box, Select again takes it out and the pad away
-- (onAway), B takes it out only
function Nav:Press(button, down)
    if not self.on then return false end
    -- (the menu's, and a release whose press was taken: nothing reaches the window or the game)
    if self:MenuShown() or (not down and self.swallow[button]) then
        self.swallow[button] = down or nil
        if MENU_KEYS[button] and self:MenuShown() then self.menu:Press(MENU_KEYS[button], down) end
        return true
    end
    if button == "PAD4" then
        if down then self:More() end
        return true
    end
    local typing = self:Typing()
    if button == "PADBACK" or (button == "PAD2" and typing) then
        if down then return true end
        if typing then typing:ClearFocus() end
        if button == "PADBACK" then
            if not typing and self:SearchBox() then self:SearchBox():SetFocus()
            elseif self.onAway then self.onAway() end
        end
        return true
    end
    if not DIRS[button] then return false end
    if down then
        self.held, self.next = button, GetTime() + REPEAT_DELAY
        self:Move(button)
    elseif self.held == button then
        self.held = nil
    end
    return true
end

-- (with nothing chosen, or the game's bindings over ours, A would reach the game's: kept)
function Nav:Passes(button)
    return self.on and BINDS[button] ~= nil and self.sel ~= nil and self.sel:IsVisible() and Bound()
        and not self:MenuShown() and not self.swallow[button] or false
end

-- Each frame while on: our bindings put back when the game's windows bound
-- theirs over them, the held direction repeated, the stick's scroll, the
-- chosen one kept (lost when the window lays itself out again or scrolls it
-- out: the nearest instead; the same button showing another item: hovered
-- again), the legend kept to it
local function Tick(self, elapsed)
    if not Bound() then Bind(true) end
    if self.held and GetTime() >= self.next then
        self.next = GetTime() + REPEAT_EVERY
        self:Move(self.held)
    end
    self:Scroll(elapsed)
    local f = self.sel
    if not (f and f:IsVisible() and Pressable(f) and (self.root or Inside(self.win, Center(f)))) then
        local list = Elements(self.win, self.root)
        self.sel = nil
        -- (the menu was for that one)
        if self.menu then self.menu:Close() end
        return self:Select((self.x and Nearest(list, self.x, self.y)) or First(list))
    end
    local key = table.concat({ Slot(f) }, " ")
    if key ~= self.slotKey then
        self.slotKey = key
        if self.menu then self.menu:Close() end
        Hover(f, true)
    end
    self.x, self.y = Center(f)
    Aim(f)
    self:ShowLegend()
end

function N.New(win, root)
    local nav = setmetatable({ win = win, root = root, on = false, swallow = {} }, Nav)
    nav.cursor = IF.Focus.Cursor(win)
    nav.cursor.navigatorSkip = true
    nav.cursor.window = win
    -- (over the window's own buttons, whatever their levels)
    nav.cursor:SetFrameStrata("FULLSCREEN_DIALOG")
    nav.legend = IF.InputLegend(win)
    nav.legend.navigatorSkip = true
    nav.legend.row.navigatorSkip = true
    nav.driver = CreateFrame("Frame")
    nav.driver:Hide()
    nav.legend.vertical = true
    nav.driver:SetScript("OnUpdate", function(_, elapsed) Tick(nav, elapsed) end)
    return nav
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    if active then active:Set(false) end
end)
