-- The panel's money: what you carry, and (its setting) what this session
-- brought or cost, since login or the last /reload
local IF = ImprovedForever

local start

local function Gain()
    local money = GetMoney()
    start = start or money
    return money - start
end

local function Signed(gain)
    return (gain >= 0 and "|cff5fd35f+" or "|cffff7a5c-") .. GetMoneyString(math.abs(gain), true) .. "|r"
end

IF.Panel.Add({
    key = "money", label = "Money",
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_MONEY" },
    text = function()
        local gain = Gain()
        local text = GetMoneyString(GetMoney(), true)
        if IF.Panel.Settings().session and gain ~= 0 then text = text .. "  " .. Signed(gain) end
        return text
    end,
    tip = function(tip)
        tip:AddLine("Money")
        tip:AddDoubleLine("This session", Signed(Gain()), 1, 1, 1, 1, 1, 1)
    end,
})
