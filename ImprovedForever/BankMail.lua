-- Mail to the bank character: with the mailbox's send tab open, a press on
-- a bag item (its binding in the Bindings tab; Ctrl + right-click with the
-- mouse) puts it into the mail. Nothing is sent: more items and the game's
-- Send button stay the player's. The bank character (General tab) shows
-- beside the recipient field; it isn't written into the field, a property
-- of the game's frame (CLAUDE.md, Taint).
local _, IF = ...

local M = {}
IF.BankMail = M

-- { on (false: off), name (the bank character), key (its press) }
function M.Settings()
    IF.db.bankMail = IF.db.bankMail or {}
    return IF.db.bankMail
end

local function On()
    return IF.db and M.Settings().on ~= false
end

local function SendOpen()
    return SendMailFrame and SendMailFrame:IsVisible()
end

function M.Attach(bag, slot)
    if not On() or IF.InCombat() or not SendOpen() then return end
    if not C_Container.GetContainerItemInfo(bag, slot) then return end
    for i = 1, ATTACHMENTS_MAX_SEND do
        if not GetSendMailItem(i) then
            ClearCursor()
            C_Container.PickupContainerItem(bag, slot)
            ClickSendMailItemButton(i)
            return
        end
    end
    IF.Print("The mail is full (" .. ATTACHMENTS_MAX_SEND .. " items).")
end

-- (the bank character beside the recipient field)
local hint = CreateFrame("Frame", nil, UIParent)
hint:SetSize(1, 1)
hint:Hide()
hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hint.text:SetPoint("LEFT")

function M.Update()
    local name = On() and M.Settings().name
    if not (name and SendOpen()) then return hint:Hide() end
    hint:ClearAllPoints()
    hint:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 8, 0)
    hint.text:SetText("Bank: " .. name)
    hint:Show()
end

-- The press, watched while the send tab is open (not taken: the button
-- keeps its own action)
local watcher = CreateFrame("Frame")
local wasDown = false
local function Watch()
    local key = On() and M.Settings().key
    if not key then return end
    local held, pressed = IF.Binds.Parse(key)
    local down = IsKeyDown(pressed) and (not held or IsKeyDown(held))
    if down and not wasDown then
        local bag, slot = IF.FocusedBagSlot()
        if bag then M.Attach(bag, slot) end
    end
    wasDown = down
end

SendMailFrame:HookScript("OnShow", function()
    wasDown = false
    watcher:SetScript("OnUpdate", Watch)
    M.Update()
end)
SendMailFrame:HookScript("OnHide", function()
    watcher:SetScript("OnUpdate", nil)
    M.Update()
end)

local B = IF.Binds
B.Add({
    id = "bankmail", label = "Mail to Bank", group = "Bags", tab = "bindings",
    icon = "Interface\\Icons\\INV_Letter_15", context = "bags", order = 24,
    desc = "Puts the bag item into the mail at the mailbox",
    tip = "With the mailbox's send tab open: puts the bag item the cursor is on into the mail. Nothing is"
        .. " sent; add more and send it yourself. The bank character (General tab) shows beside the"
        .. " recipient. Watched, not taken: the button keeps its own action.",
    accepts = B.NotDouble,
    specs = function() return B.One(IF.db and M.Settings().key) end,
    set = function(spec) M.Settings().key = spec end,
    reset = function() M.Settings().key = nil end,
    click = function(item) if item and item.bag then M.Attach(item.bag, item.slot) end end,
    defaultKey = "CTRL-BUTTON2",
})
