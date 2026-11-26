using { /Verse.org/SceneGraph }
using { /Verse.org/SceneGraph/KeyframedMovement }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /Verse.org/Concurrency }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

using { Abilities }
using { Damage }


# Extra damage veto on both paths; lets systems add scoping, e.g. same_game_projectile_gate keeps shots on their own board.
projectile_hit_gate<public> := class<abstract>:
    Allows<public>(ProjectileEntity:entity, HitEntity:entity)<transacts><decides>:void


# How damage is delivered: spatial overlaps, or the assigned target on spawn/arrival.
projectile_delivery<public> := enum:
    SpatialHits
    AssignedOnSpawn
    AssignedOnArrival


# Flies forward, damages the first valid hit plus an optional splash sphere, then despawns. Damage paths: agents via DamageApplier, tagged entity health; HitGates veto both.
projectile_component<public> := class<final_super>(component):

    @editable
    var Speed<public>:float = 1500.0

    @editable
    var MaxLifetime<public>:float = 5.0

    @editable
    var (projectile_component:)Damage<public>:float = 25.0

    # Splash radius in cm around the impact; 0 = direct hit only.
    @editable
    var SplashRadius<public>:float = 0.0

    # Splash falloff: damage scales by (1 - dist/radius)^exponent; 0 = flat full damage.
    @editable
    var SplashFalloffExponent<public>:float = 0.0

    # Damage delivery mode. DamageableTags, HitGates and PassThroughNonAgents only apply to SpatialHits; splash victims always check tags and gates.
    @editable
    var Delivery<public>:projectile_delivery = projectile_delivery.SpatialHits

    @editable
    var PassThroughNonAgents<public>:logic = true

    # Hit entities (or ancestors) need one of these tags to take entity health damage; empty means agents only.
    @editable
    var DamageableTags<public>:[]subtype(tag) = array{}

    # Extra checks on both damage paths; a failed gate makes the hit pass through (add same_game_projectile_gate on multi-board maps).
    @editable
    var HitGates<public>:[]projectile_hit_gate = array{}

    @editable
    var AttributeToInstigator<public>:logic = false

    @editable
    var DamageApplier<public>:damage_applier

    # Log spawn, each overlap and its result, and despawn.
    @editable
    var DebugHits<public>:logic = true

    var<private> SourceCharEntity<private>:?entity = false
    var<private> HitEvent<private>:event() = event(){}
    # Assigned-delivery target; the spawner sets it right after spawn (fire_projectile_on_use_component passes the use target).
    var<private> AssignedTarget<private>:?entity = false

    SetAssignedTarget<public>(T:?entity):void =
        set AssignedTarget = T

    OnSimulate<override>()<suspends>:void =
        Sleep(0.0)
        if (E := ResolveSourceCharEntity[]):
            set SourceCharEntity = option{E}

        if (DebugOn[DebugHits]):
            HasMesh := if (Entity.GetComponent[mesh_component]) then "yes" else "no"
            HasTarget := if (AssignedTarget?) then "yes" else "no"
            DName := DeliveryName()
            Print("projectile: spawned at {ToString(Entity.GetGlobalTransform().Translation)} | speed {Speed} life {MaxLifetime} dmg {Self.Damage} | mesh {HasMesh} | {DName} target {HasTarget}")

        if (Delivery = projectile_delivery.SpatialHits):
            RunSpatial()
        else:
            RunAssigned()

        if (DebugOn[DebugHits]):
            Print("projectile: despawn at {ToString(Entity.GetGlobalTransform().Translation)}")
        Entity.RemoveFromParent()

    RunSpatial<private>()<suspends>:void =
        if (Movement := Entity.GetComponent[keyframed_movement_component]):
            ConfigureMovement(Movement)
            Movement.Play()
            race:
                HitListenLoop()
                HitEvent.Await()
                Movement.FinishedEvent.Await()
        else:
            if (DebugOn[DebugHits]):
                Print("projectile: no keyframed_movement_component - immobile for {MaxLifetime}s")
            race:
                HitListenLoop()
                HitEvent.Await()
                Sleep(MaxLifetime)

    # Nothing is hit-tested; the flight is just visual, the target takes damage on spawn or arrival.
    RunAssigned<private>()<suspends>:void =
        Instant := if (Delivery = projectile_delivery.AssignedOnSpawn) then true else false
        if (Instant?, T := AssignedTarget?):
            DealAssignedDamage(T)
        FlightTime := ArrivalTime()
        if (Movement := Entity.GetComponent[keyframed_movement_component]):
            ConfigureMovement(Movement)
            Movement.Play()
        else if (DebugOn[DebugHits]):
            Print("projectile: no keyframed_movement_component - immobile for {FlightTime}s")
        Sleep(FlightTime)
        if (not Instant?):
            if (T := AssignedTarget?):
                DealAssignedDamage(T)
            else if (DebugOn[DebugHits]):
                Print("projectile: assigned delivery with no target - flew as pure visual")

    # Time to reach where the target was at fire time, capped by lifetime.
    ArrivalTime<private>()<transacts>:float =
        if:
            T := AssignedTarget?
            Speed > 0.0
            D := Distance(Entity.GetGlobalTransform().Translation, T.GetGlobalTransform().Translation)
        then:
            Min(D / Speed, MaxLifetime)
        else:
            MaxLifetime

    # No gates or tags on the direct target (the assigner chose it); splash victims still check them.
    DealAssignedDamage<private>(T:entity):void =
        var DirectVictim:?entity = false
        if (Char := FindFortCharacterAt[T], Target := Char.GetAgent[], Root := Char.GetEntity[]):
            if (DebugOn[DebugHits]):
                Print("projectile: assigned {Self.Damage} damage to agent target")
            ApplyDamage(Target, Char, Self.Damage)
            set DirectVictim = option{Root}
        else if (Health := FindAnyHealthAt[T]):
            if (DebugOn[DebugHits]):
                Print("projectile: assigned {Self.Damage} damage to health target")
            Health.TakeDamage(Self.Damage, SourceOpt())
            set DirectVictim = option{Health.Entity}
        else if (DebugOn[DebugHits]):
            Print("projectile: assigned target has nothing damageable (already gone?)")
        ApplySplash(T.GetGlobalTransform().Translation, DirectVictim)

    # FindDamageableHealthAt without the tag check; assigned delivery skips side filtering.
    FindAnyHealthAt<private>(E:entity)<transacts><decides>:entity_health_component =
        Chain := array{E} + (for (A : E.FindAncestorEntities(entity)) { A })
        Found := for (C : Chain, H := C.GetComponent[entity_health_component]) { H }
        Found[0]

    # Sphere overlap at the impact; the direct victim is excluded, it already took the full hit.
    ApplySplash<private>(Center:(LUF:)vector3, DirectVictim:?entity):void =
        if (SplashRadius > 0.0):
            Sphere := collision_sphere{
                Radius := SplashRadius,
                CollisionProfile := CollisionProfiles.DynamicOverlapAll
            }
            SphereXform := (LUF:)transform{
                Translation := Center,
                Rotation    := (LUF:)IdentityRotation(),
                Scale       := (LUF:)vector3{Forward := 1.0, Left := 1.0, Up := 1.0}
            }
            var Splashed:[]entity = array{}
            for (Hit : Entity.FindOverlapHits(SphereXform, Sphere)):
                HitEntity := Hit.TargetComponent.Entity
                if:
                    Char := FindFortCharacterAt[HitEntity]
                    Target := Char.GetAgent[]
                    Root := Char.GetEntity[]
                    not SeenIn[Splashed, Root]
                    not (DirectVictim? = Root)
                    NotSource[Root]
                    GatesAllow[HitEntity]
                then:
                    set Splashed += array{Root}
                    Dist := Distance(Center, Root.GetGlobalTransform().Translation)
                    Dmg := SplashDamageAt(Dist)
                    if (Dmg > 0.0):
                        if (DebugOn[DebugHits]):
                            Print("projectile: splash {Dmg} to agent at {Dist}cm")
                        ApplyDamage(Target, Char, Dmg)
                else if:
                    Health := FindDamageableHealthAt[HitEntity]
                    Root := Health.Entity
                    not SeenIn[Splashed, Root]
                    not (DirectVictim? = Root)
                    GatesAllow[HitEntity]
                then:
                    set Splashed += array{Root}
                    Dist := Distance(Center, Root.GetGlobalTransform().Translation)
                    Dmg := SplashDamageAt(Dist)
                    if (Dmg > 0.0):
                        if (DebugOn[DebugHits]):
                            Print("projectile: splash {Dmg} to health entity at {Dist}cm")
                        Health.TakeDamage(Dmg, SourceOpt())
            if (DebugOn[DebugHits]):
                Print("projectile: splash covered {Splashed.Length} nearby targets")

    # (1 - dist/radius)^exponent falloff; full damage at center, zero at the edge.
    SplashDamageAt<private>(Dist:float)<reads>:float =
        if (Dist < SplashRadius):
            Self.Damage * Pow(1.0 - Dist / SplashRadius, SplashFalloffExponent)
        else:
            0.0

    SeenIn<private>(Seen:[]entity, E:entity)<reads><decides>:void =
        first (X : Seen, X = E) { X }

    DeliveryName<private>()<reads>:string =
        if (Delivery = projectile_delivery.AssignedOnSpawn):
            "assigned-on-spawn"
        else if (Delivery = projectile_delivery.AssignedOnArrival):
            "assigned-on-arrival"
        else:
            "spatial"

    ConfigureMovement<private>(Movement:keyframed_movement_component):void =
        Forward := Entity.GetGlobalTransform().Rotation.GetForwardAxis()
        Delta := keyframed_movement_delta{
            Transform := (LUF:)transform{
                Translation := Forward * Speed * MaxLifetime,
                Rotation    := (LUF:)IdentityRotation(),
                Scale       := (LUF:)vector3{}
            },
            Duration := MaxLifetime,
            Easing   := linear_easing_function{}
        }
        Movement.SetKeyframes(array{Delta}, oneshot_keyframed_movement_playback_mode{})

    HitListenLoop<private>()<suspends>:void =
        if (Mesh := Entity.GetComponent[mesh_component]):
            loop:
                HitEntity:entity = Mesh.EntityEnteredEvent.Await()
                if (DebugOn[DebugHits]):
                    Print("projectile: overlap at {ToString(HitEntity.GetGlobalTransform().Translation)}")
                if:
                    Char := FindFortCharacterAt[HitEntity]
                    Target := Char.GetAgent[]
                    TargetCharEntity := Char.GetEntity[]
                    NotSource[TargetCharEntity]
                    GatesAllow[HitEntity]
                then:
                    if (DebugOn[DebugHits]):
                        Print("projectile: hit agent character, applying {Self.Damage}")
                    ApplyDamage(Target, Char, Self.Damage)
                    ApplySplash(Entity.GetGlobalTransform().Translation, option{TargetCharEntity})
                    HitEvent.Signal()
                    break
                else if (Health := FindDamageableHealthAt[HitEntity], GatesAllow[HitEntity]):
                    if (DebugOn[DebugHits]):
                        Print("projectile: hit tagged health entity, applying {Self.Damage}")
                    Health.TakeDamage(Self.Damage, SourceOpt())
                    ApplySplash(Entity.GetGlobalTransform().Translation, option{Health.Entity})
                    HitEvent.Signal()
                    break
                else if (not PassThroughNonAgents?):
                    if (DebugOn[DebugHits]):
                        Print("projectile: hit non-target, stopping (PassThroughNonAgents off)")
                    ApplySplash(Entity.GetGlobalTransform().Translation, false)
                    HitEvent.Signal()
                    break
                else:
                    if (DebugOn[DebugHits]):
                        Print("projectile: ignored (own source, gate veto, or untagged) - passing through")
        else:
            if (DebugOn[DebugHits]):
                Print("projectile: NO mesh_component - cannot detect hits")
            Sleep(Inf)

    # The hit entity may be a child of the one carrying fort_character, so walk self plus ancestors.
    FindFortCharacterAt<private>(E:entity)<transacts><decides>:fort_character =
        ContainersList := array{E} + (for (A : E.FindAncestorEntities(entity)) { A })
        Found := for:
            C : ContainersList
            Comp : C.GetComponents()
            FC := fort_character[Comp]
        do:
            FC
        Found[0]

    # Same self-or-ancestor walk; the collision mesh may be a child of the entity carrying tag and health.
    FindDamageableHealthAt<private>(E:entity)<transacts><decides>:entity_health_component =
        DamageableTags.Length > 0
        ContainersList := array{E} + (for (A : E.FindAncestorEntities(entity)) { A })
        Found := for:
            C : ContainersList
            C.ContainsAnyTag[DamageableTags]
            H := C.GetComponent[entity_health_component]
        do:
            H
        Found[0]

    GatesAllow<private>(HitEntity:entity)<transacts><decides>:void =
        for (G : HitGates):
            G.Allows[Entity, HitEntity]

    NotSource<private>(TargetCharEntity:entity)<reads><decides>:void =
        if (S := SourceCharEntity?):
            not (S = TargetCharEntity)

    ApplyDamage<private>(Target:agent, Char:fort_character, Amount:float):void =
        Source := SourceOpt()
        Instigator:?game_action_instigator = if (AttributeToInstigator?) then option{SourceInstigator[]} else false
        DamageApplier.Apply(Source, Target, Char, Amount, Instigator)

    SourceOpt<private>():?agent =
        if (S := Entity.GetSource[]) then option{S} else false

    SourceInstigator<private>()<decides><transacts>:game_action_instigator =
        Entity.GetSource[].GetInstigator()

    ResolveSourceCharEntity<private>()<transacts><decides>:entity =
        Source := Entity.GetSource[]
        Char := Source.GetFortCharacter[]
        Char.GetEntity[]
