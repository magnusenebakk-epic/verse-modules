using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Damage }


apply_effects_after_damage_component<public> := class<final_super>(component, after_damage_dealing_handler):

    @editable
    (apply_effects_after_damage_component:)Effects<public>:[]concrete_subtype(effect_base) = array{}

    AfterDealingDamage<override>(Payload:damage_payload):void =
        if (TargetHolder := Payload.Target.GetStatsHolderEntity[]):
            for (P : Self.Effects):
                SpawnEffectOnTarget(TargetHolder, P, Payload.Source)
