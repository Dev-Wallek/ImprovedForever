-- Improved Forever: Threat. A small meter: who of you, your pet and your
-- party has how much threat on your target, and a warning when you're
-- about to lose the aggro (tanking) or pull it (not tanking). Its data is
-- the core's IF.Threat (Threat.lua). With Immersion's party cards it sits
-- low, right of them (no party: the bottom's middle; no room before the
-- spell diamonds: hidden), in its font; without, under the target. Faint
-- but for a warning. Only frames of ours; shown in a fight on an enemy,
-- nothing to press.
local IF = ImprovedForever
local T = IF.Threat

IF.AddModule({ key = "threat", label = "Threat", icon = IF.TEX .. "ic_mod_threat", addon = ... })

local TM = {}
IF.ThreatMeter = TM

local DEFAULTS = {
    meter = false,   -- the meter shown (nameplates and party cards show threat too, Immersion)
    solo = false,    -- also with no one but you on the threat list
    warnings = true, -- losing / pulling aggro over the list
    close = false,   -- only while a warning is up
}

function TM.Settings()
    IF.db.threat = IF.db.threat or {}
    local s = IF.db.threat
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    return s
end

local W, ROW_H, BAR_H, NAME_W, VALUE_W, GAP = 170, 12, 6, 64, 30, 16
local FAINT = 0.6   -- (its alpha without a warning)
local WARNINGS = {
    losing = { "Losing aggro!", 1, 0.25, 0.2 },
    pulling = { "Pulling aggro!", 1, 0.6, 0.1 },
}

local meter = CreateFrame("Frame", "ImprovedForeverThreatMeter", UIParent)
meter:SetFrameStrata("LOW")
meter:SetWidth(W)
meter:Hide()
local header = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
header:SetJustifyH("LEFT")

-- (a row: the name, a thin bar, the percent)
local rows = {}
for i = 1, #T.UNITS do
    local r = CreateFrame("Frame", nil, meter)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -i * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -i * ROW_H)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT")
    r.name:SetWidth(NAME_W - 4)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetHeight(BAR_H)
    r.bar:SetPoint("LEFT", NAME_W, 0)
    r.bar:SetPoint("RIGHT", -VALUE_W, 0)
    r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    r.bar:SetMinMaxValues(0, 100)
    r.track = r.bar:CreateTexture(nil, "BACKGROUND")
    r.track:SetAllPoints()
    r.track:SetColorTexture(0, 0, 0, 0.35)
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetPoint("RIGHT")
    rows[i] = r
end

-- (Immersion's target header, when it's on)
local function ImmersionHeader()
    local IN = IF.Interface
    return IN and IN.Settings and IN.Settings().target and _G.ImprovedForeverTargetHeader
end

-- (a region's edge in UIParent's units)
local function Edge(region, edge)
    local v = region[edge](region)
    return v and v * region:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Right of the party cards and their spells' diamond, bottoms level; no
-- party: the bottom's middle; false: no room before the spell diamonds
local function PlaceLow(IN)
    local right, bottom
    for i = 1, 4 do
        local card = _G["ImprovedForeverPartyCard" .. i]
        local r = card and card:IsVisible() and Edge(card, "GetRight")
        if r and (not right or r > right) then right, bottom = r, Edge(card, "GetBottom") end
    end
    meter:ClearAllPoints()
    if not right then
        meter:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, IN.BOTTOM)
        return true
    end
    local pp, cluster = IN.PartyPad, _G.ImprovedForeverPartyCasts
    if pp and pp.Shown() and cluster then
        local left = Edge(cluster, "GetLeft")
        if left then right = math.max(right, left + pp.Width() * cluster:GetEffectiveScale() / UIParent:GetEffectiveScale()) end
    end
    local x = right + GAP
    local barLeft = IN.GamepadBar and IN.GamepadBar.Rect()
    if barLeft and x + W > barLeft / UIParent:GetEffectiveScale() - GAP then return false end
    meter:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, bottom)
    return true
end

local function Place()
    local IN = IF.Interface
    local low = IN and IN.Settings and IN.Settings().cards ~= false and IN.PartyCards and IN.BOTTOM
    if low then
        header:SetFont(IN.HeaderSlot.FONT, 11, "")
        return PlaceLow(IN)
    end
    header:SetFontObject("GameFontNormalSmall")
    meter:ClearAllPoints()
    meter:SetPoint("TOP", ImmersionHeader() or TargetFrame, "BOTTOM", 0, -4)
    return true
end

-- Entries on the target, the most threat first (a secret percent after
-- the known ones, by status)
local function Entries()
    local list = {}
    for _, unit in ipairs(T.UNITS) do
        local info = UnitExists(unit) and T.Of(unit, "target")
        if info then
            info.unit = unit
            list[#list + 1] = info
        end
    end
    table.sort(list, function(a, b)
        if (a.percent ~= nil) ~= (b.percent ~= nil) then return a.percent ~= nil end
        if a.percent and a.percent ~= b.percent then return a.percent > b.percent end
        return a.status > b.status
    end)
    return list
end

local function Refresh()
    if not IF.db then return end
    local s = TM.Settings()
    local list = s.meter and UnitCanAttack("player", "target") and Entries() or {}
    if #list == 0 or (#list == 1 and not s.solo) then return meter:Hide() end
    local warning = WARNINGS[T.Warning("target") or ""]
    if s.close and not warning then return meter:Hide() end
    if not s.warnings then warning = nil end
    -- (before the header's colour: a font object brings its own)
    if not Place() then return meter:Hide() end
    meter:SetAlpha(warning and 1 or FAINT)
    if warning then
        header:SetText(warning[1])
        header:SetTextColor(warning[2], warning[3], warning[4])
    else
        header:SetText("Threat")
        header:SetTextColor(1, 0.82, 0)
    end
    for i, r in ipairs(rows) do
        local e = list[i]
        r:SetShown(e ~= nil)
        if e then
            local cr, cg, cb = GetThreatStatusColor(e.status)
            r.bar:SetStatusBarColor(cr, cg, cb, 0.9)
            -- (a boss's percent is secret: the bar full in its status's colour)
            r.bar:SetValue(e.percent or 100)
            r.name:SetText(UnitName(e.unit) or e.unit)
            r.value:SetText(e.percent and ("%d%%"):format(math.floor(e.percent + 0.5)) or "")
        end
    end
    meter:SetHeight((#list + 1) * ROW_H)
    meter:Show()
end
TM.Refresh = Refresh

-- (threat events come many times a second in a fight: one refresh for
-- the lot)
local queued
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.1, function()
        queued = false
        Refresh()
    end)
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED",
    "GROUP_ROSTER_UPDATE", "UNIT_PET", "PLAYER_REGEN_ENABLED" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", Queue)
