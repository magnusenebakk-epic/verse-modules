using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Concurrency }
using { /UnrealEngine.com/Itemization } # result types


# Console adapter: the reference for what an interface needs from
# chess_game (drive TryMoveText, subscribe to the two events, render
# Position()). A world adapter does the same with meshes and interactables
# instead of Print.
#
# ScriptedMoves plays automatically at simulation start so the core is
# testable with zero interface work. Wire player input by calling
# Submit("e2e4") from anywhere that has a reference to this component.

chess_console_component<public> := class<final_super>(component):

    # Played in order at start. Default: Scholar's mate, then an illegal
    # move attempt, then a malformed one (error paths on show).
    @editable
    ScriptedMoves<public>:[]string = array{
        "e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7",
        "a7a6", "banana"}

    # Lazy: MakeChessGame() is a divergent call, banned in field defaults (3582).
    var MaybeGame<private>:?chess_game = false
    var Subs<private>:[]Concurrency.subscription_task(chess_move_applied) = array{}
    var EndSubs<private>:[]Concurrency.subscription_task(chess_result) = array{}

    OnSimulate<override>()<suspends>:void =
        (super:)OnSimulate()
        G := EnsureGame()
        set Subs += array{G.MoveAppliedEvent.Subscribe(OnMoveApplied)}
        set EndSubs += array{G.GameEndedEvent.Subscribe(OnGameEnded)}
        PrintBoard(G.Position())
        for (S : ScriptedMoves):
            Submit(S)
            Sleep(2.0)

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : Subs) { S.Cancel() }
        for (S : EndSubs) { S.Cancel() }
        set Subs = array{}
        set EndSubs = array{}

    # The single entry point an input mechanism calls. Param named to avoid
    # colliding with the module function MoveText (no shadowing in Verse).
    Submit<public>(Input:string):void =
        G := EnsureGame()
        Mover := if (G.Position().ToMove = chess_color.White) then "White" else "Black"
        Outcome := G.TryMoveText(Input)
        if (Outcome.GetSuccess[]):
            Print("chess: {Mover} plays {Input}")
        else if (E := Outcome.GetError[]):
            if (game_over_move_error[E]):
                Print("chess: game is over, {Input} ignored")
            else if (malformed_move_error[E]):
                Print("chess: '{Input}' is not a move (use e2e4 / e7e8q)")
            else:
                Print("chess: {Input} is illegal here")

    EnsureGame<private>():chess_game =
        if (G := MaybeGame?):
            G
        else:
            New := MakeChessGame()
            set MaybeGame = option{New}
            New

    # Everything a display needs rides in the event payload; no game access.
    OnMoveApplied<private>(A:chess_move_applied):void =
        if (Pc := A.Captured?):
            Print("chess: captured {PieceLetter(Pc)}")
        if (A.RookHop?):
            Print("chess: castles")
        if (A.GaveCheck?):
            Print("chess: check")
        PrintBoard(A.NewPosition)

    OnGameEnded<private>(R:chess_result):void =
        Text := case (R):
            chess_result.WhiteWinsCheckmate => "checkmate, White wins"
            chess_result.BlackWinsCheckmate => "checkmate, Black wins"
            chess_result.WhiteWinsResignation => "Black resigned, White wins"
            chess_result.BlackWinsResignation => "White resigned, Black wins"
            chess_result.DrawStalemate => "draw by stalemate"
            chess_result.DrawFiftyMove => "draw by fifty-move rule"
            chess_result.DrawThreefold => "draw by threefold repetition"
            chess_result.DrawInsufficientMaterial => "draw, insufficient material"
        Print("chess: {Text}")

    PrintBoard<private>(P:chess_position):void =
        var RankLines:[]string = array{}
        for (R := 0..7):
            var Line:string = "{R + 1} "
            for (F := 0..7):
                Cell := if (Pc := PieceAt[P, SquareAt(F, R)]) then PieceLetter(Pc) else "."
                set Line = "{Line}{Cell} "
            set RankLines += array{Line}
        # Print rank 8 first.
        for (I := 0..7):
            if (Line := RankLines[7 - I]):
                Print(Line)
        Print("  a b c d e f g h")
