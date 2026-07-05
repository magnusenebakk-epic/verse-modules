using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


passive_effect_entry<public> := class<concrete>:

    @editable
    EffectPrefab<public>:?concrete_subtype(effect_base) = false

    @editable
    var Resolver<public>:effect_target_resolver = while_equipped_resolver{}

    @editable
    var LocalOffset<public>:vector3 = vector3{}

    var<private> ActiveEffect<private>:?entity = false

    Reconcile<public>(Target:entity):void =
        if (Active := ActiveEffect?):
            ShouldKeep:logic = if (P := Active.GetParent[], P = Target) then true else false
            if (not ShouldKeep?):
                Active.RemoveFromParent()
                set ActiveEffect = false
        if (not ActiveEffect?, EP := EffectPrefab?):
            New := EP{}
            Target.AddEntities(array{New})
            New.SetLocalTransform(transform{
                Translation := LocalOffset,
                Rotation := IdentityRotation(),
                Scale := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
            })
            set ActiveEffect = option{New}

    Cleanup<public>():void =
        if (E := ActiveEffect?):
            E.RemoveFromParent()
            set ActiveEffect = false


passive_effect_component<public> := class<final_super>(component):

    @editable
    (passive_effect_component:)Effects<public>:[]passive_effect_entry = array{}

    var<private> ComponentCancel<private>:event() = event(){}

    OnSimulate<override>()<suspends>:void =
        for (Entry : (passive_effect_component:)Effects):
            spawn { ManageEntry(Entry) }
        Sleep(Inf)

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        ComponentCancel.Signal()
        for (Entry : (passive_effect_component:)Effects):
            Entry.Cleanup()

    ManageEntry<private>(Entry:passive_effect_entry)<suspends>:void =
        race:
            ComponentCancel.Await()
            ReconcileLoop(Entry)

    ReconcileLoop<private>(Entry:passive_effect_entry)<suspends>:void =
        loop:
            if (Target := Entry.Resolver.GetTarget[Self]):
                Entry.Reconcile(Target)
            else:
                Entry.Cleanup()
            Entry.Resolver.AwaitNextChange(Self)
