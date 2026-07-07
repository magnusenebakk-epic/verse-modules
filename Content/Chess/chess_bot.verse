using { /Verse.org/Simulation }


# Difficulty-parameterized move chooser over chess_search. Pure logic, no
# component; chess_bot_component drives it in world.
#
# Four difficulty axes:
#   MaxDepth     how far ahead it can see (tactics horizon)
#   NodeBudget   how much work per move (also the server-hitch bound)
#   ChoiceMargin picks uniformly among moves within this many centipawns
#                of the best (0 = always best)
#   EvalNoise    +/- centipawns of per-move score jitter before choosing,
#                so weaker levels misjudge close positions like humans do
#
# Presets: tune freely, they're just numbers. Think time ~= NodeBudget /
# (30 TPS * NodesPerFrame); at the default 15/frame that's ~450 nodes/s:
#   Beginner  depth 1, 1.2k nodes ~3s, margin 120, noise 80
#   Casual    depth 2, 2.5k nodes ~6s, margin 60,  noise 40
#   Club      depth 3, 4k nodes ~9s,   margin 25,  noise 10
#   Strong    depth 4, 4.5k nodes ~10s, margin 0,  noise 0

chess_difficulty<public> := class<concrete>:
    @editable
    MaxDepth<public>:int = 3
    @editable
    NodeBudget<public>:int = 4000
    @editable
    ChoiceMargin<public>:int = 25
    @editable
    EvalNoise<public>:int = 10

# <transacts>, not <computes>: class construction carries the transacts
# effect unless the class itself is declared class<computes>.
BeginnerDifficulty<public>()<transacts>:chess_difficulty =
    chess_difficulty{MaxDepth := 1, NodeBudget := 1200, ChoiceMargin := 120, EvalNoise := 80}

CasualDifficulty<public>()<transacts>:chess_difficulty =
    chess_difficulty{MaxDepth := 2, NodeBudget := 2500, ChoiceMargin := 60, EvalNoise := 40}

ClubDifficulty<public>()<transacts>:chess_difficulty =
    chess_difficulty{MaxDepth := 3, NodeBudget := 4000, ChoiceMargin := 25, EvalNoise := 10}

StrongDifficulty<public>()<transacts>:chess_difficulty =
    chess_difficulty{MaxDepth := 4, NodeBudget := 4500, ChoiceMargin := 0, EvalNoise := 0}


# What the bot decided, for logging/UI.
bot_choice<public> := class:
    Move<public>:chess_move
    Score<public>:int
    SearchDepth<public>:int
    NodesUsed<public>:int

# Local Park-Miller PRNG (Schrage). Chess stays self-contained rather than
# importing the parametric Algorithms module (sibling-resolution bug).
bot_random<public> := class:
    var State<internal>:int = 1

    SetSeed<public>(Seed:int)<transacts>:void =
        M := Mod[Abs(Seed), 2147483646] or 0
        set State = M + 1

    Next<public>()<transacts>:int =
        if:
            Hi := Quotient[State, 127773]
            Lo := Mod[State, 127773]
        then:
            Candidate := 16807 * Lo - 2836 * Hi
            set State = if (Candidate > 0) then Candidate else Candidate + 2147483647
        else:
            set State = 1
        State

    # Uniform-ish in 0..MaxV inclusive. Total; MaxV < 0 returns 0.
    NextUpTo<public>(MaxV:int)<transacts>:int =
        if (MaxV > 0, R := Mod[Next(), MaxV + 1]):
            R
        else:
            0


chess_bot<public> := class:

    Difficulty<public>:chess_difficulty
    Rand<public>:bot_random

    var Search<private>:chess_search = chess_search{}

    # Compute per frame: the search suspends after this many nodes,
    # wherever it is in the tree. Deep (quiescence-heavy) nodes measured
    # ~1ms each, so 15/frame is ~15ms of chess per 33ms tick: smooth.
    # Throughput: 30 TPS * 15 = 450 nodes/s; think time = NodeBudget / 450.
    var NodesPerFrame<public>:int = 15

    # Chooses a move for P's side to move (suspends across frames while
    # searching). Empty option iff the game has no legal moves.
    ChooseMove<public>(P:chess_position)<suspends>:?bot_choice =
        Result := Search.FindBestMoves(P, Difficulty.MaxDepth, Difficulty.NodeBudget, NodesPerFrame)
        if (Choice := Pick[Result]):
            option{Choice}
        else:
            false

    # Fails on an empty ranking.
    Pick<private>(Result:search_result)<transacts><decides>:bot_choice =
        # Noise: jitter each score, re-rank. Skipped when EvalNoise = 0.
        Jittered:[]scored_move =
            if (Difficulty.EvalNoise > 0):
                var J:[]scored_move = array{}
                for (SM : Result.Ranked):
                    Noise := Rand.NextUpTo(2 * Difficulty.EvalNoise) - Difficulty.EvalNoise
                    set J += array{scored_move{Move := SM.Move, Score := SM.Score + Noise}}
                ReRank(J)
            else:
                Result.Ranked
        # Margin: uniform pick among moves within ChoiceMargin of the top.
        Best := Jittered[0]
        Candidates := for:
            SM : Jittered
            Best.Score - SM.Score <= Difficulty.ChoiceMargin
        do:
            SM
        PickIdx := Rand.NextUpTo(Candidates.Length - 1)
        Picked := Candidates[PickIdx] or Best
        bot_choice:
            Move := Picked.Move
            Score := Picked.Score
            SearchDepth := Result.CompletedDepth
            NodesUsed := Result.NodesUsed

    # Descending stable insertion sort (local copy, see chess_search note).
    ReRank<private>(Items:[]scored_move)<transacts>:[]scored_move =
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


MakeChessBot<public>(D:chess_difficulty, Seed:int)<transacts>:chess_bot =
    R := bot_random{}
    R.SetSeed(Seed)
    chess_bot{Difficulty := D, Rand := R}
