using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }

using { Damage }


# One live enemy as the game controller sees it, whatever drives it.
# Unique so the live list can compare with =.
spawned_enemy<public> := class<abstract><unique>:
    EnemyEntity<public>:entity

    # signals the killing agent (false for non-agent deaths) exactly once, for every death path
    DiedEvent<public>:event(?agent) = event(?agent){}

    var<private> Died<private>:logic = false
    var<private> KillerAgent<private>:?agent = false
    var<private> KillCredit<private>:logic = true

    HasDied<public>()<reads><decides>:void =
        Died?

    # valid once dead; watchers that raced the death read this instead of the event
    GetKiller<public>()<reads>:?agent = KillerAgent

    # Call for leaks and teardown so the death gives no kill rewards.
    SuppressKillCredit<public>():void =
        set KillCredit = false

    HasKillCredit<public>()<reads><decides>:void =
        KillCredit?

    NotifyDied<public>(Killer:?agent):void =
        if (Died?). return
        set Died = true
        set KillerAgent = Killer
        DiedEvent.Signal(Killer)

    # the source's own removal path; must end in NotifyDied one way or another
    Remove<public>():void


# An enemy kind: how it spawns and how it gets removed. Wave data names a
# kind index, so NPC-agent enemies and custom prefabs can mix.
enemy_source<public> := class<abstract>:
    Spawn<public>(Lane:lane_component, Position:(LUF:)vector3)<suspends>:?spawned_enemy


# NPC-agent enemies via spawner devices. Devices round-robin past the
# per-device NPC cap; death arrives on EliminatedEvent, matched to the agent.
npc_enemy_source<public> := class<concrete>(enemy_source):

    @editable
    Spawners<public>:[]npc_spawner_device = array{}

    var<private> Live<private>:[]tuple(agent, spawned_enemy) = array{}
    var<private> RR<private>:int = 0
    var<private> Subscribed<private>:logic = false

    Spawn<override>(Lane:lane_component, Position:(LUF:)vector3)<suspends>:?spawned_enemy =
        EnsureSubscribed()
        MaybeDevice := option{NextSpawner[]}
        if (Device := MaybeDevice?):
            MaybeAgent := Device.SpawnAt(Position)
            if:
                A := MaybeAgent?
                Char := A.GetFortCharacter[]
                CharEntity := Char.GetEntity[]
            then:
                Enemy := npc_spawned_enemy{ EnemyEntity := CharEntity, Agent := A }
                set Live += array{(A, Enemy)}
                option{Enemy}
            else:
                Print("TD: npc spawner returned no agent (per-device NPC cap? no navmesh?)")
                false
        else:
            Print("TD: npc_enemy_source has no spawner devices wired")
            false

    EnsureSubscribed<private>():void =
        if (Subscribed?). return
        set Subscribed = true
        for (S : Spawners):
            S.EliminatedEvent.Subscribe(OnEliminated)

    NextSpawner<private>()<transacts><decides>:npc_spawner_device =
        D := Spawners[Mod[RR, Spawners.Length]]
        set RR += 1
        D

    OnEliminated<private>(Result:device_ai_interaction_result):void =
        if (T := Result.Target?, Found := first (X : Live, X(0) = T) { X }):
            set Live = for (X : Live, not (X(0) = T)) { X }
            Found(1).NotifyDied(Result.Source)


npc_spawned_enemy := class(spawned_enemy):
    Agent:agent

    # kill instead of despawn: DespawnAll is device-wide, and a kill routes death through EliminatedEvent
    Remove<override>():void =
        if (Char := Agent.GetFortCharacter[], Char.IsActive[]):
            Char.SetVulnerability(true)
            Char.Damage(1000000.0)
        else:
            NotifyDied(false)


# Custom enemies: instantiates a prefab under the lane entity. The prefab
# brings its own movement and health; death arrives on DestroyedEvent.
prefab_enemy_source<public> := class<concrete>(enemy_source):

    @editable
    Prefab<public>:concrete_subtype(entity) = entity

    Spawn<override>(Lane:lane_component, Position:(LUF:)vector3)<suspends>:?spawned_enemy =
        E := Prefab{}
        Lane.Entity.AddEntities(array{E})
        E.SetGlobalTransform((LUF:)transform{
            Translation := Position,
            Rotation := IdentityRotation(),
            # keep the prefab-authored scale
            Scale := E.GetGlobalTransform().Scale
        })
        Enemy := prefab_spawned_enemy{ EnemyEntity := E }
        if (Health := E.GetComponent[entity_health_component]):
            spawn { WatchDestroyed(Health, Enemy) }
        else:
            Print("TD: prefab enemy has no entity_health_component - it can never die")
        option{Enemy}

    # per-enemy watcher instead of Subscribe: subscriptions only end via Cancel and would leak a parked task per enemy
    WatchDestroyed<private>(Health:entity_health_component, Enemy:prefab_spawned_enemy)<suspends>:void =
        race:
            block:
                Killer := Health.DestroyedEvent.Await()
                Enemy.NotifyDied(Killer)
            block:
                if (not Enemy.HasDied[]):
                    Enemy.DiedEvent.Await()


prefab_spawned_enemy := class(spawned_enemy):

    Remove<override>():void =
        EnemyEntity.RemoveFromParent()
        NotifyDied(false)
