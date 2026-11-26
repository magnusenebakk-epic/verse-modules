using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


entity_damage_event<public> := class:
    Amount<public>:float
    Source<public>:?agent
    Remaining<public>:float


# Health for non-agent entities; the player damage pipeline only works on agents, so damage dealers call TakeDamage here directly.
entity_health_component<public> := class<final_super>(component):

    @editable
    var MaxHealth<public>:float = 100.0

    # Remove the entity from the scene when health hits zero.
    @editable
    var DestroyOnDeath<public>:logic = true

    DamagedEvent<public>:Concurrency.subscribable_event(entity_damage_event) =
        Concurrency.subscribable_event(entity_damage_event){}

    DestroyedEvent<public>:Concurrency.subscribable_event(?agent) =
        Concurrency.subscribable_event(?agent){}

    var<private> Current<private>:float = 0.0
    var<private> Initialized<private>:logic = false

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        if (not Initialized?):
            set Current = MaxHealth
            set Initialized = true

    GetCurrent<public>()<reads>:float = Current

    IsAlive<public>()<reads><decides>:void =
        Current > 0.0

    TakeDamage<public>(Amount:float, Source:?agent):void =
        if (Current <= 0.0). return
        Dealt := if (Amount > Current) then Current else Amount
        if (Dealt <= 0.0). return
        set Current -= Dealt
        DamagedEvent.Signal(entity_damage_event{
            Amount := Dealt,
            Source := Source,
            Remaining := Current
        })
        if (Current <= 0.0):
            DestroyedEvent.Signal(Source)
            if (DestroyOnDeath?):
                Entity.RemoveFromParent()

    Heal<public>(Amount:float):void =
        if (Current <= 0.0). return
        Healed := if (Current + Amount > MaxHealth) then MaxHealth - Current else Amount
        set Current += Healed
