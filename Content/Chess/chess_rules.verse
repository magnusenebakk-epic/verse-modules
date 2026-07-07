# Pure rules over immutable chess_position. Everything here is a function
# from position to positions/facts; no state, no events. Legal-move test is
# make-the-move-and-check: positions are values, so "try it on a copy" is
# just Apply (arrays copy on write, no undo needed).
#
# Full rules: castling (rights + through-check), en passant, promotion,
# check/checkmate/stalemate, fifty-move clock. Threefold and insufficient
# material live in chess_game (they need history / are draw *claims*).

StartingPosition<public>()<transacts>:chess_position =
    BackRank := array{
        chess_piece_kind.Rook, chess_piece_kind.Knight, chess_piece_kind.Bishop,
        chess_piece_kind.Queen, chess_piece_kind.King, chess_piece_kind.Bishop,
        chess_piece_kind.Knight, chess_piece_kind.Rook}
    var Squares:[]?chess_piece = array{}
    for (Sq := 0..63):
        R := Floor(Sq / 8) or 0
        F := Sq - R * 8
        Piece:?chess_piece =
            if (R = 0, K := BackRank[F]):
                option{chess_piece{Color := chess_color.White, Kind := K}}
            else if (R = 1):
                option{chess_piece{Color := chess_color.White, Kind := chess_piece_kind.Pawn}}
            else if (R = 6):
                option{chess_piece{Color := chess_color.Black, Kind := chess_piece_kind.Pawn}}
            else if (R = 7, K := BackRank[F]):
                option{chess_piece{Color := chess_color.Black, Kind := K}}
            else:
                false
        set Squares += array{Piece}
    chess_position:
        Squares := Squares
        ToMove := chess_color.White
        CastleWK := true
        CastleWQ := true
        CastleBK := true
        CastleBQ := true
        EnPassant := false
        HalfmoveClock := 0
        FullmoveNumber := 1

PieceAt<public>(P:chess_position, Sq:int)<transacts><decides>:chess_piece =
    P.Squares[Sq]?

KingSquare<public>(P:chess_position, C:chess_color)<transacts><decides>:int =
    first:
        Sq -> MaybePc : P.Squares
        Pc := MaybePc?
        Pc.Kind = chess_piece_kind.King
        Pc.Color = C
    do:
        Sq

# --- Attack detection ----------------------------------------------------------
# IsSquareAttacked walks outward from the target square, so it needs no
# move generation (and no recursion into legality).

KnightJumps<internal>:[]tuple(int, int) = array{
    (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)}
KingSteps<internal>:[]tuple(int, int) = array{
    (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)}
RookDirs<internal>:[]tuple(int, int) = array{(1, 0), (-1, 0), (0, 1), (0, -1)}
BishopDirs<internal>:[]tuple(int, int) = array{(1, 1), (1, -1), (-1, 1), (-1, -1)}

# Succeeds if By attacks Sq in P.
IsSquareAttacked<public>(P:chess_position, Sq:int, By:chess_color)<transacts><decides>:void =
    var Attacked:logic = false
    if (F := FileOf[Sq], R := RankOf[Sq]):
        # Pawn attacks: a By-colored pawn one rank BEHIND Sq (from Sq's view,
        # opposite of By's push direction) on an adjacent file.
        PawnRankStep := if (By = chess_color.White) then -1 else 1
        for (DF : array{-1, 1}):
            if:
                OnBoardFR[F + DF, R + PawnRankStep]
                Pc := PieceAt[P, SquareAt(F + DF, R + PawnRankStep)]
                Pc.Color = By
                Pc.Kind = chess_piece_kind.Pawn
            then:
                set Attacked = true
        # Knights.
        for (Jump : KnightJumps):
            if:
                OnBoardFR[F + Jump(0), R + Jump(1)]
                Pc := PieceAt[P, SquareAt(F + Jump(0), R + Jump(1))]
                Pc.Color = By
                Pc.Kind = chess_piece_kind.Knight
            then:
                set Attacked = true
        # King adjacency.
        for (Step : KingSteps):
            if:
                OnBoardFR[F + Step(0), R + Step(1)]
                Pc := PieceAt[P, SquareAt(F + Step(0), R + Step(1))]
                Pc.Color = By
                Pc.Kind = chess_piece_kind.King
            then:
                set Attacked = true
        # Sliders: first piece along each ray decides.
        if (RayHit(P, F, R, RookDirs, By, chess_piece_kind.Rook)?):
            set Attacked = true
        if (RayHit(P, F, R, BishopDirs, By, chess_piece_kind.Bishop)?):
            set Attacked = true
    Attacked?

# First piece along any of Dirs is a By-colored Slider or Queen.
RayHit<internal>(P:chess_position, F:int, R:int, Dirs:[]tuple(int, int), By:chess_color, Slider:chess_piece_kind)<transacts>:logic =
    var Hit:logic = false
    for (D : Dirs):
        var CF:int = F
        var CR:int = R
        var Blocked:logic = false
        loop:
            set CF += D(0)
            set CR += D(1)
            if (not OnBoardFR[CF, CR]):
                break
            if (Blocked?):
                break
            if (Pc := PieceAt[P, SquareAt(CF, CR)]):
                set Blocked = true
                if (Pc.Color = By, Pc.Kind = Slider or Pc.Kind = chess_piece_kind.Queen):
                    set Hit = true
    Hit

InCheck<public>(P:chess_position, C:chess_color)<transacts><decides>:void =
    K := KingSquare[P, C]
    IsSquareAttacked[P, K, C.Opposite()]

# --- Pseudo-legal move generation ------------------------------------------------
# Moves that follow piece movement but may leave the king in check; Legal*
# filters those with make-and-test.

PseudoMovesFrom<internal>(P:chess_position, From:int)<transacts>:[]chess_move =
    var Moves:[]chess_move = array{}
    if:
        Pc := PieceAt[P, From]
        Pc.Color = P.ToMove
        F := FileOf[From]
        R := RankOf[From]
    then:
        case (Pc.Kind):
            chess_piece_kind.Pawn => set Moves = PawnMoves(P, From, F, R, Pc.Color)
            chess_piece_kind.Knight => set Moves = StepMoves(P, From, F, R, Pc.Color, KnightJumps)
            chess_piece_kind.King => set Moves = StepMoves(P, From, F, R, Pc.Color, KingSteps) + CastleMoves(P, Pc.Color)
            chess_piece_kind.Rook => set Moves = SlideMoves(P, From, F, R, Pc.Color, RookDirs)
            chess_piece_kind.Bishop => set Moves = SlideMoves(P, From, F, R, Pc.Color, BishopDirs)
            chess_piece_kind.Queen => set Moves = SlideMoves(P, From, F, R, Pc.Color, RookDirs + BishopDirs)
    Moves

StepMoves<internal>(P:chess_position, From:int, F:int, R:int, C:chess_color, Steps:[]tuple(int, int))<transacts>:[]chess_move =
    var Moves:[]chess_move = array{}
    for (S : Steps):
        if (OnBoardFR[F + S(0), R + S(1)]):
            To := SquareAt(F + S(0), R + S(1))
            Occupied := option{PieceAt[P, To]}
            if (Pc := Occupied?):
                if (not (Pc.Color = C)):
                    set Moves += array{chess_move{From := From, To := To}}
            else:
                set Moves += array{chess_move{From := From, To := To}}
    Moves

SlideMoves<internal>(P:chess_position, From:int, F:int, R:int, C:chess_color, Dirs:[]tuple(int, int))<transacts>:[]chess_move =
    var Moves:[]chess_move = array{}
    for (D : Dirs):
        var CF:int = F
        var CR:int = R
        var Stopped:logic = false
        loop:
            set CF += D(0)
            set CR += D(1)
            if (Stopped? or not OnBoardFR[CF, CR]):
                break
            To := SquareAt(CF, CR)
            if (Pc := PieceAt[P, To]):
                set Stopped = true
                if (not (Pc.Color = C)):
                    set Moves += array{chess_move{From := From, To := To}}
            else:
                set Moves += array{chess_move{From := From, To := To}}
    Moves

PawnMoves<internal>(P:chess_position, From:int, F:int, R:int, C:chess_color)<transacts>:[]chess_move =
    var Moves:[]chess_move = array{}
    Dir := if (C = chess_color.White) then 1 else -1
    StartRank := if (C = chess_color.White) then 1 else 6
    PromoRank := if (C = chess_color.White) then 7 else 0
    # Pushes.
    if (OnBoardFR[F, R + Dir], not option{PieceAt[P, SquareAt(F, R + Dir)]}?):
        set Moves += PawnTargets(From, SquareAt(F, R + Dir), R + Dir, PromoRank)
        if (R = StartRank, not option{PieceAt[P, SquareAt(F, R + 2 * Dir)]}?):
            set Moves += array{chess_move{From := From, To := SquareAt(F, R + 2 * Dir)}}
    # Captures, including en passant.
    for (DF : array{-1, 1}):
        if (OnBoardFR[F + DF, R + Dir]):
            To := SquareAt(F + DF, R + Dir)
            CanCapture:logic =
                if (Pc := PieceAt[P, To]):
                    if (Pc.Color = C) then false else true
                else if (EP := P.EnPassant?, EP = To):
                    true
                else:
                    false
            if (CanCapture?):
                set Moves += PawnTargets(From, To, R + Dir, PromoRank)
    Moves

# One move, or four on the promotion rank.
PawnTargets<internal>(From:int, To:int, ToRank:int, PromoRank:int)<transacts>:[]chess_move =
    if (ToRank = PromoRank):
        for (K : PromoKinds):
            chess_move{From := From, To := To, Promo := option{K}}
    else:
        array{chess_move{From := From, To := To}}

# Castle as king-two-files. Emitted only when rights remain, squares between
# are empty, and king/crossing/landing squares are unattacked.
CastleMoves<internal>(P:chess_position, C:chess_color)<transacts>:[]chess_move =
    var Moves:[]chess_move = array{}
    Enemy := C.Opposite()
    R := if (C = chess_color.White) then 0 else 7
    KSq := SquareAt(4, R)
    KingHome := if (K := option{KingSquare[P, C]}?, K = KSq) then true else false
    NotInCheck := if (IsSquareAttacked[P, KSq, Enemy]) then false else true
    if (KingHome?, NotInCheck?):
        KingsideRight := if (C = chess_color.White) then P.CastleWK else P.CastleBK
        QueensideRight := if (C = chess_color.White) then P.CastleWQ else P.CastleBQ
        if:
            KingsideRight?
            not option{PieceAt[P, SquareAt(5, R)]}?
            not option{PieceAt[P, SquareAt(6, R)]}?
            not IsSquareAttacked[P, SquareAt(5, R), Enemy]
            not IsSquareAttacked[P, SquareAt(6, R), Enemy]
        then:
            set Moves += array{chess_move{From := KSq, To := SquareAt(6, R)}}
        if:
            QueensideRight?
            not option{PieceAt[P, SquareAt(3, R)]}?
            not option{PieceAt[P, SquareAt(2, R)]}?
            not option{PieceAt[P, SquareAt(1, R)]}?
            not IsSquareAttacked[P, SquareAt(3, R), Enemy]
            not IsSquareAttacked[P, SquareAt(2, R), Enemy]
        then:
            set Moves += array{chess_move{From := KSq, To := SquareAt(2, R)}}
    Moves

# --- Applying a move ----------------------------------------------------------
# Total over pseudo-legal moves; produces the successor position. Handles
# capture, en passant, castling rook hop, promotion, rights and clocks.

Apply<public>(P:chess_position, M:chess_move)<transacts><decides>:chess_position =
    Mover := PieceAt[P, M.From]
    Mover.Color = P.ToMove
    var Squares:[]?chess_piece = P.Squares
    IsPawn:logic = if (Mover.Kind = chess_piece_kind.Pawn) then true else false
    Captured := option{PieceAt[P, M.To]}
    # En passant capture removes the passed pawn.
    if (IsPawn?, EP := P.EnPassant?, EP = M.To, not Captured?):
        PassedSq := if (P.ToMove = chess_color.White) then M.To - 8 else M.To + 8
        if (set Squares[PassedSq] = false) {}
    # Move the piece (with promotion).
    Landed:chess_piece =
        if (K := M.Promo?):
            chess_piece{Color := Mover.Color, Kind := K}
        else:
            Mover
    if (set Squares[M.From] = false) {}
    if (set Squares[M.To] = option{Landed}) {}
    # Castling: king moved two files, hop the rook.
    if (Mover.Kind = chess_piece_kind.King):
        FF := FileOf[M.From]
        TF := FileOf[M.To]
        R := RankOf[M.From]
        if (TF - FF = 2):    # kingside
            RookPc := PieceAt[P, SquareAt(7, R)]
            if (set Squares[SquareAt(7, R)] = false) {}
            if (set Squares[SquareAt(5, R)] = option{RookPc}) {}
        if (FF - TF = 2):    # queenside
            RookPc := PieceAt[P, SquareAt(0, R)]
            if (set Squares[SquareAt(0, R)] = false) {}
            if (set Squares[SquareAt(3, R)] = option{RookPc}) {}
    # Castling rights decay when king/rooks move or rooks are captured.
    NewWK := UpdateRight(P.CastleWK, M, 4, 7)
    NewWQ := UpdateRight(P.CastleWQ, M, 4, 0)
    NewBK := UpdateRight(P.CastleBK, M, 60, 63)
    NewBQ := UpdateRight(P.CastleBQ, M, 60, 56)
    # New en passant square on double pushes.
    NewEP:?int =
        if (IsPawn?):
            FromR := RankOf[M.From]
            ToR := RankOf[M.To]
            if (ToR - FromR = 2):
                option{M.From + 8}
            else if (FromR - ToR = 2):
                option{M.From - 8}
            else:
                false
        else:
            false
    ResetClock:logic = if (IsPawn? or Captured?) then true else false
    chess_position:
        Squares := Squares
        ToMove := P.ToMove.Opposite()
        CastleWK := NewWK
        CastleWQ := NewWQ
        CastleBK := NewBK
        CastleBQ := NewBQ
        EnPassant := NewEP
        HalfmoveClock := if (ResetClock?) then 0 else P.HalfmoveClock + 1
        FullmoveNumber := if (P.ToMove = chess_color.Black) then P.FullmoveNumber + 1 else P.FullmoveNumber

UpdateRight<internal>(Right:logic, M:chess_move, KingSq:int, RookSq:int)<computes>:logic =
    if (Right?, not (M.From = KingSq), not (M.From = RookSq), not (M.To = RookSq)):
        true
    else:
        false

# --- Legality ------------------------------------------------------------------

# Pseudo-legal and does not leave own king in check.
IsLegal<public>(P:chess_position, M:chess_move)<transacts><decides>:void =
    Pseudo := PseudoMovesFrom(P, M.From)
    first (PM : Pseudo, SameMove[PM, M]) { PM }
    Next := Apply[P, M]
    not InCheck[Next, P.ToMove]

LegalMovesFrom<public>(P:chess_position, From:int)<transacts>:[]chess_move =
    for:
        M : PseudoMovesFrom(P, From)
        Next := Apply[P, M]
        not InCheck[Next, P.ToMove]
    do:
        M

AllLegalMoves<public>(P:chess_position)<transacts>:[]chess_move =
    var Moves:[]chess_move = array{}
    for (Sq := 0..63):
        set Moves += LegalMovesFrom(P, Sq)
    Moves

HasLegalMove<public>(P:chess_position)<transacts><decides>:void =
    var Found:logic = false
    for (Sq := 0..63):
        if (not Found?, LegalMovesFrom(P, Sq).Length > 0):
            set Found = true
    Found?

IsCheckmate<public>(P:chess_position)<transacts><decides>:void =
    InCheck[P, P.ToMove]
    not HasLegalMove[P]

IsStalemate<public>(P:chess_position)<transacts><decides>:void =
    not InCheck[P, P.ToMove]
    not HasLegalMove[P]

# King vs king, king+minor vs king. (Skips same-color-bishops case.)
# Count-gated: a failing for body skips, it doesn't fail the function.
IsInsufficientMaterial<public>(P:chess_position)<transacts><decides>:void =
    NonKings := for:
        Sq -> MaybePc : P.Squares
        Pc := MaybePc?
        not (Pc.Kind = chess_piece_kind.King)
    do:
        Pc
    NonKings.Length <= 1
    Minors := for:
        Pc : NonKings
        Pc.Kind = chess_piece_kind.Knight or Pc.Kind = chess_piece_kind.Bishop
    do:
        Pc
    Minors.Length = NonKings.Length
