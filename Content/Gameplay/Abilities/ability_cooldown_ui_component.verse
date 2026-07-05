using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }

using { Gameplay.Abilities.UI }


ability_cooldown_ui_component<public> := class<final_super>(component):

    var<private> UIByPlayer<private>:[player]ability_cooldown_ui = map{}

    OnSimulate<override>()<suspends>:void =
        if (ItemComp := Entity.GetComponent[item_component]):
            loop:
                Result := ItemComp.ChangeEquippedEvent.Await()
                if (Owner := ResolveOwningPlayer[ItemComp]):
                    NewAbilityUI := GetOrCreate(Owner)
                    if (Result.IsItemEquipped?):
                        NewAbilityUI.Show()
                    else:
                        NewAbilityUI.Hide()

    GetOrCreate<private>(Player:player):ability_cooldown_ui =
        if (Existing := UIByPlayer[Player]):
            Existing
        else:
            New := MakeAbilityCooldownUI(Player, Entity)
            New.Initialize()
            if (set UIByPlayer[Player] = New) {}
            New

    ResolveOwningPlayer<private>(ItemComp:item_component)<transacts><decides>:player =
        Inv := ItemComp.GetParentInventory[]
        Inv.GetOwningPlayer[]
