using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }


# Accepts hits whose target entity or any ancestor carries a grid_component.
grid_component_hit_filter<public> := class<concrete>(hit_filter):
    Accepts<override>(Hit:sweep_hit)<transacts><decides>:void =
        FindGridComponent[Hit.TargetComponent.Entity]


# Rejects hits on entities (or ancestors) with an excluded tag; tag placed towers so sweeps pass through them instead of stacking.
exclude_tags_hit_filter<public> := class<concrete>(hit_filter):
    @editable
    var ExcludedTags<public>:[]subtype(tag) = array{}

    Accepts<override>(Hit:sweep_hit)<transacts><decides>:void =
        not HasExcludedTag[Hit.TargetComponent.Entity]

    HasExcludedTag<private>(HitE:entity)<transacts><decides>:void =
        HitE.ContainsAnyTag[ExcludedTags] or
            first (A : HitE.FindAncestorEntities(entity), A.ContainsAnyTag[ExcludedTags]) { A }
