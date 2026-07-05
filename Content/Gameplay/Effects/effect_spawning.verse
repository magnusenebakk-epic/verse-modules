using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }
using { /Verse.org/Simulation/Tags }

using { Gameplay.Abilities }


SpawnEffectOnTarget<public>(Holder:entity, Prefab:concrete_subtype(effect_base), Source:?agent):?entity =
    Probe := (concrete_subtype(effect_base)(Prefab)){}
    if (Imm := Holder.GetComponent[effect_immunity_component], Imm.IsImmuneTo[Probe]):
        return false
    Holder.AddEntities(array{Probe})
    SrcComp := source_component { Entity := Probe, Source := Source }
    Probe.AddComponents(array{SrcComp})
    if (Stored := Probe.GetComponent[source_component]):
        set Stored.Source = Source
    ResolveStacking(Holder, Probe)
    option{Probe}


TestTransacts()<transacts>:void=
    TestReads()
    return

TestReads()<reads><writes><allocates>:void={}


ResolveStacking<public>(Holder:entity, New:entity):void =
    Rules:?effect_stacking_rules_component = if (R := New.GetComponent[effect_stacking_rules_component]) then option{R} else false
    Mode := if (R := Rules?) then R.Mode else effect_stacking_mode.Stack
    DoRefresh := if (R := Rules?) then R.RefreshOnStack else false
    MatchTagOpt:?subtype(tag) = if (R := Rules?) then R.MatchTag else false

    OptTarget:?entity = FindMatch(Holder, New, MatchTagOpt)

    if (Target := OptTarget?):
        case (Mode):
            effect_stacking_mode.Stack =>
                if:
                    NewSC := New.GetComponent[stackable_component], NewSC.MergeInto[Target]
                    DoRefresh?, Dur := Target.GetComponent[duration_effect_component]
                then:
                    Dur.Refresh()
            effect_stacking_mode.Refresh =>
                if (Dur := Target.GetComponent[duration_effect_component]):
                    Dur.Refresh()
                New.RemoveFromParent()
            effect_stacking_mode.Replace =>
                Target.RemoveFromParent()
            effect_stacking_mode.Ignore =>
                New.RemoveFromParent()


FindMatch<internal>(Holder:entity, New:entity, MatchTagOpt:?subtype(tag))<transacts>:?entity =
    if (TagType := MatchTagOpt?):
        Cands := for:
            Sibling : Holder.FindDescendantEntities(effect_base)
            not (Sibling = New)
            Sibling.ContainsTag[TagType]
        do:
            Sibling
        if (E := Cands[0]) then option{E} else false
    else if (NewSC := New.GetComponent[stackable_component]):
        Cands := for:
            Sibling : Holder.FindDescendantEntities(effect_base)
            not (Sibling = New)
            NewSC.CanMergeInto[Sibling]
        do:
            Sibling
        if (E := Cands[0]) then option{E} else false
    else:
        false
