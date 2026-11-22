-- Improved Forever: Addons. Every installed addon with the controller: its
-- commands, settings pages and launchers gathered per addon (Commands.lua).
local IF = ImprovedForever

IF.AddModule({ key = "addons", label = "Addons", icon = IF.TEX .. "ic_mod_addons", addon = ... })

IF.Addons = {}

-- /if addons: the panel on the Addons tab (Page.lua)
IF.AddCommand("addons", function() IF.Menu.Open("addons") end, ": the Addons tab")

-- (a probe's log no code writes, cleared)
IF.OnLogin(function() IF.db.addonsLog = nil end)
