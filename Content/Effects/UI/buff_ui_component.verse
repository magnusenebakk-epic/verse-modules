using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }


buff_ui_component<public> := class<final_super>(component):

    var<private> UIByPlayer<private>:[player]buff_ui = map{}
    var<private> ManagerSubs<private>:[]Concurrency.subscription_task(player) = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Mgr := Entity.GetPlayerManager[]):
            set ManagerSubs += array{
                Mgr.PlayerReadyEvent.Subscribe(OnPlayerReady),
                Mgr.PlayerLeavingEvent.Subscribe(OnPlayerLeaving)
            }
        if (Player := Entity.GetPlayerOf[]):
            EnsureUI(Player)

    OnEndSimulation<override>():void =
        (super:)OnEndSimulation()
        for (S : ManagerSubs):
            S.Cancel()
        set ManagerSubs = array{}
        for (P -> PlayerUI : UIByPlayer):
            PlayerUI.Hide()
        set UIByPlayer = map{}

    RegisterEffect<public>(EffectE:entity, Polarity:effect_polarity):void =
        for (P -> PlayerUI : UIByPlayer):
            PlayerUI.AddRow(EffectE, Polarity)

    UnregisterEffect<public>(EffectE:entity):void =
        for (P -> PlayerUI : UIByPlayer):
            PlayerUI.RemoveRow(EffectE)

    OnPlayerReady<private>(Player:player):void =
        if (MyPlayer := Entity.GetPlayerOf[], MyPlayer = Player):
            EnsureUI(Player)

    OnPlayerLeaving<private>(Player:player):void =
        if (PlayerUI := UIByPlayer[Player]):
            PlayerUI.Hide()
            set UIByPlayer = UIByPlayer.RemoveKey(Player)

    EnsureUI<private>(Player:player):void =
        if (Existing := UIByPlayer[Player]):
            return
        PlayerUI := MakeBuffUI(Player)
        PlayerUI.Initialize()
        PlayerUI.Show()
        if (set UIByPlayer[Player] = PlayerUI) {}
