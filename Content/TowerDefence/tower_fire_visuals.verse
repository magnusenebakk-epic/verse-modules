using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


# Broadcast down the holder's subtree by auto_fire_component after each fire.
# Cooldown is the fired ability's cooldown (0.0 if none) so reactions can time against reload.
fired_event<public> := class(scene_event):
    Cooldown<public>:float = 0.0


# Hides this entity's meshes when the holder fires, shows them just before
# reload ends. Put it on the visible ammo entity (ballista arrow).
reload_visual_component<public> := class<final_super>(component):

    # fraction of the fire cooldown the ammo stays hidden
    @editable
    var HiddenFraction<public>:float = 0.9

    # hide time when the firing ability has no cooldown
    @editable
    var NoCooldownHideTime<public>:float = 0.1

    # OnReceive cannot sleep, so it hands the hide duration to OnSimulate
    HideFor<private>:event(float) = event(float){}

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (F := fired_event[SceneEvent]):
            Duration := if (F.Cooldown > 0.0):
                F.Cooldown * HiddenFraction
            else:
                NoCooldownHideTime
            HideFor.Signal(Duration)
        # never consume: sibling reactors want the event too
        false

    OnSimulate<override>()<suspends>:void =
        if (GetMeshes().Length = 0):
            Print("TD: reload_visual_component sees no mesh_component on its entity or descendants")
        loop:
            Duration := HideFor.Await()
            SetMeshesVisible(false)
            Sleep(Duration)
            SetMeshesVisible(true)

    GetMeshes<private>()<transacts>:[]mesh_component =
        Own := if (M := Entity.GetComponent[mesh_component]) then array{M} else array{}
        Own + (for (M : Entity.FindDescendantComponents(mesh_component)) { M })

    SetMeshesVisible<private>(V:logic):void =
        for (M : GetMeshes()):
            set M.Visible = V
