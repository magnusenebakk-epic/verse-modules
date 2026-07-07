using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


# Marker manager for a move session: one circle per legal target square,
# plus a single proposal marker that follows the aimed square. Reuses
# placement_highlight_reactive from the Placement module, so proposal
# prefabs can restyle on valid/invalid exactly like placement previews.
chess_move_highlight<public> := class<concrete>:

    @editable
    LegalMarkerPrefab<public>:?concrete_subtype(entity) = false

    @editable
    ProposalMarkerPrefab<public>:?concrete_subtype(entity) = false

    # World-up offset so circles sit on top of the board surface.
    @editable
    MarkerUp<public>:float = 2.0

    var LegalMarkers<private>:[]entity = array{}
    var ProposalMarker<private>:?entity = false
    var LastValid<private>:?logic = false

    # Targets are (square, world position). The square is stamped onto the
    # marker's chess_target_marker_component so interacting with the circle
    # commits the move there.
    ShowLegalTargets<public>(Host:entity, Targets:[]tuple(int, vector3)):void =
        HideLegalTargets()
        if (Prefab := LegalMarkerPrefab?):
            for (T : Targets):
                New := Prefab{}
                Host.AddEntities(array{New})
                MoveMarker(New, T(1))
                if (TM := New.GetComponent[chess_target_marker_component]):
                    set TM.Square = T(0)
                set LegalMarkers += array{New}

    ShowProposal<public>(Host:entity, Pos:vector3, IsValid:logic):void =
        Marker := if (M := ProposalMarker?):
            M
        else:
            New := if (Prefab := ProposalMarkerPrefab?):
                Spawned := Prefab{}
                Host.AddEntities(array{Spawned})
                Spawned
            else:
                entity{}
            set ProposalMarker = option{New}
            New
        MoveMarker(Marker, Pos)
        if (LastValid <> option{IsValid}):
            for (R : Marker.GetDescendantComponentsWithInterface(Placement.placement_highlight_reactive)):
                R.OnPlacementValidChanged(IsValid)
            set LastValid = option{IsValid}

    HideProposal<public>():void =
        if (M := ProposalMarker?):
            M.RemoveFromParent()
            set ProposalMarker = false
            set LastValid = false

    HideLegalTargets<public>():void =
        for (M : LegalMarkers):
            M.RemoveFromParent()
        set LegalMarkers = array{}

    HideAll<public>():void =
        HideProposal()
        HideLegalTargets()

    MoveMarker<private>(Marker:entity, Pos:vector3):void =
        Current := Marker.GetGlobalTransform()
        Lifted := vector3{Forward := Pos.Forward, Left := Pos.Left, Up := Pos.Up + MarkerUp}
        Marker.SetGlobalTransform(transform{
            Translation := Lifted,
            Rotation := Current.Rotation,
            Scale := Current.Scale})
