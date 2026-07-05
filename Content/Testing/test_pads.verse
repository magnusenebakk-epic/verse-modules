using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }

using { Bases }
using { Currency }
using { Ownership }


# Tester pads for the Bases/Ownership/Unlocks framework. Each pad is one
# framework operation plus a Print. Set up interaction shapes in UEFN as
# usual.


# Claims the surrounding base if it's free and you don't have one.
test_claim_pad_component<public> := class<final_super>(basic_interactable_component):

    var Subscription<private>:?cancelable = false

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        Enable()

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        Disable()

    Enable<override>():void =
        (super:)Enable()
        if (not Subscription?):
            set Subscription = option{SucceededEvent.Subscribe(OnInteract)}

    Disable<override>():void =
        (super:)Disable()
        if (Subscription?.Cancel()):
            set Subscription = false

    OnInteract<private>(Agent:agent):void =
        if:
            Base := Entity.FindBase[]
            not Base.IsClaimed[]
            Mgr := Entity.GetBaseManager[]
            not Mgr.GetBaseOf[Agent]
        then:
            Claimed := Base.Claim(Agent) # signals, can't call inside if
            if (Claimed?):
                Print("TEST claim: base claimed")
        else:
            Print("TEST claim: denied (claimed already, or you own one)")


# Primary owner interacts to release: saves progression, resets nodes,
# despawns unlocked prefabs, base claimable again. The in-session
# persistence test switch.
test_release_pad_component<public> := class<final_super>(basic_interactable_component):

    var Subscription<private>:?cancelable = false

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        Enable()

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        Disable()

    Enable<override>():void =
        (super:)Enable()
        if (not Subscription?):
            set Subscription = option{SucceededEvent.Subscribe(OnInteract)}

    Disable<override>():void =
        (super:)Disable()
        if (Subscription?.Cancel()):
            set Subscription = false

    OnInteract<private>(Agent:agent):void =
        if:
            Base := Entity.FindBase[]
            Ownable := Base.GetOwnable[]
            Ownable.IsPrimaryOwner[Agent]
        then:
            Base.Release()
            Print("TEST release: base released (progress saved)")


# Non-member interacts to join as co-owner. Primary owner interacts to
# clear all co-owners.
test_coowner_pad_component<public> := class<final_super>(basic_interactable_component):

    var Subscription<private>:?cancelable = false

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        Enable()

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        Disable()

    Enable<override>():void =
        (super:)Enable()
        if (not Subscription?):
            set Subscription = option{SucceededEvent.Subscribe(OnInteract)}

    Disable<override>():void =
        (super:)Disable()
        if (Subscription?.Cancel()):
            set Subscription = false

    OnInteract<private>(Agent:agent):void =
        if:
            Base := Entity.FindBase[]
            Ownable := Base.GetOwnable[]
            Ownable.IsOwned[]
        then:
            if (Ownable.IsPrimaryOwner[Agent]):
                for (CO : Ownable.CoOwners()):
                    Ownable.RemoveCoOwner(CO)
                Print("TEST coowner: co-owners cleared")
            else if (not Ownable.IsOwner[Agent]):
                Added := Ownable.AddCoOwner(Agent) # signals, hoisted
                if (Added?):
                    Print("TEST coowner: joined as co-owner")


# Grants Amount of CurrencyType to whoever interacts. Test-funds faucet.
test_currency_grant_pad_component<public> := class<final_super>(basic_interactable_component):

    @editable
    CurrencyType<public>:subtype(currency_value) = currency_value

    @editable
    Amount<public>:int = 10

    var Subscription<private>:?cancelable = false

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        Enable()

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        Disable()

    Enable<override>():void =
        (super:)Enable()
        if (not Subscription?):
            set Subscription = option{SucceededEvent.Subscribe(OnInteract)}

    Disable<override>():void =
        (super:)Disable()
        if (Subscription?.Cancel()):
            set Subscription = false

    OnInteract<private>(Agent:agent):void =
        if:
            Holder := Agent.GetStatsHolderEntity[]
            Wallet := Holder.GetComponent[wallet_component]
        then:
            Added := Wallet.Add(CurrencyType, Amount) # signals, hoisted
            if (not Added?):
                Print("TEST grant: wallet has no matching currency")
