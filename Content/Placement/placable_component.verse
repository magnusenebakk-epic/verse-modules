using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


# Optional per-entity placement overrides on top of the driver's profile: swap the method or extend
# the lists. Entities with no special needs skip it and get placed off the profile alone.
placable_component<public> := class<final_super>(component):

    # Unset = inherit the profile's method.
    @editable
    var MethodOverride<public>:?placement_method = false

    # Appended to the profile's lists.
    @editable
    var ExtraRestrictions<public>:[]placement_restriction = array{}

    @editable
    var ExtraOnPlacedEffects<public>:[]placement_effect = array{}

    @editable
    var ExtraHighlights<public>:[]placement_highlight = array{}

    MakeSession<public>(Player:player, Profile:placement_profile):placement_session =
        placement_session:
            Query := placement_query{
                Player := Player,
                PlacableEntity := Entity,
                Restrictions := Profile.Restrictions + ExtraRestrictions}
            Method := MethodOverride? or Profile.Method
            Highlights := Profile.Highlights + ExtraHighlights
            OnPlacedEffects := Profile.OnPlacedEffects + ExtraOnPlacedEffects


# Session-build entry point for drivers; merges the profile with Target's placable_component when present.
MakePlacementSession<public>(Profile:placement_profile, Player:player, Target:entity):placement_session =
    if (Placable := Target.GetComponent[placable_component]):
        Placable.MakeSession(Player, Profile)
    else:
        Profile.MakeSession(Player, Target)
