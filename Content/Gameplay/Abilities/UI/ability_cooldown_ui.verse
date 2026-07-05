using { /UnrealEngine.com/Temporary/UI }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }

using { Gameplay.Abilities }
using { /createjag@fortnite.com/CustomItemsRPG/UI }


MsgReady<localizes>:message = "READY"


ability_cooldown_row<public> := class:
    AbilityE<public>:entity
    Root<public>:widget
    StatusText<public>:text_block
    var<private> StartedSub<private>:?Concurrency.subscription_task(float) = false
    var<private> EndedSub<private>:?Concurrency.subscription_task(tuple()) = false

    Initialize<public>():void =
        if (CC := AbilityE.GetComponent[ability_cooldown_component]):
            StartTask := CC.CooldownStartedEvent.Subscribe(OnStarted)
            set StartedSub = option{StartTask}
            EndTask := CC.CooldownEndedEvent.Subscribe(OnEnded)
            set EndedSub = option{EndTask}
            Refresh()

    Refresh<public>():void =
        if (CC := AbilityE.GetComponent[ability_cooldown_component], CC.IsOnCooldown[]):
            StatusText.SetText(S2M("..."))
        else:
            StatusText.SetText(MsgReady)

    OnStarted<private>(Duration:float):void =
        spawn { Countdown(Duration) }

    OnEnded<private>(Tuple:tuple()):void =
        StatusText.SetText(MsgReady)

    Countdown<private>(Duration:float)<suspends>:void =
        var Remaining:int = Ceil[Duration] or 0
        loop:
            if (Remaining <= 0). break
            StatusText.SetText(S2M("{Remaining}s"))
            Sleep(1.0)
            set Remaining = Remaining - 1
        StatusText.SetText(MsgReady)


ability_cooldown_ui<public> := class(ui_component):
    Rows<public>:[]ability_cooldown_row

    OnInit<override>():void =
        for (Row : Rows):
            Row.Initialize()


MakeAbilityCooldownRow<public><constructor>(AbilityE:entity, Icon:texture)<transacts> := ability_cooldown_row:
    let:
        IconBlock := texture_block:
            DefaultImage := Icon
            DefaultDesiredSize := vector2{X := 64.0, Y := 64.0}

        StatusBlock := text_block:
            DefaultText := MsgReady
            DefaultTextSize := 18.0
            DefaultTextColor := NamedColors.White

        RowStack := stack_box:
            Orientation := orientation.Horizontal
            Slots := array:
                stack_box_slot:
                    Widget := IconBlock
                    HorizontalAlignment := horizontal_alignment.Left
                    VerticalAlignment := vertical_alignment.Center
                stack_box_slot:
                    Widget := StatusBlock
                    Padding := margin{Left := 12.0}
                    HorizontalAlignment := horizontal_alignment.Fill
                    VerticalAlignment := vertical_alignment.Center

    AbilityE := AbilityE
    Root := RowStack
    StatusText := StatusBlock


MakeAbilityCooldownUI<public><constructor>(P:player, ItemEntity:entity)<transacts> := ability_cooldown_ui:
    let:
        Rows := for:
            Ability : ItemEntity.FindDescendantEntities(ability_base)
            CC := Ability.GetComponent[ability_cooldown_component]
            IC := Ability.GetComponent[icon_component]
        do:
            MakeAbilityCooldownRow(Ability, IC.Icon)

        Stack := stack_box:
            Orientation := orientation.Vertical
            Slots := for (R : Rows):
                stack_box_slot:
                    Widget := R.Root
                    Padding := margin{Bottom := 6.0}
                    HorizontalAlignment := horizontal_alignment.Fill
                    VerticalAlignment := vertical_alignment.Top

        Root := canvas:
            Slots := array:
                canvas_slot:
                    Widget := Stack
                    Anchors := AnchorAt(1.0, 0.5)
                    Offsets := margin{Right := 60.0}
                    Alignment := vector2{X := 1.0, Y := 0.5}

    Player := P
    Widget := Root
    Rows := Rows
    OptSlot := option{ player_ui_slot{ZOrder := 0, InputMode := ui_input_mode.None} }
