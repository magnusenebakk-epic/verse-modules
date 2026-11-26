using { /Verse.org/Random }
using { /Verse.org/Simulation }

# One spawn stream within a wave: Count enemies of one kind, Interval apart,
# after StartDelay. Streams run concurrently, so groups can overlap.
spawn_instruction<public> := class<concrete>:

    # Index into the game's EnemySources roster.
    @editable
    EnemyKind<public>:int = 0

    @editable
    Count<public>:int = 5

    # Seconds between spawns in this stream.
    @editable
    Interval<public>:float = 1.0

    # Seconds after wave start before this stream begins.
    @editable
    StartDelay<public>:float = 0.0

    # Index into the game's ordered lanes, or -1 to rotate across all.
    @editable
    LaneIndex<public>:int = -1


wave_plan<public> := class<concrete>:
    @editable
    Instructions<public>:[]spawn_instruction = array{}


# Wave source: one plan per wave index. Failing means no such wave, which
# ends the game in victory. KindCount is the enemy roster size.
wave_provider<public> := class<abstract>:
    GetPlan<public>(WaveIndex:int, KindCount:int)<transacts><decides>:wave_plan

    # cheap existence check; override if GetPlan is expensive or random
    HasWave<public>(WaveIndex:int, KindCount:int)<transacts><decides>:void =
        GetPlan[WaveIndex, KindCount]


# Hand-authored waves, played in order.
data_wave_provider<public> := class<concrete>(wave_provider):
    @editable
    Waves<public>:[]wave_plan = array{}

    GetPlan<override>(WaveIndex:int, KindCount:int)<transacts><decides>:wave_plan =
        Waves[WaveIndex]


# Algorithmic waves: counts grow, intervals shrink, kinds unlock over time.
# WaveCount 0 means endless. Override PickKind for a different mix.
scaling_wave_provider<public> := class<concrete>(wave_provider):

    # 0 = endless.
    @editable
    WaveCount<public>:int = 10

    # Enemies in wave 1.
    @editable
    BaseCount<public>:int = 5

    # Extra enemies added per wave after the first.
    @editable
    CountPerWave<public>:float = 2.0

    # Seconds between spawns in wave 1.
    @editable
    BaseInterval<public>:float = 1.2

    # Interval multiplier applied each wave; spawns speed up over time.
    @editable
    IntervalDecay<public>:float = 0.92

    # Lower bound for the spawn interval.
    @editable
    MinInterval<public>:float = 0.3

    # First wave (0-based) each kind may appear in, parallel to EnemySources.
    @editable
    KindUnlockWaves<public>:[]int = array{}

    GetPlan<override>(WaveIndex:int, KindCount:int)<transacts><decides>:wave_plan =
        WaveCount <= 0 or WaveIndex < WaveCount
        KindCount > 0
        Total := BaseCount + FloorOf(CountPerWave * (1.0 * WaveIndex))
        Gap := Clamp(
            BaseInterval * Pow(IntervalDecay, 1.0 * WaveIndex),
            MinInterval,
            BaseInterval)
        Unlocked := for (K := 0..KindCount - 1, KindAvailable[K, WaveIndex]) { K }
        # no unlocked kinds means an empty wave, not failure; failing here would grant an instant victory
        Instructions := if (Unlocked.Length > 0):
            # random kind per enemy, then one stream per kind that got any picks
            Picks := for (N := 1..Total) { PickKind(WaveIndex, Unlocked) }
            for:
                K : Unlocked
                C := (for (P : Picks, P = K) { P }).Length
                C > 0
            do:
                spawn_instruction{
                    EnemyKind := K,
                    Count := C,
                    Interval := Gap,
                    StartDelay := 0.0,
                    LaneIndex := -1
                }
        else:
            array{}
        wave_plan{ Instructions := Instructions }

    # Uniform pick over the unlocked kinds; override for weighting.
    PickKind<protected>(WaveIndex:int, Unlocked:[]int)<transacts>:int =
        Fallback := if (F := Unlocked[0]) then F else 0
        if (Pick := Unlocked[GetRandomInt(0, Unlocked.Length - 1)]):
            Pick
        else:
            Fallback

    KindAvailable<private>(Kind:int, WaveIndex:int)<transacts><decides>:void =
        UnlockWave := if (W := KindUnlockWaves[Kind]) then W else 0
        UnlockWave <= WaveIndex

    FloorOf<private>(V:float)<transacts>:int =
        if (I := Floor[V]) then I else 0
