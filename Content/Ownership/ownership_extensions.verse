using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# Nearest ownable_component walking up from Entity (inclusive). Nearest wins
# on purpose: a nested ownable overrides its base's ownership below it.
(Entity:entity).FindOwnable<public>()<transacts><decides>:ownable_component =
    first{E:Entity.FindAncestorComponents(ownable_component)}


# Agent is a member (primary or co-owner) of the nearest ownable.
(Agent:agent).OwnsEntity<public>(Entity:entity)<transacts><decides>:void =
    Entity.FindOwnable[].IsOwner[Agent]
