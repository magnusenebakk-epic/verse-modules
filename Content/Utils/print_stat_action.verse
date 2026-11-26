using { /Verse.org/Simulation }
using { /Verse.org/SceneGraph }
using { Stats }
using { Abilities }


# Debug use_action: prints the current value of StatType on the use's attributed agent.
print_stat_action<public> := class(use_action):

    @editable
    StatType<public>:subtype(stat_value) = stat_value

    Execute<override>(EffectEntity:entity, Holder:entity):void =
        if:
            Activator := EffectEntity.GetUseAttribution[Holder]
            StatsHolder := Activator.GetStatsHolderEntity[]
            StatsComp := StatsHolder.GetComponent[stats_component]
            Cur := StatsComp.GetStat[StatType]
        then:
            Print("Current {Cur.Name}: {Cur.GetCurrent()}")
