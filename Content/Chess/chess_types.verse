# Core chess types and square/text helpers. No parametrics anywhere in the
# Chess module, so the 3502 bug family does not apply and this is a normal
# folder module.
#
# Board layout: squares 0..63, a1 = 0, h1 = 7, a8 = 56, h8 = 63.
# Rank 0..7 (chess ranks 1..8), file 0..7 (a..h). White pawns move +8.

chess_color<public> := enum:
    White
    Black

chess_piece_kind<public> := enum:
    Pawn
    Knight
    Bishop
    Rook
    Queen
    King

chess_piece<public> := struct:
    Color<public>:chess_color
    Kind<public>:chess_piece_kind

# From/To are square indices. Promo is set on promotion moves only.
# Castling is encoded as the king moving two files (e1g1 etc).
chess_move<public> := struct:
    From<public>:int
    To<public>:int
    Promo<public>:?chess_piece_kind = false

chess_result<public> := enum:
    WhiteWinsCheckmate
    BlackWinsCheckmate
    WhiteWinsResignation
    BlackWinsResignation
    DrawStalemate
    DrawFiftyMove
    DrawThreefold
    DrawInsufficientMaterial

# Immutable snapshot of a game state. Rules functions take one and return a
# new one; the mutable shell lives in chess_game.
chess_position<public> := class:
    Squares<public>:[]?chess_piece   # 64 entries
    ToMove<public>:chess_color
    CastleWK<public>:logic
    CastleWQ<public>:logic
    CastleBK<public>:logic
    CastleBQ<public>:logic
    # Capture-destination square of a legal en passant, if any.
    EnPassant<public>:?int
    HalfmoveClock<public>:int
    FullmoveNumber<public>:int


(C:chess_color).Opposite<public>()<computes>:chess_color =
    case (C):
        chess_color.White => chess_color.Black
        chess_color.Black => chess_color.White

# --- Square geometry ---------------------------------------------------------

RankOf<public>(Sq:int)<computes><decides>:int =
    Floor(Sq / 8)

FileOf<public>(Sq:int)<computes><decides>:int =
    Sq - (Floor(Sq / 8) * 8)

SquareAt<public>(F:int, R:int)<computes>:int =
    R * 8 + F

OnBoardFR<public>(F:int, R:int)<computes><decides>:void =
    F >= 0
    F <= 7
    R >= 0
    R <= 7

# --- Text ---------------------------------------------------------------------

FileChars<internal>:string = "abcdefgh"
RankChars<internal>:string = "12345678"
PromoChars<internal>:string = "qrbn"
PromoKinds<internal>:[]chess_piece_kind = array{
    chess_piece_kind.Queen, chess_piece_kind.Rook,
    chess_piece_kind.Bishop, chess_piece_kind.Knight}

# "e4" style. Fails on a bad square index.
SquareText<public>(Sq:int)<transacts><decides>:string =
    F := FileOf[Sq]
    R := RankOf[Sq]
    FC := FileChars[F]
    RC := RankChars[R]
    "{FC}{RC}"

# Fails on anything that isn't two chars naming a square.
TextToSquare<public>(S:string)<transacts><decides>:int =
    S.Length = 2
    F := first (I -> C : FileChars, C = S[0]) { I }
    R := first (I -> C : RankChars, C = S[1]) { I }
    SquareAt(F, R)

# "e2e4" or "e7e8q". Fails on malformed text.
ParseMoveText<public>(S:string)<transacts><decides>:chess_move =
    S.Length >= 4
    S.Length <= 5
    FromText := S.Slice[0, 2]
    ToText := S.Slice[2, 4]
    From := TextToSquare[FromText]
    To := TextToSquare[ToText]
    if (S.Length = 5):
        PI := first (I -> C : PromoChars, C = S[4]) { I }
        K := PromoKinds[PI]
        chess_move{From := From, To := To, Promo := option{K}}
    else:
        chess_move{From := From, To := To}

MoveText<public>(M:chess_move)<transacts><decides>:string =
    FromText := SquareText[M.From]
    ToText := SquareText[M.To]
    if (K := M.Promo?):
        PI := first (I -> PK : PromoKinds, PK = K) { I }
        PC := PromoChars[PI]
        "{FromText}{ToText}{PC}"
    else:
        "{FromText}{ToText}"

# FEN letter, uppercase for White.
PieceLetter<public>(Pc:chess_piece)<computes>:string =
    if (Pc.Color = chess_color.White):
        case (Pc.Kind):
            chess_piece_kind.Pawn => "P"
            chess_piece_kind.Knight => "N"
            chess_piece_kind.Bishop => "B"
            chess_piece_kind.Rook => "R"
            chess_piece_kind.Queen => "Q"
            chess_piece_kind.King => "K"
    else:
        case (Pc.Kind):
            chess_piece_kind.Pawn => "p"
            chess_piece_kind.Knight => "n"
            chess_piece_kind.Bishop => "b"
            chess_piece_kind.Rook => "r"
            chess_piece_kind.Queen => "q"
            chess_piece_kind.King => "k"

SameMove<public>(A:chess_move, B:chess_move)<computes><decides>:void =
    A.From = B.From
    A.To = B.To
    if (PA := A.Promo?):
        PB := B.Promo?
        PA = PB
    else:
        not B.Promo?
