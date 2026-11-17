-- The Chat tab, a tab of settings (IF.SettingsPage, SettingsPage.lua):
-- the line picker on / off. ChatLines.lua does the work.
local IF = ImprovedForever

local CL = IF.ChatLines
local Item, OnOff = IF.SettingsItem, IF.SettingsOnOff

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
        key = "keyboard", group = "lines", label = "Inline keyboard",
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
}

local GROUPS = {
    { key = "lines", label = "Chat" },
}

IF.ChatEditor = IF.SettingsPage({ key = "chat", label = "Chat", module = "chat", order = 65 }, GROUPS, ITEMS)
