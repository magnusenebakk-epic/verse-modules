# Directory-implicit modules: each Content/ folder with Verse code needs an entry before `using { Name }` works.
# Don't put parametric definitions in a module that hosts anything else; it breaks member resolution (compiler bugs 3502/3506).
# That's why DataStructures/ holds ALL parametrics (interfaces at folder scope, nested Containers + Containers.Ops in data_structures.verse).
# Missing on purpose: "Collections" is UE-reserved (asset collections), and UI is referenced by its full project path
# (e.g. /invaliddomain/MobileGamesTD2/UI); update those `using` lines to your project's path when copying modules in.

Algorithms<public> := module:
DataStructures<public> := module:
Chess<public> := module:
Script<public> := module:
Stats<public> := module:
Abilities<public> := module:
    (Abilities:)UI<public> := module:
Damage<public> := module:
Effects<public> := module:
    (Effects:)UI<public> := module:
Placement<public> := module:
TowerDefence<public> := module:
Currency<public> := module:
Utils<public> := module:
Crafting<public> := module:
InventoryDisplay<public> := module:
Ownership<public> := module:
Bases<public> := module:
Unlocks<public> := module:
Testing<public> := module:
