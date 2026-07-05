using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


effect_polarity<public> := enum:
    Buff
    Debuff
    Neutral


effect_polarity_component<public> := class<final_super>(component):

    @editable
    Polarity<public>:effect_polarity = effect_polarity.Neutral

    var<private> RegisteredWith<private>:?buff_ui_component = false

    OnAddedToScene<override>():void =
        (super:)OnAddedToScene()
        if (Bin := option{first{E:Entity.FindAncestorComponents(buff_ui_component)}}?):
            Bin.RegisterEffect(Entity, Polarity)
            set RegisteredWith = option{Bin}

    OnRemovingFromScene<override>():void =
        (super:)OnRemovingFromScene()
        if (Bin := RegisteredWith?):
            Bin.UnregisterEffect(Entity)
            set RegisteredWith = false
