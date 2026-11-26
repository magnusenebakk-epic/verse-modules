using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Abilities }
using { /Fortnite.com/Abilities }


# The project ability base: Epic's template ability plus composable requirement and behavior
# lists. Charter: this class is configuration only - Gates (whether a use may happen), Actions
# (what it does), and the CanUse override. Cosmetics belong in timeline elements.
gated_ability<public> := class<concrete><castable>(fort_template_ability(ability_context, fort_template_ability_effect)):

    @editable
    Gates<public>:[]ability_gate = array{}

    # executed by the hub on the BeginUse edge, after the gates commit
    @editable
    Actions<public>:[]use_action = array{}

    # the native base declares this without a default; a concrete subclass must supply one
    var ActiveEffects<override>:[]fort_template_ability_effect = array{}

    CanUse<override>(AbilityEffectParent:entity, AbilityContext:ability_context)<decides><reads>:void =
        Passing := for (G : Gates, G.CanPass[AbilityContext]) { G }
        Passing.Length = Gates.Length
        (super:)CanUse[AbilityEffectParent, AbilityContext]

    # called by manual callers (the hub's Fire); the native item path builds its context natively
    MakeContext<override>()<transacts>:ability_context =
        ability_context{}

    # native Use constructs the effect through this factory on every path
    MakeAbility<override>()<transacts>:fort_template_ability_effect =
        fort_template_ability_effect{}
