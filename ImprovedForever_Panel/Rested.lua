-- Rested reminders in the chat (Panel tab): once a session when rested
-- experience is full, so more rest is lost, and when you log out outside
-- an inn or a city, where it grows slower. With "Rested tips" on, each
-- says what to do. Not while experience isn't gained (XP.lua).
local IF = ImprovedForever
local P = IF.Panel

local told

local function Say(text, tip)
    IF.Print("|cff4fa3ff" .. text .. "|r" .. (P.Settings().restTips and ("  " .. tip) or ""))
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_EXHAUSTION", "PLAYER_XP_UPDATE", "PLAYER_CAMPING" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event)
    if not (IF.db and P.Settings().restReminder and P.Gaining()) then return end
    if event == "PLAYER_CAMPING" then
        if not IsResting() and not P.RestFull() then
            Say("Logging out outside an inn or a city: your rested experience grows slower.",
                "In an inn or a city it grows four times as fast.")
        end
        return
    end
    if P.RestFull() and not told then
        Say("Your rested experience is full: more rest is lost.",
            "Spend it: kills give double experience until the blue part of the bar is used up.")
        told = true
    end
end)
