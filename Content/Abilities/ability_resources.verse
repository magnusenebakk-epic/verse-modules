using { /Verse.org/Simulation }


# Pluggable cost source for active abilities.
ability_resource<public> := class<abstract>:
    CanAfford<public>(Activator:agent, Amount:float):logic
    Consume<public>(Activator:agent, Amount:float):logic

using { /Verse.org/Simulation/Tags }

target_tag := class(tag){}

ability_cost<public> := class:

    @editable
    Resource<public>:ability_resource

    @editable
    Amount<public>:float = 0.0

    @editable
    TagT : subtype(tag) = target_tag

    CanAfford<public>(Activator:agent):logic =
        Resource.CanAfford(Activator, Amount)

    Consume<public>(Activator:agent):logic =
        Resource.Consume(Activator, Amount)

    

