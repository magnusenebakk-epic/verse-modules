using { /UnrealEngine.com/Temporary/Diagnostics }
using { /Verse.org/Simulation }


# Shared channel for all TD nav debug drawing; toggled and cleared as one group.
td_nav_debug_channel<public> := class(debug_draw_channel){}

# Per-enemy log id counter ("td[3]"); session-keyed since module vars must be weak_maps.
var TDNavDebugIds:weak_map(session, int) = map{}

NextTDNavDebugId<public>():int =
    S := GetSession()
    Next := if (Cur := TDNavDebugIds[S]) then Cur + 1 else 1
    option{set TDNavDebugIds[S] = Next}
    Next
