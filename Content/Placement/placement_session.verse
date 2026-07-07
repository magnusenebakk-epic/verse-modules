using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# The placement core, decoupled from items: tick the method, validate,
# highlight, and wait for a confirm/cancel. Anything can drive one
# programmatically (placable_component wires it to equip + input action,
# the chess board wires it to piece interactions):
#
#     Session := placement_session{Query := ..., Method := ..., Highlight := ...}
#     race:
#         block:
#             if (Proposal := Session.Run()?):
#                 Commit(Proposal)
#         MyConfirmSource(Session)   # calls RequestConfirm/RequestCancel
#
# Run ends at RequestCancel (returns false) or at the first RequestConfirm
# that lands while the proposal is valid (returns it). Confirms while
# invalid are ignored, the session keeps running.

placement_session<public> := class:

    Query<public>:placement_query
    Method<public>:placement_method
    Restrictions<public>:[]placement_restriction = array{}
    Highlight<public>:placement_highlight

    var LatestValid<private>:?placement_proposal = false
    ConfirmEvent<private>:event() = event(){}
    CancelEvent<private>:event() = event(){}

    RequestConfirm<public>():void =
        ConfirmEvent.Signal()

    RequestCancel<public>():void =
        CancelEvent.Signal()

    Run<public>()<suspends>:?placement_proposal =
        defer:
            Highlight.HidePreview()
        set LatestValid = false
        var Outcome:?placement_proposal = false
        race:
            block:   # decision arm; completing it ends the race
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
                        if (P := LatestValid?):
                            set Outcome = option{P}
                            set Deciding = false
                        # invalid confirm: ignored, keep running
                    else:
                        set Deciding = false
            TickLoop()   # never completes; cancelled when the decision lands
        Outcome

    # Preview without the decision machinery: tick/validate/highlight forever
    # until the enclosing scope cancels it. For drivers that own their commit
    # gesture elsewhere and only want the live marker.
    RunPreviewOnly<public>()<suspends>:void =
        defer:
            Highlight.HidePreview()
        TickLoop()

    TickLoop<private>()<suspends>:void =
        loop:
            if (Proposal := Method.ComputeProposal[Query]):
                Valid := logic{CheckAll[Proposal]}
                set LatestValid = if (Valid?) then option{Proposal} else false
                Highlight.ShowPreview(Query, Proposal, Valid)
            else:
                set LatestValid = false
                Highlight.HidePreview()
            Sleep(0.0)

    CheckAll<private>(Proposal:placement_proposal)<transacts><decides>:void =
        for (R : Restrictions):
            R.CanPlaceAt[Query, Proposal]
