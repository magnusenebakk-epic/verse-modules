using { /Verse.org/Simulation }


# Keyed by the canonical Owner. Co-owners don't write here.
var UnlocksPersistenceMap<internal>:weak_map(player, persisted_unlock_state) = map{}


persisted_unlock_state<public> := class<final><persistable>:
    Version<public>:int = 0
    UnlockedKeys<public>:[]string = array{}
    # Value stores, written via unlock_state_component.Get/SetInt/Float with
    # namespaced keys. One shared bag per type instead of one weak_map per
    # feature (only 4 persistent weak_maps per island). All fields defaulted
    # so adding more later is a legal schema change.
    Ints<public>:[string]int = map{}
    Floats<public>:[string]float = map{}
