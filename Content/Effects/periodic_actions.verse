using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }

using { Abilities }
using { Stats }


periodic_action<public> := class<abstract>:
    Tick<public>(Comp:periodic_effect_component):void


damage_periodic_action<public> := class(periodic_action):

    @editable
    (damage_periodic_action:)Damage<public>:float = 0.0

    @editable
    DamageApplier<public>:damage_applier

    Tick<override>(Comp:periodic_effect_component):void =
        if:
            Holder := Comp.Entity.GetParent[]
            TargetPlayer := Holder.GetPlayerOf[]
            Char := TargetPlayer.GetFortCharacter[]
        then:
            Source:?agent = if (SC := Comp.Entity.GetComponent[source_component]) then SC.Source else false
            Scaled:float = if (St := Comp.Entity.GetComponent[stackable_component]) then (damage_periodic_action:)Damage * St.StackSize else (damage_periodic_action:)Damage
            DamageApplier.Apply(Source, TargetPlayer, Char, Scaled, false)


restore_stat_periodic_action<public> := class<concrete>(periodic_action):

    @editable
    StatType<public>:subtype(stat_value) = stat_value

    @editable
    Amount<public>:float = 0.0

    Tick<override>(Comp:periodic_effect_component):void =
        if:
            Holder := Comp.Entity.GetParent[]
            SC := Holder.GetComponent[stats_component]
            Stat := SC.GetStat[StatType]
        then:
            Scaled:float = if (St := Comp.Entity.GetComponent[stackable_component]) then Amount * St.StackSize else Amount
            Stat.Restore(Scaled)
