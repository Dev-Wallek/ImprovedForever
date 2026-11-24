-- The Wiki's page of the rare creatures in the player's zone (the core's
-- GameData.Rares), the lowest level first: Cross on one opens its page, Square
-- shows it on the map (WikiPage.lua's lines). Opened by a wheel's slot (its
-- button, Actions.lua) or /if wiki rares; never in combat.
local IF = ImprovedForever

local LB = IF.Wiki

local ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"
local UP = 3                   -- parent maps tried when the player's own has none (a cave, a town)

local Rares = setmetatable({}, { __index = LB.PageClass })
Rares.__index = Rares

-- The player's map with rares on it, and them (none found: the player's own map, no rares)
local function Here()
    local all = IF.GameData.Rares()
    local own = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local map = own
    for _ = 0, UP do
        if not map or all[map] then break end
        local info = C_Map.GetMapInfo(map)
        map = info and info.parentMapID
    end
    if map and all[map] then return map, all[map] end
    return own, {}
end

function Rares:heading()
    local info = self.map and C_Map.GetMapInfo(self.map)
    return { icon = ICON, round = false, title = info and info.name or "Here",
        kind = "Rare creatures", owned = #self.lines == 0 and "None known" or (#self.lines .. " known"),
        chapter = "Rares" }
end

function Rares:notes()
    if #self.lines == 0 then
        return { "No rare creature is known to roam this zone." }, nil, {}
    end
    return { "Rare creatures said to roam here, the weakest first; each keeps to a few places only." }, nil,
        self.lines
end

function Rares:about() return nil end

function LB.OpenRares()
    if IF.InCombat() then return IF.Print("the Wiki opens after combat.") end
    local map, list = Here()
    local sorted = { unpack(list) }
    table.sort(sorted, function(a, b)
        if (a.lo or 0) ~= (b.lo or 0) then return (a.lo or 0) < (b.lo or 0) end
        return a.name < b.name
    end)
    local lines = {}
    -- (one the Wiki can't show: none added, nil at the end)
    for _, r in ipairs(sorted) do lines[#lines + 1] = LB.Entry("npc", r.id) end
    local p = setmetatable({ tab = "notes", views = {}, map = map, lines = lines }, Rares)
    LB.origin = nil
    LB.book:Open(p, {})
end

IF.Actions.PressButton("ImprovedForeverWikiRares", function() LB.OpenRares() end)
