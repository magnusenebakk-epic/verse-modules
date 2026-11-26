using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# Walk-up relocation: interacting with the sibling interactable runs a world session on this entity.
# The interactable is disabled while placing so a second player can't grab a moving entity.
placement_interactable_component<public> := class<final_super>(component):

    @editable
    Profile<public>:placement_profile = placement_profile{}

    PlacedEvent<public>:Concurrency.subscribable_event(entity) =
        Concurrency.subscribable_event(entity){}

    CancelledEvent<public>:Concurrency.subscribable_event(player) =
        Concurrency.subscribable_event(player){}

    var<private> Active<private>:?placement_session = false

    Confirm<public>():logic =
        if (S := Active?):
            S.RequestConfirm()
            true
        else:
            false

    Cancel<public>():logic =
        if (S := Active?):
            S.RequestCancel()
            true
        else:
            false

    OnSimulate<override>()<suspends>:void =
        if (Interactable := Entity.GetComponent[interactable_component]):
            Sub := Interactable.SucceededEvent.Subscribe(NullCallback) # workaround, interact events don't fire with .Await alone
            defer:
                Sub.Cancel()
            loop:
                Agent : agent = Interactable.SucceededEvent.Await()
                if (Player := player[Agent]):
                    Interactable.Disable()
                    RelocateRound(Player)
                    Interactable.Enable()

    RelocateRound<private>(Player:player)<suspends>:void =
        Session := MakePlacementSession(Profile, Player, Entity)
        set Active = option{Session}
        defer:
            set Active = false
        Outcome := RunWorldPlacement(Entity, Session)
        if (Outcome?):
            PlacedEvent.Signal(Entity)
        else:
            CancelledEvent.Signal(Player)
