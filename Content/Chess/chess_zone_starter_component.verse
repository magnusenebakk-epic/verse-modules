using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# One join zone per seat: the sandbox way to start a board. Put this on an
# entity with a mesh_component whose Queryable is on (EntityEnteredEvent
# needs it); point Board at the entity carrying chess_board_component.
# When both colors' zones are occupied, the White zone's starter calls
# StartGame. Leaving a zone mid-game aborts.
#
# This is ONE starter; matchmaking or devices can instead call
# SetPlayer/StartGame on the board directly. The board doesn't care.

chess_zone_starter_component<public> := class<final_super>(component):

    @editable
    Board<public>:entity

    # Which seat this zone fills.
    @editable
    SeatIsWhite<public>:logic = true

    var Subs<private>:[]cancelable = array{}
    var Occupant<private>:?player = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Mesh := Entity.GetComponent[mesh_component]):
            set Subs += array{
                Mesh.EntityEnteredEvent.Subscribe(OnEntered),
                Mesh.EntityExitedEvent.Subscribe(OnExited)}

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : Subs) { S.Cancel() }
        set Subs = array{}

    OnEntered<private>(Other:entity):void =
        if (P := player[Other], BoardComp := GetBoard[], not Occupant?):
            set Occupant = option{P}
            Seat := if (SeatIsWhite?) then chess_color.White else chess_color.Black
            BoardComp.SetPlayer(Seat, P)
            Print("chess zone: {if (SeatIsWhite?) then "White" else "Black"} seat taken")
            # White's zone is the referee: start when both seats are filled.
            if:
                SeatIsWhite?
                not BoardComp.IsRunning[]
                BoardComp.GetSeat[chess_color.White]
                BoardComp.GetSeat[chess_color.Black]
            then:
                Started := BoardComp.StartGame()
                if (Started?):
                    Print("chess zone: game on")
            else if:
                not SeatIsWhite?
                not BoardComp.IsRunning[]
                BoardComp.GetSeat[chess_color.White]
                BoardComp.GetSeat[chess_color.Black]
            then:
                Started := BoardComp.StartGame()
                if (Started?):
                    Print("chess zone: game on")

    OnExited<private>(Other:entity):void =
        if:
            P := player[Other]
            Current := Occupant?
            Current = P
            BoardComp := GetBoard[]
        then:
            set Occupant = false
            Seat := if (SeatIsWhite?) then chess_color.White else chess_color.Black
            BoardComp.ClearPlayer(Seat)
            if (BoardComp.IsRunning[]):
                Print("chess zone: player left, game aborted")
                BoardComp.AbortGame()

    GetBoard<private>()<transacts><decides>:chess_board_component =
        BoardEntity := Board
        BoardEntity.GetComponent[chess_board_component]
