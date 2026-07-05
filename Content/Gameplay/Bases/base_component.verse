using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Gameplay.Ownership }


# Marks a claimable plot. All ownership state lives in the required sibling
# ownable_component; this just delegates. Claim/release events are the
# ownable's MemberAdded/RemovedEvent filtered on Info.IsPrimary, or use
# AwaitClaimed/AwaitReleased. Co-owner management is the ownable's API.
#
# The sibling ownable covers the whole subtree, so gating inside the base
# needs no wiring. Owned things that aren't descendants: parent them under
# the base, or give them their own ownable and mirror via events.
base_component<public> := class<final_super>(component):

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (not GetOwnable[]):
            Print("base_component requires a sibling ownable_component")

    GetOwnable<public>()<transacts><decides>:ownable_component =
        Entity.GetComponent[ownable_component]

    IsClaimed<public>()<transacts><decides>:void =
        GetOwnable[].IsOwned[]

    IsOwner<public>(A:agent)<transacts><decides>:void =
        GetOwnable[].IsOwner[A]

    GetOwner<public>()<transacts><decides>:agent =
        GetOwnable[].GetPrimaryOwner[]

    # False if already claimed or no ownable. Signals, so hoist out of
    # if-conditions at call sites.
    Claim<public>(Agent:agent):logic =
        if (O := GetOwnable[]):
            O.Assign(Agent)
        else:
            false

    Release<public>():void =
        if (O := GetOwnable[]):
            O.Release()

    # Usage:
    #   loop:
    #       Owner := Base.AwaitClaimed()
    #       race:
    #           Base.AwaitReleased()
    #           RunWhileOwned(Owner)
    AwaitClaimed<public>()<suspends>:agent =
        if (O := GetOwnable[]):
            O.AwaitAssigned()
        else:
            Err("base_component requires a sibling ownable_component")

    AwaitReleased<public>()<suspends>:?agent =
        if (O := GetOwnable[]):
            O.AwaitReleased()
        else:
            false
