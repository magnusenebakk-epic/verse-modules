using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }

using { Abilities }


# Marks a descendant entity as the projectile spawn point (barrel tip).
# Without one, spawning falls back to the holder's own transform.
projectile_socket_component<public> := class<final_super>(component):


# Spawns a projectile at the holder's socket, aimed at the use target if any. Configure inside
# the tower ability's Actions list. Damages agents via DamageApplier and custom-health entities
# via DamageableTags (see projectile_component).
fire_projectile_action<public> := class(use_action):

    @editable
    ProjectilePrefab<public>:concrete_subtype(entity)

    Execute<override>(EffectEntity:entity, Holder:entity):void =
        TargetOpt:?entity = option{EffectEntity.GetUseTarget[]}
        Activator:?agent = option{EffectEntity.GetUseAttribution[Holder]}
        if (Sim := Holder.GetSimulationEntity[]):
            Socket := SpawnTransform(Holder)
            From := Socket.Translation
            Rot := if (Target := TargetOpt?):
                To := Target.GetGlobalTransform().Translation
                MakeShortestRotationBetween(
                    (LUF:)vector3{Forward := 1.0, Left := 0.0, Up := 0.0},
                    (To - From).MakeUnitVector()
                )
            else:
                Socket.Rotation
            New := ProjectilePrefab{}
            Sim.AddEntities(array{New})
            New.SetGlobalTransform((LUF:)transform{
                Translation := From,
                Rotation := Rot,
                # keep the prefab-authored scale
                Scale := New.GetGlobalTransform().Scale
            })
            SrcComp := source_component { Entity := New, Source := Activator }
            New.AddComponents(array{SrcComp})
            if (Stored := New.GetComponent[source_component]):
                set Stored.Source = Activator
            # projectile flies at the sim root; stamp membership so gates know whose shot it is
            if (G := FindOwningGame[Holder]):
                G.Claim(New)
            # hand the fire-time target to assigned delivery modes; spatial ones ignore it
            if (PC := New.GetComponent[projectile_component]):
                PC.SetAssignedTarget(TargetOpt)

    SpawnTransform<private>(Holder:entity)<transacts>:(LUF:)transform =
        if (S := first{C:Holder.FindDescendantComponents(projectile_socket_component)}, true?):
            S.Entity.GetGlobalTransform()
        else:
            Holder.GetGlobalTransform()


# spawn_prefab_action that claims the spawn for the holder's game, so
# ability-spawned combat prefabs aren't unaffiliated on multi-board maps.
td_spawn_prefab_action<public> := class(spawn_prefab_action):
    OnSpawned<override>(New:entity, Instigator:?agent, Holder:entity):void =
        if (G := FindOwningGame[Holder]):
            G.Claim(New)
