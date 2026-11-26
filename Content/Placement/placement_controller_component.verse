using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


# Programmatic placement driver (e.g. tower-select UI). Behavior lives on Profile so one controller serves
# every tower; BeginPlace spawns and places, BeginRelocate moves. One live session, a new one cancels the old.
placement_controller_component<public> := class<final_super>(component):

    # Parent for placed instances; unset means the simulation root.
    @editable
    PlaceUnder<public>:?entity = false

    # Placement behavior every BeginPlace/BeginRelocate under this controller inherits.
    @editable
    Profile<public>:placement_profile = placement_profile{}

    PlacedEvent<public>:Concurrency.subscribable_event(entity) =
        Concurrency.subscribable_event(entity){}

    CancelledEvent<public>:Concurrency.subscribable_event(player) =
        Concurrency.subscribable_event(player){}

    var<private> Active<private>:?placement_session = false
    StopEvent<private>:event() = event(){}

    # Signalling is no_rollback, so these return logic rather than <decides>.
    IsActive<public>():logic =
        if (Active?) then true else false

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

    # Spawns Prefab and places it; returns the instance on confirm, despawns it on cancel.
    BeginPlace<public>(Player:player, Prefab:concrete_subtype(entity))<suspends>:?entity =
        if (Parent := PlacementParent[]):
            Instance := ((concrete_subtype(entity))(Prefab)){}
            Parent.AddEntities(array{Instance})
            # park it below the field until the first aim moves it; in view it would look already placed, and its components simulate while waiting
            Park := Entity.GetGlobalTransform()
            Instance.SetGlobalTransform(transform{
                Translation := Park.Translation - vector3{Forward := 0.0, Left := 0.0, Up := 100000.0},
                Rotation    := Park.Rotation,
                Scale       := Park.Scale
            })
            Print("placement: instance spawned, parked at {ToString(Instance.GetGlobalTransform().Translation)}")
            var Placed:?entity = false
            defer:
                if (not Placed?):
                    Instance.RemoveFromParent()
            set Placed = RunExclusive(Player, Instance)
            Placed
        else:
            Print("placement: no parent entity to place under")
            false

    # Relocates an existing world entity; cancel restores its transform (RunWorldPlacement).
    BeginRelocate<public>(Player:player, Target:entity)<suspends>:?entity =
        RunExclusive(Player, Target)

    # Ends any running session first; loops in case several Begins land the same tick, only one runs.
    RunExclusive<private>(Player:player, Target:entity)<suspends>:?entity =
        loop:
            if (not Active?):
                break
            StopEvent.Signal()
            Sleep(0.0)
        var Placed:?entity = false
        race:
            block:
                set Placed = RunSession(Player, Target)
            WaitForStop()
        Placed

    RunSession<private>(Player:player, Target:entity)<suspends>:?entity =
        Session := MakePlacementSession(Profile, Player, Target)
        set Active = option{Session}
        var Placed:logic = false
        defer:
            set Active = false
            # also fires when a Stop/newer Begin cancels us mid-session
            if (not Placed?):
                CancelledEvent.Signal(Player)
        Outcome := RunWorldPlacement(Target, Session)
        if (Outcome?):
            set Placed = true
            PlacedEvent.Signal(Target)
            option{Target}
        else:
            false

    WaitForStop<private>()<suspends>:void =
        StopEvent.Await()

    PlacementParent<private>()<transacts><decides>:entity =
        PlaceUnder? or Entity.GetSimulationEntity[]
