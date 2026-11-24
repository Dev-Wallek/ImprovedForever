-- Peek map: while a hotkey is held, the game's own Map & Quest Log shows
-- with everything but its map faded out (its frame, the nav bar, the quest
-- list, the gamepad prompts): the map alone, see-through, placed and sized
-- as the Map tab says (PeekMapEditor.lua, IF.db.peekMap); letting go
-- closes it. The native map, so its quests, markers and arrow are all
-- there.
-- Opening a game window from addon code taints it on Forever (Touchpad.lua),
-- so the peek map is an action (Actions.lua, "peekmap") put on presses in
-- the Bindings tab. On a press an override binding takes, and on a key, it
-- is bound to a secure button of ours (press: opens, release: closes, or
-- tapped as the setting says). A touchpad corner holds it the same way
-- (Touchpad.lua). Anywhere else (a crossbar slot, a wheel, a press twice)
-- its macro clicks our toggle: a press opens it, the next closes it.
-- The map is shown by our secure code, never as a window: Forever's frame
-- manager only takes windows opened through ShowUIPanel, so the map never
-- has the gamepad and every press does what it does without it. Not in
-- combat (a handle to the map is refused there, and its button would open
-- it as a window).
local IF = ImprovedForever

local K = IF.ConfigKit

local PeekMap = {}
IF.PeekMap = PeekMap

local MARGIN = 40      -- from the screen's edge, placed at one

local DEFAULTS = {
    alpha = 0.75,        -- how see-through the map is
    size = 0.6,          -- its height, of the screen's
    anchor = "CENTER",   -- where on the screen: CENTER, TOP, TOPLEFT...
    x = 0,               -- moved from there: right (+) / left (-), of the screen's width
    y = 0,               -- up (+) / down (-), of its height
    labels = true,       -- each quest's name beside its node
    legend = true,       -- the buttons' prompts, below the map
    tap = false,         -- a press opens it, the next closes it (not held)
}

function PeekMap.Settings()
    local db = IF.db
    db.peekMap = db.peekMap or {}
    local settings = db.peekMap
    for k, v in pairs(DEFAULTS) do
        if settings[k] == nil then settings[k] = v end
    end
    -- (offsets were screen px once)
    for _, k in ipairs({ "x", "y" }) do
        if math.abs(settings[k]) > 0.5 then settings[k] = 0 end
    end
    settings.pins = nil
    return settings
end

---------------------------------------------------------------------------
-- The look: while the map is open for a peek, every part of the window but
-- its map (ScrollContainer) faded out, the map moved and scaled onto a
-- frame of ours placed by the settings. Put back as it closes.
-- Only looks change: no size of the map's (that would refit its canvas
-- from our code, and the values it then holds would taint the map's own
-- secure work, closing it included). The map keeps its size; one anchor
-- (its centre) and a scale put it in place.
---------------------------------------------------------------------------
local place = K.NewFrame("Frame", "ImprovedForeverPeekMapPlace", UIParent)
place:SetSize(1, 1)
place:EnableMouse(false)

-- /if peek: each line printed and kept in IF.db.peekLog (a fresh log per
-- run), read from the saved variables after a /reload
function PeekMap.Say(text)
    if not PeekMap.debug then return end
    IF.Print(text)
    local log = IF.db and IF.db.peekLog
    if log then log[#log + 1] = ("%.2f %s"):format(GetTime() % 1000, text) end
end

local peeking = false      -- the open map is a peek
local legend               -- the button prompts, on the map
local saved                -- what the look changed: { alphas, points, scale, alpha }

-- The map's size and place on the screen, for the player's map
local function Place()
    local settings = PeekMap.Settings()
    local mapID = MapUtil and MapUtil.GetDisplayableMapForPlayer and MapUtil.GetDisplayableMapForPlayer()
        or C_Map.GetBestMapForUnit("player")
    local layer = mapID and (C_Map.GetMapArtLayers(mapID) or {})[1]
    local aspect = layer and layer.layerWidth / layer.layerHeight or 1.5
    local h = UIParent:GetHeight() * settings.size
    place:SetSize(h * aspect, h)
    local a = settings.anchor
    local x = a:find("LEFT") and MARGIN or a:find("RIGHT") and -MARGIN or 0
    local y = a:find("TOP") and -MARGIN or a:find("BOTTOM") and MARGIN or 0
    place:ClearAllPoints()
    place:SetPoint(a, UIParent, a, x + settings.x * UIParent:GetWidth(), y + settings.y * UIParent:GetHeight())
end

local function Fade(region)
    saved.alphas[region] = region:GetAlpha()
    region:SetAlpha(0)
end

-- The map scaled to the place's height, centred on it (offsets in the map's
-- own scaled units, from the screen's bottom left)
local function Layout()
    local scroll = WorldMapFrame.ScrollContainer
    local w, h = scroll:GetSize()
    Place()
    local px, py = place:GetCenter()
    local placeScale = place:GetEffectiveScale()
    local parentScale = scroll:GetEffectiveScale() / scroll:GetScale()
    scroll:SetScale((place:GetHeight() * placeScale) / (h * parentScale))
    scroll:ClearAllPoints()
    scroll:SetSize(w, h)
    local mapScale = scroll:GetEffectiveScale()
    scroll:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px * placeScale / mapScale, py * placeScale / mapScale)
    PeekMap.PlaceLegend()
end

local function Apply()
    local map = WorldMapFrame
    local scroll = map and map.ScrollContainer
    if not scroll or saved then return end
    local w, h = scroll:GetSize()
    if not (w and h and w > 0 and h > 0) then return end
    saved = { alphas = {}, points = {}, scale = scroll:GetScale(), alpha = scroll:GetAlpha() }
    for _, child in ipairs({ map:GetChildren() }) do
        if child ~= scroll then Fade(child) end
    end
    for _, region in ipairs({ map:GetRegions() }) do Fade(region) end
    for i = 1, scroll:GetNumPoints() do saved.points[i] = { scroll:GetPoint(i) } end
    Layout()
    scroll:SetAlpha(PeekMap.Settings().alpha)
end

-- Spoken's place story panel and its side tab: under the gamepad UI they are
-- UIParent's, shown with the map, so they stay over a peek. Faded by an
-- animation of ours (their own alpha is Spoken's to set).
-- (named SpokenZones... in older Spoken, SpokenPlaces... now)
local SPOKEN_PANELS = { "SpokenPlacesPanel", "SpokenPlacesPanelToggle", "SpokenZonesPanel", "SpokenZonesPanelToggle" }

local function FadeSpoken(hide)
    for _, name in ipairs(SPOKEN_PANELS) do
        local frame = _G[name]
        if frame then IF.Focus.Fade(frame, hide) end
    end
end

local function Restore()
    local scroll = WorldMapFrame and WorldMapFrame.ScrollContainer
    FadeSpoken(false)
    -- (bound also when the look never applied: the map had no size yet)
    PeekMap.Keys(false)
    if not saved then return end
    IF.Focus.DimNative(place, false)
    for region, alpha in pairs(saved.alphas) do region:SetAlpha(alpha) end
    if scroll then
        scroll:SetScale(saved.scale)
        scroll:ClearAllPoints()
        for _, point in ipairs(saved.points) do scroll:SetPoint(unpack(point)) end
        scroll:SetAlpha(saved.alpha)
    end
    saved = nil
end

-- (parts of the window it shows later, a footer, faded too while a peek;
-- and the game's cursor, should it show over the map, Focus.lua)
local refade = CreateFrame("Frame")
refade:SetScript("OnUpdate", function()
    if not (peeking and saved and WorldMapFrame) then return end
    FadeSpoken(true)
    for _, child in ipairs({ WorldMapFrame:GetChildren() }) do
        if child ~= WorldMapFrame.ScrollContainer and saved.alphas[child] == nil then Fade(child) end
    end
    local pointer = _G.SmartNavigation and SmartNavigation.Pointer
    if pointer and pointer:GetAlpha() > 0 then IF.Focus.DimNative(place, true) end
end)

IF.OnLogin(function()
    local map = WorldMapFrame
    if not map then return end
    map:HookScript("OnShow", function()
        PeekMap.Say("peek: map OnShow, peeking: " .. tostring(peeking))
    end)
    map:HookScript("OnHide", function()
        PeekMap.Say("peek: map OnHide, peeking: " .. tostring(peeking))
        peeking = false
        Restore()
    end)
end)

---------------------------------------------------------------------------
-- While peeking: L1 / R1 zoom the map out / in (sub-zone <-> zone <-> continent
-- <-> world), L2 /
-- R2 move the focus (the super-tracked quest) to the previous / next
-- tracked quest. Only while the peek is held (a key, a touchpad corner) and
-- the game has the gamepad: priority override bindings on a button of
-- ours, out of combat, bound or let go again as the pad moves.
---------------------------------------------------------------------------

local MODIFIERS = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "CTRL-ALT-", "CTRL-ALT-SHIFT-" }
local KEYS = { PADLTRIGGER = "prev", PADRTRIGGER = "next", PADLSHOULDER = "out", PADRSHOULDER = "in" }

-- (on a frame above the map's strata, else the map's window covers them)
local labelFrame = CreateFrame("Frame", nil, UIParent)
labelFrame:SetFrameStrata("FULLSCREEN_DIALOG")
labelFrame:SetAllPoints(UIParent)
labelFrame:EnableMouse(false)

local function QuestName(id)
    local name = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if name then return name end
    local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
    local info = index and C_QuestLog.GetInfo and C_QuestLog.GetInfo(index)
    return info and info.title or (C_QuestLog.GetQuestInfo and C_QuestLog.GetQuestInfo(id))
end

-- Distance (squared) from the player to a quest's objective; unknown is
-- last in line
local function QuestDistance(id)
    local d = C_QuestLog.GetDistanceSqToQuest and C_QuestLog.GetDistanceSqToQuest(id)
    return type(d) == "number" and d or math.huge
end

-- The next quest to focus, step -1 / +1 (round the list): the quests with a
-- node on the map, nearest to farthest (UpdateLabels keeps the list), else
-- the tracked ones, the same way
local function MoveFocus(step)
    local ids = {}
    for _, id in ipairs(PeekMap.cycle or {}) do ids[#ids + 1] = id end
    if #ids == 0 then
        for i = 1, C_QuestLog.GetNumQuestWatches() do ids[#ids + 1] = C_QuestLog.GetQuestIDForQuestWatchIndex(i) end
        table.sort(ids, function(a, b)
            local da, db = QuestDistance(a), QuestDistance(b)
            if da ~= db then return da < db end
            return a < b
        end)
    end
    local n = #ids
    if n == 0 then return end
    local current = C_SuperTrack.GetSuperTrackedQuestID()
    local index = 0
    for i = 1, n do
        if ids[i] == current then index = i end
    end
    local target = index == 0 and (step > 0 and 1 or n) or ((index - 1 + step) % n + 1)
    C_SuperTrack.SetSuperTrackedQuestID(ids[target])
end

-- The map's own level, out (parent map) / in (the child map the player is
-- in, else the one we came out of). Native SetMapID, as its nav bar does.
local cameFrom = {}   -- map left going out -> the map to go back in to

local function ZoomMap(out)
    local map = WorldMapFrame
    if not (map and map.GetMapID and map.SetMapID) then return end
    local id = map:GetMapID()
    if not id then return end
    local target
    if out then
        local info = C_Map.GetMapInfo(id)
        local parent = info and info.parentMapID
        if parent and parent > 0 then
            cameFrom[parent] = id
            target = parent
        end
    else
        local back = cameFrom[id]
        if back then
            target = back
        else
            for _, child in ipairs(C_Map.GetMapChildrenInfo(id) or {}) do
                local pos = C_Map.GetPlayerMapPosition(child.mapID, "player")
                if pos and pos.GetXY and pos:GetXY() then
                    target = child.mapID
                    break
                end
            end
        end
    end
    if target then map:SetMapID(target) end
end

local catch = CreateFrame("Button", "ImprovedForeverPeekMapCatch", UIParent)
catch:RegisterForClicks("AnyDown")
catch:SetScript("OnClick", function(_, key)
    local action = KEYS[key]
    if not (peeking and action) then return end
    if action == "out" then ZoomMap(true)
    elseif action == "in" then ZoomMap(false)
    elseif action == "prev" then MoveFocus(-1)
    else MoveFocus(1) end
end)

local keysOn = false
local held = false   -- the open peek is held: its keys wanted

function PeekMap.Keys(on)
    if IF.InCombat() then return end
    ClearOverrideBindings(catch)
    keysOn = on and IF.Binds.InGame() and true or false
    if PeekMap.ShowLegend then PeekMap.ShowLegend() end
    if not keysOn then return end
    for key in pairs(KEYS) do
        for _, modifier in ipairs(MODIFIERS) do
            SetOverrideBindingClick(catch, true, modifier .. key, catch:GetName(), key)
        end
    end
end

-- Each quest's name beside its node on the map, none over another (or over
-- a node). The nodes are the map's quest pins, read (never changed) for
-- where they are drawn; the labels are ours, on the screen. The focused
-- quest's first, so it keeps its side.
local labels = {}
local GAP, LABEL_PAD = 4, 2
local MAX_NODE = 48   -- a pin wider than this (screen units) isn't a node

-- The map's own lettering: the game's font outlined, as its place names are,
-- sized to the map (a smaller peek, smaller names)
local function FontSize()
    return math.max(9, math.min(14, math.floor(place:GetHeight() / 48 + 0.5)))
end

local function Label(i)
    local fs = labels[i]
    if not fs then
        fs = labelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetShadowColor(0, 0, 0, 0.8)
        fs:SetShadowOffset(1, -1)
        labels[i] = fs
    end
    return fs
end

local function Style(fs, focused)
    local font = GameFontNormalSmall:GetFont()
    fs:SetFont(font, FontSize() + (focused and 1 or 0), "OUTLINE")
    if focused then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(0.95, 0.9, 0.78) end
    fs:SetAlpha(focused and 1 or 0.92)
end

local function Overlaps(a, b)
    return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t
end

local function Free(rect, taken, bounds)
    if rect.l < bounds.l or rect.r > bounds.r or rect.b < bounds.b or rect.t > bounds.t then return false end
    for _, other in ipairs(taken) do
        if Overlaps(rect, other) then return false end
    end
    return true
end

-- The map's pins: its own list of them, else the frames on its canvas
local function Pins(map)
    local list = {}
    if map.EnumerateAllPins then
        for pin in map:EnumerateAllPins() do list[#list + 1] = pin end
        return list
    end
    local canvas = map.GetCanvas and map:GetCanvas() or (map.ScrollContainer and map.ScrollContainer.Child)
    for _, child in ipairs(canvas and { canvas:GetChildren() } or {}) do
        list[#list + 1] = child
    end
    return list
end

local function UpdateLabels()
    local map = WorldMapFrame
    local used = 0
    if peeking and saved and map and PeekMap.Settings().labels then
        local ui = UIParent:GetEffectiveScale()
        local bounds = { l = place:GetLeft(), r = place:GetRight(), b = place:GetBottom(), t = place:GetTop() }
        local focused = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
        -- one node per quest: { id, x, y, radius } in the screen's units
        local nodes, seen = {}, {}
        local total, withID = 0, 0
        for _, pin in ipairs(Pins(map)) do
            total = total + 1
            local id = pin.questID or (pin.GetQuestID and pin:GetQuestID())
            if id then withID = withID + 1 end
            if id and id ~= 0 and not seen[id] and pin:IsVisible() then
                local x, y = pin:GetCenter()
                if x and bounds.l then
                    local k = pin:GetEffectiveScale() / ui
                    x, y = x * k, y * k
                    -- (not a quest's area highlight: a shape as big as the map, not a node)
                    local width = pin:GetWidth() * k
                    if width <= MAX_NODE and x >= bounds.l and x <= bounds.r and y >= bounds.b and y <= bounds.t then
                        seen[id] = true
                        nodes[#nodes + 1] = { id = id, x = x, y = y, r = math.max(6, width / 2) }
                    end
                end
            end
        end
        if PeekMap.debug and GetTime() - (PeekMap.lastLabelSay or 0) > 2 then
            PeekMap.lastLabelSay = GetTime()
            local canvas = map.GetCanvas and map:GetCanvas()
            PeekMap.Say(("peek: map has EnumerateAllPins %s, GetCanvas %s, Child %s"):format(
                tostring(map.EnumerateAllPins ~= nil), tostring(canvas ~= nil),
                tostring(map.ScrollContainer and map.ScrollContainer.Child ~= nil)))
            PeekMap.Say(("peek: labels: %d pins, %d with a quest, %d nodes on the map, bounds %s"):format(total,
                withID, #nodes, tostring(bounds.l)))
        end
        -- (the focus' order: a loop round the nodes, clockwise on the
        -- screen (top, right, bottom, left), starting at the quest nearest to
        -- the player, so R2 walks the loop and L2 walks it back)
        local byPlace = {}
        for i, n in ipairs(nodes) do byPlace[i] = n end
        if #byPlace > 1 then
            local cx, cy = 0, 0
            for _, n in ipairs(byPlace) do cx, cy = cx + n.x, cy + n.y end
            cx, cy = cx / #byPlace, cy / #byPlace
            for _, n in ipairs(byPlace) do
                n.angle = math.atan2(n.y - cy, n.x - cx) % (2 * math.pi)
            end
            table.sort(byPlace, function(a, b)
                if a.angle ~= b.angle then return a.angle > b.angle end
                return a.id < b.id
            end)
            local first, best = 1, math.huge
            for i, n in ipairs(byPlace) do
                local d = QuestDistance(n.id)
                if d < best then first, best = i, d end
            end
            local rotated = {}
            for i = 0, #byPlace - 1 do rotated[i + 1] = byPlace[(first - 1 + i) % #byPlace + 1] end
            byPlace = rotated
        end
        PeekMap.cycle = {}
        for i, n in ipairs(byPlace) do PeekMap.cycle[i] = n.id end
        table.sort(nodes, function(a, b)
            if (a.id == focused) ~= (b.id == focused) then return a.id == focused end
            return a.id < b.id
        end)
        -- every node is taken space first, so no label sits on one
        local taken = {}
        for _, n in ipairs(nodes) do
            taken[#taken + 1] = { l = n.x - n.r, r = n.x + n.r, b = n.y - n.r, t = n.y + n.r }
        end
        PeekMap.unnamed = 0
        local dump = PeekMap.debug and GetTime() - (PeekMap.lastDump or 0) > 4
        if dump then
            PeekMap.lastDump = GetTime()
            PeekMap.Say(("peek: bounds l%.0f r%.0f b%.0f t%.0f, ui scale %.3f"):format(bounds.l, bounds.r, bounds.b,
                bounds.t, ui))
            for _, n in ipairs(nodes) do
                PeekMap.Say(("peek: node %s %s x%.0f y%.0f r%.1f"):format(tostring(n.id), tostring(QuestName(n.id)), n.x,
                    n.y, n.r))
            end
        end
        for _, n in ipairs(nodes) do
            local name = QuestName(n.id)
            if not name then PeekMap.unnamed = PeekMap.unnamed + 1 end
            if name then
                local fs = Label(used + 1)
                Style(fs, n.id == focused)
                fs:SetText(name)
                local w, h = fs:GetStringWidth() + LABEL_PAD * 2, fs:GetStringHeight() + LABEL_PAD * 2
                local d = n.r + GAP
                -- right, left, above, below (then the corners)
                local tries = {
                    { n.x + d, n.y - h / 2 }, { n.x - d - w, n.y - h / 2 },
                    { n.x - w / 2, n.y + d }, { n.x - w / 2, n.y - d - h },
                    { n.x + d, n.y + d / 2 }, { n.x + d, n.y - d / 2 - h },
                    { n.x - d - w, n.y + d / 2 }, { n.x - d - w, n.y - d / 2 - h },
                }
                if dump then PeekMap.Say(("peek: label %s size %.0fx%.0f"):format(tostring(n.id), w, h)) end
                for _, t in ipairs(tries) do
                    local rect = { l = t[1], b = t[2], r = t[1] + w, t = t[2] + h }
                    if Free(rect, taken, bounds) then
                        used = used + 1
                        fs:ClearAllPoints()
                        fs:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.l + LABEL_PAD, rect.b + LABEL_PAD)
                        fs:Show()
                        taken[#taken + 1] = rect
                        break
                    end
                end
            end
        end
    end
    if PeekMap.debug and peeking and GetTime() - (PeekMap.lastUsedSay or 0) > 2 then
        PeekMap.lastUsedSay = GetTime()
        PeekMap.Say(("peek: labels placed %d, unnamed %d, keys on %s, in game %s, pad %s, legend shown %s"):format(
            used, PeekMap.unnamed or 0, tostring(keysOn), tostring(IF.Binds.InGame()), tostring(IF.Input.Pad()),
            tostring(legend:IsShown())))
    end
    for i = used + 1, #labels do labels[i]:Hide() end
end

-- The buttons, as a legend on the map's bottom (with the pad)
legend = IF.InputLegend(labelFrame)
local LEGEND = {
    { { "PADLTRIGGER", "PADRTRIGGER" }, { "PADLTRIGGER", "PADRTRIGGER" }, "Change quest" },
    { { "PADLSHOULDER", "PADRSHOULDER" }, { "PADLSHOULDER", "PADRSHOULDER" }, "Zoom map out / in" },
}
function PeekMap.ShowLegend()
    legend:Set(peeking and keysOn and PeekMap.Settings().legend and LEGEND or nil)
end

-- The pad moved between a window and the world (Binds.lua): the keys of a
-- held peek bound or let go to match
function PeekMap.Refocus()
    if peeking then PeekMap.Keys(held) end
end
IF.Input.OnChange(function() PeekMap.ShowLegend() end)

-- Below the map; inside its bottom when there's no room under it
function PeekMap.PlaceLegend()
    legend:ClearAllPoints()
    local bottom = place:GetBottom()
    if bottom and bottom < 60 then
        legend:SetPoint("BOTTOM", place, "BOTTOM", 0, 8)
    else
        legend:SetPoint("TOP", place, "BOTTOM", 0, -8)
    end
end

local sinceLabels = 0
labelFrame:SetScript("OnUpdate", function(_, elapsed)
    sinceLabels = sinceLabels + elapsed
    if sinceLabels < 0.1 then return end
    sinceLabels = 0
    UpdateLabels()
end)

local refusedSaid = false

-- After a click of ours (the hold button, the toggle, a touchpad corner;
-- button: the one clicked): a map it showed is the peek map, held (its keys
-- bound) or not. A press it refused in combat says why, once a session.
function PeekMap.Opened(withKeys, button)
    if button and button:GetAttribute("ic-peek-refused") and not refusedSaid then
        refusedSaid = true
        IF.Print("Peek map: not in combat, the game would open the map as a window that takes the controller.")
    end
    if peeking or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    peeking = true
    held = withKeys and true or false
    Apply()
    PeekMap.Keys(held)
    if PeekMap.debug then
        local scroll = WorldMapFrame.ScrollContainer
        local n = 0
        for _ in pairs(saved and saved.alphas or {}) do n = n + 1 end
        local cx, cy = scroll:GetCenter()
        PeekMap.Say(("peek: shown, look applied: %s, map %dx%d, scale %.3f, centre %s, %s, alpha %.2f,"
            .. " visible: %s, frame alpha %.2f, frame scale %.3f, %d parts faded"):format(tostring(saved ~= nil),
            scroll:GetWidth(), scroll:GetHeight(), scroll:GetEffectiveScale(), tostring(cx and math.floor(cx)),
            tostring(cy and math.floor(cy)), scroll:GetEffectiveAlpha(), tostring(scroll:IsVisible()),
            WorldMapFrame:GetEffectiveAlpha(), WorldMapFrame:GetEffectiveScale(), n))
    end
end

-- Shows the map as the peek map (its "ic-shown" is every peek's state):
-- the last step of the first peek's macro (PeekMap.SNIPPET)
local function SecureButton(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    b:SetSize(1, 1)
    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
    b:RegisterForClicks("AnyDown", "AnyUp")
    return b
end

local show = SecureButton("ImprovedForeverPeekMapShow")
SecureHandlerWrapScript(show, "OnClick", show, [[
    local map = self:GetFrameRef("map")
    if map and not map:IsShown() then
        map:Show()
        self:SetAttribute("ic-shown", true)
    end
    return false
]])

---------------------------------------------------------------------------
-- The hold button: the hotkey's press opens the map (if closed), its
-- release closes it (if open), each on its own phase whatever
-- ActionButtonUseKeyDown says
---------------------------------------------------------------------------
local hold = SecureButton("ImprovedForeverPeekMapHold")
-- (tapped: each press alone counts, toggling)
SecureHandlerWrapScript(hold, "OnClick", hold, [[
    self:SetAttribute("type", nil)
    local tap = self:GetAttribute("ic-tap")
    if tap and not down then return false end
    local result = self:RunAttribute("ic-peek", down, self:GetAttribute("ic-macro"), tap)
    if tap then self:SetAttribute("useOnKeyDown", true) end
    return result
]])

-- A peek's press (opens) or release (closes), or with toggle a press that
-- does either; for the hold button, the toggle and a touchpad corner (each
-- given the refs by PeekMap.Arm). The map is shown directly, never through
-- its button as a window. Before its first opening as a window it has no
-- place or size (its window layout gives it them): shown directly it is
-- drawn nowhere. That first press runs its button twice (opened as a
-- window, then closed: placed, the pad back with the world) and then shows
-- it directly, in the same frame. In combat a handle to the map is refused
-- (it isn't protected): a press opens nothing ("ic-peek-refused"), a
-- release closes a peek through the map's button. Returns false (nothing
-- to run) or sets the click to run a macro.
PeekMap.SNIPPET = [[
    local down, macro, toggle = ...
    local show = self:GetFrameRef("peek-show")
    local map = not PlayerInCombat() and self:GetFrameRef("map")
    -- (a peek closed another way: the next press opens it again)
    if map and not map:IsShown() then show:SetAttribute("ic-shown", nil) end
    local shown = show:GetAttribute("ic-shown")
    if toggle then down = not shown end
    if down then
        self:SetAttribute("ic-peek-refused", not map or nil)
        -- (open as the game's window: left to it)
        if shown or not map or map:IsShown() then return false end
        local scroll = self:GetFrameRef("map-scroll")
        if (scroll:GetWidth() or 0) > 0 then
            map:Show()
            show:SetAttribute("ic-shown", true)
            return false
        end
        if not macro then return false end
        macro = macro .. "\n" .. macro .. "\n/click ImprovedForeverPeekMapShow"
    else
        if not shown then return false end
        show:SetAttribute("ic-shown", nil)
        if map then
            map:Hide()
            return false
        end
    end
    self:SetAttribute("useOnKeyDown", down and true or false)
    self:SetAttribute("macrotext", macro)
    self:SetAttribute("type", "macro")
]]
hold:SetScript("PostClick", function(self, button, down)
    if PeekMap.debug then
        PeekMap.Say("peek: hotkey " .. (down and "down" or "up") .. ", ran: " .. tostring(self:GetAttribute("type"))
            .. ", map open: " .. tostring(WorldMapFrame and WorldMapFrame:IsShown()))
    end
    PeekMap.Opened(not PeekMap.Settings().tap, self)
end)

-- The action's macro anywhere else (a crossbar slot, a wheel, a press
-- twice): each click opens or closes the peek, on whichever phase /click
-- gives it
local toggle = SecureButton("ImprovedForeverPeekMapToggle")
SecureHandlerWrapScript(toggle, "OnClick", toggle, [[
    self:SetAttribute("type", nil)
    local result = self:RunAttribute("ic-peek", true, self:GetAttribute("ic-macro"), true)
    self:SetAttribute("useOnKeyDown", down and true or false)
    return result
]])
toggle:SetScript("PostClick", function(self, button, down)
    PeekMap.Say("peek: toggle " .. (down and "down" or "up") .. ", ran: " .. tostring(self:GetAttribute("type"))
        .. ", map open: " .. tostring(WorldMapFrame and WorldMapFrame:IsShown()))
    PeekMap.Opened(false, self)
end)

-- A secure button that runs PeekMap.SNIPPET as "ic-peek": the map's refs
-- and the peek's state. Out of combat.
function PeekMap.Arm(button)
    if WorldMapFrame then
        button:SetFrameRef("map", WorldMapFrame)
        button:SetFrameRef("map-scroll", WorldMapFrame.ScrollContainer)
    end
    button:SetFrameRef("peek-show", show)
    button:SetAttribute("ic-peek", PeekMap.SNIPPET)
end

---------------------------------------------------------------------------
-- The hold button's keys: each press with the peek map's action that an
-- override binding takes (Override.lua leaves them to it) and each key
-- with it. Out of combat.
---------------------------------------------------------------------------
function PeekMap.IsPeeking()
    return peeking
end

function PeekMap.HoldKeys()
    local B, O, keys = IF.Binds, IF.Override, {}
    if B.PadOverrides() then
        for spec, action in pairs(O.Settings()) do
            local _, _, double = B.Parse(spec)
            local key = action == "peekmap" and not double and B.KeyOf(spec)
            if key then keys[#keys + 1] = key end
        end
    end
    for key, action in pairs(O.KeySettings()) do
        if action == "peekmap" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

local pending = false
-- (what the hold button is bound with: unchanged, left as it is, so a
-- press held through a rebind keeps its release)
local applied

function PeekMap.Apply()
    if IF.InCombat() then
        pending = true
        return
    end
    pending = false
    -- (the core's macro for the map's button: the Controller module's
    -- touchpad not needed)
    local macro = IF.Actions and IF.Actions.Macro("map")
    if WorldMapFrame then show:SetFrameRef("map", WorldMapFrame) end
    for _, button in ipairs({ hold, toggle }) do
        PeekMap.Arm(button)
        button:SetAttribute("ic-macro", macro)
    end
    hold:SetAttribute("ic-tap", PeekMap.Settings().tap or nil)
    local keys = macro and PeekMap.HoldKeys() or {}
    local now = table.concat(keys, " ")
    if now == applied then return end
    applied = now
    ClearOverrideBindings(hold)
    -- (kept while a window has the gamepad: its release closes it)
    for _, key in ipairs(keys) do SetOverrideBindingClick(hold, true, key, hold:GetName(), "LeftButton") end
end

-- Saved presses of the peek map's own binding (IF.db.peekMapKey, its key
-- in IF.db.keyBinds) go on as its action, on the same press
local function Migrate()
    local db, B, O = IF.db, IF.Binds, IF.Override
    local spec = db.peekMapKey
    if spec and B.KeyOf(spec) and O.Settings()[spec] == nil then O.Settings()[spec] = "peekmap" end
    db.peekMapKey = nil
    local key = db.keyBinds and db.keyBinds.peekmap
    if type(key) == "string" and not B.IsClick(key) and O.KeySettings()[key] == nil then
        O.KeySettings()[key] = "peekmap"
    end
    if db.keyBinds then db.keyBinds.peekmap = nil end
end

IF.OnLogin(function()
    Migrate()
    PeekMap.Apply()
end)

-- /if peek: what the hold button is bound to and what a press does (each
-- press printed until /if peek again)
function PeekMap.Probe()
    PeekMap.debug = not PeekMap.debug
    if PeekMap.debug then IF.db.peekLog = { date("%Y-%m-%d %H:%M:%S") } end
    local bound = {}
    for _, key in ipairs(PeekMap.HoldKeys()) do bound[#bound + 1] = key .. " -> " .. tostring(GetBindingAction(key, true)) end
    PeekMap.Say("peek: hold keys " .. (#bound > 0 and table.concat(bound, ", ") or "none"))
    local slots = {}
    for _, b in ipairs(IF.Native and IF.Native.Bound() or {}) do
        if b.action == "peekmap" then slots[#slots + 1] = b.spec end
    end
    PeekMap.Say("peek: crossbar slots " .. (#slots > 0 and table.concat(slots, ", ") or "none")
        .. ", action macro: " .. tostring(IF.Actions.Macro("peekmap")):gsub("\n", " | "))
    PeekMap.Say("peek: macro " .. tostring(hold:GetAttribute("ic-macro")) .. ", map frame: "
        .. tostring(WorldMapFrame ~= nil) .. ", map scroll: " .. tostring(WorldMapFrame and WorldMapFrame.ScrollContainer ~= nil)
        .. ", in combat: " .. tostring(IF.InCombat()) .. ", pending: " .. tostring(pending))
    -- (again once the chat box has closed: while it's open the click is the game's)
    if IF.Touch and IF.Touch.Probe then
        IF.Touch.Probe()
        if PeekMap.debug then C_Timer.After(2, IF.Touch.Probe) end
    end
    IF.Print("peek: press printing " .. (PeekMap.debug and "on, logged to the saved variables (/reload to write)"
        or ("off, " .. #(IF.db.peekLog or {}) .. " lines logged")))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    if pending then PeekMap.Apply() end
    -- (the peek's buttons, left bound when it ended in combat)
    if not peeking then PeekMap.Keys(false) end
end)
