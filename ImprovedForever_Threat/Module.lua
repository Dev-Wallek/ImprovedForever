-- Improved Forever: Threat. A small meter under the target: who of you,
-- your pet and your party has how much threat on it, and a warning when
-- you're about to lose the aggro (tanking) or pull it (not tanking). Its
-- data is the core's IF.Threat (Threat.lua). Under Immersion's target
-- header when that's on, in its font. Only frames of ours; shown in a
-- fight on an enemy, nothing to press.
local IF = ImprovedForever
local T = IF.Threat

IF.AddModule({ key = "threat", label = "Threat", icon = IF.TEX .. "ic_mod_general", addon = ... })

local TM = {}
IF.ThreatMeter = TM

local DEFAULTS = {
    meter = true,    -- the meter shown
    solo = false,    -- also with no one but you on the threat list
    warnings = true, -- losing / pulling aggro over the list
}

function TM.Settings()
    IF.db.threat = IF.db.threat or {}
    local s = IF.db.threat
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    return s
end

local W, ROW_H, PAD = 170, 16, 6
local WARNINGS = {
    losing = { "Losing aggro!", 1, 0.25, 0.2 },
    pulling = { "Pulling aggro!", 1, 0.6, 0.1 },
}

local meter = CreateFrame("Frame", "ImprovedForeverThreatMeter", UIParent)
meter:SetFrameStrata("LOW")
meter:SetWidth(W)
meter:Hide()
local bg = meter:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.55)
local header = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header:SetPoint("TOPLEFT", PAD, -PAD)
header:SetPoint("TOPRIGHT", -PAD, -PAD)
header:SetJustifyH("LEFT")

local rows = {}
for i = 1, #T.UNITS do
    local r = CreateFrame("StatusBar", nil, meter)
    r:SetHeight(ROW_H - 2)
    r:SetPoint("TOPLEFT", PAD, -PAD - i * ROW_H)
    r:SetPoint("TOPRIGHT", -PAD, -PAD - i * ROW_H)
    r:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    r:SetMinMaxValues(0, 100)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 3, 0)
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetPoint("RIGHT", -3, 0)
    rows[i] = r
end

-- (Immersion's target header, when it's on)
local function ImmersionHeader()
    local IN = IF.Interface
    return IN and IN.Settings and IN.Settings().target and _G.ImprovedForeverTargetHeader
end

local fontSet
local function Place()
    local over = ImmersionHeader() or TargetFrame
    meter:ClearAllPoints()
    meter:SetPoint("TOP", over, "BOTTOM", 0, -4)
    if ImmersionHeader() and not fontSet then
        local HS = IF.Interface.HeaderSlot
        header:SetFont(HS.FONT, 13, "")
        fontSet = true
    end
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
    local warning = s.warnings and WARNINGS[T.Warning("target") or ""]
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
            r:SetStatusBarColor(cr, cg, cb, 0.6)
            -- (a boss's percent is secret: the bar full in its status's colour)
            r:SetValue(e.percent or 100)
            r.name:SetText(UnitName(e.unit) or e.unit)
            r.value:SetText(e.percent and ("%d%%"):format(math.floor(e.percent + 0.5)) or "")
        end
    end
    meter:SetHeight(2 * PAD + (#list + 1) * ROW_H)
    Place()
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
