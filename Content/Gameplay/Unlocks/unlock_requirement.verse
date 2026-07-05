using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Gameplay.Currency }


# One gate on an unlock. All requirements on a node must IsSatisfied to
# unlock; on unlock all Commits run in one transaction, so a failing Commit
# rolls back the others and a multi-cost unlock can't half-charge.
#
# Context is the node's entity, so requirements can reach the base, the
# state or scene systems without extra params.
unlock_requirement<public> := class<abstract>:
    IsSatisfied<public>(Agent:agent, Context:entity)<transacts><decides>:void
    # Runs inside the unlock transaction. Mutate state but don't signal
    # (events are no_rollback). Default: nothing to pay.
    Commit<public>(Agent:agent, Context:entity)<transacts><decides>:void = true?
    # Called once after every Commit succeeded. Fire change events here.
    OnCommitted<public>(Agent:agent, Context:entity):void = {}


# Pay N of a currency from the wallet on the agent's stats-holder entity.
currency_requirement<public> := class<concrete>(unlock_requirement):

    @editable
    CurrencyType<public>:subtype(currency_value) = currency_value

    @editable
    Amount<public>:int = 1

    IsSatisfied<override>(Agent:agent, Context:entity)<transacts><decides>:void =
        Wallet := FindWallet[Agent]
        Wallet.GetAmount[CurrencyType] >= Amount

    # Spend, not TrySpend: TrySpend signals, which is illegal inside the
    # unlock transaction.
    Commit<override>(Agent:agent, Context:entity)<transacts><decides>:void =
        Wallet := FindWallet[Agent]
        Wallet.Spend[CurrencyType, Amount]

    OnCommitted<override>(Agent:agent, Context:entity):void =
        if (Wallet := FindWallet[Agent]):
            Wallet.NotifySpent(CurrencyType, Amount)

    FindWallet<private>(Agent:agent)<transacts><decides>:wallet_component =
        Agent.GetStatsHolderEntity[].GetComponent[wallet_component]


# Gate on other unlocks in the same state. unlock_node_component.Dependencies
# is sugar for one of these.
unlocked_nodes_requirement<public> := class<concrete>(unlock_requirement):

    @editable
    RequiredKeys<public>:[]string = array{}

    # Counts because a failing for body skips the iteration, it doesn't
    # fail the function.
    IsSatisfied<override>(Agent:agent, Context:entity)<transacts><decides>:void =
        State := Context.FindUnlockState[]
        Unlocked := for (K : RequiredKeys, State.IsUnlocked[K]) { K }
        Unlocked.Length = RequiredKeys.Length
