using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/UI }
using { /UnrealEngine.com/Itemization }

using { Effects }
using { /createjag@fortnite.com/CustomItemsRPG/UI }


MsgEmpty<localizes>:message = ""


buff_ui_row<public> := class:
    EffectE<public>:entity
    Polarity<public>:effect_polarity
    Root<public>:widget
    StackText<public>:text_block
    DurationText<public>:text_block

    var<private> StackSub<private>:?cancelable = false

    Initialize<public>():void =
        if (Stk := EffectE.GetComponent[stackable_component]):
            set StackSub = option{Stk.ChangeStackSizeEvent.Subscribe(OnStackChanged)}
        Refresh()

    Cleanup<public>():void =
        if (StackSub?.Cancel()):
            set StackSub = false

    Refresh<public>():void =
        StackCount := if (Stk := EffectE.GetComponent[stackable_component]) then Stk.StackSize else 1
        if (StackCount > 1):
            StackText.SetText(S2M("x{StackCount}"))
        else:
            StackText.SetText(MsgEmpty)

    UpdateDuration<public>():void =
        if (Dur := EffectE.GetComponent[duration_effect_component]):
            Remaining := Dur.GetRemaining()
            Secs := Ceil[Remaining] or 0
            DurationText.SetText(S2M("{Secs}s"))

    OnStackChanged<private>(Result:change_stack_size_result):void =
        Refresh()


buff_ui<public> := class(ui_component):
    BuffStack<public>:stack_box
    DebuffStack<public>:stack_box

    var<private> Rows<private>:[entity]buff_ui_row = map{}
    var<private> TickCancel<private>:event() = event(){}

    OnInit<override>():void =
        spawn { TickLoop() }

    OnHide<override>():void =
        TickCancel.Signal()
        for (E -> R : Rows):
            R.Cleanup()
        set Rows = map{}

    AddRow<public>(EffectE:entity, Polarity:effect_polarity):void =
        if (Existing := Rows[EffectE]):
            return
        if (IC := EffectE.GetComponent[icon_component]):
            Row := MakeBuffUIRow(EffectE, Polarity, IC.Icon)
            Row.Initialize()
            if (set Rows[EffectE] = Row) {}
            Slot := stack_box_slot{
                Widget := Row.Root,
                Padding := margin{Bottom := 4.0},
                HorizontalAlignment := horizontal_alignment.Left,
                VerticalAlignment := vertical_alignment.Top
            }
            if (Polarity = effect_polarity.Debuff):
                DebuffStack.AddWidget(Slot)
            else:
                BuffStack.AddWidget(Slot)

    RemoveRow<public>(EffectE:entity):void =
        if (Row := Rows[EffectE]):
            Row.Cleanup()
            if (Row.Polarity = effect_polarity.Debuff):
                DebuffStack.RemoveWidget(Row.Root)
            else:
                BuffStack.RemoveWidget(Row.Root)
            set Rows = Rows.RemoveKey(EffectE)

    TickLoop<private>()<suspends>:void =
        race:
            TickCancel.Await()
            TickInner()

    TickInner<private>()<suspends>:void =
        loop:
            for (E -> R : Rows):
                R.UpdateDuration()
            Sleep(0.1)


MakeBuffUIRow<public><constructor>(EffectE:entity, Polarity:effect_polarity, Icon:texture)<transacts> := buff_ui_row:
    let:
        IconBlock := texture_block:
            DefaultImage := Icon
            DefaultDesiredSize := vector2{X := 48.0, Y := 48.0}

        StackBlock := text_block:
            DefaultText := MsgEmpty
            DefaultTextSize := 14.0
            DefaultTextColor := NamedColors.White

        DurationBlock := text_block:
            DefaultText := MsgEmpty
            DefaultTextSize := 12.0
            DefaultTextColor := NamedColors.White

        RowStack := stack_box:
            Orientation := orientation.Horizontal
            Slots := array:
                stack_box_slot:
                    Widget := IconBlock
                    HorizontalAlignment := horizontal_alignment.Left
                    VerticalAlignment := vertical_alignment.Center
                stack_box_slot:
                    Widget := StackBlock
                    Padding := margin{Left := 4.0}
                    HorizontalAlignment := horizontal_alignment.Left
                    VerticalAlignment := vertical_alignment.Center
                stack_box_slot:
                    Widget := DurationBlock
                    Padding := margin{Left := 8.0}
                    HorizontalAlignment := horizontal_alignment.Left
                    VerticalAlignment := vertical_alignment.Center

    EffectE := EffectE
    Polarity := Polarity
    Root := RowStack
    StackText := StackBlock
    DurationText := DurationBlock


MakeBuffUI<public><constructor>(P:player)<transacts> := buff_ui:
    let:
        BuffStackBox := stack_box:
            Orientation := orientation.Vertical
            Slots := array{}

        DebuffStackBox := stack_box:
            Orientation := orientation.Vertical
            Slots := array{}

        Root := canvas:
            Slots := array:
                canvas_slot:
                    Widget := BuffStackBox
                    Anchors := AnchorAt(0.0, 0.0)
                    Offsets := margin{Left := 20.0, Top := 80.0}
                    Alignment := vector2{X := 0.0, Y := 0.0}
                canvas_slot:
                    Widget := DebuffStackBox
                    Anchors := AnchorAt(1.0, 0.0)
                    Offsets := margin{Right := 20.0, Top := 80.0}
                    Alignment := vector2{X := 1.0, Y := 0.0}

    Player := P
    Widget := Root
    BuffStack := BuffStackBox
    DebuffStack := DebuffStackBox
    OptSlot := option{ player_ui_slot{ZOrder := 0, InputMode := ui_input_mode.None} }
