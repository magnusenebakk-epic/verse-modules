using { /Verse.org/SceneGraph }


# Hides the entity's mesh at game start so helper geometry stays visible only while authoring.
hide_mesh_on_simulate_component<public> := class<final_super>(component):

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Mesh := Entity.GetComponent[mesh_component]):
            set Mesh.Visible = false
