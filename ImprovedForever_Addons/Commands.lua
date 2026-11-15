-- The command list's entries, gathered per addon (its TOC title) from four
-- sources: slash commands, settings pages, the TOC's AddonCompartmentFunc
-- and LibDataBroker launchers. The game's own commands and pages are secure
-- variables and stay out, so do the commands of a library nobody owns.
--   IF.Addons.Commands() -> groups ({ title, entries }, by title), hidden
--     (the library commands left out); an entry: { kind = "slash" (text,
--     key, aliases), "settings" (text, id, openable: a number id),
--     "compartment" (text: the function's name), "ldb" (text) }
--   IF.Addons.Dump(): the list into IF.db.addonsLog
local IF = ImprovedForever

local AD = IF.Addons

local function Title(addon)
    local title = C_AddOns.GetAddOnMetadata(addon, "Title") or addon
    return (title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The loaded addons, by lower-case name
local function LoadedAddons()
    local loaded = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if C_AddOns.IsAddOnLoaded(i) then loaded[name:lower()] = name end
    end
    return loaded
end

-- The loaded addon a name stands for: the same name, else the longest addon
-- name it starts with (TitanUI is Titan's)
local function AddonNamed(loaded, text)
    text = text:lower()
    if loaded[text] then return loaded[text] end
    local best
    for lower, name in pairs(loaded) do
        if text:sub(1, #lower) == lower and (not best or #lower > #best) then best = name end
    end
    return best
end

-- A slash command's aliases (/fp, /foreverpad...), from its SLASH_<key><n> globals
local function Aliases(key)
    local aliases = {}
    for i = 1, math.huge do
        local alias = _G["SLASH_" .. key .. i]
        if not alias then break end
        aliases[i] = alias
    end
    return aliases
end

-- SlashCmdList key -> the addon it belongs to; and the library commands
-- left out. issecurevariable names the addon that set a key, but AceConsole
-- sets every command from its own code, so the addon whose copy of the
-- library loaded gets them all: those are matched by AceConfig app name,
-- then by command name, then by sharing a handler with a matched one.
local function SlashOwners(loaded)
    local owners, ace = {}, {}
    for key in pairs(SlashCmdList) do
        local secure, addon = issecurevariable(SlashCmdList, key)
        if not secure then owners[key] = addon end
    end
    local console = LibStub and LibStub("AceConsole-3.0", true)
    local config = LibStub and LibStub("AceConfigCmd-3.0", true)
    for command, key in pairs(console and console.commands or {}) do
        local app = config and config:GetChatCommandOptions(command)
        owners[key] = (app and AddonNamed(loaded, app)) or AddonNamed(loaded, command)
        ace[key] = true
    end
    for key in pairs(ace) do
        for other in pairs(ace) do
            if not owners[key] and owners[other] and SlashCmdList[other] == SlashCmdList[key] then
                owners[key] = owners[other]
            end
        end
    end
    local hidden = {}
    for key in pairs(ace) do
        if not owners[key] then hidden[#hidden + 1] = Aliases(key)[1] or key end
    end
    table.sort(hidden)
    return owners, hidden
end

function AD.Commands()
    local loaded, byAddon = LoadedAddons(), {}
    local function Add(addon, entry)
        byAddon[addon] = byAddon[addon] or {}
        table.insert(byAddon[addon], entry)
    end

    local owners, hidden = SlashOwners(loaded)
    for key, addon in pairs(owners) do
        local aliases = Aliases(key)
        if aliases[1] then Add(addon, { kind = "slash", text = aliases[1], key = key, aliases = aliases }) end
    end

    -- (the game's settings window may differ between clients: none read then)
    pcall(function()
        for _, category in ipairs(SettingsPanel:GetCategoryList():GetAllCategories()) do
            local secure, addon = issecurevariable(category, "name")
            if not secure then
                local id = category:GetID()
                Add(addon, { kind = "settings", text = category:GetName(), id = id, openable = type(id) == "number" })
            end
        end
    end)

    for _, addon in pairs(loaded) do
        local func = C_AddOns.GetAddOnMetadata(addon, "AddonCompartmentFunc")
        if func then Add(addon, { kind = "compartment", text = strtrim(func) }) end
    end

    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if ldb then
        for name, object in ldb:DataObjectIterator() do
            if object.OnClick then Add(AddonNamed(loaded, name) or name, { kind = "ldb", text = name }) end
        end
    end

    local groups = {}
    for addon, entries in pairs(byAddon) do
        table.sort(entries, function(a, b) return a.kind .. tostring(a.text) < b.kind .. tostring(b.text) end)
        groups[#groups + 1] = { title = loaded[addon:lower()] and Title(addon) or addon, entries = entries }
    end
    table.sort(groups, function(a, b) return a.title:lower() < b.title:lower() end)
    return groups, hidden
end

-- tostring errors on a secret value
local function Str(value)
    local ok, text = pcall(tostring, value)
    return ok and text or "<hidden>"
end

function AD.Dump()
    local groups, hidden = AD.Commands()
    local log = { date("%Y-%m-%d %H:%M:%S") }
    IF.db.addonsLog = log
    IF.Print("addons dump: start")
    local count = 0
    for _, group in ipairs(groups) do
        local parts = {}
        for i, entry in ipairs(group.entries) do
            local text = entry.kind .. " " .. Str(entry.text)
            if entry.aliases and #entry.aliases > 1 then text = text .. " (" .. table.concat(entry.aliases, ",") .. ")" end
            if entry.kind == "settings" then text = text .. " id=" .. Str(entry.id) .. (entry.openable and "" or " not openable") end
            parts[i] = text
        end
        count = count + #parts
        log[#log + 1] = string.format("%.2f %s: %s", GetTime() % 1000, group.title, table.concat(parts, "; "))
    end
    log[#log + 1] = string.format("%.2f hidden library commands: %s", GetTime() % 1000, table.concat(hidden, ","))
    IF.Print("addons dump: " .. #groups .. " addons, " .. count .. " entries, " .. #log .. " lines; /reload writes them")
end
