-- Baganator's Auto Open at the auction house, while our auction window is on
-- (ImprovedForever_Auction, its "Auction window" setting): that window needs no
-- bags, so the bags Baganator opens with the auction house are closed again
-- in the same frame, and its Auction House checkbox shows off, greyed out,
-- with the reason. Baganator's saved setting is left as it is.
local IF = ImprovedForever

local OPTION = "auto_open.auction_house"
local NOTE = "|cff808080Off: Improved Forever's auction window is on|r"

local function Active()
    local A = IF.Auction
    return A ~= nil and A.Settings().buy and A.Available()
end

-- The checkbox (Baganator's customise dialog, Auto Open tab)
local function Grey(holder)
    local box = holder.checkBox
    if not holder.label then
        holder.label = box:GetText()
        box:SetDisabledFontObject(GameFontDisable)
    end
    local on = Active()
    box:SetEnabled(not on)
    if on then box:SetChecked(false) end
    box:SetText(on and holder.label .. "\n" .. NOTE or holder.label)
end

local function SeenCheckbox(box)
    -- (its option is set on the holder after the box is made)
    C_Timer.After(0, function()
        local holder = box:GetParent()
        if not (holder and holder.option == OPTION and holder.checkBox == box) then return end
        hooksecurefunc(holder, "SetValue", Grey)
        holder:HookScript("OnShow", Grey)
        Grey(holder)
    end)
end

-- The bags, opened in the same frame as the auction house: closed again
local shownAt, openedAt
local function Close(win)
    if Active() and win:IsShown() and shownAt == openedAt then win:Hide() end
end

local function SeenBackpack(win)
    win:HookScript("OnShow", function()
        shownAt = GetTime()
        Close(win)
    end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    events:SetScript("OnEvent", function(_, _, kind)
        if kind ~= Enum.PlayerInteractionType.Auctioneer then return end
        openedAt = GetTime()
        Close(win)
    end)
end

local function Seen(details)
    if details.regionType == "CheckBox" then return SeenCheckbox(details.region) end
    if details.regionType ~= "ButtonFrame" then return end
    for _, tag in ipairs(details.tags or {}) do
        if tag == "backpack" then return SeenBackpack(details.region) end
    end
end
for _, details in ipairs(Baganator.API.Skins.GetAllFrames() or {}) do Seen(details) end
Baganator.API.Skins.RegisterListener(Seen)
