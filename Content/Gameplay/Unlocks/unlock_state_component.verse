using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization } # result types

using { Gameplay.Bases }
using { Gameplay.Ownership }


# Per-base unlock progression. Sits next to a base_component and follows its
# claim/release lifecycle. Owner state lives in the ownable, not here.
# The graph is just the unlock_node_components under this entity, each
# self-registering by Key.
unlock_state_component<public> := class<final_super>(component):

    var UnlockedKeys<private>:[string]logic = map{}
    var Nodes<private>:[string]unlock_node_component = map{}
    var Ints<private>:[string]int = map{}
    var Floats<private>:[string]float = map{}
    var Subscriptions<private>:[]Concurrency.subscription_task(member_change) = array{}

    NodeUnlockedEvent<public>:Concurrency.subscribable_event(unlock_node_component) =
        Concurrency.subscribable_event(unlock_node_component){}

    NodeResetEvent<public>:Concurrency.subscribable_event(unlock_node_component) =
        Concurrency.subscribable_event(unlock_node_component){}

    IntChangedEvent<public>:Concurrency.subscribable_event(unlock_int_change) =
        Concurrency.subscribable_event(unlock_int_change){}

    FloatChangedEvent<public>:Concurrency.subscribable_event(unlock_float_change) =
        Concurrency.subscribable_event(unlock_float_change){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        # Catch nodes whose OnAddedToScene ran before ours.
        for (N : Entity.FindDescendantComponents(unlock_node_component)):
            RegisterNode(N)
        # Claim/release is the sibling ownable's primary member add/remove.
        if (Base := Entity.GetComponent[base_component], Ownable := Base.GetOwnable[]):
            set Subscriptions += array{
                Ownable.MemberAddedEvent.Subscribe(OnMemberAdded),
                Ownable.MemberRemovedEvent.Subscribe(OnMemberRemoved)
            }
            if (A := Ownable.GetPrimaryOwner[]): # already claimed
                OnBaseClaimed(A)

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : Subscriptions):
            S.Cancel()
        set Subscriptions = array{}

    # --- Queries ------------------------------------------------------------

    IsUnlocked<public>(K:string)<reads><decides>:void =
        UnlockedKeys[K]?

    GetNode<public>(K:string)<reads><decides>:unlock_node_component =
        Nodes[K]

    UnlockedNodes<public>()<reads>:[]unlock_node_component =
        for (K -> N : Nodes, UnlockedKeys[K]?) { N }

    AllNodes<public>()<reads>:[]unlock_node_component =
        for (K -> N : Nodes) { N }

    # Suspends until K is unlocked. Returns immediately if it already is.
    AwaitUnlocked<public>(K:string)<suspends>:void =
        loop:
            if (IsUnlocked[K]):
                break
            NodeUnlockedEvent.Await() # recheck on any unlock, covers ForceUnlock

    # Per-base value stores, persisted with the unlock keys. Features
    # read/write namespaced keys here ("test_a.count"). Get fails if never
    # set, default at the call site with `or 0`.

    GetInt<public>(K:string)<reads><decides>:int =
        Ints[K]

    SetInt<public>(K:string, V:int):void = # signals, no rollback
        Old := Ints[K] or 0
        if (set Ints[K] = V) {}
        IntChangedEvent.Signal(unlock_int_change{Key := K, OldValue := Old, NewValue := V})

    GetFloat<public>(K:string)<reads><decides>:float =
        Floats[K]

    SetFloat<public>(K:string, V:float):void = # signals, no rollback
        Old := Floats[K] or 0.0
        if (set Floats[K] = V) {}
        FloatChangedEvent.Signal(unlock_float_change{Key := K, OldValue := Old, NewValue := V})

    # Pre-check without committing anything (requirement checks roll back).
    # Counts instead of `for (R): R.IsSatisfied[...]` because a failing for
    # body just skips the iteration, it doesn't fail the function.
    CanUnlock<public>(K:string, Agent:agent)<transacts><decides>:void =
        N := Nodes[K]
        not IsUnlocked[K]
        UnsatisfiedRequirements(N, Agent).Length = 0

    # --- Unlocking ----------------------------------------------------------

    # Check, commit all costs in one transaction, then mark and signal.
    # Typed error so UI can tell the cases apart.
    TryUnlock<public>(K:string, Agent:agent):result(unlock_success, unlock_error) =
        if (N := Nodes[K]):
            if (IsUnlocked[K]):
                MakeError(already_unlocked_error{})
            else if (Failed := UnsatisfiedRequirements(N, Agent), Failed.Length > 0):
                MakeError(requirements_unsatisfied_error{Failed := Failed})
            else if (CommitRequirements[N, Agent]):
                NotifyCommitted(N, Agent)
                MarkUnlocked(N)
                MakeSuccess(unlock_success{Node := N})
            else:
                MakeError(commit_failed_unlock_error{})
        else:
            MakeError(unknown_key_unlock_error{})

    # Unconditional. Used by AutoUnlock, persistence restore and debug.
    ForceUnlock<public>(K:string):void =
        if (N := Nodes[K], not IsUnlocked[K]):
            MarkUnlocked(N)

    # --- Node registry (called by nodes) -------------------------------------

    RegisterNode<public>(N:unlock_node_component):void =
        if (Existing := Nodes[N.Key]):
            if (not (Existing = N)):
                Print("unlock_state: duplicate key '{N.Key}' ignored")
        else:
            if (set Nodes[N.Key] = N) {}
            N.OnAttachToState(Self)
            if (IsUnlocked[N.Key]): # late registration into an unlocked key
                N.DispatchUnlocked(Self)

    UnregisterNode<public>(N:unlock_node_component):void =
        if (Existing := Nodes[N.Key], Existing = N):
            set Nodes = Nodes.RemoveKey(N.Key)

    # --- Base lifecycle -----------------------------------------------------

    # Only the primary owner counts as claim/release. Co-owner churn does
    # not touch progression.
    OnMemberAdded<private>(C:member_change):void =
        if (C.Info.IsPrimary?):
            OnBaseClaimed(C.Agent)

    OnMemberRemoved<private>(C:member_change):void =
        if (C.Info.IsPrimary?):
            OnBaseReleased(C.Agent)

    # Value stores load before ForceUnlock so spawned prefabs read correct
    # values on their first tick.
    OnBaseClaimed<private>(Agent:agent):void =
        LoadPersisted(Agent)
        for (Ignored -> N : Nodes, N.AutoUnlock?, not IsUnlocked[N.Key]):
            MarkUnlocked(N)

    OnBaseReleased<private>(Former:agent):void =
        SaveFor(Former)
        for (Ignored -> N : Nodes, IsUnlocked[N.Key]):
            NodeResetEvent.Signal(N)
        set UnlockedKeys = map{}
        set Ints = map{}
        set Floats = map{}

    # --- Persistence --------------------------------------------------------

    Save<public>():void =
        if (Base := Entity.GetComponent[base_component], A := Base.GetOwner[]):
            SaveFor(A)

    SaveFor<private>(Agent:agent):void =
        if (P := player[Agent]):
            Keys := for (K -> U : UnlockedKeys) { K }
            New := persisted_unlock_state{UnlockedKeys := Keys, Ints := Ints, Floats := Floats}
            if (set UnlocksPersistenceMap[P] = New) {}

    LoadPersisted<private>(Agent:agent):void =
        if (P := player[Agent], Stored := UnlocksPersistenceMap[P]):
            set Ints = Stored.Ints
            set Floats = Stored.Floats
            for (K : Stored.UnlockedKeys):
                if (Nodes[K]):
                    ForceUnlock(K)
                else:
                    # Node missing in this base (layout variant). Keep the
                    # key so the next save doesn't drop it.
                    if (set UnlockedKeys[K] = true) {}

    # --- Internals ----------------------------------------------------------

    UnsatisfiedRequirements<private>(N:unlock_node_component, Agent:agent)<transacts>:[]unlock_requirement =
        for (R : N.AllRequirements(), not R.IsSatisfied[Agent, N.Entity]) { R }

    # One transaction over all commits. Commit runs as a filter, then the
    # count check fails the call if any commit was skipped, which rolls back
    # the ones that did land. All or nothing.
    CommitRequirements<private>(N:unlock_node_component, Agent:agent)<transacts><decides>:void =
        All := N.AllRequirements()
        Committed := for (R : All, R.Commit[Agent, N.Entity]) { R }
        Committed.Length = All.Length

    # Post-transaction, requirements fire their change events here.
    NotifyCommitted<private>(N:unlock_node_component, Agent:agent):void =
        for (R : N.AllRequirements()):
            R.OnCommitted(Agent, N.Entity)

    MarkUnlocked<private>(N:unlock_node_component):void = # signals, no rollback
        if (set UnlockedKeys[N.Key] = true) {}
        NodeUnlockedEvent.Signal(N)
