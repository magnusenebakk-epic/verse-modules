using { /Fortnite.com/Characters }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/Temporary/SpatialMath }

using { Effects }


# Composable per-use behavior for gated_ability, run by the hub on the BeginUse edge after
# gates commit. The behavior twin of ability_gate: Gates decide WHETHER a use happens, Actions
# decide WHAT it does. Executes in no-rollback context, so signalling and spawning are fine.
# Resolve use data from EffectEntity via GetUseTarget / GetUseInstigator / GetUseAttribution.
use_action<public> := class<abstract>:
    Execute<public>(EffectEntity:entity, Holder:entity):void


# Spawns Prefab a fixed distance ahead of the use instigator's character.
spawn_prefab_action<public> := class(use_action):

    @editable
    Prefab<public>:concrete_subtype(entity)

    @editable
    DistanceAhead<public>:float = 200.0

    Execute<override>(EffectEntity:entity, Holder:entity):void =
        if:
            Activator := EffectEntity.GetUseInstigator[]
            P := player[Activator]
            Char := P.GetFortCharacter[]
            CharXform := FromTransform(Char.GetTransform())
            Sim := Holder.GetSimulationEntity[]
        then:
            CharViewRotation := Char.GetViewRotation()

            Forward := CharXform.Rotation.GetForwardAxis()
            FlatForward := (LUF:)vector3{
                Forward := Forward.Forward,
                Left := Forward.Left,
                Up := 0.0
            }.MakeUnitVector()
            SpawnPos := CharXform.Translation + FlatForward * DistanceAhead
            New := Prefab{}
            Sim.AddEntities(array{New})
            New.SetGlobalTransform((LUF:)transform{
                Translation := SpawnPos,
                Rotation := FromRotation(CharViewRotation),
                # keep the prefab-authored scale
                Scale := New.GetGlobalTransform().Scale
            })

            SrcComp := source_component { Entity := New, Source := option{Activator} }
            New.AddComponents(array{SrcComp})
            if (Stored := New.GetComponent[source_component]):
                set Stored.Source = option{Activator}
            OnSpawned(New, option{Activator}, Holder)

    # spawn lands at the sim root; subclasses attach ownership or membership here
    OnSpawned<protected>(New:entity, Instigator:?agent, Holder:entity):void = {}


# Applies EffectPrefab to the use target, else to the instigator's stats holder.
apply_effect_action<public> := class(use_action):

    @editable
    EffectPrefab<public>:concrete_subtype(effect_base)

    Execute<override>(EffectEntity:entity, Holder:entity):void =
        Instigator:?agent = option{EffectEntity.GetUseInstigator[]}
        if (Target := EffectEntity.GetUseTarget[]):
            SpawnEffectOnTarget(Target, EffectPrefab, Instigator)
        else if (A := Instigator?, StatsHolder := A.GetStatsHolderEntity[]):
            SpawnEffectOnTarget(StatsHolder, EffectPrefab, Instigator)
