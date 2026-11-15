-- The command list's entries, gathered per addon family (its TOC title
-- without [parts] and version) from four
-- sources: slash commands, settings pages, the TOC's AddonCompartmentFunc
-- and LibDataBroker launchers. The game's own commands and pages stay out,
-- so do libraries' commands.
--   IF.Addons.Commands() -> groups ({ title, entries }, by title), skipped
--     ({ kind, text, reason }: every entry left out or not matched to an
--     addon); an entry: { kind = "slash" (text, key, aliases), "settings"
--     (text, id, openable: a number id), "compartment" (text: the
--     function's name), "ldb" (text) }
--   IF.Addons.Dump(): the list into IF.db.addonsLog
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
local function SlashOwners(loaded, Skip)
    local owners, ace, game = {}, {}, {}
    for key in pairs(SlashKeys()) do
        local alias = _G["SLASH_" .. key .. "1"]
        local library = alias and LibraryKey(key)
        if not alias then
            Skip("slash", key, "no SLASH_" .. key .. "1")
        elseif library then
            Skip("slash", alias, "library command (" .. library .. ")")
        else
            local secure, addon = issecurevariable("SLASH_" .. key .. "1")
            local named = AddonTitled(loaded, key)
            if secure then
                game[#game + 1] = alias
            else
                if named and addon ~= named then
                    Skip("slash", alias, "taint names " .. tostring(addon) .. ", listed under " .. named)
                end
                owners[key] = named or addon
            end
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
    for key in pairs(ace) do
        if not owners[key] then Skip("slash", Aliases(key)[1] or key, "library command, no addon matched") end
    end
    table.sort(game)
    if game[1] then Skip("slash", table.concat(game, ","), "the game's (secure SLASH_ global)") end
    return owners
end

-- Addon settings pages. The game builds every category in its own secure
-- code, so the owner comes from the page's name.
local function SettingsPages(loaded, Add, Skip)
    local game = {}
    for _, category in ipairs(SettingsPanel:GetAllCategories()) do
        local name = category:GetName()
        if category:GetCategorySet() ~= Settings.CategorySet.AddOns then
            game[#game + 1] = name
        else
            local id = category:GetID()
            local addon = AddonTitled(loaded, name)
            if not addon then Skip("settings", name, "no addon matched, listed under its own name") end
            Add(addon or name, { kind = "settings", text = name, id = id, openable = type(id) == "number" })
        end
    end
    if game[1] then Skip("settings", table.concat(game, ","), "the game's category set") end
end

function AD.Commands()
    local loaded, byAddon, skipped = LoadedAddons(), {}, {}
    local function Add(addon, entry)
        byAddon[addon] = byAddon[addon] or {}
        table.insert(byAddon[addon], entry)
    end
    local function Skip(kind, text, reason)
        skipped[#skipped + 1] = { kind = kind, text = text, reason = reason }
    end

    for key, addon in pairs(SlashOwners(loaded, Skip)) do
        local aliases = Aliases(key)
        if aliases[1] then Add(addon, { kind = "slash", text = aliases[1], key = key, aliases = aliases }) end
    end

    local ok, err = pcall(SettingsPages, loaded, Add, Skip)
    if not ok then Skip("settings", "all", "error: " .. tostring(err)) end

    for _, addon in pairs(loaded) do
        local func = C_AddOns.GetAddOnMetadata(addon, "AddonCompartmentFunc")
        if func then Add(addon, { kind = "compartment", text = strtrim(func) }) end
    end

    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if ldb then
        for name, object in ldb:DataObjectIterator() do
            if object.OnClick then
                Add(AddonNamed(loaded, name) or name, { kind = "ldb", text = name })
            else
                Skip("ldb", name, "no OnClick")
            end
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
    return groups, skipped
end

-- tostring errors on a secret value
local function Str(value)
    local ok, text = pcall(tostring, value)
    return ok and text or "<hidden>"
end

function AD.Dump()
    local groups, skipped = AD.Commands()
    local log = { date("%Y-%m-%d %H:%M:%S") }
    IF.db.addonsLog = log
    IF.Print("addons dump: start")
    local found, left = {}, {}
    local function Line(text) log[#log + 1] = string.format("%.2f %s", GetTime() % 1000, text) end
    for _, group in ipairs(groups) do
        local parts = {}
        for i, entry in ipairs(group.entries) do
            local text = entry.kind .. " " .. Str(entry.text)
            if entry.aliases and #entry.aliases > 1 then text = text .. " (" .. table.concat(entry.aliases, ",") .. ")" end
            if entry.kind == "settings" then text = text .. " id=" .. Str(entry.id) .. (entry.openable and "" or " not openable") end
            parts[i] = text
            found[entry.kind] = (found[entry.kind] or 0) + 1
        end
        Line(group.title .. ": " .. table.concat(parts, "; "))
    end
    for _, skip in ipairs(skipped) do
        Line("skipped " .. skip.kind .. " " .. Str(skip.text) .. ": " .. skip.reason)
        left[skip.kind] = (left[skip.kind] or 0) + 1
    end
    local counts = {}
    for _, kind in ipairs({ "slash", "settings", "compartment", "ldb" }) do
        counts[#counts + 1] = string.format("%s %d (skipped lines %d)", kind, found[kind] or 0, left[kind] or 0)
    end
    Line("counts: " .. table.concat(counts, ", "))
    IF.Print("addons dump: " .. #groups .. " addons, " .. #log .. " lines; /reload writes them")
end
