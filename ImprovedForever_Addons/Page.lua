-- The Addons tab of the panel (Menu.lua): every addon's commands, settings
-- pages and launchers (Commands.lua), a heading per addon. The D-pad and
-- the left stick move through them, L1 / R1 to the previous / next addon.
-- A runs a command as typed, without arguments: a secure macro button of
-- ours takes A while one is picked (D-10). On a settings page or launcher A
-- opens it.
local IF = ImprovedForever

local K, UI, menu = IF.ConfigKit, IF.UI, IF.Menu
local AD = IF.Addons

local P = {}
local ROWS = 12
local KIND = { slash = "Command", settings = "Settings", compartment = "Addon menu", ldb = "Launcher" }

-- (acting on the release, as the navigator's: an override binding's click
-- reaches it with the game's key-down setting's side)
local run = CreateFrame("Button", "ImprovedForeverAddonsRun", UIParent, "SecureActionButtonTemplate")
run:SetAttribute("type", "macro")
run:RegisterForClicks("AnyDown", "AnyUp")
run:SetAttribute("useOnKeyDown", false)

local function Label(e)
    local text = e.kind == "slash" and table.concat(e.aliases or { e.text }, ", ") or e.text
    return text .. "  |cff9d9a8c" .. KIND[e.kind] .. "|r"
end

local function Verb(e)
    if not e or (e.kind == "settings" and not e.openable) then return nil end
    return e.kind == "slash" and "Run" or "Open"
end

function P:Build(body)
    self.list = UI.SideList(body, 620, ROWS, function(index)
        self:Select(index)
        self:Choose()
        menu.Render()
    end)
    self.list:SetPoint("TOP", body, "TOP", 0, 0)
    self.list:SetHeight(38 + ROWS * 30)
    self.list:EnableMouseWheel(true)
    self.list:SetScript("OnMouseWheel", function(_, delta)
        self:Step(delta > 0 and -1 or 1)
        menu.Render()
    end)
    self.list:Hide()
end

function P:Entry()
    local line = self.index and self.lines[self.index]
    return line and line.entry
end

function P:Select(index)
    self.index = index
    local e = self:Entry()
    run:SetAttribute("macrotext", e and e.kind == "slash" and e.text or nil)
    menu.Rebind("PAD1")
end

function P:PadButton(key)
    local e = self:Entry()
    if key == "PAD1" and e and e.kind == "slash" then return run:GetName() end
end

function P:Show()
    local groups, lines = AD.Commands(), {}
    for _, group in ipairs(groups) do
        lines[#lines + 1] = { header = group.title }
        for _, e in ipairs(group.entries) do lines[#lines + 1] = { label = Label(e), entry = e } end
    end
    self.lines, self.count = lines, #groups
    self:Select(lines[2] and 2 or nil)
    self.list:Show()
end

function P:Hide()
    self.list:Hide()
end

-- One entry up (-1) or down (1), over the headings
function P:Step(dir)
    if not self.index then return end
    local i = self.index + dir
    while self.lines[i] and self.lines[i].header do i = i + dir end
    if self.lines[i] then self:Select(i) end
end

-- The previous (-1) / next (1) addon's first entry
function P:Jump(dir)
    local lines, i = self.lines, self.index
    if not i then return end
    repeat i = i - 1 until lines[i].header
    repeat i = i + dir until not lines[i] or lines[i].header
    if lines[i] then self:Select(i + 1) end
end

function P:StickStep(dir)
    self:Step(dir)
end

-- A without the secure button (the mouse, the legend clicked)
function P:Choose()
    local e = self:Entry()
    if not Verb(e) then return end
    if e.kind == "slash" then
        local fn = SlashCmdList[e.key]
        if fn then fn("") end
    elseif e.kind == "settings" then
        -- (one of the exceptions in docs/taint.md: the game opens its panel in its own event handler)
        C_SettingsUtil.OpenSettingsPanel(e.id)
    elseif e.kind == "compartment" then
        local fn = _G[e.text]
        if type(fn) == "function" then fn(e.addon, "LeftButton") end
    else
        local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
        local object = ldb and ldb:GetDataObjectByName(e.text)
        if object and object.OnClick then object.OnClick(self.list, "LeftButton") end
    end
end

function P:Press(name)
    if name == "UP" or name == "DOWN" then
        self:Step(name == "UP" and -1 or 1)
    elseif name == "LB" or name == "RB" then
        self:Jump(name == "LB" and -1 or 1)
    elseif name == "A" then
        self:Choose()
    else
        return false
    end
    menu.Render()
    return true
end

function P:Help()
    local H = K.H
    local hints = { H({ "DPAD_UD" }, "Move"), H({ "LB", "RB" }, "Addon") }
    local verb = Verb(self:Entry())
    if verb then hints[#hints + 1] = H({ "A" }, verb, "A") end
    hints[#hints + 1] = H({ "RS" }, "Tab")
    hints[#hints + 1] = H({ "B" }, "Close", "B")
    return hints
end

function P:Render()
    local title = self.count == 0 and "No addon commands found" or (self.count .. " addons")
    self.list:Render(title, self.lines, self.index or 0, not menu.Behind())
end

menu.AddTab({ key = "addons", label = "Addons", module = "addons", order = 80, page = P })
