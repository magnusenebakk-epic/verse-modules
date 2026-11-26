using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


# lane_traveler for NPC enemies. NPC nav isn't deterministic, so progress is
# derived on demand by projecting the NPC position onto its current segment.
npc_lane_traveler<public> := class(lane_traveler):
    Lane<public>:lane_component
    CharEntity<public>:entity

    var<private> Segment<private>:int = 0
    var<private> LastProgress<private>:float = 0.0

    SetSegment<public>(I:int):void =
        set Segment = I

    GetLaneProgress<override>()<transacts>:float =
        Pos := CharEntity.GetGlobalTransform().Translation
        if (P := Lane.ProgressOnSegment[Segment, Pos]):
            set LastProgress = P
            P
        else:
            # last good value, never 0.0, which would invert progress ordering
            LastProgress
