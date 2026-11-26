-- The General tab: the core's own features that have no tab of a module
-- (a tab of settings, IF.SettingsPage, SettingsPage.lua).
local _, IF = ...

local Item, OnOff = IF.SettingsItem, IF.SettingsOnOff

local ITEMS = {
    Item({
        key = "padOverrides", group = "gamepad", label = "Controller buttons",
        tip = "On: Improved Forever's actions on the controller work (the wheels' R3 combos, the actions put on "
            .. "buttons in the Bindings tab, Square shooting the wand, the touchpad corners). Off: the "
            .. "buttons stay the game's own, and the modules (Immersion, Fishing, Wiki...) still work with the "
            .. "mouse and keyboard.",
    }, OnOff(function() return IF.Binds.PadOverrides() end, function(on)
        IF.db.padOverrides = on
        if IF.Binds.FocusChanged then IF.Binds.FocusChanged() end
    end, "Controller buttons")),
    Item({
        key = "menuDouble", group = "gamepad", label = "Double tap Menu opens this panel",
        tip = "Pressing the Menu button (Start) twice quickly opens this panel; once still opens the game's own "
            .. "menu. Turn it off if you don't want the double tap to do that. The same as the \"Improved Forever "
            .. "panel\" binding in the Bindings tab; the panel also opens with /if.",
    }, OnOff(function() return IF.db.menuDouble ~= false end, function(on)
        -- (nil: on, the default)
        if on then IF.db.menuDouble = nil else IF.db.menuDouble = false end
    end, "Double tap Menu opens this panel")),
    Item({
        key = "wandShoot", group = "gamepad", label = "Square shoots the wand",
        tip = "With a wand in your ranged slot, Square on a living enemy shoots it instead of swinging the "
            .. "melee weapon. L2 / R2 + Square stay the crossbar's; on a corpse, an NPC or an object Square is "
            .. "the game's own Interact. A Square override set in the Bindings tab wins over it. Off by default.",
    }, OnOff(function() return IF.db.wandShoot == true end, function(on)
        IF.db.wandShoot = on
        IF.Override.Apply()
    end, "Square shoots the wand")),
    Item({
        key = "squareAttack", group = "gamepad", label = "Square always attacks",
        tip = "Square on a living enemy starts the melee attack and never switches it off: pressing it again "
            .. "keeps attacking. With a wand and \"Square shoots the wand\" on, the wand wins. L2 / R2 + Square "
            .. "stay the crossbar's; on a corpse, an NPC or an object Square is the game's own Interact. A "
            .. "Square override set in the Bindings tab wins over it. Off by default.",
    }, OnOff(function() return IF.db.squareAttack == true end, function(on)
        IF.db.squareAttack = on
        IF.Override.Apply()
    end, "Square always attacks")),
    Item({
        key = "bagSort", group = "gamepad", label = "L3 cleans up the bags",
        tip = "While a bag is open, L3 (the left stick click) sorts the items in your bags. Once they close, "
            .. "the button does its own job again. The button can't be changed.",
    }, OnOff(function() return IF.db.bagSort ~= false end, function(on)
        IF.db.bagSort = on
        IF.db.bagSortKey = nil
        IF.UpdateBagBinding()
    end, "L3 cleans up the bags")),
    Item({
        key = "addonWindows", group = "gamepad", label = "Other addons' windows in L2 / R2",
        tip = "Windows of other addons that Escape closes join L2 / R2 beside the game's windows: one opened "
            .. "takes the controller, the D-pad moves a cursor in it, A presses, Circle closes it. Turn it off "
            .. "if an addon's windows should leave the controller to the game.",
    }, OnOff(function() return IF.AddonWindows.Scanned() end, function(on)
        -- (nil: on, the default)
        if on then IF.db.addonWindows = nil else IF.db.addonWindows = false end
        if not on then IF.AddonWindows.Refresh() end
    end, "Other addons' windows in L2 / R2")),
    Item({
        key = "cornerKeys", group = "gamepad", label = "Touchpad corners from Steam Input",
        tip = "For SteamOS / Steam Deck with Steam Input on: the game sees an Xbox pad there and no touchpad "
            .. "finger, so the touchpad's corners come as the numpad keys 7 / 9 / 1 / 3 (the Improved Forever "
            .. "Steam Input layout, see the README). On: those keys are the corners, and the Bindings tab shows "
            .. "the corners to bind. A PlayStation controller the game sees as one has them without this. "
            .. "The same as /if cornerkeys.",
    }, OnOff(function() return IF.Touch.GetSettings().cornerKeys == true end, function(on)
        IF.Touch.GetSettings().cornerKeys = on or nil
        IF.Touch.Apply()
    end, "Touchpad corners from Steam Input")),
    Item({
        key = "resetBindings", group = "gamepad", label = "Reset all bindings",
        tip = "Puts every binding back to its default: the buttons and keys of the Bindings tab, the actions "
            .. "put on presses and keys, and the touchpad's corners. The crossbar's own slots stay as they are.",
    }, {
        button = "Reset",
        run = function()
            if IF.InCombat() then return IF.Print("Not in combat.") end
            if IF.Binds.ResetAll() then IF.Print("Every binding is back to its default.") end
        end,
        confirm = true, confirmText = "Reset every binding to its default?",
    }),
    Item({
        key = "bankMail", group = "mail", label = "Mail to Bank",
        tip = "At the mailbox's send tab, the Mail to Bank press (Bindings tab; Ctrl + right-click with the "
            .. "mouse) puts a bag item into the mail, and your bank character shows beside the recipient. "
            .. "Nothing is sent by itself.",
    }, OnOff(function() return IF.BankMail.Settings().on ~= false end, function(on)
        IF.BankMail.Settings().on = on
        IF.BankMail.Update()
    end, "Mail to Bank")),
    Item({
        key = "bankName", group = "mail", label = "Bank character",
        tip = "The character your items go to: one of yours on this realm and side (each one logged in once "
            .. "with Improved Forever), set per realm and side. Kept even when that character hasn't logged in "
            .. "for a long time.",
        value = function() return IF.BankMail.Name() or "" end,
        text = function() return IF.BankMail.Name() or "|cffff7a5cNone|r" end,
        options = function()
            local list = { { action = "", name = "None" } }
            for _, c in ipairs(IF.GameData.AltSkills()) do list[#list + 1] = { action = c.name, name = c.name } end
            return list
        end,
        choose = function(name) IF.BankMail.SetName(name ~= "" and name or nil) end,
    }),
    Item({
        key = "whatsNew", group = "updates", label = "What's new",
        tip = "Shows what the latest version of each Improved Forever module changed, again: the list that "
            .. "appears after an update. Nothing is noted as seen by it.",
    }, {
        button = "Show",
        run = function()
            -- (the config window closed first: the list shows in its place, the pad
            -- handed back before the tour takes it)
            if IF.Menu and IF.Menu.Close then IF.Menu.Close() end
            C_Timer.After(0.2, function() IF.WhatsNew.Replay() end)
        end,
    }),
    Item({
        key = "reload", group = "updates", label = "Reload the interface",
        tip = "Reloads the interface, the same as /reload: settings and saved data are written to disk, and"
            .. " every addon loads again.",
    }, {
        button = "Reload",
        run = function() ReloadUI() end,
    }),
}

local GROUPS = {
    { key = "gamepad", label = "Gamepad" },
    { key = "mail", label = "Mail" },
    { key = "updates", label = "Updates" },
}

IF.GeneralEditor = IF.SettingsPage({ key = "general", label = "General", icon = IF.TEX .. "ic_mod_general", order = 5 },
    GROUPS, ITEMS)
