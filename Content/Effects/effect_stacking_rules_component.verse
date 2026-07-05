using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }

effect_stacking_mode<public> := enum:
    Stack
    Refresh
    Replace
    Ignore


effect_stacking_rules_component<public> := class<final_super>(component):

    @editable
    Mode<public>:effect_stacking_mode = effect_stacking_mode.Stack

    @editable
    RefreshOnStack<public>:logic = false

    @editable
    MatchTag<public>:?subtype(tag) = false
