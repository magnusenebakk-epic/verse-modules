using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }


placement_query<public> := class:
    Player<public>:player
    PlacableEntity<public>:entity

    # Lives on the query so highlights validate with the same rules the confirm uses.
    Restrictions<public>:[]placement_restriction = array{}


# Method output
placement_proposal<public> := class:
    Transform<public>:transform
    HitNormal<public>:?vector3 = false
    HitEntity<public>:?entity = false


# Confirm/cancel surface of a running session, handed to RunInput.
placement_controls<public> := interface:
    RequestConfirm<public>():void
    RequestCancel<public>():void


# Fails when there's no valid proposal this tick.
placement_method<public> := class<public><abstract>:
    ComputeProposal<public>(Query:placement_query)<transacts><decides>:placement_proposal

    # Method-owned input arm, raced by the session; gesture methods drive Controls here, wrappers forward, default is a no-op.
    RunInput<public>(Query:placement_query, Controls:placement_controls)<suspends>:void = {}


hit_filter<public> := class<abstract>:
    Accepts<public>(Hit:sweep_hit)<transacts><decides>:void


hit_aware_placement_method<public> := class<abstract>(placement_method):
    @editable
    var HitFilters<public>:[]hit_filter = array{}

    # First hit passing all filters, skipping the placable itself (it may be following the pointer).
    FirstAcceptedHit<protected>(Query:placement_query, Hits:generator(sweep_hit))<transacts><decides>:sweep_hit =
        (for (H : Hits, not IsSelfHit[Query, H], AcceptsAll[H]) { H })[0]

    IsSelfHit<private>(Query:placement_query, Hit:sweep_hit)<transacts><decides>:void =
        HitE := Hit.TargetComponent.Entity
        (HitE = Query.PlacableEntity) or (first (A : HitE.FindAncestorEntities(entity), A = Query.PlacableEntity) { A })

    AcceptsAll<private>(Hit:sweep_hit)<transacts><decides>:void =
        for (F : HitFilters) { F.Accepts[Hit] }


placement_restriction<public> := class<abstract>:
    CanPlaceAt<public>(Query:placement_query, Proposal:placement_proposal)<transacts><decides>:void


# Runs once per confirmed placement, after the placed entity is at the proposal; bookkeeping
# like grid occupancy goes here. Placed is the placable, or the spawned instance on the item path.
placement_effect<public> := class<abstract>:
    OnPlaced<public>(Placed:entity, Query:placement_query, Proposal:placement_proposal):void


# Per-tick preview. OnProposalLost fires on aimless ticks and defaults to hiding, so persistent
# highlights override it; HidePreview is the full clear at session end.
placement_highlight<public> := class<abstract>:
    ShowPreview<public>(Query:placement_query, Proposal:placement_proposal, IsValid:logic):void
    HidePreview<public>():void
    OnProposalLost<public>():void = HidePreview()

    # Runs once at session start, before any proposal; override for aim-independent visuals like the tiles painter.
    OnSessionStart<public>(Query:placement_query):void = {}


# Context-owned half of the placement config; a driver carries one profile for everything it places.
# A placable_component on the placed entity can override the method and extend the lists (MakePlacementSession).
placement_profile<public> := class<concrete>:
    @editable
    Method<public>:placement_method = virtual_pointer_placement_method{}

    @editable
    Restrictions<public>:[]placement_restriction = array{}

    @editable
    OnPlacedEffects<public>:[]placement_effect = array{}

    # move_entity suits world drivers (the placed entity is its own preview); the item path should use a marker.
    @editable
    Highlights<public>:[]placement_highlight = array{move_entity_highlight{}}

    # Session straight off the profile, for targets without a placable.
    MakeSession<public>(Player:player, Target:entity):placement_session =
        placement_session:
            Query := placement_query{
                Player := Player,
                PlacableEntity := Target,
                Restrictions := Restrictions}
            Method := Method
            Highlights := Highlights
            OnPlacedEffects := OnPlacedEffects
