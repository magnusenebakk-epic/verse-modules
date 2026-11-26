using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }

using { Abilities }
using { Damage }


# Damages the resolved use target's entity_health_component; pair with tower_radius_targeter
# so the driver only fires with a tower in reach. Configure inside the ability's Actions list.
damage_target_action<public> := class(use_action):

    @editable
    var DamageAmount<public>:float = 10.0

    Execute<override>(EffectEntity:entity, Holder:entity):void =
        if:
            Target := EffectEntity.GetUseTarget[]
            Health := Target.GetComponent[entity_health_component]
        then:
            Health.TakeDamage(DamageAmount, option{EffectEntity.GetUseAttribution[Holder]})


# Piercing arrow: damages every tower within Width of the lane ahead.
# Self-aiming; VisualPrefab, if set, flies down the lane as pure cosmetics.
lane_pierce_action<public> := class(use_action):

    @editable
    var DamageAmount<public>:float = 15.0

    # How far from the lane centerline a tower can stand and still be hit.
    @editable
    var Width<public>:float = 250.0

    # How far ahead along the path the pierce reaches.
    @editable
    var PierceRange<public>:float = 2000.0

    @editable
    VisualPrefab<public>:?concrete_subtype(entity) = false

    Execute<override>(EffectEntity:entity, Holder:entity):void =
        Pos := Holder.GetGlobalTransform().Translation
        if:
            Found := FindNearestLane[Holder, Pos]
            Lane := Found(0)
            MyProgress := Found(1)
        then:
            DamageTowersAlong(Lane, MyProgress, option{EffectEntity.GetUseAttribution[Holder]}, Holder)
            SpawnVisual(Lane, MyProgress, Pos, Holder)

    DamageTowersAlong<private>(Lane:lane_component, MyProgress:float, Instigator:?agent, Holder:entity):void =
        if (Sim := Holder.GetSimulationEntity[]):
            Hits := for:
                T : Sim.FindDescendantEntitiesWithTag(tower_tag)
                # adjacent boards' towers can project onto this lane too
                MayEngage[Holder, T]
                Proj := Lane.ProjectOntoPath[T.GetGlobalTransform().Translation]
                Proj(0) >= MyProgress
                Proj(0) <= MyProgress + PierceRange
                Proj(1) <= Width
                Health := T.GetComponent[entity_health_component]
            do:
                Health
            for (H : Hits):
                H.TakeDamage(DamageAmount, Instigator)

    SpawnVisual<private>(Lane:lane_component, MyProgress:float, Pos:(LUF:)vector3, Holder:entity):void =
        if:
            Prefab := VisualPrefab?
            Dir := Lane.DirectionAt[MyProgress]
            Sim := Holder.GetSimulationEntity[]
        then:
            New := Prefab{}
            Sim.AddEntities(array{New})
            New.SetGlobalTransform((LUF:)transform{
                Translation := Pos,
                Rotation := MakeShortestRotationBetween(
                    (LUF:)vector3{Forward := 1.0, Left := 0.0, Up := 0.0},
                    Dir
                ),
                # keep the prefab-authored scale
                Scale := New.GetGlobalTransform().Scale
            })
            # the visual still carries a live projectile_component; stamp it so its hit gate stays on this board
            if (G := FindOwningGame[Holder]):
                G.Claim(New)
