using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


# Placement core, driver-agnostic: ticks the method, validates, highlights, waits for confirm/cancel.
# Run returns the confirmed proposal, or false on cancel; invalid confirms are ignored and it keeps running.

placement_session<public> := class(placement_controls):

    Query<public>:placement_query
    Method<public>:placement_method
    Highlights<public>:[]placement_highlight = array{}
    OnPlacedEffects<public>:[]placement_effect = array{}

    ConfirmEvent<private>:event() = event(){}
    CancelEvent<private>:event() = event(){}

    RequestConfirm<override>():void =
        ConfirmEvent.Signal()

    RequestCancel<override>():void =
        CancelEvent.Signal()

    Run<public>()<suspends>:?placement_proposal =
        defer:
            for (H : Highlights):
                H.HidePreview()
        for (H : Highlights):
            H.OnSessionStart(Query)
        var Outcome:?placement_proposal = false
        race:
            block:   # decision arm, completing it ends the race
                var Deciding:logic = true
                loop:
                    if (not Deciding?):
                        break
                    Confirmed := race:
                        block:
                            ConfirmEvent.Await()
                            true
                        block:
                            CancelEvent.Await()
                            false
                    if (Confirmed?):
                        # revalidate at confirm time so a press that just moved the target confirms at the new spot
                        if (P := Method.ComputeProposal[Query]):
                            if (CheckAll[P]):
                                Print("placement: confirm ok at {ToString(P.Transform.Translation)}")
                                set Outcome = option{P}
                                set Deciding = false
                            else:
                                Print("placement: confirm blocked by restriction at {ToString(P.Transform.Translation)}")
                        else:
                            Print("placement: confirm ignored, no aim proposal")
                            DebugProbe()
                    else:
                        set Deciding = false
            TickLoop()   # never completes, cancelled when the decision lands
            InputArm()
        Outcome

    # Live marker only, for drivers that commit elsewhere; RunInput still runs but its confirms go nowhere.
    RunPreviewOnly<public>()<suspends>:void =
        defer:
            for (H : Highlights):
                H.HidePreview()
        for (H : Highlights):
            H.OnSessionStart(Query)
        race:
            TickLoop()
            InputArm()

    # Sleep(Inf) guard so a no-op RunInput doesn't end the race.
    InputArm<private>()<suspends>:void =
        Method.RunInput(Query, Self)
        Sleep(Inf)

    TickLoop<private>()<suspends>:void =
        # dedupe on the aim string so cell hops print once, not per tick
        var LastAim:string = ""
        loop:
            AimMsg := if (Proposal := Method.ComputeProposal[Query]):
                Valid := logic{CheckAll[Proposal]}
                for (H : Highlights):
                    H.ShowPreview(Query, Proposal, Valid)
                ValidStr := if (Valid?) then "ok" else "blocked"
                "{ToString(Proposal.Transform.Translation)} [{ValidStr}]"
            else:
                # aim lost this tick, not session end; persistent highlights keep showing
                for (H : Highlights):
                    H.OnProposalLost()
                "none"
            if (AimMsg <> LastAim):
                Print("placement: aim {AimMsg}")
                set LastAim = AimMsg
                # log why aim was lost (the first one each session is just no press yet)
                if (AimMsg = "none"):
                    DebugProbe()
            Sleep(0.0)

    # Temporary debug: re-runs the grid method's steps to report which one fails when aim is lost.
    DebugProbe<private>():void =
        if (GM := grid_component_placement_method[Method]):
            if (InnerP := GM.HitMethod.ComputeProposal[Query]):
                if (HitEnt := InnerP.HitEntity?):
                    if (G := FindGridComponent[HitEnt]):
                        GridXform := G.Entity.GetGlobalTransform()
                        GridOrigin := GridXform.Translation + G.OriginOffset * GridXform.Rotation
                        LocalPos := (InnerP.Transform.Translation - GridOrigin) * GridXform.Rotation.Invert()
                        CellF := LocalPos.Forward / G.CellSize
                        CellL := LocalPos.Left / G.CellSize
                        Print("placement dbg: hit {ToString(InnerP.Transform.Translation)}, grid origin {ToString(GridOrigin)}")
                        Print("placement dbg: cell coords F={CellF} L={CellL}, field is {G.CellsForward}x{G.CellsLeft} cells of {G.CellSize}")
                    else:
                        Print("placement dbg: hit entity has no grid_component on itself or ancestors")
                else:
                    Print("placement dbg: inner method returned no HitEntity")
            else:
                Print("placement dbg: pointer sweep found no accepted hit (no press yet, filters, or range)")
        else:
            Print("placement dbg: method is not grid_component_placement_method")

    CheckAll<private>(Proposal:placement_proposal)<transacts><decides>:void =
        for (R : Query.Restrictions):
            R.CanPlaceAt[Query, Proposal]

    # Commit-side bookkeeping, fired once by whoever commits the confirmed proposal.
    RunPlacedEffects<public>(Placed:entity, Proposal:placement_proposal):void =
        for (E : OnPlacedEffects):
            E.OnPlaced(Placed, Query, Proposal)


# Confirm moves Target to the proposal and fires effects; cancel restores the original transform (matters if a highlight moved it).
RunWorldPlacement<public>(Target:entity, Session:placement_session)<suspends>:?placement_proposal =
    Original := Target.GetGlobalTransform()
    var Confirmed:logic = false
    defer:
        if (not Confirmed?):
            Target.SetGlobalTransform(Original)
    Outcome := Session.Run()
    if (Proposal := Outcome?):
        Target.SetGlobalTransform(Proposal.Transform)
        set Confirmed = true
        Print("placement: committed at {ToString(Proposal.Transform.Translation)} scale {ToString(Proposal.Transform.Scale)}")
        Session.RunPlacedEffects(Target, Proposal)
    else:
        Print("placement: session ended without confirm")
    Outcome
