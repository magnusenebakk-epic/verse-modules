# minilang tree-walking interpreter. Environments are class instances
# chained by Parent, so closures come for free: a closure_value pairs the
# fn AST with the environment it was evaluated in, and calls chain a fresh
# frame onto it. BPVM Verse has no closures; minilang does.
#
# Runtime errors (type mismatch, unknown name, div by zero, fuel out) are
# reported by failure: Eval* are <decides>, and the whole program run is
# one failure context. Fuel bounds total work so a `while true` script
# can't hang the server.

value<public> := class<abstract><castable>:

int_value<public> := class(value):
    N<public>:int

str_value<public> := class(value):
    S<public>:string

bool_value<public> := class(value):
    B<public>:logic

unit_value<public> := class(value):

closure_value<public> := class(value):
    Fn<public>:fn_expr
    Captured<public>:env


env<public> := class:
    Parent<public>:?env = false
    var Bindings<internal>:[string]value = map{}

    # Define in this frame (let / params). Shadowing outer frames is fine,
    # redefining in the same frame just overwrites.
    Define<public>(Name:string, V:value)<transacts>:void =
        if (set Bindings[Name] = V) {}

    # Walk the chain. Fails on unknown name.
    Lookup<public>(Name:string)<transacts><decides>:value =
        Bindings[Name] or Parent?.Lookup[Name]

    # Assign to the nearest frame that defines Name. Fails if none does.
    AssignExisting<public>(Name:string, V:value)<transacts><decides>:void =
        if (Bindings[Name]):
            if (set Bindings[Name] = V) {}
        else:
            Parent?.AssignExisting[Name, V]


# Statement outcome: normal flow or an early return unwinding call frames.
exec_result<internal> := class<abstract><castable>:
normal_result<internal> := class(exec_result):
return_result<internal> := class(exec_result):
    V<public>:value


interpreter<public> := class:

    # Total budget across the whole run; each Eval step spends 1. Also
    # bounds single-frame work: a `while true` burns this out and fails.
    # fib(12) costs roughly 5k.
    var Fuel<internal>:int = 20000

    # minilang call depth cap. The VM unrecoverably kills at ~120 TOTAL
    # Verse stack frames (measured: a 64 cap here never fired, kill came
    # first). One minilang call costs ~4-5 host frames (Eval, EvalCall,
    # ExecBlock, ExecStmt), so budget is ~120/5 with margin.
    MaxCallDepth<internal>:int = 20
    var Depth<internal>:int = 0

    # Runs a program; false and a printed message on any runtime error.
    Run<public>(Program:[]stmt):?value =
        Globals := env{}
        Outcome := option{ExecBlock[Program, Globals]}
        if (R := Outcome?):
            if (Ret := return_result[R]):
                option{Ret.V}
            else:
                option{value_unit()}
        else:
            Print("minilang: runtime error (unknown name, type mismatch, div by zero, or out of fuel)")
            false

    # --- Statements ----------------------------------------------------------

    # First return short-circuits the rest of the block.
    ExecBlock<internal>(Body:[]stmt, E:env)<transacts><decides>:exec_result =
        var Result:exec_result = normal_result{}
        var Failed:logic = false
        for (S : Body, not Failed?, not return_result[Result]):
            if (R := option{ExecStmt[S, E]}?):
                set Result = R
            else:
                set Failed = true
        not Failed?
        Result

    ExecStmt<internal>(S:stmt, E:env)<transacts><decides>:exec_result =
        Spend[]
        var Out:?exec_result = false
        if (Let := let_stmt[S]):
            V := Eval[Let.Init, E]
            E.Define(Let.Name, V)
            set Out = option{normal_result{}}
        else if (Asn := assign_stmt[S]):
            V := Eval[Asn.ValueExpr, E]
            E.AssignExisting[Asn.Name, V]
            set Out = option{normal_result{}}
        else if (ExprS := expr_stmt[S]):
            Ignored := Eval[ExprS.E, E]
            set Out = option{normal_result{}}
        else if (IfS := if_stmt[S]):
            Cond := EvalBool[IfS.Cond, E]
            Body := if (Cond?) then IfS.ThenBody else IfS.ElseBody
            Scope := env{Parent := option{E}}
            set Out = option{ExecBlock[Body, Scope]}
        else if (WhileS := while_stmt[S]):
            set Out = option{ExecWhile[WhileS, E]}
        else if (Ret := return_stmt[S]):
            V := if (VE := Ret.ValueExpr?) then Eval[VE, E] else value_unit()
            set Out = option{return_result{V := V}}
        Out?

    # Iterates with loop, NOT recursion: the VM unrecoverably kills
    # same-function recursion at ~120 frames. Failure inside cond/body is
    # captured per iteration and re-raised after the loop.
    ExecWhile<internal>(W:while_stmt, E:env)<transacts><decides>:exec_result =
        var Out:exec_result = normal_result{}
        var Failed:logic = false
        loop:
            MaybeCond := option{EvalBool[W.Cond, E]}
            if (Cond := MaybeCond?):
                if (Cond?):
                    Scope := env{Parent := option{E}}
                    MaybeR := option{ExecBlock[W.Body, Scope]}
                    if (R := MaybeR?):
                        if (return_result[R]):
                            set Out = R
                            break
                    else:
                        set Failed = true
                        break
                else:
                    break
            else:
                set Failed = true
                break
        not Failed?
        Out

    # --- Expressions ---------------------------------------------------------

    Eval<internal>(Ex:expr, E:env)<transacts><decides>:value =
        Spend[]
        var Out:?value = false
        if (I := int_literal[Ex]):
            set Out = option{int_value{N := I.Value}}
        else if (S := str_literal[Ex]):
            set Out = option{str_value{S := S.Value}}
        else if (B := bool_literal[Ex]):
            set Out = option{bool_value{B := B.Value}}
        else if (Nm := name_expr[Ex]):
            set Out = option{E.Lookup[Nm.Name]}
        else if (U := unary_expr[Ex]):
            set Out = option{EvalUnary[U, E]}
        else if (Bin := binary_expr[Ex]):
            set Out = option{EvalBinary[Bin, E]}
        else if (Fn := fn_expr[Ex]):
            set Out = option{closure_value{Fn := Fn, Captured := E}}   # capture here
        else if (Call := call_expr[Ex]):
            set Out = option{EvalCall[Call, E]}
        Out?

    EvalUnary<internal>(U:unary_expr, E:env)<transacts><decides>:value =
        if (U.Op = token_kind.Minus):
            V := EvalInt[U.Operand, E]
            int_value{N := -V}
        else:
            U.Op = token_kind.NotKw
            B := EvalBool[U.Operand, E]
            bool_value{B := if (B?) then false else true}

    EvalBinary<internal>(B:binary_expr, E:env)<transacts><decides>:value =
        L := Eval[B.Lhs, E]
        R := Eval[B.Rhs, E]
        var Out:?value = false
        if (B.Op = token_kind.Plus):
            # Int addition, or string concat when either side is a string.
            if (LI := int_value[L], RI := int_value[R]):
                set Out = option{int_value{N := LI.N + RI.N}}
            else:
                set Out = option{str_value{S := "{ToText(L)}{ToText(R)}"}}
        else if (B.Op = token_kind.Minus, LI := int_value[L], RI := int_value[R]):
            set Out = option{int_value{N := LI.N - RI.N}}
        else if (B.Op = token_kind.Star, LI := int_value[L], RI := int_value[R]):
            set Out = option{int_value{N := LI.N * RI.N}}
        else if (B.Op = token_kind.Slash, LI := int_value[L], RI := int_value[R]):
            Q := Floor(LI.N / RI.N)   # fails on zero divisor
            set Out = option{int_value{N := Q}}
        else if (B.Op = token_kind.EqEq):
            set Out = option{bool_value{B := ValueEquals(L, R)}}
        else if (B.Op = token_kind.Ne):
            Eq := ValueEquals(L, R)
            set Out = option{bool_value{B := if (Eq?) then false else true}}
        else if (LI := int_value[L], RI := int_value[R]):
            # Remaining ops are int comparisons.
            var Truth:logic = false
            if (B.Op = token_kind.Lt, LI.N < RI.N):
                set Truth = true
            else if (B.Op = token_kind.Gt, LI.N > RI.N):
                set Truth = true
            else if (B.Op = token_kind.Le, LI.N <= RI.N):
                set Truth = true
            else if (B.Op = token_kind.Ge, LI.N >= RI.N):
                set Truth = true
            set Out = option{bool_value{B := Truth}}
        Out?

    EvalCall<internal>(Call:call_expr, E:env)<transacts><decides>:value =
        # print is a builtin, not a value: check the callee by name first.
        if (Nm := name_expr[Call.Callee], Nm.Name = "print", not option{E.Lookup[Nm.Name]}?):
            # Args evaluated with plain propagation: print(nope) must FAIL,
            # not skip (a failing for filter skips the iteration).
            var Texts:[]string = array{}
            for (A : Call.Args):
                V := Eval[A, E]
                set Texts += array{ToText(V)}
            for (T : Texts):
                Print("minilang> {T}")
            unit_value{}
        else:
            CalleeV := Eval[Call.Callee, E]
            Closure := closure_value[CalleeV]
            Closure.Fn.Params.Length = Call.Args.Length
            # Host recursion guard: EvalCall -> ExecBlock -> Eval -> EvalCall
            # deepens the HOST stack; the VM kills it around 120 frames.
            Depth < MaxCallDepth
            Frame := env{Parent := option{Closure.Captured}}   # lexical, not dynamic
            # Args evaluated with plain propagation (a failing for body would
            # skip the binding, not fail the call), then bound pairwise.
            var ArgVals:[]value = array{}
            for (A : Call.Args):
                V := Eval[A, E]
                set ArgVals += array{V}
            for (I -> P : Closure.Fn.Params, V := ArgVals[I]):
                Frame.Define(P, V)
            set Depth += 1
            MaybeR := option{ExecBlock[Closure.Fn.Body, Frame]}
            set Depth -= 1
            R := MaybeR?
            if (Ret := return_result[R]):
                Ret.V
            else:
                unit_value{}

    # --- Helpers -------------------------------------------------------------

    EvalInt<internal>(Ex:expr, E:env)<transacts><decides>:int =
        int_value[Eval[Ex, E]].N

    EvalBool<internal>(Ex:expr, E:env)<transacts><decides>:logic =
        bool_value[Eval[Ex, E]].B

    ValueEquals<internal>(L:value, R:value)<transacts>:logic =
        var Eq:logic = false
        if (LI := int_value[L], RI := int_value[R], LI.N = RI.N):
            set Eq = true
        else if (LS := str_value[L], RS := str_value[R], LS.S = RS.S):
            set Eq = true
        else if (LB := bool_value[L], RB := bool_value[R], LB.B = RB.B):
            set Eq = true
        Eq

    Spend<internal>()<transacts><decides>:void =
        Fuel > 0
        set Fuel -= 1


ToText<public>(V:value)<transacts>:string =
    if (I := int_value[V]):
        "{I.N}"
    else if (S := str_value[V]):
        S.S
    else if (B := bool_value[V]):
        if (B.B?) then "true" else "false"
    else if (closure_value[V]):
        "<fn>"
    else:
        "unit"

value_unit<internal>()<transacts>:unit_value = unit_value{}


# Source to result in one call. Tokenize/ParseProgram print on error, so
# they are no_rollback: hoist the calls out of the if conditions (3512).
RunMinilang<public>(Source:string):?value =
    L := lexer{Source := Source}
    MaybeToks := L.Tokenize()
    if (Toks := MaybeToks?):
        P := parser{Toks := Toks}
        MaybeProgram := P.ParseProgram()
        if (Program := MaybeProgram?):
            interpreter{}.Run(Program)
        else:
            false
    else:
        false
