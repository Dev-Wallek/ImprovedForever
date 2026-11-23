-- A card beside the profession window about the recipe it shows: its
-- colours on a bar with your skill on it, the chance of a point, about how
-- many crafts are left until it turns grey, what its reagents cost (a
-- vendor's price where a vendor sells one and the auction's) and what the
-- result brings at a vendor and at the auction house. Only to look at: the
-- game's window keeps the controller.
local IF = ImprovedForever
local PR = IF.Professions
local K = IF.ConfigKit
local KC = K.C

local W, PAD, BAR_H = 300, 16, 10
local COLORS = {
    orange = { 1, 0.5, 0.25 }, yellow = { 1, 0.9, 0.2 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.55, 0.55, 0.55 },
}
local HEX = { orange = "ff8040", yellow = "ffe633", green = "40bf40", grey = "8c8c8c" }

local card = K.NewFrame("Frame", "ImprovedForeverProfessionCard", UIParent, "DefaultPanelFlatTemplate")
card:SetWidth(W)
card:SetClampedToScreen(true)
card:Hide()
IF.Focus.Dock(card)
local title = card.TitleContainer and card.TitleContainer.TitleText
if title then title:SetText("Levelling") end

local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
name:SetPoint("TOPLEFT", PAD, -34)
name:SetPoint("RIGHT", -PAD, 0)
name:SetJustifyH("LEFT")
name:SetWordWrap(false)

-- The bar: a segment per colour, a mark at your skill, the thresholds under it
local bar = CreateFrame("Frame", nil, card)
bar:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -12)
bar:SetSize(W - 2 * PAD, BAR_H)
local segments, ticks = {}, {}
for i, key in ipairs({ "orange", "yellow", "green", "grey" }) do
    local seg = bar:CreateTexture(nil, "ARTWORK")
    seg:SetColorTexture(unpack(COLORS[key]))
    seg:SetHeight(BAR_H)
    segments[i] = seg
    ticks[i] = K.ChatText(bar, 10, KC.help)
end
local mark = bar:CreateTexture(nil, "OVERLAY")
mark:SetColorTexture(1, 1, 1)
mark:SetSize(2, BAR_H + 6)
local you = K.ChatText(bar, 10, KC.cream)

-- The text under the bar: one font string, a line each
local body = K.ChatText(card, 12, KC.cream)
body:SetWidth(W - 2 * PAD)
body:SetJustifyH("LEFT")
body:SetSpacing(3)

local function Money(copper)
    return GetMoneyString(math.floor(copper + 0.5), true)
end

-- A reagent's prices: a vendor's where one sells it, the auction's; each
-- nil when not known
local function ReagentPrices(itemID)
    local buy = IF.RecipeData.buy[itemID]
    local vendor = buy and IF.GameData.SoldByVendor(itemID) and buy or nil
    local A = IF.Auction
    return vendor, A and A.Price and A.Price(itemID)
end

-- The thresholds: orange from where it's learnt, yellow, green, grey
local function Thresholds(spell)
    local t = IF.RecipeData.trivial[spell]
    if not t or t[2] == 0 then return nil end
    local yellow, grey = math.min(t[1], t[2]), t[2]
    return { PR.LearnRank(spell) or 1, yellow, math.floor((yellow + grey) / 2), grey }
end

local function DrawBar(spell, skill)
    local th = Thresholds(spell)
    bar:SetShown(th ~= nil)
    if not th then return end
    local first, last = th[1], th[4] + math.max(5, math.floor((th[4] - th[2]) / 4))
    local width = bar:GetWidth()
    local function X(v) return (math.max(first, math.min(last, v)) - first) / (last - first) * width end
    for i, seg in ipairs(segments) do
        local from, to = X(th[i]), X(th[i + 1] or last)
        seg:ClearAllPoints()
        seg:SetPoint("LEFT", bar, "LEFT", from, 0)
        seg:SetWidth(math.max(1, to - from))
        ticks[i]:ClearAllPoints()
        ticks[i]:SetPoint("TOP", bar, "BOTTOMLEFT", from, -2)
        ticks[i]:SetText(th[i])
    end
    mark:ClearAllPoints()
    mark:SetPoint("CENTER", bar, "LEFT", X(skill), 0)
    you:ClearAllPoints()
    you:SetPoint("TOP", bar, "BOTTOMLEFT", X(skill), -14)
    you:SetText("You: " .. skill)
end

local function Lines(recipe, skill, difficulty)
    local spell = recipe.recipeID
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    local color, chance = PR.Color(spell, skill, difficulty)
    if color then
        local tint = "|cff" .. HEX[color]
        add(tint .. "Chance of a point: " .. (chance and (math.floor(chance * 100 + 0.5) .. "%") or "?") .. "|r")
    end
    local crafts = color ~= "grey" and PR.CraftsToGrey(spell, skill)
    if color == "grey" then
        add("Grey: no more points")
    else
        add("Until grey: " .. (crafts and ("about " .. crafts .. " crafts") or "?"))
    end
    add("You can make: " .. IF.Recipes.Craftable(spell))
    add(" ")
    local cost = 0
    for _, r in ipairs(recipe.reagents) do
        local item = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.itemID)) or ("item " .. r.itemID)
        local vendor, auction = ReagentPrices(r.itemID)
        -- (the cost: the cheaper of the two)
        local price = vendor and auction and math.min(vendor, auction) or vendor or auction
        if price and cost then cost = cost + price * r.per else cost = nil end
        local prices = {}
        if vendor then prices[#prices + 1] = Money(vendor * r.per) .. " |cff9d917a(vendor)|r" end
        if auction then prices[#prices + 1] = Money(auction * r.per) .. " |cff9d917a(auction)|r" end
        add(("%s ×%d  %s"):format(item, r.per,
            #prices > 0 and table.concat(prices, "  ") or "|cff9d917a?|r"))
    end
    add("|cffffd24aReagents per craft:|r " .. (cost and Money(cost) or "?"))
    local out = recipe.output
    if out then
        local function Profit(income)
            if not cost then return "" end
            local p = income - cost
            return (p < 0 and "  |cffff7a5c-" or "  |cff5fd35f+") .. Money(math.abs(p)) .. "|r"
        end
        local sell = select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(out))
        if sell and sell > 0 then
            add("|cffffd24aSold to a vendor:|r " .. Money(sell * recipe.makes) .. Profit(sell * recipe.makes))
        end
        local A = IF.Auction
        local net = A and A.UnitNet and A.UnitNet(out)
        add("|cffffd24aAt the auction house:|r " .. (net and (Money(net * recipe.makes) .. Profit(net * recipe.makes))
            or "?"))
    end
    return table.concat(lines, "\n")
end

local function Refresh()
    local id = IF.Recipes.Shown()
    local recipe = id and IF.Recipes.Read(id)
    local skill = recipe and PR.Skill()
    if not skill then
        card:Hide()
        return
    end
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
    name:SetText(recipe.name)
    DrawBar(id, skill)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", bar:IsShown() and bar or name, "BOTTOMLEFT", 0, bar:IsShown() and -30 or -10)
    body:SetText(Lines(recipe, skill, ok and info and info.relativeDifficulty))
    card:SetHeight(34 + name:GetStringHeight() + (bar:IsShown() and 42 or 10) + body:GetStringHeight() + 2 * PAD)
    card:Show()
end
PR.RefreshCard = Refresh

-- With the profession window: shown with it, again on a recipe picked, the
-- bags or the skill changing; nothing on a timer
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if IF.Recipes.WindowUp() then Refresh() end
end)

local function Hook()
    local frame = _G.ProfessionsFrame
    if not frame or card.hooked then return end
    card.hooked = true
    frame:HookScript("OnShow", function()
        for _, e in ipairs({ "TRADE_SKILL_LIST_UPDATE", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED" }) do
            events:RegisterEvent(e)
        end
        Refresh()
    end)
    frame:HookScript("OnHide", function()
        events:UnregisterAllEvents()
        card:Hide()
    end)
    local page = frame.CraftingPage
    if page and page.SelectRecipe then hooksecurefunc(page, "SelectRecipe", Refresh) end
    if frame:IsShown() then Refresh() end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, addon)
    if addon == "Blizzard_Professions" then Hook() end
end)
Hook()
