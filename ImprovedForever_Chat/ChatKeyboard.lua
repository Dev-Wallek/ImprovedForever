-- An on-screen keyboard for the chat, typed with the controller, laid out
-- like the PS5's: low in the middle of the screen on a soft dark band (as
-- Immersion's subtitles sit), the channel over the message, the message
-- centred (it grows out from the middle), the keys under them.
--
-- It opens anywhere, the chat's edit box not needed (the message is ours):
-- the hotkey LB + RB held, Cross (a binding, Bindings tab: Chat keyboard),
-- or, while the game's chat window has the pad (its edit box focused,
-- Forever's own gamepad chat: it has no keyboard of its own), D-pad Down.
--   D-pad: key to key     Cross: type the key    Square: delete
--   Triangle: space       LB / RB: cursor left / right in the message
--   LT / RT: channel back / forward (Say, Yell, Party, Raid, Guild, Whisper,
--   the numbered channels: General, Trade...)
--   Start: send   Circle: close, nothing sent   (Aa and #+= keys: shift, symbols)
-- The sticks are never taken (no EnableGamePadStick, no stick button): the
-- character walks and the camera turns as always.
-- The message is ours (the game's edit box is never written to); Start
-- sends it with SendChatMessage to the channel picked, then the keyboard
-- closes. Like ChatLines.lua: D-pad Down is watched (IsKeyDown), never
-- bound, nothing of ours goes into the game's chat window. Once open, a
-- catcher of ours takes the pad (the chat window keeps the game's focus),
-- the game's cursor and the chat's legend dimmed (IF.Focus).
local IF = ImprovedForever

local K = IF.ConfigKit
local F = IF.Focus

local CK = {}
IF.ChatKeyboard = CK

local OPEN_KEY = "PADDDOWN"
local REPEAT_DELAY, REPEAT_RATE = 0.4, 0.06
local KEY_W, KEY_H, GAP = 48, 32, 4
local COLS = 10
local PAD = 16
local BOTTOM_Y = 40
local WIDTH = COLS * (KEY_W + GAP) - GAP + PAD * 2
local TEXT_W = WIDTH - PAD * 2          -- (the message's room)
local SIDE_X, SIDE_COLS = 40, 6        -- (left / right: its margin, its keys a row)
-- (set by CK.Place: where it sits, bottom / left / right; its width, the message's)
local mode, side, boardW, textW = "bottom", false, WIDTH, TEXT_W
local MAX_BYTES = 255
local BAND_REACH, BAND_ALPHA = 80, 0.6
local FONT = STANDARD_TEXT_FONT
local TITLE_FONT = (K.FONT == STANDARD_TEXT_FONT) and FONT or "Fonts\\MORPHEUS.TTF"
local GOLD = { 1, 0.82, 0 }
local GREY = { 0.62, 0.62, 0.62 }
local LIT = { 0.55, 0.82, 1 }            -- (Immersion's: the one lit, light blue on a soft bar)
local DEFAULT_KEY = "PADLSHOULDER+PADRSHOULDER+PAD1"      -- (LB + RB held, Cross)
local DEFAULTS = { enabled = true, scale = 100, offsetX = 0, offsetY = 0, position = "bottom" }
CK.DEFAULTS = DEFAULTS

function CK.Settings()
    local db = IF.db
    db.chatKeyboard = db.chatKeyboard or {}
    local settings = db.chatKeyboard
    for key, value in pairs(DEFAULTS) do
        if settings[key] == nil then settings[key] = value end
    end
    return settings
end

---------------------------------------------------------------------------
-- The layers: rows of keys, a key = { text typed (nil: an action), label,
-- action, width in keys }; the last row is the same in each
---------------------------------------------------------------------------
local function Row(chars)
    local row = {}
    for c in chars:gmatch(".") do row[#row + 1] = { c } end
    return row
end

local LAYERS = {
    lower = { Row("1234567890"), Row("qwertyuiop"), Row("asdfghjkl'"), Row("zxcvbnm,.?") },
    upper = { Row("1234567890"), Row("QWERTYUIOP"), Row("ASDFGHJKL\""), Row("ZXCVBNM;:!") },
    symbols = { Row("1234567890"), Row("@#$%&*()-+"), Row("/\\=_[]{}<>"), Row("~^|`:;!?.,") },
}
local LAST_ROW = {
    { action = "shift", label = "Aa", w = 1.5 },
    { action = "symbols", label = "#+=", w = 1.5 },
    { "/", w = 1 },
    { " ", label = "space", w = 3 },
    { action = "back", label = "Del", w = 1.5 },
    { action = "send", label = "Send", w = 1.5 },
}

local SIDE_ACTIONS = {
    {
        { action = "shift", label = "Aa", w = 2 }, { action = "symbols", label = "#+=", w = 2 },
        { action = "back", label = "Del", w = 2 },
    },
    { { " ", label = "space", w = 4 }, { action = "send", label = "Send", w = 2 } },
}

local function RowsOf(layer)
    if side then
        -- (left / right: the letters in rows of SIDE_COLS, the actions under them)
        local rows, row = {}, {}
        for _, r in ipairs(LAYERS[layer]) do
            for _, key in ipairs(r) do
                row[#row + 1] = key
                if #row == SIDE_COLS then rows[#rows + 1], row = row, {} end
            end
        end
        if #row > 0 then rows[#rows + 1] = row end
        for _, r in ipairs(SIDE_ACTIONS) do rows[#rows + 1] = r end
        return rows
    end
    local rows = {}
    for i, r in ipairs(LAYERS[layer]) do rows[i] = r end
    rows[#rows + 1] = LAST_ROW
    return rows
end

---------------------------------------------------------------------------
-- The frames: a band low in the middle, the channel, the message, the keys
-- (built once, each layer sets their text), the legend
---------------------------------------------------------------------------
local board = K.NewFrame("Frame", "ImprovedForeverChatKeyboard", UIParent)
board:SetFrameStrata("DIALOG")
board:EnableMouse(false)
board:Hide()

local CHANNEL_H, INPUT_H, LEGEND_H = 28, 40, 34
local KEYS_H = 5 * (KEY_H + GAP) - GAP
local HEIGHT = PAD + CHANNEL_H + INPUT_H + 10 + KEYS_H + 10 + LEGEND_H + PAD / 2
board:SetSize(WIDTH, HEIGHT)
board:SetClampedToScreen(true)

-- (the band: dark in the middle, fading out to its sides, as Immersion's)
local band = CreateFrame("Frame", nil, board)
band:SetPoint("TOPLEFT", -BAND_REACH, 24)
band:SetPoint("BOTTOMRIGHT", BAND_REACH, -8)
band:SetFrameLevel(math.max(0, board:GetFrameLevel() - 1))
local function BandPart(a, b, gradient)
    local t = band:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetPoint(unpack(a))
    t:SetPoint(unpack(b))
    if gradient and t.SetGradient and CreateColor then
        t:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, gradient[1]), CreateColor(0, 0, 0, gradient[2]))
    else
        t:SetVertexColor(0, 0, 0, BAND_ALPHA)
    end
end
BandPart({ "TOPLEFT", band, "TOPLEFT", BAND_REACH, 0 }, { "BOTTOMRIGHT", band, "BOTTOMRIGHT", -BAND_REACH, 0 })
BandPart({ "TOPLEFT", band, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", band, "BOTTOMLEFT", BAND_REACH, 0 }, { 0, BAND_ALPHA })
BandPart({ "TOPRIGHT", band, "TOPRIGHT", 0, 0 }, { "BOTTOMLEFT", band, "BOTTOMRIGHT", -BAND_REACH, 0 }, { BAND_ALPHA, 0 })

local function Text(parent, font, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if not fs:SetFont(font, size, "") then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

-- The channel: its name in its colour, the arrows (LT / RT) either side
local channelText = Text(board, TITLE_FONT, 20, GOLD[1], GOLD[2], GOLD[3])
channelText:SetPoint("TOP", board, "TOP", 0, -PAD)
channelText:SetHeight(CHANNEL_H)
local arrowL = Text(board, FONT, 18, GREY[1], GREY[2], GREY[3])
arrowL:SetPoint("RIGHT", channelText, "LEFT", -14, 0)
arrowL:SetText("<")
local arrowR = Text(board, FONT, 18, GREY[1], GREY[2], GREY[3])
arrowR:SetPoint("LEFT", channelText, "RIGHT", 14, 0)
arrowR:SetText(">")

-- The message: centred; the caret between the letters; clipped to the
-- band's width (a long one slides so the caret stays in view)
local input = CreateFrame("Frame", nil, board)
input:SetPoint("TOP", channelText, "BOTTOM", 0, -2)
input:SetSize(TEXT_W, INPUT_H)
input:SetClipsChildren(true)
local rule = input:CreateTexture(nil, "ARTWORK")
rule:SetColorTexture(1, 1, 1, 0.18)
rule:SetPoint("BOTTOMLEFT", 0, 0)
rule:SetPoint("BOTTOMRIGHT", 0, 0)
rule:SetHeight(1)
local message = Text(input, FONT, 22)
message:SetWordWrap(false)
message:SetNonSpaceWrap(false)
local hint = Text(input, FONT, 18, GREY[1], GREY[2], GREY[3])
hint:SetPoint("CENTER", input, "CENTER", 0, 2)
hint:SetText("Type a message")
local caret = input:CreateTexture(nil, "OVERLAY")
caret:SetColorTexture(LIT[1], LIT[2], LIT[3], 1)
caret:SetSize(2, 26)
-- (the width of a text, measured: a font string of the same font)
local measure = Text(board, FONT, 22)
measure:SetWordWrap(false)
measure:Hide()

local keysFrame = CreateFrame("Frame", nil, board)
keysFrame:SetPoint("TOP", input, "BOTTOM", 0, -10)
keysFrame:SetSize(WIDTH - PAD * 2, KEYS_H)

local legend = IF.InputLegend(board)
legend:ClearAllPoints()
legend:SetPoint("BOTTOM", board, "BOTTOM", 0, PAD / 2)
local legend2 = IF.InputLegend(board)     -- (left / right: the prompts in two rows)
local PROMPTS = {
    { glyph = "DPAD", text = "Keys" },
    { "PAD1", "A", "Type" },
    { "PAD3", "X", "Delete" },
    { "PAD4", "Y", "Space" },
    { { "PADLSHOULDER", "PADRSHOULDER" }, { "LB", "RB" }, "Cursor" },
    { { "PADLTRIGGER", "PADRTRIGGER" }, { "LT", "RT" }, "Channel" },
    { "PADFORWARD", "START", "Send" },
    { "PAD2", "B", "Close" },
}

local PROMPTS_A = { PROMPTS[1], PROMPTS[2], PROMPTS[3], PROMPTS[4] }
local PROMPTS_B = { PROMPTS[5], PROMPTS[6], PROMPTS[7], PROMPTS[8] }
local function SetLegends()
    if side then
        legend:Set(PROMPTS_A)
        legend2:Set(PROMPTS_B)
    else
        legend:Set(PROMPTS)
        legend2:Hide()
    end
end

local buttons = {}      -- the key frames, reused
local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Frame", nil, keysFrame)
    b.text = Text(b, FONT, 18)
    b.text:SetPoint("CENTER")
    -- (the one lit: a soft light bar, fading out at its ends, as Immersion's rows)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 1)
    if b.hl.SetGradient and CreateColor then
        b.hl:SetGradient("HORIZONTAL", CreateColor(LIT[1], LIT[2], LIT[3], 0.05), CreateColor(LIT[1], LIT[2], LIT[3], 0.2))
    else
        b.hl:SetVertexColor(LIT[1], LIT[2], LIT[3], 0.15)
    end
    b.hl:Hide()
    buttons[i] = b
    return b
end

---------------------------------------------------------------------------
-- Slash commands: every one the game and the addons registered (SLASH_<NAME>n
-- with SlashCmdList[NAME], emotes by EMOTEn_CMDm / EMOTEn_TOKEN), read from
-- the globals when the keyboard opens. Typed as "/xx" they are offered in a
-- strip over the keyboard (D-pad Up from the top row, Left / Right, Cross).
---------------------------------------------------------------------------
local commands, commandList   -- ["/reload"] = { list = NAME } or { emote = TOKEN }; the names, sorted
local function BuildCommands()
    commands, commandList = {}, {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "string" and v:sub(1, 1) == "/" then
            local name = k:match("^SLASH_(.-)%d+$")
            if name and _G.SlashCmdList and _G.SlashCmdList[name] then
                commands[v:lower()] = { list = name }
            else
                local n = k:match("^EMOTE(%d+)_CMD%d+$")
                local token = n and _G["EMOTE" .. n .. "_TOKEN"]
                if type(token) == "string" then commands[v:lower()] = { emote = token } end
            end
        end
    end
    for cmd in pairs(commands) do commandList[#commandList + 1] = cmd end
    table.sort(commandList, function(a, b)
        if #a ~= #b then return #a < #b end
        return a < b
    end)
end

-- Runs a typed "/command rest", as the game's chat would. False: unknown.
local function RunCommand(text)
    if not commands then BuildCommands() end
    local cmd, rest = text:match("^(/%S+)%s*(.-)%s*$")
    local info = cmd and commands[cmd:lower()]
    if not info then return false end
    if info.list then
        local box = _G.ChatFrame1 and _G.ChatFrame1.editBox
        local ok, err = pcall(_G.SlashCmdList[info.list], rest, box)
        if not ok then geterrorhandler()(err) end
    else
        pcall(_G.DoEmote, info.emote, rest ~= "" and rest or nil)
    end
    return true
end

local SUGGEST_MAX = 6
local matches, sugSel = {}, nil     -- the commands offered, the one lit (nil: the keys have the pad)
local sug = CreateFrame("Frame", nil, board)
sug:SetPoint("BOTTOM", board, "TOP", 0, 12)
sug:SetSize(WIDTH, 28)
sug:Hide()
local sugText = {}
local function SuggestRender()
    for i = 1, SUGGEST_MAX do
        local fs = sugText[i]
        if not fs then
            fs = Text(sug, FONT, 18)
            sugText[i] = fs
        end
        fs:SetShown(matches[i] ~= nil)
    end
    if #matches == 0 then sug:Hide() return end
    sug:Show()
    local total, gap = 0, 22
    for i, cmd in ipairs(matches) do
        sugText[i]:SetText(cmd)
        total = total + sugText[i]:GetStringWidth() + (i > 1 and gap or 0)
    end
    local x = (boardW - total) / 2
    -- (left / right: one under the other, the board being narrow)
    sug:SetHeight(side and #matches * 24 or 28)
    for i = 1, #matches do
        local fs = sugText[i]
        fs:ClearAllPoints()
        if side then
            fs:SetPoint("TOP", sug, "TOP", 0, -(i - 1) * 24)
        else
            fs:SetPoint("LEFT", sug, "LEFT", x, 0)
        end
        x = x + fs:GetStringWidth() + gap
        if i == sugSel then fs:SetTextColor(LIT[1], LIT[2], LIT[3]) else fs:SetTextColor(1, 1, 1) end
    end
end

---------------------------------------------------------------------------
-- State: the message (its characters, the caret after the nth), the
-- channel, the layer, the key picked
---------------------------------------------------------------------------
local chat                      -- the game's chat window it was opened from (nil: opened by the hotkey)
local last                      -- the channel last sent to ({ type, target }), this session
local chars, caretAt, bytes = {}, 0, 0
local channels, channelIndex = {}, 1
local layer = "lower"
local rows, grid = {}, {}
local cx, cy = 1, 2
local held, nextRepeat
local previewing, previewUntil   -- (shown for the config's sliders: no pad taken, nothing sent)

-- The colour of a chat type, the game's own
local function TypeColor(kind)
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo[kind]
    if info and info.r then return info.r, info.g, info.b end
    return 1, 1, 1
end

-- The channels there are to send to now: { type, label, target / channel number }
local function Channels(from)
    local list = {
        -- (Global: no message; each key goes to the game as the keyboard key, to fire its binding)
        { type = "GLOBAL", label = "Global" },
        { type = "SAY", label = _G.SAY or "Say" },
        { type = "YELL", label = _G.YELL or "Yell" },
    }
    if IsInGroup and IsInGroup() then list[#list + 1] = { type = "PARTY", label = _G.PARTY or "Party" } end
    if IsInRaid and IsInRaid() then list[#list + 1] = { type = "RAID", label = _G.RAID or "Raid" } end
    if IsInGuild and IsInGuild() then list[#list + 1] = { type = "GUILD", label = _G.GUILD or "Guild" } end
    -- (a whisper: the one the chat is on, the last one you spoke with, the target if a player)
    local who = from and from.editBox and from.editBox:GetAttribute("chatType") == "WHISPER"
        and from.editBox:GetAttribute("tellTarget")
    if type(who) ~= "string" or who == "" then
        local ok, last = pcall(function() return _G.ChatEdit_GetLastTellTarget and _G.ChatEdit_GetLastTellTarget() end)
        who = ok and type(last) == "string" and last ~= "" and last or nil
    end
    if not who and UnitExists and UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
        who = UnitName("target")
    end
    if who then list[#list + 1] = { type = "WHISPER", label = (_G.WHISPER or "Whisper") .. ": " .. who, target = who } end
    -- (the numbered channels: GetChannelList's id, name, disabled)
    if GetChannelList then
        local info = { GetChannelList() }
        for i = 1, #info, 3 do
            local id, name, disabled = info[i], info[i + 1], info[i + 2]
            if type(id) == "number" and type(name) == "string" and not disabled then
                list[#list + 1] = { type = "CHANNEL", label = id .. ". " .. name, target = id }
            end
        end
    end
    return list
end

-- The channel the chat is on, to start from
local function StartIndex(from, list)
    if not from and last then
        for i, c in ipairs(list) do
            if c.type == last.type and c.target == last.target then return i end
        end
    end
    local box = from and from.editBox
    local kind = box and box:GetAttribute("chatType")
    if kind == "CHANNEL" then
        local n = box:GetAttribute("channelTarget")
        for i, c in ipairs(list) do if c.type == "CHANNEL" and c.target == n then return i end end
    elseif kind then
        for i, c in ipairs(list) do if c.type == kind then return i end end
    end
    return 2   -- (Say: Global is the one before it, picked by LT)
end

local function Joined() return table.concat(chars) end

local global = false   -- the Global channel picked: keys go to the game

local HINT = "Type a message"
local function ChannelRender()
    local c = channels[channelIndex]
    if not c then return end
    global = c.type == "GLOBAL"
    hint:SetText(global and "Global: each key goes to the game" or HINT)
    local r, g, b = TypeColor(c.type)
    channelText:SetText(c.label)
    channelText:SetTextColor(r, g, b)
    arrowL:SetShown(#channels > 1)
    arrowR:SetShown(#channels > 1)
end

local function Blink()
    caret:SetAlpha((GetTime() % 1) < 0.55 and 1 or 0.15)
end

-- The message in the middle, the caret after the nth character
local Suggest
local function MessageRender()
    local full = Joined()
    Suggest(full)
    hint:SetShown(#chars == 0)
    message:SetText(full)
    measure:SetText(table.concat(chars, "", 1, caretAt))
    local left = (#chars > 0 and caretAt > 0) and measure:GetStringWidth() or 0
    measure:SetText(full)
    local total = #chars > 0 and measure:GetStringWidth() or 0
    message:ClearAllPoints()
    caret:ClearAllPoints()
    if total <= textW then
        -- (centred: grows out from the middle)
        message:SetPoint("CENTER", input, "CENTER", 0, 2)
        caret:SetPoint("LEFT", input, "CENTER", -total / 2 + left, 2)
    else
        -- (too long: the caret held in the middle, the message slides)
        message:SetPoint("LEFT", input, "CENTER", -left, 2)
        caret:SetPoint("CENTER", input, "CENTER", 0, 2)
    end
    Blink()
end

local function KeysRender()
    for r, row in ipairs(grid) do
        for c, b in ipairs(row) do
            local on = not sugSel and r == cy and c == cx
            local key = b.key
            local color = on and LIT or (key.action == "send" and GOLD) or (key.action and GREY) or { 1, 1, 1 }
            b.text:SetTextColor(color[1], color[2], color[3])
            b.hl:SetShown(on)
        end
    end
end

-- The commands starting with the word typed (the first, while it has no space yet)
function Suggest(full)
    local old = matches
    matches = {}
    if full:sub(1, 1) == "/" and not full:find("%s") then
        if not commands then BuildCommands() end
        local low = full:lower()
        for _, cmd in ipairs(commandList) do
            if cmd:sub(1, #low) == low and cmd ~= low then
                matches[#matches + 1] = cmd
                if #matches >= SUGGEST_MAX then break end
            end
        end
    end
    if #matches == 0 or #matches ~= #old then sugSel = nil end
    SuggestRender()
    KeysRender()
end

local function Layout()
    rows = RowsOf(layer)
    grid = {}
    local used = 0
    for r, row in ipairs(rows) do
        grid[r] = {}
        -- (a row centred under the message)
        local rowW = -GAP
        for _, key in ipairs(row) do rowW = rowW + (key.w or 1) * KEY_W + ((key.w or 1) - 1) * GAP + GAP end
        local x = (keysFrame:GetWidth() - rowW) / 2
        for c, key in ipairs(row) do
            used = used + 1
            local b = Button(used)
            local w = (key.w or 1) * KEY_W + ((key.w or 1) - 1) * GAP
            b:SetSize(w, KEY_H)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", keysFrame, "TOPLEFT", x, -((r - 1) * (KEY_H + GAP)))
            b.text:SetText(key.label or key[1])
            b.key = key
            b:Show()
            grid[r][c] = b
            x = x + w + GAP
        end
    end
    for i = used + 1, #buttons do buttons[i]:Hide() end
    if cy > #rows then cy = #rows end
    if cx > #rows[cy] then cx = #rows[cy] end
    KeysRender()
end

local function SetLayer(name)
    layer = name
    Layout()
end

---------------------------------------------------------------------------
-- Opening, closing
---------------------------------------------------------------------------
local function NativeLegend(window)
    local footer = window and window.footer
    local l = type(footer) == "table" and footer.inputLegend
    return l and l.GetObjectType and l or nil
end

local function Close()
    if not board:IsShown() then return end
    board:Hide()
    legend:Hide()
    legend2:Hide()
    if board.EnableGamePadButton then pcall(board.EnableGamePadButton, board, false) end
    F.DimNative(board, false)
    F.Fade(NativeLegend(chat), false)
    chat, held, previewing = nil, nil, nil
end
CK.Close = Close

function CK.IsOpen() return board:IsShown() and not previewing end

function CK.Open(window)
    if IF.InCombat() then return end
    CK.Place()
    chat, held, cx, cy = window, nil, 1, 2
    chars, caretAt, bytes, layer = {}, 0, 0, "lower"
    commands, sugSel = nil, nil
    channels = Channels(window)
    channelIndex = StartIndex(window, channels)
    board:Show()
    Layout()
    ChannelRender()
    MessageRender()
    SetLegends()
    if board.EnableGamePadButton then board:EnableGamePadButton(true) end
    F.DimNative(board, true)
    F.Fade(NativeLegend(window), true)
    if IF.Vibe then IF.Vibe.Play("pulse") end
end

---------------------------------------------------------------------------
-- Typing
---------------------------------------------------------------------------
-- (a text split into its characters, UTF-8)
local function Split(text)
    local out = {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

local function Insert(text)
    for _, ch in ipairs(Split(text)) do
        if bytes + #ch > MAX_BYTES then break end
        caretAt = caretAt + 1
        table.insert(chars, caretAt, ch)
        bytes = bytes + #ch
    end
    if layer == "upper" and text:match("%a") then SetLayer("lower") end
    MessageRender()
end

local function Delete()
    if caretAt == 0 then return end
    bytes = bytes - #table.remove(chars, caretAt)
    caretAt = caretAt - 1
    MessageRender()
end

-- The command picked: the typed word replaced by it, a space after
local function Complete(i)
    local cmd = matches[i]
    if not cmd then return end
    chars = Split(cmd .. " ")
    caretAt, bytes, sugSel = #chars, #cmd + 1, nil
    MessageRender()
end

local function MoveCaret(step)
    local to = caretAt + step
    if to < 0 or to > #chars then return end
    caretAt = to
    MessageRender()
end

local function Channel(step)
    if #channels < 2 then return end
    channelIndex = (channelIndex - 1 + step) % #channels + 1
    ChannelRender()
    if IF.Vibe then IF.Vibe.Play("pulse") end
end

-- Global: a key of the keyboard goes to the game as the keyboard's key: its binding runs (down, then up),
-- so the hotkeys of the keyboard work from the pad. A binding the game keeps to itself (the action bar's,
-- protected) is not run.
local SHIFTED = {
    ["?"] = "SHIFT-/", ["!"] = "SHIFT-1", ["@"] = "SHIFT-2", ["#"] = "SHIFT-3", ["$"] = "SHIFT-4",
    ["%"] = "SHIFT-5", ["^"] = "SHIFT-6", ["&"] = "SHIFT-7", ["*"] = "SHIFT-8", ["("] = "SHIFT-9",
    [")"] = "SHIFT-0", ["_"] = "SHIFT--", ["+"] = "SHIFT-=", [":"] = "SHIFT-;", ['"'] = "SHIFT-'",
    ["<"] = "SHIFT-,", [">"] = "SHIFT-.", ["{"] = "SHIFT-[", ["}"] = "SHIFT-]", ["|"] = "SHIFT-\\",
    ["~"] = "SHIFT-`",
}
local NAMED = { [" "] = "SPACE", back = "BACKSPACE", send = "ENTER" }
-- (the bindings of the game's protected functions: run from addon code the game blocks them, with a
-- "forbidden UNKNOWN()" from us: the nameplates (V), the action bars, targeting, attack, macros, spells,
-- items, clicks on a button, movement)
local PROTECTED = { "ACTIONBUTTON", "MULTIACTIONBAR", "SHAPESHIFTBUTTON", "BONUSACTIONBUTTON", "EXTRAACTIONBUTTON",
    "PETACTION", "CLICK", "MACRO", "SPELL", "ITEM", "TARGET", "ASSIST", "ATTACK", "STARTATTACK", "STOPATTACK",
    "FOCUS", "FOLLOW", "INTERACT", "NAMEPLATES", "FRIENDNAMEPLATES", "ALLNAMEPLATES", "MOVE", "STRAFE", "TURN",
    "JUMP", "SITORSTAND", "TOGGLERUN", "TOGGLEAUTORUN", "PITCH", "DISMOUNT", "STOPCASTING", "USE", "EQUIP" }
local function Protected(action)
    for _, prefix in ipairs(PROTECTED) do
        if action:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- The nameplate toggles done by their CVars (what the game's binding does; out of combat, as the
-- keyboard is): the enemies' (V), the friends' (Ctrl-V), both (Shift-V)
local PLATES = { NAMEPLATES = { "nameplateShowEnemies" }, FRIENDNAMEPLATES = { "nameplateShowFriends" },
    ALLNAMEPLATES = { "nameplateShowEnemies", "nameplateShowFriends" } }
local function TogglePlates(cvars)
    local on = true
    for _, c in ipairs(cvars) do
        if GetCVar(c) ~= "1" then on = false end
    end
    for _, c in ipairs(cvars) do pcall(SetCVar, c, on and "0" or "1") end
end

local function FireKey(name)
    if not name then return end
    local ok, action = pcall(GetBindingAction, name, true)
    action = ok and action or ""
    if PLATES[action] and not IF.InCombat() then
        TogglePlates(PLATES[action])
        if IF.Vibe then IF.Vibe.Play("pulse") end
        hint:SetText(name .. "  >  " .. action)
        return
    end
    if action ~= "" and Protected(action) then
        hint:SetText(name .. "  >  " .. action .. " (kept by the game)")
        return
    end
    if action ~= "" then
        pcall(RunBinding, action)
        pcall(RunBinding, action, "up")
        if IF.Vibe then IF.Vibe.Play("pulse") end
    end
    hint:SetText(name .. (action ~= "" and ("  >  " .. action) or "  >  (not bound)"))
end

local function GlobalKey(key)
    local text = key[1]
    if not text then return key.action and NAMED[key.action] end
    if NAMED[text] then return NAMED[text] end
    if SHIFTED[text] then return SHIFTED[text] end
    if text:match("%u") then return "SHIFT-" .. text end
    return text:upper()
end

local function Send()
    if global then return end
    local text = Joined():gsub("^%s+", ""):gsub("%s+$", "")
    local c = channels[channelIndex]
    if text == "" or not c then return end
    -- (a slash command runs, whatever the channel)
    if text:sub(1, 1) == "/" and RunCommand(text) then
        if IF.Vibe then IF.Vibe.Play("pulse") end
        return Close()
    end
    last = { type = c.type, target = c.target }
    -- (the game's own call; its edit box is not used)
    if c.type == "WHISPER" or c.type == "CHANNEL" then
        SendChatMessage(text, c.type, nil, c.target)
    else
        SendChatMessage(text, c.type)
    end
    if IF.Vibe then IF.Vibe.Play("pulse") end
    Close()
end

local function Act(key)
    if global and key.action ~= "shift" and key.action ~= "symbols" then
        FireKey(GlobalKey(key))
        if layer == "upper" then SetLayer("lower") end
    elseif key[1] then
        Insert(key[1])
    elseif key.action == "shift" then
        SetLayer(layer == "lower" and "upper" or "lower")
    elseif key.action == "symbols" then
        SetLayer(layer == "symbols" and "lower" or "symbols")
    elseif key.action == "back" then
        Delete()
    elseif key.action == "send" then
        Send()
    end
end

local function Move(dx, dy)
    if sugSel then
        -- (in the strip: Left / Right pick, Down gives the keys the pad back)
        if dy > 0 then sugSel = nil
        elseif dx ~= 0 then sugSel = (sugSel - 1 + dx) % #matches + 1 end
        SuggestRender()
        KeysRender()
        return
    end
    if dy < 0 and cy == 1 and #matches > 0 then
        sugSel = 1
        SuggestRender()
        KeysRender()
        return
    end
    if dy ~= 0 then
        local to = cy + dy
        if to < 1 or to > #rows then return end
        -- (the key above / below nearest to this one's middle)
        local mid = grid[cy][cx]:GetCenter()
        local best, bestDist = 1, math.huge
        for c, b in ipairs(grid[to]) do
            local d = math.abs((b:GetCenter() or 0) - (mid or 0))
            if d < bestDist then best, bestDist = c, d end
        end
        cy, cx = to, best
    else
        local n = #rows[cy]
        cx = (cx - 1 + dx) % n + 1
    end
    KeysRender()
end

local function Press(button)
    if button == "PADDUP" then Move(0, -1)
    elseif button == "PADDDOWN" then Move(0, 1)
    elseif button == "PADDLEFT" then Move(-1, 0)
    elseif button == "PADDRIGHT" then Move(1, 0)
    elseif button == "PAD1" then
        if sugSel then Complete(sugSel) else Act(rows[cy][cx]) end
    elseif button == "PAD3" then if global then FireKey("BACKSPACE") else Delete() end
    elseif button == "PAD4" then if global then FireKey("SPACE") else Insert(" ") end
    elseif button == "PADLSHOULDER" then MoveCaret(-1)
    elseif button == "PADRSHOULDER" then MoveCaret(1)
    elseif button == "PADLTRIGGER" then Channel(-1)
    elseif button == "PADRTRIGGER" then Channel(1)
    elseif button == "PADFORWARD" then Send()
    end
end

local REPEATS = {
    PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true,
    PAD3 = true, PADLSHOULDER = true, PADRSHOULDER = true,
}

if board.EnableGamePadButton then
    board:SetScript("OnGamePadButtonDown", function(_, button)
        if REPEATS[button] then held, nextRepeat = button, GetTime() + REPEAT_DELAY end
        Press(button)
    end)
    board:SetScript("OnGamePadButtonUp", function(_, button)
        if button == held then held = nil end
        -- (Circle closes on its release: else the release goes to the chat)
        if button == "PAD2" then Close() end
    end)
    -- (setting a gamepad handler switches the frame's input on by itself:
    -- off until it is wanted)
    board:EnableGamePadButton(false)
end

board:SetScript("OnUpdate", function()
    -- (a preview: as long as the config is up and a slider was touched a moment ago)
    if previewing then
        if GetTime() > previewUntil or (IF.Menu and not IF.Menu.IsOpen()) then return Close() end
        return Blink()
    end
    -- Gone from under us: the chat closed, lost the pad, or combat (or the
    -- mouse taken up)
    -- (opened from the chat: while it has the pad; by the hotkey: anywhere)
    if (chat and IF.ChatLines.FocusedChat() ~= chat) or IF.InCombat() or not IF.Input.Pad() then return Close() end
    if held and IsKeyDown and IsKeyDown(held) and GetTime() >= nextRepeat then
        nextRepeat = GetTime() + REPEAT_RATE
        Press(held)
    end
    Blink()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", Close)

---------------------------------------------------------------------------
-- D-pad Down watched while the chat has the pad
---------------------------------------------------------------------------
local wasDown, shown = false, false
local watch = CreateFrame("Frame")
watch:SetScript("OnUpdate", function()
    if not IF.db then return end
    local CL = IF.ChatLines
    local window = not board:IsShown() and not (CL and CL.IsOpen()) and not IF.InCombat()
        and CK.Settings().enabled and IF.Input.Pad() and CL and CL.FocusedChat()
    local down = IsKeyDown and IsKeyDown(OPEN_KEY) or false
    -- (a press counts if the chat had the pad just before it)
    if window and down and not wasDown and shown then
        wasDown, shown = down, false
        return CK.Open(window)
    end
    wasDown = down
    shown = window and true or false
end)

---------------------------------------------------------------------------
-- Its hotkey (the Bindings tab): buttons held and one pressed, watched, not
-- taken over (the buttons keep their own actions too); and a keyboard key
-- (Binds.lua). Opens it anywhere the game has the pad, the chat or not.
---------------------------------------------------------------------------
function CK.Key()
    if not IF.db then return nil end
    local key = CK.Settings().openKey
    if key == nil then return DEFAULT_KEY end
    return key or nil
end

local function Toggle()
    if previewing then Close() elseif board:IsShown() then return Close() end
    local CL = IF.ChatLines
    if not CK.Settings().enabled or IF.InCombat() or (CL and CL.IsOpen()) then return end
    CK.Open(nil)
end

local keyDown = false
local keyWatch = CreateFrame("Frame")
keyWatch:SetScript("OnUpdate", function()
    local key = CK.Key()
    -- (only while the game has the gamepad's focus, Binds.lua; the pad in hand)
    if not key or not IsKeyDown or not IF.Input.Pad() or (IF.Menu and IF.Menu.IsOpen()) or not IF.Binds.InGame() then
        keyDown = false
        return
    end
    local held, pressed = IF.Binds.Parse(key)
    local down = IsKeyDown(pressed) and true or false
    if down then
        for _, k in ipairs(IF.Binds.HeldList(held)) do
            if not IsKeyDown(k) then down = false break end
        end
    end
    -- (the moment the combination is made)
    if down and not keyDown and not board:IsShown() then Toggle() end
    keyDown = down
end)

IF.Binds.Add({
    id = "chatkeyboard", label = "Chat keyboard", group = "Other", tab = "chat",
    icon = IF.TEX .. "ic_mod_chat", context = "world", order = 38,
    desc = "Opens the chat keyboard",
    tip = "Opens the on-screen keyboard anywhere, the chat's edit box not needed: type a message, pick its "
        .. "channel (LT / RT), Start sends it. Watched only: the buttons keep their own actions too (Cross "
        .. "still jumps), so pick a combination you don't mind.",
    accepts = IF.Binds.NotDouble,
    specs = function() return IF.Binds.One(CK.Key()) end,
    set = function(spec) CK.Settings().openKey = spec or false end,
    reset = function() CK.Settings().openKey = nil end,
    run = function(down) if down then Toggle() end end,
})

-- The keyboard shown for the config's sliders, with a sample message, for a
-- few seconds after the last touch (the pad is not taken, nothing is sent)
function CK.Preview()
    CK.Place()
    if board:IsShown() and not previewing then return end         -- (really open: it moved)
    if IF.InCombat() then return end
    if not previewing then
        chat, held, cx, cy, layer = nil, nil, 1, 2, "lower"
        chars, caretAt, bytes = Split("Hello Azeroth"), 13, 13
        commands, sugSel = nil, nil
        channels = Channels(nil)
        channelIndex = 1
        previewing = true
        board:Show()
        Layout()
        ChannelRender()
        MessageRender()
        SetLegends()
    end
    previewUntil = GetTime() + 4
end

-- Its place and layout (the Chat tab): bottom (middle), left or right of the
-- screen; the scale in percent; the offsets in screen pixels from there,
-- whatever the scale (up from the bottom, or from the middle on a side)
function CK.Place()
    local st = IF.db and CK.Settings() or DEFAULTS
    mode = st.position == "left" and "left" or st.position == "right" and "right" or "bottom"
    side = mode ~= "bottom"
    local cols = side and SIDE_COLS or COLS
    boardW = cols * (KEY_W + GAP) - GAP + PAD * 2
    textW = boardW - PAD * 2
    local keysH = (side and 9 or 5) * (KEY_H + GAP) - GAP
    board:SetSize(boardW, PAD + CHANNEL_H + INPUT_H + 10 + keysH + 10 + (side and LEGEND_H * 2 + 4 or LEGEND_H) + PAD / 2)
    input:SetSize(textW, INPUT_H)
    keysFrame:SetSize(boardW - PAD * 2, keysH)
    sug:SetSize(boardW, 28)
    legend:ClearAllPoints()
    legend2:ClearAllPoints()
    if side then
        legend2:SetPoint("BOTTOM", board, "BOTTOM", 0, PAD / 2)
        legend:SetPoint("BOTTOM", legend2, "TOP", 0, 4)
    else
        legend:SetPoint("BOTTOM", board, "BOTTOM", 0, PAD / 2)
    end
    local scale = math.max(0.3, (st.scale or 100) / 100)
    local ox, oy = st.offsetX or 0, st.offsetY or 0
    board:SetScale(scale)
    board:ClearAllPoints()
    if mode == "left" then
        board:SetPoint("LEFT", UIParent, "LEFT", (SIDE_X + ox) / scale, oy / scale)
    elseif mode == "right" then
        board:SetPoint("RIGHT", UIParent, "RIGHT", (-SIDE_X + ox) / scale, oy / scale)
    else
        board:SetPoint("BOTTOM", UIParent, "BOTTOM", ox / scale, (BOTTOM_Y + oy) / scale)
    end
    if board:IsShown() then
        Layout()
        SetLegends()
        MessageRender()
        SuggestRender()
    end
end
CK.Place()
IF.OnLogin(CK.Place)
