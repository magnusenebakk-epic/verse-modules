using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }


# Interactable where only owners count. SucceededEvent still fires for
# anyone; OwnerInteractedEvent only when the activator owns the entity.
# Non-owners land in DeniedInteractionEvent for deny feedback.
ownership_gated_interactable_component<public> := class<final_super>(basic_interactable_component):

    OwnerInteractedEvent<public>:Concurrency.subscribable_event(agent) =
        Concurrency.subscribable_event(agent){}

    DeniedInteractionEvent<public>:Concurrency.subscribable_event(agent) =
        Concurrency.subscribable_event(agent){}

    var Subscription<private>:?cancelable = false

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        Enable()

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        Disable()

    Enable<override>():void =
        (super:)Enable()
        if (not Subscription?):
            set Subscription = option{SucceededEvent.Subscribe(OnInteractionSucceeded)}

    Disable<override>():void =
        (super:)Disable()
        if (Subscription?.Cancel()):
            set Subscription = false

    OnInteractionSucceeded<protected>(Agent:agent):void =
        if (Agent.OwnsEntity[Entity]):
            OwnerInteractedEvent.Signal(Agent)
        else:
            DeniedInteractionEvent.Signal(Agent)
