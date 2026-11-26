using { /Fortnite.com/UI }
using { /UnrealEngine.com/Temporary/UI }
using { /Verse.org/Assets }
using { /Verse.org/Concurrency }
using { /Verse.org/Simulation }

using { /invaliddomain/MobileGamesTD2/UI }


# Dedicated message fields so they localize; static labels are authored in the UMG widget itself.
MsgStartGame<localizes>:message = "Start Game"
MsgNextWave<localizes>:message = "Next Wave"


# UMG verse fields can't be arrays, so the slot helpers map index 0..N-1 to the named TowerN fields.
MaxTowerSlots<public>:int = 3

# module-internal on purpose: the widget class is project-scoped, so wider signatures hit verse error 3593
SlotPressedEvents(W:WBP_TowerCommanderUI):[]event(tuple()) =
    array{W.Tower1_PressedEvent, W.Tower2_PressedEvent, W.Tower3_PressedEvent}

SetSlotIcon(W:WBP_TowerCommanderUI, Index:int, T:texture):void =
    if (Index = 0). set W.Tower1_Icon = T
    if (Index = 1). set W.Tower2_Icon = T
    if (Index = 2). set W.Tower3_Icon = T

SetSlotCount(W:WBP_TowerCommanderUI, Index:int, N:int):void =
    if (Index = 0). set W.Tower1_Count = N
    if (Index = 1). set W.Tower2_Count = N
    if (Index = 2). set W.Tower3_Count = N

SetSlotVisible(W:WBP_TowerCommanderUI, Index:int, Visible:logic):void =
    if (Index = 0). set W.Tower1_Visible = Visible
    if (Index = 1). set W.Tower2_Visible = Visible
    if (Index = 2). set W.Tower3_Visible = Visible


# Wraps the UMG commander widget; holds no logic. Module-internal like its
# CmdWidget field: a wider class gets a public constructor internal scopes can't call (3593).
td_commander_ui := class(ui_component):
    CmdWidget:WBP_TowerCommanderUI

    SetGameCtrlLabel<public>(M:message):void =
        set CmdWidget.GameCtrl_LabelMessage = M


MakeCommanderUI(P:player, Palette:[]tower_palette_entry, ConsumeInput:logic):td_commander_ui =
    W := WBP_TowerCommanderUI{}
    set W.GameCtrl_LabelMessage = MsgStartGame
    if (Palette.Length > MaxTowerSlots):
        Print("TD cmd: {Palette.Length} palette towers but the widget has {MaxTowerSlots} slots; extras are unreachable")
    for (Index -> Entry : Palette):
        if (T := Entry.Icon?):
            SetSlotIcon(W, Index, T)
        SetSlotCount(W, Index, 0)
    # slots with no palette entry hide entirely
    for (Index := 0..MaxTowerSlots - 1):
        SetSlotVisible(W, Index, if (Index < Palette.Length) then true else false)
    Mode := if (ConsumeInput?) then ui_input_mode.All else ui_input_mode.None
    td_commander_ui:
        Player := P
        Widget := W
        CmdWidget := W
        OptSlot := option{player_ui_slot{ZOrder := 10, InputMode := Mode}}
