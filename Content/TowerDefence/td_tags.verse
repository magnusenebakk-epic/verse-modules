using { /Verse.org/Simulation/Tags }


# Identity tags: enemy/tower if the entity carries the tag. tower_tag also
# feeds the placement aim blocklist (exclude_tags_hit_filter).
td_enemy_tag<public> := class(tag){}
tower_tag<public> := class(tag){}

# Marks the tower sub-entity whose mesh is the targeting zone (overlap_targeter).
target_zone_tag<public> := class(tag){}
