using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


stat_modifier_op<public> := class<abstract>:
    Apply<public>(Current:float, Value:float)<transacts>:float


stat_add_op<public> := class<concrete>(stat_modifier_op):
    Apply<override>(Current:float, Value:float)<transacts>:float = Current + Value


stat_mul_op<public> := class<concrete>(stat_modifier_op):
    Apply<override>(Current:float, Value:float)<transacts>:float = Current * Value


stat_override_op<public> := class<concrete>(stat_modifier_op):
    Apply<override>(Current:float, Value:float)<transacts>:float = Value


stat_modifier<public> := class<concrete>:

    @editable
    Stat<public>:subtype(stat_value) = stat_value

    @editable
    Op<public>:stat_modifier_op = stat_add_op{}

    @editable
    Value<public>:float = 0.0


modifier_with_source := class:
    Modifier:stat_modifier
    Source:entity


# StatChangedEvent payload.
stat_change<public> := class:
    Stat<public>:stat_value
    OldValue<public>:float
    NewValue<public>:float


# Stat min/max source.
stat_bound<public> := class<abstract>:
    Get<public>()<reads>:float


fixed_stat_bound<public> := class<concrete>(stat_bound):

    @editable
    Value<public>:float = 0.0

    Get<override>()<computes>:float = Value


# uses Default if the ref isn't found.
stat_ref_stat_bound<public> := class(stat_bound):

    @editable
    StatType<public>:subtype(stat_value)

    @editable
    Default<public>:float = 0.0

    var<private> Resolved<private>:?stat_value = false

    Get<override>()<reads>:float =
        if (S := Resolved?) then S.GetCurrent() else Default

    SetResolved<public>(S:stat_value):void =
        set Resolved = option{S}


# Final = clamp((Base + sum(Add)) * prod(Mul), MinVal, MaxVal). Override is last.
stat_value<public> := class<concrete><castable>:

    @editable
    Name<public>:[]char = ""

    @editable
    var Base<public>:float = 0.0

    @editable
    MinVal<public>:stat_bound = fixed_stat_bound{Value := -1000000.0}

    @editable
    MaxVal<public>:stat_bound = fixed_stat_bound{Value := 1000000.0}

    StatChangedEvent<public>:Concurrency.subscribable_event(stat_change) = Concurrency.subscribable_event(stat_change){}

    var<private> Mods<private>:[]modifier_with_source = array{}
    var<private> Current<private>:float = 0.0

    Init<public>()<transacts>:void =
        set Current = CalculateValue()

    GetCurrent<public>()<reads>:float = Current

    AddModifier<public>(M:stat_modifier, Source:entity):void =
        set Mods += array{ modifier_with_source{ Modifier := M, Source := Source } }
        Recompute()

    RemoveModifiersFrom<public>(Source:entity):void =
        set Mods = for (X : Mods, not (X.Source = Source)) { X }
        Recompute()

    # Not <decides>: Recompute fires StatChangedEvent (no_rollback).
    TrySpend<public>(Amount:float):logic =
        if (Current >= Amount):
            set Base = Base - Amount
            Recompute()
            true
        else:
            false

    Restore<public>(Amount:float):void =
        set Base = Base + Amount
        Recompute()

    Recompute<public>():void =
        MaxV := MaxVal.Get()
        MinV := MinVal.Get()
        if (Base > MaxV). set Base = MaxV
        if (Base < MinV). set Base = MinV
        NewVal := CalculateValue()
        if (NewVal <> Current):
            Old := Current
            set Current = NewVal
            StatChangedEvent.Signal(stat_change{Stat := Self, OldValue := Old, NewValue := NewVal})

    OnDependencyChanged<public>(Change:stat_change):void =
        Recompute()

    CalculateValue<private>()<transacts>:float =
        var V:float = Base
        for (X : Mods):
            set V = X.Modifier.Op.Apply(V, X.Modifier.Value)
        MinV := MinVal.Get()
        MaxV := MaxVal.Get()
        if (V < MinV). set V = MinV
        if (V > MaxV). set V = MaxV
        V
