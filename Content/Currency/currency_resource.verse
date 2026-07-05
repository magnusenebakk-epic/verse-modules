using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }

using { Abilities }


currency_resource<public> := class(ability_resource):

    @editable
    CurrencyType<public>:subtype(currency_value) = currency_value

    CanAfford<override>(Activator:agent, Amount:float):logic =
        if:
            Holder := Activator.GetStatsHolderEntity[]
            Wallet := Holder.GetComponent[wallet_component]
            FloorAmount := Floor[Amount] or 0
            Have := Wallet.GetAmount[CurrencyType]
            Have >= FloorAmount
        then:
            true
        else:
            false

    Consume<override>(Activator:agent, Amount:float):logic =
        if:
            Holder := Activator.GetStatsHolderEntity[]
            Wallet := Holder.GetComponent[wallet_component]
            FloorAmount := Floor[Amount] or 0
        then:
            Wallet.TrySpend(CurrencyType, FloorAmount)
        else:
            false
