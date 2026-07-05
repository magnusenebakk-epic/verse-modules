using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


ability_charges_component<public> := class<final_super>(component):

    @editable
    (ability_charges_component:)Max<public>:int = 1

    @editable
    RechargeInterval<public>:float = 5.0

    var<private> Current<private>:int = 0

    ChargeChangedEvent<public>:Concurrency.subscribable_event(int) =
        Concurrency.subscribable_event(int){}

    GetCurrent<public>()<reads>:int = Current

    HasCharge<public>()<decides><reads>:void = Current > 0

    Consume<public>():void =
        if (Current > 0):
            set Current = Current - 1
            ChargeChangedEvent.Signal(Current)

    OnSimulate<override>()<suspends>:void =
        set Current = Self.Max
        ChargeChangedEvent.Signal(Current)
        loop:
            Sleep(RechargeInterval)
            if (Current < Self.Max):
                set Current = Current + 1
                ChargeChangedEvent.Signal(Current)
