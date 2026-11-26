using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Abilities }
using { /Fortnite.com/Abilities }


# Composable use requirement for gated_ability. CanPass is the read-only check
# behind the official CanUse; mutations (paying, timers) happen on the use edges,
# which run outside CanUse's rollback context.
# CanPass also runs in the server's ~5 Hz CanUse poller for item abilities; keep it cheap.
ability_gate<public> := class<abstract><castable>:

    CanPass<public>(Context:ability_context)<decides><reads>:void

    OnUseBegan<public>(Context:?ability_context, EffectComp:?ability_effect_component):void = {}

    OnUseEnded<public>(Context:?ability_context):void = {}

    # long-running upkeep (recharge); the gate driver runs this for its component's lifetime
    Maintain<public>()<suspends>:void = {}


# Dev tool: always fails. Add to Gates to verify the native use path consults CanUse.
blocked_gate<public> := class<concrete>(ability_gate):

    CanPass<override>(Context:ability_context)<decides><computes>:void =
        false?


cooldown_start<public> := enum:
    BeginUse
    EndUse


cooldown_gate<public> := class<concrete>(ability_gate):

    @editable
    Duration<public>:float = 1.0

    # BeginUse: cooldown runs from activation. EndUse: from when the effect finishes.
    @editable
    StartOn<public>:cooldown_start = cooldown_start.BeginUse

    var<private> OnCooldown<private>:logic = false

    CooldownStartedEvent<public>:Concurrency.subscribable_event(float) =
        Concurrency.subscribable_event(float){}

    CooldownEndedEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    IsOnCooldown<public>()<decides><reads>:void = OnCooldown?

    CanPass<override>(Context:ability_context)<decides><reads>:void =
        not OnCooldown?

    OnUseBegan<override>(Context:?ability_context, EffectComp:?ability_effect_component):void =
        if (StartOn = cooldown_start.BeginUse):
            Begin()

    OnUseEnded<override>(Context:?ability_context):void =
        if (StartOn = cooldown_start.EndUse):
            Begin()

    Begin<private>():void =
        if (OnCooldown?). return
        set OnCooldown = true
        CooldownStartedEvent.Signal(Duration)
        spawn { Timer() }

    Timer<private>()<suspends>:void =
        Sleep(Duration)
        set OnCooldown = false
        CooldownEndedEvent.Signal(())


charges_gate<public> := class<concrete>(ability_gate):

    @editable
    MaxCharges<public>:int = 1

    @editable
    RechargeInterval<public>:float = 5.0

    var<private> Current<private>:int = 0

    ChargeChangedEvent<public>:Concurrency.subscribable_event(int) =
        Concurrency.subscribable_event(int){}

    GetCurrent<public>()<reads>:int = Current

    HasCharge<public>()<decides><reads>:void = Current > 0

    CanPass<override>(Context:ability_context)<decides><reads>:void =
        Current > 0

    OnUseBegan<override>(Context:?ability_context, EffectComp:?ability_effect_component):void =
        if (Current > 0):
            set Current -= 1
            ChargeChangedEvent.Signal(Current)

    Maintain<override>()<suspends>:void =
        set Current = MaxCharges
        ChargeChangedEvent.Signal(Current)
        loop:
            Sleep(RechargeInterval)
            if (Current < MaxCharges):
                set Current += 1
                ChargeChangedEvent.Signal(Current)


# Optimistic in CanPass (resource lookups need effects CanUse forbids), authoritative
# at pay time: a use whose cost bounces is cancelled instead of never starting.
cost_gate<public> := class(ability_gate):

    @editable
    Resource<public>:ability_resource

    @editable
    Amount<public>:float = 0.0

    # a cost with no one to pay it fails up front
    CanPass<override>(Context:ability_context)<decides><reads>:void =
        Context.Instigator?

    OnUseBegan<override>(Context:?ability_context, EffectComp:?ability_effect_component):void =
        Paid := if (C := Context?, A := C.Instigator?):
            Resource.Consume(A, Amount)
        else:
            false
        if (not Paid?):
            CancelUse(EffectComp)

    CancelUse<private>(EffectComp:?ability_effect_component):void =
        if (EC := EffectComp?):
            Cancelled := logic{EC.Cancel[fort_cancel_reason_invalid{}]}
            if (not Cancelled?):
                Print("gates: cost bounced but the effect refused to cancel")
        else:
            Print("gates: cost bounced and no effect component was resolved to cancel")


# --- Gate lookup on a configured ability ---

(A:gated_ability).GetCooldownGate<public>()<transacts><decides>:cooldown_gate =
    Cands := for (G : A.Gates, CG := cooldown_gate[G]) { CG }
    Cands[0]

(A:gated_ability).GetChargesGate<public>()<transacts><decides>:charges_gate =
    Cands := for (G : A.Gates, CG := charges_gate[G]) { CG }
    Cands[0]
