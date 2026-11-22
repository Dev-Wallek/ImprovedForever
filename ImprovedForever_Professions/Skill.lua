-- A recipe's colour and chance of a point at a skill. The bundled table
-- (RecipeData.lua trivial: where it turns yellow and grey) gives it for
-- every recipe; for one the profession window shows, the game's colour
-- (its relativeDifficulty) wins. Green starts halfway from yellow to grey.
local IF = ImprovedForever
local PR = IF.Professions

-- (Enum.TradeskillRelativeDifficulty)
local DIFFICULTY = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }

-- The skill a recipe is learnt at: its trainer's, else its recipe item's
function PR.LearnRank(spell)
    local world, data = IF.WorldData, IF.RecipeData
    local rank = world and world.trainerSkill and world.trainerSkill[spell]
    local row = data.recipes[spell]
    if not rank and row and row[4] > 0 then rank = data.learnRank[row[4]] end
    return rank
end

-- The table's colour and chance; nil for a recipe without a grey (unknown).
-- A yellow above its grey (Spell 22434) is orange up to the grey.
function PR.TableColor(spell, skill)
    local t = IF.RecipeData.trivial[spell]
    if not t or t[2] == 0 then return nil end
    local yellow, grey = t[1], t[2]
    if skill >= grey then return "grey", 0 end
    if skill < yellow or yellow >= grey then return "orange", 1 end
    local color = skill >= math.floor((yellow + grey) / 2) and "green" or "yellow"
    return color, (grey - skill) / (grey - yellow)
end

-- The colour and chance now; difficulty is the game's, when it shows the
-- recipe. A yellow or green the table doesn't agree on has no chance (nil).
function PR.Color(spell, skill, difficulty)
    local color, chance = PR.TableColor(spell, skill)
    local game = difficulty and DIFFICULTY[difficulty]
    if not game or game == color then return color, chance end
    if game == "orange" then return game, 1 end
    if game == "grey" then return game, 0 end
    return game, (color == "yellow" or color == "green") and chance or nil
end

-- The open profession's skill
local function Skill()
    local ui = C_TradeSkillUI
    local info = ui.GetChildProfessionInfo and ui.GetChildProfessionInfo()
    if not (info and (info.skillLevel or 0) > 0) then info = ui.GetBaseProfessionInfo() end
    return info and info.skillLevel
end

-- /if prof audit: the known recipes of the open profession whose table
-- colour differs from the game's, into IF.db.profAudit
local function Audit()
    local ui = C_TradeSkillUI
    local ok, ids = pcall(ui and ui.GetAllRecipeIDs)
    local skill = ok and type(ids) == "table" and #ids > 0 and Skill()
    if not skill then
        IF.Print("open a profession window first.")
        return
    end
    local log = { date("%Y-%m-%d %H:%M") .. " skill " .. skill }
    local checked = 0
    for _, id in ipairs(ids) do
        local info = ui.GetRecipeInfo(id)
        if info and info.learned and info.relativeDifficulty then
            checked = checked + 1
            local color = PR.TableColor(id, skill)
            local game = DIFFICULTY[info.relativeDifficulty]
            if color ~= game then
                local t = IF.RecipeData.trivial[id]
                log[#log + 1] = ("%d %s: table %s (%s), game %s"):format(id, tostring(info.name), tostring(color),
                    t and (t[1] .. "/" .. t[2]) or "none", tostring(game))
            end
        end
    end
    IF.db.profAudit = log
    IF.Print(("%d recipes checked, %d differ (IF.db.profAudit, on disk after /reload)."):format(checked, #log - 1))
end

IF.AddCommand("prof", function(args)
    if args[1] == "audit" then Audit() end
end, "audit: recipe colours against the game's")
