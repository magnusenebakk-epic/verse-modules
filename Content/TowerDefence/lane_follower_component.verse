using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/SceneGraph/KeyframedMovement }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


# Walks an enemy along its lane with keyframed movement. Movement is
# deterministic (constant Speed), so progress derives from elapsed time.
lane_follower_component<public> := class<final_super>(component, lane_traveler):

    @editable
    var Speed<public>:float = 300.0

    ReachedEndEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    var<private> StartTime<private>:float = 0.0
    var<private> StartProgress<private>:float = 0.0
    var<private> Walking<private>:logic = false
    # set while registered; OnRemovingFromScene cleans up since BPVM makes defer in a cancelled task unreliable
    var<private> RegisteredLane<private>:?lane_component = false

    GetLaneProgress<override>()<transacts>:float =
        if (Walking?):
            StartProgress + (GetSimulationElapsedTime() - StartTime) * Speed
        else:
            StartProgress

    OnSimulate<override>()<suspends>:void =
        if:
            Lane := FindLane[]
            Movement := Entity.GetComponent[keyframed_movement_component]
            Path := ValidPath[Lane]
        then:
            WalkPath(Lane, Movement, Path)

    WalkPath<private>(Lane:lane_component, Movement:keyframed_movement_component, Path:[](LUF:)vector3)<suspends>:void =
        if (Start := Path[0]):
            Entity.SetGlobalTransform((LUF:)transform{
                Translation := Start,
                Rotation := Entity.GetGlobalTransform().Rotation,
                Scale := Entity.GetGlobalTransform().Scale
            })
        # keyframe translations apply in the parent's frame; unrotate world-space deltas for rotated lanes
        ToParent := if (Parent := Entity.GetParent[]):
            Parent.GetGlobalTransform().Rotation.Invert()
        else:
            IdentityRotation()
        Deltas := for:
            I -> P : Path
            I > 0
            Prev := Path[I - 1]
        do:
            SegLen := Distance(Prev, P)
            keyframed_movement_delta{
                Transform := (LUF:)transform{
                    Translation := (P - Prev) * ToParent,
                    Rotation := IdentityRotation(),
                    Scale := (LUF:)vector3{}
                },
                Duration := if (Speed > 0.0) then SegLen / Speed else 0.0,
                Easing := linear_easing_function{}
            }
        Movement.SetKeyframes(Deltas, oneshot_keyframed_movement_playback_mode{})
        set StartTime = GetSimulationElapsedTime()
        set StartProgress = 0.0
        set Walking = true
        # register only after progress state is live; Register signals targeters synchronously
        Lane.Register(Entity, Self)
        set RegisteredLane = option{Lane}
        Movement.Play()
        Movement.FinishedEvent.Await()
        set StartProgress = GetLaneProgress()
        set Walking = false
        # unregister before notifying: ReachedEnd subscribers must not see the enemy still on the lane
        Unregister()
        ReachedEndEvent.Signal(())
        Lane.NotifyReachedEnd(Entity)

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        Unregister()

    Unregister<private>():void =
        if (Lane := RegisteredLane?):
            set RegisteredLane = false
            Lane.Unregister(Entity)

    FindLane<private>()<transacts><decides>:lane_component =
        first{L:Entity.FindAncestorComponents(lane_component)}

    ValidPath<private>(Lane:lane_component)<reads><decides>:[](LUF:)vector3 =
        Path := Lane.GetPathPoints()
        Path.Length >= 2
        Path
