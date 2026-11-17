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
function frameMeta.Hide(self) self.__shown = false end
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
function frameMeta.GetStringWidth() return 50 end
function frameMeta.GetStringHeight() return 14 end
function frameMeta.GetText(self) return self.__text end
function frameMeta.SetText(self, t) self.__text = t end
function frameMeta.GetName(self) return self.__name end
function frameMeta.GetParent(self) return self.__parent end
function frameMeta.GetLeft() return 0 end
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
function frameMeta.CreateAnimationGroup(self) return Frame(nil, self) end
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
-- (UISpecialFrames: a game window, one of another addon's, one of ours, one of
-- Baganator's; an entry an addon put there is tainted by it)
-- (and a game frame another addon listed: its entry tainted, its global not)
UISpecialFrames = { "GameSpecialWindow", "OtherAddonWindow", "ImprovedForeverSpecialWindow", "BaganatorSpecialWindow",
    "GameFrameListedByAddon" }
local specialBy = { [2] = "OtherAddon", [3] = "ImprovedForever_Wiki", [4] = "Baganator", [5] = "OtherAddon" }
local addonGlobals = { OtherAddonWindow = true, ImprovedForeverSpecialWindow = true, BaganatorSpecialWindow = true }
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
-- (Baganator's skins: the listeners kept, for the checks to hand them windows)
local skinListeners = {}
Baganator = Frame("Baganator")
Baganator.API.Skins = { GetAllFrames = function() return {} end,
    RegisterListener = function(fn) skinListeners[#skinListeners + 1] = fn end }

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
-- (a Baganator window, hidden, skinned as Baganator hands its windows to skins)
local function BaganatorWindow(tag)
    local w = CreateFrame("Frame")
    w.BagSlots, w.Character = false, false
    function w:Show() self.__shown = true self.__scripts.OnShow(self) end
    function w:Hide() self.__shown = false self.__scripts.OnHide(self) end
    w.__shown = false
    for _, fn in ipairs(skinListeners) do fn({ regionType = "ButtonFrame", region = w, tags = { tag } }) end
    return w
end

local CHECKS = {
    { name = "config panel", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if IF and IF.Menu and IF.Menu.Open then
            IF.Menu.Open()
            for _, tab in ipairs(IF.Menu.TABS or {}) do IF.Menu.SetTab(tab.key) end
            IF.Menu.Close()
        end
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
    -- ours and one of an addon a module claims don't)
    { name = "addon windows from UISpecialFrames", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        local W = IF and IF.AddonWindows
        if not W then return end
        local function check(ok, msg) if not ok then error(msg, 0) end end
        check(W.Watched(OtherAddonWindow), "another addon's window joins")
        check(not W.Watched(GameSpecialWindow), "the game's doesn't")
        check(not W.Watched(GameFrameListedByAddon), "a game frame another addon listed doesn't")
        check(not W.Watched(ImprovedForeverSpecialWindow), "ours doesn't")
        check(not (IF.Baganator and W.Watched(BaganatorSpecialWindow)), "a claimed addon's doesn't")
        IF.db.addonWindows = false
        local off = not W.Scanned()
        IF.db.addonWindows = nil
        check(off and W.Scanned(), "the General tab's switch turns them off and on")
        -- (out of the way of the checks after: closing a window hands the pad to the nearest shown)
        for _, name in ipairs(UISpecialFrames) do _G[name].__shown = false end
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
    -- (our auction window on: the backpack Baganator opens with the auction
    -- house, before or after its event, closes again; one opened later stays;
    -- its Auto Open checkbox shows off and disabled)
    { name = "baganator auto open at the auction house", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Baganator and #skinListeners > 0) then return end
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local auction, after, getTime, kinds = rawget(IF, "Auction"), C_Timer.After, GetTime, rawget(Enum, "PlayerInteractionType")
        local now = 1000
        GetTime = function() return now end
        C_Timer.After = function(_, fn) fn() end
        rawset(Enum, "PlayerInteractionType", { Auctioneer = 21 })
        IF.Auction = { Settings = function() return { buy = true } end, Available = function() return true end }
        local w = CreateFrame("Frame")
        function w:Show() self.__shown = true self.__scripts.OnShow(self) end
        function w:Hide() self.__shown = false self.__scripts.OnHide(self) end
        w.BagSlots, w.Character = false, false
        for _, fn in ipairs(skinListeners) do fn({ regionType = "ButtonFrame", region = w, tags = { "backpack" } }) end
        local holder = CreateFrame("Frame")
        local box = CreateFrame("Frame", nil, holder)
        rawset(holder, "checkBox", box)
        holder.option = "auto_open.auction_house"
        local checked, enabled, text = true, true, "Auction House"
        function box:GetText() return text end
        function box:SetText(t) text = t end
        function box:SetEnabled(on) enabled = on end
        function box:SetChecked(on) checked = on end
        function box:GetParent() return holder end
        function holder:SetValue(v) checked = v end
        for _, fn in ipairs(skinListeners) do fn({ regionType = "CheckBox", region = box }) end
        local function open(first)
            now = now + 10
            if first then w:Show() end
            fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
            if not first then w:Show() end
        end
        open(true)
        check(not w:IsShown(), "opened before the event: closed")
        open(false)
        check(not w:IsShown(), "opened after the event: closed")
        now = now + 1
        w:Show()
        check(w:IsShown(), "opened later: stays")
        holder:SetValue(true)
        local greyed = not checked and not enabled and text:find("auction window")
        w:Hide()
        IF.Auction, C_Timer.After, GetTime = auction, after, getTime
        rawset(Enum, "PlayerInteractionType", kinds)
        check(greyed, "the checkbox off, disabled, with the reason")
    end },
    -- (the Baganator module's settings filled once, not on every read)
    { name = "baganator settings", fn = function()
        local BG = rawget(_G, "ImprovedForever") and ImprovedForever.Baganator
        if not BG then return end
        local s = BG.Settings()
        ImprovedForever.db.bagsLog = {}
        local kept = BG.Settings() == s and ImprovedForever.db.bagsLog
        ImprovedForever.db.bagsLog = nil
        if not (kept and s.switch == true) then error("Settings: not filled once", 0) end
    end },
    -- (Baganator's backpack and bank open beside an unseen game window (the
    -- game's bank, Baganator hides it): closing the backpack with B hands
    -- the pad straight to the bank, and one B then closes that)
    { name = "baganator close hands the pad on", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Baganator and #skinListeners > 0) then return end
        local F = IF.Focus
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local gamepadMode, isKeyDown = GamepadMode, IsKeyDown
        local manager = { shownFrames = {}, isUIFocused = false }
        GamepadMode = { FrameControlsManager = manager }
        local function Catcher(w)
            for _, f in ipairs(frames) do
                if f.__parent == w and f.__scripts.OnGamePadButtonDown then return f end
            end
        end
        local function B(w)
            local c = Catcher(w)
            c.__scripts.OnGamePadButtonDown(c, "PAD2")
            c.__scripts.OnGamePadButtonUp(c, "PAD2")
        end
        local backpack, bank = BaganatorWindow("backpack"), BaganatorWindow("bank")
        backpack:Show()
        bank:Show()
        check(F.Holding() == backpack, "the backpack opened first holds the pad")
        local game = CreateFrame("Frame")
        manager.shownFrames, manager.focusedFrame, manager.isUIFocused = { game }, game, true
        -- (B still down as the backpack hides on its release)
        IsKeyDown = function(key) return key == "PAD2" end
        B(backpack)
        IsKeyDown = isKeyDown
        local c = Catcher(bank)
        c.__scripts.OnUpdate(c)
        check(not backpack:IsShown() and F.Holding() == bank, "closing the backpack hands the pad to the bank")
        B(bank)
        GamepadMode = gamepadMode
        check(not bank:IsShown(), "one B then closes the bank")
    end },
    -- (a Baganator window opened from the panel (its Addons tab): the last one opened has the
    -- pad, the panel behind it; the pad back on the panel once it closes)
    { name = "baganator over the panel", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Baganator and IF.Menu and #IF.Menu.TABS > 0 and #skinListeners > 0) then return end
        local F, M = IF.Focus, IF.Menu
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local gamepadMode = GamepadMode
        GamepadMode = { FrameControlsManager = { shownFrames = {}, isUIFocused = false } }
        M.Open()
        local bags = BaganatorWindow("backpack")
        bags:Show()
        M.OnUpdate(0)
        check(F.Holding() == bags and M.Behind(), "the bags opened over the panel have the pad, the panel behind")
        -- (L2 there, the triggers up first: back on the panel, the bags letting go)
        local isKeyDown = IsKeyDown
        IsKeyDown = function(key) return key == "PADLTRIGGER" end
        M.OnUpdate(0)
        IsKeyDown = isKeyDown
        check(not M.Behind() and F.Holding() ~= bags, "L2 on the bags gives the panel the pad, the bags let go")
        bags:Hide()
        M.OnUpdate(0)
        GamepadMode = gamepadMode
        check(M.IsOpen() and not M.Behind() and F.Holding() ~= bags, "the bags closing give the panel the pad back")
        M.Close()
    end },
    -- (the bag slots bar open above the backpack: closing the backpack with
    -- B leaves the bar shown under it, unseen; the pad must not go to it)
    { name = "baganator close skips the hidden bag slots bar", fn = function()
        local IF = rawget(_G, "ImprovedForever")
        if not (IF and IF.Baganator and #skinListeners > 0) then return end
        local F = IF.Focus
        local function check(ok, msg) if not ok then error(msg, 0) end end
        local gamepadMode = GamepadMode
        GamepadMode = { FrameControlsManager = { shownFrames = {}, isUIFocused = false } }
        local backpack = CreateFrame("Frame")
        backpack.__shown = false
        local slots = CreateFrame("Frame", nil, backpack)
        backpack.BagSlots = slots
        slots.liveBagSlots = { CreateFrame("Button", nil, slots) }
        function backpack:ToggleBagSlots() end
        function backpack:Show() self.__shown = true self.__scripts.OnShow(self) end
        function backpack:Hide() self.__shown = false self.__scripts.OnHide(self) end
        for _, fn in ipairs(skinListeners) do fn({ regionType = "ButtonFrame", region = backpack, tags = { "backpack" } }) end
        local catcher
        for _, f in ipairs(frames) do
            if f.__parent == backpack and f.__scripts.OnGamePadButtonUp then catcher = f end
        end
        backpack:Show()
        check(F.Holding() == backpack, "the backpack holds the pad")
        catcher.__scripts.OnGamePadButtonDown(catcher, "PAD2")
        catcher.__scripts.OnGamePadButtonUp(catcher, "PAD2")
        GamepadMode = gamepadMode
        check(not backpack:IsShown() and F.Holding() == nil, "closing the backpack leaves the pad to no window of ours")
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
