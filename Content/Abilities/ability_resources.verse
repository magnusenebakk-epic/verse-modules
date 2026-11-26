using { /Verse.org/Simulation }


# Pluggable cost source for cost_gate.
ability_resource<public> := class<abstract>:
    CanAfford<public>(Activator:agent, Amount:float):logic
    Consume<public>(Activator:agent, Amount:float):logic
