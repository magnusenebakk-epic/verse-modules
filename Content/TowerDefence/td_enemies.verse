# The three demo enemies: td_npc_behavior variants with different defaults.
# Character Definitions pick the class; attack kits are prefabs per definition.


# Slow, tanky, hits hard; give it the MeleeAttackKit prefab so it attacks towers.
tank_enemy_behavior<public> := class(td_npc_behavior):
    var MaxHealth<override>:float = 400.0
    var SpeedMultiplier<override>:float = 0.5
    var LeakDamage<override>:float = 5.0
    var UseRunningMovement<override>:logic = false


# Fast and fragile runner; never attacks (no attack kit on its definition).
fast_enemy_behavior<public> := class(td_npc_behavior):
    var MaxHealth<override>:float = 40.0
    var SpeedMultiplier<override>:float = 2.0
    var LeakDamage<override>:float = 1.0


# Baseline enemy, named so wave data can refer to it.
normal_enemy_behavior<public> := class(td_npc_behavior){}
