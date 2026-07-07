# Static evaluation: material + piece-square tables (Michniewski's
# "simplified evaluation" values, public domain). Centipawns, returned from
# the side-to-move's perspective so negamax can negate uniformly.
#
# Tables are printed rank 8 first (like a diagram from White's side), so
# indexing mirrors by color: White reads (7-R)*8+F, Black reads R*8+F.
# No division anywhere: the king switches midgame/endgame table by a
# material threshold instead of a tapered blend.

PawnValue<public>:int = 100
KnightValue<public>:int = 320
BishopValue<public>:int = 330
RookValue<public>:int = 500
QueenValue<public>:int = 900

PieceValue<public>(K:chess_piece_kind)<computes>:int =
    case (K):
        chess_piece_kind.Pawn => PawnValue
        chess_piece_kind.Knight => KnightValue
        chess_piece_kind.Bishop => BishopValue
        chess_piece_kind.Rook => RookValue
        chess_piece_kind.Queen => QueenValue
        chess_piece_kind.King => 0

PawnTable<internal>:[]int = array{
     0,  0,  0,  0,  0,  0,  0,  0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
     5,  5, 10, 25, 25, 10,  5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5, -5,-10,  0,  0,-10, -5,  5,
     5, 10, 10,-20,-20, 10, 10,  5,
     0,  0,  0,  0,  0,  0,  0,  0}

KnightTable<internal>:[]int = array{
   -50,-40,-30,-30,-30,-30,-40,-50,
   -40,-20,  0,  0,  0,  0,-20,-40,
   -30,  0, 10, 15, 15, 10,  0,-30,
   -30,  5, 15, 20, 20, 15,  5,-30,
   -30,  0, 15, 20, 20, 15,  0,-30,
   -30,  5, 10, 15, 15, 10,  5,-30,
   -40,-20,  0,  5,  5,  0,-20,-40,
   -50,-40,-30,-30,-30,-30,-40,-50}

BishopTable<internal>:[]int = array{
   -20,-10,-10,-10,-10,-10,-10,-20,
   -10,  0,  0,  0,  0,  0,  0,-10,
   -10,  0,  5, 10, 10,  5,  0,-10,
   -10,  5,  5, 10, 10,  5,  5,-10,
   -10,  0, 10, 10, 10, 10,  0,-10,
   -10, 10, 10, 10, 10, 10, 10,-10,
   -10,  5,  0,  0,  0,  0,  5,-10,
   -20,-10,-10,-10,-10,-10,-10,-20}

RookTable<internal>:[]int = array{
     0,  0,  0,  0,  0,  0,  0,  0,
     5, 10, 10, 10, 10, 10, 10,  5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
     0,  0,  0,  5,  5,  0,  0,  0}

QueenTable<internal>:[]int = array{
   -20,-10,-10, -5, -5,-10,-10,-20,
   -10,  0,  0,  0,  0,  0,  0,-10,
   -10,  0,  5,  5,  5,  5,  0,-10,
    -5,  0,  5,  5,  5,  5,  0, -5,
     0,  0,  5,  5,  5,  5,  0, -5,
   -10,  5,  5,  5,  5,  5,  0,-10,
   -10,  0,  5,  0,  0,  0,  0,-10,
   -20,-10,-10, -5, -5,-10,-10,-20}

KingMidTable<internal>:[]int = array{
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -20,-30,-30,-40,-40,-30,-30,-20,
   -10,-20,-20,-20,-20,-20,-20,-10,
    20, 20,  0,  0,  0,  0, 20, 20,
    20, 30, 10,  0,  0, 10, 30, 20}

KingEndTable<internal>:[]int = array{
   -50,-40,-30,-20,-20,-30,-40,-50,
   -30,-20,-10,  0,  0,-10,-20,-30,
   -30,-10, 20, 30, 30, 20,-10,-30,
   -30,-10, 30, 40, 40, 30,-10,-30,
   -30,-10, 30, 40, 40, 30,-10,-30,
   -30,-10, 20, 30, 30, 20,-10,-30,
   -30,-30,  0,  0,  0,  0,-30,-30,
   -50,-30,-30,-30,-30,-30,-50,-50}

# Endgame when total non-pawn, non-king material is at most this
# (roughly a rook and a bishop per side).
EndgameMaterial<internal>:int = 1700

TableFor<internal>(K:chess_piece_kind, Endgame:logic)<computes>:[]int =
    case (K):
        chess_piece_kind.Pawn => PawnTable
        chess_piece_kind.Knight => KnightTable
        chess_piece_kind.Bishop => BishopTable
        chess_piece_kind.Rook => RookTable
        chess_piece_kind.Queen => QueenTable
        chess_piece_kind.King => if (Endgame?) then KingEndTable else KingMidTable

# Score from P.ToMove's perspective. Small tempo bonus for the mover.
# Single board pass (this runs at every quiescence leaf): material and
# PST accumulate together; the endgame king table is patched in after,
# only when the king-count materially matters.
EvaluatePosition<public>(P:chess_position)<transacts>:int =
    var NonPawnMaterial:int = 0
    var WhiteScore:int = 0
    var WKingSq:int = P.WhiteKing
    var BKingSq:int = P.BlackKing
    for:
        Sq -> MaybePc : P.Squares
        Pc := MaybePc?
        F := FileOf[Sq]
        R := RankOf[Sq]
    do:
        if (not (Pc.Kind = chess_piece_kind.Pawn)):
            set NonPawnMaterial += PieceValue(Pc.Kind)
        Table := TableFor(Pc.Kind, false)   # midgame tables in the main pass
        Idx := if (Pc.Color = chess_color.White) then (7 - R) * 8 + F else R * 8 + F
        Bonus := Table[Idx] or 0
        Delta := PieceValue(Pc.Kind) + Bonus
        if (Pc.Color = chess_color.White):
            set WhiteScore += Delta
        else:
            set WhiteScore -= Delta
    # Endgame: swap the kings' midgame PST contribution for the endgame one.
    if (NonPawnMaterial <= EndgameMaterial):
        set WhiteScore += KingTableSwap(WKingSq, chess_color.White)
        set WhiteScore -= KingTableSwap(BKingSq, chess_color.Black)
    Signed := if (P.ToMove = chess_color.White) then WhiteScore else -WhiteScore
    Signed + 10

# Endgame-minus-midgame king PST delta for the king on Sq.
KingTableSwap<internal>(Sq:int, C:chess_color)<transacts>:int =
    if (F := FileOf[Sq], R := RankOf[Sq]):
        Idx := if (C = chess_color.White) then (7 - R) * 8 + F else R * 8 + F
        EndB := KingEndTable[Idx] or 0
        MidB := KingMidTable[Idx] or 0
        EndB - MidB
    else:
        0
