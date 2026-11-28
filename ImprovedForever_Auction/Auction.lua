-- The auction house's prices, kept over time, per realm and house, in
-- ImprovedForeverAuctionDB: a full scan of every auction
-- (C_AuctionHouse.ReplicateItems, as the auction house opens, at most once
-- in 15 minutes: the server's limit) and a search of one item (the
-- auction window's tabs). Another addon's full scan is read too, when
-- none was in 15 minutes. Each is kept as the day's latest numbers per item:
-- its lowest price a unit, "now" (A.Market: what the cheapest ask, the
-- odd one far under them left out), how many are up. A.Suggest prices an
-- item from them; the Auction tab (AuctionEditor.lua) sets how.
local IF = ImprovedForever

local A = {}
IF.Auction = A

local AH = C_AuctionHouse
local DAY = 86400
local REPLICATE_EVERY = 15 * 60   -- the server's own limit on full scans
local CHUNK = 2000                -- auctions read a frame (a scan can be many thousands)
-- The houses: Alliance, Horde, neutral (Booty Bay, Gadgetzan, Everlook),
-- each its own market; their cut of a sale
local CUTS = { A = 0.05, H = 0.05, N = 0.15 }
local SEARCH_TIMEOUT = 8

local DEFAULTS = {
    scan = true,           -- a full scan as the auction house opens
    undercut = "1",        -- under the lowest: copper ("1", "100") or a share ("1%", "5%")
    pricing = "undercut",  -- the price it starts at: undercut, match, market
    duration = 2,          -- 1 / 2 / 3: the game's three (A.Durations)
    vendorFloor = true,    -- never under what a vendor pays (after the cut)
    tooltip = true,        -- item tooltips show the usual price, now and the lowest
    buy = true,            -- our auction window (AuctionBuyClassic.lua); off: the game's
    buyUsable = false,     -- its filters: usable only, qualities (none ticked: any), up to my level, sort
    buyMyLevel = false,
    buySort = "price",
    tasksTracker = true,   -- tasks tracked in the objective tracker (Tasks.lua)
    buyUpgrades = "mark",  -- upgrades (Upgrades.lua) in it: off, mark (an arrow), only
    destroy = true,        -- junk (ItemValue.lua) is never what sells better here than to a vendor
    share = 25,            -- "sells better here": by this many percent over a vendor's pay
    minGain = 100,         -- and by at least this much (copper)
    bargainShare = 30,     -- Buy's Bargains: listed this many percent or more under now or the usual price
    belowMin = 0,          -- Buy's Below vendor price: gaining this much copper or more an item
    keepDays = 30,         -- days of prices kept
    chartDays = 14,        -- days the charts show (and the usual price covers)
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

local FACTION_HOUSE = { Alliance = "A", Horde = "H" }
A.HOUSE_NAMES = { A = "Alliance", H = "Horde", N = "Neutral" }

-- The player's faction's house (nil until the game knows the faction)
local function PlayerHouse()
    return FACTION_HOUSE[UnitFactionGroup("player")]
end

---------------------------------------------------------------------------
-- The store: realms[realm].houses[house] holds a house's prices:
-- items[itemID][day] = "lowest:now:quantity" (":f": few listed), the
-- day's last whole view of it; scannedAt, myPrices, sold, watched (Sales);
-- image: the last full scan, { at, owners = { name }, items = { [itemID] =
-- "owner,count,minBid,buyout,band;..." } } (owner: its index in owners, 0
-- none given; band: GetReplicateItemTimeLeft's, "" none).
-- realms[realm].lastHouse: the house open last. The server's limit on full
-- scans is the account's: replicateAt at the top.
---------------------------------------------------------------------------
local function Today()
    return math.floor(time() / DAY)
end
A.Today = Today

local function DB()
    ImprovedForeverAuctionDB = ImprovedForeverAuctionDB or {}
    return ImprovedForeverAuctionDB
end

-- A house's prices into another's, a day both have taken from the one
-- scanned last. Its Bargains and Below vendor price go; the next scan
-- makes them anew.
local function Merge(from, to)
    to.items = to.items or {}
    local newer = (from.scannedAt or 0) > (to.scannedAt or 0)
    for itemID, days in pairs(from.items or {}) do
        local into = to.items[itemID]
        if not into then
            to.items[itemID] = days
        else
            for day, packed in pairs(days) do
                if newer or not into[day] then into[day] = packed end
            end
        end
    end
    for itemID, price in pairs(from.myPrices or {}) do
        to.myPrices = to.myPrices or {}
        if newer or not to.myPrices[itemID] then to.myPrices[itemID] = price end
    end
    to.scannedAt = math.max(to.scannedAt or 0, from.scannedAt or 0)
end

-- A realm kept before the houses were told apart (its prices beside
-- `houses`): into the player's faction's house, the scan limit to the top.
-- false: the faction not known yet
local function Migrate(realm)
    if realm.items == nil then return true end
    local house = PlayerHouse()
    if not house then return false end
    realm.houses = realm.houses or {}
    realm.houses[house] = realm.houses[house] or { items = {} }
    Merge(realm, realm.houses[house])
    local db = DB()
    db.replicateAt = math.max(db.replicateAt or 0, realm.replicateAt or 0)
    realm.items, realm.scannedAt, realm.myPrices, realm.bargains, realm.belowVendor, realm.replicateAt =
        nil, nil, nil, nil, nil, nil
    return true
end

-- Realms kept under no name (the game named none): they join the realm's
-- once it has one, house by house. false: the faction not known yet
local UNNAMED = { "", "?" }
local function Adopt(realms, name)
    for _, old in ipairs(UNNAMED) do
        local from = realms[old]
        if from and old ~= name then
            local to = realms[name] or { houses = {} }
            if not (Migrate(from) and Migrate(to)) then return false end
            realms[name] = to
            to.houses = to.houses or {}
            for house, prices in pairs(from.houses or {}) do
                to.houses[house] = to.houses[house] or { items = {} }
                Merge(prices, to.houses[house])
            end
            to.lastHouse = to.lastHouse or from.lastHouse
            realms[old] = nil
        end
    end
    return true
end
A.Adopt = Adopt

-- When a realm was scanned last (any of its houses)
local function ScannedAt(realm)
    local at = realm.scannedAt or 0
    for _, prices in pairs(realm.houses or {}) do at = math.max(at, prices.scannedAt or 0) end
    return at
end

-- The realm scanned last, of those named
local function Newest(realms)
    local best, at
    for name, realm in pairs(realms) do
        if name ~= "" and name ~= "?" and ScannedAt(realm) >= (at or -1) then
            best, at = name, ScannedAt(realm)
        end
    end
    return best
end

-- The game's name for the realm can come back empty: then the one it last
-- gave (or the one scanned last) holds the prices, and the chat says so once
local realmName, adopted, warned
local function Realm()
    local store = DB()
    store.realms = store.realms or {}
    if not realmName then
        local name = GetNormalizedRealmName and GetNormalizedRealmName() or ""
        if name ~= "" then realmName, store.lastRealm = name, name end
    end
    if realmName and not adopted then adopted = Adopt(store.realms, realmName) end
    local name = realmName
    if not name then
        name = store.lastRealm or Newest(store.realms) or "?"
        if not warned then
            warned = true
            IF.Print("auction: the game gives no realm name; prices are kept under " .. name .. ".")
        end
    end
    store.realms[name] = store.realms[name] or { houses = {} }
    local realm = store.realms[name]
    Migrate(realm)
    -- (Bargains and Below vendor price are made from the image: saved lists go)
    for _, prices in pairs(realm.houses or {}) do prices.bargains, prices.belowVendor = nil, nil end
    return realm
end

-- The house open now, else the one open last, else the player's
-- faction's: "A", "H" or "N"
function A.House()
    return A.house or Realm().lastHouse or PlayerHouse() or "N"
end

-- The house's cut of a sale
function A.Cut()
    return CUTS[A.House()]
end

-- The prices of a house (default: A.House()'s)
local function Store(house)
    local realm = Realm()
    house = house or A.House()
    realm.houses = realm.houses or {}
    realm.houses[house] = realm.houses[house] or { items = {} }
    return realm.houses[house]
end
A.Store = Store

-- What a search found this session, newer than the image: [house][itemID] = { { unit, count } }
local searched = { A = {}, H = {}, N = {} }

-- A day the item was searched for and none were up
local NONE = "-"

-- lowest, now, quantity, few (all nil: none listed). (Days kept before
-- "now" was hold the cheapest quarter's average in its place, and a
-- number where "f" is.)
local function Unpack(s)
    local lowest, now, qty, few = strsplit(":", s)
    return tonumber(lowest), tonumber(now), tonumber(qty), few == "f"
end

-- Its numbers as last seen today (nil: none listed)
function A.Record(itemID, lowest, now, qty, few)
    local items = Store().items
    local days = items[itemID] or {}
    items[itemID] = days
    days[Today()] = lowest and (lowest .. ":" .. now .. ":" .. qty .. (few and ":f" or "")) or NONE
end

-- Searched for today and none up
function A.NoneListed(itemID)
    local days = Store().items[itemID]
    return days ~= nil and days[Today()] == NONE
end

---------------------------------------------------------------------------
-- "Now": what the item sells for at the moment, from listings
-- { { unit, count } } sorted cheapest first, after TSM's AuctionDB market
-- value with a robust cut ahead of it. The auction house shows only what
-- is asked, so only the cheapest count:
-- 1. Units far under the rest (under the median of all units less 3 MADs,
--    a MAD at least 5% of the median) go, while together under 20% of the
--    units; more of them, and they are the market.
-- 2. Of the rest, the cheapest 30% of the units; once 15% are in, a step up
--    of 20% or more ends it.
-- 3. Units more than 1.5 standard deviations off those's mean go; the
--    rest's mean is it.
-- Under 3 listings or 10 units: the lowest, "few".
---------------------------------------------------------------------------
local CUT_MADS, CUT_SHARE, MAD_MIN = 3, 0.2, 0.05
local WINDOW, WINDOW_FROM, STEP = 0.3, 0.15, 1.2
local SPREAD = 1.5
local FEW_LISTINGS, FEW_UNITS = 3, 10

-- The k-th cheapest unit's price
local function UnitAt(list, k)
    for _, l in ipairs(list) do
        if k <= l[2] then return l[1] end
        k = k - l[2]
    end
end

local function Median(list, total)
    return (UnitAt(list, math.floor((total + 1) / 2)) + UnitAt(list, math.ceil((total + 1) / 2))) / 2
end

-- now, the first listing the cut keeps (its index), the units, few
function A.Market(list)
    local total = 0
    for _, l in ipairs(list) do total = total + l[2] end
    if #list < FEW_LISTINGS or total < FEW_UNITS then return list[1][1], 1, total, true end
    -- 1.
    local median = Median(list, total)
    local off = {}
    for i, l in ipairs(list) do off[i] = { math.abs(l[1] - median), l[2] } end
    table.sort(off, function(a, b) return a[1] < b[1] end)
    local under = median - CUT_MADS * math.max(Median(off, total), median * MAD_MIN)
    local kept, cut = 1, 0
    while kept <= #list and list[kept][1] < under do
        cut, kept = cut + list[kept][2], kept + 1
    end
    if cut >= total * CUT_SHARE then kept, cut = 1, 0 end
    -- 2.
    local rest = total - cut
    local most = math.max(1, math.floor(rest * WINDOW))
    local window, got, prev = {}, 0, nil
    for i = kept, #list do
        local l = list[i]
        if got >= most or (prev and got >= rest * WINDOW_FROM and l[1] >= prev * STEP) then break end
        local take = math.min(l[2], most - got)
        window[#window + 1] = { l[1], take }
        got, prev = got + take, l[1]
    end
    -- 3.
    local sum = 0
    for _, w in ipairs(window) do sum = sum + w[1] * w[2] end
    local mean, spread = sum / got, 0
    for _, w in ipairs(window) do spread = spread + (w[1] - mean) ^ 2 * w[2] end
    spread = math.sqrt(spread / got)
    local n
    sum, n = 0, 0
    for _, w in ipairs(window) do
        if math.abs(w[1] - mean) <= SPREAD * spread then sum, n = sum + w[1] * w[2], n + w[2] end
    end
    return math.floor(sum / n + 0.5), kept, total, false
end

-- The day's numbers from listings { { unit, count } }: lowest, now, total, few
local function Summarize(list)
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local now, _, total, few = A.Market(list)
    return list[1][1], now, total, few
end

-- The item's days over the last `days`, oldest first: { { day, lowest, now, qty } }
-- (house: default A.House(), as for the functions after it)
function A.History(itemID, days, house)
    local list = {}
    local item = Store(house).items[itemID]
    if not item then return list end
    local from = Today() - (days or A.Settings().chartDays)
    for day, packed in pairs(item) do
        if day > from then
            local lowest, now, qty = Unpack(packed)
            if lowest then list[#list + 1] = { day = day, lowest = lowest, now = now, qty = qty } end
        end
    end
    table.sort(list, function(a, b) return a.day < b.day end)
    return list
end

-- Its usual price: the median of the days' "now" over the chart's days
function A.MarketPrice(itemID, days, house)
    local values = {}
    for _, d in ipairs(A.History(itemID, days, house)) do values[#values + 1] = d.now end
    if #values == 0 then return nil end
    table.sort(values)
    local mid = (#values + 1) / 2
    return math.floor((values[math.floor(mid)] + values[math.ceil(mid)]) / 2 + 0.5), #values
end

-- Its latest day's "now" against the median of the days before it, over the chart's days:
-- "rising +12%" / "falling -8%" in its colour, "steady +2%" in grey within 5%; nil when known for under 4 days
local TREND_DAYS, TREND_MIN = 4, 5
function A.TrendText(itemID)
    local days = A.History(itemID)
    if #days < TREND_DAYS then return nil end
    local values = {}
    for i = 1, #days - 1 do values[i] = days[i].now end
    table.sort(values)
    local mid = (#values + 1) / 2
    local before = (values[math.floor(mid)] + values[math.ceil(mid)]) / 2
    if before <= 0 then return nil end
    local pct = math.floor((days[#days].now / before - 1) * 100 + 0.5)
    if math.abs(pct) < TREND_MIN then return "|cff9d917asteady " .. (pct >= 0 and "+" or "") .. pct .. "%|r" end
    return pct > 0 and ("|cffe0a050rising +" .. pct .. "%|r") or ("|cff7fb0e0falling " .. pct .. "%|r")
end

-- What it brings a unit here after the cut, at its usual price (nil: unknown)
function A.UnitNet(itemID)
    local market = A.MarketPrice(itemID)
    return market and market * (1 - A.Cut()) or nil
end

-- Its latest day with prices: day, lowest, now, quantity, few
-- (nil: never seen up)
function A.Latest(itemID, house)
    local item = Store(house).items[itemID]
    local last
    for day, packed in pairs(item or {}) do
        if packed ~= NONE and (not last or day > last) then last = day end
    end
    if not last then return nil end
    return last, Unpack(item[last])
end

-- The item in each house with prices, the house open (or open last) first:
-- { { house, usual, now, lowest, age (days since its latest day), cut } }
local HOUSES = { "A", "H", "N" }
function A.AcrossHouses(itemID)
    local list, here = {}, A.House()
    for _, house in ipairs(HOUSES) do
        local day, lowest, now = A.Latest(itemID, house)
        if day then
            list[#list + 1] = { house = house, usual = A.MarketPrice(itemID, nil, house), now = now, lowest = lowest,
                age = Today() - day, cut = CUTS[house] }
        end
    end
    table.sort(list, function(a, b)
        if (a.house == here) ~= (b.house == here) then return a.house == here end
        return a.house < b.house
    end)
    return list
end

-- For other modules and addons (ImprovedForever.Auction.Price), a unit in
-- copper: "now" on its latest day, its usual price (A.MarketPrice) and the
-- days since that day. nil: never seen.
function A.Price(itemID)
    if type(itemID) ~= "number" or not IF.db then return nil end
    local day, _, now = A.Latest(itemID)
    if not day then return nil end
    return now, A.MarketPrice(itemID), Today() - day
end

-- Days older than kept go, and items left with none
function A.Prune()
    local from = Today() - A.Settings().keepDays
    for _, realm in pairs(DB().realms or {}) do
        -- (a realm not migrated yet: its prices beside the houses)
        for _, prices in pairs(realm.houses or { realm }) do
            for _, byItem in ipairs({ prices.items or {}, prices.sold or {} }) do
                for itemID, days in pairs(byItem) do
                    for day in pairs(days) do
                        if day <= from then days[day] = nil end
                    end
                    if next(days) == nil then byItem[itemID] = nil end
                end
            end
            for day in pairs(prices.watched or {}) do
                if day <= from then prices.watched[day] = nil end
            end
        end
    end
end

-- How many items the house has prices for, and when it was last scanned
function A.Stats()
    local prices = Store()
    local n = 0
    for _ in pairs(prices.items) do n = n + 1 end
    return n, prices.scannedAt
end

-- A time() as "5 min ago" ("never": nil)
function A.Ago(at)
    if not at then return "never" end
    local s = math.max(0, time() - at)
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " days ago"
end

function A.Clear()
    local prices = Store()
    prices.items, prices.scannedAt, prices.image, prices.sold, prices.watched = {}, nil, nil, nil, nil
    wipe(searched[A.House()])
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

-- When the server lets this account scan again (seconds from now; 0: now)
function A.ScanWait()
    local at = DB().replicateAt or 0
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
    DB().replicateAt = time()
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

-- An image's auctions of an item: { seller (false: none given), count, minBid, buyout, band }
local function Auctions(image, itemID)
    local list = {}
    for entry in (image.items[itemID] or ""):gmatch("[^;]+") do
        local o, count, minBid, buyout, band = strsplit(",", entry)
        list[#list + 1] = { o ~= "0" and image.owners[tonumber(o)] or false, tonumber(count), tonumber(minBid),
            tonumber(buyout), tonumber(band) }
    end
    return list
end

-- The item's listings with a buyout, { { unit, count } }: its search's,
-- else the house's image's (nil: neither has it)
local function Listings(itemID)
    local found = searched[A.House()][itemID]
    if found then return found end
    local image = Store().image
    if not (image and image.items[itemID]) then return nil end
    local list = {}
    for _, a in ipairs(Auctions(image, itemID)) do
        if a[4] > 0 then list[#list + 1] = { a[4] / a[2], a[2] } end
    end
    return list
end

-- The items of the house's image and its searches (none without an image:
-- the categories need a full scan)
local function ImageItems()
    local image = Store().image
    if not image then return {} end
    local ids = {}
    for itemID in pairs(image.items) do ids[itemID] = true end
    for itemID in pairs(searched[A.House()]) do ids[itemID] = true end
    return ids
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
    for itemID in pairs(ImageItems()) do
        local b = BelowVendor(itemID, Listings(itemID))
        if b and b.each > 0 and b.each >= least then
            list[#list + 1] = { itemKey = AH.MakeItemKey(itemID), totalQuantity = b.units, minPrice = b.lowest,
                each = b.each, count = b.count }
        end
    end
    table.sort(list, function(a, b) return a.each > b.each end)
    return list
end

-- Bargains: listings well under what the item sells for. Against "now":
-- the odd few A.Market leaves out, far under the rest (a first scan
-- shows them); against its usual price: any, once that is known for
-- BARGAIN_DAYS days. Made from the image and searches, kept this session
-- (Bargained): { usual, now, kept (the price the cut keeps from), listings
-- BARGAIN_KEEP or more under either }, so A.Bargains can take any of the
-- setting's shares. nil: none.
-- (BARGAIN_KEEP: the smallest share Bargains at offers, AuctionEditor.lua)
local BARGAIN_DAYS, BARGAIN_KEEP = 3, 0.2
A.BARGAIN_DAYS = BARGAIN_DAYS

-- What a price is a bargain against, share or more under it: ref, "now" / "usual"
local function Against(b, price, share)
    if b.now and price < b.kept and price <= b.now * (1 - share) then return b.now, "now" end
    if b.usual and price <= b.usual * (1 - share) then return b.usual, "usual" end
end

local function Bargain(itemID, list)
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local usual, days = A.MarketPrice(itemID)
    if usual and days < BARGAIN_DAYS then usual = nil end
    local now, kept, _, few = A.Market(list)
    local b = { usual = usual, now = not few and kept > 1 and now or nil, kept = list[kept][1], listings = {} }
    for _, l in ipairs(list) do
        if Against(b, l[1], BARGAIN_KEEP) then b.listings[#b.listings + 1] = { math.ceil(l[1]), l[2] } end
    end
    return #b.listings > 0 and b or nil
end

-- The item's Bargain, made once per image and search ([image][itemID] =
-- bargain or false; weak: a replaced image's go)
local bargained = setmetatable({}, { __mode = "k" })
local function Bargained(itemID)
    local image = Store().image
    if not image then return nil end
    bargained[image] = bargained[image] or {}
    local made = bargained[image]
    if made[itemID] == nil then
        local list = Listings(itemID)
        made[itemID] = list and #list > 0 and Bargain(itemID, list) or false
    end
    return made[itemID] or nil
end

-- A price of the item against the last scan's bargains (else its usual
-- price): ref, "now" / "usual"; nil: no bargain at the setting's share
function A.BargainAgainst(itemID, price)
    local share = A.Settings().bargainShare / 100
    local b = Bargained(itemID)
    if b then return Against(b, price, share) end
    local usual, days = A.MarketPrice(itemID)
    if usual and days >= BARGAIN_DAYS then return Against({ usual = usual }, price, share) end
end

-- The Buy tab's "Bargains": what is listed at least the setting's share
-- under now or its usual price, as browse results, the most saved first
function A.Bargains()
    local share = A.Settings().bargainShare / 100
    local list = {}
    for itemID in pairs(ImageItems()) do
        local b = Bargained(itemID)
        local units, saving, lowest, ref, against = 0, 0, nil, nil, nil
        for _, l in ipairs(b and b.listings or {}) do
            local r, what = Against(b, l[1], share)
            if r then
                units, saving = units + l[2], saving + (r - l[1]) * l[2]
                if not lowest or l[1] < lowest then lowest, ref, against = l[1], r, what end
            end
        end
        if units > 0 then
            list[#list + 1] = { itemKey = AH.MakeItemKey(itemID), totalQuantity = units, minPrice = lowest,
                saving = math.floor(saving), ref = ref, against = against }
        end
    end
    table.sort(list, function(a, b) return a.saving > b.saving end)
    return list
end

---------------------------------------------------------------------------
-- Sales, from two full scans' images (as Auctioneer's Stat-Purchased): an
-- auction gone before its time could have run out was bought. Its time
-- left band says how long it had at least: the end of the band below
-- (auctions of 2, 8 and 24 hours; bands to 30 min, 2 h, 8 h, 24 h).
-- A seller's auction gone as the same seller lists the item cheaper is a
-- cancel; one come back with fewer at its price was partly bought. Other
-- cancels count as sales: an upper bound, good for fast against slow.
-- Kept per house: sold[itemID][day] = units, watched[day] = seconds the
-- scans compared covered.
---------------------------------------------------------------------------
local AT_LEAST = { [0] = 0, [1] = 1800, [2] = 7200, [3] = 28800 }
local WATCH_MAX = AT_LEAST[3]

local function Key(a, seller)
    return tostring(seller) .. "," .. a[2] .. "," .. a[3] .. "," .. a[4]
end

-- Units of the item bought between the images, elapsed seconds apart
local function SoldBetween(old, new, itemID, elapsed)
    -- (still up: by seller and the rest; whoever's, by the rest alone)
    local up, any = {}, {}
    local now = Auctions(new, itemID)
    for _, a in ipairs(now) do
        local k, loose = Key(a, a[1]), Key(a, false)
        up[k], any[loose] = (up[k] or 0) + 1, (any[loose] or 0) + 1
    end
    local gone = {}
    for _, a in ipairs(Auctions(old, itemID)) do
        local k, loose = Key(a, a[1]), Key(a, false)
        if (up[k] or 0) > 0 then
            up[k], any[loose] = up[k] - 1, any[loose] - 1
        elseif a[1] and (up[loose] or 0) > 0 then
            -- (still up, its seller not given this time)
            up[loose], any[loose] = up[loose] - 1, any[loose] - 1
        elseif not a[1] and (any[loose] or 0) > 0 then
            -- (its seller not given last time: anyone's like it)
            any[loose] = any[loose] - 1
        else
            gone[#gone + 1] = a
        end
    end
    -- (listed since: by seller, to tell cancels and part buys)
    local fresh = {}
    for _, a in ipairs(now) do
        local k = Key(a, a[1])
        if a[1] and (up[k] or 0) > 0 then
            up[k] = up[k] - 1
            fresh[a[1]] = fresh[a[1]] or {}
            table.insert(fresh[a[1]], a)
        end
    end
    local sold = 0
    for _, a in ipairs(gone) do
        -- (one without a buyout gone early: cancelled, a bid wins only at its end)
        local least = a[5] and AT_LEAST[a[5]]
        if a[4] > 0 and least and elapsed < least then
            local units, unit = a[2], a[4] / a[2]
            for _, f in ipairs(a[1] and fresh[a[1]] or {}) do
                local each = f[4] / f[2]
                if each < unit then units = 0 break end
                if each == unit and f[2] < a[2] then units = math.min(units, a[2] - f[2]) end
            end
            sold = sold + units
        end
    end
    return sold
end

-- Sales between the house's last image and this scan's, into its days
local function RecordSales(prices, new)
    local old = prices.image
    local elapsed = old and old.at and new.at - old.at
    if not elapsed or elapsed <= 0 or elapsed > WATCH_MAX then return end
    local day = Today()
    prices.watched = prices.watched or {}
    prices.watched[day] = (prices.watched[day] or 0) + elapsed
    for itemID in pairs(old.items) do
        local n = SoldBetween(old, new, itemID, elapsed)
        if n > 0 then
            prices.sold = prices.sold or {}
            local days = prices.sold[itemID] or {}
            prices.sold[itemID] = days
            days[day] = (days[day] or 0) + n
        end
    end
end

-- Units sold over the last `days` (default the chart's) and the hours the
-- scans watched in them (nil: never watched)
function A.Sold(itemID, days)
    local prices = Store()
    local from = Today() - (days or A.Settings().chartDays)
    local units, watched = 0, 0
    for day, s in pairs(prices.watched or {}) do
        if day > from then watched = watched + s end
    end
    if watched == 0 then return nil end
    for day, n in pairs(prices.sold and prices.sold[itemID] or {}) do
        if day > from then units = units + n end
    end
    return units, watched / 3600
end

-- How fast it sells here, sold a day against how many are up: "sells fast"
-- (a day sells what is up), "sells steadily" (a quarter of it), "sells
-- slowly", in its colour; nil: scans watched it under WATCH_MIN hours
local WATCH_MIN, FAST, STEADY = 2, 1, 0.25
function A.SaleText(itemID)
    local units, hours = A.Sold(itemID)
    if not units or hours < WATCH_MIN then return nil end
    local _, _, _, up = A.Latest(itemID)
    local share = units * 24 / hours / math.max(1, up or 0)
    if share >= FAST then return "|cff5fd35fsells fast|r" end
    if share >= STEADY then return "|cffd8ccb0sells steadily|r" end
    return "|cff9d917asells slowly|r"
end

local function FinishScan()
    reader:Hide()
    local items = 0
    for itemID, list in pairs(scan.byItem or {}) do
        A.Record(itemID, Summarize(list))
        items = items + 1
    end
    local image = {}
    for itemID, list in pairs(scan.image) do image[itemID] = table.concat(list, ";") end
    local prices = Store()
    prices.scannedAt = time()
    -- (an empty scan is the server's failure, not an empty house)
    if scan.read > 0 then
        local new = { at = scan.at, owners = scan.owners, items = image }
        -- ponytail: every item compared in this one frame, in chunks like the reading if it stutters
        RecordSales(prices, new)
        prices.image = new
        wipe(searched[A.House()])
    end
    IF.Print("auction scan done: " .. (scan.read or 0) .. " auctions, " .. items .. " items priced.")
    scan.state, scan.byItem, scan.image, scan.owners, scan.ownerOf = "idle", nil, nil, nil, nil
    Changed()
end

reader:SetScript("OnUpdate", function()
    local last = math.min(scan.total - 1, scan.read + CHUNK - 1)
    local byItem, image, owners, ownerOf = scan.byItem, scan.image, scan.owners, scan.ownerOf
    for i = scan.read, last do
        -- name, texture, count, quality, usable, level, levelType, minBid,
        -- minIncrement, buyout, bid, highBidder, bidderFull, owner,
        -- ownerFull, saleStatus, itemID
        local _, _, count, _, _, _, _, minBid, _, buyout, _, _, _, owner, _, _, itemID = AH.GetReplicateItemInfo(i)
        if itemID and count and count > 0 then
            if buyout and buyout > 0 then
                local list = byItem[itemID]
                if not list then
                    list = {}
                    byItem[itemID] = list
                end
                list[#list + 1] = { buyout / count, count }
            end
            -- (the image: every auction, its seller a number, 0: none given)
            local o = 0
            if owner and owner ~= "" then
                o = ownerOf[owner]
                if not o then
                    owners[#owners + 1] = owner
                    o = #owners
                    ownerOf[owner] = o
                end
            end
            local list = image[itemID]
            if not list then
                list = {}
                image[itemID] = list
            end
            list[#list + 1] = o .. "," .. count .. "," .. (minBid or 0) .. "," .. (buyout or 0) .. ","
                .. (AH.GetReplicateItemTimeLeft(i) or "")
        end
    end
    scan.read = last + 1
    if scan.read >= scan.total then FinishScan() end
end)

local function StartReading()
    scan.state, scan.read, scan.byItem, scan.at = "reading", 0, {}, time()
    scan.image, scan.owners, scan.ownerOf = {}, {}, {}
    scan.total = AH.GetNumReplicateItems() or 0
    if scan.total == 0 then return FinishScan() end
    reader:Show()
end

---------------------------------------------------------------------------
-- A search for one item: fn(listings) once its results are in (nil: no
-- answer); listings: { { unit, count, own, auctionID (, total, link,
-- itemLevel: an item's) } }, cheapest first. Its numbers
-- are kept too. Auctions bought this visit are left out (A.MarkBought).
---------------------------------------------------------------------------
local search
local bought = {}   -- auctionID -> true: the server lists them a moment longer

function A.MarkBought(auctionID)
    bought[auctionID] = true
end

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

-- all: every listing of the item, kept as the day's state (a key of gear
-- holds all its versions); shown: what the caller gets (default all)
local function Answer(all, shown)
    local s = search
    search = nil
    shown = shown or all
    local plain = {}
    for i, l in ipairs(all) do plain[i] = { l.unit, l.count } end
    searched[A.House()][s.itemID] = plain
    local image = Store().image
    if image and bargained[image] then bargained[image][s.itemID] = nil end
    if #plain > 0 then A.Record(s.itemID, Summarize(plain)) else A.Record(s.itemID) end
    Changed()
    table.sort(shown, function(a, b) return a.unit < b.unit end)
    s.fn(shown)
end

-- (results come before ours is sent too: the client's own, a purchase's
-- refresh, its auctions as they were; only an answer to ours is taken.
-- The server sends a long list in parts: the rest is asked for first.)
local function CommodityResults(itemID)
    if not (search and search.sent and search.commodity and search.itemID == itemID) then return end
    if AH.HasFullCommoditySearchResults and not AH.HasFullCommoditySearchResults(itemID) then
        AH.RequestMoreCommoditySearchResults(itemID)
        return
    end
    local listings = {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.quantity > 0 and not bought[r.auctionID] then
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
    if AH.HasFullItemSearchResults and not AH.HasFullItemSearchResults(itemKey) then
        AH.RequestMoreItemSearchResults(itemKey)
        return
    end
    local all, sameLevel = {}, {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and r.quantity > 0 and not bought[r.auctionID] then
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
    Answer(all, #sameLevel > 0 and sameLevel or nil)
end

-- The price last set by hand for an item (a unit), per house: where its
-- next sale starts
function A.MyPrice(itemID)
    local mine = Store().myPrices
    return mine and mine[itemID]
end

function A.SetMyPrice(itemID, price)
    local prices = Store()
    prices.myPrices = prices.myPrices or {}
    prices.myPrices[itemID] = price
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
    return math.ceil(vendor / (1 - A.Cut()))
end

function A.Suggest(itemID, listings, vendor)
    -- The lowest anyone else asks; the lowest of all (ours may be under it);
    -- the odd few far under the rest left out (A.Market's cut)
    listings = listings or {}
    local plain = {}
    for i, l in ipairs(listings) do plain[i] = { l.unit, l.count } end
    local kept = #plain > 0 and select(2, A.Market(plain)) or 1
    local others, lowest
    for i = kept, #listings do
        local l = listings[i]
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
    elseif kept > 1 then
        warn = "Left out " .. (kept - 1) .. " listed far under the rest (from " .. A.Money(listings[1].unit) .. ")"
    end
    return price, presets, warn, chosen and chosen.key
end

---------------------------------------------------------------------------
-- The player's own sales per house, from their auctions as the house
-- lists them (asked as it opens): one seen is posted; Sold, or gone before
-- its end, sold; gone after it, expired; cancelled here, cancelled.
-- Kept: mine[auctionID] = "itemID:quantity:endsAt:sold" (1: counted sold),
-- own[itemID] = "posted:sold:expired:cancelled"
---------------------------------------------------------------------------
local SOLD = Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1
local POSTED, BOUGHT, EXPIRED, CANCELLED = 1, 2, 3, 4

local function Count(prices, itemID, what, n)
    prices.own = prices.own or {}
    local c = { strsplit(":", prices.own[itemID] or "0:0:0:0") }
    c[what] = tonumber(c[what]) + n
    prices.own[itemID] = table.concat(c, ":")
end

-- Its auctions here: posted, sold, expired, cancelled (nil: none seen)
function A.Own(itemID)
    local own = Store().own
    local s = own and own[itemID]
    if not s then return nil end
    local posted, sold, expired, cancelled = strsplit(":", s)
    return tonumber(posted), tonumber(sold), tonumber(expired), tonumber(cancelled)
end

local function OwnedUpdated()
    if not (A.IsOpen() and AH.GetOwnedAuctions) then return end
    local prices, now = Store(), time()
    prices.mine = prices.mine or {}
    local mine, seen = prices.mine, {}
    for _, a in ipairs(AH.GetOwnedAuctions() or {}) do
        local id, itemID, qty = a.auctionID, a.itemKey and a.itemKey.itemID, a.quantity or 1
        if id and itemID then
            seen[id] = true
            local ends = now + (a.timeLeftSeconds or AT_LEAST[a.timeLeft] or 0)
            local kept = mine[id]
            local _, had, endsAt, counted = strsplit(":", kept or "")
            had, endsAt, counted = tonumber(had), tonumber(endsAt), counted == "1"
            if not kept then Count(prices, itemID, POSTED, qty) end
            -- (fewer left: those bought)
            if had and qty < had and not counted then Count(prices, itemID, BOUGHT, had - qty) end
            if a.status == SOLD and not counted then
                Count(prices, itemID, BOUGHT, qty)
                counted = true
            end
            mine[id] = itemID .. ":" .. qty .. ":" .. math.max(endsAt or 0, ends) .. ":" .. (counted and 1 or 0)
        end
    end
    for id, kept in pairs(mine) do
        if not seen[id] then
            local itemID, qty, endsAt, counted = strsplit(":", kept)
            itemID, qty = tonumber(itemID), tonumber(qty)
            if counted ~= "1" then Count(prices, itemID, now < tonumber(endsAt) and BOUGHT or EXPIRED, qty) end
            mine[id] = nil
        end
    end
end

local function Cancelled(auctionID)
    local prices = Store()
    local kept = prices.mine and prices.mine[auctionID]
    if not kept then return end
    local itemID, qty = strsplit(":", kept)
    Count(prices, tonumber(itemID), CANCELLED, tonumber(qty))
    prices.mine[auctionID] = nil
end

local own = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED" }) do
    pcall(own.RegisterEvent, own, event)
end
own:SetScript("OnEvent", function(_, event, arg)
    if event == "AUCTION_HOUSE_SHOW" then
        -- (after the scan's request, the server takes one at a time)
        C_Timer.After(2, function()
            if A.IsOpen() and AH.QueryOwnedAuctions then
                AH.QueryOwnedAuctions({ { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false } })
            end
        end)
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        OwnedUpdated()
    elseif event == "AUCTION_CANCELED" then
        Cancelled(arg)
    end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
IF.OnLogin(A.Prune)

---------------------------------------------------------------------------
-- Item tooltips: its usual price in each house on one line, the house open
-- (or open last) first; there "now" and the latest lowest; a bag stack's
-- whole, a unit's in brackets after it
---------------------------------------------------------------------------
local MARKS = { A = { "AllianceSymbol", "|cff4a8ff0A|r" }, H = { "HordeSymbol", "|cffe04a3aH|r" },
    N = { nil, "|cffd8ccb0N|r" } }
local OLD_DAYS = 3   -- a house's price this many days old or more: dimmed

-- The house's mark: its faction's symbol, else its letter
function A.HouseMark(house)
    local atlas, letter = MARKS[house][1], MARKS[house][2]
    if atlas and IF.HasAtlas and IF.HasAtlas(atlas) then return "|A:" .. atlas .. ":14:14|a" end
    return letter
end

-- Money short for a line of several: no copper beside gold
function A.ShortMoney(copper)
    return A.Money(copper >= 10000 and math.floor(copper / 100 + 0.5) * 100 or copper)
end

-- "[A] 1g 20s   [H] 1g 5s 2d": each house's usual price (else its latest
-- "now") times count, its age in days after it, dimmed when old
function A.HousesText(itemID, count)
    local parts = {}
    for _, h in ipairs(A.AcrossHouses(itemID)) do
        local text = A.ShortMoney((h.usual or h.now) * (count or 1)) .. (h.age > 0 and (" " .. h.age .. "d") or "")
        if h.age >= OLD_DAYS then text = "|cff9d917a" .. text .. "|r" end
        parts[#parts + 1] = A.HouseMark(h.house) .. " " .. text
    end
    return #parts > 0 and table.concat(parts, "   ") or nil
end

local function TooltipPrices(tooltip, data)
    if not (IF.db and A.Settings().tooltip) then return end
    if tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip then return end
    local itemID = data and data.id
    if not itemID or (issecretvalue and issecretvalue(itemID)) or type(itemID) ~= "number" then return end
    local day, lowest, now, _, few = A.Latest(itemID)
    local none = A.NoneListed(itemID)
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
    local houses = A.HousesText(itemID, count)
    if not houses and not none then return end
    if houses then tooltip:AddDoubleLine("Auction: usually" .. of, houses, r, g, b, 1, 1, 1) end
    if not day and not none then return end
    local trend, sells = A.TrendText(itemID), A.SaleText(itemID)
    local lately = trend and sells and (trend .. " · " .. sells) or trend or sells
    if lately then tooltip:AddDoubleLine("Auction: lately", lately, r, g, b) end
    if none then
        tooltip:AddDoubleLine("Auction: lowest", "none listed", r, g, b, 0.62, 0.57, 0.48)
        return
    end
    local ago = A.Today() - day
    local when = ago == 0 and "" or ago == 1 and " (yesterday)" or (" (" .. ago .. " days ago)")
    if now and not few and now ~= lowest then
        tooltip:AddDoubleLine("Auction: now" .. of .. when, Price(now), r, g, b, 1, 1, 1)
    end
    tooltip:AddDoubleLine("Auction: lowest" .. of .. when .. (few and " (few listed)" or ""), Price(lowest), r, g, b, 1, 1, 1)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        pcall(TooltipPrices, tooltip, data)
    end)
end

-- Probe: when the game's realm name comes back empty (IF.db.realmLog, at most 100 lines)
local function ProbeRealm(at)
    local log = IF.db and IF.db.realmLog
    if not log or #log >= 100 then return end
    local normalized = GetNormalizedRealmName and GetNormalizedRealmName()
    log[#log + 1] = ("%s %.1f %s: normalized=%q realm=%q"):format(date("%H:%M:%S"), GetTime() % 1000, at,
        tostring(normalized), tostring(GetRealmName()))
end
IF.OnLogin(function()
    IF.db.realmLog = IF.db.realmLog or {}
    IF.db.realmLog[#IF.db.realmLog + 1] = date("%Y-%m-%d %H:%M:%S") .. " login"
    ProbeRealm("login")
end)
local probe = CreateFrame("Frame")
probe:RegisterEvent("PLAYER_ENTERING_WORLD")
probe:RegisterEvent("AUCTION_HOUSE_SHOW")
probe:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
probe:SetScript("OnEvent", function(_, event) ProbeRealm(event) end)

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
    "ITEM_SEARCH_RESULTS_ADDED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "AUCTION_HOUSE_SHOW" then
        A.open = true
        -- (the auctioneer's faction: English tokens; a goblin's has none.
        -- No auctioneer to ask: the player's faction's)
        if UnitExists("npc") then
            A.house = FACTION_HOUSE[UnitFactionGroup("npc")] or "N"
        else
            A.house = PlayerHouse() or "N"
        end
        Realm().lastHouse = A.house
        if A.Available() and A.Settings().scan and A.ScanWait() == 0 then
            -- (once the frame has settled)
            C_Timer.After(1, function() A.Scan(true) end)
        end
        Changed()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        A.open = false
        search = nil
        wipe(bought)
        -- A scan the server hasn't answered won't be now; one being read is finished
        if scan.state == "waiting" then scan.state = "idle" end
        Changed()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if scan.state == "waiting" then
            StartReading()
        elseif scan.state == "idle" and A.ScanWait() == 0 and A.Settings().scan then
            -- (another addon's full scan: the server's 15 minutes count from it)
            DB().replicateAt = time()
            StartReading()
        end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
        CommodityResults(arg)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
        ItemResults(arg)
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        Send()
    end
end)
