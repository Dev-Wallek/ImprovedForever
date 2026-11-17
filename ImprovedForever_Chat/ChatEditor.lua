-- The Chat tab, a tab of settings (IF.SettingsPage, SettingsPage.lua):
-- the line picker on / off. ChatLines.lua does the work.
local IF = ImprovedForever

local CL = IF.ChatLines
local Item, OnOff = IF.SettingsItem, IF.SettingsOnOff

local function Slide(key, label, tip, min, max, step, format)
    local CK = IF.ChatKeyboard
    return {
        key = key, group = "lines", section = "Keyboard", label = label, tip = tip,
        slider = {
            min = min, max = max, step = step, default = CK.DEFAULTS[key],
            get = function() return CK.Settings()[key] end,
            set = function(n)
                CK.Settings()[key] = n
                CK.Preview()
            end,
            format = format,
        },
    }
end

local ITEMS = {
    Item({
        key = "enabled", group = "lines", label = "Chat lines",
        tip = "While the chat has the controller (its edit box open), D-pad Up goes up into its lines: the D-pad "
            .. "picks a line, left / right a link in it (its tooltip shows). Cross opens an item in the Wiki, "
            .. "Square puts the link in your message, Circle goes back to the edit box.",
        -- (with the mouse the chat's own links do it: the Wiki's click, the core's)
        note = function()
            if IF.Input.Pad() then return nil end
            return "For the controller. With the mouse the chat's own links do this: a click shows its tooltip, "
                .. "Shift + click puts it in your message"
                .. (IF.Wiki and IF.Binds.KeyBind(IF.Binds.Get("wiki")) and (", "
                    .. IF.Binds.KeyText(IF.Binds.KeyBind(IF.Binds.Get("wiki"))) .. " opens an item in the Wiki.") or ".")
        end,
    }, OnOff(function() return CL.Settings().enabled end, function(on)
        CL.Settings().enabled = on
        if not on then CL.Close() end
    end, "Chat lines")),
    Item({
        key = "keyboard", group = "lines", section = "Keyboard", label = "Inline keyboard",
        tip = "LB + RB held, Cross (the Chat keyboard binding, Bindings tab) opens a keyboard anywhere, the chat's "
            .. "edit box not needed; so does D-pad Down while the chat has the controller. It sits low in the "
            .. "middle of the screen, laid out as the PS5's: the D-pad picks a key, Cross types it, Square "
            .. "deletes, Triangle is a space, LB / RB move the cursor, LT / RT pick the channel (Say, Party, "
            .. "Guild, Whisper, General...), Start sends to the channel, Circle closes. The sticks stay the game's.",
        note = function()
            if IF.Input.Pad() then return nil end
            return "For the controller. With the mouse, type on the keyboard."
        end,
    }, OnOff(function() return IF.ChatKeyboard.Settings().enabled end, function(on)
        IF.ChatKeyboard.Settings().enabled = on
        if not on then IF.ChatKeyboard.Close() end
    end, "Inline keyboard")),
    {
        key = "position", group = "lines", section = "Keyboard", label = "Keyboard position",
        tip = "Where the keyboard sits: low in the middle of the screen, or down the left or right side (its keys "
            .. "then in a narrower block, a taller one).",
        value = function() return IF.ChatKeyboard.Settings().position end,
        text = function()
            local p = IF.ChatKeyboard.Settings().position
            return p == "left" and "Left" or p == "right" and "Right" or "Bottom"
        end,
        options = function()
            return { { action = "bottom", name = "Bottom" }, { action = "left", name = "Left" },
                { action = "right", name = "Right" } }
        end,
        choose = function(action)
            IF.ChatKeyboard.Settings().position = action
            IF.ChatKeyboard.Preview()
        end,
    },
    -- (its place: the keyboard shows while you slide, so you see where it lands)
    Slide("scale", "Keyboard size", "How big the keyboard is, in percent.", 50, 200, 5, function(n) return n .. "%" end),
    Slide("offsetX", "Keyboard left / right", "Moves the keyboard from the middle of the screen: left (minus) or right.",
        -1000, 1000, 10, function(n) return n .. " px" end),
    Slide("offsetY", "Keyboard up / down", "Moves the keyboard up (minus: down), from the bottom of the screen, or from the middle on a side.",
        -600, 800, 10, function(n) return n .. " px" end),
}

local GROUPS = {
    { key = "lines", label = "Chat" },
}

IF.ChatEditor = IF.SettingsPage({ key = "chat", label = "Chat", module = "chat", order = 65 }, GROUPS, ITEMS)
