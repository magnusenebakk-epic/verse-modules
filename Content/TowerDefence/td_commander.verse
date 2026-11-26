using { /Fortnite.com/Devices }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/UI }
using { /Verse.org/Assets }
using { /Verse.org/Concurrency }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Placement }


# One tower the commander UI offers. Economy can add a cost here later.
tower_palette_entry<public> := class<concrete>:
    @editable
    DisplayName<public>:string = "Tower"

    # The tower prefab; placement behavior comes from the controller's Profile.
    @editable
    Prefab<public>:concrete_subtype(entity) = entity

    # Palette-button icon, explicit so the UI never spawns a tower just to read an icon.
    @editable
    Icon<public>:?texture = false


# Command mode: fixed camera, pointer input, tower/wave UI per player.
td_commander_component<public> := class<final_super>(component):

    # The fixed board view; the device's own transform frames the shot.
    @editable
    FixedCamera<public>:gameplay_camera_fixed_point_device

    # Enter command mode on first spawn (needs a player_event_manager); players can exit anytime.
    @editable
    var AutoEnterOnSpawn<public>:logic = true

    # Towers the UI offers for placement.
    @editable
    var (td_commander_component:)Towers<public>:[]tower_palette_entry = array{}

    # Widget input mode: true = All (buttons work), false = None (likely display-only). Test knob.
    @editable
    var ConsumeUIInput<public>:logic = true

    # Hide the stock HUD (touch controls, hotbar, minimap, prompts) per player while commanding.
    @editable
    var HideHUDInCommand<public>:logic = true

    var<private> Commanding<private>:[]player = array{}
    var<private> UIs<private>:[player]td_commander_ui = map{}
    var<private> Subs<private>:[]Concurrency.subscription_task(player) = array{}

    # placed towers per palette slot, mirrored into the widget counts
    var<private> PlacedCounts<private>:[int]int = map{}

    # UI buttons signal, the place loop consumes; carries the slot index, which is also the widget-count key
    PlaceRequest<private>:event(tuple(player, int)) =
        event(tuple(player, int)){}

    # UMG press events carry no player, so each widget gets its own listener bound to its player
    UICreated<private>:event(tuple(player, td_commander_ui)) =
        event(tuple(player, td_commander_ui)){}

    # Command-mode lifecycle; the console interactable disables itself while a player commands.
    EnteredCommandEvent<public>:Concurrency.subscribable_event(player) =
        Concurrency.subscribable_event(player){}
    ExitedCommandEvent<public>:Concurrency.subscribable_event(player) =
        Concurrency.subscribable_event(player){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (AutoEnterOnSpawn?):
            if (Mgr := Entity.GetPlayerEventManager[]):
                set Subs += array{Mgr.PlayerFirstSpawnEvent.Subscribe(OnFirstSpawn)}
            else:
                Print("TD cmd: no player_event_manager found, auto-enter disabled")

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (C : Subs):
            C.Cancel()
        set Subs = array{}
        for (P : Commanding):
            FixedCamera.RemoveFrom(P)
            SetStockHUDHidden(P, false)
            if (Input := GetPlayerInput[P]):
                Input.RemoveInputMapping(TouchMapping)
        set Commanding = array{}

    OnSimulate<override>()<suspends>:void =
        race:
            RunPlaceLoop()
            RunUIListeners()

    OnFirstSpawn<private>(Player:player):void =
        Entered := EnterCommand(Player)

    EnterCommand<public>(Player:player):logic =
        if (Commanding.Find[Player]):
            false
        else:
            # pop any stray stack entry first so the single RemoveFrom on exit always clears the camera
            FixedCamera.RemoveFrom(Player)
            FixedCamera.AddTo(Player)
            if (Input := GetPlayerInput[Player]):
                Input.AddInputMapping(TouchMapping)
            CmdUI := EnsureUI(Player)
            CmdUI.Show()
            set Commanding += array{Player}
            if (HideHUDInCommand?):
                SetStockHUDHidden(Player, true)
            EnteredCommandEvent.Signal(Player)
            Print("TD cmd: entered command mode")
            true

    ExitCommand<public>(Player:player):logic =
        if (Commanding.Find[Player]):
            # drop commanding first so the place loop's re-assert skips
            set Commanding = Commanding.RemoveAllElements(Player)
            if (Ctrl := Controller[]):
                Cancelled := Ctrl.Cancel()
            FixedCamera.RemoveFrom(Player)
            if (Input := GetPlayerInput[Player]):
                Input.RemoveInputMapping(TouchMapping)
            if (CmdUI := UIs[Player]):
                CmdUI.Hide()
            SetStockHUDHidden(Player, false)
            ExitedCommandEvent.Signal(Player)
            Print("TD cmd: exited command mode")
            true
        else:
            false

    # GameCtrl is both start-game and next-wave; the label shows which.
    OnAdvancePressed<private>(CmdUI:td_commander_ui, Player:player):void =
        if (Game := FindGame[]):
            Started := Game.Start()
            if (Started?):
                Print("TD cmd: game started")
                CmdUI.SetGameCtrlLabel(MsgNextWave)
            else:
                Accepted := Game.RequestNextWave()
                if (Accepted?):
                    Print("TD cmd: next wave requested")
                else:
                    Print("TD cmd: next wave refused (wave already running)")
        else:
            Print("TD cmd: no td_game_component on entity or ancestors")

    # one listener per widget via recursive race; widgets outlive Hide, so no cleanup needed
    RunUIListeners<private>()<suspends>:void =
        Created := UICreated.Await()
        race:
            RunUIListeners()
            RunWidgetLoop(Created(0), Created(1))

    RunWidgetLoop<private>(Player:player, CmdUI:td_commander_ui)<suspends>:void =
        W := CmdUI.CmdWidget
        Events := SlotPressedEvents(W)
        race:
            loop:
                W.GameCtrl_PressedEvent.Await()
                OnAdvancePressed(CmdUI, Player)
            loop:
                W.ControlMode_PressedEvent.Await()
                Exited := ExitCommand(Player)
            # one arm per widget slot; extend alongside MaxTowerSlots
            RunSlotLoop(Player, 0, Events)
            RunSlotLoop(Player, 1, Events)
            RunSlotLoop(Player, 2, Events)

    RunSlotLoop<private>(Player:player, Index:int, Events:[]event(tuple()))<suspends>:void =
        if (Ev := Events[Index]):
            loop:
                Ev.Await()
                PlaceRequest.Signal((Player, Index))
        else:
            Sleep(Inf)

    # one placement at a time; a new request cancels the running one
    RunPlaceLoop<private>()<suspends>:void =
        var Pending:?tuple(player, int) = false
        loop:
            Req := if (P := Pending?) then P else PlaceRequest.Await()
            set Pending = false
            race:
                RunOnePlacement(Req(0), Req(1))
                block:
                    Next := PlaceRequest.Await()
                    set Pending = option{Next}

    RunOnePlacement<private>(Player:player, Index:int)<suspends>:void =
        MaybeEntry := option{(td_commander_component:)Towers[Index]}
        MaybeCtrl := option{Controller[]}
        if (Entry := MaybeEntry?, Ctrl := MaybeCtrl?):
            Name := Entry.DisplayName
            Print("TD cmd: placing {Name}")
            Placed := Ctrl.BeginPlace(Player, Entry.Prefab)
            if (Placed?):
                Print("TD cmd: {Name} placed")
                BumpPlacedCount(Player, Index)
            else:
                Print("TD cmd: {Name} placement cancelled")
            # the method's session end may have stripped TouchMapping
            if (Commanding.Find[Player], Input := GetPlayerInput[Player]):
                Input.AddInputMapping(TouchMapping)
        else:
            Print("TD cmd: no tower in slot {Index} or no placement_controller_component")

    BumpPlacedCount<private>(Player:player, Index:int):void =
        N := (PlacedCounts[Index] or 0) + 1
        if (set PlacedCounts[Index] = N) {}
        if (CmdUI := UIs[Player]):
            SetSlotCount(CmdUI.CmdWidget, Index, N)

    EnsureUI<private>(Player:player):td_commander_ui =
        if (Existing := UIs[Player]):
            Existing
        else:
            New := MakeCommanderUI(Player, (td_commander_component:)Towers, ConsumeUIInput)
            # a widget created mid-game must not offer "Start Game"
            if (Game := FindGame[], not (Game.GetState() = td_game_state.Idle)):
                New.SetGameCtrlLabel(MsgNextWave)
            if (set UIs[Player] = New) {}
            UICreated.Signal((Player, New))
            New

    SetStockHUDHidden<private>(Player:player, Hidden:logic):void =
        if (Playspace := Entity.GetPlayspaceForEntity[]):
            Elements:[]hud_element_identifier = array{creative_hud_identifier_all{}, player_hud_identifier_all{}}
            HUD := Playspace.GetHUDController()
            if (Hidden?):
                HUD.HideElementsForPlayer(Player, Elements)
            else:
                HUD.ResetElementsForPlayer(Player, Elements)

    Controller<private>()<transacts><decides>:placement_controller_component =
        Entity.GetComponent[placement_controller_component] or first{C : Entity.FindDescendantComponents(placement_controller_component)}

    FindGame<private>()<transacts><decides>:td_game_component =
        Entity.GetComponent[td_game_component] or first{G : Entity.FindAncestorComponents(td_game_component)}


# Walk-up re-entry: pair with an interactable on the console entity; interact
# puts the player back into command mode. Finds the commander via ancestors.
command_console_component<public> := class<final_super>(component):

    var<private> Subs<private>:[]cancelable = array{}
    # subscription_task is not a cancelable (its Cancel signals), so these are stored concretely
    var<private> CmdSubs<private>:[]Concurrency.subscription_task(player) = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Interactable := Entity.GetComponent[interactable_component]):
            set Subs += array{Interactable.SucceededEvent.Subscribe(OnInteracted)}
        else:
            Print("TD cmd: console entity has no interactable_component")
        # disabled while commanding, explicitly re-enabled on exit
        if (Commander := FindCommander[]):
            set CmdSubs += array{Commander.EnteredCommandEvent.Subscribe(OnCommandEntered)}
            set CmdSubs += array{Commander.ExitedCommandEvent.Subscribe(OnCommandExited)}

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (C : Subs):
            C.Cancel()
        set Subs = array{}
        for (C : CmdSubs):
            C.Cancel()
        set CmdSubs = array{}

    OnInteracted<private>(Agent:agent):void =
        if (Player := player[Agent], Commander := FindCommander[]):
            Entered := Commander.EnterCommand(Player)

    OnCommandEntered<private>(Player:player):void =
        if (Interactable := Entity.GetComponent[interactable_component]):
            Interactable.Disable()

    OnCommandExited<private>(Player:player):void =
        if (Interactable := Entity.GetComponent[interactable_component]):
            Interactable.Enable()

    FindCommander<private>()<transacts><decides>:td_commander_component =
        Entity.GetComponent[td_commander_component] or first{C : Entity.FindAncestorComponents(td_commander_component)}
