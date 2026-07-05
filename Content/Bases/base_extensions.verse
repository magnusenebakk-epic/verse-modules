using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }


# Walks up the entity tree to the nearest base_component (includes Entity).
(Entity:entity).FindBase<public>()<transacts><decides>:base_component =
    first{B:Entity.FindAncestorComponents(base_component)}


(InEntity:entity).GetBaseManager<public>()<transacts><decides>:base_manager_component =
    Sim := InEntity.GetSimulationEntity[]
    MgrEntity := first{E:Sim.FindDescendantEntitiesWithTag(base_manager_tag)}
    MgrEntity.GetComponent[base_manager_component]


# The base Agent owns (or co-owns), via the manager registry.
(Agent:agent).GetOwnedBase<public>(Context:entity)<transacts><decides>:base_component =
    Context.GetBaseManager[].GetBaseOf[Agent]
