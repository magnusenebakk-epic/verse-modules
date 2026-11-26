using { /Fortnite.com/AI }
using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /Verse.org/Colors }
using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }

using { Damage }


# Runtime-attached marker plus data for code reading enemy info off a leaked
# or killed entity. td_npc_behavior attaches it; prefab enemies carry it.
td_enemy_info_component<public> := class<final_super>(component):
    @editable
    var LeakDamage<public>:float = 1.0

    # tower this enemy is engaging; engaged_blocker_targeter awaits it so melee kits skip range checks
    var<private> Engaged<private>:?entity = false

    EngagedChangedEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    GetEngaged<public>()<reads>:?entity = Engaged

    SetEngaged<public>(E:?entity):void =
        set Engaged = E
        EngagedChangedEvent.Signal(())


# NPC lane enemy base: walks the nearest lane, registers as a lane_traveler,
# dies/leaks like any enemy. Attacks live in AttackKit child prefabs, not here.
td_npc_behavior<public> := class(npc_behavior):

    @editable
    var MaxHealth<public>:float = 100.0

    # Engine clamps to 0.5..2 of base speed; bigger spreads need the definition's movement settings.
    @editable
    var SpeedMultiplier<public>:float = 1.0

    # Damage to the players' base when this enemy reaches the lane end.
    @editable
    var LeakDamage<public>:float = 1.0

    @editable
    var UseRunningMovement<public>:logic = true

    @editable
    var ReachRadius<public>:float = 60.0

    # Stop range for on-lane towers; keep well above LaneLookahead + tower half-width. 0.0 = never stop.
    @editable
    var BlockerStopRange<public>:float = 200.0

    # A tower blocks within this of the lane line; keep under tile-size minus tower half-width.
    @editable
    var BlockerProbeRadius<public>:float = 40.0

    # How far short of the blocker the enemy stands: tower half-footprint + capsule + gap.
    @editable
    var BlockerEngageDistance<public>:float = 100.0

    # Drift threshold before nav is interrupted and steered back; keep around a tile. 0.0 = let nav wander.
    @editable
    var MaxLaneDeviation<public>:float = 100.0

    # Lane distance ahead for the drift-recovery goal; keep under BlockerStopRange.
    @editable
    var LaneLookahead<public>:float = 100.0

    # Child prefabs spawned under the NPC at start (attack kits); empty = plain walker.
    @editable
    Kits<public>:[]concrete_subtype(entity) = array{}

    # Dev aid: log nav info and draw targets, probes and the movement trail.
    @editable
    var DebugNav<public>:logic = true

    # set while registered; OnEnd cleans up despawns that never resolve the race
    var<private> Registration<private>:?tuple(lane_component, entity) = false

    var<private> DebugId<private>:int = 0
    Drawer<private>:debug_draw = debug_draw{ Channel := td_nav_debug_channel }

    OnBegin<override>()<suspends>:void =
        if:
            Agent := GetAgent[]
            Char := Agent.GetFortCharacter[]
            CharEntity := Char.GetEntity[]
            Nav := Char.GetNavigatable[]
        then:
            if (DebugOn[DebugNav]):
                set DebugId = NextTDNavDebugId()
            Char.SetMaxHealth(MaxHealth)
            Char.SetHealth(MaxHealth)
            Nav.SetMovementSpeedMultiplier(SpeedMultiplier)
            TagKey := CharEntity.AddTag(td_enemy_tag{})
            Info := td_enemy_info_component{
                Entity := CharEntity,
                LeakDamage := Self.LeakDamage
            }
            CharEntity.AddComponents(array{Info})
            for (Kit : Kits):
                CharEntity.AddEntities(array{Kit{}})
            RunOnLane(Nav, CharEntity)

    AwaitEliminated<private>()<suspends>:void =
        if (Char := GetAgent[].GetFortCharacter[]):
            Result := Char.EliminatedEvent().Await()
        else:
            Sleep(Inf)

    # cleanup runs after the race, not in a defer in the cancelled arm; BPVM makes defer unreliable there
    RunOnLane<private>(Nav:navigatable, CharEntity:entity)<suspends>:void =
        Pos := CharEntity.GetGlobalTransform().Translation
        if:
            Found := FindNearestLane[CharEntity, Pos]
            Lane := Found(0)
            Points := Lane.GetPathPoints()
            Points.Length >= 2
        then:
            # spawning mid-lane is fine: start at the first waypoint ahead
            StartIdx := Lane.FirstWaypointAtOrBeyond(Found(1))
            Traveler := npc_lane_traveler{
                Lane := Lane,
                CharEntity := CharEntity
            }
            InitialSegment := if (StartIdx > 0) then StartIdx - 1 else 0
            Traveler.SetSegment(InitialSegment)
            # register only after the traveler can answer progress; Register signals targeters synchronously
            Lane.Register(CharEntity, Traveler)
            set Registration = option{(Lane, CharEntity)}
            if (DebugOn[DebugNav]):
                Print("td[{DebugId}] spawn {ToString(Pos)} | lane {Lane.LaneOrder} | startIdx {StartIdx} | spawnLaneD {Found(1)} | cfg stop={BlockerStopRange} probe={BlockerProbeRadius} engage={BlockerEngageDistance} maxDev={MaxLaneDeviation} lookahead={LaneLookahead} reach={ReachRadius}")
            Reached := race:
                block:
                    AwaitEliminated()
                    false
                block:
                    WalkPath(Nav, CharEntity, Lane, Points, StartIdx, Traveler)
                    true
                block:
                    TraceWalk(CharEntity, Lane, Traveler)
                    false
            # unregister before notifying: ReachedEnd subscribers must not see the enemy still on the lane
            Cleanup()
            if (Reached?):
                Lane.NotifyReachedEnd(CharEntity)

    # idempotent; also called from OnEnd for despawns that never resolve the race
    Cleanup<private>():void =
        if (R := Registration?):
            set Registration = false
            R(0).Unregister(R(1))

    OnEnd<override>():void =
        Cleanup()

    WalkPath<private>(Nav:navigatable, CharEntity:entity, Lane:lane_component, Points:[](LUF:)vector3, StartIdx:int, Traveler:npc_lane_traveler)<suspends>:void =
        var I:int = StartIdx
        loop:
            if (Target := Points[I], TargetD := Lane.WaypointDistance[I]):
                if (I > 0):
                    Traveler.SetSegment(I - 1)
                NavigateUntilArrived(Nav, CharEntity, Lane, Traveler, Target, TargetD)
            set I += 1
            if (I >= Points.Length):
                break

    # nav owns the whole leg (restarting on a timer is jerky); blocker and drift watchers interrupt it
    NavigateUntilArrived<private>(Nav:navigatable, CharEntity:entity, Lane:lane_component, Traveler:npc_lane_traveler, Target:(LUF:)vector3, TargetD:float)<suspends>:void =
        MoveType := if (UseRunningMovement?) then movement_types.Running else movement_types.Walking
        # one print per waypoint, not per 0.5s retry
        var ReportedStuck:logic = false
        loop:
            # blocked: walk up to the tower and stand, don't ask nav for a detour
            if (Blocker := FindBlockerAhead[CharEntity, Lane, Traveler]):
                EngageBlocker(Nav, CharEntity, Lane, Traveler, Blocker, MoveType)
            else:
                # drifted: aim at a lane point ahead until back on the line
                Recovering := if (OffLane[CharEntity, Lane]) then true else false
                MyD := Traveler.GetLaneProgress()
                var Clamped:logic = false
                # (target, its lane distance); the watcher needs the leg end to notice a mid-leg tower
                Leg := if:
                    Recovering?
                    RD := Min(MyD + LaneLookahead, TargetD)
                    P := Lane.PointAtDistance[RD]
                then:
                    (P, RD)
                else:
                    # never target beyond an on-lane tower: nav detours around its carve and cuts off the lane; clamp the leg to the stand point
                    if:
                        TowerD := NextTowerOnLaneD[CharEntity, Lane, MyD]
                        StandD := TowerD - BlockerEngageDistance
                        StandD < TargetD
                        ClampD := Max(StandD, MyD)
                        P := Lane.PointAtDistance[ClampD]
                    then:
                        set Clamped = true
                        (P, ClampD)
                    else:
                        (Target, TargetD)
                LegTarget := Leg(0)
                LegEndD := Leg(1)
                # recovery/clamp goals may sit inside a carve; stopping at its edge is right, not a Blocked failure
                AllowPartial := if (Recovering? or Clamped?) then true else false
                if (DebugOn[DebugNav]):
                    Kind := if (Recovering?) then "recover" else if (Clamped?) then "clamp" else "waypoint"
                    Pos := CharEntity.GetGlobalTransform().Translation
                    Print("td[{DebugId}] nav {Kind} -> {ToString(LegTarget)} | pos {ToString(Pos)} | laneD {MyD} | dev {LaneDeviation(CharEntity, Lane)}")
                    LegColor := if (Recovering?) then NamedColors.Yellow else if (Clamped?) then NamedColors.Purple else NamedColors.Green
                    Drawer.DrawSphere(LegTarget, ?Radius := 20.0, ?Color := LegColor, ?DrawDurationPolicy := debug_draw_duration_policy.FiniteDuration, ?Duration := 5.0)
                    Drawer.DrawArrow(Pos, LegTarget, ?Color := LegColor, ?DrawDurationPolicy := debug_draw_duration_policy.FiniteDuration, ?Duration := 5.0)
                var BlockerAppeared:logic = false
                var Drifted:logic = false
                Result := race:
                    block:
                        Nav.NavigateTo(
                            MakeNavigationTarget(LegTarget),
                            ?MovementType := MoveType,
                            ?ReachRadius := ReachRadius,
                            ?AllowPartialPath := AllowPartial
                        )
                    block:
                        AwaitBlockerAhead(CharEntity, Lane, Traveler, LegEndD)
                        set BlockerAppeared = true
                        navigation_result.Interrupted
                    block:
                        AwaitOffLane(CharEntity, Lane, Recovering)
                        set Drifted = true
                        navigation_result.Interrupted
                if (DebugOn[DebugNav]):
                    Why := if (BlockerAppeared?) then "blocker" else if (Drifted?) then "drift" else NavResultName(Result)
                    Print("td[{DebugId}] leg end: {Why} | pos {ToString(CharEntity.GetGlobalTransform().Translation)} | laneD {Traveler.GetLaneProgress()} | dev {LaneDeviation(CharEntity, Lane)}")
                if (BlockerAppeared? or Drifted?):
                    Nav.StopNavigation()
                else if ((Result = navigation_result.Reached) or (AllowPartial? and (Result = navigation_result.PartiallyReached))):
                    if (not Recovering? and not Clamped?):
                        return
                    # recovery/clamp leg done: loop re-evaluates; brief pause so a zero-length clamp leg can't hot-spin
                    Nav.Wait(?Duration := 0.25)
                else:
                    if (not ReportedStuck?):
                        set ReportedStuck = true
                        if (Result = navigation_result.Blocked):
                            Print("td nav: Blocked toward {ToString(LegTarget)}, retrying")
                        else if (Result = navigation_result.PartiallyReached):
                            Print("td nav: PartiallyReached toward {ToString(LegTarget)}, retrying")
                        else:
                            Print("td nav: Interrupted toward {ToString(LegTarget)}, retrying")
                    # blocked/interrupted: brief pause then retry (tower despawn or path rebake usually clears it)
                    Nav.Wait(?Duration := 0.5)

    OffLane<private>(CharEntity:entity, Lane:lane_component)<transacts><decides>:void =
        MaxLaneDeviation > 0.0
        LaneDeviation(CharEntity, Lane) > MaxLaneDeviation

    # horizontal-only: capsule center vs floating waypoints would read a constant vertical offset as drift; -1.0 = no projection
    LaneDeviation<private>(CharEntity:entity, Lane:lane_component)<transacts>:float =
        Pos := CharEntity.GetGlobalTransform().Translation
        if:
            Proj := Lane.ProjectOntoPath[Pos]
            LanePoint := Lane.PointAtDistance[Proj(0)]
        then:
            Delta := Pos - LanePoint
            Sqrt(Delta.Forward * Delta.Forward + Delta.Left * Delta.Left)
        else:
            -1.0

    # resolves once off lane; sleeps forever while recovering or when drift correction is off
    AwaitOffLane<private>(CharEntity:entity, Lane:lane_component, Recovering:logic)<suspends>:void =
        if (Recovering? or MaxLaneDeviation <= 0.0):
            Sleep(Inf)
        loop:
            if (OffLane[CharEntity, Lane]):
                return
            Sleep(0.25)

    # walk up the lane to just short of the blocker's carve, stand until the front blocker changes
    EngageBlocker<private>(Nav:navigatable, CharEntity:entity, Lane:lane_component, Traveler:npc_lane_traveler, Blocker:entity, MoveType:movement_type)<suspends>:void =
        # hand the target to the attack kit for the whole engagement, walk-up included
        if (Info := CharEntity.GetComponent[td_enemy_info_component]):
            Info.SetEngaged(option{Blocker})
        if (DebugOn[DebugNav]):
            TowerPos := Blocker.GetGlobalTransform().Translation
            if (TProj := Lane.ProjectOntoPath[TowerPos]):
                Print("td[{DebugId}] engage tower {ToString(TowerPos)} | towerLaneD {TProj(0)} | towerOffLane {TProj(1)} | myLaneD {Traveler.GetLaneProgress()}")
            else:
                Print("td[{DebugId}] engage tower {ToString(TowerPos)} (no lane projection!)")
            Drawer.DrawSphere(TowerPos, ?Radius := 30.0, ?Color := NamedColors.Red, ?DrawDurationPolicy := debug_draw_duration_policy.FiniteDuration, ?Duration := 5.0)
        if:
            Proj := Lane.ProjectOntoPath[Blocker.GetGlobalTransform().Translation]
            StandD := Proj(0) - BlockerEngageDistance
            StandD > Traveler.GetLaneProgress()
            StandPoint := Lane.PointAtDistance[StandD]
        then:
            if (DebugOn[DebugNav]):
                Print("td[{DebugId}] stand -> {ToString(StandPoint)} (standD {StandD})")
                Drawer.DrawSphere(StandPoint, ?Radius := 20.0, ?Color := NamedColors.Blue, ?DrawDurationPolicy := debug_draw_duration_policy.FiniteDuration, ?Duration := 5.0)
            # partial path: a big footprint may swallow the stand point; nav then stops at the carve edge
            Nav.NavigateTo(
                MakeNavigationTarget(StandPoint),
                ?MovementType := MoveType,
                ?ReachRadius := ReachRadius,
                ?AllowPartialPath := true
            )
        else:
            # already at (or past) the stand point
            if (DebugOn[DebugNav]):
                Print("td[{DebugId}] stand in place (at/past stand point)")
            Nav.StopNavigation()
        AwaitBlockerChanged(CharEntity, Lane, Traveler, Blocker)
        # engagement over; a re-engage publishes the new blocker itself
        if (Info := CharEntity.GetComponent[td_enemy_info_component]):
            Info.SetEngaged(false)

    # resolves on a probed blocker ahead, or when the leg crosses a tower it didn't cross when planned
    AwaitBlockerAhead<private>(CharEntity:entity, Lane:lane_component, Traveler:npc_lane_traveler, LegEndD:float)<suspends>:void =
        if (BlockerStopRange <= 0.0):
            Sleep(Inf)
        loop:
            if (DebugOn[DebugNav]):
                DrawProbeChain(Lane, Traveler)
            if (B := FindBlockerAhead[CharEntity, Lane, Traveler]):
                if (DebugOn[DebugNav]):
                    Print("td[{DebugId}] blocker detected at {ToString(B.GetGlobalTransform().Translation)}")
                return
            # epsilon keeps a clamped leg from re-triggering on its own tower
            if:
                TowerD := NextTowerOnLaneD[CharEntity, Lane, Traveler.GetLaneProgress()]
                TowerD - BlockerEngageDistance < LegEndD - 1.0
            then:
                if (DebugOn[DebugNav]):
                    Print("td[{DebugId}] leg crosses new tower (towerD {TowerD}), re-leg")
                return
            Sleep(0.25)

    # Visualizes where FindBlockerAhead is looking this instant.
    DrawProbeChain<private>(Lane:lane_component, Traveler:npc_lane_traveler):void =
        if (BlockerProbeRadius > 0.0, Steps := Floor[BlockerStopRange / BlockerProbeRadius] + 1):
            D := Traveler.GetLaneProgress()
            for (K := 0..Steps, P := Lane.PointAtDistance[D + (1.0 * K) * BlockerProbeRadius]):
                Drawer.DrawSphere(P, ?Radius := BlockerProbeRadius, ?NumSegments := 8, ?Color := NamedColors.Orange, ?DrawDurationPolicy := debug_draw_duration_policy.FiniteDuration, ?Duration := 0.3)

    # 0.5s movement trail; quiet while standing so engaged enemies don't flood the log
    TraceWalk<private>(CharEntity:entity, Lane:lane_component, Traveler:npc_lane_traveler)<suspends>:void =
        if (not DebugOn[DebugNav]):
            Sleep(Inf)
        var LastPos:(LUF:)vector3 = (LUF:)vector3{Forward := Inf, Left := Inf, Up := Inf}
        loop:
            Pos := CharEntity.GetGlobalTransform().Translation
            if (Distance(Pos, LastPos) > 1.0):
                set LastPos = Pos
                Print("td[{DebugId}] trace {ToString(Pos)} | laneD {Traveler.GetLaneProgress()} | dev {LaneDeviation(CharEntity, Lane)}")
                Drawer.DrawPoint(Pos, ?Color := NamedColors.Cyan, ?Thickness := 8.0, ?DrawDurationPolicy := debug_draw_duration_policy.FiniteDuration, ?Duration := 20.0)
            Sleep(0.5)

    NavResultName<private>(R:navigation_result)<transacts>:string =
        if (R = navigation_result.Reached) then "Reached"
        else if (R = navigation_result.PartiallyReached) then "PartiallyReached"
        else if (R = navigation_result.Blocked) then "Blocked"
        else "Interrupted"

    # resolves on any front-blocker change; timer recheck on purpose, no death event covers relocation
    AwaitBlockerChanged<private>(CharEntity:entity, Lane:lane_component, Traveler:npc_lane_traveler, Engaged:entity)<suspends>:void =
        loop:
            Sleep(0.5)
            if (not (FindBlockerAhead[CharEntity, Lane, Traveler] = Engaged)):
                return

    # nearest killable on-lane tower ahead of D at any range; leg targets must respect blockers a lane away
    NextTowerOnLaneD<private>(CharEntity:entity, Lane:lane_component, D:float)<transacts><decides>:float =
        BlockerStopRange > 0.0
        Sim := CharEntity.GetSimulationEntity[]
        Ahead := for:
            T : Sim.FindDescendantEntitiesWithTag(tower_tag)
            MayEngage[CharEntity, T]
            T.GetComponent[entity_health_component]
            Proj := Lane.ProjectOntoPath[T.GetGlobalTransform().Translation]
            Proj(0) > D
            Proj(1) <= BlockerProbeRadius + 50.0
        do:
            Proj(0)
        var Best:?float = false
        for (TD : Ahead):
            if (B := Best?):
                if (TD < B):
                    set Best = option{TD}
            else:
                set Best = option{TD}
        Best?

    # probes anchored to the lane, not the enemy heading; nav may already be pulling the enemy sideways
    FindBlockerAhead<private>(CharEntity:entity, Lane:lane_component, Traveler:npc_lane_traveler)<transacts><decides>:entity =
        BlockerStopRange > 0.0
        BlockerProbeRadius > 0.0
        D := Traveler.GetLaneProgress()
        Steps := Floor[BlockerStopRange / BlockerProbeRadius] + 1
        Blockers := for:
            K := 0..Steps
            P := Lane.PointAtDistance[D + (1.0 * K) * BlockerProbeRadius]
            Tower := TowerAt[CharEntity, P]
        do:
            Tower
        Blockers[0]

    # Killable tower whose collision overlaps a probe sphere at P.
    TowerAt<private>(CharEntity:entity, P:(LUF:)vector3)<transacts><decides>:entity =
        Probe := collision_sphere{
            Radius := BlockerProbeRadius,
            CollisionProfile := CollisionProfiles.DynamicOverlapAll
        }
        CharXform := CharEntity.GetGlobalTransform()
        Hits := for:
            H : CharEntity.FindOverlapHits(
                (LUF:)transform{Translation := P, Rotation := CharXform.Rotation, Scale := CharXform.Scale},
                Probe)
            Tower := TowerRootOf[H.TargetComponent.Entity]
            MayEngage[CharEntity, Tower]
            Tower.GetComponent[entity_health_component]
        do:
            Tower
        Hits[0]

    # The overlap may hit a mesh child; the tag is on the tower root.
    TowerRootOf<private>(E:entity)<transacts><decides>:entity =
        Chain := array{E} + (for (A : E.FindAncestorEntities(entity)) { A })
        Found := for (C : Chain, C.ContainsTag[tower_tag]) { C }
        Found[0]
