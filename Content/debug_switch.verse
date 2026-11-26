# Master switch over the per-component debug flags; false silences everything. Lives at content root so every module sees it.
DebugMaster<public>:logic = false

DebugOn<public>(Flag:logic)<reads><decides>:void =
    DebugMaster?
    Flag?
