-- The Bags & Bank window: the portrait frame of the game's windows, the
-- picked character's bags or bank (side tabs, L1 / R1) as the game's bags
-- lay them out, a thin heading over each bag, every slot with its icon,
-- count and quality border. Drawn from ImprovedForeverBagsDB alone (Record.lua),
-- again whenever it's written. The pad: the D-pad over the slots (the
-- game's tooltip at the one it's on), Y the characters, R3 an item's Wiki
-- page, B closes, L2 / R2 to the game's windows beside it. The mouse: the
-- same tooltips, the wheel scrolls, a click on the portrait the
-- characters, the middle button the Wiki. A fight starting closes it,
-- unless it was opened in one (then it stays, the mouse's only: our pad
-- catcher is never switched on in a fight).
local IF = ImprovedForever
local BG = IF.Bags
local K = IF.ConfigKit

local COLS, SLOT, GAP, HEAD = 10, 37, 4, 22
local PAD_X, TOP, BOTTOM = 14, 64, 34
local W = 2 * PAD_X + COLS * SLOT + (COLS - 1) * GAP
local TABS = {
    { key = "bags", label = "Bags", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
    { key = "bank", label = "Bank", icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue" },
}

local view = { tab = 1, sel = 1, focus = "ours" }

local ok, win = pcall(K.NewFrame, "Frame", "ImprovedForeverBagsWindow", UIParent, "PortraitFrameTemplate")
if not ok then win = K.NewFrame("Frame", "ImprovedForeverBagsWindow", UIParent) end
win:SetSize(W, 400)
win:SetFrameStrata("HIGH")
win:SetPoint("CENTER")
win:EnableMouse(true)
win:SetClampedToScreen(true)
win:Hide()
if win.CloseButton then win.CloseButton:SetScript("OnClick", function() win:Hide() end) end

local bg = win:CreateTexture(nil, "BACKGROUND", nil, 1)
bg:SetPoint("TOPLEFT", 2, -22)
bg:SetPoint("BOTTOMRIGHT", -2, 2)
bg:SetColorTexture(0.05, 0.04, 0.03, 0.92)

local footer = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
footer:SetPoint("BOTTOMLEFT", PAD_X, 12)
local seen = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
seen:SetPoint("BOTTOMRIGHT", -PAD_X, 12)
local empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("TOP", win, "TOP", 0, -TOP - 20)
empty:SetWidth(W - 40)

local scroll = CreateFrame("ScrollFrame", nil, win)
scroll:SetPoint("TOPLEFT", PAD_X, -TOP)
scroll:SetPoint("BOTTOMRIGHT", -PAD_X, BOTTOM)
if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(W - 2 * PAD_X, 1)
scroll:SetScrollChild(content)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = math.max(0, content:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 60)))
end)

local cursor = IF.Focus.Cursor(win)
local legend = IF.InputLegend(win)
legend:SetPoint("TOP", win, "BOTTOM", 0, -4)
local dropdown = IF.Dropdown(win, { maxHeight = 360 })
dropdown.frame:SetPoint("TOPLEFT", win, "TOPLEFT", 60, -40)

---------------------------------------------------------------------------
-- The pieces: headings and slots, made as they're needed
---------------------------------------------------------------------------
local heads, slots = {}, {}

local function Head(i)
    local h = heads[i]
    if h then return h end
    h = CreateFrame("Frame", nil, content)
    h:SetSize(W - 2 * PAD_X, HEAD)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(16, 16)
    h.icon:SetPoint("LEFT")
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.text:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
    heads[i] = h
    return h
end

local function Tip(b)
    if not b.itemID then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(b.link or ("item:" .. b.itemID))
    GameTooltip:Show()
end

local function Wiki(itemID)
    local wiki = IF.Wiki
    if itemID and wiki and wiki.Open then wiki.Open(itemID, "ui") end
end

local function Slot(i)
    local b = slots[i]
    if b then return b end
    b = CreateFrame("Button", nil, content)
    b:SetSize(SLOT, SLOT)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    if not pcall(b.bg.SetAtlas, b.bg, "bags-item-slot64") or not b.bg:GetAtlas() then
        b.bg:SetColorTexture(0.12, 0.1, 0.08, 1)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetAllPoints()
    b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:RegisterForClicks("MiddleButtonUp")
    b:SetScript("OnClick", function(self) Wiki(self.itemID) end)
    b:SetScript("OnEnter", Tip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slots[i] = b
    return b
end

local function Fill(b, s)
    local id, count, link
    if s then id, count, link = BG.Unslot(s) end
    b.itemID, b.link = id, link
    b.icon:SetTexture(id and C_Item.GetItemIconByID(id) or nil)
    b.count:SetText(count and count > 1 and count or "")
    local q = id and C_Item.GetItemQualityByID(id)
    local c = q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    b.border:SetShown(c ~= nil and c ~= false)
    if c then b.border:SetVertexColor(c.r, c.g, c.b) end
end

local function BagName(item, i)
    local fallback = (view.tab == 1 and "Bag " or "Tab ") .. i
    if not item then return i == 1 and view.tab == 1 and (_G.BACKPACK_TOOLTIP or "Backpack") or fallback end
    return C_Item.GetItemNameByID(item) or fallback
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Ago(at)
    if not at then return "never" end
    local s = math.max(0, time() - at)
    if s < 120 then return "now" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " days ago"
end

local switch
function view:Render()
    if not win:IsShown() then return end
    local chars = BG.Chars()
    self.key = chars[self.key] and self.key or BG.Me()
    local c = chars[self.key] or {}
    local tab = TABS[self.tab]
    local mine = self.key == BG.Me()
    pcall(function()
        win:SetTitle((c.name or self.key) .. " - " .. tab.label)
        if mine then win:SetPortraitToUnit("player")
        else win:SetPortraitToAsset("Interface\\Icons\\ClassIcon_" .. (c.class or "WARRIOR"):lower()) end
    end)
    self.tabs:Render(TABS, tab.key)
    footer:SetText(c.money and GetMoneyString(c.money, true) or "")
    seen:SetText("Seen " .. Ago(tab.key == "bags" and c.bagsAt or c.bankAt))
    local containers = c[tab.key]
    empty:SetText(containers and "" or (tab.key == "bank" and "Bank not seen yet: open the bank once with this character"
        or "Not seen yet"))
    -- (headings and slots, line by line; cells: the slots in order, each
    -- with its line and column for the D-pad)
    local y, line, nh, ns = 0, 0, 0, 0
    self.cells = {}
    for i, bag in ipairs(containers or {}) do
        nh = nh + 1
        local h = Head(nh)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        h.icon:SetTexture(bag.item and C_Item.GetItemIconByID(bag.item) or "Interface\\Icons\\INV_Misc_Bag_08")
        h.text:SetText(BagName(bag.item, i) .. "  |cff9d917a" .. bag.size .. "|r")
        h:Show()
        y = y + HEAD
        for slot = 1, bag.size do
            local col = (slot - 1) % COLS
            if slot > 1 and col == 0 then y = y + SLOT + GAP end
            if col == 0 then line = line + 1 end
            ns = ns + 1
            local b = Slot(ns)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", content, "TOPLEFT", col * (SLOT + GAP), -y)
            Fill(b, bag.slots[slot])
            b:Show()
            self.cells[ns] = { b = b, line = line, col = col, y = y }
        end
        y = y + SLOT + GAP + 4
    end
    for i = nh + 1, #heads do heads[i]:Hide() end
    for i = ns + 1, #slots do slots[i]:Hide() end
    content:SetHeight(math.max(1, y))
    win:SetHeight(math.max(260, math.min(UIParent:GetHeight() * 0.8, y + TOP + BOTTOM)))
    -- (the pad: its cursor and the game's tooltip on the picked slot, its prompts)
    local focused = self.focus ~= "window" and not self.away
    local pad = IF.Input.Pad()
    IF.Focus.Glow(win, focused and pad)
    self.sel = math.max(1, math.min(self.sel, #self.cells))
    local cell = focused and pad and not dropdown:IsShown() and self.cells[self.sel]
    if cell then
        cursor:Point(cell.b)
        Tip(cell.b)
    else
        cursor:Hide()
    end
    if focused and pad then
        local defs = { { glyph = "DPAD_UD", text = "Choose" }, { { "PADLSHOULDER", "PADRSHOULDER" }, { "LB", "RB" }, "Bags / Bank" },
            { "PAD4", "Y", "Character" } }
        if IF.Wiki and cell and cell.b.itemID then defs[#defs + 1] = { "PADRSTICK", "RS", "Wiki" } end
        local hint = switch and switch:Hint()
        if hint then defs[#defs + 1] = hint end
        defs[#defs + 1] = { "PADBACK", "BACK", "Background" }
        defs[#defs + 1] = { "PAD2", "B", "Close" }
        legend:Set(defs)
    else
        legend:Set(nil)
    end
end

view.tabs = IF.UI.SideTabs(win, function(key)
    for i, t in ipairs(TABS) do
        if t.key == key then view:SetTab(i) end
    end
end, { keys = { "LB", "RB" } })

function view:SetTab(i)
    self.tab, self.sel = i, 1
    scroll:SetVerticalScroll(0)
    GameTooltip:Hide()
    self:Render()
end

-- (the picked slot in view)
local function ScrollTo()
    local cell = view.cells and view.cells[view.sel]
    if not cell then return end
    local at, h = scroll:GetVerticalScroll(), scroll:GetHeight()
    if cell.y < at + HEAD then scroll:SetVerticalScroll(math.max(0, cell.y - HEAD))
    elseif cell.y + SLOT > at + h then scroll:SetVerticalScroll(cell.y + SLOT - h) end
end

-- The characters: own first, then by name
local function CharEntries()
    local chars, me, list = BG.Chars(), BG.Me(), {}
    local keys = {}
    for key in pairs(chars) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if a == me or b == me then return a == me end
        return a < b
    end)
    list[1] = { kind = "title", text = "Character" }
    for _, key in ipairs(keys) do
        local c = chars[key]
        local color = RAID_CLASS_COLORS and c.class and RAID_CLASS_COLORS[c.class]
        local name = color and ("|c" .. color.colorStr .. (c.name or key) .. "|r") or (c.name or key)
        list[#list + 1] = { kind = "radio", key = key, selected = key == view.key,
            text = name .. "  |cff9d917a" .. (c.level or "?") .. "  " .. (c.money and GetMoneyString(c.money, true) or "") .. "|r",
            select = function()
                view.key, view.sel = key, 1
                dropdown:Close()
            end }
    end
    return list
end

function view:Characters()
    if dropdown:IsShown() then return dropdown:Close() end
    if IF.InCombat() then return end
    GameTooltip:Hide()
    dropdown:Open(CharEntries, { onClose = function() view:Render() end })
    self:Render()
end

local picker = CreateFrame("Button", nil, win)
picker:SetSize(60, 60)
picker:SetPoint("TOPLEFT", -6, 7)
picker:SetScript("OnClick", function() view:Characters() end)

---------------------------------------------------------------------------
-- The pad
---------------------------------------------------------------------------
local KEYS = { PADDUP = "UP", PADDDOWN = "DOWN", PADDLEFT = "LEFT", PADDRIGHT = "RIGHT", PAD1 = "A", PAD2 = "B",
    PAD4 = "Y", PADLSHOULDER = "LB", PADRSHOULDER = "RB", PADLTRIGGER = "LT", PADRTRIGGER = "RT", PADRSTICK = "RS",
    PADBACK = "BACK" }

-- The slot one line up or down: the nearest column there
local function Vertical(dir)
    local cells, from = view.cells, view.cells[view.sel]
    if not from then return end
    local best
    for i, c in ipairs(cells) do
        if c.line == from.line + dir and (not best or math.abs(c.col - from.col) < math.abs(cells[best].col - from.col)) then
            best = i
        end
    end
    if best then view.sel = best end
end

local function Press(name, down)
    if dropdown:IsShown() then
        if down == (name ~= "B") then dropdown:Press(name) end
        return view:Render()
    end
    if name == "B" then
        if not down then win:Hide() end
        return
    end
    if not down then return end
    local n = #(view.cells or {})
    if name == "UP" then Vertical(-1)
    elseif name == "DOWN" then Vertical(1)
    elseif name == "LEFT" then view.sel = math.max(1, view.sel - 1)
    elseif name == "RIGHT" then view.sel = math.min(n, view.sel + 1)
    elseif name == "LB" or name == "RB" then
        return view:SetTab((view.tab - 1 + (name == "RB" and 1 or -1)) % #TABS + 1)
    elseif name == "LT" or name == "RT" then return switch:Press(name)
    elseif name == "Y" then return view:Characters()
    elseif name == "BACK" then return view:Away()
    elseif name == "RS" then
        local cell = view.cells and view.cells[view.sel]
        return Wiki(cell and cell.b.itemID)
    end
    view:Render()
    ScrollTo()
end

local catcher = K.NewFrame("Frame", nil, win)
catcher:SetAllPoints(win)
if catcher.EnableGamePadButton then
    catcher:SetScript("OnGamePadButtonDown", function(_, button) if KEYS[button] then Press(KEYS[button], true) end end)
    catcher:SetScript("OnGamePadButtonUp", function(_, button) if KEYS[button] then Press(KEYS[button], false) end end)
    -- (setting the handler switches its input on: off until wanted)
    catcher:EnableGamePadButton(false)
end
legend:SetPress(catcher)

-- A pad button pressed and let go, as the catcher gets them (tools/loadcheck.lua)
function BG.Press(button)
    if not KEYS[button] then return end
    Press(KEYS[button], true)
    Press(KEYS[button], false)
end

local function TakePad(on)
    if catcher.EnableGamePadButton and not IF.InCombat() then catcher:EnableGamePadButton(on and true or false) end
end

-- (Esc: closed, on its release)
local escape = K.NewFrame("Button", "ImprovedForeverBagsEscape")
escape:RegisterForClicks("AnyUp")
escape:SetScript("OnClick", function()
    if dropdown:IsShown() then return dropdown:Close() end
    win:Hide()
end)
local function BindEscape(on)
    if IF.InCombat() then return end
    ClearOverrideBindings(win)
    if on then SetOverrideBindingClick(win, true, "ESCAPE", escape:GetName()) end
end

IF.Focus.Dock(win)

switch = IF.Focus.Switch(win, {
    onChange = function(focus)
        local ours = focus == "ours"
        view.focus = ours and "ours" or "window"
        TakePad(ours)
        BindEscape(ours)
        IF.Focus.DimNative(win, ours)
        view:Render()
    end,
})

-- Select: the pad let go as the game's TOGGLEUIFOCUS does, the window
-- left open behind. With a game window beside it the switch hands it there
-- (L2 / R2 back); else it's the character's until Select again. Meanwhile
-- a do-nothing button of ours takes PADBACK while no window of the game's
-- is shown (its TOGGLEUIFOCUS would only say there's none to focus),
-- unless another addon's click is on it.
local hush = CreateFrame("Button", "ImprovedForeverBagsSelect")
local HUSH = "CLICK " .. hush:GetName() .. ":LeftButton"
local hushOwner = CreateFrame("Frame")
local function Hush(on)
    if on == (view.hush or false) or IF.InCombat() then return end
    view.hush = on
    if on then SetOverrideBindingClick(hushOwner, true, "PADBACK", hush:GetName())
    else ClearOverrideBindings(hushOwner) end
end

function view:Away()
    if switch:Other() then return switch:Set("game") end
    self.away, self.selectHeld = true, true
    TakePad(false)
    BindEscape(false)
    IF.Focus.DimNative(win, false)
    GameTooltip:Hide()
    self:Render()
end

local function Back()
    view.away = false
    Hush(false)
    TakePad(true)
    BindEscape(true)
    IF.Focus.DimNative(win, true)
    view:Render()
end

win:SetScript("OnUpdate", function()
    if not view.away then return switch:Update() end
    local m = IF.Focus.Manager()
    local down = IsKeyDown("PADBACK")
    local fresh = down and not view.selectHeld and not view.gameFocus
    view.selectHeld = down
    view.gameFocus = m and m.isUIFocused or false
    local now = GetBindingAction("PADBACK", true)
    local taken = now and now:find("^CLICK ") and now ~= HUSH
    Hush(m ~= nil and not m.isUIFocused and #(m.shownFrames or {}) == 0 and not taken)
    if fresh then Back() end
end)
IF.Input.OnChange(function() view:Render() end)
BG.OnChange(function() view:Render() end)

win:SetScript("OnHide", function()
    view.away = false
    Hush(false)
    view.focus, switch.focus = "ours", "ours"
    TakePad(false)
    IF.Focus.DimNative(win, false)
    cursor:Hide()
    dropdown:Close()
    GameTooltip:Hide()
    if not IF.InCombat() then ClearOverrideBindings(win) end
    PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE or 863)
end)

local openedInFight = false
win:RegisterEvent("PLAYER_REGEN_DISABLED")
win:RegisterEvent("PLAYER_REGEN_ENABLED")
win:RegisterEvent("GET_ITEM_INFO_RECEIVED")
win:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if not openedInFight then win:Hide() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- (opened in the fight: the pad's now)
        if openedInFight and win:IsShown() then
            openedInFight = false
            TakePad(view.focus == "ours")
            BindEscape(view.focus == "ours")
        end
    elseif not view.queued then
        -- (items' names and qualities coming: drawn again once, a moment later)
        view.queued = true
        C_Timer.After(0.3, function()
            view.queued = false
            view:Render()
        end)
    end
end)

function BG.Open()
    openedInFight = IF.InCombat()
    view.tab, view.sel, view.focus, view.key = 1, 1, "ours", BG.Me()
    switch:Take()
    if not win:IsShown() then PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN or 862) end
    win:Show()
    TakePad(true)
    BindEscape(true)
    IF.Focus.DimNative(win, true)
    scroll:SetVerticalScroll(0)
    view:Render()
end

function BG.Toggle()
    if win:IsShown() then return win:Hide() end
    BG.Open()
end

-- A button beside the game's bags, the way here from them: outside their
-- top left corner, shown with them, clicked with the mouse; with the pad L3
-- while they have the game's focus (watched, never taken: their own
-- buttons are the face ones, Select and the shoulders). Ours, never a child
-- of theirs, so the game's pad navigation in them stays its own.
local opener = CreateFrame("Button", nil, UIParent)
opener:SetSize(32, 32)
opener:SetFrameStrata("HIGH")
opener:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_08")
opener:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
opener:SetScript("OnClick", function() BG.Toggle() end)
opener:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Bags & Bank")
    GameTooltip:AddLine("Your bank and your other characters' bags", 1, 1, 1)
    GameTooltip:Show()
end)
opener:SetScript("OnLeave", function() GameTooltip:Hide() end)
opener.glyph = opener:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
opener.glyph:SetPoint("TOP", opener, "BOTTOM", 0, -2)
opener:Hide()
local combined = _G.ContainerFrameCombinedBags
local l3Held = false
opener:SetScript("OnUpdate", function()
    opener.glyph:SetText(IF.Input.Pad() and IF.GlyphText("PADLSTICK", 20) or "")
    local down = IsKeyDown("PADLSTICK")
    local m = IF.Focus.Manager()
    if down and not l3Held and m and m.isUIFocused and m.focusedFrame == combined and not IF.InCombat() then
        BG.Toggle()
    end
    l3Held = down
end)
if combined then
    opener:SetPoint("TOPRIGHT", combined, "TOPLEFT", -4, -40)
    combined:HookScript("OnShow", function() opener:Show() end)
    combined:HookScript("OnHide", function() opener:Hide() end)
end

-- (its button: a wheel's slot, a press, a corner opens it: Actions.lua)
IF.Actions.PressButton("ImprovedForeverBagsToggle", function() BG.Toggle() end)
IF.AddCommand("bags", function() BG.Toggle() end, ": your bags and bank, and your other characters'")
