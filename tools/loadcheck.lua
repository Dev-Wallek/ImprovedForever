-- Loads addons' files as the game would (their TOC's order, dependencies
-- first) against a stand-in for the WoW API, then fires ADDON_LOADED,
-- PLAYER_LOGIN and PLAYER_ENTERING_WORLD, and runs any extra checks; every
-- error said with where it happened. Catches a module reaching for another
-- that isn't loaded, a nil at load time, a login callback that fails.
-- Not a test of what the addons do: the API answers anything with a stub.
--
-- Usage (from the repo's root):
--   luajit tools/loadcheck.lua ImprovedForever ImprovedForever_Wheel ...
--   luajit tools/loadcheck.lua all        every folder with a TOC
--   luajit tools/loadcheck.lua each       core + each module alone, then all
local ROOT = "./"

---------------------------------------------------------------------------
-- Stubs: indexable, callable, anything they're asked returns another
---------------------------------------------------------------------------
local Stub
local stubMeta = {}
stubMeta.__index = function(t, k)
    local s = Stub()
    rawset(t, k, s)
    return s
end
stubMeta.__call = function() return Stub() end
stubMeta.__concat = function(a, b)
    return (type(a) == "table" and "" or tostring(a)) .. (type(b) == "table" and "" or tostring(b))
end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do
    stubMeta[op] = function() return 0 end
end
stubMeta.__len = function() return 0 end
function Stub() return setmetatable({}, stubMeta) end

-- Frames: their scripts and events kept, the rest stubs
local frames = {}
local frameMeta = {}
local Frame
-- (an unknown field: a method returning a frame, or a field to index)
local memberMeta = {}
for k, v in pairs(stubMeta) do memberMeta[k] = v end
memberMeta.__call = function() return nil end
frameMeta.__index = function(t, k)
    local m = rawget(frameMeta, k)
    if m then return m end
    -- (the stand-in's own fields: unset)
    if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
    local s = setmetatable({}, memberMeta)
    rawset(t, k, s)
    return s
end
function frameMeta.SetScript(self, name, fn) self.__scripts[name] = fn end
function frameMeta.HookScript(self, name, fn)
    local old = self.__scripts[name]
    self.__scripts[name] = old and function(...) old(...) fn(...) end or fn
end
function frameMeta.GetScript(self, name) return self.__scripts[name] end
function frameMeta.RegisterEvent(self, e) self.__events[e] = true end
function frameMeta.UnregisterEvent(self, e) self.__events[e] = nil end
function frameMeta.RegisterUnitEvent(self, e) self.__events[e] = true end
function frameMeta.IsEventRegistered(self, e) return self.__events[e] == true end
function frameMeta.Show(self) self.__shown = true end
function frameMeta.Hide(self)
    self.__shown = false
    for _, g in ipairs(rawget(self, "__groups") or {}) do g.__playing = false end
end
function frameMeta.SetShown(self, on) self.__shown = on and true or false end
function frameMeta.IsShown(self) return self.__shown end
function frameMeta.IsVisible(self)
    local parent = self.__parent
    return self.__shown and (getmetatable(parent) ~= frameMeta or parent:IsVisible())
end
function frameMeta.GetWidth(self) return self.__w or 100 end
function frameMeta.GetHeight(self) return self.__h or 20 end
function frameMeta.SetWidth(self, w) self.__w = w end
function frameMeta.SetHeight(self, h) self.__h = h end
function frameMeta.SetSize(self, w, h) self.__w, self.__h = w, h end
function frameMeta.GetSize(self) return self.__w or 100, self.__h or 20 end
function frameMeta.GetVerticalScroll(self) return self.__scroll or 0 end
function frameMeta.SetVerticalScroll(self, v) self.__scroll = v end
function frameMeta.GetStringWidth() return 50 end
function frameMeta.GetStringHeight() return 14 end
function frameMeta.GetText(self) return self.__text end
function frameMeta.SetText(self, t) self.__text = t end
function frameMeta.GetName(self) return self.__name end
function frameMeta.GetParent(self) return self.__parent end
function frameMeta.GetLeft() return 0 end
-- (a bag frame's item buttons: none)
function frameMeta.EnumerateValidItems() return function() end end
function frameMeta.GetRight() return 100 end
function frameMeta.GetTop() return 100 end
function frameMeta.GetBottom() return 0 end
function frameMeta.GetCenter() return 50, 50 end
function frameMeta.GetScale() return 1 end
function frameMeta.GetEffectiveScale() return 1 end
function frameMeta.GetAlpha() return 1 end
function frameMeta.GetFrameLevel() return 1 end
function frameMeta.GetNumPoints() return 0 end
function frameMeta.GetObjectType() return "Frame" end
function frameMeta.IsObjectType() return true end
function frameMeta.IsMouseOver() return false end
function frameMeta.IsForbidden() return false end
function frameMeta.GetAttribute(self, k) return self.__attr[k] end
function frameMeta.SetAttribute(self, k, v) self.__attr[k] = v end
function frameMeta.GetValue() return 0 end
function frameMeta.GetMinMaxValues() return 0, 1 end
function frameMeta.GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function frameMeta.GetNumChildren() return 0 end
function frameMeta.GetChildren() return end
function frameMeta.GetRegions() return end
function frameMeta.CreateTexture(self) return Frame(nil, self) end
function frameMeta.CreateFontString(self) return Frame(nil, self) end
function frameMeta.CreateMaskTexture(self) return Frame(nil, self) end
function frameMeta.CreateLine(self) return Frame(nil, self) end
-- (animation groups play and stop; hiding a region stops those playing on it, its own and the
-- ones aimed at it, as in game)
local function PlaysOn(region, group)
    local list = rawget(region, "__groups") or {}
    rawset(region, "__groups", list)
    list[#list + 1] = group
end
function frameMeta.CreateAnimationGroup(self)
    local g = Frame(nil, self)
    PlaysOn(self, g)
    return g
end
function frameMeta.SetTarget(self, region) PlaysOn(region, self.__parent) end
function frameMeta.Play(self) self.__playing = true end
function frameMeta.Stop(self) self.__playing = false end
function frameMeta.IsPlaying(self) return self.__playing == true end
function frameMeta.CreateAnimation(self)
    local a = Frame(nil, self)
    self.__anim = self.__anim or a
    return a
end
function frameMeta.GetAnimations(self) return self.__anim end

frameMeta.__call = function() return nil end

function Frame(name, parent)
    local f = setmetatable({ __scripts = {}, __events = {}, __attr = {}, __name = name, __parent = parent,
        __shown = true }, frameMeta)
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end

---------------------------------------------------------------------------
-- The API: what the addons read at load time, given real-ish answers
---------------------------------------------------------------------------
local env = _G
setmetatable(env, { __index = function(_, k)
    -- (our own globals and saved variables: nil until set; QuestieDB isn't
    -- installed)
    if type(k) == "string" and (k:find("^ImprovedForever") or k:find("^Questie")) then return nil end
    -- (other clients' APIs Forever doesn't have)
    if k == "WatchFrame" or k == "ShiftQuestWatches" or k == "GetSuperTrackedQuestID" then return nil end
    -- (the game's global strings: ITEM_MIN_LEVEL = "Requires Level %d"...)
    if type(k) == "string" and (k:find("^NUM_") or k:find("^MAX_")) then return 4 end
    if type(k) == "string" and k:find("^[A-Z][A-Z0-9_]+$") then
        rawset(env, k, k .. " %d")
        return k .. " %d"
    end
    -- (an unknown global: a frame, also callable as a function answering
    -- nil, as the game's are frames, tables or functions)
    local s = Frame(k)
    rawset(env, k, s)
    return s
end })

UIParent = Frame("UIParent")
WorldFrame = Frame("WorldFrame")
Minimap = Frame("Minimap")
GameTooltip = Frame("GameTooltip")
ItemRefTooltip = Frame("ItemRefTooltip")
function CreateFrame(_, name, parent) return Frame(name, parent) end
function CreateFont(name) return Frame(name) end
function GetTime() return 1000 end
function time() return os.time() end
date = os.date
function GetServerTime() return os.time() end
function InCombatLockdown() return false end
function IsKeyDown() return false end
function GetCVar() return "1" end
function GetCVarBool() return false end
function SetCVar() end
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function UnitName() return "Player", "Realm" end
function UnitLevel() return 60 end
function UnitClass() return "Mage", "MAGE", 8 end
function UnitRace() return "Human", "Human" end
function UnitFactionGroup() return "Alliance" end
function UnitGUID() return "Player-1-0001" end
function UnitExists() return true end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function GetBuildInfo() return "1.15.0", "1", "Oct 1 2026", 11500 end
function GetAddOnMetadata() return "0.3.0" end
function IsAddOnLoaded() return false end
function GetNumMacros() return 0, 0 end
function GetMacroInfo() return nil end
function GetBindingKey() return nil end
function GetItemInfo() return nil end
function GetInventoryItemID() return nil end
function GetNumSpellTabs() return 0 end
function GetMoney() return 0 end
function PlaySound() end
-- (hooks on a table's function kept, for the checks to call them as the game would, and run
-- after a function the table has itself; a hook on a global function runs after it)
local tableHooks = {}
function hooksecurefunc(t, name, fn)
    local target, key, hook = _G, t, name
    if type(t) == "table" and fn then
        tableHooks[#tableHooks + 1] = { name = name, fn = fn }
        if type(rawget(t, name)) ~= "function" then return end
        target, key, hook = t, name, fn
    elseif type(t) ~= "string" then
        return
    end
    local orig = target[key]
    rawset(target, key, function(...)
        local r = { orig(...) }
        hook(...)
        return unpack(r)
    end)
end
-- (UISpecialFrames: a game window, one of another addon's, one of ours; an
-- entry an addon put there is tainted by it)
-- (and a game frame another addon listed: its entry tainted, its global not)
UISpecialFrames = { "GameSpecialWindow", "OtherAddonWindow", "ImprovedForeverSpecialWindow", "GameFrameListedByAddon" }
local specialBy = { [2] = "OtherAddon", [3] = "ImprovedForever_Wiki", [4] = "OtherAddon" }
local addonGlobals = { OtherAddonWindow = true, ImprovedForeverSpecialWindow = true }
for _, name in ipairs(UISpecialFrames) do Frame(name) end
function issecurevariable(t, key)
    if t == UISpecialFrames and specialBy[key] then return false, specialBy[key] end
    if type(t) == "string" and addonGlobals[t] then return false, "OtherAddon" end
    return true
end
function securecall(fn, ...) return fn(...) end
function SetOverrideBinding() end
function SetOverrideBindingClick() end
function ClearOverrideBindings() end
function RegisterStateDriver() end
function UnregisterStateDriver() end
function GetCoinTextureString(c) return tostring(c) end
function debugprofilestop() return 0 end
NUM_BAG_SLOTS = 4
MAX_ACCOUNT_MACROS = 120
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end })
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
SlashCmdList = {}
Enum = Stub()
Settings = Stub()
C_Timer = { After = function() end, NewTicker = function() return Stub() end, NewTimer = function() return Stub() end }
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemID = function() return nil end,
    GetContainerItemInfo = function() return nil end, GetContainerNumFreeSlots = function() return 0, 0 end }
function GetContainerNumSlots() return 0 end
C_QuestLog = { GetNumQuestWatches = function() return 0 end, GetNumQuestLogEntries = function() return 0, 0 end,
    GetQuestIDForQuestWatchIndex = function() return nil end, AddQuestWatch = function() end,
    GetLogIndexForQuestID = function() return nil end, GetDistanceSqToQuest = function() return nil end,
    GetInfo = function() return nil end, IsComplete = function() return false end }
function GetNumQuestLeaderBoards() return 0 end
function GetNumQuestWatches() return 0 end
C_Texture = { GetAtlasInfo = function() return nil end }
C_CVar = { GetCVar = function() return "1" end, GetCVarBool = function() return false end, SetCVar = function() end }
C_AddOns = { IsAddOnLoaded = function() return false end, GetAddOnMetadata = function() return "0.3.0" end,
    GetNumAddOns = function() return 0 end }
C_GamePad = { IsEnabled = function() return true end, GetActiveDeviceID = function() return 1 end,
    GetDeviceMappedState = function() return nil end, GetDeviceRawState = function() return nil end,
    GetCombinedDeviceID = function() return 1 end, GetPowerLevel = function() return nil end,
    SetVibration = function() end, StopVibration = function() end, ButtonIndexToBinding = function() return nil end }

-- Lua helpers the game adds
function strsplit(sep, s, n)
    local out, i = {}, 1
    s = tostring(s or "")
    while true do
        local a, b = s:find(sep, i, true)
        if not a or (n and #out == n - 1) then out[#out + 1] = s:sub(i) break end
        out[#out + 1] = s:sub(i, a - 1)
        i = b + 1
    end
    return unpack(out)
end
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function strlower(s) return s:lower() end
function strupper(s) return s:upper() end
function strmatch(s, p) return s:match(p) end
function strfind(...) return string.find(...) end
function strsub(...) return string.sub(...) end
function strlen(s) return #s end
function strrep(...) return string.rep(...) end
function gsub(...) return string.gsub(...) end
format = string.format
tinsert, tremove, tconcat, sort = table.insert, table.remove, table.concat, table.sort
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
function Mixin(o, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do o[k] = v end end return o end
function CreateFromMixins(...) return Mixin({}, ...) end
function Clamp(v, a, b) return math.min(math.max(v, a), b) end
floor, ceil, abs, max, min, sqrt = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt
mod = math.fmod
bit = bit or require("bit")

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
local failures = 0
local function report(where, err)
    failures = failures + 1
    -- (the traceback's lines in the addons only)
    local lines = {}
    for line in tostring(err):gmatch("[^\n]+") do
        -- (a check's own failure: its place in this file cut, its message kept)
        line = line:gsub("^%S*loadcheck%.lua:%d+: ", "")
        if not line:find("loadcheck.lua") and not line:find("%[C%]") and line ~= "stack traceback:" then
            lines[#lines + 1] = line
        end
    end
    print("  ERROR " .. where .. ": " .. table.concat(lines, "\n      "))
end

local function readToc(folder)
    local fh = io.open(ROOT .. folder .. "/" .. folder .. ".toc")
    if not fh then return nil end
    local toc = { files = {}, deps = {}, opt = {} }
    for line in fh:lines() do
        line = line:gsub("\r", "")
        local tag, value = line:match("^##%s*([%w%-]+):%s*(.-)%s*$")
        if tag == "Dependencies" or tag == "RequiredDeps" then
            for d in value:gmatch("[^,%s]+") do toc.deps[#toc.deps + 1] = d end
        elseif tag == "OptionalDeps" then
            for d in value:gmatch("[^,%s]+") do toc.opt[#toc.opt + 1] = d end
        elseif not line:match("^#") and line:match("%S") then
            toc.files[#toc.files + 1] = line:match("^%s*(.-)%s*$")
        end
    end
    fh:close()
    return toc
end

local function loadAddon(folder, loaded, wanted)
    if loaded[folder] then return true end
    local toc = readToc(folder)
    if not toc then return false end
    loaded[folder] = "loading"
    for _, d in ipairs(toc.deps) do
        -- (another author's addon (Spoken): not in this repo, taken as
        -- there, the API stub standing in for it)
        if readToc(d) and (not wanted[d] or not loadAddon(d, loaded, wanted)) then
            print("  " .. folder .. ": missing dependency " .. d .. " (not loaded)")
            loaded[folder] = nil
            return false
        end
    end
    for _, d in ipairs(toc.opt) do
        if wanted[d] then loadAddon(d, loaded, wanted) end
    end
    local private = {}
    for _, file in ipairs(toc.files) do
        if file:match("%.lua$") then
            local chunk, err = loadfile(ROOT .. folder .. "/" .. file)
            if not chunk then
                report(folder .. "/" .. file, err)
            else
                local ok, e = xpcall(function() return chunk(folder, private) end, debug.traceback)
                if not ok then report(folder .. "/" .. file, e) end
            end
        end
    end
    loaded[folder] = true
    loaded[#loaded + 1] = folder
    return true
end

local function fire(event, ...)
    local args = { ... }
    for _, f in ipairs(frames) do
        local fn = f.__scripts.OnEvent
        if fn and f.__events[event] then
            local ok, e = xpcall(function() fn(f, event, unpack(args)) end, debug.traceback)
            if not ok then report("event " .. event .. " (" .. tostring(f.__name) .. ")", e) end
        end
    end
end

local function run(folders, checks)
    -- (each one's required addons with it, as the game insists on them)
    local wanted = {}
    local function want(f)
        if wanted[f] then return end
        wanted[f] = true
        local toc = readToc(f)
        for _, d in ipairs(toc and toc.deps or {}) do
            if readToc(d) then
                want(d)
                table.insert(folders, 1, d)
            end
        end
    end
    for _, f in ipairs({ unpack(folders) }) do want(f) end
    local loaded = {}
    for _, f in ipairs(folders) do loadAddon(f, loaded, wanted) end
    for _, f in ipairs(loaded) do fire("ADDON_LOADED", f) end
    fire("VARIABLES_LOADED")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", true, false)
    for _, check in ipairs(checks or {}) do
        local ok, e = xpcall(check.fn, debug.traceback)
        if not ok then report("check " .. check.name, e) end
    end
end

-- The folders with a TOC
local function allFolders()
    local list = {}
    local p = io.popen("ls -d " .. ROOT .. "ImprovedForever*/ 2>/dev/null")
    for line in p:lines() do
        local name = line:match("([^/]+)/?$")
        if name and readToc(name) then list[#list + 1] = name end
    end
    p:close()
    table.sort(list)
    return list
end

-- After loading: open each panel the modules give (what a player does first)
local CHECKS = {
    -- (drawn from a character with a bag and a bank tab written; every press once)
    { name = "bags window", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local BG = IF and IF.Bags
        if not BG then return end
        BG.Chars()[BG.Me()] = { name = "Me", class = "WARRIOR", level = 8, money = 12345, bagsAt = 0,
            bags = { { size = 12, slots = { [1] = "6948", [3] = "2589:20", [5] = "item:2036:15::::::::8#2" } } },
            bank = { { item = 4496, size = 6, slots = { [2] = "2589:5" } } } }
        BG.Open()
        for _, b in ipairs({ "PADDDOWN", "PADDRIGHT", "PADDUP", "PADDLEFT", "PADRSHOULDER", "PADLSHOULDER",
            "PADRSTICK", "PAD4", "PADBACK" }) do
            IF.Bags.Press(b)
        end
        -- (away by Select: its watch a frame)
        local win = rawget(_G, "ImprovedForeverBagsWindow")
        win:GetScript("OnUpdate")(win)
        IF.Bags.Press("PAD2")
        BG.Toggle()
    end },
    { name = "config panel", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if IF and IF.Menu and IF.Menu.Open then
            IF.Menu.Open()
            for _, tab in ipairs(IF.Menu.TABS or {}) do IF.Menu.SetTab(tab.key) end
            IF.Menu.Close()
        end
    end },
    -- (a CVar changed: the pad's bindings set again only for the ones they read)
    { name = "bindings on CVAR_UPDATE", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local O, MW, T = IF and IF.Override, IF and IF.MyWheels, IF and IF.Touch
        local saved = { O and O.Apply, MW and MW.ApplyWheelKeys, T and T.Apply }
        local applied = 0
        if O then O.Apply = function() applied = applied + 1 end end
        if MW then MW.ApplyWheelKeys = function() applied = applied + 1 end end
        if T then T.Apply = function() applied = applied + 1 end end
        fire("CVAR_UPDATE", "Sound_MasterVolume", "0.5")
        local other = applied
        fire("CVAR_UPDATE", "GamePadEmulateShift", "PADLSHOULDER")
        if O then O.Apply = saved[1] end
        if MW then MW.ApplyWheelKeys = saved[2] end
        if T then T.Apply = saved[3] end
        assert(other == 0, "an unrelated CVar set the bindings again")
        assert(applied == (O and 1 or 0) + (MW and 1 or 0) + (T and 1 or 0), "a modifier CVar left the bindings as they were")
    end },
    { name = "config panel presses", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Menu and #IF.Menu.TABS > 0) then return end
        local M = IF.Menu
        M.Open()
        for _, tab in ipairs(M.TABS) do
            M.SetTab(tab.key)
            for _, name in ipairs({ "DOWN", "DOWN", "RIGHT", "LEFT", "UP", "RT", "DOWN", "RIGHT", "LT",
                "Y", "UP", "LEFT", "A", "DOWN", "UP", "A", "B", "A", "B", "RT", "A", "DOWN", "A", "B" }) do
                if not M.IsOpen() then M.Open(tab.key) end
                M.Press(name)
            end
            local page = tab.page
            if page.StickStep then page:StickStep(1) M.Render() end
            if page.StickSide then page:StickSide(1) M.Render() end
        end
        M.Close()
    end },
    -- (Immersion's quest page: every reward the game's window lists, in its
    -- order (choices, spells, items, currencies), one not loaded yet kept in
    -- its place, each one ours for the game's button the pad is on)
    { name = "immersion quest rewards", fn = function()
        local IN = rawget(_G, "ImprovedForever") and ImprovedForever.Interface
        if not (IN and IN.NpcDialog) then return end
        local function check(ok, msg) if not ok then error(msg, 0) end end
        -- (a local of the dialog's, by the upvalues from its ticker down)
        local function Up(fn, want, depth)
            for i = 1, 200 do
                local name, value = debug.getupvalue(fn, i)
                if not name then break end
                if name == want then return value end
                if type(value) == "function" and depth > 0 then
                    local found = Up(value, want, depth - 1)
                    if found then return found end
                end
            end
        end
        local Tick
        for _, f in ipairs(frames) do
            local fn = f.__scripts.OnUpdate
            Tick = Tick or (fn and Up(fn, "Tick", 2))
        end
        check(Tick, "the dialog's Tick is found")
        local Detail, Build, KeyOf = Up(Tick, "Detail", 2), Up(Tick, "Build", 0), Up(Tick, "KeyOf", 0)
        local saved = {}
        local stubs = {
            GetNumQuestChoices = function() return 1 end,
            GetNumQuestRewards = function() return 2 end,
            GetQuestItemInfo = function(kind, i)
                if kind == "reward" and i == 2 then return nil end
                return kind .. i, 100 + i, 1
            end,
            GetQuestItemInfoLootType = function() return 0 end,
            GetQuestID = function() return 5 end,
            GetRewardTitle = function() return "the Brave" end,
            C_QuestInfoSystem = {
                GetQuestRewardSpells = function() return { 123 } end,
                GetQuestRewardSpellInfo = function() return { texture = 7, name = "Mining", isTradeskillSpell = true } end,
                GetQuestRewardCurrencies = function() return { { texture = 8, name = "Mark", totalRewardAmount = 3, currencyID = 1 } } end,
            },
            C_SpellBook = { IsSpellInSpellBook = function() return false end },
            C_QuestOffer = { GetQuestOfferMajorFactionReputationRewards = function() return nil end },
            CurrencyContainerUtil = { GetCurrencyContainerInfo = function(_, amount, name, texture) return name, texture, amount end },
        }
        for k, v in pairs(stubs) do saved[k] = rawget(_G, k) rawset(_G, k, v) end
        local ok, err = pcall(function()
            local d = Detail()
            local keys = {}
            for _, it in ipairs(d.items) do keys[#keys + 1] = it.key end
            check(table.concat(keys, ",") == "choice:1,spell:123,reward:1,reward:2,reward:c1",
                "the rewards in the game's order: " .. table.concat(keys, ","))
            check(d.pending and d.lines[1] == "Title: the Brave", "a reward waits for its data; the title a line")
            Build(d)
            local byKey = Up(Build, "byKey", 0)
            local spell = byKey[KeyOf({ rewardSpellID = 123 })]
            local currency = byKey[KeyOf({ type = "reward", objectType = "currency", GetID = function() return 1 end })]
            local item = byKey[KeyOf({ type = "reward", objectType = "item", GetID = function() return 2 end })]
            check(spell and spell.spellID == 123, "the game's spell button is our spell")
            check(currency and currency.currency and currency.index == 1, "the game's currency button is our currency")
            -- (rawget: the stand-in's frames answer any unset field)
            check(item and not rawget(item, "currency") and item.index == 2, "the game's item button is our item, not the currency")
        end)
        for k in pairs(stubs) do rawset(_G, k, saved[k]) end
        check(ok, err)
        -- (Spoken_Quests' Contribute button faded with the game's window, also without its Listen button)
        local FadeSubtitle = Up(Tick, "FadeSubtitle", 0)
        local F, contribute, faded = ImprovedForever.Focus, Frame(), false
        local fade = F.Fade
        F.Fade = function(region, on) if region == contribute then faded = on end end
        rawset(_G, "VoiceOver", { ContributeButton = { button = contribute } })
        FadeSubtitle(true)
        F.Fade = fade
        rawset(_G, "VoiceOver", nil)
        check(faded, "Contribute not faded without the Listen button")
    end },
    -- (two of ours: the one opened last holds the pad, both name the other in
    -- their legend, and L2 / R2 moves the pad either way)
    { name = "focus switch between two of ours", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Focus and IF.Focus.Switch) then return end
        local F = IF.Focus
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local function Window(x)
            local w = CreateFrame("Frame")
            w.__shown = true
            function w:GetCenter() return x, 300 end
            function w:GetEffectiveScale() return 1 end
            return w
        end
        local scale = rawget(UIParent, "GetEffectiveScale")
        rawset(UIParent, "GetEffectiveScale", function() return 1 end)
        local left, right = Window(100), Window(500)
        local a, b = F.Switch(left), F.Switch(right)
        a:Take()
        b:Take()
        check(F.Holding() == right and a.focus == "game", "the last opened holds the pad")
        local hint = b:Hint()
        check(hint and hint[2] == "LT", "its legend names L2 to the other")
        check(b:Press("LT") and F.Holding() == left, "L2 hands the pad over")
        hint = a:Hint()
        check(hint and hint[2] == "RT", "the other's legend names R2 back")
        check(a:Press("RT") and F.Holding() == right, "R2 hands it back")
        left.__shown, right.__shown = false, false
        rawset(UIParent, "GetEffectiveScale", scale)
    end },
    -- (the core's dropdown: an action closes it and runs; a hold entry runs
    -- only when Cross is let go after its hold, whatever else is let go)
    { name = "dropdown actions", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Dropdown) then return end
        local now, ran, getTime = 1000, {}, GetTime
        GetTime = function() return now end
        local menu = IF.Dropdown(CreateFrame("Frame"))
        local function build()
            return {
                { kind = "action", text = "go", run = function() ran[#ran + 1] = "go" end },
                { kind = "action", text = "hold", hold = 1, run = function() ran[#ran + 1] = "hold" end },
            }
        end
        menu:Open(build)
        menu:Press("A", true)
        assert(ran[1] == "go" and not menu:IsShown(), "an action runs and closes the menu")
        menu:Open(build)
        menu:Press("DOWN", true)
        menu:Press("A", true)
        now = now + 0.5
        menu:Press("A", false)
        assert(#ran == 1 and menu:IsShown(), "a hold let go early runs nothing")
        menu:Press("A", true)
        now = now + 2
        menu:Press("DOWN", false)
        menu:Press("A", false)
        assert(ran[2] == "hold" and not menu:IsShown(), "a full hold runs and closes the menu")
        GetTime = getTime
    end },
    -- (the navigator's Y on an item: the menu shown on the press, with the
    -- item's entries; the game errors on a nil bag or slot)
    { name = "navigator item menu", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Navigator and IF.Dropdown) then return end
        local getInfo = C_Container.GetContainerItemInfo
        -- (level 0: a message without a place, which the report would drop)
        local function check(ok, msg) if not ok then error(msg, 0) end end
        C_Container.GetContainerItemInfo = function(bag, slot)
            check(type(bag) == "number" and type(slot) == "number", "the item's bag and slot reach the game")
            return { itemID = 25, stackCount = 5, hyperlink = "[Sword]", quality = 1 }
        end
        local nav = IF.Navigator.New(CreateFrame("Frame"))
        local item = CreateFrame("Button")
        item.GetBagID = function() return 0 end
        item.GetID = function() return 3 end
        nav.on, nav.sel = true, item
        local ok, err = pcall(nav.Press, nav, "PAD4", true)
        C_Container.GetContainerItemInfo = getInfo
        check(ok, err)
        check(nav:MenuShown(), "Y opens the menu on the press")
        local kinds = {}
        for _, e in ipairs(nav.menu.entries) do kinds[#kinds + 1] = e.kind end
        check(nav.menu.entries[1].text == "[Sword]" and #kinds >= 3,
            "the menu has the item's title and entries: " .. table.concat(kinds, ","))
        nav.menu:Close()
    end },
    -- (UISpecialFrames at login: another addon's window joins L2 / R2; the game's,
    -- ours don't)
    { name = "addon windows from UISpecialFrames", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local W = IF and IF.AddonWindows
        if not W then return end
        local function check(ok, msg) if not ok then error(msg, 0) end end
        check(W.Watched(OtherAddonWindow), "another addon's window joins")
        check(not W.Watched(GameSpecialWindow), "the game's doesn't")
        check(not W.Watched(GameFrameListedByAddon), "a game frame another addon listed doesn't")
        check(not W.Watched(ImprovedForeverSpecialWindow), "ours doesn't")
        IF.db.addonWindows = false
        local off = not W.Scanned()
        IF.db.addonWindows = nil
        check(off and W.Scanned(), "the General tab's switch turns them off and on")
        -- (out of the way of the checks after: closing a window hands the pad to the nearest shown)
        for _, name in ipairs(UISpecialFrames) do _G[name].__shown = false end
    end },
    -- (a held D-pad repeat steps through its press's list, the window's tree walked once)
    { name = "navigator held repeat", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Navigator) then return end
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local root, buttons, walks = CreateFrame("Frame"), {}, 0
        for i = 1, 3 do
            local b = CreateFrame("Button")
            b.GetCenter = function() return i * 50, 100 end
            b.GetWidth = function() return 40 end
            b.GetObjectType = function() return "Button" end
            b.IsEnabled = function() return true end
            b.IsMouseEnabled = function() return true end
            b.navigatorSkip, b.smartNavigationIgnored = false, false
            buttons[i] = b
        end
        root.GetChildren = function() walks = walks + 1 return unpack(buttons) end
        local nav = IF.Navigator.New(CreateFrame("Frame"), root)
        nav.on, nav.sel = true, buttons[1]
        nav:Press("PADDRIGHT", true)
        check(nav.sel == buttons[2] and walks == 1, "the press walks the tree and steps")
        nav:Move("PADDRIGHT", true)
        check(nav.sel == buttons[3] and walks == 1, "the repeat steps without a walk")
        nav:Press("PADDRIGHT", false)
        nav:Press("PADDLEFT", true)
        check(nav.sel == buttons[2] and walks == 2, "a new press walks again")
        nav:Press("PADDLEFT", false)
    end },
    -- (a switch's legend entry: the same table while it stays the same, a new one when it changes)
    { name = "switch hint kept", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Focus and IF.Focus.Switch) then return end
        local label = "Character"
        local sw = IF.Focus.Switch(CreateFrame("Frame"), { label = function() return label end })
        -- (never holding the pad, which the other checks look at)
        sw.focus = "game"
        sw.Behind = function() return label, "LT" end
        local first = sw:Hint()
        if sw:Hint() ~= first then error("a new table for the same entry", 0) end
        label = "Bank"
        local second = sw:Hint()
        if second == first or second[3] ~= "Bank" then error("the old table for a changed entry", 0) end
    end },
    -- (the navigator's legend names the window switch's L2 / R2 just before B, while nav.hint gives one)
    { name = "navigator legend switch", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Navigator and IF.InputLegend) then return end
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local nav = IF.Navigator.New(CreateFrame("Frame"))
        nav.on = true
        local hint = { "PADRTRIGGER", "RT", "Character", pad = true }
        nav.hint = function() return hint end
        nav:ShowLegend()
        local defs = nav.legend.defs
        check(defs and defs[#defs - 1] == hint and defs[#defs][1] == "PAD2", "the switch's entry just before B")
        hint = nil
        nav:ShowLegend()
        defs = nav.legend.defs
        check(defs and defs[#defs - 1][1] ~= "PADRTRIGGER", "no switch: no entry")
    end },
    -- (a window the frame manager shows and focuses while the panel is up:
    -- the panel stays open behind it; in front again when it closes, or on
    -- opening or toggling the panel)
    { name = "panel behind a game window", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Menu and #IF.Menu.TABS > 0) then return end
        local M = IF.Menu
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local shown
        for _, h in ipairs(tableHooks) do
            if h.name == "FrameShown" then shown = h.fn end
        end
        check(shown, "the panel hooks the frame manager's FrameShown")
        local gamepadMode = GamepadMode
        local game = CreateFrame("Frame")
        local manager = { shownFrames = { game }, focusedFrame = game, isUIFocused = true }
        GamepadMode = { FrameControlsManager = manager }
        M.Open()
        shown(manager, game)
        check(M.IsOpen() and M.Behind(), "a window shown takes the pad, the panel stays open behind it")
        M.Open()
        check(not M.Behind(), "opening the panel again brings it to front")
        shown(manager, game)
        M.Toggle()
        check(M.IsOpen() and not M.Behind(), "the toggle brings it to front, not closed")
        shown(manager, game)
        game:Hide()
        M.OnUpdate(0)
        check(M.IsOpen() and not M.Behind(), "the window closing brings the panel to front")
        GamepadMode = gamepadMode
        M.Close()
    end },
    -- (the Addons tab: /if addons opens on it; L1 / R1 jump between addons;
    -- A runs a command (by the secure button on the pad) or opens a page)
    { name = "addons tab", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Addons and IF.Menu) then return end
        local M, AD = IF.Menu, IF.Addons
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local commands, ran = AD.Commands, nil
        SlashCmdList.ALPHA = function(msg) ran = msg end
        AD.Commands = function()
            return {
                { title = "Alpha", entries = { { kind = "slash", text = "/al", key = "ALPHA", aliases = { "/al" } },
                    { kind = "settings", text = "Alpha", id = 7, openable = true } } },
                { title = "Beta", entries = { { kind = "ldb", text = "Beta" } } },
            }
        end
        IF.RunCommand("addons")
        check(M.IsOpen() and M.tab == "addons", "/if addons opens the panel on the Addons tab")
        local page
        for _, tab in ipairs(M.TABS) do
            if tab.key == "addons" then page = tab.page end
        end
        local function verb()
            for _, h in ipairs(page:Help()) do
                if h.press == "A" then return h.verb end
            end
        end
        check(verb() == "Run" and page:PadButton("PAD1") == "ImprovedForeverAddonsRun"
            and ImprovedForeverAddonsRun:GetAttribute("macrotext") == "/al", "A on a command runs it by the secure button")
        M.Press("A")
        check(ran == "", "A clicked runs the command without arguments")
        M.Press("DOWN")
        check(verb() == "Open" and page:PadButton("PAD1") == nil, "A on a settings page opens it")
        M.Press("RB")
        check(page:Entry().text == "Beta", "R1 jumps to the next addon")
        M.Press("RB")
        check(page:Entry().text == "Beta", "R1 on the last addon stays")
        M.Press("LB")
        check(page:Entry().text == "/al", "L1 jumps to the previous addon's first entry")
        AD.Commands, SlashCmdList.ALPHA = commands, nil
        M.Close()
    end },
    -- (the Immersion module: the party cards on a target change, previewed and back)
    { name = "party cards", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local PC = IF and IF.Interface and IF.Interface.PartyCards
        if not PC then return end
        -- (your target's card marked in gold, unmarked once you target another)
        local card, isUnit = _G.ImprovedForeverPartyCard1, UnitIsUnit
        -- (no preview: the stand-in's frames answer an unset field)
        card.sample = false
        UnitIsUnit = function(a, b) return a == card.unit and b == "target" end
        fire("PLAYER_TARGET_CHANGED")
        local marked = card.targetMark:IsShown()
        UnitIsUnit = function() return false end
        fire("PLAYER_TARGET_CHANGED")
        UnitIsUnit = isUnit
        rawset(card, "sample", nil)
        assert(marked and not card.targetMark:IsShown(), "the target's party card not marked, or kept marked")
        PC.TogglePreview()
        PC.TogglePreview("off")
        -- (the raid-style party's target boxes faded, the player's and a fifth pet's, and the
        -- player's again after the game hides and shows it on a target change)
        local party = Frame("CompactPartyFrame")
        local me, pet = Frame("CompactPartyFrameMember1", party), Frame("CompactPartyFramePet5", party)
        me.selectionHighlight, pet.selectionHighlight = Frame(nil, me), Frame(nil, pet)
        party.memberUnitFrames, party.petUnitFrames = { me }, { pet }
        PC.Apply()
        assert(IF.Focus.Faded(pet.selectionHighlight), "a fifth pet's target box not faded")
        me.selectionHighlight:Hide()
        me.selectionHighlight:Show()
        CompactUnitFrame_UpdateSelectionHighlight(me)
        assert(IF.Focus.Faded(me.selectionHighlight), "the player's target box shown again unfaded")
    end },
    -- (the Wheel module: a wheel of each kind made, built and shown)
    { name = "wheel kinds", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local MW, KD = IF and IF.MyWheels, IF and IF.WheelKinds
        if not (MW and KD and IF.Menu) then return end
        local M = IF.Menu
        M.Open()
        M.SetTab("wheel")
        for _, kind in ipairs(KD.ORDER) do
            if #MW.List() >= MW.MAX then table.remove(MW.List(), 1) end
            local id = MW.Create(kind.key)
            IF.RingBuilders[MW.RingKey(id)]()
            MW.Page.key = MW.RingKey(id)
            for _, name in ipairs({ "RIGHT", "RT", "A", "Y", "X", "LEFT" }) do
                if not M.IsOpen() then M.Open("wheel") end
                M.Press(name)
            end
        end
        if KD.Equip then KD.Equip({ item = 1, slot = 13 }) end
        M.Close()
    end },
    -- (Immersion's buff row: no caps, its icons pushed together (overlapping at most) when all the
    -- auras don't fit in 3 lines at the size they were built with, their times hidden while too
    -- close; its lane from after the minion card (else the player frame) to the shown party cards,
    -- wrapping upward; the cooldowns' lane from the shown party cards' right edge)
    { name = "immersion buff row", fn = function()
        local IN = rawget(_G, "ImprovedForever") and ImprovedForever.Interface
        if not (IN and IN.BuffTimeline and IN.PartyCards and IN.HudLayout and IN.PartyPad) then return end
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local function Up(fn, want)
            for i = 1, 200 do
                local name, value = debug.getupvalue(fn, i)
                if not name then return end
                if name == want then return value, i end
            end
        end
        local ShowBuffs = Up(Up(IN.BuffTimeline.Apply, "Watch"), "ShowBuffs")
        local Container = Up(ShowBuffs, "Container")
        -- (made afresh, wherever login placed it)
        debug.setupvalue(Container, select(2, Up(Container, "container")), nil)
        debug.setupvalue(ShowBuffs, select(2, Up(ShowBuffs, "placedAt")), nil)
        local HL, s = IN.HudLayout, IN.Settings()
        local saved = { CreateFrame = CreateFrame, C_UnitAuras = rawget(_G, "C_UnitAuras"), UnitExists = UnitExists,
            size = HL.CooldownIconSize, w = rawget(UIParent, "__w"), partyX = s.partyX }
        local rec, measured, auras = { caps = {}, spacing = {} }, nil, { HELPFUL = 0, HARMFUL = 0 }
        CreateFrame = function(kind, ...)
            if kind ~= "AuraContainer" then return saved.CreateFrame(kind, ...) end
            local c = saved.CreateFrame("Frame", ...)
            c.AddAuraGroup = function(_, key, _, o)
                rec.caps[key], rec.size, rec.spacing[key] = o.maxFrameCount or "none", o.layout.elementWidth, o.layout.elementSpacing
                local b = saved.CreateFrame("Frame")
                local made = b.CreateFontString
                -- (the first a button makes: its time)
                b.CreateFontString = function(...)
                    local t = made(...)
                    rec.time = rec.time or t
                    return t
                end
                o.initializeFrame(b)
            end
            c.SetAuraGroupLayout = function(_, key, o) rec.spacing[key] = o.elementSpacing end
            c.SetFlowLayoutMaximumLineSize = function(_, n) rec.line = n end
            c.SetFlowLayoutGrowthDirection = function(_, _, v) rec.up = v == AnchorUtil.FlowDirection.Up end
            c.SetPoint = function(_, _, _, _, x) rec.x = x end
            return c
        end
        C_UnitAuras = { GetUnitAuraInstanceIDs = function(_, filter)
            if auras == "secret" then error("secret") end
            local ids = {}
            for i = 1, auras[filter] do ids[i] = i end
            return ids
        end }
        -- (the spacing both groups got, the same, or nil)
        local function spacing()
            return rec.spacing.buffs == rec.spacing.debuffs and rec.spacing.buffs or nil
        end
        HL.CooldownIconSize = function() return measured end
        UnitExists = function(unit) return unit == "party1" or unit == "party2" end
        UIParent.__w = 1920
        local minion, cards = _G.ImprovedForeverMinionCard1, {}
        for i = 1, 4 do
            local b = _G["ImprovedForeverPartyCard" .. i]
            b.SetPoint = function(self, _, _, _, x) self.__x = x end
            b.GetLeft = function(self) return UIParent:GetWidth() / 2 + self.__x end
            b.GetRight = function(self) return self:GetLeft() + self.cardW end
            b.__shown = false
            cards[i] = b
        end
        minion.__shown = false
        minion.GetRight = function() return 177 end
        s.partyX = 0
        -- (the cooldowns' lane: its near end, the party spells' diamond hidden)
        local cooldowns = Up(IN.BuffTimeline.Apply, "cooldowns")
        -- (the row's OnUpdate, or IF.Prof's wrapper round it)
        local onUpdate = cooldowns.holder:GetScript("OnUpdate")
        local Lane = (Up(onUpdate, "source") or Up(Up(onUpdate, "fn"), "source")).Lane
        local PP = IN.PartyPad
        saved.ppShown, PP.Shown = PP.Shown, function() return false end
        local ok, err = pcall(function()
            check(Lane() == 1152, "no cards: the cooldowns after a full row's half 164 + 28: " .. tostring(Lane()))
            -- (lane: the player frame's right 100 + 20 to 960 - a full row's half 164 - 28: 648)
            ShowBuffs(true)
            check(rec.size == 24 and rec.x == 120 and rec.line == 648 and rec.up, "the row built at 24, lane 120 + 648, wrapping up")
            check(rec.caps.buffs == "none" and rec.caps.debuffs == "none", "no caps: " .. tostring(rec.caps.buffs))
            check(spacing() == 10 and rec.time.__shown, "no auras: the normal spacing, times shown")
            -- (3 lines of 19 at 24 + 10: 57 fit; 60 make 20 a line: (648 - 480) / 19 = 8)
            auras.HELPFUL = 57
            ShowBuffs(true)
            check(spacing() == 10, "57 buffs fit 3 lines: the normal spacing: " .. tostring(spacing()))
            auras.HELPFUL = 60
            ShowBuffs(true)
            check(spacing() == 8 and rec.time.__shown, "60 buffs: pushed together to 8: " .. tostring(spacing()))
            measured = 55
            ShowBuffs(true)
            check(spacing() == 8, "the spacing follows the built size, not the measured one: " .. tostring(spacing()))
            -- (30 and 30: the line holding the gap 636 wide, still 20 a line)
            auras.HELPFUL, auras.HARMFUL = 30, 30
            ShowBuffs(true)
            check(spacing() == 8, "30 debuffs and 30 buffs: the gap between them counted: " .. tostring(spacing()))
            -- (40 a line: (648 - 960) / 39 = -8, the icons overlapping, their times hidden)
            auras.HELPFUL, auras.HARMFUL = 120, 0
            ShowBuffs(true)
            check(spacing() == -8 and not rec.time.__shown, "120 buffs: overlapping by 8, times hidden: " .. tostring(spacing()))
            auras.HELPFUL = 1000
            ShowBuffs(true)
            check(spacing() == -16, "far too many: two thirds of an icon hidden at most: " .. tostring(spacing()))
            auras = "secret"
            ShowBuffs(true)
            check(spacing() == -16, "auras unreadable: the last count kept: " .. tostring(spacing()))
            auras = { HELPFUL = 3, HARMFUL = 2 }
            ShowBuffs(true)
            check(spacing() == 10 and rec.time.__shown, "few again: the normal spacing, times back: " .. tostring(spacing()))
            minion.__shown = true
            ShowBuffs(true)
            check(rec.x == 197 and rec.line == 571, "a minion: the lane after its card: " .. tostring(rec.x))
            -- (two cards, 160 wide, centred 200 left: their left 680, the lane to 652)
            s.partyX = -200
            IN.PartyCards.Layout()
            cards[1].__shown, cards[2].__shown = true, true
            ShowBuffs(true)
            check(rec.line == 455, "two party cards moved left: the lane to their left edge: " .. tostring(rec.line))
            check(Lane() == 868, "two party cards moved left: the cooldowns from their right edge 840: " .. tostring(Lane()))
            UnitExists = function() return true end
            IN.PartyCards.Layout()
            cards[3].__shown, cards[4].__shown = true, true
            ShowBuffs(true)
            check(rec.line == 371, "four party cards: the lane shorter: " .. tostring(rec.line))
            check(Lane() == 952, "four party cards: the cooldowns from their right edge 924: " .. tostring(Lane()))
        end)
        CreateFrame, C_UnitAuras, UnitExists, HL.CooldownIconSize = saved.CreateFrame, saved.C_UnitAuras, saved.UnitExists, saved.size
        PP.Shown = saved.ppShown
        UIParent.__w, s.partyX = saved.w, saved.partyX
        check(ok, err)
    end },
    -- (the threat meter right of the party, the cooldowns after it; too little room left them: over their row)
    { name = "threat meter beside the cooldowns", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local IN, TM = IF and IF.Interface, IF and IF.ThreatMeter
        if not (TM and IN and IN.BuffTimeline and IN.PartyCards and IN.GamepadBar) then return end
        local PC, BT, GB = IN.PartyCards, IN.BuffTimeline, IN.GamepadBar
        local meter = _G.ImprovedForeverThreatMeter
        local saved = { PC.RowRight, PC.RightOfParty, BT.CooldownRow, GB.Rect, meter.__shown }
        local x, y
        meter.SetPoint = function(_, _, _, _, px, py) x, y = px, py end
        PC.RowRight = function() return 700, 42 end
        PC.RightOfParty = function() return 760 end
        GB.Rect = function() return 1500 end
        meter.__shown = true
        local far = 1460
        BT.CooldownRow = function() return far, 34, 100 end
        -- (meter 776 to 946, the cooldowns from 962 to 1460: room for 14)
        local ok, err = pcall(function()
            assert(TM.PlaceLow(IN) and x == 776 and y == 42 and TM.LowRight() == 946,
                "room left: the meter beside the party, bottoms level: " .. tostring(y))
            -- (the cooldowns' lane: after the meter, 946 + 28)
            local function Up(fn, want)
                for i = 1, 200 do
                    local name, value = debug.getupvalue(fn, i)
                    if not name then return end
                    if name == want then return value end
                end
            end
            local onUpdate = Up(BT.Apply, "cooldowns").holder:GetScript("OnUpdate")
            local Lane = (Up(onUpdate, "source") or Up(Up(onUpdate, "fn"), "source")).Lane
            assert(Lane() == 974, "the cooldowns not after the meter: " .. tostring(Lane()))
            far = 1050
            assert(TM.PlaceLow(IN) and x == 776 and y == 100 and TM.LowRight() == nil,
                "too little room left: the meter over the cooldowns: " .. tostring(y))
            BT.CooldownRow = function() return nil end
            assert(TM.PlaceLow(IN) and y == 42 and TM.LowRight() == 946, "cooldowns hidden: beside the party")
        end)
        PC.RowRight, PC.RightOfParty, BT.CooldownRow, GB.Rect, meter.__shown = unpack(saved)
        rawset(meter, "SetPoint", nil)
        assert(ok, err)
    end },
    -- (the Immersion module: its settings filled once)
    { name = "immersion settings", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local IN = IF and IF.Interface
        if not IN then return end
        local s = IN.Settings()
        IF.db.plateLog = {}
        assert(s.player == true and IN.Settings() == s and IF.db.plateLog, "Settings: not filled once")
        IF.db.plateLog = nil
    end },
    -- (/if perf: a handler timed, a focus change and the events since in the timeline, every
    -- addon's spikes and each of ours, all in the saved log)
    { name = "perf", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local function check(ok, msg) if not ok then error(msg, 0) end end
        -- (each metric read counts up, so every loaded addon gains frames over 5 ms during the run)
        local reads, profiler = 0, rawget(_G, "C_AddOnProfiler")
        C_AddOnProfiler = { IsEnabled = function() return true end,
            GetAddOnMetric = function() reads = reads + 1; return reads end }
        local addOns = C_AddOns
        local names = { "Spiky", "ImprovedForever" }
        C_AddOns = setmetatable({ GetNumAddOns = function() return 2 end, IsAddOnLoaded = function() return true end,
            GetAddOnInfo = function(i) return names[i] end }, { __index = addOns })
        local after = C_Timer.After
        local report
        C_Timer.After = function(_, fn) report = fn end
        IF.RunCommand("perf 2")
        C_Timer.After = after
        IF.Prof("check", function() end)()
        fire("UPDATE_BINDINGS")
        fire("CVAR_UPDATE", "GamePadEmulateShift", "PADLSHOULDER")
        IF.Binds.FocusChanged()
        report()
        C_AddOns = addOns
        rawset(_G, "C_AddOnProfiler", profiler)
        local has = {}
        for _, line in ipairs(IF.db.perfLog or {}) do
            if line:find("^check: .*slowest call") then has.row = true end
            -- (every call takes 0 here: any handler may head the slowest)
            if line == "slowest single calls:" then has.slowest = true end
            if line:find("^addon ImprovedForever: ") then has.addon = true end
            if line:find("^addons with frames over 5 ms: .*Spiky %d") then has.spikes = true end
            if line:find("^focus: overrides: ") then has.part = true end
            if line:find("focus changed, in game .* ms %(since last: CVAR_UPDATE GamePadEmulateShift 1, UPDATE_BINDINGS 1%)") then
                has.note = true
            end
        end
        check(has.row and has.slowest, "perf: a handler's row or its slowest call missing")
        check(has.addon and has.spikes, "perf: our addon's figure or the addons' spikes missing")
        check(has.part and has.note, "perf: the focus change's parts or its timeline line missing")
    end },
    -- (Immersion's pad bar: a tile left empty drops its whole cooldown, the global one's too)
    { name = "immersion pad tile cooldown cleared", fn = function()
        local IN = rawget(_G, "ImprovedForever") and ImprovedForever.Interface
        local GB = IN and IN.GamepadBar
        if not GB then return end
        local cleared = false
        local b = { gcdStart = 5, cdDuration = 2, cdUntil = 3, cdDoneAt = 4,
            cooldown = { Clear = function() cleared = true end } }
        GB.ClearCooldown(b)
        assert(cleared and not (b.gcdStart or b.cdDuration or b.cdUntil or b.cdDoneAt),
            "an emptied tile kept a cooldown")
    end },
    -- (a recipe's colour and chance of a point: 2329 turns yellow at 55,
    -- grey at 95; -1 has no grey, -2 a yellow above its grey)
    { name = "profession colours", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local PR = IF and IF.Professions
        if not (PR and PR.Color) then return end
        local trivial = IF.RecipeData.trivial
        trivial[-1], trivial[-2] = { 10, 0 }, { 320, 310 }
        local function is(want, wantChance, ...)
            local color, chance = ...
            assert(color == want and chance == wantChance,
                ("%s, %s: want %s, %s"):format(tostring(color), tostring(chance), tostring(want), tostring(wantChance)))
        end
        is("orange", 1, PR.Color(2329, 54))
        is("yellow", 1, PR.Color(2329, 55))
        is("yellow", 0.6, PR.Color(2329, 71))
        is("green", 0.5, PR.Color(2329, 75))
        is("grey", 0, PR.Color(2329, 95))
        is(nil, nil, PR.Color(-1, 50))
        is("orange", 1, PR.Color(-2, 309))
        is("grey", 0, PR.Color(-2, 310))
        is("orange", 1, PR.Color(2329, 75, 0))
        is("yellow", 0.5, PR.Color(2329, 75, 1))
        is("green", nil, PR.Color(2329, 100, 2))
        is("grey", 0, PR.Color(-1, 50, 3))
        -- (orange 54: 1; yellow 55..94: 40/40 .. 40/1; grey: 0)
        local want = 1
        for s = 55, 94 do want = want + 1 / ((95 - s) / 40) end
        assert(PR.CraftsToGrey(2329, 54) == math.ceil(want), "crafts to grey from 54")
        assert(PR.CraftsToGrey(2329, 95) == 0 and PR.CraftsToGrey(-1, 5) == nil, "crafts to grey: grey, unknown")
        trivial[-1], trivial[-2] = nil, nil
    end },
    -- (an item's trend: its last day against the median of the days before)
    { name = "auction trend", fn = function()
        local A = rawget(_G, "ImprovedForever") and ImprovedForever.Auction
        if not A then return end
        local history = A.History
        local function days(...)
            local list = {}
            for i, m in ipairs({ ... }) do list[i] = { day = i, market = m } end
            A.History = function() return list end
        end
        days(100, 100, 100, 112)
        assert(A.TrendText(1):find("rising +12%", 1, true), "rising")
        days(100, 90, 110, 92)
        assert(A.TrendText(1):find("falling -8%", 1, true), "falling")
        days(100, 100, 100, 104)
        assert(A.TrendText(1):find("steady +4%", 1, true), "within 5%")
        days(100, 100, 150)
        assert(A.TrendText(1) == nil, "too few days")
        A.History = history
    end },
    -- (the Destroy panel's press unbound: only the press goes, the panel stays on)
    { name = "destroy press unbound", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local DS, B = IF and IF.Destroy, IF and IF.Binds
        if not DS then return end
        local def = B.Get("destroy")
        def.set(nil)
        assert(DS.Enabled() and DS.OpenKey() == nil, "unbinding turned the panel off or kept the press")
        def.set("PADLSHOULDER+PADRSTICK")
        assert(DS.OpenKey() == "PADLSHOULDER+PADRSTICK", "a press set")
        assert(not def.accepts("PAD4") and not def.accepts("PADRSTICK") and not def.accepts("PADRTRIGGER+PAD1"),
            "a press the bags use accepted")
        def.set("PAD4")
        assert(DS.OpenKey() == "PADRTRIGGER+PADRSTICK", "a saved press the bags use kept")
        def.reset()
        assert(DS.OpenKey() == "PADRTRIGGER+PADRSTICK", "reset: the default press")
    end },
    -- (the rares by map, from the bundled data: Mother Fang in Elwynn Forest, none in an instance)
    { name = "rares by map", fn = function()
        local GD = rawget(_G, "ImprovedForever") and ImprovedForever.GameData
        if not (GD and GD.Rares) then return end
        local fang
        for _, r in ipairs(GD.Rares()[1429] or {}) do
            if r.id == 471 then fang = r end
        end
        assert(fang and fang.name == "Mother Fang" and #fang.points > 0, "Mother Fang not on Elwynn Forest's map")
        for _, list in pairs(GD.Rares()) do
            for _, r in ipairs(list) do assert(r.points[1][1] >= 0, r.name .. ": an instance's spawn on a map") end
        end
    end },
}

local args = { ... }
if args[1] == "each" then
    -- Each module alone with the core, in a fresh state each time
    local all = allFolders()
    local script = arg and arg[0] or "tools/loadcheck.lua"
    local total = 0
    for _, folder in ipairs(all) do
        if folder ~= "ImprovedForever" then
            print("== ImprovedForever + " .. folder)
            local ok = os.execute("luajit " .. script .. " ImprovedForever " .. folder)
            if ok ~= 0 and ok ~= true then total = total + 1 end
        end
    end
    print("== all")
    local ok = os.execute("luajit " .. script .. " all")
    if ok ~= 0 and ok ~= true then total = total + 1 end
    os.exit(total == 0 and 0 or 1)
end
local folders = args[1] == "all" and allFolders() or args
run(folders, CHECKS)
print(failures == 0 and "  ok" or ("  " .. failures .. " error(s)"))
os.exit(failures == 0 and 0 or 1)
