using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# Pluggable reaction to a node's lock/unlock lifecycle. All hooks default to
# no-op so concrete presenters only override what they need.
unlock_presenter<public> := class<abstract>:
    # Called once when the node attaches to its state, before any unlock event.
    # Visibility presenters hide entities up-front here.
    OnNodeInit<public>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void = {}

    OnNodeUnlocked<public>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void = {}

    OnNodeReset<public>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void = {}


# Hides ManagedEntities until the node unlocks. Author them as children of
# Host in UEFN; init detaches them, unlock re-attaches under Host.
entity_visibility_presenter<public> := class<concrete>(unlock_presenter):

    @editable
    ManagedEntities<public>:[]entity = array{}

    var Removed<private>:[]entity = array{}

    OnNodeInit<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        if (not State.IsUnlocked[Node.Key]):
            HideEntities()

    OnNodeUnlocked<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        if (Removed.Length > 0):
            Host.AddEntities(Removed)
            set Removed = array{}

    OnNodeReset<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        HideEntities()

    HideEntities<private>():void =
        if (Removed.Length = 0):
            set Removed = for (E : ManagedEntities):
                E.RemoveFromParent()
                E


# Spawns Prefab as a child of Host on unlock, despawns on reset. The spawned
# prefab's own components carry the unlocked gameplay.
prefab_spawn_presenter<public> := class<concrete>(unlock_presenter):

    @editable
    Prefab<public>:?concrete_subtype(entity) = false

    var Spawned<private>:?entity = false

    OnNodeUnlocked<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        if (not Spawned?, P := Prefab?, T:concrete_subtype(entity) = P):
            New := T{}
            Host.AddEntities(array{New})
            set Spawned = option{New}

    OnNodeReset<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        if (S := Spawned?):
            S.RemoveFromParent()
            set Spawned = false


# Implement this on a feature component and the dispatch presenter below
# toggles it on init/unlock/reset. No per-feature bridge components needed.
#
# Same shape as the engine's enableable. Note that implementing both does
# not share one method pair; same-named members from different interfaces
# need qualified implementations:
#     jetpack_component := class<final_super>(component, enableable, unlockable):
#         (enableable:)Enable<override>():void = DoEnable()
#         (unlockable:)Enable<override>():void = DoEnable()
# Implementing only unlockable needs no qualification.
unlockable<public> := interface<castable>(p_interface):
    Enable<public>():void
    Disable<public>():void


unlockable_dispatch_presenter<public> := class<concrete>(unlock_presenter):

    # Scanned in addition to the node's subtree, for features that live
    # elsewhere.
    @editable
    AdditionalEntities<public>:[]entity = array{}

    OnNodeInit<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        if (not State.IsUnlocked[Node.Key]):
            Dispatch(Host, false)

    OnNodeUnlocked<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        Dispatch(Host, true)

    OnNodeReset<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        Dispatch(Host, false)

    Dispatch<private>(Host:entity, Enabled:logic):void =
        for (Root : array{Host} + AdditionalEntities):
            for (U : Root.GetDescendantComponentsWithInterface(unlockable)):
                if (Enabled?):
                    U.Enable()
                else:
                    U.Disable()


# Fires events instead of doing anything itself. Drop one on the node and
# any component with a reference can Subscribe/Await.
event_dispatch_presenter<public> := class<concrete>(unlock_presenter):

    UnlockedEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    ResetEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    OnNodeUnlocked<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        UnlockedEvent.Signal()

    OnNodeReset<override>(Host:entity, Node:unlock_node_component, State:unlock_state_component):void =
        ResetEvent.Signal()
