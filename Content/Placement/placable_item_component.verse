using { /Verse.org/Assets }
using { /Verse.org/Concurrency }
using { /Verse.org/Input }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/Itemization }
using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Temporary/SpatialMath }


# Item-driven placement: equip enters, ConfirmAction confirms, unequip or disable cancels; owns the item
# lifecycle and inventory-to-world commit. The item lives in an inventory, so use a marker highlight, not move_entity.
placable_item_component<public> := class<final_super>(component):

    @editable
    Profile<public>:placement_profile = placement_profile{}

    @editable
    var ConfirmAction<public>:?input_action(logic) = false

    @editable
    var Provider<public>:placement_target_provider

    # Parent for committed entities; unset means the simulation root.
    @editable
    var PlaceUnder<public>:?entity = false

    PlacedEvent<public>:Concurrency.subscribable_event(entity) =
        Concurrency.subscribable_event(entity){}

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

    # One session while equipped; unequip or disable ends the race and cancels Run mid-await (its defer hides the preview).
    PlacementRound<private>(Owner:player, ItemComp:item_component)<suspends>:void =
        Session := MakePlacementSession(Profile, Owner, Entity)
        var Confirmed:?placement_proposal = false
        race:
            block:
                set Confirmed = Session.Run()
            ConfirmInputArm(Owner, Session)
            WaitForUnequip(ItemComp)
            WaitForDisable()
        if (Proposal := Confirmed?):
            CommitPlacement(Owner, ItemComp, Session, Proposal)

    ConfirmInputArm<private>(Owner:player, Session:placement_session)<suspends>:void =
        if:
            CA := ConfirmAction?
            Input := GetPlayerInput[Owner]
        then:
            ConfirmEvents := Input.GetInputEvents(CA)
            Sub := ConfirmEvents.TriggerActivationEvent.Subscribe(NullCallback) # workaround, input events don't fire with .Await alone
            defer:
                Sub.Cancel()
            loop:
                Sleep(-1.0)
                ConfirmEvents.TriggerActivationEvent.Await()
                Session.RequestConfirm()
        else:
            Sleep(Inf)

    CommitPlacement<private>(Owner:player, ItemComp:item_component, Session:placement_session, Proposal:placement_proposal):void =
        if:
            ItemComp.Unequip().GetSuccess[]
            Inv := ItemComp.GetParentInventory[]
            Parent := CommitParent[Owner]
            Inv.RemoveItem(Entity).GetSuccess[]
        then:
            NewEntity := Provider.ProvideTarget(Session.Query)
            Parent.AddEntities(array{NewEntity})
            NewEntity.SetGlobalTransform(Proposal.Transform)
            # effects see the world entity, not the inventory item
            Session.RunPlacedEffects(NewEntity, Proposal)
            PlacedEvent.Signal(NewEntity)

    CommitParent<private>(Owner:player)<transacts><decides>:entity =
        PlaceUnder? or Owner.GetFortCharacter[].GetEntity[].GetSimulationEntity[]

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

    FindOwningPlayer<private>(ItemComp:item_component)<transacts><decides>:player =
        ItemComp.GetParentInventory[].GetOwningPlayer[]
