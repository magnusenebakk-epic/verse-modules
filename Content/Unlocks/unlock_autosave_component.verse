using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Bases }


# Periodically saves the sibling unlock_state while the base is claimed.
# Release/leave saves are handled by the state itself; this only covers the
# crash gap between saves.
unlock_autosave_component<public> := class<final_super>(component):

    @editable
    IntervalSeconds<public>:float = 60.0

    # Print each save, handy when testing.
    @editable
    LogSaves<public>:logic = false

    OnSimulate<override>()<suspends>:void =
        (super:)OnSimulate()
        if (Base := Entity.GetComponent[base_component]):
            loop:
                Base.AwaitClaimed()
                race:
                    Base.AwaitReleased()
                    SaveLoop()

    SaveLoop<private>()<suspends>:void =
        loop:
            Sleep(IntervalSeconds)
            if (State := Entity.GetComponent[unlock_state_component]):
                State.Save()
                if (LogSaves?):
                    Print("unlock autosave")
