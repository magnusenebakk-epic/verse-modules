using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Bases }
using { Unlocks }


# Testers for the two ways to hook a feature to an unlock.


# Way 1: implements unlockable (Enable/Disable), knows nothing about
# unlocks. Wire it via unlockable_dispatch_presenter on a node. Prints every
# toggle: disabled on claim (locked), enabled on unlock, disabled on reset,
# re-enabled on reclaim.
test_unlockable_component<public> := class<final_super>(component, unlockable):

    @editable
    Label<public>:string = "feature_a"

    var Enabled<private>:logic = false

    Enable<override>():void =
        if (not Enabled?):
            set Enabled = true
            Print("TEST unlockable[{Label}]: ENABLED")

    Disable<override>():void =
        if (Enabled?):
            set Enabled = false
            Print("TEST unlockable[{Label}]: DISABLED")


# Way 2: State.AwaitUnlocked(Key). Heartbeats only while the key is unlocked
# and the base is claimed. Silent while locked, resumes on reclaim.
test_await_unlocked_component<public> := class<final_super>(component):

    @editable
    NodeKey<public>:string = "node_b"

    @editable
    HeartbeatSeconds<public>:float = 5.0

    OnSimulate<override>()<suspends>:void =
        (super:)OnSimulate()
        if:
            Base := Entity.FindBase[]
            State := Entity.FindUnlockState[]
        then:
            loop:
                State.AwaitUnlocked(NodeKey)
                Print("TEST await[{NodeKey}]: unlocked, heartbeat starts")
                race:
                    Base.AwaitReleased() # release resets the key
                    Heartbeat()
                Print("TEST await[{NodeKey}]: stopped (released)")

    Heartbeat<private>()<suspends>:void =
        loop:
            Sleep(HeartbeatSeconds)
            Print("TEST await[{NodeKey}]: heartbeat")
