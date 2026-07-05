using { /Verse.org/Input }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }

ability_component<public> := class<final_super>(component):

    @editable
    var Trigger<public>:?input_action(logic) = false

    @editable
    var Action<public>:ability_action
