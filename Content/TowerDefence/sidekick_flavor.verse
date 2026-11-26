using { /Fortnite.com/AI }
using { /Fortnite.com/Characters }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /Verse.org/Concurrency }
using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

using { Abilities }


# Sidekick dressing for this game's NPC enemies: drives mood and reactions
# off existing events. Game-specific kit, not TD framework; no-op on non-sidekicks.
sidekick_flavor_kit_component<public> := class<final_super>(component):

    # Below this fraction of max health the mood locks to Worried; 0.0 disables.
    @editable
    var WorriedHealthFraction<public>:float = 0.3

    # Play the Attack reaction on every successful ability fire.
    @editable
    var PlaySwingReactions<public>:logic = true

    # Play the HitReact reaction whenever the NPC takes damage.
    @editable
    var PlayHitReactions<public>:logic = true

    # last applied override so recomputes only touch the engine on real changes
    var<private> AppliedMood<private>:?sidekick_mood = false

    OnSimulate<override>()<suspends>:void =
        if:
            CharE := Entity.GetParent[]
            Info := CharE.GetComponent[td_enemy_info_component]
            Char := OwningCharacter[]
        then:
            if (SK := CharE.GetComponent[npc_sidekick_component]):
                sync:
                    RunMood(SK, Info, Char)
                    RunHits(SK, Info, Char)
                    RunSwings(SK, CharE)
            else:
                Print("TD: sidekick_flavor found no npc_sidekick_component on this NPC")

    # the kit is a direct child of the NPC char entity; the character lives in the parent's components
    OwningCharacter<private>()<transacts><decides>:fort_character =
        CharE := Entity.GetParent[]
        Chars := for (Comp : CharE.GetComponents(), FC := fort_character[Comp]) { FC }
        Chars[0]

    RunMood<private>(SK:npc_sidekick_component, Info:td_enemy_info_component, Char:fort_character)<suspends>:void =
        ApplyMood(SK, Info, Char)
        loop:
            Info.EngagedChangedEvent.Await()
            ApplyMood(SK, Info, Char)

    # every damage instance: flinch, then re-check the worried threshold
    RunHits<private>(SK:npc_sidekick_component, Info:td_enemy_info_component, Char:fort_character)<suspends>:void =
        loop:
            Result := Char.DamagedEvent().Await()
            if (PlayHitReactions?):
                option{SK.PlayReaction[sidekick_reaction.HitReact]}
            ApplyMood(SK, Info, Char)

    # ability use is the swing signal (once per fire); sibling kits spawn this pass, so retry a while
    RunSwings<private>(SK:npc_sidekick_component, CharE:entity)<suspends>:void =
        if (PlaySwingReactions?):
            var Found:?ability_hub_component = false
            var Tries:int = 0
            loop:
                set Found = option{first{D : CharE.FindDescendantComponents(ability_hub_component)}}
                if (Found? or Tries >= 8):
                    break
                set Tries += 1
                Sleep(0.25)
            if (Driver := Found?):
                loop:
                    Driver.UseBeganEvent.Await()
                    option{SK.PlayReaction[sidekick_reaction.Attack]}
            else:
                Sleep(Inf)
        else:
            Sleep(Inf)

    # priority: hurt, then fighting, then automatic; clearing the override returns control to the engine
    ApplyMood<private>(SK:npc_sidekick_component, Info:td_enemy_info_component, Char:fort_character):void =
        Hurt := if:
            WorriedHealthFraction > 0.0
            Char.GetHealth() < WorriedHealthFraction * Char.GetMaxHealth()
        then:
            true
        else:
            false
        NewMood:?sidekick_mood = if (Hurt?):
            option{sidekick_mood.Worried}
        else if (Info.GetEngaged()?):
            option{sidekick_mood.Combat}
        else:
            false
        if (not (NewMood = AppliedMood)):
            set AppliedMood = NewMood
            set SK.MoodOverride = NewMood
