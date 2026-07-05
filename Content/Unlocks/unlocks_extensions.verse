using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# Walk up the entity tree to the nearest unlock_state_component (includes
# Entity itself).
(Entity:entity).FindUnlockState<public>()<transacts><decides>:unlock_state_component =
    first{S:Entity.FindAncestorComponents(unlock_state_component)}
