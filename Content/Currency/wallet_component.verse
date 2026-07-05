using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


wallet_component<public> := class<final_super>(component):

    @editable
    Currencies<public>:[]currency_value = array{}

    GetCurrency<public>(currency_type:castable_subtype(currency_value))<reads><decides>:currency_type =
        for (C : Currencies, T := currency_type[C]) { T }[0]

    GetAmount<public>(currency_type:castable_subtype(currency_value))<transacts><decides>:int =
        GetCurrency[currency_type].GetAmount(Entity)

    Add<public>(currency_type:castable_subtype(currency_value), N:int):logic =
        if (C := GetCurrency[currency_type]):
            C.Add(Entity, N)
        else:
            false

    TrySpend<public>(currency_type:castable_subtype(currency_value), N:int):logic =
        if (C := GetCurrency[currency_type]):
            C.TrySpend(Entity, N)
        else:
            false

    # Transactional spend with no event, usable inside rollback contexts.
    # Pair with NotifySpent after the enclosing transaction commits.
    Spend<public>(currency_type:castable_subtype(currency_value), N:int)<transacts><decides>:void =
        GetCurrency[currency_type].Spend[Entity, N]

    NotifySpent<public>(currency_type:castable_subtype(currency_value), N:int):void =
        if (C := GetCurrency[currency_type]):
            C.NotifySpent(Entity, N)
