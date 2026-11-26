using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }

using { Abilities }


# Shared fire loop for towers and attacking NPC enemies: acquire a target,
# fire the sibling gate driver's first ability, block until it can fire again.
auto_fire_component<public> := class<final_super>(component):

    @editable
    var Targeter<public>:?targeter = false

    # Dev aid: log the whole fire cycle; shares the td debug id counter (af[N]).
    @editable
    var DebugFire<public>:logic = true

    var<private> DebugId<private>:int = 0

    OnSimulate<override>()<suspends>:void =
        if (DebugOn[DebugFire]):
            set DebugId = NextTDNavDebugId()
        if (Driver := Entity.GetComponent[ability_hub_component]):
            if (A := Driver.GetWiredAbilities()[0]):
                if (DebugOn[DebugFire]):
                    HasTargeter := if (Targeter?) then "yes" else "no"
                    Print("af[{DebugId}] ready at {ToString(Entity.GetGlobalTransform().Translation)} | targeter {HasTargeter}")
                FireCycle(Driver, A)
            else if (DebugOn[DebugFire]):
                Print("af[{DebugId}] IDLE: driver has 0 gated abilities at {ToString(Entity.GetGlobalTransform().Translation)}")
        else if (DebugOn[DebugFire]):
            Print("af[{DebugId}] IDLE: no ability_hub_component sibling at {ToString(Entity.GetGlobalTransform().Translation)}")

    FireCycle<private>(Driver:ability_hub_component, A:gated_ability)<suspends>:void =
        loop:
            TargetOpt := AcquireTarget()
            if (DebugOn[DebugFire]):
                if (T := TargetOpt?):
                    Print("af[{DebugId}] target at {ToString(T.GetGlobalTransform().Translation)}, firing")
                else:
                    Print("af[{DebugId}] firing targetless")
            R := Driver.Fire(A, ?Instigator := InstigatorForUse(), ?Target := TargetOpt)
            if (DebugOn[DebugFire]):
                if (R?):
                    Print("af[{DebugId}] fired ok")
                else:
                    Print("af[{DebugId}] fire REJECTED")
            if (R?):
                # let the holder's visual reactors sync to the shot and its reload
                Entity.SendDown(fired_event{Cooldown := CooldownOf(A)})
            AwaitReady(A)

    AcquireTarget<private>()<suspends>:?entity =
        if (T := Targeter?):
            Target := T.AwaitTarget(Entity)
            option{Target}
        else:
            false

    # attribution: the placing agent (towers), else the character this sits under (NPC kits)
    ActivatorOpt<private>()<transacts>:?agent =
        if (S := Entity.GetSource[]):
            option{S}
        else if (A := OwningAgent[]):
            option{A}
        else:
            false

    # this build: player-instigated manual Use round-trips GAS and spawns a rogue pawn-parented
    # effect (UE-393979); bots run synchronously and agentless is fine. Kill credit still flows
    # via source_component (GetUseAttribution). Retire the filter once CL 57513011 ships.
    InstigatorForUse<private>()<transacts>:?agent =
        if (Acting := ActivatorOpt()?, not player[Acting]):
            option{Acting}
        else:
            false

    OwningAgent<private>()<transacts><decides>:agent =
        Chars := for:
            E : Entity.FindAncestorEntities(entity)
            Comp : E.GetComponents()
            FC := fort_character[Comp]
        do:
            FC
        Chars[0].GetAgent[]

    # the fired ability's cooldown duration; 0.0 when it has none
    CooldownOf<private>(A:gated_ability)<transacts>:float =
        A.GetCooldownGate[].Duration or 0.0

    # block on whichever gate is closed; the Sleep(0.0) backstop keeps a no-cooldown loop yielding
    AwaitReady<private>(A:gated_ability)<suspends>:void =
        if (CG := A.GetCooldownGate[], CG.IsOnCooldown[]):
            if (DebugOn[DebugFire]):
                Print("af[{DebugId}] waiting cooldown")
            CG.CooldownEndedEvent.Await()
        else if (ChG := A.GetChargesGate[], not ChG.HasCharge[]):
            if (DebugOn[DebugFire]):
                Print("af[{DebugId}] waiting charge")
            ChG.ChargeChangedEvent.Await()
        else:
            Sleep(0.0)
