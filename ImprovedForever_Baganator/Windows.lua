-- Baganator's windows in L2 / R2 (the core's AddonWindows.lua): its bags,
-- bank and guild bank, its customise dialog, its character list, its search
-- help and the bag slots bar above the bags or bank (no glow: the cursor
-- alone shows it; closed by Baganator's own toggle). Its item menu has
-- KeepOrSell's keep mark when that is loaded. The module's "Windows in
-- L2 / R2" setting switches them all.
local IF = ImprovedForever

local W = IF.AddonWindows
local BG = IF.Baganator

-- (its windows come from here, not from the core's UISpecialFrames scan)
W.Claim("Baganator")

-- (Baganator's skin tags for its windows)
local KINDS = { backpack = true, bank = true, guild = true, customise = true }
local CHARACTERS = "^Baganator_CharacterSelectFrame"
-- (its skin sees the search help with no tag)
local HELP = "Baganator_SearchHelpFrame"

local mine = {}   -- the windows handed in from here

local function Enabled()
    return BG.Settings().switch
end

-- An item's menu, with KeepOrSell loaded: its keep mark, by its /kos keep | unkeep
-- (KeepOrSellDB.keep: it has no Lua API)
local function KeepOrSell(id, Add)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("KeepOrSell")) then return end
    local db, kos = _G.KeepOrSellDB, SlashCmdList.KEEPORSELL
    if not (db and kos) then return end
    local kept = db.keep and db.keep[id]
    Add(kept and "KeepOrSell: don't keep" or "KeepOrSell: keep", function() kos((kept and "unkeep " or "keep ") .. id) end)
end

local function Watch(win, close, root)
    mine[win] = true
    W.Watch(win, { close = close, root = root, enabled = Enabled, itemEntries = KeepOrSell })
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
    if W.Watched(win) then return end
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
    if name and (name == HELP or name:find(CHARACTERS)) then return WatchWindow(win) end
    for _, tag in ipairs(details.tags or {}) do
        if KINDS[tag] then return WatchWindow(win, tag == "backpack" or tag == "bank") end
    end
end
for _, details in ipairs(Baganator.API.Skins.GetAllFrames() or {}) do Seen(details) end
Baganator.API.Skins.RegisterListener(Seen)

-- The radial's Bags while one of these is away: its pad back, true (false in combat)
function BG.Back()
    return W.Back(function(win) return mine[win] end)
end

-- The setting switched off: they let the pad go
function BG.SwitchOff()
    W.Refresh()
end
