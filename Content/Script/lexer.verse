# minilang lexer: string in, tokens out. Dispatch is failure-native, see
# NextToken: each Lex* gates on its first char and fails otherwise, so
# alternation is just `or` and an unknown char fails them all.
#
# Diagnostics and rollback: a failed NextToken rolls Pos and Line back to
# the token start, so Tokenize can report an accurate error position after
# the failure, even though nothing set inside the attempt survives.

token_kind<public> := enum:
    LetKw
    FnKw
    IfKw
    ElseKw
    WhileKw
    ReturnKw
    DoKw
    EndKw
    TrueKw
    FalseKw
    NotKw
    Ident
    IntLit
    StrLit
    Plus
    Minus
    Star
    Slash
    Lt
    Gt
    Le
    Ge
    EqEq
    Ne
    Assign
    LParen
    RParen
    Comma
    Semicolon
    EndOfFile


token<public> := class:
    Kind<public>:token_kind
    Text<public>:string
    IntVal<public>:int = 0
    Line<public>:int


Keywords<internal>:[string]token_kind = map{
    "let" => token_kind.LetKw,
    "fn" => token_kind.FnKw,
    "if" => token_kind.IfKw,
    "else" => token_kind.ElseKw,
    "while" => token_kind.WhileKw,
    "return" => token_kind.ReturnKw,
    "do" => token_kind.DoKw,
    "end" => token_kind.EndKw,
    "true" => token_kind.TrueKw,
    "false" => token_kind.FalseKw,
    "not" => token_kind.NotKw}


# Index in the digit string is the digit's value.
DigitVal<public>(C:char)<transacts><decides>:int =
    first (I -> D : "0123456789", D = C) { I }

IsDigit<public>(C:char)<transacts><decides>:void =
    DigitVal[C]

# Char has no ordering in Verse, so membership in a set string instead of
# range checks.
IsAlpha<public>(C:char)<transacts><decides>:void =
    first (A : "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_", A = C) { A }

IsIdentChar<public>(C:char)<transacts><decides>:void =
    IsAlpha[C] or IsDigit[C]


lexer<public> := class:

    Source<public>:string
    var Pos<internal>:int = 0
    var Line<internal>:int = 1

    # False on a lex error, with a printed message.
    Tokenize<public>():?[]token =
        var Toks:[]token = array{}
        var Failed:logic = false
        loop:
            SkipTrivia()
            if (not AtEnd[]):
                MaybeTok := option{NextToken[]}
                if (T := MaybeTok?):
                    set Toks += array{T}
                else:
                    set Failed = true
                    break
            else:
                break
        if (Failed?):
            BadText := CurrentCharText()
            Print("minilang lex error at line {Line} near '{BadText}'")
            false
        else:
            set Toks += array{token{Kind := token_kind.EndOfFile, Text := "", Line := Line}}
            option{Toks}

    AtEnd<internal>()<transacts><decides>:void =
        not Source[Pos]

    NextToken<internal>()<transacts><decides>:token =
        LexNumber[] or LexIdentOrKeyword[] or LexString[] or LexSymbol[]

    LexNumber<internal>()<transacts><decides>:token =
        IsDigit[Source[Pos]]
        Start := Pos
        loop:
            if (C := Source[Pos], IsDigit[C]):
                set Pos += 1
            else:
                break
        Text := Source.Slice[Start, Pos]
        var N:int = 0
        for (C : Text):
            set N = N * 10 + (DigitVal[C] or 0)
        token{Kind := token_kind.IntLit, Text := Text, IntVal := N, Line := Line}

    LexIdentOrKeyword<internal>()<transacts><decides>:token =
        IsAlpha[Source[Pos]]
        Start := Pos
        loop:
            if (C := Source[Pos], IsIdentChar[C]):
                set Pos += 1
            else:
                break
        Text := Source.Slice[Start, Pos]
        Kind := Keywords[Text] or token_kind.Ident
        token{Kind := Kind, Text := Text, Line := Line}

    # No escape sequences; fails (unterminated) if the file ends first.
    LexString<internal>()<transacts><decides>:token =
        Source[Pos] = '\"'
        Start := Pos + 1
        set Pos += 1
        loop:
            if (C := Source[Pos], not (C = '\"')):
                set Pos += 1
            else:
                break
        Source[Pos] = '\"'
        Text := Source.Slice[Start, Pos]
        set Pos += 1
        token{Kind := token_kind.StrLit, Text := Text, Line := Line}

    LexSymbol<internal>()<transacts><decides>:token =
        var Result:?token = false
        if (K2 := TwoCharKind[]):
            Text := Source.Slice[Pos, Pos + 2] or ""
            set Pos += 2
            set Result = option{token{Kind := K2, Text := Text, Line := Line}}
        else if (C := Source[Pos], K1 := OneCharKind[C]):
            Text := Source.Slice[Pos, Pos + 1] or ""
            set Pos += 1
            set Result = option{token{Kind := K1, Text := Text, Line := Line}}
        Result?

    TwoCharKind<internal>()<transacts><decides>:token_kind =
        C1 := Source[Pos]
        C2 := Source[Pos + 1]
        var K:?token_kind = false
        if (C1 = '=', C2 = '='):
            set K = option{token_kind.EqEq}
        else if (C1 = '!', C2 = '='):
            set K = option{token_kind.Ne}
        else if (C1 = '<', C2 = '='):
            set K = option{token_kind.Le}
        else if (C1 = '>', C2 = '='):
            set K = option{token_kind.Ge}
        K?

    OneCharKind<internal>(C:char)<transacts><decides>:token_kind =
        var K:?token_kind = false
        if (C = '+'):
            set K = option{token_kind.Plus}
        else if (C = '-'):
            set K = option{token_kind.Minus}
        else if (C = '*'):
            set K = option{token_kind.Star}
        else if (C = '/'):
            set K = option{token_kind.Slash}
        else if (C = '<'):
            set K = option{token_kind.Lt}
        else if (C = '>'):
            set K = option{token_kind.Gt}
        else if (C = '='):
            set K = option{token_kind.Assign}
        else if (C = '('):
            set K = option{token_kind.LParen}
        else if (C = ')'):
            set K = option{token_kind.RParen}
        else if (C = ','):
            set K = option{token_kind.Comma}
        else if (C = ';'):
            set K = option{token_kind.Semicolon}
        K?

    # Spaces, newlines (counting lines) and // comments.
    SkipTrivia<internal>():void =
        loop:
            if (C := Source[Pos]):
                if (C = ' ' or C = '\t' or C = '\r'):
                    set Pos += 1
                else if (C = '\n'):
                    set Pos += 1
                    set Line += 1
                else if (C = '/', C2 := Source[Pos + 1], C2 = '/'):
                    SkipLineComment()
                else:
                    break
            else:
                break

    SkipLineComment<internal>():void =
        loop:
            if (C := Source[Pos], not (C = '\n')):
                set Pos += 1
            else:
                break

    CurrentCharText<internal>():string =
        Source.Slice[Pos, Pos + 1] or ""
