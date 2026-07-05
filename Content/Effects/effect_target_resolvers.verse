using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Itemization }


effect_target_resolver<public> := class<abstract>:
    GetTarget<public>(EffectComponent:passive_effect_component)<decides><transacts>:entity
    AwaitNextChange<public>(EffectComponent:passive_effect_component)<suspends>:void


while_equipped_resolver<public> := class<concrete>(effect_target_resolver):

    var<private> Equipped<private>:logic = false

    GetTarget<override>(EC:passive_effect_component)<transacts><decides>:entity =
        Equipped?
        ItemComp := EC.Entity.GetComponent[item_component]
        Inv := ItemComp.GetParentInventory[]
        P := Inv.GetOwningPlayer[]
        P.GetStatsHolderEntity[]

    AwaitNextChange<override>(EC:passive_effect_component)<suspends>:void =
        if (ItemComp := EC.Entity.GetComponent[item_component]):
            Result := ItemComp.ChangeEquippedEvent.Await()
            set Equipped = Result.IsItemEquipped


while_in_inventory_resolver<public> := class<concrete>(effect_target_resolver):

    GetTarget<override>(EC:passive_effect_component)<transacts><decides>:entity =
        ItemComp := EC.Entity.GetComponent[item_component]
        Inv := ItemComp.GetParentInventory[]
        P := Inv.GetOwningPlayer[]
        P.GetStatsHolderEntity[]

    AwaitNextChange<override>(EC:passive_effect_component)<suspends>:void =
        if (ItemComp := EC.Entity.GetComponent[item_component]):
            ItemComp.ChangeEquippedEvent.Await()


while_equipped_on_character_resolver<public> := class<concrete>(effect_target_resolver):

    var<private> Equipped<private>:logic = false

    GetTarget<override>(EC:passive_effect_component)<transacts><decides>:entity =
        Equipped?
        ItemComp := EC.Entity.GetComponent[item_component]
        Inv := ItemComp.GetParentInventory[]
        P := Inv.GetOwningPlayer[]
        Char := P.GetFortCharacter[]
        CharE := Char.GetEntity[]

    AwaitNextChange<override>(EC:passive_effect_component)<suspends>:void =
        if (ItemComp := EC.Entity.GetComponent[item_component]):
            race:
                AwaitEquipChange(ItemComp)
                AwaitCharSwap(EC)

    AwaitEquipChange<private>(ItemComp:item_component)<suspends>:void =
        Result := ItemComp.ChangeEquippedEvent.Await()
        set Equipped = Result.IsItemEquipped

    AwaitCharSwap<private>(EC:passive_effect_component)<suspends>:void =
        if:
            ItemComp := EC.Entity.GetComponent[item_component]
            Inv := ItemComp.GetParentInventory[]
            OwningPlayer := Inv.GetOwningPlayer[]
            PEM := EC.Entity.GetPlayerEventManager[]
        then:
            loop:
                Signaled := PEM.PlayerRespawnedEvent.Await()
                if (Signaled = OwningPlayer):
                    return
        else:
            Sleep(Inf)
