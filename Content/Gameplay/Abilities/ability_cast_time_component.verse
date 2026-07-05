using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }


ability_cast_time_component<public> := class<final_super>(component):

    @editable
    Duration<public>:float = 1.0

    @editable
    CancelOnDamage<public>:logic = false

    var<private> CancelSignal<private>:event() = event(){}
    var<private> Cancelled<private>:logic = false

    CastStartedEvent<public>:Concurrency.subscribable_event(float) =
        Concurrency.subscribable_event(float){}

    CastCompletedEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    CastCancelledEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    Cancel<public>():void =
        CancelSignal.Signal()

    Wait<public>(Activator:agent)<suspends>:logic =
        set Cancelled = false
        CastStartedEvent.Signal(Duration)
        race:
            CompleteArm()
            CancelArm()
            DamageArm(Activator)
        if (Cancelled?):
            CastCancelledEvent.Signal(())
            true
        else:
            CastCompletedEvent.Signal(())
            false

    CompleteArm<private>()<suspends>:void =
        Sleep(Duration)

    CancelArm<private>()<suspends>:void =
        CancelSignal.Await()
        set Cancelled = true

    DamageArm<private>(Activator:agent)<suspends>:void =
        if:
            CancelOnDamage?
            P := player[Activator]
            Char := P.GetFortCharacter[]
        then:
            Char.DamagedEvent().Await()
            set Cancelled = true
        else:
            Sleep(Inf)
