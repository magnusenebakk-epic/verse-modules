using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Itemization }


# Bot-game starter pad: interact to seat yourself as White and start a game
# against the bot at this pad's difficulty. Place three of these (Easy,
# Medium, Hard) next to a board; whoever interacts first gets the game.
# Another example of the board's init-agnostic surface, alongside the zone
# starter.
chess_difficulty_starter_component<public> := class<final_super>(basic_interactable_component):

    # Required: components may leave @editable fields uninitialized, the
    # editor forces them to be set.
    @editable
    Board<public>:entity

    # 0 = Beginner, 1 = Casual, 2 = Club, 3 = Strong. An int rather than a
    # chess_difficulty instance so pads are one-click to author; tune the
    # presets in chess_bot.verse or set a custom difficulty on the board
    # and use PresetIndex := -1 to keep it.
    @editable
    PresetIndex<public>:int = 1

    @editable
    LabelText<public>:string = "Casual"

    var Subscription<private>:?cancelable = false

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        Enable()

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        Disable()

    Enable<override>():void =
        (super:)Enable()
        if (not Subscription?):
            set Subscription = option{SucceededEvent.Subscribe(OnInteracted)}

    Disable<override>():void =
        (super:)Disable()
        if (Subscription?.Cancel()):
            set Subscription = false

    OnInteracted<private>(Agent:agent):void =
        if:
            P := player[Agent]
            BoardComp := GetBoard[]
            not BoardComp.IsRunning[]
        then:
            if (D := PresetFor[PresetIndex]):
                BoardComp.SetBotDifficulty(D)
            BoardComp.SetPlayer(chess_color.White, P)
            BoardComp.ClearPlayer(chess_color.Black)   # bot seat
            Started := BoardComp.StartGame()
            if (Started?):
                Print("chess: game vs bot ({LabelText}) started")

    PresetFor<private>(Index:int)<transacts><decides>:chess_difficulty =
        Index >= 0
        if (Index = 0):
            BeginnerDifficulty()
        else if (Index = 1):
            CasualDifficulty()
        else if (Index = 2):
            ClubDifficulty()
        else:
            StrongDifficulty()

    GetBoard<private>()<transacts><decides>:chess_board_component =
        Board.GetComponent[chess_board_component]
