using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Temporary }
using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


# How a combatant finds something to shoot: returns when a target exists, blocks while none does.
targeter<public> := class<abstract>:
    AwaitTarget<public>(Searcher:entity)<suspends>:entity


# Pick priority for single-target zone towers. Entry order gives the classic
# first/last pair (first in = in range longest); distance gives nearest/furthest.
target_priority<public> := enum:
    First
    Last
    Nearest
    Furthest


# SortBy comparators must be computes, so distances are scored before the sort
CloserFirst(A:tuple(entity, float), B:tuple(entity, float))<computes><decides>:void =
    A(1) < B(1)


# Shared core for zone targeters: the ordered in-zone list plus the priority
# pick over it. Subclasses only differ in how the list is maintained.
zone_targeter<public> := class<abstract>(targeter):

    # Re-read at every pick, so it can be switched at runtime.
    @editable
    var Priority<public>:target_priority = target_priority.First

    # in-zone enemies, oldest entry first; index 0 is "first in"
    var<protected> InZone<protected>:[]entity = array{}

    # despawns and teardown can skip the exit event; no ghost targets
    Scrub<protected>():void =
        set InZone = for (E : InZone, E.GetSimulationEntity[]) { E }

    # resolve hits to the tagged enemy root; NPC bodies are not in the tagged char entity's chain, so hop via fort_character's agent
    EnemyRootOf<protected>(E:entity)<transacts><decides>:entity =
        Chain := array{E} + (for (A : E.FindAncestorEntities(entity)) { A })
        Direct := for (C : Chain, C.ContainsTag[td_enemy_tag]) { C }
        ViaChar := for:
            C : Chain
            Comp : C.GetComponents()
            FC := fort_character[Comp]
            CharE := FC.GetAgent[].GetFortCharacter[].GetEntity[]
            CharE.ContainsTag[td_enemy_tag]
        do:
            CharE
        Found := Direct + ViaChar
        Found[0]

    Contains<protected>(E:entity)<reads><decides>:void =
        first (X : InZone, X = E) { X }

    Pick<protected>(Searcher:entity)<transacts><decides>:entity =
        Cands := for (E : InZone, MayEngage[Searcher, E]) { E }
        case (Priority):
            target_priority.First => Cands[0]
            target_priority.Last => Cands[Cands.Length - 1]
            target_priority.Nearest => ByDistance[Searcher, Cands, false]
            target_priority.Furthest => ByDistance[Searcher, Cands, true]

    ByDistance<private>(Searcher:entity, Cands:[]entity, PickFar:logic)<transacts><decides>:entity =
        Pos := Searcher.GetGlobalTransform().Translation
        Scored := for (E : Cands):
            (E, Distance(E.GetGlobalTransform().Translation, Pos))
        Sorted := SortBy(Scored, CloserFirst)
        Winner := if (PickFar?) then Sorted[Sorted.Length - 1] else Sorted[0]
        Winner(0)


# Overlap-zone targeting via a target_zone_tag mesh zone; no polling. Gotcha:
# query meshes carve the navmesh even with Collidable off; lane towers need box_query_targeter.
overlap_targeter<public> := class<concrete>(zone_targeter):

    var<private> Tracking<private>:logic = false
    Changed<private>:event() = event(){}

    AwaitTarget<override>(Searcher:entity)<suspends>:entity =
        EnsureTracking(Searcher)
        loop:
            Scrub()
            if (T := Pick[Searcher]):
                return T
            Changed.Await()

    # subscribe first, then seed with what already overlaps; OnEntered's dupe guard covers the gap
    EnsureTracking<private>(Searcher:entity):void =
        if (Tracking?). return
        set Tracking = true
        MaybeZone := option{FindZone[Searcher]}
        if (Zone := MaybeZone?):
            Zone.EntityEnteredEvent.Subscribe(OnEntered)
            Zone.EntityExitedEvent.Subscribe(OnExited)
            for (H : Zone.Entity.FindOverlapHits()):
                OnEntered(H.TargetComponent.Entity)
        else:
            Print("TD: overlap_targeter found no target_zone_tag mesh under the tower")

    FindZone<private>(Searcher:entity)<transacts><decides>:mesh_component =
        ZoneEntity := first{E : Searcher.FindDescendantEntitiesWithTag(target_zone_tag)}
        ZoneEntity.GetComponent[mesh_component]

    OnEntered<private>(E:entity):void =
        MaybeEnemy := option{EnemyRootOf[E]}
        if (Enemy := MaybeEnemy?, not Contains[Enemy]):
            set InZone += array{Enemy}
            Changed.Signal()

    OnExited<private>(E:entity):void =
        MaybeEnemy := option{EnemyRootOf[E]}
        if (Enemy := MaybeEnemy?):
            set InZone = for (X : InZone, not (X = Enemy)) { X }
            Changed.Signal()


# Zone targeting via a periodic box query; no scene presence, so no navmesh
# carving. Entry order survives scans; box centers on the target_zone_tag child (else the searcher) and Extents are in its local frame.
box_query_targeter<public> := class<concrete>(zone_targeter):

    # Half-size of the box (engine Extents convention).
    @editable
    var Extents<public>:vector3 = vector3{Forward := 250.0, Left := 250.0, Up := 150.0}

    # Seconds between box scans; polling is required since there is no physical zone.
    @editable
    var RescanInterval<public>:float = 0.25

    # Dev aid: log the box once, then scans whose counts change and each pick (bq[N]).
    @editable
    var DebugQuery<public>:logic = true

    var<private> DebugId<private>:int = 0
    # (query in-box, tracked) of the last logged scan
    var<private> LastCounts<private>:tuple(int, int) = (-1, -1)
    # forces a heartbeat print so a permanently-empty query stays visible
    var<private> ScansSinceLog<private>:int = 0

    AwaitTarget<override>(Searcher:entity)<suspends>:entity =
        if (DebugOn[DebugQuery], DebugId = 0):
            set DebugId = NextTDNavDebugId()
            ZT := ZoneTransform(Searcher)
            YPR := ZT.Rotation.GetYawPitchRollDegrees()
            Print("bq[{DebugId}] scanning: center {ToString(ZT.Translation)} yaw {YPR(0)} scale {ToString(ZT.Scale)} extents {ToString(Extents)} every {RescanInterval}s")
        loop:
            Refresh(Searcher)
            if (T := Pick[Searcher]):
                if (DebugOn[DebugQuery]):
                    Print("bq[{DebugId}] target picked at {ToString(T.GetGlobalTransform().Translation)}")
                return T
            Sleep(RescanInterval)

    ZoneTransform<private>(Searcher:entity)<transacts>:transform =
        if (ZoneEntity := first{E : Searcher.FindDescendantEntitiesWithTag(target_zone_tag)}, true?):
            ZoneEntity.GetGlobalTransform()
        else:
            Searcher.GetGlobalTransform()

    Refresh<private>(Searcher:entity):void =
        ZT := ZoneTransform(Searcher)
        QueryHits := for (H : Searcher.FindOverlapHits(ZT, collision_box{
            Extents := Extents, CollisionProfile := CollisionProfiles.DynamicOverlapAll})) { H }
        Roots := for (H : QueryHits, R := EnemyRootOf[H.TargetComponent.Entity]) { R }
        # survivors keep entry order, newcomers append; Contains also dedupes multi-volume hits on one body
        set InZone = for (E : InZone, HitsContain[Roots, E]) { E }
        for (R : Roots):
            if (not Contains[R]):
                set InZone += array{R}
        if (DebugOn[DebugQuery]):
            Counts := (Roots.Length, InZone.Length)
            set ScansSinceLog += 1
            if (not (Counts = LastCounts) or ScansSinceLog >= 20):
                set LastCounts = Counts
                set ScansSinceLog = 0
                Print("bq[{DebugId}] scan: query {Roots.Length} | {InZone.Length} tracked")

    HitsContain<private>(Hits:[]entity, E:entity)<reads><decides>:void =
        first (X : Hits, X = E) { X }


# Spatial polling fallback: closest tagged entity within Radius, for searchers
# with no zone sub-entity. tower_radius_targeter below is the main user.
radius_targeter<public> := class<concrete>(targeter):

    @editable
    var Radius<public>:float = 500.0

    @editable
    var RescanInterval<public>:float = 0.25

    # candidate pool; the enemy-side subclass swaps the tag
    Candidates<protected>(Sim:entity)<transacts>:[]entity =
        for (En : Sim.FindDescendantEntitiesWithTag(td_enemy_tag)) { En }

    AwaitTarget<override>(Searcher:entity)<suspends>:entity =
        loop:
            if (T := FindClosest[Searcher]):
                return T
            Sleep(RescanInterval)

    FindClosest<private>(Searcher:entity)<transacts><decides>:entity =
        Sim := Searcher.GetSimulationEntity[]
        Pos := Searcher.GetGlobalTransform().Translation
        Cands := for:
            En : Candidates(Sim)
            # never engage across game instances (td_membership.verse)
            MayEngage[Searcher, En]
            D := Distance(En.GetGlobalTransform().Translation, Pos)
            D <= Radius
        do:
            (En, D)
        Closest := SortBy(Cands, CloserFirst)[0]
        Closest(0)


# Enemy-side spatial targeting: closest tower within Radius, gating enemy attacks.
tower_radius_targeter<public> := class<concrete>(radius_targeter):
    Candidates<override>(Sim:entity)<transacts>:[]entity =
        for (En : Sim.FindDescendantEntitiesWithTag(tower_tag)) { En }


# Enemy melee targeting: whatever blocker the NPC behavior is engaging; no
# range checks. Waits forever on non-TD holders and between engagements.
engaged_blocker_targeter<public> := class<concrete>(targeter):

    AwaitTarget<override>(Searcher:entity)<suspends>:entity =
        if (Info := FindInfo[Searcher]):
            loop:
                if (T := Info.GetEngaged()?):
                    return T
                Info.EngagedChangedEvent.Await()
        else:
            Sleep(Inf)
        Searcher

    FindInfo<private>(Searcher:entity)<transacts><decides>:td_enemy_info_component =
        Chain := array{Searcher} + (for (A : Searcher.FindAncestorEntities(entity)) { A })
        Found := for (C : Chain, I := C.GetComponent[td_enemy_info_component]) { I }
        Found[0]
