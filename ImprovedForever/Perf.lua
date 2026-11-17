-- /if perf [seconds]: every handler wrapped with IF.Prof or run with IF.Run is timed while it
-- runs (default 10 s); the top ten said in chat, every row into IF.db.perfLog (saved on /reload).
-- Off, a wrapper costs one check. Besides the totals: each handler's slowest single call, every
-- loaded addon's frames over 5 ms during the run (one-off hitches an average hides), each
-- Improved Forever addon's own figure, the counts of UPDATE_BINDINGS and of CVAR_UPDATE by
-- CVar, and a line per IF.Note (a focus change: what it cost, the counts since the last one).
local IF = ImprovedForever

local perf          -- (name: { ms, calls, max } while measuring; nil: off)
local spikesAtStart -- (addon name: its frames over 5 ms when the run started)
local notes         -- (the run's IF.Note lines)
local since = {}    -- (count name: how many since the last IF.Note)

local function Record(name, took)
    local row = perf[name]
    if not row then
        row = { ms = 0, calls = 0, max = 0 }
        perf[name] = row
    end
    row.ms = row.ms + took
    row.calls = row.calls + 1
    if took > row.max then row.max = took end
end

-- fn(...) run, timed under name while measuring; its time in ms, nil when off
function IF.Run(name, fn, ...)
    if not perf then
        fn(...)
        return nil
    end
    local start = debugprofilestop()
    fn(...)
    local took = debugprofilestop() - start
    Record(name, took)
    return took
end

-- fn wrapped: timed under name while measuring
function IF.Prof(name, fn)
    return function(...) IF.Run(name, fn, ...) end
end

-- One more of name (an event), while measuring
function IF.Count(name)
    if not perf then return end
    Record(name, 0)
    since[name] = (since[name] or 0) + 1
end

-- A line for the log while measuring, with the counts since the last one
function IF.Note(text)
    if not perf then return end
    local parts = {}
    for name, n in pairs(since) do parts[#parts + 1] = ("%s %d"):format(name, n) end
    table.sort(parts)
    wipe(since)
    notes[#notes + 1] = ("%.2f %s%s"):format(GetTime() % 1000, text, #parts > 0 and (" (since last: " .. table.concat(parts, ", ") .. ")") or "")
end

-- (the events counted while measuring)
local counter = CreateFrame("Frame")
counter:SetScript("OnEvent", function(_, event, cvar)
    if event == "CVAR_UPDATE" then
        IF.Count("CVAR_UPDATE " .. (type(cvar) == "string" and cvar or "?"))
    else
        IF.Count(event)
    end
end)

-- Each loaded addon's count of one metric (nil: the game has no addon profiler)
local function AddOnCounts(metric)
    local P = C_AddOnProfiler
    if not (P and P.GetAddOnMetric and P.IsEnabled and P.IsEnabled()) then return nil end
    local counts = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        if C_AddOns.IsAddOnLoaded(i) then
            local name = C_AddOns.GetAddOnInfo(i)
            counts[name] = P.GetAddOnMetric(name, metric)
        end
    end
    return counts
end

local function Report(seconds)
    counter:UnregisterAllEvents()
    local rows = {}
    for name, row in pairs(perf) do
        rows[#rows + 1] = { name = name, ms = row.ms / seconds, calls = row.calls / seconds, max = row.max }
    end
    perf = nil
    table.sort(rows, function(a, b) return a.ms > b.ms end)
    local log = { date("%H:%M:%S") .. (" perf run, %d s, %d handlers"):format(seconds, #rows) }
    IF.db.perfLog = log
    IF.Print(("perf: %d s, top %d by ms/s:"):format(seconds, math.min(10, #rows)))
    for i, row in ipairs(rows) do
        local line = ("%s: %.3f ms/s, %.1f calls/s, slowest call %.2f ms"):format(row.name, row.ms, row.calls, row.max)
        log[#log + 1] = line
        if i <= 10 then IF.Print("  " .. line) end
    end
    table.sort(rows, function(a, b) return a.max > b.max end)
    IF.Print("  slowest single calls:")
    log[#log + 1] = "slowest single calls:"
    for i = 1, math.min(5, #rows) do
        local line = ("%s: %.2f ms"):format(rows[i].name, rows[i].max)
        log[#log + 1] = "  " .. line
        IF.Print("    " .. line)
    end
    -- (every addon's frames over 5 ms during the run: is a hitch ours at all)
    local spikesNow = spikesAtStart and AddOnCounts(Enum.AddOnProfilerMetric.CountTimeOver5Ms)
    if spikesNow then
        local spiked = {}
        for name, count in pairs(spikesNow) do
            local added = count - (spikesAtStart[name] or 0)
            if added > 0 then spiked[#spiked + 1] = { name = name, added = added } end
        end
        table.sort(spiked, function(a, b) return a.added > b.added end)
        local parts = {}
        for i, s in ipairs(spiked) do parts[i] = ("%s %d"):format(s.name, s.added) end
        local line = "addons with frames over 5 ms: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
        log[#log + 1] = line
        IF.Print("  " .. line)
    end
    spikesAtStart = nil
    -- (the game's own figure for each of our addons, all its code: per frame over the last 60)
    local P, metric = C_AddOnProfiler, Enum.AddOnProfilerMetric
    if P and P.GetAddOnMetric and metric and metric.RecentAverageTime then
        for i = 1, C_AddOns.GetNumAddOns() do
            local addon = C_AddOns.GetAddOnInfo(i)
            if C_AddOns.IsAddOnLoaded(i) and addon:find("^ImprovedForever") then
                local line = ("addon %s: %.3f ms/frame recent, %.3f ms peak"):format(addon,
                    P.GetAddOnMetric(addon, metric.RecentAverageTime), P.GetAddOnMetric(addon, metric.PeakTime))
                log[#log + 1] = line
                IF.Print("  " .. line)
            end
        end
    end
    log[#log + 1] = "timeline:"
    for _, line in ipairs(notes) do log[#log + 1] = "  " .. line end
    notes = nil
    IF.Print("  /reload to save every row (ImprovedForeverDB.perfLog)")
end

IF.AddCommand("perf", function(args)
    if perf then return IF.Print("perf: already measuring.") end
    local seconds = math.max(1, math.floor(tonumber(args[1]) or 10))
    perf, notes = {}, {}
    wipe(since)
    counter:RegisterEvent("UPDATE_BINDINGS")
    counter:RegisterEvent("CVAR_UPDATE")
    spikesAtStart = Enum.AddOnProfilerMetric and AddOnCounts(Enum.AddOnProfilerMetric.CountTimeOver5Ms)
    IF.Print(("perf: measuring %d s."):format(seconds))
    C_Timer.After(seconds, function() Report(seconds) end)
end, "[seconds]: time Improved Forever's handlers (default 10 s), the top ten in chat, all in the saved log")
