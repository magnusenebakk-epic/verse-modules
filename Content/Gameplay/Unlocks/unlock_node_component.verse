using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# A single unlockable thing in a base. Self-registers by Key with the
# nearest ancestor unlock_state_component. Scene reactions go through
# Presenters; the node carries no gameplay of its own.
unlock_node_component<public> := class<final_super>(component):

    # Must be unique within the owning state.
    @editable
    Key<public>:string

    @editable
    Requirements<public>:[]unlock_requirement = array{}

    # Node keys that must be unlocked first. Folded into AllRequirements()
    # as an unlocked_nodes_requirement.
    @editable
    Dependencies<public>:[]string = array{}

    # Unlock for free when the base is claimed.
    @editable
    AutoUnlock<public>:logic = false

    # Scene reactions: visibility, prefab spawn, event dispatch.
    @editable
    Presenters<public>:[]unlock_presenter = array{}

    var Subscriptions<private>:[]Concurrency.subscription_task(unlock_node_component) = array{}

    # Requirements and Dependencies as one list so the state has a single
    # thing to check/commit. <transacts> because it allocates.
    AllRequirements<public>()<transacts>:[]unlock_requirement =
        if (Dependencies.Length > 0):
            array{unlocked_nodes_requirement{RequiredKeys := Dependencies}} + Requirements
        else:
            Requirements

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        if (State := Entity.FindUnlockState[]):
            State.RegisterNode(Self)

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        if (State := Entity.FindUnlockState[]):
            State.UnregisterNode(Self)
        for (S : Subscriptions):
            S.Cancel()
        set Subscriptions = array{}

    # Called once by state.RegisterNode. The state drives setup so it can
    # order registration, persistence restore and auto-unlocks.
    OnAttachToState<public>(State:unlock_state_component):void =
        for (P : Presenters):
            P.OnNodeInit(Entity, Self, State)
        set Subscriptions += array{
            State.NodeUnlockedEvent.Subscribe(OnAnyNodeUnlocked),
            State.NodeResetEvent.Subscribe(OnAnyNodeReset)
        }

    # Called directly by the state for late registration into an unlocked
    # key. Normal unlocks arrive via the event subscription below.
    DispatchUnlocked<public>(State:unlock_state_component):void =
        for (P : Presenters):
            P.OnNodeUnlocked(Entity, Self, State)

    OnAnyNodeUnlocked<private>(N:unlock_node_component):void =
        if (N = Self, State := Entity.FindUnlockState[]):
            DispatchUnlocked(State)

    OnAnyNodeReset<private>(N:unlock_node_component):void =
        if (N = Self, State := Entity.FindUnlockState[]):
            for (P : Presenters):
                P.OnNodeReset(Entity, Self, State)
