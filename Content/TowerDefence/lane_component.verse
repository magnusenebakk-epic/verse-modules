using { /UnrealEngine.com/Temporary/Diagnostics }
using { /Verse.org/Colors }
using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


# Marks a descendant entity of a lane as a path waypoint. Order sorts them.
lane_waypoint_component<public> := class<final_super>(component):
    @editable
    (lane_waypoint_component:)Order<public>:int = 0


# How the lane reads an enemy's motion, whatever drives it; progress is distance along the path.
lane_traveler<public> := interface:
    GetLaneProgress<public>()<transacts>:float


# A lane: a waypoint path plus the enemies currently on it. Travelers report
# progress as path distance so lane-aware code can order enemies by track progress.
lane_component<public> := class<final_super>(component):

    # Stable index for wave data; the game sorts lanes by this.
    @editable
    LaneOrder<public>:int = 0

    # Dev aid: dump the built path to log and draw it in-world.
    @editable
    DebugPath<public>:logic = true

    Drawer<private>:debug_draw = debug_draw{ Channel := td_nav_debug_channel }

    # Signalled on register/unregister for anything watching lane population.
    EnemiesChangedEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    # An enemy walked off the end (leaked). Wave/health logic subscribes.
    EnemyReachedEndEvent<public>:Concurrency.subscribable_event(entity) =
        Concurrency.subscribable_event(entity){}

    var<private> PathPoints<private>:[](LUF:)vector3 = array{}
    # path distance at each point; parallel to PathPoints
    var<private> StartDists<private>:[]float = array{}
    var<private> (lane_component:)Enemies<private>:[]tuple(entity, lane_traveler) = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        BuildPath()
        if (DebugOn[DebugPath]):
            DumpPath()

    DumpPath<private>():void =
        Print("td lane {LaneOrder}: {PathPoints.Length} waypoints")
        for (I -> P : PathPoints):
            SD := StartDists[I] or -1.0
            Print("td lane {LaneOrder}: wp{I} {ToString(P)} d={SD}")
            Drawer.DrawSphere(P, ?Radius := 15.0, ?Color := NamedColors.Green, ?DrawDurationPolicy := debug_draw_duration_policy.Persistent)
            Drawer.DrawText("L{LaneOrder} wp{I}", P + (LUF:)vector3{Forward := 0.0, Left := 0.0, Up := 60.0}, ?Color := NamedColors.White, ?DrawDurationPolicy := debug_draw_duration_policy.Persistent)
            if (I > 0, Prev := PathPoints[I - 1]):
                Drawer.DrawLine(Prev, P, ?Color := NamedColors.Green, ?Thickness := 3.0, ?DrawDurationPolicy := debug_draw_duration_policy.Persistent)

    GetPathPoints<public>()<reads>:[](LUF:)vector3 = PathPoints

    # Path distance of waypoint Idx; pairs with GetPathPoints.
    WaypointDistance<public>(Idx:int)<transacts><decides>:float = StartDists[Idx]

    GetEnemies<public>()<reads>:[]entity = for (X : (lane_component:)Enemies) { X(0) }

    Register<public>(E:entity, T:lane_traveler):void =
        set (lane_component:)Enemies += array{(E, T)}
        EnemiesChangedEvent.Signal(())

    Unregister<public>(E:entity):void =
        set (lane_component:)Enemies = for (X : (lane_component:)Enemies, not (X(0) = E)) { X }
        EnemiesChangedEvent.Signal(())

    NotifyReachedEnd<public>(E:entity):void =
        EnemyReachedEndEvent.Signal(E)

    # furthest enemy in [MinD, MaxD]; unused by targeters today, kept for lane-aware modes
    HighestProgressInWindow<public>(MinD:float, MaxD:float)<transacts><decides>:entity =
        Candidates := for:
            X : (lane_component:)Enemies
            P := X(1).GetLaneProgress()
            MinD <= P
            P <= MaxD
        do:
            (X(0), P)
        var Best:?tuple(entity, float) = false
        for (C : Candidates):
            if (B := Best?):
                if (C(1) > B(1)):
                    set Best = option{C}
            else:
                set Best = option{C}
        Winner := Best?
        Winner(0)

    # closest point on the path to P: (path distance, distance to path); fails below 2 waypoints
    ProjectOntoPath<public>(P:(LUF:)vector3)<transacts><decides>:tuple(float, float) =
        PathPoints.Length >= 2
        var BestDist:float = Inf
        var BestAlong:float = 0.0
        for (I := 0..PathPoints.Length - 2):
            if:
                A := PathPoints[I]
                B := PathPoints[I + 1]
                SegStart := StartDists[I]
            then:
                AB := B - A
                LenSq := DotProduct(AB, AB)
                T := if (LenSq > 0.0) then Clamp(DotProduct(P - A, AB) / LenSq, 0.0, 1.0) else 0.0
                Closest := A + AB * T
                D := Distance(P, Closest)
                if (D < BestDist):
                    set BestDist = D
                    set BestAlong = SegStart + Distance(A, Closest)
        (BestAlong, BestDist)

    # path distance of Pos projected onto segment Idx (clamped); NPC travelers derive progress on demand
    ProgressOnSegment<public>(Idx:int, Pos:(LUF:)vector3)<transacts><decides>:float =
        A := PathPoints[Idx]
        B := PathPoints[Idx + 1]
        SegStart := StartDists[Idx]
        AB := B - A
        LenSq := DotProduct(AB, AB)
        T := if (LenSq > 0.0) then Clamp(DotProduct(Pos - A, AB) / LenSq, 0.0, 1.0) else 0.0
        SegStart + Distance(A, A + AB * T)

    # first waypoint at or past path distance D; mid-lane joiners start navigating here
    FirstWaypointAtOrBeyond<public>(D:float)<transacts>:int =
        var Found:?int = false
        for (I -> SD : StartDists, not Found?, SD >= D):
            set Found = option{I}
        if (F := Found?):
            F
        else if (PathPoints.Length > 0):
            PathPoints.Length - 1
        else:
            0

    # world position at path distance D, clamped to the path ends
    PointAtDistance<public>(D:float)<transacts><decides>:(LUF:)vector3 =
        PathPoints.Length >= 2
        var Index:int = 0
        # last segment whose start is at or before D (StartDists is monotonic)
        for (I := 0..PathPoints.Length - 2, SD := StartDists[I], SD <= D):
            set Index = I
        A := PathPoints[Index]
        B := PathPoints[Index + 1]
        SegStart := StartDists[Index]
        SegLen := Distance(A, B)
        T := if (SegLen > 0.0) then Clamp((D - SegStart) / SegLen, 0.0, 1.0) else 0.0
        A + (B - A) * T

    # unit travel direction of the segment containing D, clamped to the last segment
    DirectionAt<public>(D:float)<transacts><decides>:(LUF:)vector3 =
        PathPoints.Length >= 2
        var Index:int = 0
        # last segment whose start is at or before D (StartDists is monotonic)
        for (I := 0..PathPoints.Length - 2, SD := StartDists[I], SD <= D):
            set Index = I
        A := PathPoints[Index]
        B := PathPoints[Index + 1]
        (B - A).MakeUnitVector()

    BuildPath<private>():void =
        Waypoints := for (W : Entity.FindDescendantComponents(lane_waypoint_component)) { W }
        Sorted := SortByOrder(Waypoints)
        set PathPoints = for (W : Sorted) { W.Entity.GetGlobalTransform().Translation }
        var Dists:[]float = array{}
        var Acc:float = 0.0
        for (I -> P : PathPoints):
            if (I > 0, Prev := PathPoints[I - 1]):
                set Acc += Distance(Prev, P)
            set Dists += array{Acc}
        set StartDists = Dists

    SortByOrder<private>(In:[]lane_waypoint_component):[]lane_waypoint_component =
        var Out:[]lane_waypoint_component = array{}
        for (W : In):
            var Inserted:logic = false
            var New:[]lane_waypoint_component = array{}
            for (X : Out):
                if (not Inserted?, W.Order < X.Order):
                    set New += array{W}
                    set Inserted = true
                set New += array{X}
            if (not Inserted?):
                set New += array{W}
            set Out = New
        Out


# lane closest to Pos: (lane, path distance, distance to path); candidates scoped by game membership
FindNearestLane<public>(SearchRoot:entity, Pos:(LUF:)vector3)<transacts><decides>:tuple(lane_component, float, float) =
    Projected := for:
        L : CandidateLanes(SearchRoot)
        Proj := L.ProjectOntoPath[Pos]
    do:
        (L, Proj(0), Proj(1))
    var Best:?tuple(lane_component, float, float) = false
    for (P : Projected):
        if (B := Best?):
            if (P(2) < B(2)):
                set Best = option{P}
        else:
            set Best = option{P}
    Best?
