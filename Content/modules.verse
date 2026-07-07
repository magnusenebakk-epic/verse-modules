Algorithms<public> := module:
# DataStructures/ folder holds ALL parametrics (interfaces at folder scope,
# nested Containers + Containers.Ops declared in data_structures.verse).
# None may sit at the content root: a module hosting parametric definitions
# gets member resolution poisoned for its other members (3502/3506).
# "Collections" is unusable as a folder name (reserved by UE for asset
# collections; Content/Collections is the editor's, not a Verse module).
DataStructures<public> := module:
Chess<public> := module:
Placement<public> := module:
Script<public> := module:
Stats<public> := module:
Abilities<public> := module:
    (Abilities:)UI<public> := module:
Damage<public> := module:
Effects<public> := module:
    (Effects:)UI<public> := module:
Currency<public> := module:
Utils<public> := module:
Crafting<public> := module:
InventoryDisplay<public> := module:
Ownership<public> := module:
Bases<public> := module:
Unlocks<public> := module:
Testing<public> := module:
