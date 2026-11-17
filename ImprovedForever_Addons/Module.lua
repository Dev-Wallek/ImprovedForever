-- Improved Forever: Addons. Every installed addon with the controller: its
-- commands, settings pages and launchers gathered per addon (Commands.lua).
local IF = ImprovedForever

IF.AddModule({ key = "addons", label = "Addons", icon = IF.TEX .. "ic_mod_addons", addon = ... })

IF.Addons = {}

-- /if addons: the panel on the Addons tab (Page.lua); /if addons dump: the
-- command list into IF.db.addonsLog
IF.AddCommand("addons", function(args)
    if args[1] == "dump" then return IF.Addons.Dump() end
    IF.Menu.Open("addons")
end, ": the Addons tab; dump: the command list into the saved variables")
