using { /Verse.org/SceneGraph }
using { /Verse.org/SceneGraph/CollisionProfiles }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }


# Places where the virtual pointer (touch/mouse/right-stick) points: deprojects the latched position and sweeps.
# Press latches, hold drags (DragToAim), release confirms; the player is immobilized while TouchMapping is active.
virtual_pointer_placement_method<public> := class<concrete>(hit_aware_placement_method):

    @editable
    var MaxRange<public>:float = 50000.0

    # Nudges the trace start off the camera to avoid hitting the player.
    @editable
    var StartOffset<public>:float = 100.0

    # Adds TouchMapping for the session; turn off if something else already put the player in pointer mode.
    @editable
    var ManageInputMapping<public>:logic = true

    # Each tap requests a confirm (on release) as well as aiming. Off = aim only.
    @editable
    var TapToConfirm<public>:logic = true

    # Holding drags the aim around until release. Off = the aim stays where the press landed.
    @editable
    var DragToAim<public>:logic = true

    var<private> LastPointer<private>:?vector3 = false
    # per-gesture trace state, reset on press
    var<private> SawTrigger<private>:logic = false
    var<private> LastBeat<private>:int = -1

    RunInput<override>(Query:placement_query, Controls:placement_controls)<suspends>:void =
        if (Input := GetPlayerInput[Query.Player]):
            if (ManageInputMapping?):
                Input.AddInputMapping(TouchMapping)
            Events := Input.GetInputEvents(PointerSelect)
            # latch through callbacks, not awaits; an await loop misses events landing between awaits or in the press frame
            SubBegin := Events.BeginDetectEvent.Subscribe(OnPointerBegin)
            SubDrag := Events.DetectionOngoingEvent.Subscribe(OnPointerOngoing)
            SubTrig := Events.TriggerActivationEvent.Subscribe(OnPointerTrigger)
            SubCancel := Events.CancelActivationEvent.Subscribe(OnPointerCancel)
            SubEnd := Events.EndDetectEvent.Subscribe(NullCallback) # workaround, .Await alone doesn't fire
            defer:
                SubBegin.Cancel()
                SubDrag.Cancel()
                SubTrig.Cancel()
                SubCancel.Cancel()
                SubEnd.Cancel()
                if (ManageInputMapping?):
                    Input.RemoveInputMapping(TouchMapping)
                set LastPointer = false
            loop:
                Sleep(-1.0)
                End := Events.EndDetectEvent.Await()
                Print("pointer: release after {End(1)}s")
                if (TapToConfirm?):
                    Controls.RequestConfirm()

    OnPointerBegin<private>(P:player, Pos:vector3):void =
        Print("pointer: press at {ToString(Pos)}")
        set SawTrigger = false
        set LastBeat = -1
        # latch first so anything downstream reads this press, not the old aim
        set LastPointer = option{Pos}

    # held-stream, if this action sends one; heartbeat print shows whether the payload follows the finger
    OnPointerOngoing<private>(P:player, Pos:vector3, Elapsed:float):void =
        if (Beat := Floor[Elapsed * 2.0], Beat > LastBeat):
            set LastBeat = Beat
            Print("pointer: held {Elapsed}s at {ToString(Pos)}")
        if (DragToAim?):
            set LastPointer = option{Pos}

    # Possible second stream: the input docs allow repeat triggers while held.
    OnPointerTrigger<private>(P:player, Pos:vector3):void =
        if (not SawTrigger?):
            set SawTrigger = true
            Print("pointer: trigger at {ToString(Pos)}")
        if (DragToAim?):
            set LastPointer = option{Pos}

    OnPointerCancel<private>(P:player, Pos:vector3, Elapsed:float):void =
        Print("pointer: canceled after {Elapsed}s at {ToString(Pos)}")

    ComputeProposal<override>(Query:placement_query)<transacts><decides>:placement_proposal =
        Pointer := LastPointer?
        Ray := Query.Player.DeprojectViewportToWorld(
            vector3{Forward := 0.0, Left := Pointer.Left, Up := Pointer.Up})

        Start := Ray.Origin + Ray.Direction * StartOffset
        Delta := Ray.Direction * MaxRange

        Probe := collision_point{ CollisionProfile := VisibilityOverlapAll }
        StartTransform := transform{
            Translation := Start,
            Rotation    := IdentityRotation(),
            Scale       := vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
        }

        Sim := Query.PlacableEntity.GetSimulationEntity[]
        Hit := FirstAcceptedHit[Query, Sim.FindSweepHits(Delta, StartTransform, Probe)]

        Xform := transform{
            Translation := Hit.ContactPosition,
            Rotation    := Query.PlacableEntity.GetGlobalTransform().Rotation,
            Scale       := Query.PlacableEntity.GetGlobalTransform().Scale
        }
        placement_proposal{
            Transform := Xform,
            HitNormal := option{Hit.ContactNormal},
            HitEntity := option{Hit.TargetComponent.Entity}
        }
