using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# Supplies the entity placed on confirm; takes the query so item and non-item drivers share providers.
placement_target_provider<public> := class<abstract>:
    ProvideTarget<public>(Query:placement_query):entity


direct_placement_target_provider<public> := class<concrete>(placement_target_provider):
    ProvideTarget<override>(Query:placement_query):entity =
        Query.PlacableEntity


prefab_placement_target_provider<public> := class<concrete>(placement_target_provider):

    @editable
    WorldPrefab<public>:concrete_subtype(entity) = entity

    ProvideTarget<override>(Query:placement_query):entity =
        WorldPrefab{}
