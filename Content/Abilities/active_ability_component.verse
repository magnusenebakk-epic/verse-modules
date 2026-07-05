using { /Verse.org/Assets }
using { /Verse.org/Concurrency }
using { /Verse.org/Input }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Itemization }


active_ability_component<public> := class<final_super>(component):

    @editable
    (active_ability_component:)Abilities<public>:[]concrete_subtype(ability_base) = array{}

    var<private> ChildAbilities<private>:[]entity = array{}
    var<private> ComponentCancel<private>:event() = event(){}

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        if (ChildAbilities.Length > 0). return
        for (Class : (active_ability_component:)Abilities):
            Inst := Class{}
            Entity.AddEntities(array{Inst})
            set ChildAbilities += array{Inst}

    OnSimulate<override>()<suspends>:void =
        if (ItemComp := Entity.GetComponent[item_component]):
            loop:
                Result := ItemComp.ChangeEquippedEvent.Await()
                if:
                    Result.IsItemEquipped?
                    Inv := ItemComp.GetParentInventory[]
                    Owner := Inv.GetOwningPlayer[]
                then:
                    EquippedSession(Owner, ItemComp)

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        ComponentCancel.Signal()

    EquippedSession<private>(Owner:player, ItemComp:item_component)<suspends>:void =
        SessionCancel := event(){}
        for (Child : ChildAbilities):
            spawn { ListenForActivation(Child, Owner, SessionCancel) }
        race:
            WaitForUnequip(ItemComp)
            ComponentCancel.Await()
        SessionCancel.Signal()

    ListenForActivation<private>(AbilityE:entity, Owner:player, SessionCancel:event())<suspends>:void =
        race:
            SessionCancel.Await()
            ComponentCancel.Await()
            FireLoop(AbilityE, Owner)

    FireLoop<private>(AbilityE:entity, Owner:player)<suspends>:void =
        if:
            AC := AbilityE.GetComponent[ability_component]
            T := AC.Trigger?
            Input := GetPlayerInput[Owner]
        then:
            Events := Input.GetInputEvents(T)
            Events.BeginDetectEvent.Subscribe(NullCallback)
            loop:
                Sleep(-1.0)
                Events.BeginDetectEvent.Await()
                Result := TryFire(AbilityE, Owner)

    TryFire<public>(AbilityE:entity, Activator:agent)<suspends>:result(ability_fire_success, ability_fire_error) =
        if (CC := AbilityE.GetComponent[ability_cooldown_component], CC.IsOnCooldown[]):
            return MakeError(ability_on_cooldown_error{})
        if (CG := AbilityE.GetComponent[ability_charges_component], not CG.HasCharge[]):
            return MakeError(ability_no_charges_error{})
        CanAfford := if (CostC := AbilityE.GetComponent[ability_cost_component]) then CostC.CanAfford(Activator) else true
        if (not CanAfford?):
            return MakeError(ability_cost_failed_error{})

        if (CT := AbilityE.GetComponent[ability_cast_time_component]):
            Cancelled := CT.Wait(Activator)
            if (Cancelled?):
                return MakeError(ability_cast_cancelled_error{})

        if (CG := AbilityE.GetComponent[ability_charges_component]):
            CG.Consume()
        if (CostC := AbilityE.GetComponent[ability_cost_component]):
            Consumed := CostC.Consume(Activator)
            if (not Consumed?):
                return MakeError(ability_cost_failed_error{})

        if (AC := AbilityE.GetComponent[ability_component]):
            AC.Action.Execute(Self, Activator)
        if (CC := AbilityE.GetComponent[ability_cooldown_component]):
            CC.StartCooldown()
        MakeSuccess(ability_fire_success{})

    WaitForUnequip<private>(ItemComp:item_component)<suspends>:void =
        loop:
            Result := ItemComp.ChangeEquippedEvent.Await()
            if (not Result.IsItemEquipped?):
                break
