using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


grid_claim<public> := class:
    Occupant<public>:entity
    CellF<public>:int
    CellL<public>:int


# Tracks who occupies which cell; when absent the restriction and tile painter pass everything.
# One claim per occupant per grid, Claim replaces the previous cell; racing confirms may briefly double-claim, both release independently.
grid_occupancy_component<public> := class<final_super>(component):

    ChangedEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    var<private> Claims<private>:[]grid_claim = array{}

    AllClaims<public>()<reads>:[]grid_claim =
        Claims

    IsFree<public>(CellF:int, CellL:int)<reads><decides>:void =
        not ClaimOn[CellF, CellL]

    # Free, or held by Placable itself, so a relocating entity can re-pick its own tile.
    AllowsFor<public>(CellF:int, CellL:int, Placable:entity)<reads><decides>:void =
        not OtherClaimOn[CellF, CellL, Placable]

    Claim<public>(CellF:int, CellL:int, Occupant:entity):void =
        # re-claiming your own cell is a no-op; a fresh placement fires both the begin-sim claim and the effect's explicit claim
        if (C := ClaimOn[CellF, CellL], C.Occupant = Occupant). return
        Others := for (C : Claims, not (C.Occupant = Occupant)) { C }
        set Claims = Others + array{grid_claim{Occupant := Occupant, CellF := CellF, CellL := CellL}}
        Print("grid: cell ({CellF},{CellL}) claimed, {Claims.Length} total")
        ChangedEvent.Signal(())

    Release<public>(Occupant:entity):void =
        Remaining := for (C : Claims, not (C.Occupant = Occupant)) { C }
        if (Remaining.Length < Claims.Length):
            set Claims = Remaining
            Print("grid: claim released, {Claims.Length} remain")
            ChangedEvent.Signal(())

    ClaimOn<private>(CellF:int, CellL:int)<reads><decides>:grid_claim =
        first (C : Claims, C.CellF = CellF, C.CellL = CellL) { C }

    OtherClaimOn<private>(CellF:int, CellL:int, Placable:entity)<reads><decides>:grid_claim =
        first (C : Claims, C.CellF = CellF, C.CellL = CellL, not (C.Occupant = Placable)) { C }


# Link from a placed entity back to its occupancy; added by grid_occupy_effect, or in-editor on pre-placed
# entities which claim their cell at begin-simulation. Releases on removal, so a destroyed tower frees its tile.
grid_occupant_component<public> := class<final_super>(component):

    var<private> Home<private>:?grid_occupancy_component = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (not Home?, T := FindHomeAt[Entity.GetGlobalTransform().Translation]):
            set Home = option{T(0)}
            T(0).Claim(T(1)(0), T(1)(1), Entity)

    # Claim already replaced any old cell on the same grid; releasing only matters when the occupant moved across grids.
    MovedTo<public>(NewHome:grid_occupancy_component):void =
        if (Old := Home?, not (Old.Entity = NewHome.Entity)):
            Old.Release(Entity)
        set Home = option{NewHome}

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        if (H := Home?):
            H.Release(Entity)
            set Home = false

    # Grid whose cell field contains Pos and that has an occupancy; grids don't overlap, first match wins.
    FindHomeAt<private>(Pos:vector3)<transacts><decides>:tuple(grid_occupancy_component, tuple(int, int)) =
        Sim := Entity.GetSimulationEntity[]
        Found := for:
            G : Sim.FindDescendantComponents(grid_component)
            Occ := G.Entity.GetComponent[grid_occupancy_component]
            Cell := G.CellAt[Pos]
        do:
            (Occ, Cell)
        Found[0]


# Fails when the proposed cell is claimed by someone else; proposals with no grid or an untracked one pass.
grid_cell_free_restriction<public> := class<concrete>(placement_restriction):
    CanPlaceAt<override>(Query:placement_query, Proposal:placement_proposal)<transacts><decides>:void =
        if:
            HitEnt := Proposal.HitEntity?
            Grid := FindGridComponent[HitEnt]
            Occ := Grid.Entity.GetComponent[grid_occupancy_component]
            Cell := Grid.CellAt[Proposal.Transform.Translation]
        then:
            Occ.AllowsFor[Cell(0), Cell(1), Query.PlacableEntity]


# The write side: adds or updates the placed entity's grid_occupant_component and claims the landed cell.
grid_occupy_effect<public> := class<concrete>(placement_effect):
    OnPlaced<override>(Placed:entity, Query:placement_query, Proposal:placement_proposal):void =
        if:
            HitEnt := Proposal.HitEntity?
            Grid := FindGridComponent[HitEnt]
            Occ := Grid.Entity.GetComponent[grid_occupancy_component]
            Cell := Grid.CellAt[Proposal.Transform.Translation]
        then:
            Occupant := EnsureOccupant(Placed)
            Occupant.MovedTo(Occ)
            Occ.Claim(Cell(0), Cell(1), Placed)

    EnsureOccupant<private>(Placed:entity):grid_occupant_component =
        if (Existing := Placed.GetComponent[grid_occupant_component]):
            Existing
        else:
            New := grid_occupant_component{Entity := Placed}
            Placed.AddComponents(array{New})
            New
