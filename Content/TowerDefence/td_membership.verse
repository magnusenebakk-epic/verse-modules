using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Placement }


# Game membership: authored entities belong by hierarchy, runtime spawns by
# this stamp. Not @editable; entity refs can't be wired in the editor.
td_game_ref_component<public> := class<final_super>(component):
    var Game<public>:?td_game_component = false


# checks self then ancestors for a stamp or game component; fails for unaffiliated entities
FindOwningGame<public>(E:entity)<transacts><decides>:td_game_component =
    Chain := array{E} + (for (A : E.FindAncestorEntities(entity)) { A })
    Found := for:
        C : Chain
        G := GameOn[C]
    do:
        G
    Found[0]

GameOn<internal>(E:entity)<transacts><decides>:td_game_component =
    if (R := E.GetComponent[td_game_ref_component], G := R.Game?):
        G
    else:
        E.GetComponent[td_game_component]


# fails only when both sides belong to different known games; unaffiliated always passes
MayEngage<public>(A:entity, B:entity)<transacts><decides>:void =
    not CrossGame[A, B]

CrossGame<internal>(A:entity, B:entity)<transacts><decides>:void =
    GA := FindOwningGame[A]
    GB := FindOwningGame[B]
    not (GA = GB)


# a searcher's own game's lanes if it belongs to one, else every lane in the sim
CandidateLanes<public>(SearchRoot:entity)<transacts>:[]lane_component =
    Scoped := ScopedLanes(SearchRoot)
    if (Scoped.Length > 0):
        Scoped
    else if (Sim := SearchRoot.GetSimulationEntity[]):
        for (L : Sim.FindDescendantComponents(lane_component)) { L }
    else:
        array{}

ScopedLanes<internal>(SearchRoot:entity)<transacts>:[]lane_component =
    MaybeGame := option{FindOwningGame[SearchRoot]}
    if (G := MaybeGame?):
        Owned := G.GetLanes()
        if (Owned.Length > 0):
            Owned
        else:
            # game not started yet: read the authored board directly
            for (L : G.Entity.FindDescendantComponents(lane_component)) { L }
    else:
        array{}


# Keeps a projectile's damage on its own board; wire into HitGates on
# multi-board maps. An unstamped projectile blocks nothing.
same_game_projectile_gate<public> := class(projectile_hit_gate):
    Allows<override>(ProjectileEntity:entity, HitEntity:entity)<transacts><decides>:void =
        MayEngage[ProjectileEntity, HitEntity]


# Rejects placements on another game's board. The aim sweep is sim-wide, so
# grid methods would otherwise snap to a neighbour's grid.
same_game_placement_restriction<public> := class(placement_restriction):
    CanPlaceAt<override>(Query:placement_query, Proposal:placement_proposal)<transacts><decides>:void =
        if (HitEnt := Proposal.HitEntity?):
            MayEngage[Query.PlacableEntity, HitEnt]


# Stamps towers placed through a placement_controller_component with the
# owning game. Put it on the controller's entity, under the game entity.
td_placement_claim_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        MaybeController := option{Entity.GetComponent[placement_controller_component]}
        MaybeGame := option{FindOwningGame[Entity]}
        if (Controller := MaybeController?, Game := MaybeGame?):
            loop:
                Placed := Controller.PlacedEvent.Await()
                # a relocate can hand over another game's tower; don't claim those
                Foreign := if (Owner := FindOwningGame[Placed], not (Owner = Game)) then true else false
                if (not Foreign?):
                    Game.Claim(Placed)
