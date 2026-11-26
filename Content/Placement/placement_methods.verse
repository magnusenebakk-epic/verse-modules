
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Verse.org/SpatialMath }
using { /Verse.org/Colors }
using { /Fortnite.com/Characters }
using { /Verse.org/SceneGraph }
using { /Verse.org/SceneGraph/CollisionProfiles }
using { /UnrealEngine.com/Temporary/Diagnostics }


placement_debug_channel<public> := class(debug_draw_channel){}


# Fixed distance ahead of the player
at_player_placement_method<public> := class<concrete>(placement_method):
    @editable
    var DistanceAhead<public>:float = 200.0

    ComputeProposal<override>(Query:placement_query)<transacts><decides>:placement_proposal =
        PlayerXform := FromTransform(Query.Player.GetFortCharacter[].GetTransform())
        Forward := PlayerXform.Rotation.GetForwardAxis()
        FlatForward := (LUF:)vector3{
            Forward := Forward.Forward,
            Left := Forward.Left,
            Up := 0.0
        }.MakeUnitVector()
        Translation := PlayerXform.Translation + FlatForward * DistanceAhead
        Rotation := MakeShortestRotationBetween(
            (LUF:)vector3{Forward := 1.0, Left := 0.0, Up := 0.0},
            FlatForward
        )
        Scale := Query.PlacableEntity.GetGlobalTransform().Scale
        Xform := (LUF:)transform{
            Translation := Translation,
            Rotation := Rotation,
            Scale := Scale
        }
        placement_proposal{ Transform := Xform }


# Sphere-sweep from camera forward up to MaxRange. Fails when nothing is hit.
look_aim_placement_method<public> := class<concrete>(hit_aware_placement_method):

    @editable
    var MaxRange<public>:float = 500.0

    @editable
    var SweepRadius<public>:float = 5.0

    @editable
    var Debug<public>:logic = false

    var<private> Drawer<private>:debug_draw = debug_draw{ Channel := placement_debug_channel }

    ComputeProposal<override>(Query:placement_query)<transacts><decides>:placement_proposal =
        Char := Query.Player.GetFortCharacter[]

        ViewLocation := FromVector3(Char.GetViewLocation())
        ViewRotation := FromRotation(Char.GetViewRotation())
        ViewForward := ViewRotation.GetForwardAxis()

        CharLocation := FromVector3(Char.GetTransform().Translation)
        CharRotation := FromRotation(Char.GetTransform().Rotation)
        CharForward := CharRotation.GetForwardAxis()

        Start := CharLocation + CharForward * 50.0
        End := ViewLocation + ViewForward * MaxRange
        Delta := End - Start

        if (Debug?):
            Drawer.ShowChannel()
            Drawer.DrawSphere(Start, ?Radius := SweepRadius, ?Color := NamedColors.Green, ?Duration := 0.1)
            Drawer.DrawArrow(Start, End, ?Color := NamedColors.Yellow, ?Duration := 0.1)

        Probe := collision_sphere{
            Radius := SweepRadius,
            CollisionProfile := VisibilityOverlapAll
        }
        StartTransform := (LUF:)transform{
            Translation := Start,
            Rotation    := ViewRotation,
            Scale       := (LUF:)vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
        }

        Sim := Char.GetEntity[].GetSimulationEntity[]
        Hits := Sim.FindSweepHits(Delta, StartTransform, Probe)
        FirstHit := FirstAcceptedHit[Query, Hits]

        if (Debug?):
            Drawer.DrawSphere(FirstHit.ContactPosition, ?Radius := SweepRadius * 1.5, ?Color := NamedColors.Red, ?DrawDurationPolicy := debug_draw_duration_policy.SingleFrame)
            Drawer.DrawArrow(FirstHit.ContactPosition, FirstHit.ContactPosition + FirstHit.ContactNormal * 30.0, ?Color := NamedColors.Cyan, ?DrawDurationPolicy := debug_draw_duration_policy.SingleFrame)

        PlayerXform := FromTransform(Char.GetTransform())
        PlayerForward := PlayerXform.Rotation.GetForwardAxis()
        FlatForward := (LUF:)vector3{
            Forward := PlayerForward.Forward,
            Left := PlayerForward.Left,
            Up := 0.0
        }.MakeUnitVector()
        Rotation := MakeShortestRotationBetween(
            (LUF:)vector3{Forward := 1.0, Left := 0.0, Up := 0.0},
            FlatForward
        )
        Scale := Query.PlacableEntity.GetGlobalTransform().Scale
        Xform := (LUF:)transform{
            Translation := FirstHit.ContactPosition,
            Rotation    := Rotation,
            Scale       := Scale
        }
        placement_proposal{
            Transform  := Xform,
            HitNormal  := option{FirstHit.ContactNormal},
            HitEntity  := option{FirstHit.TargetComponent.Entity}
        }


# Confirm gate for tap-to-place: a tap only confirms if it resolves to the same spot as the last
# tap, so a new cell aims and a re-tap places. UI confirm calls skip this. Resets every session.
retap_confirm_controls := class(placement_controls):
    Inner:placement_controls
    Method:placement_method
    Query:placement_query

    var LastSpot:?(LUF:)vector3 = false

    RequestConfirm<override>():void =
        NewSpot := option:
            Method.ComputeProposal[Query].Transform.Translation
        if:
            New := NewSpot?
            Prev := LastSpot?
            # unsnapped axes carry raw hit coords that jitter between taps; cells are a full CellSize apart, so 1cm slop is safe
            Distance(New, Prev) <= 1.0
        then:
            Inner.RequestConfirm()
        else:
            set LastSpot = NewSpot

    RequestCancel<override>():void =
        Inner.RequestCancel()


# Snaps Inner's proposal to a uniform global grid.
grid_snap_placement_method<public> := class<concrete>(placement_method):

    @editable
    var Inner<public>:placement_method = look_aim_placement_method{}

    # Route input through the retap gate so the wrapped method's taps aim first instead of confirming right away.
    RunInput<override>(Query:placement_query, Controls:placement_controls)<suspends>:void =
        Inner.RunInput(Query, retap_confirm_controls{
            Inner := Controls, Method := Self, Query := Query})

    @editable
    var CellSize<public>:float = 100.0

    @editable
    var Origin<public>:(LUF:)vector3 = (LUF:)vector3{Forward := 0.0, Left := 0.0, Up := 0.0}

    @editable
    var SnapForward<public>:logic = true

    @editable
    var SnapLeft<public>:logic = true

    @editable
    var SnapUp<public>:logic = false

    ComputeProposal<override>(Query:placement_query)<transacts><decides>:placement_proposal =
        InnerP := Inner.ComputeProposal[Query]
        Local := InnerP.Transform.Translation - Origin

        SnappedF := if (SnapForward?) then (1.0 * Round[Local.Forward / CellSize]) * CellSize else Local.Forward
        SnappedL := if (SnapLeft?)    then (1.0 * Round[Local.Left    / CellSize]) * CellSize else Local.Left
        SnappedU := if (SnapUp?)      then (1.0 * Round[Local.Up      / CellSize]) * CellSize else Local.Up

        SnappedXform := (LUF:)transform{
            Translation := Origin + (LUF:)vector3{Forward := SnappedF, Left := SnappedL, Up := SnappedU},
            Rotation    := InnerP.Transform.Rotation,
            Scale       := InnerP.Transform.Scale
        }
        placement_proposal{
            Transform := SnappedXform,
            HitNormal := InnerP.HitNormal,
            HitEntity := InnerP.HitEntity
        }


# Snaps to a grid_component on the entity HitMethod hits; never sweeps itself, put hit filters on HitMethod.
grid_component_placement_method<public> := class<concrete>(placement_method):

    @editable
    var HitMethod<public>:hit_aware_placement_method = look_aim_placement_method{}

    # Take rotation from the grid entity instead of the aim, so placements face the way the board faces.
    @editable
    var LockRotationToGrid<public>:logic = false

    # Extra yaw around the entity's own up axis; with LockRotationToGrid on, 90/180/270 give the other facings.
    @editable
    var YawOffsetDegrees<public>:float = 0.0

    # Gate tap confirms to a re-tap of the same cell (see retap_confirm_controls).
    RunInput<override>(Query:placement_query, Controls:placement_controls)<suspends>:void =
        HitMethod.RunInput(Query, retap_confirm_controls{
            Inner := Controls, Method := Self, Query := Query})

    ComputeProposal<override>(Query:placement_query)<transacts><decides>:placement_proposal =
        InnerP := HitMethod.ComputeProposal[Query]
        HitEnt := InnerP.HitEntity?
        Grid := FindGridComponent[HitEnt]
        SnappedPos := Grid.Snap[InnerP.Transform.Translation]

        BaseRotation := if (LockRotationToGrid?):
            Grid.Entity.GetGlobalTransform().Rotation
        else:
            InnerP.Transform.Rotation
        # yaw in the local frame first, then base rotation, so the spin is around the entity's own up axis
        Rotation := (LUF:)MakeRotationDegrees(
            (LUF:)vector3{Forward := 0.0, Left := 0.0, Up := 1.0},
            YawOffsetDegrees) * BaseRotation
        SnappedXform := (LUF:)transform{
            Translation := SnappedPos,
            Rotation    := Rotation,
            Scale       := InnerP.Transform.Scale
        }
        placement_proposal{
            Transform := SnappedXform,
            HitNormal := InnerP.HitNormal,
            HitEntity := InnerP.HitEntity
        }
