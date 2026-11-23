-- Improved Forever: Map. The peek map: the game's map shown see-through,
-- held or tapped (PeekMap.lua), placed and sized in its tab (PeekMapEditor.lua).
local IF = ImprovedForever

IF.AddModule({ key = "map", label = "Map", icon = IF.TEX .. "ic_mod_map", addon = ... })

-- /if peek: the peek map's presses; prints each press
IF.AddCommand("peek", function() IF.PeekMap.Probe() end, ": the peek map's presses, each press")

