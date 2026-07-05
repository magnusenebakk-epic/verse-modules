using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }

using { Gameplay.Ownership }


# Interact to unlock NodeKey in the ancestor unlock_state_component,
# optionally owner-gated. Publishes the outcome so feedback (UI, sound)
# subscribes here instead of re-deriving why it failed.
unlock_purchase_interactable_component<public> := class<final_super>(basic_interactable_component):

    @editable
    NodeKey<public>:string

    @editable
    RestrictToOwners<public>:logic = true

    PurchasedEvent<public>:Concurrency.subscribable_event(agent) =
        Concurrency.subscribable_event(agent){}

    # Denied attempts: not owner, requirements unmet, or commit race.
    DeniedEvent<public>:Concurrency.subscribable_event(agent) =
        Concurrency.subscribable_event(agent){}

    var Subscription<private>:?cancelable = false
    var StateSubs<private>:[]Concurrency.subscription_task(unlock_node_component) = array{}

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        Enable()

    # Follow the node's lifecycle so reconstruction works: any unlock path
    # disables the pad, base reset re-enables it for the next owner.
    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (State := Entity.FindUnlockState[]):
            set StateSubs += array{
                State.NodeUnlockedEvent.Subscribe(OnNodeUnlocked),
                State.NodeResetEvent.Subscribe(OnNodeReset)
            }
            if (State.IsUnlocked[NodeKey]):
                Disable()

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : StateSubs):
            S.Cancel()
        set StateSubs = array{}

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        Disable()

    OnNodeUnlocked<private>(N:unlock_node_component):void =
        if (N.Key = NodeKey):
            Disable()

    OnNodeReset<private>(N:unlock_node_component):void =
        if (N.Key = NodeKey):
            Enable()

    Enable<override>():void =
        (super:)Enable()
        if (not Subscription?):
            set Subscription = option{SucceededEvent.Subscribe(OnInteractionSucceeded)}

    Disable<override>():void =
        (super:)Disable()
        if (Subscription?.Cancel()):
            set Subscription = false

    OnInteractionSucceeded<protected>(Agent:agent):void =
        if (State := Entity.FindUnlockState[]):
            if (RestrictToOwners?, not Agent.OwnsEntity[Entity]):
                DeniedEvent.Signal(Agent)
                return
            Outcome := State.TryUnlock(NodeKey, Agent)
            if (Outcome.GetSuccess[]):
                PurchasedEvent.Signal(Agent) # NodeUnlockedEvent disables us
            else:
                DeniedEvent.Signal(Agent)
