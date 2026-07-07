# Finite-domain constraint solver: propagation to fixpoint + backtracking
# search (MRV heuristic). Variables are ints 0..N-1, domains are []int.
#
# The whole backtracking engine is the `or` in TryCandidates. A trying
# branch assigns, propagates and recurses speculatively inside a <decides>
# context; if it dead-ends, STM rolls back every domain change it made and
# the next candidate starts from clean state. Solvers like Gecode implement
# this with explicit trail stacks; here it's language semantics.
#
# Architecture note: a failing expression in a `for` body only skips that
# iteration, it doesn't fail the enclosing function. So constraint Prune
# hooks are total (they just shrink domains, possibly to empty) and
# inconsistency is detected centrally by HasWipeout after each round,
# where the failure can propagate.

csp_constraint<public> := interface:
    # Shrink domains based on current state. Total: on inconsistency just
    # empty a domain and the solver notices. Returns whether anything changed.
    Prune<public>(S:csp_solver)<transacts>:logic


csp_solver<public> := class:

    var<internal> Domains<public>:[int][]int = map{}
    var<internal> Constraints<public>:[]csp_constraint = array{}

    # --- Setup ---------------------------------------------------------------

    AddVariable<public>(V:int, Lo:int, Hi:int)<transacts>:void =
        if (set Domains[V] = for (X := Lo..Hi) { X }) {}

    AddConstraint<public>(C:csp_constraint)<transacts>:void =
        set Constraints += array{C}

    # Pin a variable, e.g. puzzle givens. Fails if Val isn't in the domain.
    Assign<public>(V:int, Val:int)<transacts><decides>:void =
        D := Domains[V]
        first (X : D, X = Val) { X }
        if (set Domains[V] = array{Val}) {}

    # --- Constraint toolkit --------------------------------------------------

    GetDomain<public>(V:int)<transacts><decides>:[]int =
        Domains[V]

    # Remove Val from V's domain. Total; may empty the domain, which the
    # next HasWipeout check turns into failure.
    Eliminate<public>(V:int, Val:int)<transacts>:logic =
        if (D := Domains[V]):
            New := for (X : D, X <> Val) { X }
            if (New.Length < D.Length):
                if (set Domains[V] = New) {}
                true
            else:
                false
        else:
            false

    # --- Solving -------------------------------------------------------------

    # Solution as variable -> value. Fails if no assignment satisfies all
    # constraints. Everything below runs speculatively under the caller's
    # failure context.
    Solve<public>()<transacts><decides>:[int]int =
        Propagate[]
        if (V := PickMRV[]):
            Cands := Domains[V]
            TryCandidates[V, Cands]
        else:
            # No branching variable left and no wipeout: all singletons.
            Extract()

    # Run every constraint until a full round changes nothing. Fails on
    # wipeout (some domain emptied), which means this branch is inconsistent.
    Propagate<public>()<transacts><decides>:void =
        var Failed:logic = false
        var Dirty:logic = true
        loop:
            if (not Dirty?):
                break
            set Dirty = false
            for (C : Constraints):
                Pruned := C.Prune(Self)
                if (Pruned?):
                    set Dirty = true
            if (HasWipeout[]):
                set Failed = true
                break
        not Failed?

    # Try each candidate for V in order. The `or` is the backtracker: a
    # failed left arm rolls back its assign, its propagation and the whole
    # recursive subtree before the right arm runs.
    TryCandidates<internal>(V:int, Cands:[]int)<transacts><decides>:[int]int =
        Val := Cands[0]
        TryOne[V, Val] or TryCandidates[V, Cands.Slice[1]]

    TryOne<internal>(V:int, Val:int)<transacts><decides>:[int]int =
        Assign[V, Val]
        Solve[]

    # Smallest domain with more than one value. Fails when all singleton.
    # Map iteration is insertion order, so ties break to the lowest id.
    PickMRV<internal>()<transacts><decides>:int =
        var BestV:?int = false
        var BestSize:int = 2147483647
        for (V -> D : Domains, D.Length > 1):
            if (D.Length < BestSize):
                set BestV = option{V}
                set BestSize = D.Length
        BestV?

    HasWipeout<internal>()<transacts><decides>:void =
        Empties := for (V -> D : Domains, D.Length = 0) { V }
        Empties.Length > 0

    # All domains are singletons here: Propagate ruled out empties and
    # PickMRV ruled out size > 1.
    Extract<internal>()<transacts>:[int]int =
        var Sol:[int]int = map{}
        for (V -> D : Domains, Val := D[0]):
            if (set Sol[V] = Val) {}
        Sol


# All variables take pairwise distinct values. Pruning: naked singles, an
# assigned value is removed from every peer domain.
all_different<public> := class(csp_constraint):
    Vars<public>:[]int

    Prune<override>(S:csp_solver)<transacts>:logic =
        var Narrowed:logic = false
        for:
            V : Vars
            D := S.GetDomain[V]
            D.Length = 1
            Val := D[0]
        do:
            for (W : Vars, not (W = V)):
                Changed := S.Eliminate(W, Val)
                if (Changed?):
                    set Narrowed = true
        Narrowed
