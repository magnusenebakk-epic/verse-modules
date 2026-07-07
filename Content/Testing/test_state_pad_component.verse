using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Ownership }
using { Unlocks }


# Value-store + owner-gating tester. Put it on a node's spawned prefab next
# to an ownership_gated_interactable_component.
#
# Owner interactions bump Int "{Key}.count" and write Float "{Key}.value" in
# the surrounding unlock state, printing both. Non-owners get nothing (the
# gate filters them). Counts surviving release/reclaim and sessions is the
# persistence check.
test_state_pad_component<public> := class<final_super>(component):

    # Namespace in the state's value stores, unique per pad instance.
    @editable
    Key<public>:string = "test_a"

    OnSimulate<override>()<suspends>:void =
        (super:)OnSimulate()
        if (Gate := Entity.GetComponent[ownership_gated_interactable_component]):
            loop:
                Gate.OwnerInteractedEvent.Await()
                OnOwnerHit()
        else:
            Print("TEST state[{Key}]: missing sibling ownership_gated_interactable_component")

    OnOwnerHit<private>():void =
        if (State := Entity.FindUnlockState[]):
            Count := (State.GetInt[CountKey()] or 0) + 1
            State.SetInt(CountKey(), Count)
            State.SetFloat(ValueKey(), (1.0 * Count) / 10.0)
            Value := State.GetFloat[ValueKey()] or 0.0
            Print("TEST state[{Key}]: count={Count} value={Value}")

    CountKey<private>()<computes>:string = "{Key}.count"
    ValueKey<private>()<computes>:string = "{Key}.value"
