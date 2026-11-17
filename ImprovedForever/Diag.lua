-- /if report: a text to paste in a comment or an issue when the game blocks an action
-- (ADDON_ACTION_FORBIDDEN / BLOCKED, the "an addon tried to use a protected action" popup).
-- Every such event is logged, whichever addon the game names, with where it happened
-- (instance, zone, combat), in IF.db.taintLog (the newest MAX_LOG kept, a repeat counted).
-- The report adds the versions of our addons and the other addons loaded (a clash with another
-- addon shows there). It can't read the game's taint.log: only the game writes it.
local _, IF = ...

local MAX_LOG = 40
local MAX_ADDONS = 40

local log   -- IF.db.taintLog, set at login
local told  -- the chat hint, once per session

local function Str(value)
    local ok, text = pcall(tostring, value)
    return ok and text or "<hidden>"
end

local function Where()
    local parts = {}
    local ok, inInstance, kind = pcall(IsInInstance)
    parts[#parts + 1] = (ok and inInstance) and Str(kind) or "world"
    local okZone, zone = pcall(GetRealZoneText)
    if okZone and zone and zone ~= "" then parts[#parts + 1] = Str(zone) end
    if InCombatLockdown and InCombatLockdown() then parts[#parts + 1] = "combat" end
    return table.concat(parts, ", ")
end

local function Record(event, addon, func)
    if not log then return end
    local line = (event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked")
        .. " " .. Str(func) .. " (addon: " .. Str(addon) .. ") [" .. Where() .. "]"
    local last = log[#log]
    if last and last.line == line then
        last.count = last.count + 1
        return
    end
    log[#log + 1] = { line = line, at = date("%Y-%m-%d %H:%M:%S"), count = 1 }
    while #log > MAX_LOG do table.remove(log, 1) end
    if not told then
        told = true
        IF.Print("The game blocked an action. Type /if report and paste the text where you reported it, to help fix it.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, addon, func)
    pcall(Record, event, addon, func)
end)

IF.OnLogin(function()
    IF.db.taintLog = IF.db.taintLog or {}
    log = IF.db.taintLog
end)

---------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------
function IF.BuildReport()
    local A = _G.C_AddOns
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    local version, build = GetBuildInfo()
    Add("Improved Forever report " .. date("%Y-%m-%d %H:%M"))
    Add("Client: " .. Str(version) .. " (" .. Str(build) .. ")")
    local mine, others = {}, {}
    if A and A.GetNumAddOns then
        for index = 1, A.GetNumAddOns() do
            local name = A.GetAddOnInfo(index)
            if name and A.IsAddOnLoaded(name) then
                local v = A.GetAddOnMetadata and A.GetAddOnMetadata(name, "Version") or "?"
                if name:find("^ImprovedForever") then
                    mine[#mine + 1] = name:gsub("^ImprovedForever_?", "") .. " " .. Str(v)
                elseif #others < MAX_ADDONS then
                    others[#others + 1] = name
                end
            end
        end
    end
    for i, text in ipairs(mine) do if text:sub(1, 1) == " " then mine[i] = "Core" .. text end end
    Add("Ours: " .. table.concat(mine, ", "))
    Add("Others: " .. (#others > 0 and table.concat(others, ", ") or "none"))
    Add("Buttons: " .. Str(IF.PadStyle and IF.PadStyle()))
    Add("")
    if log and #log > 0 then
        Add("Blocked actions (" .. #log .. "):")
        for _, entry in ipairs(log) do
            Add(entry.at .. " x" .. entry.count .. " " .. entry.line)
        end
    else
        Add("No blocked action logged.")
    end
    return table.concat(lines, "\n")
end

local window
local function Show()
    local K, UI = IF.ConfigKit, IF.UI
    if not window then
        window = UI.Window("ImprovedForeverReport", 560, 380, true)
        window:SetTitle("Improved Forever report")
        local hint = K.Text(window, 12, K.C.title)
        hint:SetPoint("TOP", 0, -34)
        hint:SetText("Click the text, Ctrl+A, Ctrl+C, then paste it in your comment.")
        local scroll = CreateFrame("ScrollFrame", "ImprovedForeverReportScroll", window, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -56)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject("ChatFontNormal")
        box:SetWidth(500)
        box:SetMaxLetters(0)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() window:Hide() end)
        scroll:SetScrollChild(box)
        window.box = box
        -- (Esc closes it, with the mouse; never by UISpecialFrames, which taints the game's close)
        IF.Focus.EscapeClose(window)
    end
    window.box:SetText(IF.BuildReport())
    window:Show()
    window.box:SetFocus()
    window.box:HighlightText()
end

IF.AddCommand("report", Show, ": text to paste when the game blocks an action")
IF.AddCommand("clearreport", function()
    if log then wipe(log) end
    IF.Print("Report log cleared.")
end, ": clear what /if report lists")
