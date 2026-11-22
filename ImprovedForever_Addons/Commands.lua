-- The command list's entries, gathered per addon family (its TOC title
-- without [parts] and version) from four
-- sources: slash commands, settings pages, the TOC's AddonCompartmentFunc
-- and LibDataBroker launchers. The game's own commands and pages stay out,
-- so do libraries' commands.
--   IF.Addons.Commands() -> groups ({ title, entries }, by title); an entry: { kind = "slash" (text, key, aliases), "settings"
--     (text, id, openable: a number id), "compartment" (text: the
--     function's name, addon), "ldb" (text) }
local IF = ImprovedForever

local AD = IF.Addons

local function Title(addon)
    local title = C_AddOns.GetAddOnMetadata(addon, "Title") or addon
    return (title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Lower case, letters and digits only ("Titan Panel" -> "titanpanel")
local function Norm(text)
    return (text:lower():gsub("[^%w]", ""))
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

-- The loaded addon a settings page's name stands for: its name or title
-- equal to it, else the shortest addon whose title starts with it
-- ("Titan Panel" is Titan's, not TitanUI's: both titles start with it)
local function AddonTitled(loaded, text)
    local want, best = Norm(text)
    if want == "" then return end
    for _, name in pairs(loaded) do
        local title = Norm(Title(name))
        if Norm(name) == want or title == want then return name end
        if title:sub(1, #want) == want and (not best or #name < #best) then best = name end
    end
    return best
end

-- A slash command's aliases (/fp, /foreverpad...), from its SLASH_<key><n>
-- globals; the game stops at the first missing one too
local function Aliases(key)
    local aliases = {}
    for i = 1, math.huge do
        local alias = _G["SLASH_" .. key .. i]
        if not alias then break end
        aliases[i] = alias
    end
    return aliases
end

-- Every SlashCmdList key. The chat frame moves each entry into the table's
-- metatable __index on load and on every typed command, so most live there.
local function SlashKeys()
    local keys = {}
    for key in pairs(SlashCmdList) do keys[key] = true end
    local meta = getmetatable(SlashCmdList)
    if meta and type(meta.__index) == "table" then
        for key in pairs(meta.__index) do keys[key] = true end
    end
    return keys
end

-- A LibStub library the key stands for (LibQTip for LibQTip-1.0): its
-- command is the library's, whichever addon's copy set it
local function LibraryKey(key)
    local want = Norm(key)
    for major in pairs(LibStub and LibStub.libs or {}) do
        if Norm(major):sub(1, #want) == want then return major end
    end
end

-- SlashCmdList key -> the addon it belongs to. The entries themselves were
-- moved by the game's secure code, so the owner is the addon the key names
-- (its name or title: TitanPanel is Titan's), else the one that set the
-- SLASH_<key>1 global. (That taint can name another addon: Titan sets its
-- globals in its main chunk, yet the game named Auctionator for them.)
-- A library's command is left out. AceConsole sets every command from its
-- own code, so the addon whose copy of the library loaded gets them all:
-- those are matched by AceConfig app name, then by command name, then by
-- sharing a handler with a matched one.
local function SlashOwners(loaded)
    local owners, ace = {}, {}
    for key in pairs(SlashKeys()) do
        local alias = _G["SLASH_" .. key .. "1"]
        if alias and not LibraryKey(key) then
            local secure, addon = issecurevariable("SLASH_" .. key .. "1")
            if not secure then owners[key] = AddonTitled(loaded, key) or addon end
        end
    end
    local console = LibStub and LibStub("AceConsole-3.0", true)
    local config = LibStub and LibStub("AceConfigCmd-3.0", true)
    for command, key in pairs(console and console.commands or {}) do
        local app = config and config:GetChatCommandOptions(command)
        owners[key] = (app and (AddonTitled(loaded, app) or AddonNamed(loaded, app))) or AddonNamed(loaded, command)
        ace[key] = true
    end
    for key in pairs(ace) do
        for other in pairs(ace) do
            if not owners[key] and owners[other] and SlashCmdList[other] == SlashCmdList[key] then
                owners[key] = owners[other]
            end
        end
    end
    return owners
end

-- Addon settings pages. The game builds every category in its own secure
-- code, so the owner comes from the page's name.
local function SettingsPages(loaded, Add)
    for _, category in ipairs(SettingsPanel:GetAllCategories()) do
        local name = category:GetName()
        if category:GetCategorySet() == Settings.CategorySet.AddOns then
            local id = category:GetID()
            Add(AddonTitled(loaded, name) or name, { kind = "settings", text = name, id = id, openable = type(id) == "number" })
        end
    end
end

function AD.Commands()
    local loaded, byAddon = LoadedAddons(), {}
    local function Add(addon, entry)
        byAddon[addon] = byAddon[addon] or {}
        table.insert(byAddon[addon], entry)
    end

    for key, addon in pairs(SlashOwners(loaded)) do
        local aliases = Aliases(key)
        if aliases[1] then Add(addon, { kind = "slash", text = aliases[1], key = key, aliases = aliases }) end
    end

    pcall(SettingsPages, loaded, Add)

    for _, addon in pairs(loaded) do
        local func = C_AddOns.GetAddOnMetadata(addon, "AddonCompartmentFunc")
        if func then Add(addon, { kind = "compartment", text = strtrim(func), addon = addon }) end
    end

    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if ldb then
        for name, object in ldb:DataObjectIterator() do
            if object.OnClick then Add(AddonNamed(loaded, name) or name, { kind = "ldb", text = name }) end
        end
    end

    -- (one group per addon family: its title without [parts] and version,
    -- "Titan Panel [_Core_] 9.3.5" and "Titan Panel [UI] 9.3.5" both "Titan Panel")
    local groups, byTitle = {}, {}
    for addon, entries in pairs(byAddon) do
        local title = loaded[addon:lower()] and Title(addon) or addon
        local family = strtrim((title:gsub("%b[]", ""):gsub("%s+v?%d[%d%.]*%s*$", ""):gsub("%s+", " ")))
        if family ~= "" then title = family end
        local group = byTitle[title]
        if not group then
            group = { title = title, entries = {} }
            byTitle[title] = group
            groups[#groups + 1] = group
        end
        for _, entry in ipairs(entries) do table.insert(group.entries, entry) end
    end
    for _, group in ipairs(groups) do
        table.sort(group.entries, function(a, b) return a.kind .. tostring(a.text) < b.kind .. tostring(b.text) end)
    end
    table.sort(groups, function(a, b) return a.title:lower() < b.title:lower() end)
    return groups
end
