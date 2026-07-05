using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }


base_manager_tag<public> := class(tag){}


# Default assignment policy: one base per player, first unclaimed wins.
# Releases the base when the owner leaves. Tag the entity with
# base_manager_tag so extensions can find it.
#
# Bases are discovered from descendants unless listed in Bases. For custom
# policies (team bases, claim pads etc) call base_component.Claim/Release
# directly.
base_manager_component<public> := class<final_super>(component):

    @editable
    (base_manager_component:)Bases<public>:[]entity = array{}

    # Off = claim happens elsewhere (e.g. a claim pad); the manager still
    # tracks GetBaseOf and releases on leave.
    @editable
    AutoAssign<public>:logic = true

    var<private> ManagedBases<private>:[]base_component = array{}
    var<private> Subscriptions<private>:[]Concurrency.subscription_task(player) = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set ManagedBases = FindManagedBases()
        if (PM := Entity.GetPlayerManager[]):
            set Subscriptions += array{
                PM.PlayerReadyEvent.Subscribe(OnPlayerReady),
                PM.PlayerLeavingEvent.Subscribe(OnPlayerLeaving)
            }

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : Subscriptions):
            S.Cancel()
        set Subscriptions = array{}

    GetBaseOf<public>(A:agent)<transacts><decides>:base_component =
        first (B : ManagedBases, B.IsOwner[A]) { B }

    OnPlayerReady<private>(Player:player):void =
        if (AutoAssign?, not GetBaseOf[Player]):
            if (B := FirstUnclaimed[]):
                Claimed := B.Claim(Player) # signals, can't call inside if
                if (not Claimed?):
                    Print("base_manager: claim failed for a ready player")
            else:
                Print("base_manager: no unclaimed base available")

    OnPlayerLeaving<private>(Player:player):void =
        if (B := GetBaseOf[Player]):
            B.Release()

    FirstUnclaimed<private>()<transacts><decides>:base_component =
        first (B : ManagedBases, not B.IsClaimed[]) { B }

    FindManagedBases<private>():[]base_component =
        Listed := for (E : (base_manager_component:)Bases, B := E.GetComponent[base_component]) { B }
        if (Listed.Length > 0):
            Listed
        else:
            for (B : Entity.FindDescendantComponents(base_component)) { B }
