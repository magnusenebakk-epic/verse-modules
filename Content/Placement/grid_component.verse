using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


# Rectangular cell field on the entity's Forward/Left plane; pure rotation-aware world-to-cell math.
# Occupancy lives in grid_occupancy_component, kept separate so decorative snap-grids carry no state.
grid_component<public> := class<final_super>(component):

    @editable
    var CellSize<public>:float = 100.0

    @editable
    var CellsForward<public>:int = 10

    @editable
    var CellsLeft<public>:int = 10

    # Local offset to the field's min corner; rotates with the entity, world-size units, entity scale not applied.
    @editable
    var OriginOffset<public>:(LUF:)vector3 = (LUF:)vector3{Forward := 0.0, Left := 0.0, Up := 0.0}

    # Cell indices (Forward, Left) for a world position. Fails off the grid.
    CellAt<public>(WorldPos:vector3)<transacts><decides>:tuple(int, int) =
        Rot := Entity.GetGlobalTransform().Rotation
        Origin := Entity.GetGlobalTransform().Translation + OriginOffset * Rot
        Local := (WorldPos - Origin) * Rot.Invert()
        IndexF := Floor[Local.Forward / CellSize]
        IndexL := Floor[Local.Left / CellSize]

        IndexF >= 0
        IndexF < CellsForward
        IndexL >= 0
        IndexL < CellsLeft

        (IndexF, IndexL)

    # World-space center of a cell. Total, so callers must pass in-range indices.
    CellCenter<public>(CellF:int, CellL:int)<transacts>:vector3 =
        Rot := Entity.GetGlobalTransform().Rotation
        Origin := Entity.GetGlobalTransform().Translation + OriginOffset * Rot
        Origin + (LUF:)vector3{
            Forward := ((1.0 * CellF) + 0.5) * CellSize,
            Left    := ((1.0 * CellL) + 0.5) * CellSize,
            Up      := 0.0
        } * Rot

    Snap<public>(WorldPos:vector3)<transacts><decides>:vector3 =
        Cell := CellAt[WorldPos]
        CellCenter(Cell(0), Cell(1))


FindGridComponent<public>(InEntity:entity)<transacts><decides>:grid_component =
    InEntity.GetComponent[grid_component] or first{E:InEntity.FindAncestorComponents(grid_component)}
