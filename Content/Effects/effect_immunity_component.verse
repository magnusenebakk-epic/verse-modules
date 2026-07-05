using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }


effect_immunity_component<public> := class<final_super>(component):

    @editable
    ImmuneTags<public>:[]subtype(tag) = array{}

    IsImmuneTo<public>(EffectE:entity)<reads><decides>:void =
        Matches := for (T : ImmuneTags, EffectE.ContainsTag[T]) { T }
        Matches.Length > 0
