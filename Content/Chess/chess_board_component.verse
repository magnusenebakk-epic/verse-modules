using { /Verse.org/Concurrency }
using { /Verse.org/Input }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/Itemization }
using { /Fortnite.com/Characters }
using { /Verse.org/Assets }

using { Placement }


# In-world chess board. Initialization-agnostic: SOMETHING (zone starter,
# matchmaking, a device) seats the players and starts the game; this
# component owns everything after that.
#
#   Board := ...GetComponent[chess_board_component]
#   Board.SetPlayer(chess_color.White, P1)
#   Board.SetPlayer(chess_color.Black, P2)   # or leave empty for the bot
#   Board.StartGame()
#
# Board geometry rides the sibling grid_component (CellSize/OriginOffset;
# a1 = cell (0,0), files run Forward, ranks run Left). Pieces are spawned
# prefabs carrying chess_board_piece_component + basic_interactable_component.
# Interacting with your piece on your turn starts a MOVE SESSION:
#   legal targets get LegalMarkerPrefab circles (chess_move_highlight),
#   the aimed square gets the proposal marker (look_aim_placement_method
#   into grid Snap, same pipeline as the Placement module),
#   interacting again commits the aimed move if legal, cancels otherwise.
# Bot turns run through chess_bot when a seat has no player.

chess_seats<public> := class:
    var White<public>:?player = false
    var Black<public>:?player = false

chess_board_component<public> := class<final_super>(component):

    # --- Authoring -------------------------------------------------------------

    @editable
    WhitePiecePrefabs<public>:chess_piece_prefab_set = chess_piece_prefab_set{}

    @editable
    BlackPiecePrefabs<public>:chess_piece_prefab_set = chess_piece_prefab_set{}

    @editable
    Highlight<public>:chess_move_highlight = chess_move_highlight{}

    # Aiming method for the proposal marker during a move session.
    @editable
    AimMethod<public>:hit_aware_placement_method = look_aim_placement_method{}

    # Place gesture, chosen by whether PlaceAction is assigned:
    #   unset -> click mode: circles are interactable, the engine popup is
    #            the aim truth, interacting a circle places there.
    #   set   -> aim+press mode: the proposal ring follows the legal square
    #            you look at and PlaceAction places there. Make the circle
    #            prefab NON-interactable in this mode (engine popups use a
    #            different aim model and visibly disagree with the ring).
    @editable
    PlaceAction<public>:?input_action(logic) = false

    # Bot settings for seats without a player. var so starters can set the
    # difficulty at runtime before StartGame (e.g. difficulty pads).
    @editable
    var BotDifficulty<public>:chess_difficulty = chess_difficulty{}

    SetBotDifficulty<public>(D:chess_difficulty):void =
        set BotDifficulty = D

    @editable
    BotThinkDelay<public>:float = 1.5

    # Search nodes evaluated per frame while the bot thinks. Deep nodes
    # measured ~1ms each; 15 keeps a 30 TPS tick smooth. Throughput cap:
    # 30 * this = nodes/sec, think time = NodeBudget / that.
    @editable
    BotNodesPerFrame<public>:int = 15

    @editable
    RandomSeed<public>:int = 777

    # --- Events (world systems subscribe) ---------------------------------------

    GameStartedEvent<public>:Concurrency.subscribable_event(chess_seats) =
        Concurrency.subscribable_event(chess_seats){}

    GameEndedEvent<public>:Concurrency.subscribable_event(chess_result) =
        Concurrency.subscribable_event(chess_result){}

    MoveShownEvent<public>:Concurrency.subscribable_event(chess_move_applied) =
        Concurrency.subscribable_event(chess_move_applied){}

    # --- State -------------------------------------------------------------------

    var Seats<private>:chess_seats = chess_seats{}
    var MaybeGame<private>:?chess_game = false
    var MaybeBot<private>:?chess_bot = false
    var PieceEntities<private>:[int]entity = map{}   # square -> piece entity
    var Running<private>:logic = false
    # Set by NotifyPieceInteracted, consumed by the session loop.
    PieceInteractedEvent<private>:event(tuple(agent, chess_board_piece_component)) =
        event(tuple(agent, chess_board_piece_component)){}
    # Set by NotifyTargetInteracted (legal-move circles), the place gesture.
    TargetInteractedEvent<private>:event(tuple(agent, int)) =
        event(tuple(agent, int)){}
    GameEndedInternal<private>:event() = event(){}
    var EndSubs<private>:[]Concurrency.subscription_task(chess_result) = array{}

    # --- Public control (the initialization-agnostic surface) --------------------

    SetPlayer<public>(C:chess_color, P:player):void =
        if (C = chess_color.White):
            set Seats.White = option{P}
        else:
            set Seats.Black = option{P}

    ClearPlayer<public>(C:chess_color):void =
        if (C = chess_color.White):
            set Seats.White = false
        else:
            set Seats.Black = false

    GetSeat<public>(C:chess_color)<reads><decides>:player =
        if (C = chess_color.White):
            Seats.White?
        else:
            Seats.Black?

    IsRunning<public>()<reads><decides>:void =
        Running?

    # False if already running. Spawns pieces and begins play; seats without
    # a player are played by the bot.
    StartGame<public>():logic =
        if (Running?):
            false
        else:
            G := MakeChessGame()
            set MaybeGame = option{G}
            NewBot := MakeChessBot(BotDifficulty, RandomSeed)
            set NewBot.NodesPerFrame = BotNodesPerFrame
            set MaybeBot = option{NewBot}
            set Running = true
            set EndSubs += array{G.GameEndedEvent.Subscribe(OnGameEnded)}
            RebuildPieces(G.Position())
            Print("chess dbg: game started, {PieceCount()} piece entities spawned, white seat {SeatText(chess_color.White)}, black seat {SeatText(chess_color.Black)}")
            GameStartedEvent.Signal(Seats)
            true

    # Ends without a result (players left, round reset).
    AbortGame<public>():void =
        if (Running?):
            TearDown()

    # Relay target for chess_board_piece_component.
    NotifyPieceInteracted<public>(Agent:agent, Piece:chess_board_piece_component):void =
        Print("chess dbg: piece interacted, sq {Piece.Square} color {ColorText(Piece.PieceColor)} kind {PieceLetter(chess_piece{Color := Piece.PieceColor, Kind := Piece.Kind})}")
        PieceInteractedEvent.Signal((Agent, Piece))

    # Relay target for chess_target_marker_component (legal-move circles).
    NotifyTargetInteracted<public>(Agent:agent, Square:int):void =
        Print("chess dbg: target circle interacted, sq {Square}")
        TargetInteractedEvent.Signal((Agent, Square))

    # --- The game loop -------------------------------------------------------------

    OnSimulate<override>()<suspends>:void =
        (super:)OnSimulate()
        loop:
            if (not Running?):
                Sleep(0.5)   # cheap idle; StartGame is external
            else if (G := MaybeGame?):
                race:
                    GameEndedInternal.Await()
                    RunTurns(G)
                set Running = false
            else:
                Sleep(0.5)

    RunTurns<private>(G:chess_game)<suspends>:void =
        loop:
            if (G.IsOver[]):
                break
            Mover := G.Position().ToMove
            if (Seated := GetSeat[Mover]):
                Print("chess dbg: {ColorText(Mover)} to move (human), awaiting piece pick")
                TakeHumanTurn(G, Seated, Mover)
            else:
                Print("chess dbg: {ColorText(Mover)} to move (bot)")
                Sleep(BotThinkDelay)
                TakeBotTurn(G)   # suspends across frames while searching
            Sleep(0.0)

    # One human turn: await a valid piece pick, run a move session; session
    # cancel loops back to picking.
    TakeHumanTurn<private>(G:chess_game, Seated:player, Mover:chess_color)<suspends>:void =
        var Done:logic = false
        loop:
            if (Done?):
                break
            Picked := AwaitOwnPiecePick(G, Seated, Mover)
            Moved := RunMoveSession(G, Seated, Picked)
            if (Moved?):
                set Done = true

    AwaitOwnPiecePick<private>(G:chess_game, Seated:player, Mover:chess_color)<suspends>:chess_board_piece_component =
        var Result:?chess_board_piece_component = false
        loop:
            Pick := PieceInteractedEvent.Await()
            Agent := Pick(0)
            Piece := Pick(1)
            # Debug: report exactly which gate rejects a pick.
            IsSeated:logic = if (PickedPlayer := player[Agent], PickedPlayer = Seated) then true else false
            IsOwnColor:logic = if (Piece.PieceColor = Mover) then true else false
            LegalCount := G.LegalFrom(Piece.Square).Length
            Print("chess dbg: pick sq {Piece.Square}, seated {LogicText(IsSeated)}, ownColor {LogicText(IsOwnColor)}, legalMoves {LegalCount}")
            if:
                IsSeated?
                IsOwnColor?
                LegalCount > 0
            then:
                set Result = option{Piece}
                break
        Result? or Err("unreachable: loop breaks only after setting Result")

    # Move session. PRIMARY place gesture: interact a legal-move circle
    # (the engine popup is the aim truth). Optional: PlaceAction places on
    # the sweep-aimed square, with ShowAimPreview for its ring. Interacting
    # the picked piece cancels; another own piece with moves switches the
    # session. Returns whether a move was committed.
    RunMoveSession<private>(G:chess_game, Seated:player, Piece:chess_board_piece_component)<suspends>:logic =
        defer:
            Highlight.HideAll()
        Legal := G.LegalFrom(Piece.Square)
        LegalTargets := for (M : Legal, Pos := SquareWorldPos[M.To]) { (M.To, Pos) }
        Print("chess dbg: session open, sq {Piece.Square}, {Legal.Length} legal, {LegalTargets.Length} circles")
        Highlight.ShowLegalTargets(Entity, LegalTargets)
        Session := placement_session:
            Query := placement_query{Player := Seated, PlacableEntity := Entity}
            Method := chess_square_placement_method{Board := Self, Inner := AimMethod}
            Restrictions := array{chess_legal_square_restriction{Board := Self, LegalTargets := for (M : Legal) { M.To }}}
            Highlight := chess_proposal_highlight{Board := Self, Markers := Highlight}
        var Committed:logic = false
        var SwitchTo:?chess_board_piece_component = false
        race:
            # Aim ring: essential feedback for aim+press, noise for click
            # mode, so it follows PlaceAction.
            block:
                if (PlaceAction?):
                    Session.RunPreviewOnly()
                else:
                    Sleep(Inf)
            # Arm A: PlaceAction commits at the AIMED square. Loops so a
            # press over an illegal square stays in the session.
            block:
                if (CA := PlaceAction?, Input := GetPlayerInput[Seated]):
                    Events := Input.GetInputEvents(CA)
                    Events.TriggerActivationEvent.Subscribe(NullCallback) # NOTE: workaround for input events not working with .Await
                    loop:
                        Events.TriggerActivationEvent.Await()
                        MaybeMove:?chess_move =
                            if (Sq := AimedSquare[Seated], M := first (Mv : Legal, Mv.To = Sq) { Mv }):
                                option{M}   # promotions: first = queen
                            else:
                                false
                        if (Move := MaybeMove?):
                            Done := TryCommit(G, Move)   # signals, hoisted
                            if (Done?):
                                set Committed = true
                                break
                        else:
                            Print("chess dbg: place pressed off a legal square, ignored")
                else:
                    Sleep(Inf)   # no action authored: circles only
            # Arm B: fallback, interacting a legal circle commits there.
            block:
                var Deciding:logic = true
                loop:
                    if (not Deciding?):
                        break
                    Pick := TargetInteractedEvent.Await()
                    Agent := Pick(0)
                    Sq := Pick(1)
                    MaybeMove:?chess_move =
                        if:
                            PickedPlayer := player[Agent]
                            PickedPlayer = Seated
                            M := first (Mv : Legal, Mv.To = Sq) { Mv }
                        then:
                            option{M}
                        else:
                            false
                    if (Move := MaybeMove?):
                        Done := TryCommit(G, Move)   # signals, hoisted
                        if (Done?):
                            set Committed = true
                            set Deciding = false
            # Arm C: piece interactions cancel or switch.
            block:
                var Deciding:logic = true
                loop:
                    if (not Deciding?):
                        break
                    Pick := PieceInteractedEvent.Await()
                    Agent := Pick(0)
                    Target := Pick(1)
                    if (PickedPlayer := player[Agent], PickedPlayer = Seated):
                        if (Target = Piece):
                            Print("chess dbg: session cancelled (same piece)")
                            set Deciding = false
                        else if (Target.PieceColor = Piece.PieceColor, G.LegalFrom(Target.Square).Length > 0):
                            Print("chess dbg: switching session to sq {Target.Square}")
                            set SwitchTo = option{Target}
                            set Deciding = false
        # Recurse OUTSIDE the race: the old session's arms and preview are
        # torn down before the new session opens.
        if (Target := SwitchTo?):
            RunMoveSession(G, Seated, Target)
        else:
            Committed

    # Validates nothing (caller matched against Legal); applies and syncs.
    # Plain (no_rollback): TryMove and ApplyMoveToWorld both signal.
    TryCommit<private>(G:chess_game, Move:chess_move):logic =
        Outcome := G.TryMove(Move)
        if (A := Outcome.GetSuccess[]):
            ApplyMoveToWorld(A)
            true
        else:
            Print("chess dbg: TryMove rejected a listed legal move, engine bug")
            false

    # The square the player's aim currently resolves to, legal or not.
    AimedSquare<private>(Seated:player)<transacts><decides>:int =
        Query := placement_query{Player := Seated, PlacableEntity := Entity}
        Proposal := AimMethod.ComputeProposal[Query]
        WorldToSquare[Proposal.Transform.Translation]

    TakeBotTurn<private>(G:chess_game)<suspends>:void =
        if (B := MaybeBot?):
            T0 := GetSimulationElapsedTime()
            MaybeChoice := B.ChooseMove(G.Position())
            ThinkMs := Int[(GetSimulationElapsedTime() - T0) * 1000.0] or 0
            Print("chess dbg: ChooseMove wall time {ThinkMs}ms")
            if (Choice := MaybeChoice?):
                MvText := MoveText[Choice.Move] or "????"
                Print("chess dbg: bot plays {MvText} (score {Choice.Score}, depth {Choice.SearchDepth}, {Choice.NodesUsed} nodes)")
                Outcome := G.TryMove(Choice.Move)
                if (A := Outcome.GetSuccess[]):
                    ApplyMoveToWorld(A)
            else:
                Print("chess dbg: bot found no move (game should be over)")

    # --- World sync -------------------------------------------------------------

    # Moves/removes piece entities per the applied move, then republishes.
    # ORDER MATTERS: the victim leaves before the mover writes its map slot,
    # or a normal capture overwrites the victim's entry and the entity leaks
    # on the board (visually two pieces stacked; picks report wrong color).
    ApplyMoveToWorld<private>(A:chess_move_applied):void =
        if (CapturedSq := A.CapturedSquare?):
            if (Victim := PieceEntities[CapturedSq]):
                Victim.RemoveFromParent()
                set PieceEntities = PieceEntities.RemoveKey(CapturedSq)
                Print("chess dbg: captured entity removed from sq {CapturedSq}")
            else:
                Print("chess dbg: capture at sq {CapturedSq} but no entity there, board desynced")
        # Mover entity relocates (promotion respawns instead).
        if (MoverEntity := PieceEntities[A.Move.From]):
            set PieceEntities = PieceEntities.RemoveKey(A.Move.From)
            if (K := A.Move.Promo?):
                MoverEntity.RemoveFromParent()
                SpawnPiece(chess_piece{Color := A.Mover.Color, Kind := K}, A.Move.To)
            else:
                PlacePieceEntity(MoverEntity, A.Move.To)
                if (set PieceEntities[A.Move.To] = MoverEntity) {}
                UpdatePieceSquare(MoverEntity, A.Move.To)
        # Castling rook hop.
        if (Hop := A.RookHop?, RookEntity := PieceEntities[Hop.From]):
            set PieceEntities = PieceEntities.RemoveKey(Hop.From)
            PlacePieceEntity(RookEntity, Hop.To)
            if (set PieceEntities[Hop.To] = RookEntity) {}
            UpdatePieceSquare(RookEntity, Hop.To)
        MoveShownEvent.Signal(A)

    RebuildPieces<private>(P:chess_position):void =
        for (Sq -> E : PieceEntities):
            E.RemoveFromParent()
        set PieceEntities = map{}
        for (Sq := 0..63):
            if (Pc := PieceAt[P, Sq]):
                SpawnPiece(Pc, Sq)

    SpawnPiece<private>(Pc:chess_piece, Sq:int):void =
        Prefabs := if (Pc.Color = chess_color.White) then WhitePiecePrefabs else BlackPiecePrefabs
        if (Prefab := Prefabs.PrefabFor[Pc.Kind]):
            New := Prefab{}
            Entity.AddEntities(array{New})
            PlacePieceEntity(New, Sq)
            if (set PieceEntities[Sq] = New) {}
            UpdatePieceSquare(New, Sq)

    UpdatePieceSquare<private>(E:entity, Sq:int):void =
        if (PieceComp := E.GetComponent[chess_board_piece_component]):
            set PieceComp.Square = Sq
            if (G := MaybeGame?, Pc := PieceAt[G.Position(), Sq]):
                set PieceComp.PieceColor = Pc.Color
                set PieceComp.Kind = Pc.Kind
            else:
                Print("chess dbg: no piece in game at sq {Sq} while updating entity, board desynced")

    PlacePieceEntity<private>(E:entity, Sq:int):void =
        if (Pos := SquareWorldPos[Sq]):
            Current := E.GetGlobalTransform()
            E.SetGlobalTransform(transform{
                Translation := Pos,
                Rotation := Current.Rotation,
                Scale := Current.Scale})

    # --- Geometry (sibling grid_component) ----------------------------------------
    # <internal>: the placement adapters below use these.

    # a1 at grid cell (0,0): file along Forward, rank along Left.
    SquareWorldPos<internal>(Sq:int)<transacts><decides>:vector3 =
        Grid := Entity.GetComponent[grid_component]
        F := FileOf[Sq]
        R := RankOf[Sq]
        Origin := Entity.GetGlobalTransform().Translation + Grid.OriginOffset
        Origin + vector3{
            Forward := (1.0 * F) * Grid.CellSize,
            Left := (1.0 * R) * Grid.CellSize,
            Up := 0.0}

    WorldToSquare<internal>(WorldPos:vector3)<transacts><decides>:int =
        Grid := Entity.GetComponent[grid_component]
        Snapped := Grid.Snap[WorldPos]
        Origin := Entity.GetGlobalTransform().Translation + Grid.OriginOffset
        Local := Snapped - Origin
        F := Round[Local.Forward / Grid.CellSize]
        R := Round[Local.Left / Grid.CellSize]
        F >= 0
        F <= 7
        R >= 0
        R <= 7
        SquareAt(F, R)

    # --- Debug helpers --------------------------------------------------------------

    PieceCount<internal>()<transacts>:int =
        var N:int = 0
        for (Sq -> E : PieceEntities):
            set N += 1
        N

    SeatText<internal>(C:chess_color)<transacts>:string =
        if (GetSeat[C]) then "human" else "bot"

    ColorText<internal>(C:chess_color)<computes>:string =
        if (C = chess_color.White) then "White" else "Black"

    LogicText<internal>(L:logic)<computes>:string =
        if (L?) then "yes" else "no"

    # --- Teardown -----------------------------------------------------------------

    OnGameEnded<private>(R:chess_result):void =
        GameEndedEvent.Signal(R)
        GameEndedInternal.Signal()

    TearDown<private>():void =
        for (Sq -> E : PieceEntities):
            E.RemoveFromParent()
        set PieceEntities = map{}
        for (S : EndSubs) { S.Cancel() }
        set EndSubs = array{}
        set MaybeGame = false
        set Running = false
        Highlight.HideAll()

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        TearDown()


# --- Placement pipeline adapters ------------------------------------------------
# The move session is a stock placement_session; these three plug chess in.

# Method: aim with Inner, snap to the aimed board square's center.
chess_square_placement_method<public> := class(placement_method):
    Board<public>:chess_board_component
    Inner<public>:placement_method

    ComputeProposal<override>(Query:placement_query)<transacts><decides>:placement_proposal =
        InnerP := Inner.ComputeProposal[Query]
        Sq := Board.WorldToSquare[InnerP.Transform.Translation]
        Pos := Board.SquareWorldPos[Sq]
        placement_proposal:
            Transform := transform{
                Translation := Pos,
                Rotation := InnerP.Transform.Rotation,
                Scale := InnerP.Transform.Scale}
            HitNormal := InnerP.HitNormal
            HitEntity := InnerP.HitEntity

# Restriction: the aimed square must be a legal destination.
chess_legal_square_restriction<public> := class(placement_restriction):
    Board<public>:chess_board_component
    LegalTargets<public>:[]int

    CanPlaceAt<override>(Query:placement_query, Proposal:placement_proposal)<transacts><decides>:void =
        Sq := Board.WorldToSquare[Proposal.Transform.Translation]
        first (T : LegalTargets, T = Sq) { T }

# Highlight: route the session's per-tick preview to the proposal marker,
# LEGAL squares only (an always-on marker over illegal squares reads as
# "you can go here" no matter how it's styled). Legal-target circles are
# shown once per session by the board itself.
chess_proposal_highlight<public> := class(placement_highlight):
    Board<public>:chess_board_component
    Markers<public>:chess_move_highlight

    ShowPreview<override>(Query:placement_query, Proposal:placement_proposal, IsValid:logic):void =
        if (IsValid?):
            Markers.ShowProposal(Board.Entity, Proposal.Transform.Translation, true)
        else:
            Markers.HideProposal()

    HidePreview<override>():void =
        Markers.HideProposal()


# Prefab per piece kind, per side (assign your authored piece prefabs).
chess_piece_prefab_set<public> := class<concrete>:
    @editable
    Pawn<public>:?concrete_subtype(entity) = false
    @editable
    Knight<public>:?concrete_subtype(entity) = false
    @editable
    Bishop<public>:?concrete_subtype(entity) = false
    @editable
    Rook<public>:?concrete_subtype(entity) = false
    @editable
    Queen<public>:?concrete_subtype(entity) = false
    @editable
    King<public>:?concrete_subtype(entity) = false

    PrefabFor<public>(K:chess_piece_kind)<transacts><decides>:concrete_subtype(entity) =
        case (K):
            chess_piece_kind.Pawn => Pawn?
            chess_piece_kind.Knight => Knight?
            chess_piece_kind.Bishop => Bishop?
            chess_piece_kind.Rook => Rook?
            chess_piece_kind.Queen => Queen?
            chess_piece_kind.King => King?
