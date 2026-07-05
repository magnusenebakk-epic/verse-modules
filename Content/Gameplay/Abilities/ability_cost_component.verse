using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


ability_cost_component<public> := class<final_super>(component):

    @editable
    Cost<public>:ability_cost

    CanAfford<public>(Activator:agent):logic =
        Cost.CanAfford(Activator)

    Consume<public>(Activator:agent):logic =
        Cost.Consume(Activator)
