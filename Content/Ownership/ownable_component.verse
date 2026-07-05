using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization } # result types


# The ownership model. Follows the /Verse.org/AgentGroup shape: membership
# is one agent -> owner_info map and the role is data on the info. We don't
# depend on AgentGroup directly since it's @experimental; conforming later
# is additive.
#
# An ownable at a subtree root owns everything below it (nearest-ancestor
# walk in Entity.FindOwnable[]). Nothing else stores owners.
#
# All mutators signal events, so they can't be called inside if-conditions
# or for-domains. Hoist the call, test the result.


# Per-member role data. Subclass for game-specific capabilities:
#     builder_info := class(owner_info): CanDemolish:logic = false
owner_info<public> := class<castable>:
    # At most one primary per ownable. Persistence keys off them.
    IsPrimary<public>:logic = false


member_change<public> := class:
    Agent<public>:agent
    Info<public>:owner_info


add_owner_error<public> := class<computes>:
already_member_error<public> := class<concrete><computes>(add_owner_error){}
primary_already_assigned_error<public> := class<concrete><computes>(add_owner_error){}

remove_owner_error<public> := class<computes>:
not_a_member_error<public> := class<concrete><computes>(remove_owner_error){}

change_info_error<public> := class<computes>:
info_target_not_a_member_error<public> := class<concrete><computes>(change_info_error){}
invalid_primary_change_error<public> := class<concrete><computes>(change_info_error){}


ownable_component<public> := class<final_super>(component):

    # Mutate through the API below so the events stay truthful.
    var<private> Members<public>:[agent]owner_info = map{}

    MemberAddedEvent<public>:Concurrency.subscribable_event(member_change) =
        Concurrency.subscribable_event(member_change){}

    MemberRemovedEvent<public>:Concurrency.subscribable_event(member_change) =
        Concurrency.subscribable_event(member_change){}

    # A member's info was replaced (role upgrade/downgrade). Payload = new info.
    MemberInfoChangedEvent<public>:Concurrency.subscribable_event(member_change) =
        Concurrency.subscribable_event(member_change){}

    # --- Queries --------------------------------------------------------------

    # Any member (primary or not).
    IsOwner<public>(A:agent)<reads><decides>:void =
        Members[A]

    IsPrimaryOwner<public>(A:agent)<reads><decides>:void =
        Members[A].IsPrimary?

    GetPrimaryOwner<public>()<reads><decides>:agent =
        first (A -> I : Members, I.IsPrimary?) { A }

    # Has a primary owner.
    IsOwned<public>()<reads><decides>:void =
        GetPrimaryOwner[]

    GetInfo<public>(A:agent)<reads><decides>:owner_info =
        Members[A]

    AllOwners<public>()<reads>:[]agent =
        for (A -> I : Members) { A }

    CoOwners<public>()<reads>:[]agent =
        for (A -> I : Members, not I.IsPrimary?) { A }

    # --- Membership -------------------------------------------------------------

    AddMember<public>(A:agent, Info:owner_info):result(void, add_owner_error) =
        if (Members[A]):
            MakeError(already_member_error{})
        else if (Info.IsPrimary? and IsOwned[]):
            MakeError(primary_already_assigned_error{})
        else:
            if (set Members[A] = Info) {}
            MemberAddedEvent.Signal(member_change{Agent := A, Info := Info})
            MakeSuccess(false)

    RemoveMember<public>(A:agent):result(void, remove_owner_error) =
        if (Info := Members[A]):
            set Members = Members.RemoveKey(A)
            MemberRemovedEvent.Signal(member_change{Agent := A, Info := Info})
            MakeSuccess(false)
        else:
            MakeError(not_a_member_error{})

    # Replace a member's info. Primary status can't change this way,
    # release/reassign instead.
    SetMemberInfo<public>(A:agent, Info:owner_info):result(void, change_info_error) =
        if (Old := Members[A]):
            if (Old.IsPrimary? <> Info.IsPrimary?):
                MakeError(invalid_primary_change_error{})
            else:
                if (set Members[A] = Info) {}
                MemberInfoChangedEvent.Signal(member_change{Agent := A, Info := Info})
                MakeSuccess(false)
        else:
            MakeError(info_target_not_a_member_error{})

    # --- Convenience ------------------------------------------------------------

    # Become the primary owner. False if one exists already.
    Assign<public>(A:agent):logic =
        Outcome := AddMember(A, owner_info{IsPrimary := true})
        logic{Outcome.GetSuccess[]}

    AddCoOwner<public>(A:agent):logic =
        Outcome := AddMember(A, owner_info{})
        logic{Outcome.GetSuccess[]}

    RemoveCoOwner<public>(A:agent):void =
        if (Info := Members[A], not Info.IsPrimary?):
            Removed := RemoveMember(A)
            if (Removed.GetError[]):
                Print("ownable: co-owner removal raced")

    # Removes all members, co-owners first and the primary last, so observers
    # of the primary's removal see an otherwise empty group.
    Release<public>():void =
        for (A : CoOwners()):
            Removed := RemoveMember(A)
        if (Primary := GetPrimaryOwner[]):
            Removed := RemoveMember(Primary)

    # --- Await helpers ----------------------------------------------------------

    # Current primary if owned, else the next one assigned.
    AwaitAssigned<public>()<suspends>:agent =
        if (A := GetPrimaryOwner[]):
            A
        else:
            var Found:?agent = false
            loop:
                C := MemberAddedEvent.Await()
                if (C.Info.IsPrimary?):
                    set Found = option{C.Agent}
                    break
            Found? or Err("unreachable: loop breaks only after setting Found")

    # The former primary on release. Immediately false if not owned.
    AwaitReleased<public>()<suspends>:?agent =
        if (IsOwned[]):
            var Found:?agent = false
            loop:
                C := MemberRemovedEvent.Await()
                if (C.Info.IsPrimary?):
                    set Found = option{C.Agent}
                    break
            Found
        else:
            false
