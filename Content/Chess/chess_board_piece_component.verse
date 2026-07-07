using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }


# Lives on every spawned piece entity, next to a basic_interactable_component.
# Holds the piece's identity and relays interactions to the ancestor board
# (a relay component instead of a closure: handlers can't capture which
# piece was clicked).
chess_board_piece_component<public> := class<final_super>(component):

    var Square<public>:int = 0
    var PieceColor<public>:chess_color = chess_color.White
    var Kind<public>:chess_piece_kind = chess_piece_kind.Pawn

    var Subscription<private>:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Interactable := Entity.GetComponent[basic_interactable_component]):
            set Subscription = option{Interactable.SucceededEvent.Subscribe(OnInteracted)}
        else:
            Print("chess dbg: piece at sq {Square} has NO basic_interactable_component")

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        if (Subscription?.Cancel()):
            set Subscription = false

    OnInteracted<private>(Agent:agent):void =
        if (Board := option{first{B:Entity.FindAncestorComponents(chess_board_component)}}?):
            Board.NotifyPieceInteracted(Agent, Self)
        else:
            Print("chess dbg: piece interacted but NO ancestor chess_board_component found")
