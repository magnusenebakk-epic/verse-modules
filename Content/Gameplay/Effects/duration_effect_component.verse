using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


duration_effect_component<public> := class<final_super>(component):

    @editable
    Duration<public>:float = 5.0

    var<private> RefreshSignal<private>:event() = event(){}
    var<private> Expired<private>:logic = false
    var<private> Elapsed<private>:float = 0.0

    Refresh<public>():void =
        RefreshSignal.Signal()

    GetRemaining<public>()<reads>:float =
        if (Elapsed >= Duration) then 0.0 else Duration - Elapsed

    OnSimulate<override>()<suspends>:void =
        loop:
            if (Expired?). break
            set Elapsed = 0.0
            race:
                ExpireArm()
                RefreshSignal.Await()
        Entity.RemoveFromParent()

    ExpireArm<private>()<suspends>:void =
        loop:
            Sleep(0.1)
            set Elapsed = Elapsed + 0.1
            if (Elapsed >= Duration):
                set Expired = true
                break
