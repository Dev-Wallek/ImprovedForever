-- The panel's experience: level, share of the level (or its points and
-- those to go), rested; gone where
-- the game shows no experience bar (the top level, experience turned off)
local IF = ImprovedForever

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function Values()
    local level, cur, max, rest = UnitLevel("player"), UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0
    if Secret(level) or Secret(cur) or Secret(max) or Secret(rest) or not max or max <= 0 then return nil end
    return level, cur, max, rest
end

local function Gaining()
    local rules = GameRulesUtil
    return not (rules and rules.CanShowExperienceBar) or rules.CanShowExperienceBar()
end

IF.Panel.Add({
    key = "xp", label = "Experience",
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION" },
    text = function()
        if not Gaining() then return nil end
        local level, cur, max, rest = Values()
        if not level then return false end
        if IF.Panel.Settings().xpNumbers then
            local n = BreakUpLargeNumbers
            local text = ("Level %d  %s / %s  (%s to go)"):format(level, n(cur), n(max), n(max - cur))
            if rest > 0 then text = text .. ("  |cff4fa3ff+%s rested|r"):format(n(rest)) end
            return text
        end
        local text = ("Level %d  %d%%"):format(level, math.floor(cur / max * 100))
        if rest > 0 then text = text .. ("  |cff4fa3ff+%d%% rested|r"):format(math.floor(rest / max * 100)) end
        return text
    end,
    tip = function(tip)
        local level, cur, max, rest = Values()
        tip:AddLine("Experience")
        if not level then return end
        tip:AddDoubleLine("Level " .. level, cur .. " / " .. max, 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("To the next level", max - cur, 1, 1, 1, 1, 1, 1)
        if rest > 0 then tip:AddDoubleLine("Rested", rest, 1, 1, 1, 0.31, 0.64, 1) end
    end,
})
