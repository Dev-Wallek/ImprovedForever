-- Rare creatures on the world map (the peek map is the same map): a pin at each spawn of
-- the shown zone's rares (the core's GameData.Rares), the mouse over one: its name and level.
-- On unless turned off in the Map tab (IF.db.peekMap.rares false).
-- Our own frame on the map's canvas, redrawn when the map, its size or its zoom change:
-- no data provider, no hook into the map's code, nothing of the game's touched.
local IF = ImprovedForever

local PeekMap = IF.PeekMap

local RM = {}
IF.RareMap = RM

local SIZE = 18                -- on screen, whatever the zoom
local ATLAS = "VignetteKill"   -- (else the raid skull)

local holder
local pins = {}
local drawnId, drawnW, drawnZoom, drawnOn   -- the last drawing's (compared each frame: no strings made)

function RM.On()
    return PeekMap.Settings().rares ~= false
end

local function Level(r)
    local level = r.lo and (r.hi and r.hi ~= r.lo and (r.lo .. "-" .. r.hi) or tostring(r.lo)) or "?"
    return "Level " .. level .. (r.elite and " Rare Elite" or " Rare")
end

local function Pin(i)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Frame", nil, holder)
    p.icon = p:CreateTexture(nil, "OVERLAY")
    p.icon:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS) then
        p.icon:SetAtlas(ATLAS)
    else
        p.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    end
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.rare.name, 1, 0.82, 0)
        GameTooltip:AddLine(Level(self.rare), 1, 1, 1)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    pins[i] = p
    return p
end

local function Draw()
    local map = WorldMapFrame
    local canvas = map:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local zoom = map.ScrollContainer:GetCanvasScale()
    local id = map:GetMapID()
    local on = RM.On()
    if id == drawnId and w == drawnW and zoom == drawnZoom and on == drawnOn then return end
    drawnId, drawnW, drawnZoom, drawnOn = id, w, zoom, on
    local n = 0
    for _, r in ipairs(on and id and IF.GameData.Rares()[id] or {}) do
        for _, point in ipairs(r.points) do
            n = n + 1
            local p = Pin(n)
            p.rare = r
            -- (scaled against the zoom: the same size on screen; its offsets in its own scale)
            p:SetScale(1 / zoom)
            p:SetSize(SIZE, SIZE)
            p:ClearAllPoints()
            p:SetPoint("CENTER", canvas, "TOPLEFT", point[1] / 100 * w * zoom, -point[2] / 100 * h * zoom)
            p:Show()
        end
    end
    for i = n + 1, #pins do pins[i]:Hide() end
end

-- (the map loads on demand: our frame once it's there)
local function Build()
    if holder or not (WorldMapFrame and WorldMapFrame.GetCanvas) then return holder ~= nil end
    local canvas = WorldMapFrame:GetCanvas()
    if not canvas then return false end
    holder = CreateFrame("Frame", nil, canvas)
    holder:SetAllPoints(canvas)
    holder:SetFrameLevel(canvas:GetFrameLevel() + 2)
    -- (runs only while the map shows: the holder is on its canvas)
    holder:SetScript("OnUpdate", Draw)
    return true
end

local load = CreateFrame("Frame")
load:RegisterEvent("ADDON_LOADED")
load:RegisterEvent("PLAYER_LOGIN")
load:SetScript("OnEvent", function()
    if Build() then load:UnregisterAllEvents() end
end)
