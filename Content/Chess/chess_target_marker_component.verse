using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }


# Lives on the legal-target marker prefab next to a basic_interactable_component.
# Interacting with a circle commits the move to its square: this is THE
# place gesture. Square is set by chess_move_highlight when spawning.
chess_target_marker_component<public> := class<final_super>(component):

    var Square<public>:int = 0

    var Subscription<private>:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Interactable := Entity.GetComponent[basic_interactable_component]):
            set Subscription = option{Interactable.SucceededEvent.Subscribe(OnInteracted)}
        else:
            Print("chess dbg: legal marker has NO basic_interactable_component")

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        if (Subscription?.Cancel()):
            set Subscription = false

    OnInteracted<private>(Agent:agent):void =
        if (Board := option{first{B:Entity.FindAncestorComponents(chess_board_component)}}?):
            Board.NotifyTargetInteracted(Agent, Square)
        else:
            Print("chess dbg: marker interacted but no ancestor board found")
