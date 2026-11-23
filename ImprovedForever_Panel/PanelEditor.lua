-- The Panel tab, a tab of settings (IF.SettingsPage, SettingsPage.lua):
-- each block shown or hidden and its place in the row, the experience as
-- numbers, the money's session gain. Module.lua does the work.
local IF = ImprovedForever

local menu = IF.Menu
local P = IF.Panel
local Item, OnOff = IF.SettingsItem, IF.SettingsOnOff

local function S()
    return P.Settings()
end

local ITEMS = {}

-- A block: shown or hidden, a place earlier or later in the row
for _, b in ipairs(P.Blocks()) do
    local key, label = b.def.key, b.def.label
    ITEMS[#ITEMS + 1] = Item({
        key = "block_" .. key, group = "blocks", label = label,
        tip = "Shows or hides " .. label:lower() .. ", or moves it a place along the panel.",
        text = function()
            local at, all = 1, P.Blocks()
            for i, other in ipairs(all) do
                if other == b then at = i end
            end
            return (S().hidden[key] and "|cffff7a5cHidden|r" or "Shown") .. "  ·  " .. at .. " of " .. #all
        end,
        value = function() end,
        options = function()
            return {
                { action = "toggle", name = S().hidden[key] and "Show" or "Hide" },
                { action = "earlier", name = "Move earlier" },
                { action = "later", name = "Move later" },
            }
        end,
        choose = function(action)
            if action == "toggle" then
                S().hidden[key] = not S().hidden[key] or nil
                P.Layout()
            else
                P.Move(key, action == "earlier" and -1 or 1)
            end
            menu.Toast(label .. ": " .. (S().hidden[key] and "hidden" or "shown"))
        end,
    })
end

ITEMS[#ITEMS + 1] = Item({
    key = "xpNumbers", group = "blocks", label = "Experience as numbers",
    tip = "Your experience in points, and how many are left to the next level, instead of the share of the level.",
}, OnOff(function() return S().xpNumbers end, function(on)
    S().xpNumbers = on
    P.Refresh()
end, "Experience as numbers"))

ITEMS[#ITEMS + 1] = Item({
    key = "session", group = "blocks", label = "Money this session",
    tip = "Beside your money, what this session brought (green) or cost (red), since login (a /reload keeps it).",
}, OnOff(function() return S().session end, function(on)
    S().session = on
    P.Refresh()
end, "Money this session"))

local GROUPS = {
    { key = "blocks", label = "Shown" },
}

IF.PanelEditor = IF.SettingsPage({ key = "panel", label = "Panel", module = "panel", order = 45, peek = true },
    GROUPS, ITEMS)
