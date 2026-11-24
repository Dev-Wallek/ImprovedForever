-- Threat on a mob for the player, the pet and the party, and the player's
-- warning: losing aggro (tanking, the next one close behind) or pulling it
-- (not tanking, near the tank's threat). What the game keeps secret (a
-- boss's values) is nil; its status often stays readable then.
local _, IF = ...

local T = {}
IF.Threat = T

T.UNITS = { "player", "pet", "party1", "party2", "party3", "party4" }

local PULL_AT = 90 -- (scaled percent; at 100 the aggro goes over)

local function Value(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    return v
end

-- unit's status on mob, or overall without one (0 to 3); nil: none, or secret
function T.Status(unit, mob)
    return Value(UnitThreatSituation(unit, mob))
end

-- { status, tanking, percent, lead } of unit on mob (percent and lead nil
-- when secret); nil: unit isn't on its threat list
function T.Of(unit, mob)
    local tanking, status, percent = UnitDetailedThreatSituation(unit, mob)
    status = Value(status)
    if status == nil then
        status = T.Status(unit, mob)
        if status == nil then return nil end
        return { status = status, tanking = status >= 2 }
    end
    return {
        status = status,
        tanking = Value(tanking),
        percent = Value(percent),
        -- (0 to 3: how far ahead of the second the tank is, 3 the closest)
        lead = Value(UnitThreatLeadSituation(unit, mob)),
    }
end

-- The player's on mob: "losing", "pulling" or nil
function T.Warning(mob)
    local me = T.Of("player", mob)
    if not me then return nil end
    if me.tanking then
        -- (status 2: tanking, but another has more threat)
        if me.status == 2 or me.lead == 3 then return "losing" end
    elseif me.status == 1 or (me.percent or 0) >= PULL_AT then
        return "pulling"
    end
    return nil
end
