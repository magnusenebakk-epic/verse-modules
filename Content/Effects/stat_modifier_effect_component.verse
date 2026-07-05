using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Stats }


stat_modifier_effect_component<public> := class<final_super>(component):

    @editable
    Modifiers<public>:[]stat_modifier = array{}

    var<private> StackSub<private>:?cancelable = false

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        ApplyForCurrentStacks()
        if (StC := Entity.GetComponent[stackable_component]):
            set StackSub = option{StC.ChangeStackSizeEvent.Subscribe(OnStackChanged)}

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        if (StackSub?.Cancel()) { set StackSub = false }
        if (StatsComponent := FindStatsComponent[]):
            StatsComponent.RemoveModifiersFrom(Entity)

    OnStackChanged<private>(Result:change_stack_size_result):void =
        ReapplyForStacks(Result.CurrentStackSize)

    ApplyForCurrentStacks<private>():void =
        Stacks := if (StC := Entity.GetComponent[stackable_component]) then StC.StackSize else 1
        ReapplyForStacks(Stacks)

    ReapplyForStacks<private>(Stacks:int):void =
        if (StatsComponent := FindStatsComponent[]):
            StatsComponent.RemoveModifiersFrom(Entity)
            var I:int = 0
            loop:
                if (I >= Stacks). break
                for (M : Modifiers):
                    StatsComponent.AddModifier(M, Entity)
                set I = I + 1

    FindStatsComponent<private>()<transacts><decides>:stats_component =
        Parent := Entity.GetParent[]
        Parent.GetComponent[stats_component]
