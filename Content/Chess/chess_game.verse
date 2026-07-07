using { /Verse.org/Concurrency }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization } # result types


# The mutable shell around the pure rules. Owns current position + history,
# validates and applies moves, tracks game-over, publishes events. Interfaces
# (world display, console, bots) talk ONLY to this: call TryMove/TryMoveText,
# read Position(), subscribe to the events. Not a component, so it can live
# inside any component, device or test.

# What actually happened, for displays: Captured is the removed piece (incl
# en passant) and CapturedSquare is where it stood (= Move.To except en
# passant). RookHop is the extra rook move on castling.
chess_move_applied<public> := class:
    Move<public>:chess_move
    Mover<public>:chess_piece
    Captured<public>:?chess_piece
    CapturedSquare<public>:?int
    RookHop<public>:?chess_move
    # Position AFTER the move.
    NewPosition<public>:chess_position
    GaveCheck<public>:logic

chess_move_error<public> := class<computes>:
game_over_move_error<public> := class<concrete><computes>(chess_move_error){}
malformed_move_error<public> := class<concrete><computes>(chess_move_error){}
illegal_move_error<public> := class<concrete><computes>(chess_move_error){}


# Construct with MakeChessGame(): StartingPosition() is a divergent call,
# which field initializers reject (3582), so Current is set here instead.
# The class constructor is internal (factory pattern) so the no-default
# internal field satisfies the constructor-accessibility rule.
MakeChessGame<public>()<transacts>:chess_game =
    chess_game{Current := StartingPosition()}


chess_game<public> := class<internal>:

    var<internal> Current<internal>:chess_position
    var History<private>:[]chess_move = array{}
    # Position keys since the last irreversible move, for threefold.
    var RepetitionKeys<private>:[]string = array{}
    var Result<private>:?chess_result = false

    MoveAppliedEvent<public>:Concurrency.subscribable_event(chess_move_applied) =
        Concurrency.subscribable_event(chess_move_applied){}

    GameEndedEvent<public>:Concurrency.subscribable_event(chess_result) =
        Concurrency.subscribable_event(chess_result){}

    # --- Reads ----------------------------------------------------------------

    Position<public>()<reads>:chess_position = Current

    Moves<public>()<reads>:[]chess_move = History

    GetResult<public>()<reads><decides>:chess_result = Result?

    IsOver<public>()<reads><decides>:void = Result?

    LegalMoves<public>()<transacts>:[]chess_move =
        AllLegalMoves(Current)

    LegalFrom<public>(Sq:int)<transacts>:[]chess_move =
        LegalMovesFrom(Current, Sq)

    # --- Driving --------------------------------------------------------------

    # "e2e4" / "e7e8q" text form.
    TryMoveText<public>(S:string):result(chess_move_applied, chess_move_error) =
        if (M := ParseMoveText[S]):
            TryMove(M)
        else:
            MakeError(malformed_move_error{})

    # Full validation, application, end detection, events. Signals, so the
    # method is plain (no_rollback callers hoist and test the result).
    TryMove<public>(M:chess_move):result(chess_move_applied, chess_move_error) =
        if (IsOver[]):
            MakeError(game_over_move_error{})
        else if (Applied := ApplyValidated[M]):
            MoveAppliedEvent.Signal(Applied)
            CheckGameEnd()
            MakeSuccess(Applied)
        else:
            MakeError(illegal_move_error{})

    Resign<public>(C:chess_color):void =
        if (not IsOver[]):
            R := if (C = chess_color.White) then chess_result.BlackWinsResignation else chess_result.WhiteWinsResignation
            EndWith(R)

    Reset<public>():void =
        set Current = StartingPosition()
        set History = array{}
        set RepetitionKeys = array{}
        set Result = false

    # --- Internals --------------------------------------------------------------

    # The transactional core: validates and mutates, no signals. Rolls back
    # whole on any failure.
    ApplyValidated<private>(M:chess_move)<transacts><decides>:chess_move_applied =
        IsLegal[Current, M]
        Prev := Current
        Mover := PieceAt[Prev, M.From]
        Next := Apply[Prev, M]
        # Describe side effects for displays before mutating.
        # Where a captured piece stood: To for normal captures, the passed
        # pawn's square for en passant. The FACT lives here, not re-derived
        # by displays.
        IsEP:logic =
            if:
                Mover.Kind = chess_piece_kind.Pawn
                EP := Prev.EnPassant?
                EP = M.To
                not option{PieceAt[Prev, M.To]}?
            then:
                true
            else:
                false
        CapturedSquare:?int =
            if (IsEP?):
                option{if (Prev.ToMove = chess_color.White) then M.To - 8 else M.To + 8}
            else if (option{PieceAt[Prev, M.To]}?):
                option{M.To}
            else:
                false
        Captured:?chess_piece =
            if (Sq := CapturedSquare?):
                option{PieceAt[Prev, Sq]}
            else:
                false
        RookHop:?chess_move =
            if (Mover.Kind = chess_piece_kind.King, FF := FileOf[M.From], TF := FileOf[M.To], R := RankOf[M.From]):
                if (TF - FF = 2):
                    option{chess_move{From := SquareAt(7, R), To := SquareAt(5, R)}}
                else if (FF - TF = 2):
                    option{chess_move{From := SquareAt(0, R), To := SquareAt(3, R)}}
                else:
                    false
            else:
                false
        set Current = Next
        set History += array{M}
        # Irreversible moves clear the repetition window.
        if (Next.HalfmoveClock = 0):
            set RepetitionKeys = array{}
        set RepetitionKeys += array{PositionKey(Next)}
        GaveCheck:logic = if (InCheck[Next, Next.ToMove]) then true else false
        chess_move_applied:
            Move := M
            Mover := Mover
            Captured := Captured
            CapturedSquare := CapturedSquare
            RookHop := RookHop
            NewPosition := Next
            GaveCheck := GaveCheck

    CheckGameEnd<private>():void =
        Loser := Current.ToMove
        if (IsCheckmate[Current]):
            R := if (Loser = chess_color.White) then chess_result.BlackWinsCheckmate else chess_result.WhiteWinsCheckmate
            EndWith(R)
        else if (IsStalemate[Current]):
            EndWith(chess_result.DrawStalemate)
        else if (IsInsufficientMaterial[Current]):
            EndWith(chess_result.DrawInsufficientMaterial)
        else if (Current.HalfmoveClock >= 100):
            EndWith(chess_result.DrawFiftyMove)
        else if (CountKey(PositionKey(Current)) >= 3):
            EndWith(chess_result.DrawThreefold)

    EndWith<private>(R:chess_result):void =
        if (not Result?):
            set Result = option{R}
            GameEndedEvent.Signal(R)

    CountKey<private>(Key:string)<transacts>:int =
        for (K : RepetitionKeys, K = Key) { K }.Length

    # Squares + mover + castling + en passant: the FEN identity fields.
    PositionKey<private>(P:chess_position)<transacts>:string =
        var S:string = ""
        for (Sq := 0..63):
            Letter := if (Pc := PieceAt[P, Sq]) then PieceLetter(Pc) else "."
            set S = "{S}{Letter}"
        Mover := if (P.ToMove = chess_color.White) then "w" else "b"
        WK := if (P.CastleWK?) then "K" else ""
        WQ := if (P.CastleWQ?) then "Q" else ""
        BK := if (P.CastleBK?) then "k" else ""
        BQ := if (P.CastleBQ?) then "q" else ""
        EP := if (E := P.EnPassant?, T := SquareText[E]) then T else "-"
        "{S} {Mover} {WK}{WQ}{BK}{BQ} {EP}"
