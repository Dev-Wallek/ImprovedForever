-- Improved Forever: Wiki. Everything about an item (Wiki.lua,
-- WikiPage.lua): what drops it, who sells it, the recipes that make or
-- use it, its quests and auction prices; set up in its tab (WikiEditor.lua).
local IF = ImprovedForever

IF.AddModule({ key = "wiki", label = "Wiki", icon = IF.TEX .. "ic_mod_wiki", addon = ... })

-- /if wiki <item id or link>: an item's Wiki page; /if wiki target: the target's
IF.AddCommand("wiki", function(args, msg)
    if args[1] == "target" then return IF.Wiki.OpenTarget() end
    local id = tonumber(args[1]) or tonumber((msg or ""):match("item:(%d+)"))
    if id then IF.Wiki.Open(id) else IF.Print("/if wiki <item id or link> | target") end
end, "<item id or link>: an item's page; target: the target's (what it drops and sells)")
