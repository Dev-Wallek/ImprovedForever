-- Improved Forever: Bags & Bank. Every character of yours writes down its
-- bags and, at the banker, its bank (Record.lua, ImprovedForeverBagsDB);
-- a window like the game's bags shows them, any character's, anywhere
-- (Window.lua). Only to look at: the items themselves stay the game's.
local IF = ImprovedForever

-- ponytail: the game's bag icon, a drawn one of ours when the module gets art
IF.AddModule({ key = "bags", label = "Bags & Bank", icon = "Interface\\Icons\\INV_Misc_Bag_08", addon = ... })

local BG = {}
IF.Bags = BG

-- One slot as kept: "6948", "2589:20" (its count), or, when the item
-- carries more than its ID (an enchant, gems, random stats), its item
-- string and "#count" ("item:2036::::::1018:...#1"). Free of the game's API.
function BG.Slot(itemID, count, link)
    local itemString = link and link:match("|H(item:[^|]+)|h")
    if itemString then
        local f = {}
        for v in (itemString .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
        -- (item, ID, enchant, four gems, suffix: anything set beyond the ID)
        for i = 3, 8 do
            if f[i] and f[i] ~= "" and f[i] ~= "0" then
                return itemString .. (count > 1 and ("#" .. count) or "")
            end
        end
    end
    return count > 1 and (itemID .. ":" .. count) or tostring(itemID)
end

-- A kept slot back: itemID, count, link (the item string, or nil)
function BG.Unslot(s)
    local itemString, count = s:match("^(item:[^#]+)#?(%d*)$")
    if itemString then
        return tonumber(itemString:match("^item:(%d+)")), tonumber(count) or 1, itemString
    end
    local id, n = s:match("^(%d+):?(%d*)$")
    return tonumber(id), tonumber(n) or 1, nil
end
