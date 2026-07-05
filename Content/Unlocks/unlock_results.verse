using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# TryUnlock outcome types. Mirrors craft_results.

unlock_success<public> := class:
    Node<public>:unlock_node_component


unlock_int_change<public> := class:
    Key<public>:string
    OldValue<public>:int
    NewValue<public>:int


unlock_float_change<public> := class:
    Key<public>:string
    OldValue<public>:float
    NewValue<public>:float


unlock_error<public> := class<computes>:

unknown_key_unlock_error<public> := class<concrete><computes>(unlock_error){}

already_unlocked_error<public> := class<concrete><computes>(unlock_error){}

# Some requirement (dependency or otherwise) isn't satisfied.
requirements_unsatisfied_error<public> := class<computes>(unlock_error):
    Failed<public>:[]unlock_requirement = array{}

# Requirements passed the check but a Commit failed (e.g. wallet raced empty).
commit_failed_unlock_error<public> := class<concrete><computes>(unlock_error){}
