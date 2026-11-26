using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/Abilities }
using { /Fortnite.com/Abilities }


# The ability hub for a holder entity: discovers which gated abilities live here
# (subclasses define the source), wires gate consumption to the official Begin/EndUse
# events, runs gate upkeep, rebroadcasts uses to sibling reaction components, and
# exposes Fire for callers the native item/input flow does not drive.
ability_hub_component<public> := class<abstract><final_super>(component):

    # prototype diagnostics for the official-API unknowns; silence once answered
    @editable
    var DebugUse<public>:logic = true

    # > 0.0: fire the first discovered ability on this interval, for testing without input
    @editable
    var DebugAutoFireInterval<public>:float = 0.0

    # dev: skip our CanUse pre-check in Fire; native Use enforces CanUse anyway (verified)
    @editable
    var DebugSkipCanUseCheck<public>:logic = false

    # manual-path effects never end on their own (observed: ActiveEffects grows unbounded);
    # when set, the hub ends each effect this many seconds after it begins
    @editable
    var ManualEffectLifetime<public>:?float = false

    # signalled after gates commit; payload is the effect entity (resolve with GetUseTarget etc.)
    # UseEndedEvent can fire twice per effect on early cancels (engine bug) - subscribers must be idempotent
    UseBeganEvent<public>:Concurrency.subscribable_event(entity) =
        Concurrency.subscribable_event(entity){}

    UseEndedEvent<public>:Concurrency.subscribable_event(entity) =
        Concurrency.subscribable_event(entity){}

    var<private> Wired<private>:[]gated_ability = array{}
    var<private> Subs<private>:[]cancelable = array{}
    ComponentCancel<private>:event() = event(){}

    # where this holder's abilities come from
    DiscoverAbilities<protected>()<transacts>:[]gated_ability

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set Wired = DiscoverAbilities()
        if (DebugUse?):
            Print("gates: hub wired {Wired.Length} gated abilities at {ToString(Entity.GetGlobalTransform().Translation)}")
        for (A : Wired):
            W := gate_use_watcher{Ability := A, Debug := DebugUse, Holder := Entity, UseBegan := UseBeganEvent, UseEnded := UseEndedEvent}
            set Subs += array{A.BeginUseEvent.Subscribe(W.OnBegan)}
            set Subs += array{A.EndUseEvent.Subscribe(W.OnEnded)}
            for (G : A.Gates):
                spawn { RunMaintain(G) }

    OnSimulate<override>()<suspends>:void =
        if (DebugAutoFireInterval > 0.0):
            loop:
                Sleep(DebugAutoFireInterval)
                if (A := Wired[0]):
                    R := Fire(A)
                    if (DebugUse?):
                        Outcome := if (R?) then "effect spawned" else "no effect"
                        Print("gates: auto-fire -> {Outcome} | active effects {A.ActiveEffects.Length}")

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (C : Subs):
            C.Cancel()
        set Subs = array{}
        ComponentCancel.Signal()

    GetWiredAbilities<public>()<reads>:[]gated_ability = Wired

    # manual use path for holders the native item/input flow does not drive
    Fire<public>(A:gated_ability, ?Instigator:?agent = false, ?Target:?entity = false):?fort_template_ability_effect =
        Ctx := A.MakeContext()
        set Ctx.Instigator = Instigator
        set Ctx.Participants = array{Entity}
        if (T := Target?):
            set Ctx.Targets = array{T}
        Result:?fort_template_ability_effect = if (DebugSkipCanUseCheck? or A.CanUse[Entity, Ctx]):
            A.Use(Entity, Ctx)
        else:
            if (DebugUse?):
                Print("gates: fire blocked by CanUse")
            false
        if (E := Result?, L := ManualEffectLifetime?):
            spawn { EndEffectAfter(A, E, L) }
        Result

    # Idempotent manual ender: Cancel fires the EndUse hooks but does not despawn, removal alone
    # ends nothing this build - so do both. Cancel is gated on ActiveEffects membership because a
    # use the native flow already ended (bot instigators) would double-fire EndUseEvent;
    # RemoveFromParent on an already-removed entity is a silent no-op, so it runs unconditionally.
    EndEffectAfter<private>(A:gated_ability, Effect:fort_template_ability_effect, Lifetime:float)<suspends>:void =
        race:
            ComponentCancel.Await()
            block:
                Sleep(Lifetime)
                StillActive := for (E : A.ActiveEffects, E = Effect) { E }
                if (StillActive.Length > 0):
                    _Cancelled := logic{Effect.AbilityComponent.Cancel[ability_ended{}]}
                    if (DebugUse?):
                        Print("gates: ending effect after {Lifetime}s")
                else if (DebugUse?):
                    Print("gates: effect already ended, skipping cancel")
                Effect.RemoveFromParent()

    RunMaintain<private>(G:ability_gate)<suspends>:void =
        race:
            ComponentCancel.Await()
            G.Maintain()


# Items: abilities come from the sibling fort_item_ability_component's lists.
item_ability_hub_component<public> := class(ability_hub_component):

    DiscoverAbilities<override>()<transacts>:[]gated_ability =
        if (IAC := Entity.GetComponent[fort_item_ability_component]):
            Listed : []?ability(ability_context, ability_effect) = IAC.ItemAbilities + IAC.ItemEquippedAbilities
            for (MaybeA : Listed, A := MaybeA?, G := gated_ability[A]) { G }
        else:
            Print("gates: item_ability_hub_component found no fort_item_ability_component sibling")
            array{}


# Towers and other item-less holders: abilities are listed directly on the component.
manual_ability_hub_component<public> := class(ability_hub_component):

    @editable
    var ManualAbilities<public>:[]gated_ability = array{}

    DiscoverAbilities<override>()<transacts>:[]gated_ability = ManualAbilities


# Closure holder binding an ability's gates and actions to the engine event callbacks.
gate_use_watcher := class:
    Ability:gated_ability
    Debug:logic = false
    Holder:entity
    UseBegan:Concurrency.subscribable_event(entity)
    UseEnded:Concurrency.subscribable_event(entity)

    OnBegan(EffectE:entity):void =
        Ctx := ResolveContext(EffectE)
        EC := ResolveEffectComp(EffectE)
        if (Debug?):
            HasEC := if (EC?) then "yes" else "no"
            HasCtx := if (Ctx?) then "yes" else "no"
            HasInstigator := if (C := Ctx?, C.Instigator?) then "yes" else "no"
            Print("gates: BeginUse at {GetSimulationElapsedTime()} | effect comp {HasEC} | context {HasCtx} | instigator {HasInstigator} | payload entity at {ToString(EffectE.GetGlobalTransform().Translation)}")
        for (G : Ability.Gates):
            G.OnUseBegan(Ctx, EC)
        for (Act : Ability.Actions):
            Act.Execute(EffectE, Holder)
        UseBegan.Signal(EffectE)

    OnEnded(EffectE:entity):void =
        Ctx := ResolveContext(EffectE)
        if (Debug?):
            Print("gates: EndUse at {GetSimulationElapsedTime()}")
        for (G : Ability.Gates):
            G.OnUseEnded(Ctx)
        UseEnded.Signal(EffectE)

    ResolveEffectComp(EffectE:entity):?ability_effect_component =
        if (EC := EffectE.GetComponent[ability_effect_component]):
            option{EC}
        else:
            false

    ResolveContext(EffectE:entity):?ability_context =
        if (EC := EffectE.GetComponent[ability_effect_component], C := EC.Context?):
            option{C}
        else:
            false


# --- Use payload helpers for reaction components ---

(E:entity).GetAbilityContext<public>()<transacts><decides>:ability_context =
    E.GetComponent[ability_effect_component].Context?

(E:entity).GetUseTarget<public>()<transacts><decides>:entity =
    E.GetAbilityContext[].Targets[0]

(E:entity).GetUseInstigator<public>()<transacts><decides>:agent =
    E.GetAbilityContext[].Instigator?

# instigator when the use carried one, else the holder's source_component chain (towers)
(EffectE:entity).GetUseAttribution<public>(Holder:entity)<transacts><decides>:agent =
    EffectE.GetUseInstigator[] or Holder.GetSource[]
