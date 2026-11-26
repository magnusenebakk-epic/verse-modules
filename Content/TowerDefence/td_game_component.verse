using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }

using { Damage }


td_game_state<public> := enum:
    Idle
    BuildPhase
    WaveActive
    Victory
    Defeat

# Display name for logs and UI; enum values don't interpolate.
StateName<public>(S:td_game_state):string =
    case (S):
        td_game_state.Idle => "Idle"
        td_game_state.BuildPhase => "BuildPhase"
        td_game_state.WaveActive => "WaveActive"
        td_game_state.Victory => "Victory"
        td_game_state.Defeat => "Defeat"


td_kill_event<public> := class:
    Killer<public>:?agent
    EnemyEntity<public>:entity
    WaveIndex<public>:int


td_leak_event<public> := class:
    Lane<public>:lane_component
    EnemyEntity<public>:entity
    (td_leak_event:)Damage<public>:float


# Match orchestrator: Start() begins, each wave waits for RequestNextWave().
# Board is this entity's subtree (two games per scene stay separate); runtime spawns join via Claim.
td_game_component<public> := class<final_super>(component):

    # Enemy roster. spawn_instruction.EnemyKind indexes into this.
    @editable
    EnemySources<public>:[]enemy_source = array{}

    @editable
    Provider<public>:wave_provider = data_wave_provider{}

    # Defeat only when every base is destroyed, not just the first.
    @editable
    var RequireAllBasesDestroyed<public>:logic = false

    # Spawn height above the lane's first waypoint.
    @editable
    var SpawnUpOffset<public>:float = 50.0

    # Leak damage for enemies missing td_enemy_info_component.
    @editable
    var DefaultLeakDamage<public>:float = 1.0

    StateChangedEvent<public>:Concurrency.subscribable_event(td_game_state) =
        Concurrency.subscribable_event(td_game_state){}
    GameStartedEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}
    WaveStartedEvent<public>:Concurrency.subscribable_event(int) =
        Concurrency.subscribable_event(int){}
    WaveClearedEvent<public>:Concurrency.subscribable_event(int) =
        Concurrency.subscribable_event(int){}
    EnemyKilledEvent<public>:Concurrency.subscribable_event(td_kill_event) =
        Concurrency.subscribable_event(td_kill_event){}
    EnemyLeakedEvent<public>:Concurrency.subscribable_event(td_leak_event) =
        Concurrency.subscribable_event(td_leak_event){}
    VictoryEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}
    DefeatEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}
    GameOverEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    var<private> State<private>:td_game_state = td_game_state.Idle
    var<private> WaveIndex<private>:int = 0
    var<private> Lanes<private>:[]lane_component = array{}
    var<private> Bases<private>:[]td_base_component = array{}
    var<private> Live<private>:[]spawned_enemy = array{}
    var<private> Pending<private>:int = 0
    var<private> NextLaneRR<private>:int = 0
    var<private> StartPending<private>:logic = false
    var<private> NextWavePending<private>:logic = false
    StartRequested<private>:event() = event(){}
    NextWaveRequested<private>:event() = event(){}
    DefeatTriggered<private>:event() = event(){}
    PendingChanged<private>:event() = event(){}
    var<private> Subs<private>:[]Concurrency.subscription_task(entity) = array{}
    var<private> BaseSubs<private>:[]Concurrency.subscription_task(?agent) = array{}

    GetState<public>()<reads>:td_game_state = State
    GetWaveIndex<public>()<reads>:int = WaveIndex
    GetLiveEnemyCount<public>()<reads>:int = Pending
    GetLanes<public>()<reads>:[]lane_component = Lanes

    # Begin the match. Ignored if already started; the game never starts itself.
    Start<public>():logic =
        if (StartPending?):
            Print("TD: Start() ignored - already started")
            false
        else:
            Print("TD: Start() accepted")
            set StartPending = true
            StartRequested.Signal()
            true

    # Latched like Start: a call from a StateChangedEvent(BuildPhase) callback lands before WaveLoop's Await.
    RequestNextWave<public>():logic =
        if (State = td_game_state.BuildPhase):
            Print("TD: next wave requested")
            set NextWavePending = true
            NextWaveRequested.Signal()
            true
        else:
            Print("TD: next wave rejected (state {StateName(State)})")
            false

    # Runtime spawns live outside the game subtree, so membership is stamped via td_game_ref_component.
    Claim<public>(E:entity):void =
        if (R := E.GetComponent[td_game_ref_component]):
            set R.Game = option{Self}
        else:
            E.AddComponents(array{td_game_ref_component{
                Entity := E,
                Game := option{Self}
            }})

    OnSimulate<override>()<suspends>:void =
        # Start() may have landed during another component's setup, before anyone listened
        if (not StartPending?):
            Print("TD: game ready - awaiting Start()")
            StartRequested.Await()
        RunGame()

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : Subs):
            S.Cancel()
        set Subs = array{}
        for (S : BaseSubs):
            S.Cancel()
        set BaseSubs = array{}

    RunGame<private>()<suspends>:void =
        InitLanesAndBases()
        Print("TD: game starting - {Lanes.Length} lanes, {Bases.Length} bases")
        if (Lanes.Length = 0):
            Print("TD: WARNING - no lanes found; every spawn will fail")
        GameStartedEvent.Signal(())
        Won := race:
            block:
                WaveLoop()
                true
            block:
                DefeatTriggered.Await()
                false
        if (Won?):
            Print("TD: VICTORY after {WaveIndex} waves")
            SetState(td_game_state.Victory)
            VictoryEvent.Signal(())
        else:
            # suppress kill credit so defeat cleanup gives no reward
            Print("TD: DEFEAT on wave {WaveIndex} - removing {Live.Length} live enemies")
            for (E : Live):
                E.SuppressKillCredit()
                E.Remove()
            SetState(td_game_state.Defeat)
            DefeatEvent.Signal(())
        Print("TD: game over")
        GameOverEvent.Signal(())

    WaveLoop<private>()<suspends>:void =
        loop:
            SetState(td_game_state.BuildPhase)
            if (not NextWavePending?):
                NextWaveRequested.Await()
            set NextWavePending = false
            MaybePlan := option{Provider.GetPlan[WaveIndex, EnemySources.Length]}
            if (Plan := MaybePlan?):
                Print("TD: wave {WaveIndex} starting ({Plan.Instructions.Length} streams)")
                SetState(td_game_state.WaveActive)
                WaveStartedEvent.Signal(WaveIndex)
                RunStreams(Plan.Instructions)
                Print("TD: wave {WaveIndex} spawns done - awaiting clear ({Pending} pending)")
                AwaitWaveCleared()
                Print("TD: wave {WaveIndex} cleared")
                WaveClearedEvent.Signal(WaveIndex)
                set WaveIndex += 1
                if (not HasNextWave[]):
                    Print("TD: provider has no wave {WaveIndex} - ending in victory")
                    break
            else:
                Print("TD: no plan for wave {WaveIndex} - ending in victory")
                break

    HasNextWave<private>()<transacts><decides>:void =
        Provider.HasWave[WaveIndex, EnemySources.Length]

    # streams run concurrently; Verse has no iterative sync, so this recurses
    RunStreams<private>(Instructions:[]spawn_instruction)<suspends>:void =
        if (Instructions.Length = 1, I := Instructions[0]):
            RunStream(I)
        else if (Head := Instructions[0], Tail := Instructions.Slice[1]):
            sync:
                RunStream(Head)
                RunStreams(Tail)

    RunStream<private>(I:spawn_instruction)<suspends>:void =
        Print("TD: stream: {I.Count}x kind {I.EnemyKind}, lane {I.LaneIndex}, every {I.Interval}s")
        if (I.StartDelay > 0.0):
            Sleep(I.StartDelay)
        var Spawned:int = 0
        loop:
            if (Spawned >= I.Count):
                break
            SpawnOne(I)
            set Spawned += 1
            if (Spawned < I.Count):
                Sleep(I.Interval)

    SpawnOne<private>(I:spawn_instruction)<suspends>:void =
        MaybeLane := PickLane(I.LaneIndex)
        if:
            Lane := MaybeLane?
            Source := EnemySources[I.EnemyKind]
            StartPos := Lane.GetPathPoints()[0]
        then:
            Pos := (LUF:)vector3{
                Forward := StartPos.Forward,
                Left := StartPos.Left,
                Up := StartPos.Up + SpawnUpOffset
            }
            MaybeEnemy := Source.Spawn(Lane, Pos)
            if (Enemy := MaybeEnemy?):
                # stamp membership so enemy attack kits only search this game's towers
                Claim(Enemy.EnemyEntity)
                set Live += array{Enemy}
                set Pending += 1
                Print("TD: spawned enemy (kind {I.EnemyKind}, {Pending} pending)")
                spawn { WatchEnemy(Enemy) }
            else:
                Print("TD: spawn failed (kind {I.EnemyKind}; spawner limit?)")
        else:
            # bad EnemyKind/LaneIndex in wave data, or a pathless lane
            Print("TD: skipped spawn (kind {I.EnemyKind}, lane {I.LaneIndex}) - check wave data")

    PickLane<private>(LaneIndex:int)<transacts>:?lane_component =
        if (LaneIndex >= 0):
            option{Lanes[LaneIndex]}
        else if (Lane := Lanes[Mod[NextLaneRR, Lanes.Length]]):
            set NextLaneRR += 1
            option{Lane}
        else:
            false

    # one watcher per enemy; every death path decrements Pending here
    WatchEnemy<private>(Enemy:spawned_enemy)<suspends>:void =
        if (not Enemy.HasDied[]):
            Enemy.DiedEvent.Await()
        set Live = for (X : Live, not (X = Enemy)) { X }
        set Pending -= 1
        if (Enemy.HasKillCredit[]):
            Print("TD: enemy killed ({Pending} pending)")
            EnemyKilledEvent.Signal(td_kill_event{
                Killer := Enemy.GetKiller(),
                EnemyEntity := Enemy.EnemyEntity,
                WaveIndex := WaveIndex
            })
        else:
            Print("TD: enemy removed without credit ({Pending} pending)")
        PendingChanged.Signal()

    AwaitWaveCleared<private>()<suspends>:void =
        loop:
            if (Pending <= 0):
                break
            PendingChanged.Await()

    # base is looked up per leak so a destroyed base stops taking damage; kill credit suppressed so leaks pay nothing
    HandleLeak<public>(Lane:lane_component, E:entity):void =
        if (Enemy := first (X : Live, X.EnemyEntity = E) { X }):
            Leak := if (Info := E.GetComponent[td_enemy_info_component]):
                Info.LeakDamage
            else:
                DefaultLeakDamage
            if (B := BaseForLane(Lane)?):
                Print("TD: leak - {Leak} damage to covering base")
                B.ApplyLeak(Leak)
            else:
                Print("TD: leak - no living base covers this lane ({Leak} damage lost)")
            EnemyLeakedEvent.Signal(td_leak_event{
                Lane := Lane,
                EnemyEntity := E,
                Damage := Leak
            })
            Enemy.SuppressKillCredit()
            Enemy.Remove()
            CheckDefeat()

    OnBaseDestroyed<private>(Killer:?agent):void =
        Print("TD: base destroyed")
        CheckDefeat()

    CheckDefeat<private>():void =
        if (Bases.Length = 0). return
        Dead := (for (B : Bases, not B.IsAlive[]) { B }).Length
        Lost := if (RequireAllBasesDestroyed?):
            logic{Dead >= Bases.Length}
        else:
            logic{Dead > 0}
        if (Lost?):
            Print("TD: defeat triggered ({Dead}/{Bases.Length} bases down)")
            DefeatTriggered.Signal()

    # subtree first so two games in one scene stay separate; lane-less games fall back to the whole sim
    InitLanesAndBases<private>():void =
        Own := for (L : Entity.FindDescendantComponents(lane_component)) { L }
        if (Own.Length > 0):
            set Lanes = SortLanes(Own)
            set Bases = for (B : Entity.FindDescendantComponents(td_base_component)) { B }
        else if (Sim := Entity.GetSimulationEntity[]):
            Found := for (L : Sim.FindDescendantComponents(lane_component)) { L }
            set Lanes = SortLanes(Found)
            set Bases = for (B : Sim.FindDescendantComponents(td_base_component)) { B }
        for (L : Lanes):
            Listener := lane_leak_listener{ Game := Self, Lane := L }
            set Subs += array{L.EnemyReachedEndEvent.Subscribe(Listener.OnLeaked)}
        for (B : Bases):
            if (Health := B.Entity.GetComponent[entity_health_component]):
                set BaseSubs += array{Health.DestroyedEvent.Subscribe(OnBaseDestroyed)}

    # first living base whose CoveredLanes includes this lane; empty CoveredLanes covers all
    BaseForLane<private>(Lane:lane_component)<transacts>:?td_base_component =
        if:
            Idx := first (I -> L : Lanes; L = Lane) { I }
            B := first (X : Bases, X.IsAlive[], X.Covers[Idx]) { X }
        then:
            option{B}
        else:
            false

    SortLanes<private>(In:[]lane_component):[]lane_component =
        var Out:[]lane_component = array{}
        for (L : In):
            var Inserted:logic = false
            var New:[]lane_component = array{}
            for (X : Out):
                if (not Inserted?, L.LaneOrder < X.LaneOrder):
                    set New += array{L}
                    set Inserted = true
                set New += array{X}
            if (not Inserted?):
                set New += array{L}
            set Out = New
        Out

    SetState<private>(S:td_game_state):void =
        set State = S
        Print("TD: state -> {StateName(S)}")
        StateChangedEvent.Signal(S)


# Adapter: subscribable_event(entity) passes only the entity, so each subscription carries its lane.
lane_leak_listener := class:
    Game:td_game_component
    Lane:lane_component

    OnLeaked<public>(E:entity):void =
        Game.HandleLeak(Lane, E)
