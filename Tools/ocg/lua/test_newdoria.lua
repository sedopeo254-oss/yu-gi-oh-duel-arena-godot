-- Predicate-level negative controls. These do not simulate banishment or effect
-- destruction in a full duel; the battle fixtures separately exercise the core.
local function check(location, reason, expected)
    local card = {
        IsLocation = function(_, wanted) return location == wanted end,
        IsReason = function(_, wanted) return (reason & wanted) ~= 0 end
    }
    local effect = {GetHandler = function() return card end}
    assert(c4335645.battle_to_grave(effect) == expected,
        "Newdoria battle-to-GY condition mismatch")
end
check(LOCATION_GRAVE, REASON_BATTLE, true)
check(LOCATION_GRAVE, REASON_EFFECT, false)
check(0x20, REASON_BATTLE, false) -- banished, not GY
check(0x20, REASON_EFFECT, false)
