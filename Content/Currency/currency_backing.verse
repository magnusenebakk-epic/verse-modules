using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }


# Pluggable storage for a currency_value: counter or inventory items.
currency_backing<public> := class<abstract>:
    GetAmount<public>(Holder:entity)<transacts>:int
    Add<public>(Holder:entity, N:int)<transacts><decides>:void
    TrySpend<public>(Holder:entity, N:int)<transacts><decides>:void


# Diablo-style abstract counter.
counter_backing<public> := class<concrete>(currency_backing):

    @editable
    var Amount<public>:int = 0

    GetAmount<override>(Holder:entity)<transacts>:int = Amount

    Add<override>(Holder:entity, N:int)<transacts><decides>:void =
        set Amount = Amount + N

    TrySpend<override>(Holder:entity, N:int)<transacts><decides>:void =
        Amount >= N
        set Amount = Amount - N


# Tarkov / PoE-style: currency lives as stackable items in an inventory_component
# on Holder (or its first descendant carrying one).
item_currency_backing<public> := class<concrete>(currency_backing):

    @editable
    ItemType<public>:subtype(item_component) = item_component

    # Spawned to deposit currency. Should carry ItemType + a stackable_component.
    @editable
    ItemPrefab<public>:?concrete_subtype(entity) = false

    GetAmount<override>(Holder:entity)<transacts>:int =
        if (Inv := FindInventory[Holder]):
            var Total:int = 0
            for (Item : Inv.FindItems(ItemType)):
                set Total = Total + Item.GetComponent[stackable_component].StackSize or 1
            Total
        else:
            0

    Add<override>(Holder:entity, N:int)<transacts><decides>:void =
        N > 0
        Inv := FindInventory[Holder]
        Prefab := ItemPrefab?
        New := Prefab{}
        if (Stack := New.GetComponent[stackable_component]):
            Stack.SetStackSize(N)
        Inv.AddItemDistribute(New, ?AllowMergeItems := true).GetSuccess[]

    TrySpend<override>(Holder:entity, N:int)<transacts><decides>:void =
        Inv := FindInventory[Holder]
        Have := GetAmount(Holder)
        Have >= N
        ConsumeFromInventory[Inv, N]

    # Mirrors recipe_types.verse:56-72. Caller verifies Have >= Amount up front.
    ConsumeFromInventory<private>(Inv:inventory_component, Amount:int)<transacts><decides>:void =
        var Remaining:int = Amount
        for:
            Item : Inv.FindItems(ItemType)
            Remaining > 0
        do:
            if (Stack := Item.GetComponent[stackable_component]):
                StackSize := Stack.StackSize
                if (StackSize <= Remaining):
                    Inv.RemoveItem(Item).GetSuccess[]
                    set Remaining = Remaining - StackSize
                else:
                    Stack.SetStackSize(StackSize - Remaining)
                    set Remaining = 0
            else:
                Inv.RemoveItem(Item).GetSuccess[]
                set Remaining = Remaining - 1

    FindInventory<private>(Holder:entity)<transacts><decides>:inventory_component =
        if (Inv := Holder.GetComponent[inventory_component]):
            Inv
        else:
            Holder.GetFirstDescendantComponent[inventory_component]
