using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

    

periodic_effect_component<public> := class<final_super>(component):

    @editable
    TickInterval<public>:float = 1.0

    @editable
    Action<public>:periodic_action

    OnSimulate<override>()<suspends>:void =
        loop:
            Sleep(TickInterval)
            Action.Tick(Self)
