-- Newly authored for this project's bounded native fixture, not copied from an
-- upstream card-script collection. Core ID 4335645 = printed passcode 04335645.
-- Primary text: Konami CID 5484 (English).
-- Primary timing/mandatory ruling: Konami CID 5484 Q&A (Japanese, 2022-04-29).
-- Mandatory GY trigger at the end of the Damage Step after battle destruction.

function c4335645.initial_effect(card)
    local trigger = Effect.CreateEffect(card)
    trigger:SetDescription(4335645 * 16)
    trigger:SetCategory(CATEGORY_DESTROY)
    trigger:SetType(EFFECT_TYPE_SINGLE | EFFECT_TYPE_TRIGGER_F)
    trigger:SetCode(EVENT_BATTLE_DESTROYED)
    trigger:SetProperty(EFFECT_FLAG_CARD_TARGET)
    trigger:SetCondition(c4335645.battle_to_grave)
    trigger:SetTarget(c4335645.choose_monster)
    trigger:SetOperation(c4335645.destroy_target)
    card:RegisterEffect(trigger)
end

function c4335645.battle_to_grave(effect)
    local card = effect:GetHandler()
    return card:IsLocation(LOCATION_GRAVE) and card:IsReason(REASON_BATTLE)
end

function c4335645.choose_monster(effect, player, group, event_player, event_value, reason_effect, reason, reason_player, checking, clicked)
    if clicked then
        return clicked:IsLocation(LOCATION_MZONE)
    end
    -- Do not turn a mandatory trigger into an optional/conditional activation.
    if checking == 0 then
        return true
    end
    local selected = Duel.SelectTarget(player, nil, player,
        LOCATION_MZONE, LOCATION_MZONE, 1, 1, nil)
    Duel.SetOperationInfo(0, CATEGORY_DESTROY, selected, 1, 0, 0)
end

function c4335645.destroy_target(effect)
    local target = Duel.GetFirstTarget()
    if target and target:IsRelateToEffect(effect) then
        Duel.Destroy(target, REASON_EFFECT)
    end
end
