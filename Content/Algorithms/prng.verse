# Deterministic seeded PRNG. Native /Verse.org/Random is not seedable, so
# it can't do reproducible procgen ("same seed, same dungeon") or replays.
#
# Park-Miller minimal standard (state' = 16807 * state mod 2^31-1) via
# Schrage's factorization. Two platform constraints force this choice:
# Verse has no bitwise operators (rules out xorshift/PCG) and BPVM raises
# a runtime error on int overflow (rules out plain a*x mod m, since a*x
# can exceed 2^31 even though 64-bit would hold it, we stay portable).
# With Schrage every intermediate stays below 2^31.

random_stream<public> := class:

    # Always in 1 .. 2147483646. Seed through MakeRandomStream/SetSeed.
    var<internal> State<public>:int = 1

    SetSeed<public>(Seed:int)<transacts>:void =
        if (M := Mod[Abs(Seed), 2147483646]):
            set State = M + 1
        else:
            set State = 1 # unreachable, divisor is a nonzero literal

    # Next raw value, uniform in 1 .. 2147483646.
    Next<public>()<transacts>:int =
        if:
            Hi := Quotient[State, 127773]  # m div a
            Lo := Mod[State, 127773]
        then:
            Candidate := 16807 * Lo - 2836 * Hi   # 2836 = m mod a
            set State = if (Candidate > 0) then Candidate else Candidate + 2147483647
        else:
            set State = 1 # unreachable
        State

    # Uniform-ish int in Min..Max inclusive. Fails if Max < Min.
    # Modulo bias is ~range/2^31, irrelevant at game ranges.
    NextIn<public>(MinV:int, MaxV:int)<transacts><decides>:int =
        MaxV >= MinV
        Mod[Next(), MaxV - MinV + 1] + MinV

    # In [0.0, 1.0).
    NextFloat<public>()<transacts>:float =
        (1.0 * (Next() - 1)) / 2147483646.0

    # Succeeds with probability P (clamped 0..1).
    Chance<public>(P:float)<transacts><decides>:void =
        NextFloat() < P


MakeRandomStream<public>(Seed:int)<transacts>:random_stream =
    S := random_stream{}
    S.SetSeed(Seed)
    S


# Fisher-Yates. Same stream and seed gives the same order.
(Arr:[]t where t:type).ShuffledBy<public>(Rand:random_stream)<transacts>:[]t =
    var A:[]t = Arr
    MaxI := Arr.Length - 1
    for (K := 0..MaxI - 1):        # no reverse ranges, walk I = MaxI-K down
        I := MaxI - K
        if:
            J := Rand.NextIn[0, I]
            X := A[I]
            Y := A[J]
        then:
            if (set A[I] = Y) {}
            if (set A[J] = X) {}
    A

# Seeded pick. Fails on empty.
(Arr:[]t where t:type).PickBy<public>(Rand:random_stream)<transacts><decides>:t =
    Arr[Rand.NextIn[0, Arr.Length - 1]]
