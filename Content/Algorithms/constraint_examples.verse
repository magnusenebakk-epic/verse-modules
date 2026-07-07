# Two classic problems on the same csp_solver, showing the engine is
# generic: Sudoku is pure all_different; N-Queens adds a custom constraint.

# --- Sudoku ------------------------------------------------------------------
# Variables 0..80 (row major), domains 1..9, 27 all_different constraints.
# Givens as a [int]int of cell -> value. Fails if unsolvable.

SolveSudoku<public>(Givens:[int]int)<transacts><decides>:[int]int =
    S := csp_solver{}
    for (Cell := 0..80):
        S.AddVariable(Cell, 1, 9)
    for (R := 0..8):
        S.AddConstraint(all_different{Vars := for (C := 0..8) { R * 9 + C }})
    for (C := 0..8):
        S.AddConstraint(all_different{Vars := for (R := 0..8) { R * 9 + C }})
    for (BR := 0..2, BC := 0..2):
        S.AddConstraint(all_different{Vars := for (R := 0..2, C := 0..2) { (BR * 3 + R) * 9 + (BC * 3 + C) }})
    for (Cell -> Val : Givens):
        S.Assign[Cell, Val]
    S.Solve[]


# --- N-Queens ----------------------------------------------------------------
# Variable per row, value = column. all_different covers columns; diagonals
# need a custom constraint: queens I and J clash when |Col_I - Col_J| = |I - J|.
# Prunes singles: once a queen is placed, its diagonal cells leave the
# other domains.

no_diagonal_attack<public> := class(csp_constraint):
    N<public>:int

    Prune<override>(S:csp_solver)<transacts>:logic =
        var Narrowed:logic = false
        for:
            I := 0..N - 1
            D := S.GetDomain[I]
            D.Length = 1
            Col := D[0]
        do:
            for (J := 0..N - 1, not (J = I)):
                Dist := Abs(I - J)
                for (Bad : array{Col - Dist, Col + Dist}):
                    Changed := S.Eliminate(J, Bad)
                    if (Changed?):
                        set Narrowed = true
        Narrowed


# Row -> column of the queen. Fails only for N where no solution exists
# (2 and 3).
SolveNQueens<public>(N:int)<transacts><decides>:[int]int =
    S := csp_solver{}
    for (Row := 0..N - 1):
        S.AddVariable(Row, 0, N - 1)
    S.AddConstraint(all_different{Vars := for (Row := 0..N - 1) { Row }})
    S.AddConstraint(no_diagonal_attack{N := N})
    S.Solve[]


# --- Log helpers -------------------------------------------------------------

PrintSudoku<public>(Sol:[int]int):void =
    # Interpolation only takes ToString-able types (int/float/char/string),
    # not arrays. Build the line digit by digit.
    for (R := 0..8):
        var Line:string = ""
        for (C := 0..8, V := Sol[R * 9 + C]):
            set Line = "{Line}{V} "
        Print(Line)

PrintQueens<public>(N:int, Sol:[int]int):void =
    for (R := 0..N - 1, Col := Sol[R]):
        Print("row {R}: queen at column {Col}")
