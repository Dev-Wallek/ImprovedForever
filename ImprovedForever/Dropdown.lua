-- A dropdown of choices over a window of ours, as the auction window's
-- filters (AuctionBuyClassic.lua) and Improved Quest Tracker's: the game's own
-- Menu look (its background, titles, radio and check ticks, dividers), a
-- hint along its bottom. Its sections in columns when they don't fit one.
-- The window it's in passes the pad's presses on (menu:Press: the D-pad
-- moves, Cross picks, Circle / L3 close); the mouse clicks a choice.
--   menu = IF.Dropdown(parent, { maxHeight })
--   menu:Open(build, { onClose }): build() -> entries, asked again after
--     each pick (a choice may bring others): { kind = "title", text },
--     { kind = "radio" | "checkbox", text, selected, select(), key (the
--     focus kept on it as entries change) },
--     { kind = "action", text, run(), hold (seconds: Cross held that long,
--     then let go) }: the menu closes, then run() (which may open another),
--     { kind = "divider" }
--   menu:Press(name, down) -> true: taken (down nil: a press with no
--     release to come, which no hold entry takes);  menu:Close();  menu:IsShown()
-- Placed by the caller (menu.frame). Never in combat.
local IF = ImprovedForever

local K = IF.ConfigKit

local ROW, INSET, COL_GAP, DIVIDER = 20, { left = 8, top = 8, right = 8, bottom = 15 }, 22, 13
local HINT_H = 16

local function Atlas(tex, name)
    if IF.HasAtlas(name) then
        tex:SetAtlas(name)
        return true
    end
end

local function Selectable(e)
    return e and (e.kind == "radio" or e.kind == "checkbox" or e.kind == "action")
end

local function Sound()
    if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
end

function IF.Dropdown(parent, opts)
    opts = opts or {}
    local menu = { entries = {}, focus = nil }
    local maxHeight = opts.maxHeight or 460

    local f = K.NewFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 30)
    f:EnableMouse(true)
    f:Hide()
    menu.frame = f
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    if not Atlas(bg, "common-dropdown-bg") then bg:SetColorTexture(0.05, 0.04, 0.03, 0.95) end
    bg:SetPoint("TOPLEFT", -10, 3)
    bg:SetPoint("BOTTOMRIGHT", 10, -3)
    bg:SetAlpha(0.925)
    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", INSET.left, 6)
    hint:SetJustifyH("LEFT")
    -- (the game's cursor left of the choice the pad is on: Focus.lua)
    local cursor = IF.Focus.Cursor(f)

    -- Rows made as they're needed: a title, a choice (its tick, its words),
    -- a divider
    local rows = {}
    local function Row(i)
        local row = rows[i]
        if row then return row end
        row = K.NewFrame("Button", nil, f)
        row:SetHeight(ROW)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetBlendMode("ADD")
        row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.highlight:Hide()
        -- (a hold under way: filling as the Destroy panel's cards do)
        row.fill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.fill:SetPoint("TOPLEFT")
        row.fill:SetPoint("BOTTOMLEFT")
        row.fill:Hide()
        row.divider = row:CreateTexture(nil, "ARTWORK")
        row.divider:SetPoint("LEFT")
        row.divider:SetPoint("RIGHT")
        row.divider:SetHeight(DIVIDER)
        row.divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
        row.radio = row:CreateTexture(nil, "ARTWORK")
        if not Atlas(row.radio, "common-dropdown-tickradial") then row.radio:SetColorTexture(0.3, 0.3, 0.3, 0.8) end
        row.radio:SetSize(16, 16)
        row.radio:SetPoint("LEFT", -3, 0)
        row.square = row:CreateTexture(nil, "ARTWORK")
        if not Atlas(row.square, "common-dropdown-ticksquare") then row.square:SetColorTexture(0.3, 0.3, 0.3, 0.8) end
        row.square:SetSize(16, 16)
        row.square:SetPoint("LEFT", 0, 0)
        row.radioCheck = row:CreateTexture(nil, "OVERLAY")
        if not Atlas(row.radioCheck, "common-dropdown-icon-radialtick-yellow") then row.radioCheck:SetColorTexture(1, 0.82, 0, 1) end
        row.radioCheck:SetSize(16, 16)
        row.radioCheck:SetPoint("TOPLEFT", row.radio, "TOPLEFT")
        row.squareCheck = row:CreateTexture(nil, "OVERLAY")
        if not Atlas(row.squareCheck, "common-dropdown-icon-checkmark-yellow") then row.squareCheck:SetColorTexture(1, 0.82, 0, 1) end
        row.squareCheck:SetSize(14, 14)
        row.squareCheck:SetPoint("CENTER", row.square, "CENTER", 2, 1)
        row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.title:SetPoint("LEFT")
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            local e = self.index and menu.entries[self.index]
            if Selectable(e) and not e.hold then
                menu.focus = self.index
                menu:Pick()
            end
        end)
        -- (a hold entry: the mouse button held as Cross is)
        row:SetScript("OnMouseDown", function(self)
            local e = self.index and menu.entries[self.index]
            if Selectable(e) and e.hold then
                menu.focus = self.index
                menu:Press("A", true)
            end
        end)
        row:SetScript("OnMouseUp", function(self)
            local e = self.index and menu.entries[self.index]
            if Selectable(e) and e.hold then menu:Press("A", false) end
        end)
        row:SetScript("OnEnter", function(self)
            if self.index and Selectable(menu.entries[self.index]) and not IF.Input.Pad() then
                menu.focus = self.index
                menu:Render()
            end
        end)
        rows[i] = row
        return row
    end

    -- A row's look for its entry; its width
    local function Fill(row, e)
        local choice = Selectable(e)
        local radio = e.kind == "radio"
        local action = e.kind == "action"
        local tick = choice and not action
        row:SetHeight(e.kind == "divider" and DIVIDER or ROW)
        row.divider:SetShown(e.kind == "divider")
        row.title:SetShown(e.kind == "title")
        row.title:SetText(e.kind == "title" and e.text or "")
        row.radio:SetShown(radio)
        row.square:SetShown(tick and not radio)
        row.radioCheck:SetShown(radio and e.selected and true or false)
        row.squareCheck:SetShown(tick and not radio and e.selected and true or false)
        row.text:SetShown(choice)
        row:EnableMouse(choice and true or false)
        if not choice then
            return e.kind == "title" and row.title:GetStringWidth() or 0
        end
        row.text:ClearAllPoints()
        row.text:SetText(e.text or "")
        if action then
            row.text:SetPoint("LEFT", 0, 0)
            return row.text:GetStringWidth()
        end
        row.text:SetPoint("LEFT", radio and row.radio or row.square, "RIGHT", radio and 1 or 7, radio and 0 or 1)
        return 16 + 7 + row.text:GetStringWidth()
    end

    -- Laid out: a column filled down to maxHeight, the next begun at a
    -- section's title (a section taller than that: broken where it must)
    local function Layout()
        local entries = menu.entries
        local cols, col = {}, nil
        local function newCol()
            col = { rows = {}, width = 0, height = 0 }
            cols[#cols + 1] = col
        end
        newCol()
        -- (a section's height: its title to the next one)
        local function sectionHeight(i)
            local h = 0
            for j = i, #entries do
                if j > i and entries[j].kind == "title" then break end
                h = h + (entries[j].kind == "divider" and DIVIDER or ROW)
            end
            return h
        end
        for i, e in ipairs(entries) do
            local h = e.kind == "divider" and DIVIDER or ROW
            local starts = e.kind == "title" and col.height > 0 and col.height + sectionHeight(i) > maxHeight
            local full = col.height > 0 and col.height + h > maxHeight
            if starts or full then
                -- (a divider ending a column: left out)
                local last = col.rows[#col.rows]
                if last and last.entry.kind == "divider" then
                    col.height = col.height - DIVIDER
                    table.remove(col.rows)
                    last.row:Hide()
                end
                newCol()
            end
            if not (e.kind == "divider" and col.height == 0) then
                local row = Row(i)
                row.index, row.entry = i, e
                local w = Fill(row, e)
                col.rows[#col.rows + 1] = { row = row, entry = e, y = col.height, index = i }
                col.width = math.max(col.width, w)
                col.height = col.height + h
                row:Show()
            else
                Row(i):Hide()
            end
        end
        for i = #entries + 1, #rows do rows[i]:Hide() end
        local x, height = INSET.left, 0
        for c, column in ipairs(cols) do
            column.x = x
            for _, r in ipairs(column.rows) do
                r.row:ClearAllPoints()
                r.row:SetPoint("TOPLEFT", f, "TOPLEFT", x, -INSET.top - r.y)
                r.row:SetWidth(column.width + 4)
                r.col = c
            end
            x = x + column.width + 4 + COL_GAP
            height = math.max(height, column.height)
        end
        menu.cols = cols
        local width = x - COL_GAP + INSET.right
        f:SetSize(math.max(width, hint:GetStringWidth() + INSET.left + INSET.right),
            height + INSET.top + INSET.bottom + HINT_H)
    end

    -- Where each choice is: { col, y } by entry index
    local function Places()
        local at = {}
        for c, column in ipairs(menu.cols or {}) do
            for _, r in ipairs(column.rows) do at[r.index] = { col = c, y = r.y } end
        end
        return at
    end

    function menu:Render()
        if not f:IsShown() then return end
        hint:SetText(IF.Input.Pad()
            and (IF.GlyphText("DPAD", 16) .. " Move   " .. IF.GlyphText("A", 16) .. " Select   "
                .. IF.GlyphText("B", 16) .. " Close")
            or "Click to tick  ·  Done closes")
        Layout()
        cursor:Hide()
        for i, row in ipairs(rows) do
            local on = i == self.focus and row:IsShown() and Selectable(self.entries[i])
            row.highlight:SetShown(on and true or false)
            if on and IF.Input.Pad() then cursor:Point(row) end
        end
    end

    -- The entries again (after a pick), the focus kept on its key
    local function Rebuild()
        local key = menu.focus and menu.entries[menu.focus] and menu.entries[menu.focus].key
        menu.entries = menu.build() or {}
        local found
        if key ~= nil then
            for i, e in ipairs(menu.entries) do
                if Selectable(e) and e.key == key then found = i break end
            end
        end
        if not found then
            for i, e in ipairs(menu.entries) do
                if Selectable(e) then found = i break end
            end
        end
        menu.focus = found
    end

    -- A hold entry's row filling till full; Hold(i): the hold on entry i
    -- begun (nil: none)
    local function ShowHold()
        local e = menu.holdStart and menu.entries[menu.holdIndex]
        for i, row in ipairs(rows) do
            local p = e and i == menu.holdIndex and math.min(1, (GetTime() - menu.holdStart) / e.hold)
            row.fill:SetShown(p and true or false)
            if p then
                row.fill:SetWidth(math.max(1, row:GetWidth() * p))
                -- (full: brighter, let go now)
                row.fill:SetColorTexture(p >= 1 and 1 or 0.85, p >= 1 and 0.35 or 0.2, 0.1, p >= 1 and 0.6 or 0.45)
            end
        end
    end
    local function Hold(i)
        menu.holdIndex, menu.holdStart = i, i and GetTime() or nil
        ShowHold()
    end
    f:SetScript("OnUpdate", function()
        if menu.holdStart then ShowHold() end
    end)

    function menu:Open(build, how)
        self.build, self.how = build, how or {}
        self.focus = nil
        Hold(nil)
        f:Show()
        Rebuild()
        Sound()
        self:Render()
    end

    function menu:Close()
        if not f:IsShown() then return end
        Hold(nil)
        f:Hide()
        local onClose = self.how and self.how.onClose
        self.how = nil
        if onClose then onClose() end
    end

    function menu:IsShown() return f:IsShown() end

    -- The focused choice picked: its select(), the entries again; an
    -- action: the menu closed, then its run()
    function menu:Pick()
        local e = self.entries[self.focus or 0]
        if not Selectable(e) then return end
        if e.kind == "action" then
            Sound()
            self:Close()
            return e.run()
        end
        if e.select then e.select() end
        Sound()
        Rebuild()
        self:Render()
    end

    -- Up / down: the next choice (wrapping); left / right: the nearest in
    -- the column beside
    local function Move(name)
        local entries = menu.entries
        local n = #entries
        if name == "UP" or name == "DOWN" then
            local step = name == "UP" and -1 or 1
            local i = menu.focus or 0
            for _ = 1, n do
                i = i + step
                if i < 1 then i = n elseif i > n then i = 1 end
                if Selectable(entries[i]) then
                    menu.focus = i
                    return
                end
            end
            return
        end
        local at = Places()
        local here = at[menu.focus or 0]
        if not here then return end
        local want = here.col + (name == "RIGHT" and 1 or -1)
        local best, dist
        for i, p in pairs(at) do
            if p.col == want and Selectable(entries[i]) then
                local d = math.abs(p.y - here.y)
                if not dist or d < dist then best, dist = i, d end
            end
        end
        if best then menu.focus = best end
    end

    function menu:Press(name, down)
        if not f:IsShown() then return false end
        -- (a release: a hold entry run once full, nothing else)
        if down == false then
            if name ~= "A" then return true end
            local e = self.holdStart and self.focus == self.holdIndex and self.entries[self.focus]
            local full = e and GetTime() - self.holdStart >= e.hold
            Hold(nil)
            if full then self:Pick() end
            return true
        end
        if name == "UP" or name == "DOWN" or name == "LEFT" or name == "RIGHT" then
            Hold(nil)
            Move(name)
            self:Render()
        elseif name == "A" then
            local e = self.entries[self.focus or 0]
            if not (e and e.hold) then self:Pick()
            elseif down then Hold(self.focus) end
        elseif name == "B" or name == "LS" then
            self:Close()
        end
        return true
    end

    f:SetScript("OnHide", function() cursor:Hide() end)
    IF.Input.OnChange(function() menu:Render() end)
    return menu
end
