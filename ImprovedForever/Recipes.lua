-- The game's recipes as the client gives them: a recipe's reagents and
-- result, the one the profession window shows, how many the bags allow.
-- Read only: the profession window is never changed from here.
local _, IF = ...

local R = {}
IF.Recipes = R

-- { recipeID, name, icon, makes, output, reagents = { { itemID, per } } },
-- nil: the client doesn't know it
function R.Read(recipeID)
    local ui = C_TradeSkillUI
    local ok, schematic = pcall(ui.GetRecipeSchematic, recipeID, false)
    if not ok or not schematic then return nil end
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local basic = not Enum.CraftingReagentType or slot.reagentType == Enum.CraftingReagentType.Basic
        local first = slot.reagents and slot.reagents[1]
        if basic and first and first.itemID and (slot.quantityRequired or 0) > 0 then
            reagents[#reagents + 1] = { itemID = first.itemID, per = slot.quantityRequired }
        end
    end
    local info = ui.GetRecipeInfo and ui.GetRecipeInfo(recipeID)
    return {
        recipeID = recipeID, reagents = reagents,
        name = schematic.name or (info and info.name) or ("recipe " .. recipeID),
        icon = info and info.icon, makes = math.max(1, schematic.quantityMin or 1),
        output = schematic.outputItemID,
    }
end

function R.WindowUp()
    local frame = _G.ProfessionsFrame
    return frame and frame:IsShown() or false
end

-- The recipe the profession window shows now (nil: not up, or not known)
function R.Shown()
    local frame = _G.ProfessionsFrame
    local page = R.WindowUp() and frame.CraftingPage
    local form = page and page.SchematicForm
    if not (form and form.GetRecipeInfo) then return nil end
    local ok, info = pcall(form.GetRecipeInfo, form)
    return ok and info and info.recipeID or nil
end

-- How many the bags allow now
function R.Craftable(recipeID)
    local ui = C_TradeSkillUI
    if ui.GetCraftableCount then
        local ok, n = pcall(ui.GetCraftableCount, recipeID)
        if ok and n then return n end
    end
    local got, info = pcall(ui.GetRecipeInfo, recipeID)
    return got and info and info.numAvailable or 0
end
