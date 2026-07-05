using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Gameplay.Bases }
using { Gameplay.Currency }
using { Gameplay.Ownership }
using { Gameplay.Unlocks }


# Passive Print probes. Each subscribes to one framework surface and logs
# everything it emits.


# Put on the base root. Logs membership, unlock and value-store traffic.
test_base_probe_component<public> := class<final_super>(component):

    var MemberSubs<private>:[]Concurrency.subscription_task(member_change) = array{}
    var NodeSubs<private>:[]Concurrency.subscription_task(unlock_node_component) = array{}
    var IntSubs<private>:[]Concurrency.subscription_task(unlock_int_change) = array{}
    var FloatSubs<private>:[]Concurrency.subscription_task(unlock_float_change) = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Ownable := Entity.GetComponent[ownable_component]):
            set MemberSubs += array{
                Ownable.MemberAddedEvent.Subscribe(OnMemberAdded),
                Ownable.MemberRemovedEvent.Subscribe(OnMemberRemoved),
                Ownable.MemberInfoChangedEvent.Subscribe(OnMemberInfoChanged)
            }
        if (State := Entity.GetComponent[unlock_state_component]):
            set NodeSubs += array{
                State.NodeUnlockedEvent.Subscribe(OnNodeUnlocked),
                State.NodeResetEvent.Subscribe(OnNodeReset)
            }
            set IntSubs += array{State.IntChangedEvent.Subscribe(OnIntChanged)}
            set FloatSubs += array{State.FloatChangedEvent.Subscribe(OnFloatChanged)}

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : MemberSubs) { S.Cancel() }
        for (S : NodeSubs) { S.Cancel() }
        for (S : IntSubs) { S.Cancel() }
        for (S : FloatSubs) { S.Cancel() }
        set MemberSubs = array{}
        set NodeSubs = array{}
        set IntSubs = array{}
        set FloatSubs = array{}

    OnMemberAdded<private>(C:member_change):void =
        Role := if (C.Info.IsPrimary?) then "PRIMARY" else "co-owner"
        Print("PROBE base: member added ({Role})")

    OnMemberRemoved<private>(C:member_change):void =
        Role := if (C.Info.IsPrimary?) then "PRIMARY" else "co-owner"
        Print("PROBE base: member removed ({Role})")

    OnMemberInfoChanged<private>(C:member_change):void =
        Print("PROBE base: member info changed")

    OnNodeUnlocked<private>(N:unlock_node_component):void =
        if (State := Entity.GetComponent[unlock_state_component]):
            Done := State.UnlockedNodes().Length
            Total := State.AllNodes().Length
            Print("PROBE base: unlocked '{N.Key}' ({Done}/{Total})")

    OnNodeReset<private>(N:unlock_node_component):void =
        Print("PROBE base: reset '{N.Key}'")

    OnIntChanged<private>(C:unlock_int_change):void =
        Print("PROBE base: int '{C.Key}' {C.OldValue} -> {C.NewValue}")

    OnFloatChanged<private>(C:unlock_float_change):void =
        Print("PROBE base: float '{C.Key}' {C.OldValue} -> {C.NewValue}")


# Put next to a wallet_component. Logs every balance change.
test_wallet_probe_component<public> := class<final_super>(component):

    var Subs<private>:[]Concurrency.subscription_task(currency_change) = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (W := Entity.GetComponent[wallet_component]):
            for (C : W.Currencies):
                set Subs += array{C.ChangedEvent.Subscribe(OnChanged)}

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : Subs) { S.Cancel() }
        set Subs = array{}

    OnChanged<private>(Change:currency_change):void =
        Print("PROBE wallet: {Change.Currency.Name} {Change.OldAmount} -> {Change.NewAmount}")


# Put next to an unlock_purchase_interactable_component. Logs outcomes.
test_purchase_probe_component<public> := class<final_super>(component):

    var Subs<private>:[]Concurrency.subscription_task(agent) = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Pad := Entity.GetComponent[unlock_purchase_interactable_component]):
            set Subs += array{
                Pad.PurchasedEvent.Subscribe(OnPurchased),
                Pad.DeniedEvent.Subscribe(OnDenied)
            }

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : Subs) { S.Cancel() }
        set Subs = array{}

    OnPurchased<private>(Agent:agent):void =
        Print("PROBE purchase: PURCHASED")

    OnDenied<private>(Agent:agent):void =
        Print("PROBE purchase: DENIED (owner gate / requirements / commit)")
