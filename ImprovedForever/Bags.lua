-- L3 (the left stick click, not changeable) cleans up bags while any bag
-- frame is open. Off in the General tab: IF.db.bagSort = false.
local _, IF = ...

local DEFAULT_KEY = "PADLSTICK"

function IF.BagSortKey()
    return DEFAULT_KEY
end

local owner = CreateFrame("Frame", "ImprovedForeverBagsOwner")
local sortButton = CreateFrame("Button", "ImprovedForeverSortBags", UIParent)
sortButton:RegisterForClicks("AnyDown", "AnyUp")
sortButton:Hide()

local bound = false
local pending = false

-- A shoulder or trigger held (or a key modifier): the press is another's
-- (L2 + L3: L2 is the game's Shift, and an override binding on L3 alone
-- also answers SHIFT-L3 when nothing has that)
local SHOULDERS = { "PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER" }
local function Modified()
    if IsModifierKeyDown and IsModifierKeyDown() then return true end
    for _, key in ipairs(SHOULDERS) do
        if IsKeyDown and IsKeyDown(key) then return true end
    end
    return false
end

local function SortAllBags()
    if C_Container and C_Container.SortBags then
        C_Container.SortBags()
    elseif SortBags then
        SortBags()
    else
        IF.Print("bag sorting is not available on this client.")
        return
    end
    PlaySound(SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 or 852)
end

-- Sorts on the release; bound to one button alone, not when the press
-- began with one held under it (told on the press: the shoulder may be let
-- go first)
local modifiedPress = false
sortButton:SetScript("OnClick", function(_, _, down)
    if down then
        modifiedPress = not IF.BagSortKey():find("+", 1, true) and Modified()
        return
    end
    if down == nil and not IF.BagSortKey():find("+", 1, true) and Modified() then return end
    if modifiedPress then
        modifiedPress = false
        return
    end
    SortAllBags()
end)

-- The bag slot the game's cursor is on: bag, slot (nil: none)
function IF.FocusedBagSlot()
    local bag, slot
    pcall(function()
        local nav = _G.SmartNavigation
        local button = nav and nav.GetCurrentButton and nav:GetCurrentButton()
        for _, f in ipairs({ button, button and button:GetParent() }) do
            if f and f.GetBagID and f.GetID then
                local b, s = f:GetBagID(), f:GetID()
                if b and s and C_Container.GetContainerItemInfo(b, s) then
                    bag, slot = b, s
                    return
                end
            end
        end
    end)
    return bag, slot
end

local bagFrames = {}

local function AnyBagOpen()
    for _, frame in ipairs(bagFrames) do
        if frame:IsShown() then
            return true
        end
    end
    return false
end

local function UpdateBinding()
    local want = IF.db.bagSort ~= false and AnyBagOpen()
    if want == bound then
        pending = false
        return
    end
    if IF.InCombat() then
        -- Override bindings can't change in combat; retry on PLAYER_REGEN_ENABLED.
        pending = true
        return
    end
    pending = false
    if want then
        SetOverrideBindingClick(owner, true, IF.BagSortKey(), sortButton:GetName(), "LeftButton")
    else
        ClearOverrideBindings(owner)
    end
    bound = want
end

local function WatchFrame(frame)
    if not frame or frame.ImprovedForeverWatched then
        return
    end
    frame.ImprovedForeverWatched = true
    table.insert(bagFrames, frame)
    frame:HookScript("OnShow", UpdateBinding)
    frame:HookScript("OnHide", UpdateBinding)
end

local function WatchBagFrames()
    WatchFrame(_G.ContainerFrameCombinedBags)
    local count = NUM_CONTAINER_FRAMES or 13
    for i = 1, count do
        WatchFrame(_G["ContainerFrame" .. i])
    end
end

IF.UpdateBagBinding = UpdateBinding

IF.OnLogin(function()
    WatchBagFrames()
    UpdateBinding()
end)

owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:SetScript("OnEvent", function()
    if pending then
        UpdateBinding()
    end
end)

---------------------------------------------------------------------------
-- Destroying a bag item (the Destroy panel, the navigator's menu): picked
-- up and deleted with no game popup, so the caller asks for a hold first.
-- From a button press only, never in combat.
---------------------------------------------------------------------------
local blocked = false
local watch = CreateFrame("Frame")
watch:RegisterEvent("ADDON_ACTION_BLOCKED")
watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watch:SetScript("OnEvent", function(_, _, addon, fn)
    if type(addon) == "string" and addon:find("^ImprovedForever") and tostring(fn):find("DeleteCursorItem") then
        blocked = true
    end
end)

-- itemID: the item that must still be there; say: the outcome in the chat
-- -> true when destroyed; else false, whether the game blocked it
function IF.DestroyItem(bag, slot, itemID, say)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.itemID ~= itemID or info.isLocked or IF.InCombat() then return false, false end
    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    if not CursorHasItem() then return false, false end
    blocked = false
    DeleteCursorItem()
    if CursorHasItem() then ClearCursor() end
    if say then
        local count = info.stackCount or 1
        IF.Print(blocked and "the game doesn't let addons destroy items here."
            or "destroyed " .. (info.hyperlink or "item") .. (count > 1 and (" x" .. count) or ""))
    end
    return not blocked, blocked
end
