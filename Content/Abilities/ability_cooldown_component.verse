using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


ability_cooldown_component<public> := class<final_super>(component):

    @editable
    Duration<public>:float = 1.0

    var<private> OnCooldown<private>:logic = false

    CooldownStartedEvent<public>:Concurrency.subscribable_event(float) =
        Concurrency.subscribable_event(float){}

    CooldownEndedEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    IsOnCooldown<public>()<decides><reads>:void = OnCooldown?

    StartCooldown<public>():void =
        if (not OnCooldown?):
            set OnCooldown = true
            CooldownStartedEvent.Signal(Duration)
            spawn { Timer() }

    Timer<private>()<suspends>:void =
        Sleep(Duration)
        set OnCooldown = false
        CooldownEndedEvent.Signal(())
