using { /Verse.org/Assets }
using { /Verse.org/Concurrency }
using { /Verse.org/Input }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/Itemization }
using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Temporary/SpatialMath }


# Item-driven wrapper over placement_session: equipping the sibling item
# enters placement mode, ConfirmAction confirms, unequip/disable cancels.
# For programmatic placement (no items) drive a placement_session directly;
# see the chess board.
placable_component<public> := class<final_super>(component):

    @editable
    var Method<public>:placement_method

    @editable
    var Restrictions<public>:[]placement_restriction = array{}

    @editable
    var Highlight<public>:placement_highlight

    @editable
    var ConfirmAction<public>:?input_action(logic) = false

    @editable
    var Provider<public>:placement_target_provider

    @editable
    var Enabled<public>:logic = true

    EnabledChangedEvent<private>:Concurrency.subscribable_event(logic) = Concurrency.subscribable_event(logic){}

    Enable<public>():void =
        if (not Enabled?):
            set Enabled = true
            EnabledChangedEvent.Signal(true)

    Disable<public>():void =
        if (Enabled?):
            set Enabled = false
            EnabledChangedEvent.Signal(false)

    OnSimulate<override>()<suspends>:void =
        if (ItemComp := Entity.GetComponent[item_component]):
            loop:
                if:
                    Enabled?
                    ItemComp.IsEquipped[]
                    Owner := FindOwningPlayer[ItemComp]
                then:
                    PlacementRound(Owner, ItemComp)
                else:
                    race:
                        ItemComp.ChangeEquippedEvent.Await()
                        EnabledChangedEvent.Await()

    # One session while equipped. Unequip/disable end the race, cancelling
    # Run mid-await (its defer hides the preview); input confirms.
    PlacementRound<private>(Owner:player, ItemComp:item_component)<suspends>:void =
        Session := placement_session:
            Query := placement_query{Player := Owner, PlacableEntity := Entity}
            Method := Method
            Restrictions := Restrictions
            Highlight := Highlight
        var Confirmed:?placement_proposal = false
        race:
            block:
                set Confirmed = Session.Run()
            ConfirmInputArm(Owner, Session)
            WaitForUnequip(ItemComp)
            WaitForDisable()
        if (Proposal := Confirmed?):
            CommitPlacement(Owner, ItemComp, Proposal)

    ConfirmInputArm<private>(Owner:player, Session:placement_session)<suspends>:void =
        if:
            CA := ConfirmAction?
            Input := GetPlayerInput[Owner]
        then:
            ConfirmEvents := Input.GetInputEvents(CA)
            ConfirmEvents.TriggerActivationEvent.Subscribe(NullCallback) # NOTE: Workaround for input events not working with .Await
            loop:
                ConfirmEvents.TriggerActivationEvent.Await()
                Session.RequestConfirm()
        else:
            Sleep(Inf)

    CommitPlacement<private>(Owner:player, ItemComp:item_component, Proposal:placement_proposal):void =
        if:
            ItemComp.Unequip().GetSuccess[]
            Inv := ItemComp.GetParentInventory[]
            SimEntity := Owner.GetFortCharacter[].GetEntity[].GetSimulationEntity[]
            Inv.RemoveItem(Entity).GetSuccess[]
        then:
            NewEntity := Provider.ProvideTarget(Self)
            SimEntity.AddEntities(array{NewEntity})
            NewEntity.SetGlobalTransform(Proposal.Transform)

    WaitForUnequip<private>(ItemComp:item_component)<suspends>:void =
        loop:
            Result := ItemComp.ChangeEquippedEvent.Await()
            if (not Result.IsItemEquipped?):
                break

    WaitForDisable<private>()<suspends>:void =
        loop:
            EnabledChangedEvent.Await()
            if (not Enabled?):
                break

    # castable bug with agent: look ancestors instead.
    FindOwningPlayer<private>(ItemComp:item_component)<transacts><decides>:player =
        Inv := ItemComp.GetParentInventory[]
        if (P := player[Inv.Entity]). P # first check if inventory parent is player
        else: # find player in ancestor hierarchy
            Players := for (Ancestor : Inv.Entity.FindAncestorEntities(entity), P := player[Ancestor]) { P }
            Players[0]
