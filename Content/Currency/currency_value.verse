using { /Verse.org/Assets }
using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


currency_change<public> := class:
    (currency_change:)Currency<public>:currency_value
    OldAmount<public>:int
    NewAmount<public>:int


currency_value<public> := class<castable>(has_icon):

    @editable
    Name<public>:string = ""

    @editable
    Backing<public>:currency_backing = counter_backing{}

    ChangedEvent<public>:Concurrency.subscribable_event(currency_change) =
        Concurrency.subscribable_event(currency_change){}

    GetAmount<public>(Holder:entity)<transacts>:int = Backing.GetAmount(Holder)

    Add<public>(Holder:entity, N:int):logic =
        Old := Backing.GetAmount(Holder)
        if (Backing.Add[Holder, N]):
            ChangedEvent.Signal(currency_change{Currency := Self, OldAmount := Old, NewAmount := Old + N})
            true
        else:
            false

    TrySpend<public>(Holder:entity, N:int):logic = # no rollback - signal
        Old := Backing.GetAmount(Holder)
        if (Backing.TrySpend[Holder, N]):
            ChangedEvent.Signal(currency_change{Currency := Self, OldAmount := Old, NewAmount := Old - N})
            true
        else:
            false

    # Transactional spend with no event, so it can run inside a rollback
    # context (e.g. an unlock commit). Pair with NotifySpent after the
    # enclosing transaction commits.
    Spend<public>(Holder:entity, N:int)<transacts><decides>:void =
        Backing.TrySpend[Holder, N]

    # Post-commit notification for a Spend(N) that already happened.
    NotifySpent<public>(Holder:entity, N:int):void =
        New := Backing.GetAmount(Holder)
        ChangedEvent.Signal(currency_change{Currency := Self, OldAmount := New + N, NewAmount := New})
