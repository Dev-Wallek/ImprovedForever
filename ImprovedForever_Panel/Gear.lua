-- The panel's gear: the durability of the most worn item you wear, red
-- once it's about to break; its tooltip lists every worn one
local IF = ImprovedForever

local SLOTS = 19

-- { slot, share } of each worn item with durability, the most worn first
local function Worn()
    local list = {}
    for slot = 1, SLOTS do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then list[#list + 1] = { slot, cur / max } end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    return list
end

local function Color(share)
    if share < 0.25 then return "|cffff4040" end
    if share < 0.5 then return "|cffffb030" end
    return "|cffffffff"
end

IF.Panel.Add({
    key = "gear", label = "Gear",
    events = { "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" },
    text = function()
        local worst = Worn()[1]
        if not worst then return nil end
        return ("Gear %s%d%%|r"):format(Color(worst[2]), math.floor(worst[2] * 100))
    end,
    tip = function(tip)
        tip:AddLine("Gear")
        for _, w in ipairs(Worn()) do
            if w[2] < 1 then
                local link = GetInventoryItemLink("player", w[1])
                tip:AddDoubleLine(link or "?", Color(w[2]) .. math.floor(w[2] * 100) .. "%|r")
            end
        end
    end,
})
