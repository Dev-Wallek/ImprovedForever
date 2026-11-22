-- Writes this character's bags (at login, and a second after they change)
-- and its bank (while the banker is open, and as it closes) into
-- ImprovedForeverBagsDB, account-wide: chars[key] = { name, class, level,
-- money, bagsAt, bankAt, bags = { container... }, bank = { container... } },
-- a container { item (the bag's own item ID; nil: the backpack), size,
-- slots = { [slot] = BG.Slot(...) } }. Only reads the game.
local IF = ImprovedForever
local BG = IF.Bags

-- The game's numbered bag indices from `prefix`1 on (Forever has 9 bank
-- tabs, other clients fewer)
local function Numbered(prefix)
    local list, index = {}, Enum and Enum.BagIndex or {}
    for i = 1, 20 do
        if not index[prefix .. i] then break end
        list[i] = index[prefix .. i]
    end
    return list
end

function BG.BagIDs()
    local index = Enum.BagIndex
    local list = { index.Backpack, index.Bag_1, index.Bag_2, index.Bag_3, index.Bag_4 }
    if (Constants.InventoryConstants.NumReagentBagSlots or 0) > 0 and index.ReagentBag then
        list[#list + 1] = index.ReagentBag
    end
    return list
end

function BG.BankIDs()
    return Numbered("CharacterBankTab_")
end

-- This character's key: its full name (Forever's first name and surname) and realm
function BG.Me()
    local name = GetUnitName and GetUnitName("player", false) or UnitName("player")
    return name .. "-" .. (GetRealmName() or "?")
end

local function Store()
    ImprovedForeverBagsDB = ImprovedForeverBagsDB or {}
    ImprovedForeverBagsDB.chars = ImprovedForeverBagsDB.chars or {}
    return ImprovedForeverBagsDB.chars
end
BG.Chars = Store

local function Char()
    local chars, key = Store(), BG.Me()
    local c = chars[key] or {}
    chars[key] = c
    c.name = GetUnitName and GetUnitName("player", false) or UnitName("player")
    c.class = select(2, UnitClass("player"))
    c.level = UnitLevel("player")
    c.money = GetMoney()
    return c
end

local function Read(bag)
    local size = C_Container.GetContainerNumSlots(bag) or 0
    if size == 0 then return nil end
    local slots = {}
    for slot = 1, size do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then slots[slot] = BG.Slot(info.itemID, info.stackCount or 1, info.hyperlink) end
    end
    local item
    if bag ~= Enum.BagIndex.Backpack and C_Container.ContainerIDToInventoryID then
        local ok, inv = pcall(C_Container.ContainerIDToInventoryID, bag)
        item = ok and inv and GetInventoryItemID("player", inv) or nil
    end
    return { item = item, size = size, slots = slots }
end

local function ReadAll(ids)
    local list = {}
    for _, bag in ipairs(ids) do list[#list + 1] = Read(bag) end
    return list
end

local listeners = {}
function BG.OnChange(fn)
    listeners[#listeners + 1] = fn
end
local function Changed()
    for _, fn in ipairs(listeners) do fn() end
end

local bankOpen = false

local function Write(bank)
    local c = Char()
    c.bags, c.bagsAt = ReadAll(BG.BagIDs()), time()
    if bank and bankOpen then c.bank, c.bankAt = ReadAll(BG.BankIDs()), time() end
    Changed()
end

-- (many changes at once: written once, a second later)
local queued, queuedBank = false, false
local function Soon(bank)
    queuedBank = queuedBank or bank
    if queued then return end
    queued = true
    C_Timer.After(1, function()
        queued = false
        local b = queuedBank
        queuedBank = false
        Write(b)
    end)
end

local isBankBag = {}
for _, id in ipairs(BG.BankIDs()) do isBankBag[id] = true end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BAG_UPDATE", "PLAYER_MONEY",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        Soon(true)
    elseif event == "BANKFRAME_CLOSED" then
        -- (read as it closes: the bank isn't always loaded at its opening)
        Write(true)
        bankOpen = false
    elseif event == "BAG_UPDATE" then
        if bankOpen and isBankBag[arg] then Soon(true) end
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if bankOpen then Soon(true) end
    elseif event == "PLAYER_MONEY" then
        Char()
        Changed()
    else
        Soon(false)
    end
end)
