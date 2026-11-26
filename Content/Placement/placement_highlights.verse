using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


log_placement_highlight<public> := class<concrete>(placement_highlight):
    var<private> LastMsg<private>:string = ""

    ShowPreview<override>(Query:placement_query, Proposal:placement_proposal, IsValid:logic):void =
        ValidStr := if (IsValid?) then "ok" else "blocked"
        Msg := "{ToString(Proposal.Transform)} [{ValidStr}]"
        if (Msg <> LastMsg):
            Print("placement preview @ {Msg}")
            set LastMsg = Msg

    HidePreview<override>():void =
        if (LastMsg <> ""):
            Print("placement preview hidden")
            set LastMsg = ""


# Implement on highlight prefab descendants to react to validity changes, like swapping a material when invalid.
placement_highlight_reactive<public> := interface<castable>(p_interface):
    OnPlacementValidChanged<public>(IsValid:logic):void


# Moves the placable itself to the proposal, so the entity is its own preview; world entities only,
# restoring on cancel is the driver's job (RunWorldPlacement).
move_entity_highlight<public> := class<concrete>(placement_highlight):

    ShowPreview<override>(Query:placement_query, Proposal:placement_proposal, IsValid:logic):void =
        Query.PlacableEntity.SetGlobalTransform(Proposal.Transform)

    # nothing spawned, nothing to clear; on lost aim the entity stays put
    HidePreview<override>():void = {}
    OnProposalLost<override>():void = {}


# spawns HighlightPrefab on first show, retransforms each tick, despawns on hide.
prefab_highlight<public> := class<concrete>(placement_highlight):

    @editable
    HighlightPrefab<public>:?concrete_subtype(entity) = false

    var<private> Spawned<private>:?entity = false
    # ?logic so first ShowPreview always notifies
    var<private> LastValid<private>:?logic = false

    ShowPreview<override>(Query:placement_query, Proposal:placement_proposal, IsValid:logic):void =
        Active := GetHighlight(Query)
        Active.SetGlobalTransform(Proposal.Transform)
        if (LastValid <> option{IsValid}):
            NotifyValidChanged(Active, IsValid)
            set LastValid = option{IsValid}

    HidePreview<override>():void =
        if (E := Spawned?):
            E.RemoveFromParent()
            set Spawned = false
            set LastValid = false

    GetHighlight<private>(Query:placement_query):entity =
        Spawned? or SpawnNew(Query)

    SpawnNew<private>(Query:placement_query):entity =
        NewHighlight := if:
            P := HighlightPrefab?
            Sim := Query.PlacableEntity.GetSimulationEntity[]
        then:
            New := P{}
            Sim.AddEntities(array{New})
            New
        else:
            entity{} # TODO: make this better default

        set Spawned = option{NewHighlight}
        NewHighlight

    NotifyValidChanged<private>(HighlightEntity:entity, IsValid:logic):void =
        for (R : HighlightEntity.GetDescendantComponentsWithInterface(placement_highlight_reactive)):
            R.OnPlacementValidChanged(IsValid)


# Optional marker on a placable prefab: the ghost to show while placing it; read by placable_preview_highlight.
placement_preview_component<public> := class<final_super>(component):
    # Ghost prefab shown at the aim instead of the real entity.
    @editable
    PreviewPrefab<public>:concrete_subtype(entity) = entity


# Per-prefab ghost preview: drags the prefab from placement_preview_component
# at the aim; ghost parents under the placable so self-hit checks skip it.
placable_preview_highlight<public> := class<concrete>(placement_highlight):

    var<private> Spawned<private>:?entity = false
    # ?logic so first ShowPreview always notifies
    var<private> LastValid<private>:?logic = false

    ShowPreview<override>(Query:placement_query, Proposal:placement_proposal, IsValid:logic):void =
        Target := PreviewTarget(Query)
        Target.SetGlobalTransform(Proposal.Transform)
        if (LastValid <> option{IsValid}):
            NotifyValidChanged(Target, IsValid)
            set LastValid = option{IsValid}

    # keep the ghost up through aim gaps
    OnProposalLost<override>():void = {}

    HidePreview<override>():void =
        if (E := Spawned?):
            E.RemoveFromParent()
        set Spawned = false
        set LastValid = false

    PreviewTarget<private>(Query:placement_query):entity =
        Spawned? or SpawnGhost(Query)

    # no preview component on the placable = the entity previews itself
    SpawnGhost<private>(Query:placement_query):entity =
        if (Prev := Query.PlacableEntity.GetComponent[placement_preview_component]):
            Ghost := ((concrete_subtype(entity))(Prev.PreviewPrefab)){}
            Query.PlacableEntity.AddEntities(array{Ghost})
            set Spawned = option{Ghost}
            Ghost
        else:
            Query.PlacableEntity

    NotifyValidChanged<private>(PreviewEntity:entity, IsValid:logic):void =
        for (R : PreviewEntity.GetDescendantComponentsWithInterface(placement_highlight_reactive)):
            R.OnPlacementValidChanged(IsValid)


# Paints TilePrefab on every cell the placable is allowed on, judged by the session Restrictions on a
# synthetic proposal at the cell center. Repaints only on occupancy changes; markers stay up until session end.
grid_valid_tiles_highlight<public> := class<concrete>(placement_highlight):

    @editable
    TilePrefab<public>:concrete_subtype(entity) = entity

    # Lift above the board plane so flat markers don't z-fight the tiles.
    @editable
    var MarkerUp<public>:float = 2.0

    var<private> Markers<private>:[]entity = array{}
    var<private> BoundGrid<private>:?grid_component = false
    var<private> ChangedSub<private>:?Concurrency.subscription_task(tuple()) = false
    var<private> NeedsRepaint<private>:logic = true

    # no proposal before the first tap, so find the board by scene query; first grid wins, the first aim rebinds
    OnSessionStart<override>(Query:placement_query):void =
        if (Grid := FindStartGrid[Query]):
            PaintIfNeeded(Query, Grid)

    ShowPreview<override>(Query:placement_query, Proposal:placement_proposal, IsValid:logic):void =
        if (HitEnt := Proposal.HitEntity?, Grid := FindGridComponent[HitEnt]):
            PaintIfNeeded(Query, Grid)

    PaintIfNeeded<private>(Query:placement_query, Grid:grid_component):void =
        BindGrid(Grid)
        if (NeedsRepaint?):
            set NeedsRepaint = false
            Repaint(Query, Grid)

    FindStartGrid<private>(Query:placement_query)<transacts><decides>:grid_component =
        first{G : Query.PlacableEntity.GetSimulationEntity[].FindDescendantComponents(grid_component)}

    # Aim gap: keep the tiles up.
    OnProposalLost<override>():void = {}

    HidePreview<override>():void =
        ClearMarkers()
        Unbind()

    BindGrid<private>(Grid:grid_component):void =
        if (B := BoundGrid?, B.Entity = Grid.Entity). return
        Unbind()
        set BoundGrid = option{Grid}
        set NeedsRepaint = true
        if (Occ := Grid.Entity.GetComponent[grid_occupancy_component]):
            C := Occ.ChangedEvent.Subscribe(OnOccupancyChanged)
            set ChangedSub = option{C}

    Unbind<private>():void =
        if (S := ChangedSub?):
            S.Cancel()
        set ChangedSub = false
        set BoundGrid = false
        set NeedsRepaint = true

    # Just marks dirty. The next ShowPreview tick repaints with its Query.
    OnOccupancyChanged<private>(X:tuple()):void =
        set NeedsRepaint = true

    Repaint<private>(Query:placement_query, Grid:grid_component):void =
        ClearMarkers()
        # filter pass first, spawn pass second, so the failable filter is not in the same for as the scene mutation
        Cells := for:
            CellF := 0..(Grid.CellsForward - 1)
            CellL := 0..(Grid.CellsLeft - 1)
            CellValidFor[Query, Grid, CellF, CellL]
        do:
            (CellF, CellL)
        set Markers = for (Cell : Cells) { SpawnMarker(Grid, Cell(0), Cell(1)) }

    ClearMarkers<private>():void =
        for (M : Markers):
            M.RemoveFromParent()
        set Markers = array{}

    # same restriction checks as confirm, aimed at the cell center; HitEntity is the grid root, not the true hit child
    CellValidFor<private>(Query:placement_query, Grid:grid_component, CellF:int, CellL:int)<transacts><decides>:void =
        GridRot := Grid.Entity.GetGlobalTransform().Rotation
        Synthetic := placement_proposal{
            Transform := (LUF:)transform{
                Translation := Grid.CellCenter(CellF, CellL),
                Rotation    := GridRot,
                Scale       := Query.PlacableEntity.GetGlobalTransform().Scale
            },
            HitNormal := option{GridRot.GetUpAxis()},
            HitEntity := option{Grid.Entity}
        }
        for (R : Query.Restrictions):
            R.CanPlaceAt[Query, Synthetic]

    SpawnMarker<private>(Grid:grid_component, CellF:int, CellL:int):entity =
        M := TilePrefab{}
        Grid.Entity.AddEntities(array{M})
        GridXform := Grid.Entity.GetGlobalTransform()
        Up := GridXform.Rotation.GetUpAxis()
        M.SetGlobalTransform((LUF:)transform{
            Translation := Grid.CellCenter(CellF, CellL) + Up * MarkerUp,
            Rotation    := GridXform.Rotation,
            # authored scale as world scale; reading global scale after attach picks up the board's scale (12x board made 12x tiles)
            Scale       := M.GetLocalTransform().Scale
        })
        M
