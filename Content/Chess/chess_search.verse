# Negamax + alpha-beta + quiescence over the pure rules.
#
# Two VM constraints shape the architecture:
#
# 1. No long blocking compute (runtime "Computation timed out" kill), so
#    the RECURSION ITSELF is <suspends>: SpendNode() sleeps one tick every
#    NodesPerFrame nodes, wherever the search happens to be. Legal because
#    the recursion is total (no <decides>), and coroutines keep the whole
#    recursion stack alive across the suspend. NodesPerFrame is the
#    compute-per-frame knob: lower = smoother frames, slower thinking.
#
# 2. Budget checks must not fail inside rollback machinery (a failing
#    check rolls back its own counter and siblings retry on a refreshed
#    budget, unbounded work). So running out of budget sets an Aborted
#    flag and returns sentinel scores; nothing fails, nothing rolls back.
#    A deepening pass that aborted is discarded whole.
#
# Scores are centipawns from the side-to-move's perspective. Mates are
# +/-(MateScore - Ply) so nearer mates score higher.

using { /Verse.org/Simulation }

MateScore<public>:int = 100000
SearchInfinity<public>:int = 1000000

scored_move<public> := class:
    Move<public>:chess_move
    Score<public>:int

search_result<public> := class:
    # Root moves with full-window scores, best first. Empty iff no legal moves.
    Ranked<public>:[]scored_move
    CompletedDepth<public>:int
    NodesUsed<public>:int


chess_search<public> := class:

    var Nodes<private>:int = 0
    var Budget<private>:int = 0
    var FrameNodes<private>:int = 0
    var PerFrame<private>:int = 0
    var Aborted<private>:logic = false
    # Instrumentation. Sim time is constant within a tick, so per-slab
    # timing is impossible; TotalMs / Yields = avg frame cost of one slab.
    var Yields<private>:int = 0

    # Iterative deepening to MaxDepth, total work capped by NodeBudget,
    # per-frame work capped by NodesPerFrame. A pass that aborts mid-depth
    # (budget out) is discarded; the last completed depth stands.
    FindBestMoves<public>(P:chess_position, MaxDepth:int, NodeBudget:int, NodesPerFrame:int)<suspends>:search_result =
        set Nodes = 0
        set Budget = NodeBudget
        set FrameNodes = 0
        set PerFrame = NodesPerFrame
        set Aborted = false
        set Yields = 0
        StartTime := GetSimulationElapsedTime()
        Print("chess dbg: search start, budget {NodeBudget}, perFrame {NodesPerFrame}")
        var RootMoves:[]chess_move = AllLegalMoves(P)
        var Ranked:[]scored_move = array{}
        var CompletedDepth:int = 0
        var Depth:int = 1
        loop:
            if (Depth > MaxDepth or RootMoves.Length = 0 or Nodes >= Budget):
                break
            MaybePass := SearchDepthPass(P, RootMoves, Depth)
            ElapsedMs := Int[(GetSimulationElapsedTime() - StartTime) * 1000.0] or 0
            if (Pass := MaybePass?):
                set Ranked = Pass
                set CompletedDepth = Depth
                Print("chess dbg: depth {Depth} done, nodes {Nodes}, yields {Yields}, elapsed {ElapsedMs}ms")
                # Next depth searches in this pass's order (better pruning).
                set RootMoves = for (SM : Pass) { SM.Move }
                set Depth += 1
            else:
                Print("chess dbg: depth {Depth} aborted (budget), nodes {Nodes}, elapsed {ElapsedMs}ms")
                break
        TotalMs := Int[(GetSimulationElapsedTime() - StartTime) * 1000.0] or 0
        AvgSlabMs := if (Yields > 0, A := Int[(1.0 * TotalMs) / (1.0 * Yields)]) then A else TotalMs
        Print("chess dbg: search end, {Nodes} nodes, {Yields} yields, total {TotalMs}ms, avg {AvgSlabMs}ms per slab")
        search_result{Ranked := Ranked, CompletedDepth := CompletedDepth, NodesUsed := Nodes}

    # One deepening pass; false if it aborted (budget out). The recursion
    # paces itself via SpendNode, no pacing needed here.
    SearchDepthPass<private>(P:chess_position, Moves:[]chess_move, Depth:int)<suspends>:?[]scored_move =
        var Scored:[]scored_move = array{}
        var Failed:logic = false
        var I:int = 0
        loop:
            if (M := Moves[I]):
                set I += 1
                MaybeScore := SearchRootMove(P, M, Depth)
                if (S := MaybeScore?):
                    set Scored += array{scored_move{Move := M, Score := S}}
                else:
                    set Failed = true
                    break
            else:
                break
        if (Failed?):
            false
        else:
            option{SortScoredDesc(Scored)}

    # One root move's subtree. false = budget ran out mid-subtree, discard
    # the pass.
    SearchRootMove<private>(P:chess_position, M:chess_move, Depth:int)<suspends>:?int =
        var Out:?int = false
        if (Next := Apply[P, M], not InCheck[Next, P.ToMove]):
            Raw := Negamax(Next, Depth - 1, -SearchInfinity, SearchInfinity, 1)
            if (not Aborted?):
                set Out = option{-Raw}
        Out

    # TOTAL core recursion (see header): aborts via flag, never fails.
    # <suspends>: SpendNode sleeps every PerFrame nodes mid-recursion.
    Negamax<private>(P:chess_position, Depth:int, InAlpha:int, Beta:int, Ply:int)<suspends>:int =
        Spent := SpendNode()
        if (Spent?):
            0
        else:
            var Alpha:int = InAlpha
            InCheckNow:logic = if (InCheck[P, P.ToMove]) then true else false
            # Check extension: don't stand at depth 0 while in check.
            EffDepth := if (InCheckNow?) then Depth + 1 else Depth
            if (EffDepth <= 0):
                Quiescence(P, Alpha, Beta, 0)
            else if (P.HalfmoveClock >= 100):
                0
            else:
                Pseudo := OrderMoves(P, AllPseudoMoves(P))
                var Best:int = -SearchInfinity
                var AnyLegal:logic = false
                var Stop:logic = false
                var I:int = 0
                loop:
                    if (Stop? or Aborted?):
                        break
                    if (M := Pseudo[I]):
                        set I += 1
                        # Illegal pseudo move (own king in check): skip.
                        if (Next := Apply[P, M], not InCheck[Next, P.ToMove]):
                            set AnyLegal = true
                            Raw := Negamax(Next, EffDepth - 1, -Beta, -Alpha, Ply + 1)
                            Score := -Raw
                            if (Score > Best):
                                set Best = Score
                            if (Best > Alpha):
                                set Alpha = Best
                            if (Alpha >= Beta):
                                set Stop = true   # beta cutoff
                    else:
                        break
                if (Aborted?):
                    0
                else if (not AnyLegal?):
                    # Mate or stalemate.
                    if (InCheckNow?) then -(MateScore - Ply) else 0
                else:
                    Best

    # Captures/promotions only, so eval never lands mid-exchange. Total,
    # same abort discipline, suspends via SpendNode like Negamax.
    Quiescence<private>(P:chess_position, InAlpha:int, Beta:int, QDepth:int)<suspends>:int =
        Spent := SpendNode()
        if (Spent?):
            0
        else:
            var Alpha:int = InAlpha
            Stand := EvaluatePosition(P)
            if (Stand >= Beta or QDepth >= 4):
                Stand
            else:
                if (Stand > Alpha):
                    set Alpha = Stand
                Noisy := OrderMoves(P, AllNoisyPseudoMoves(P))
                var Best:int = Stand
                var Stop:logic = false
                var I:int = 0
                loop:
                    if (Stop? or Aborted?):
                        break
                    if (M := Noisy[I]):
                        set I += 1
                        if (Next := Apply[P, M], not InCheck[Next, P.ToMove]):
                            Raw := Quiescence(Next, -Beta, -Alpha, QDepth + 1)
                            Score := -Raw
                            if (Score > Best):
                                set Best = Score
                            if (Best > Alpha):
                                set Alpha = Best
                            if (Alpha >= Beta):
                                set Stop = true
                    else:
                        break
                Best

    # True (and sets Aborted) when out of budget; otherwise counts the node
    # and yields the frame every PerFrame nodes. THE pacing point of the
    # whole search: every node passes through here.
    SpendNode<private>()<suspends>:logic =
        if (Aborted?):
            true
        else if (Nodes >= Budget):
            set Aborted = true
            true
        else:
            set Nodes += 1
            set FrameNodes += 1
            if (FrameNodes >= PerFrame):
                set FrameNodes = 0
                set Yields += 1
                Sleep(0.0)
            false

    # Noisy moves first (MVV-LVA sorted, small list), quiet moves after in
    # generation order. Comprehensions, not var+append (append copies the
    # accumulated array per element, and this runs at every node).
    OrderMoves<private>(P:chess_position, Moves:[]chess_move)<transacts>:[]chess_move =
        NoisyKeyed := for (M : Moves, Key := NoisyOrderKey[P, M]):
            scored_move{Move := M, Score := Key}
        Quiet := for (M : Moves, not NoisyOrderKey[P, M]):
            M
        SortedNoisy := for (SM : SortScoredDesc(NoisyKeyed)) { SM.Move }
        SortedNoisy + Quiet

    # Fails for quiet moves. MVV-LVA: most valuable victim, least valuable
    # attacker; promotions score with the captures.
    NoisyOrderKey<internal>(P:chess_position, M:chess_move)<transacts><decides>:int =
        var Key:?int = false
        if (Victim := PieceAt[P, M.To], Attacker := PieceAt[P, M.From]):
            set Key = option{10000 + PieceValue(Victim.Kind) * 10 - PieceValue(Attacker.Kind)}
        if (K := M.Promo?):
            Base := Key? or 9000
            set Key = option{Base + PieceValue(K)}
        Key?

    # Insertion sort, stable, descending Score. Only used on small lists
    # (root moves, noisy subsets).
    SortScoredDesc<internal>(Items:[]scored_move)<transacts>:[]scored_move =
        var Sorted:[]scored_move = array{}
        for (Item : Items):
            var Placed:logic = false
            var NewSorted:[]scored_move = array{}
            for (Existing : Sorted):
                if (not Placed?, Item.Score > Existing.Score):
                    set NewSorted += array{Item}
                    set Placed = true
                set NewSorted += array{Existing}
            if (not Placed?):
                set NewSorted += array{Item}
            set Sorted = NewSorted
        Sorted
