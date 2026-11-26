using { /Fortnite.com/Devices }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# Optional drivers that call Start / RequestNextWave; the game never starts
# itself. Both find the game on their own entity or an ancestor.

# Button-driven: one button starts the match, one advances waves.
button_game_driver_component<public> := class<final_super>(component):

    @editable
    StartButton<public>:button_device

    @editable
    NextWaveButton<public>:button_device

    OnSimulate<override>()<suspends>:void =
        MaybeGame := option{FindGame[]}
        if (Game := MaybeGame?):
            Presser := StartButton.InteractedWithEvent.Await()
            Print("TD: start button pressed")
            Started := Game.Start()

            race:
                RunNextWave(Game)
                Game.GameOverEvent.Await()
            Print("TD: button driver done (game over)")
        else:
            Print("TD: button driver found no td_game_component on entity or ancestors")

    RunNextWave<private>(Game:td_game_component)<suspends>:void =
        loop:
            Presser := NextWaveButton.InteractedWithEvent.Await()
            Print("TD: next-wave button pressed")
            Accepted := Game.RequestNextWave()

    FindGame<private>()<transacts><decides>:td_game_component =
        Entity.GetComponent[td_game_component] or first{G : Entity.FindAncestorComponents(td_game_component)}


# No-input driver: starts at sim begin, advances waves on a fixed delay.
auto_game_driver_component<public> := class<final_super>(component):

    # Delay before the match starts.
    @editable
    var StartDelay<public>:float = 3.0

    # Build-phase length between waves.
    @editable
    var TimeBetweenWaves<public>:float = 8.0

    OnSimulate<override>()<suspends>:void =
        MaybeGame := option{FindGame[]}
        if (Game := MaybeGame?):
            Print("TD: auto driver starting game in {StartDelay}s")
            Sleep(StartDelay)
            Started := Game.Start()
            race:
                AdvanceLoop(Game)
                Game.GameOverEvent.Await()
            Print("TD: auto driver done (game over)")
        else:
            Print("TD: auto driver found no td_game_component on entity or ancestors")

    AdvanceLoop<private>(Game:td_game_component)<suspends>:void =
        loop:
            Sleep(TimeBetweenWaves)
            Accepted := Game.RequestNextWave()
            if (not Accepted?):
                # wave still running; try again once it clears
                Print("TD: auto driver waiting for wave clear before next request")
                W := Game.WaveClearedEvent.Await()

    FindGame<private>()<transacts><decides>:td_game_component =
        if (G := Entity.GetComponent[td_game_component]):
            G
        else:
            first{G : Entity.FindAncestorComponents(td_game_component)}
