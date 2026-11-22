-- The auction house's prices, kept over time, per realm, in
-- ImprovedForeverAuctionDB: a full scan of every auction
-- (C_AuctionHouse.ReplicateItems, as the auction house opens, at most once
-- in 15 minutes: the server's limit) and a search of one item (the
-- auction window's tabs). Another addon's full scan is read too, when
-- none was in 15 minutes. Each is kept as the day's numbers per item:
-- its lowest price a unit, its market price (what the cheapest quarter of
-- those listed ask on average), how many are up and what the cheapest
-- five units cost on average (A.Price: buying a few). A.Suggest prices an
-- item from them; the Auction tab (AuctionEditor.lua) sets how.
local IF = ImprovedForever

local A = {}
IF.Auction = A

local AH = C_AuctionHouse
local DAY = 86400
local REPLICATE_EVERY = 15 * 60   -- the server's own limit on full scans
local CHUNK = 2000                -- auctions read a frame (a scan can be many thousands)
local MARKET_SHARE = 0.25         -- the market price: the cheapest quarter listed
local BUY_UNITS = 5               -- A.Price: what buying a few costs
local AH_CUT = 0.05               -- the auction house's cut of a sale
local SEARCH_TIMEOUT = 8

local DEFAULTS = {
    scan = true,           -- a full scan as the auction house opens
    undercut = "1",        -- under the lowest: copper ("1", "100") or a share ("1%", "5%")
    pricing = "undercut",  -- the price it starts at: undercut, match, market
    duration = 2,          -- 1 / 2 / 3: the game's three (A.Durations)
    vendorFloor = true,    -- never under what a vendor pays (after the cut)
    tooltip = true,        -- item tooltips show the usual and lowest price
    buy = true,            -- our auction window (AuctionBuyClassic.lua); off: the game's
    buyUsable = false,     -- its filters: usable only, qualities (none ticked: any), up to my level, sort
    buyMyLevel = false,
    buySort = "price",
    tasksTracker = true,   -- tasks tracked in the objective tracker (Tasks.lua)
    buyUpgrades = "mark",  -- upgrades (Upgrades.lua) in it: off, mark (an arrow), only
    destroy = true,        -- junk (ItemValue.lua) is never what sells better here than to a vendor
    share = 25,            -- "sells better here": by this many percent over a vendor's pay
    minGain = 0,           -- and by at least this much (copper)
    bargainShare = 30,     -- Buy's Bargains: listed this many percent or more under the usual price
    belowMin = 0,          -- Buy's Below vendor price: gaining this much copper or more an item
    keepDays = 30,         -- days of prices kept
    chartDays = 14,        -- days the charts show (and the market price covers)
}

function A.Settings()
    local db = IF.db
    db.buyLog = nil   -- (a buying probe's, since removed)
    db.auction = db.auction or {}
    local settings = db.auction
    for k, v in pairs(DEFAULTS) do
        if settings[k] == nil then settings[k] = v end
    end
    -- The qualities ticked ({ [quality] = true }); once a lowest one: it and up
    if not settings.buyQualities then
        settings.buyQualities = {}
        if (settings.buyQuality or 0) > 0 then
            for q = settings.buyQuality, 5 do settings.buyQualities[q] = true end
        end
        settings.buyQuality = nil
    end
    return settings
end

function A.Available()
    return AH ~= nil and AH.ReplicateItems ~= nil and AH.PostItem ~= nil
end

function A.IsOpen()
    local frame = _G.AuctionHouseFrame
    return A.open and frame ~= nil and frame:IsShown()
end

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------
-- 10350 -> "1 [gold] 3 [silver] 50 [copper]", with the game's coin icons
local COINS = {
    { 10000, "Interface\\MoneyFrame\\UI-GoldIcon" },
    { 100, "Interface\\MoneyFrame\\UI-SilverIcon" },
    { 1, "Interface\\MoneyFrame\\UI-CopperIcon" },
}
-- The auction durations' names, as the game's own Sell window shows them
-- (this client's: 2 / 8 / 24 hours; posting takes their index)
function A.Durations()
    return {
        _G.AUCTION_DURATION_ONE or "2 Hours",
        _G.AUCTION_DURATION_TWO or "8 Hours",
        _G.AUCTION_DURATION_THREE or "24 Hours",
    }
end

function A.Money(copper)
    copper = math.floor(copper or 0)
    local parts = {}
    for _, coin in ipairs(COINS) do
        local n = math.floor(copper / coin[1])
        copper = copper - n * coin[1]
        if n > 0 then parts[#parts + 1] = n .. " |T" .. coin[2] .. ":0:0:2:0|t" end
    end
    return #parts > 0 and table.concat(parts, " ") or ("0 |T" .. COINS[3][2] .. ":0:0:2:0|t")
end

-- Prices in whole silver where the auction house takes no copper
function A.Round(copper)
    copper = math.max(1, math.floor(copper + 0.5))
    if AH and AH.SupportsCopperValues and not AH.SupportsCopperValues() then
        return math.max(100, math.floor(copper / 100 + 0.5) * 100)
    end
    return copper
end

function A.Cut()
    return AH_CUT
end

---------------------------------------------------------------------------
-- The store: realms[realm].items[itemID][day] = "lowest:market:quantity"
---------------------------------------------------------------------------
local function Today()
    return math.floor(time() / DAY)
end
A.Today = Today

local function Realm()
    ImprovedForeverAuctionDB = ImprovedForeverAuctionDB or {}
    local store = ImprovedForeverAuctionDB
    store.realms = store.realms or {}
    local name = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
    store.realms[name] = store.realms[name] or { items = {} }
    return store.realms[name]
end
A.Realm = Realm

-- (cheapest5: nil in days kept before it was)
local function Unpack(s)
    local lowest, market, qty, cheapest5 = strsplit(":", s)
    return tonumber(lowest), tonumber(market), tonumber(qty), tonumber(cheapest5)
end

-- A sighting today: the day's lowest kept, the rest as last seen
function A.Record(itemID, lowest, market, qty, cheapest5)
    local items = Realm().items
    local days = items[itemID] or {}
    items[itemID] = days
    local today = Today()
    local old = days[today] and Unpack(days[today])
    if old and old < lowest then lowest = old end
    days[today] = lowest .. ":" .. market .. ":" .. qty .. ":" .. cheapest5
end

-- What the cheapest `units` cost a unit on average (list sorted cheapest first;
-- fewer listed: all of them)
local function Cheapest(list, units)
    local got, sum = 0, 0
    for _, l in ipairs(list) do
        local take = math.min(l[2], units - got)
        if take <= 0 then break end
        sum, got = sum + l[1] * take, got + take
    end
    return math.floor(sum / got + 0.5)
end

-- The day's numbers from listings { { unit, count } }: lowest, market,
-- total, cheapest five
local function Summarize(list)
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local total = 0
    for _, l in ipairs(list) do total = total + l[2] end
    return list[1][1], Cheapest(list, math.max(1, total * MARKET_SHARE)), total, Cheapest(list, BUY_UNITS)
end

-- The item's days over the last `days`, oldest first: { { day, lowest, market, qty } }
function A.History(itemID, days)
    local list = {}
    local item = Realm().items[itemID]
    if not item then return list end
    local from = Today() - (days or A.Settings().chartDays)
    for day, packed in pairs(item) do
        if day > from then
            local lowest, market, qty = Unpack(packed)
            if lowest then list[#list + 1] = { day = day, lowest = lowest, market = market, qty = qty } end
        end
    end
    table.sort(list, function(a, b) return a.day < b.day end)
    return list
end

-- Its usual price: the median of the days' market prices over the chart's days
function A.MarketPrice(itemID, days)
    local values = {}
    for _, d in ipairs(A.History(itemID, days)) do values[#values + 1] = d.market end
    if #values == 0 then return nil end
    table.sort(values)
    local mid = (#values + 1) / 2
    return math.floor((values[math.floor(mid)] + values[math.ceil(mid)]) / 2 + 0.5), #values
end

-- What it brings a unit here after the cut, at its usual price (nil: unknown)
function A.UnitNet(itemID)
    local market = A.MarketPrice(itemID)
    return market and market * (1 - AH_CUT) or nil
end

-- Its latest day: day, lowest, market, quantity, cheapest five (nil: never seen)
function A.Latest(itemID)
    local item = Realm().items[itemID]
    local last
    for day in pairs(item or {}) do
        if not last or day > last then last = day end
    end
    if not last then return nil end
    return last, Unpack(item[last])
end

-- For other modules and addons (ImprovedForever.Auction.Price), a unit in
-- copper: what the cheapest five cost on average on its latest day, its
-- usual price (A.MarketPrice) and the days since that day. nil: never seen.
function A.Price(itemID)
    if type(itemID) ~= "number" or not IF.db then return nil end
    local day, lowest, _, _, cheapest5 = A.Latest(itemID)
    if not day then return nil end
    return cheapest5 or lowest, A.MarketPrice(itemID), Today() - day
end

-- Days older than kept go, and items left with none
function A.Prune()
    local from = Today() - A.Settings().keepDays
    local store = ImprovedForeverAuctionDB
    for _, realm in pairs(store and store.realms or {}) do
        for itemID, days in pairs(realm.items or {}) do
            for day in pairs(days) do
                if day <= from then days[day] = nil end
            end
            if next(days) == nil then realm.items[itemID] = nil end
        end
    end
end

-- How many items this realm has prices for, and when it was last scanned
function A.Stats()
    local realm = Realm()
    local n = 0
    for _ in pairs(realm.items) do n = n + 1 end
    return n, realm.scannedAt
end

function A.Clear()
    local realm = Realm()
    realm.items, realm.scannedAt, realm.belowVendor, realm.bargains = {}, nil, nil, nil
end

---------------------------------------------------------------------------
-- Listeners: told when prices change (a scan done, a search in)
---------------------------------------------------------------------------
local listeners = {}
function A.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function Changed()
    for _, fn in ipairs(listeners) do fn() end
    if IF.ItemValue then IF.ItemValue.Changed() end
end

-- The core's item verdict (ItemValue.lua) weighs these prices: what is
-- worth more here is never junk, the Sell tab's sections
if IF.ItemValue then
    IF.ItemValue.UseAuction({
        price = A.UnitNet,
        counts = function() return A.Settings().destroy end,
        share = function() return A.Settings().share end,
        minGain = function() return A.Settings().minGain end,
    })
end

---------------------------------------------------------------------------
-- The full scan: every auction, read a few thousand a frame
---------------------------------------------------------------------------
local scan = { state = "idle" }   -- idle, waiting (for the server), reading

-- When the server lets this realm scan again (seconds from now; 0: now)
function A.ScanWait()
    local at = Realm().replicateAt or 0
    -- (a clock gone back: never a wait longer than the limit)
    return math.max(0, math.min(REPLICATE_EVERY, at + REPLICATE_EVERY - time()))
end

function A.Scanning()
    return scan.state ~= "idle", scan.read, scan.total
end

function A.CanScan()
    if not A.Available() then return false, "not on this client" end
    if not A.IsOpen() then return false, "open the auction house first" end
    if scan.state ~= "idle" then return false, "already scanning" end
    local wait = A.ScanWait()
    if wait > 0 then return false, "the server allows one scan in 15 minutes: again in " .. math.ceil(wait / 60) .. " min" end
    return true
end

function A.Scan(quiet)
    local ok, why = A.CanScan()
    if not ok then
        if not quiet then IF.Print("scan: " .. why) end
        return false
    end
    scan.state, scan.started, scan.read, scan.total = "waiting", GetTime(), 0, nil
    Realm().replicateAt = time()
    AH.ReplicateItems()
    if not quiet then IF.Print("scanning the auction house...") end
    Changed()
    return true
end

local reader = CreateFrame("Frame")
reader:Hide()

-- Stops a scan under way (waiting for the server, or being read). What was
-- read is dropped; the server's 15 minutes still count.
function A.StopScan(quiet)
    if scan.state == "idle" then return false end
    reader:Hide()
    scan.state, scan.byItem = "idle", nil
    if not quiet then IF.Print("auction scan stopped.") end
    Changed()
    return true
end

-- The scan's state as a line for a window ("" when none is under way)
function A.ScanText()
    if scan.state == "idle" then return "" end
    if scan.state == "waiting" or not scan.total or scan.total == 0 then
        return "Scanning: waiting for the server..."
    end
    return "Scanning: " .. scan.read .. " / " .. scan.total
        .. " (" .. math.floor(scan.read * 100 / scan.total) .. "%)"
end

-- What of listings { { unit, count } } is under a vendor's pay: { units,
-- lowest, each (an item's gain at the lowest), count (the cheapest
-- listing's) }; nil: none, or its vendor price not known yet (ponytail:
-- skipped till the next scan)
local function BelowVendor(itemID, list)
    local sell = select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(itemID))
    if not sell or sell <= 0 then return nil end
    local units, cheapest = 0, nil
    for _, l in ipairs(list) do
        if l[1] < sell then
            units = units + l[2]
            if not cheapest or l[1] < cheapest[1] then cheapest = l end
        end
    end
    if not cheapest then return nil end
    local lowest = math.ceil(cheapest[1])
    return { units = units, lowest = lowest, each = sell - lowest, count = cheapest[2] }
end

-- The Buy tab's "Below vendor price": the last full scan's (an item's
-- search updates its own), as browse results, those gaining the setting's
-- copper or more an item, the most an item first
function A.BelowVendor()
    local list, least = {}, A.Settings().belowMin
    for itemID, b in pairs(Realm().belowVendor or {}) do
        if b.each and b.each > 0 and b.each >= least then
            list[#list + 1] = { itemKey = AH.MakeItemKey(itemID), totalQuantity = b.units, minPrice = b.lowest,
                each = b.each, count = b.count }
        end
    end
    table.sort(list, function(a, b) return a.each > b.each end)
    return list
end

-- Bargains: listings well under an item's usual price (its market price's
-- median over BARGAIN_DAYS days at least). Kept: the usual price and the
-- listings BARGAIN_KEEP or more under it, so A.Bargains can take any of the
-- setting's shares without a new scan. nil: none, or too few days known.
local BARGAIN_DAYS, BARGAIN_KEEP = 3, 0.2
A.BARGAIN_DAYS = BARGAIN_DAYS

local function Bargain(itemID, list)
    local usual, days = A.MarketPrice(itemID)
    if not usual or days < BARGAIN_DAYS then return nil end
    local cheap = {}
    for _, l in ipairs(list) do
        if l[1] <= usual * (1 - BARGAIN_KEEP) then cheap[#cheap + 1] = { math.ceil(l[1]), l[2] } end
    end
    if #cheap == 0 then return nil end
    return { usual = usual, listings = cheap }
end

-- The Buy tab's "Bargains": what is listed at least the setting's share
-- under its usual price, as browse results, the most saved first
function A.Bargains()
    local share = A.Settings().bargainShare / 100
    local list = {}
    for itemID, b in pairs(Realm().bargains or {}) do
        local units, saving, lowest = 0, 0, nil
        for _, l in ipairs(b.listings) do
            if l[1] <= b.usual * (1 - share) then
                units, saving = units + l[2], saving + (b.usual - l[1]) * l[2]
                lowest = math.min(lowest or l[1], l[1])
            end
        end
        if units > 0 then
            list[#list + 1] = { itemKey = AH.MakeItemKey(itemID), totalQuantity = units, minPrice = lowest,
                saving = math.floor(saving), usual = b.usual }
        end
    end
    table.sort(list, function(a, b) return a.saving > b.saving end)
    return list
end

local function FinishScan()
    reader:Hide()
    local items, below, bargains = 0, {}, {}
    for itemID, list in pairs(scan.byItem or {}) do
        below[itemID] = BelowVendor(itemID, list)
        -- (against the days before today's numbers join them)
        bargains[itemID] = Bargain(itemID, list)
        A.Record(itemID, Summarize(list))
        items = items + 1
    end
    local realm = Realm()
    realm.scannedAt, realm.belowVendor, realm.bargains = time(), below, bargains
    IF.Print("auction scan done: " .. (scan.read or 0) .. " auctions, " .. items .. " items priced.")
    scan.state, scan.byItem = "idle", nil
    Changed()
end

reader:SetScript("OnUpdate", function()
    local last = math.min(scan.total - 1, scan.read + CHUNK - 1)
    local byItem = scan.byItem
    for i = scan.read, last do
        -- name, texture, count, quality, usable, level, levelType, minBid,
        -- minIncrement, buyout, bid, highBidder, bidderFull, owner,
        -- ownerFull, saleStatus, itemID
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = AH.GetReplicateItemInfo(i)
        if itemID and count and count > 0 and buyout and buyout > 0 then
            local list = byItem[itemID]
            if not list then
                list = {}
                byItem[itemID] = list
            end
            list[#list + 1] = { buyout / count, count }
        end
    end
    scan.read = last + 1
    if scan.read >= scan.total then FinishScan() end
end)

local function StartReading()
    scan.state, scan.read, scan.byItem = "reading", 0, {}
    scan.total = AH.GetNumReplicateItems() or 0
    if scan.total == 0 then return FinishScan() end
    reader:Show()
end

---------------------------------------------------------------------------
-- A search for one item: fn(listings) once its results are in (nil: no
-- answer); listings: { { unit, count, own, auctionID (, total, link,
-- itemLevel: an item's) } }, cheapest first. Its numbers
-- are kept too.
---------------------------------------------------------------------------
local search

local function Send()
    if not search or search.sent then return end
    if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
        return -- (sent on AUCTION_HOUSE_THROTTLED_SYSTEM_READY)
    end
    local key = search.itemKey or AH.MakeItemKey(search.itemID)
    if search.commodity then
        AH.SendSearchQuery(key, { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }, false)
    elseif search.itemKey then
        -- (buying: that exact item, its auctions one by one)
        AH.SendSearchQuery(key, { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }, false)
    else
        AH.SendSellSearchQuery(key, { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }, false)
    end
    search.sent, search.sentAt = true, GetTime()
    A.lastQuery = search
end

-- itemLevel: gear's own (results of that level preferred, when there are
-- any); itemKey: a browse result's (buying), searched as it is
function A.Search(itemID, commodity, itemLevel, fn, itemKey)
    search = { itemID = itemID, commodity = commodity, itemLevel = itemLevel, fn = fn, token = {}, itemKey = itemKey }
    local token = search.token
    C_Timer.After(SEARCH_TIMEOUT, function()
        if search and search.token == token then
            search = nil
            fn(nil)
        end
    end)
    Send()
end

function A.CancelSearch()
    search = nil
end

local function Answer(listings)
    local s = search
    search = nil
    local plain = {}
    for i, l in ipairs(listings) do plain[i] = { l.unit, l.count } end
    local realm = Realm()
    if realm.belowVendor then realm.belowVendor[s.itemID] = BelowVendor(s.itemID, plain) end
    if realm.bargains then realm.bargains[s.itemID] = Bargain(s.itemID, plain) end
    if #listings > 0 then
        A.Record(s.itemID, Summarize(plain))
        Changed()
    end
    table.sort(listings, function(a, b) return a.unit < b.unit end)
    s.fn(listings)
end

-- (results come before ours is sent too: the client's own, a purchase's
-- refresh, its auctions as they were; only an answer to ours is taken)
local function CommodityResults(itemID)
    if not (search and search.sent and search.commodity and search.itemID == itemID) then return end
    local listings = {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.quantity > 0 then
            listings[#listings + 1] = { unit = r.unitPrice, count = r.quantity, own = (r.numOwnerItems or 0),
                auctionID = r.auctionID }
        end
    end
    Answer(listings)
end

local function ItemResults(itemKey)
    if not (search and search.sent and not search.commodity and itemKey and itemKey.itemID == search.itemID) then
        return
    end
    local all, sameLevel = {}, {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and r.quantity > 0 then
            -- (a search result's buyout is a unit's, quantity how many are
            -- up at it, as the game's own sell window reads it; a buy costs it)
            local l = { unit = r.buyoutAmount, total = r.buyoutAmount, count = r.quantity,
                own = r.containsOwnerItem and r.quantity or 0, auctionID = r.auctionID, link = r.itemLink,
                itemLevel = r.itemKey and r.itemKey.itemLevel }
            all[#all + 1] = l
            if search.itemLevel and r.itemKey and r.itemKey.itemLevel == search.itemLevel then
                sameLevel[#sameLevel + 1] = l
            end
        end
    end
    Answer(#sameLevel > 0 and sameLevel or all)
end

-- The price last set by hand for an item (a unit), per realm: where its
-- next sale starts
function A.MyPrice(itemID)
    local mine = Realm().myPrices
    return mine and mine[itemID]
end

function A.SetMyPrice(itemID, price)
    local realm = Realm()
    realm.myPrices = realm.myPrices or {}
    realm.myPrices[itemID] = price
end

---------------------------------------------------------------------------
-- The price to ask a unit. listings: a search's (or nil); vendor: what a
-- vendor pays a unit. Returns the price, the presets ({ key, label, price }:
-- the last price set by hand first, A.MyPrice), a warning (or nil) and the
-- preset it is.
---------------------------------------------------------------------------
A.PRESETS = {
    { key = "undercut", label = "Undercut lowest" },
    { key = "match", label = "Match lowest" },
    { key = "market", label = "Usual price" },
}

local function Undercut(price)
    local how = A.Settings().undercut
    local share = how:match("^(%d+)%%$")
    local cut = share and math.max(1, math.floor(price * tonumber(share) / 100)) or tonumber(how) or 1
    return math.max(1, price - cut)
end

function A.Floor(vendor)
    if not A.Settings().vendorFloor or not vendor or vendor <= 0 then return 0 end
    return math.ceil(vendor / (1 - AH_CUT))
end

function A.Suggest(itemID, listings, vendor)
    -- The lowest anyone else asks; the lowest of all (ours may be under it)
    local others, lowest
    for _, l in ipairs(listings or {}) do
        lowest = lowest or l.unit
        if not others and l.own < l.count then others = l.unit end
    end
    local market = A.MarketPrice(itemID)
    local prices = {
        -- (the lowest is ours: matched, never undercut)
        undercut = others and ((lowest < others) and lowest or Undercut(others)),
        match = lowest,
        market = market,
    }
    local presets = {}
    for _, p in ipairs(A.PRESETS) do
        if prices[p.key] then
            presets[#presets + 1] = { key = p.key, label = p.label, price = A.Round(math.max(prices[p.key], A.Floor(vendor))) }
        end
    end
    -- The setting's, else the first there is: undercut, match, market;
    -- with nothing known, three times what a vendor pays
    local want = A.Settings().pricing
    -- The last price set by hand for it: first, and where it starts
    local mine = A.MyPrice(itemID)
    if mine then
        table.insert(presets, 1, { key = "mine", label = "Your last price", price = mine })
        want = "mine"
    end
    local chosen
    for _, p in ipairs(presets) do
        if p.key == want then chosen = p end
    end
    chosen = chosen or presets[1]
    local price = chosen and chosen.price or A.Round(math.max((vendor or 0) * 3, A.Floor(vendor), 1))
    local warn
    if others and market and others < market * 0.7 then
        warn = "Lowest is " .. math.floor((1 - others / market) * 100 + 0.5) .. "% under its usual price"
    elseif not lowest and not market then
        warn = "No prices known: none listed, none scanned"
    end
    return price, presets, warn, chosen and chosen.key
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
IF.OnLogin(A.Prune)

---------------------------------------------------------------------------
-- Item tooltips: its usual price and the latest lowest; a bag stack's
-- whole, a unit's in brackets after it
---------------------------------------------------------------------------
local function TooltipPrices(tooltip, data)
    if not (IF.db and A.Settings().tooltip) then return end
    if tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip then return end
    local itemID = data and data.id
    if not itemID or (issecretvalue and issecretvalue(itemID)) or type(itemID) ~= "number" then return end
    local day, lowest = A.Latest(itemID)
    if not day then return end
    local market = A.MarketPrice(itemID)
    local ago = A.Today() - day
    -- A bag stack: what it all brings, a unit's after it
    local owner = tooltip:GetOwner()
    local stack = owner and owner.GetBagID and owner.GetID and C_Container and C_Container.GetContainerItemInfo
        and C_Container.GetContainerItemInfo(owner:GetBagID(), owner:GetID())
    local count = stack and stack.itemID == itemID and stack.stackCount or 1
    local function Price(unit)
        if count == 1 then return A.Money(unit) end
        return A.Money(unit * count) .. " |cff9d917a(" .. A.Money(unit) .. ")|r"
    end
    local r, g, b = 0.79, 0.64, 0.35
    local of = count > 1 and (" ×" .. count) or ""
    if market then tooltip:AddDoubleLine("Auction: usually" .. of, Price(market), r, g, b, 1, 1, 1) end
    tooltip:AddDoubleLine("Auction: lowest" .. of .. (ago == 0 and "" or ago == 1 and " (yesterday)" or (" (" .. ago .. " days ago)")),
        Price(lowest), r, g, b, 1, 1, 1)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        pcall(TooltipPrices, tooltip, data)
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "AUCTION_HOUSE_SHOW" then
        A.open = true
        if A.Available() and A.Settings().scan and A.ScanWait() == 0 then
            -- (once the frame has settled)
            C_Timer.After(1, function() A.Scan(true) end)
        end
        Changed()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        A.open = false
        search = nil
        -- A scan the server hasn't answered won't be now; one being read is finished
        if scan.state == "waiting" then scan.state = "idle" end
        Changed()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if scan.state == "waiting" then
            StartReading()
        elseif scan.state == "idle" and A.ScanWait() == 0 and A.Settings().scan then
            -- (another addon's full scan: the server's 15 minutes count from it)
            Realm().replicateAt = time()
            StartReading()
        end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        CommodityResults(arg)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        ItemResults(arg)
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        Send()
    end
end)
