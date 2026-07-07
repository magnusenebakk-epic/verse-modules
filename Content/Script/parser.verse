# minilang recursive-descent parser. Precedence climbing:
#   comparison < additive < multiplicative < unary < call < primary
#
# Statement grammar:
#   stmt   := "let" IDENT "=" expr ";"
#           | IDENT "=" expr ";"
#           | "if" expr "do" stmt* ("else" stmt*)? "end"
#           | "while" expr "do" stmt* "end"
#           | "return" expr? ";"
#           | expr ";"
#   fn     := "fn" "(" params ")" "do" stmt* "end"
#
# All Parse* are <decides>; a failed alternative rolls the cursor back, so
# trying statement forms with `or` is safe backtracking. Bodies recurse
# instead of looping (loop retracts the failure context).

parser<public> := class:

    Toks<public>:[]token
    var Pos<internal>:int = 0

    # False on a parse error, with a printed message. Demands full input.
    ParseProgram<public>():?[]stmt =
        MaybeBody := option{ParseStmts[]}
        if:
            Body := MaybeBody?
            Cur := Toks[Pos]
            Cur.Kind = token_kind.EndOfFile
        then:
            option{Body}
        else:
            BadLine := if (T := Toks[Pos]) then T.Line else 0
            BadText := if (T := Toks[Pos]) then T.Text else ""
            Print("minilang parse error at line {BadLine} near '{BadText}'")
            false

    # Zero or more statements: recursion as iteration so that one failed
    # statement fails the sequence cleanly.
    ParseStmts<internal>()<transacts><decides>:[]stmt =
        if (S := option{ParseStmt[]}?):
            array{S} + ParseStmts[]
        else:
            array{}

    ParseStmt<internal>()<transacts><decides>:stmt =
        ParseLet[] or ParseIf[] or ParseWhile[] or ParseReturn[] or ParseAssign[] or ParseExprStmt[]

    ParseLet<internal>()<transacts><decides>:stmt =
        Eat[token_kind.LetKw]
        Name := Eat[token_kind.Ident]
        Eat[token_kind.Assign]
        Init := ParseExpr[]
        Eat[token_kind.Semicolon]
        let_stmt{Name := Name.Text, Init := Init}

    ParseAssign<internal>()<transacts><decides>:stmt =
        Name := Eat[token_kind.Ident]
        Eat[token_kind.Assign]
        ValueExpr := ParseExpr[]
        Eat[token_kind.Semicolon]
        assign_stmt{Name := Name.Text, ValueExpr := ValueExpr}

    ParseIf<internal>()<transacts><decides>:stmt =
        Eat[token_kind.IfKw]
        Cond := ParseExpr[]
        Eat[token_kind.DoKw]
        ThenBody := ParseStmts[]
        ElseBody :=
            if (option{Eat[token_kind.ElseKw]}?):
                ParseStmts[]
            else:
                array{}
        Eat[token_kind.EndKw]
        if_stmt{Cond := Cond, ThenBody := ThenBody, ElseBody := ElseBody}

    ParseWhile<internal>()<transacts><decides>:stmt =
        Eat[token_kind.WhileKw]
        Cond := ParseExpr[]
        Eat[token_kind.DoKw]
        Body := ParseStmts[]
        Eat[token_kind.EndKw]
        while_stmt{Cond := Cond, Body := Body}

    ParseReturn<internal>()<transacts><decides>:stmt =
        Eat[token_kind.ReturnKw]
        ValueExpr := option{ParseExpr[]}
        Eat[token_kind.Semicolon]
        return_stmt{ValueExpr := ValueExpr}

    ParseExprStmt<internal>()<transacts><decides>:stmt =
        E := ParseExpr[]
        Eat[token_kind.Semicolon]
        expr_stmt{E := E}

    # --- Expressions ---------------------------------------------------------

    ParseExpr<internal>()<transacts><decides>:expr =
        ParseComparison[]

    ParseComparison<internal>()<transacts><decides>:expr =
        Lhs := ParseAdditive[]
        if (Op := EatComparisonOp[]):
            Rhs := ParseAdditive[]
            binary_expr{Op := Op, Lhs := Lhs, Rhs := Rhs}
        else:
            Lhs

    EatComparisonOp<internal>()<transacts><decides>:token_kind =
        T := Toks[Pos]
        var Found:?token_kind = false
        for:
            K : array{token_kind.EqEq, token_kind.Ne, token_kind.Lt,
                      token_kind.Gt, token_kind.Le, token_kind.Ge}
            T.Kind = K
        do:
            set Found = option{K}
        R := Found?
        set Pos += 1
        R

    # Left associative: parse one operand, then extend as long as the next
    # token matches. RestAdditive returns (accumulated expr).
    ParseAdditive<internal>()<transacts><decides>:expr =
        First := ParseMultiplicative[]
        RestAdditive[First]

    RestAdditive<internal>(Acc:expr)<transacts><decides>:expr =
        if (Op := EatOneOf[array{token_kind.Plus, token_kind.Minus}]):
            Rhs := ParseMultiplicative[]
            RestAdditive[binary_expr{Op := Op, Lhs := Acc, Rhs := Rhs}]
        else:
            Acc

    ParseMultiplicative<internal>()<transacts><decides>:expr =
        First := ParseUnary[]
        RestMultiplicative[First]

    RestMultiplicative<internal>(Acc:expr)<transacts><decides>:expr =
        if (Op := EatOneOf[array{token_kind.Star, token_kind.Slash}]):
            Rhs := ParseUnary[]
            RestMultiplicative[binary_expr{Op := Op, Lhs := Acc, Rhs := Rhs}]
        else:
            Acc

    ParseUnary<internal>()<transacts><decides>:expr =
        if (Op := EatOneOf[array{token_kind.Minus, token_kind.NotKw}]):
            unary_expr{Op := Op, Operand := ParseUnary[]}
        else:
            ParseCall[]

    # Postfix call chains: f(1)(2).
    ParseCall<internal>()<transacts><decides>:expr =
        First := ParsePrimary[]
        RestCalls[First]

    RestCalls<internal>(Acc:expr)<transacts><decides>:expr =
        if (option{Eat[token_kind.LParen]}?):
            Args := ParseArgs[]
            Eat[token_kind.RParen]
            RestCalls[call_expr{Callee := Acc, Args := Args}]
        else:
            Acc

    ParseArgs<internal>()<transacts><decides>:[]expr =
        if (First := option{ParseExpr[]}?):
            RestArgs[array{First}]
        else:
            array{}

    RestArgs<internal>(Acc:[]expr)<transacts><decides>:[]expr =
        if (option{Eat[token_kind.Comma]}?):
            Next := ParseExpr[]
            RestArgs[Acc + array{Next}]
        else:
            Acc

    ParsePrimary<internal>()<transacts><decides>:expr =
        ParseIntLit[] or ParseStrLit[] or ParseBoolLit[] or ParseFn[] or ParseName[] or ParseParen[]

    ParseIntLit<internal>()<transacts><decides>:expr =
        T := Eat[token_kind.IntLit]
        int_literal{Value := T.IntVal}

    ParseStrLit<internal>()<transacts><decides>:expr =
        T := Eat[token_kind.StrLit]
        str_literal{Value := T.Text}

    ParseBoolLit<internal>()<transacts><decides>:expr =
        if (option{Eat[token_kind.TrueKw]}?):
            bool_literal{Value := true}
        else:
            Eat[token_kind.FalseKw]
            bool_literal{Value := false}

    ParseName<internal>()<transacts><decides>:expr =
        T := Eat[token_kind.Ident]
        name_expr{Name := T.Text}

    ParseParen<internal>()<transacts><decides>:expr =
        Eat[token_kind.LParen]
        E := ParseExpr[]
        Eat[token_kind.RParen]
        E

    ParseFn<internal>()<transacts><decides>:expr =
        Eat[token_kind.FnKw]
        Eat[token_kind.LParen]
        Params := ParseParams[]
        Eat[token_kind.RParen]
        Eat[token_kind.DoKw]
        Body := ParseStmts[]
        Eat[token_kind.EndKw]
        fn_expr{Params := Params, Body := Body}

    ParseParams<internal>()<transacts><decides>:[]string =
        if (First := option{Eat[token_kind.Ident]}?):
            RestParams[array{First.Text}]
        else:
            array{}

    RestParams<internal>(Acc:[]string)<transacts><decides>:[]string =
        if (option{Eat[token_kind.Comma]}?):
            Next := Eat[token_kind.Ident]
            RestParams[Acc + array{Next.Text}]
        else:
            Acc

    # --- Cursor --------------------------------------------------------------

    Eat<internal>(K:token_kind)<transacts><decides>:token =
        T := Toks[Pos]
        T.Kind = K
        set Pos += 1
        T

    EatOneOf<internal>(Kinds:[]token_kind)<transacts><decides>:token_kind =
        T := Toks[Pos]
        Matched := first (K : Kinds, T.Kind = K) { K }
        set Pos += 1
        Matched
