-- Improved Forever: Panel. A slim bar of small displays (experience,
-- money), each a block of its own (P.Add, a file each), at an edge, in a
-- corner or under the minimap (its tab: PanelEditor.lua). Only frames of
-- ours, nothing of the game's moved; a block's text is set again on its
-- own events alone, nothing runs on a timer.
local IF = ImprovedForever

IF.AddModule({ key = "panel", label = "Panel", icon = IF.TEX .. "ic_mod_panel", addon = ... })

local P = {}
IF.Panel = P

local DEFAULTS = {
    place = "top",    -- top, bottom (a bar across); left, right (a strip down); TOPLEFT... (a corner); minimap (under it)
    hidden = {},      -- block key -> true: not shown
    order = {},       -- block keys, first first (blocks added later after them)
    session = false,  -- money: this session's gain beside it
}

function P.Settings()
    IF.db.panel = IF.db.panel or {}
    local s = IF.db.panel
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = type(v) == "table" and {} or v end
    end
    return s
end

local BAR_H, ROW_H, GAP, PAD = 20, 18, 20, 8

local bar = CreateFrame("Frame", nil, UIParent)
bar:SetFrameStrata("LOW")
bar:Hide()
local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.55)

local blocks, byEvent = {}, {}
local events = CreateFrame("Frame")

-- def: { key, label, events = { event... }, text = fn() -> its line (nil:
-- nothing to show now, false: kept as it is), tip = fn(tooltip) }
function P.Add(def)
    local b = CreateFrame("Frame", nil, bar)
    b:SetHeight(ROW_H)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT")
    b.def = def
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        if not def.tip then return end
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        def.tip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    blocks[#blocks + 1] = b
    for _, event in ipairs(def.events) do
        if not byEvent[event] then
            byEvent[event] = {}
            events:RegisterEvent(event)
        end
        table.insert(byEvent[event], b)
    end
    return b
end

-- The blocks in the order set, those not in it after them (before login:
-- as added)
function P.Blocks()
    local list, seen = {}, {}
    local byKey = {}
    for _, b in ipairs(blocks) do byKey[b.def.key] = b end
    for _, key in ipairs(IF.db and P.Settings().order or {}) do
        if byKey[key] and not seen[key] then
            list[#list + 1], seen[key] = byKey[key], true
        end
    end
    for _, b in ipairs(blocks) do
        if not seen[b.def.key] then list[#list + 1] = b end
    end
    return list
end

-- A block one place earlier (dir -1) or later (1)
function P.Move(key, dir)
    local order = {}
    for i, b in ipairs(P.Blocks()) do order[i] = b.def.key end
    for i, k in ipairs(order) do
        local j = i + dir
        if k == key and order[j] then
            order[i], order[j] = order[j], order[i]
            break
        end
    end
    P.Settings().order = order
    P.Layout()
end

local function Refresh(b)
    local value = b.def.text()
    if value == false then return end
    b.value = value
    b.text:SetText(value or "")
    b:SetWidth(math.max(1, b.text:GetStringWidth()))
end

function P.Layout()
    if not IF.db then return end
    local s = P.Settings()
    local shown, widest = {}, 0
    for _, b in ipairs(P.Blocks()) do
        local on = not s.hidden[b.def.key] and b.value ~= nil
        b:SetShown(on)
        if on then
            shown[#shown + 1] = b
            widest = math.max(widest, b:GetWidth())
        end
    end
    bar:SetShown(#shown > 0)
    bar:ClearAllPoints()
    local place = s.place
    if place == "top" or place == "bottom" then
        local edge = place == "top" and "TOP" or "BOTTOM"
        bar:SetPoint(edge .. "LEFT")
        bar:SetPoint(edge .. "RIGHT")
        bar:SetHeight(BAR_H)
        local x = PAD
        for _, b in ipairs(shown) do
            b:ClearAllPoints()
            b:SetPoint("LEFT", bar, "LEFT", x, 0)
            x = x + b:GetWidth() + GAP
        end
        return
    end
    local width = widest + 2 * PAD
    if place == "left" or place == "right" then
        local edge = place == "left" and "LEFT" or "RIGHT"
        bar:SetPoint("TOP" .. edge)
        bar:SetPoint("BOTTOM" .. edge)
        bar:SetWidth(width)
    else
        bar:SetHeight(#shown * ROW_H + PAD)
        if place == "minimap" and Minimap then
            bar:SetPoint("TOP", Minimap, "BOTTOM", 0, -PAD)
            width = math.max(width, Minimap:GetWidth())
        else
            bar:SetPoint(place == "minimap" and "TOPRIGHT" or place)
        end
        bar:SetWidth(width)
    end
    for i, b in ipairs(shown) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -PAD / 2 - (i - 1) * ROW_H)
    end
end

-- Every block's line set again (a setting a block reads changed)
function P.Refresh()
    for _, b in ipairs(blocks) do Refresh(b) end
    P.Layout()
end

events:SetScript("OnEvent", function(_, event)
    if not IF.db then return end
    for _, b in ipairs(byEvent[event]) do Refresh(b) end
    P.Layout()
end)

IF.OnLogin(P.Refresh)
