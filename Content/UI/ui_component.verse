using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/ControlInput }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }


player_ui_input_data<public> := class:
    PlayerInput<public>:player_input
    MappingToApply<public>:input_mapping

    Apply<public>():void =
        PlayerInput.AddInputMapping(MappingToApply)

    Remove<public>():void =
        PlayerInput.RemoveInputMapping(MappingToApply)


ui_component<public> := class<abstract><unique>:
    Player<public>:player
    Widget<public>:widget
    OptSlot<public>:?player_ui_slot = false
    OptInput<public>:?player_ui_input_data = false

    ShownEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    HiddenEvent<public>:Concurrency.subscribable_event(tuple()) =
        Concurrency.subscribable_event(tuple()){}

    var<private> Initialized<private>:logic = false
    var<private> Visible<private>:logic = false

    Initialize<public><final>():void =
        if (Initialized?). return
        OnInit()
        set Initialized = true

    Show<public><final>():void =
        if (Visible?). return
        Initialize()
        if (PlayerUI := GetPlayerUI[Player]):
            Slot := if (S := OptSlot?) then S else player_ui_slot{InputMode := ui_input_mode.None}
            PlayerUI.AddWidget(Widget, Slot)
        if (Input := OptInput?). Input.Apply()
        set Visible = true
        OnShow()
        ShownEvent.Signal(())

    Hide<public><final>():void =
        if (not Visible?). return
        if (PlayerUI := GetPlayerUI[Player]):
            PlayerUI.RemoveWidget(Widget)
        if (Input := OptInput?). Input.Remove()
        set Visible = false
        OnHide()
        HiddenEvent.Signal(())

    IsVisible<public>()<decides><reads>:void = Visible?
    IsInitialized<public>()<decides><reads>:void = Initialized?

    OnInit<protected>():void = {}
    OnShow<protected>():void = {}
    OnHide<protected>():void = {}


ui_group<public> := class<abstract>(ui_component):
    var<protected> Children<protected>:[]ui_component = array{}

    AddChild<public>(C:ui_component):void =
        set Children += array{C}
        if (IsVisible[]):
            C.Show()

    RemoveChild<public>(C:ui_component):void =
        set Children = for (X : Children, not (X = C)) { X }
        C.Hide()

    OnShow<override>():void =
        for (C : Children):
            C.Show()

    OnHide<override>():void =
        for (C : Children):
            C.Hide()


S2M<localizes><public>(S:string)<transacts>:message = "{S}"

AnchorAt<public>(X:float, Y:float)<transacts>:anchors =
    anchors{Minimum := vector2{X := X, Y := Y}, Maximum := vector2{X := X, Y := Y}}
