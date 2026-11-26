using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Damage }


# Marks an entity as a base to defend; leak damage goes to the sibling
# entity_health_component. Just a marker plus helpers.
td_base_component<public> := class<final_super>(component):

    # Lanes this base takes leaks for (indices into the sorted lanes); empty = every lane.
    @editable
    CoveredLanes<public>:[]int = array{}

    Covers<public>(LaneIndex:int)<transacts><decides>:void =
        CoveredLanes.Length = 0 or first (C : CoveredLanes, C = LaneIndex) { C }

    ApplyLeak<public>(Amount:float):void =
        if (Health := Entity.GetComponent[entity_health_component]):
            Health.TakeDamage(Amount, false)

    IsAlive<public>()<transacts><decides>:void =
        Health := Entity.GetComponent[entity_health_component]
        Health.IsAlive[]
