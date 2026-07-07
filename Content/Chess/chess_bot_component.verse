using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Concurrency }
using { /UnrealEngine.com/Itemization } # result types


# CONSOLE adapter for the bot: log-and-text harness for testing the engine
# without any world setup (and bot-vs-bot soak tests via PlayBothSides).
# NOT needed for in-world boards: chess_board_component runs the bot itself
# for any seat without a player.
#
# Event-reactive: the play loop awaits MoveAppliedEvent rather than polling.
# The search itself is a blocking <transacts> slab bounded by NodeBudget;
# ThinkDelay spreads turns out so games are watchable.

chess_bot_component<public> := class<final_super>(component):

    # true = bot plays White.
    @editable
    BotPlaysWhite<public>:logic = true

    @editable
    PlayBothSides<public>:logic = false

    @editable
    Difficulty<public>:chess_difficulty = chess_difficulty{}

    @editable
    RandomSeed<public>:int = 12345

    # Seconds between bot moves, so games are watchable and turns spread
    # across frames.
    @editable
    ThinkDelay<public>:float = 1.0

    @editable
    LogBoards<public>:logic = true

    var MaybeGame<private>:?chess_game = false
    var MaybeBot<private>:?chess_bot = false
    var EndSubs<private>:[]Concurrency.subscription_task(chess_result) = array{}

    OnSimulate<override>()<suspends>:void =
        (super:)OnSimulate()
        G := EnsureGame()
        set EndSubs += array{G.GameEndedEvent.Subscribe(OnGameEnded)}
        if (LogBoards?):
            PrintBoard(G.Position())
        PlayLoop(G)

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : EndSubs) { S.Cancel() }
        set EndSubs = array{}

    # Human/world input for the non-bot side.
    Submit<public>(Input:string):void =
        G := EnsureGame()
        Outcome := G.TryMoveText(Input)
        if (A := Outcome.GetSuccess[]):
            LogApplied(A, Input)
        else if (E := Outcome.GetError[]):
            if (game_over_move_error[E]):
                Print("chess: game over, {Input} ignored")
            else if (malformed_move_error[E]):
                Print("chess: '{Input}' is not a move (e2e4 / e7e8q)")
            else:
                Print("chess: {Input} is illegal")

    # --- Bot driving -----------------------------------------------------------

    PlayLoop<private>(G:chess_game)<suspends>:void =
        loop:
            if (G.IsOver[]):
                break
            if (BotToMove[G]):
                Sleep(ThinkDelay)
                TakeBotTurn(G)
            else:
                # Wait for the other side's move to land, then re-check.
                G.MoveAppliedEvent.Await()
            Sleep(0.0)   # yield between iterations

    BotToMove<private>(G:chess_game)<transacts><decides>:void =
        Mover := G.Position().ToMove
        if (PlayBothSides?):
            true?
        else if (BotPlaysWhite?):
            Mover = chess_color.White
        else:
            Mover = chess_color.Black

    TakeBotTurn<private>(G:chess_game)<suspends>:void =
        B := EnsureBot()
        MaybeChoice := B.ChooseMove(G.Position())   # suspends while searching
        if (Choice := MaybeChoice?):
            Text := MoveText[Choice.Move] or "????"
            Outcome := G.TryMove(Choice.Move)
            if (A := Outcome.GetSuccess[]):
                Print("chess bot: {Text} (score {Choice.Score}, depth {Choice.SearchDepth}, {Choice.NodesUsed} nodes)")
                LogApplied(A, Text)
            else:
                Print("chess bot: chose illegal {Text}, engine bug")
        # else: no legal moves; game end was already signalled by the game.

    # --- Plumbing --------------------------------------------------------------

    EnsureGame<private>():chess_game =
        if (G := MaybeGame?):
            G
        else:
            New := MakeChessGame()
            set MaybeGame = option{New}
            New

    EnsureBot<private>():chess_bot =
        if (B := MaybeBot?):
            B
        else:
            New := MakeChessBot(Difficulty, RandomSeed)
            set MaybeBot = option{New}
            New

    LogApplied<private>(A:chess_move_applied, Text:string):void =
        MoverName := if (A.Mover.Color = chess_color.White) then "White" else "Black"
        var Line:string = "chess: {MoverName} {Text}"
        if (Pc := A.Captured?):
            set Line = "{Line} takes {PieceLetter(Pc)}"
        if (A.RookHop?):
            set Line = "{Line} (castles)"
        if (A.GaveCheck?):
            set Line = "{Line} +"
        Print(Line)
        if (LogBoards?):
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
        for (I := 0..7):
            if (Line := RankLines[7 - I]):
                Print(Line)
        Print("  a b c d e f g h")
