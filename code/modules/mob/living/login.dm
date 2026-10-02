// DeepQuarry preferences + loadout rewrite (commit fd3e36a673). Bay preference_setup framework deleted; /datum/gear loadout catalog relocated from code/modules/client/preference_setup/loadout/ to code/datums/gear/.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/// Verbs a living mob has once a player has had it (applied at Login; an NPC-only mob never carries them).
/mob/living/type_verbs()
	. = ..()
	. += type_verb(/mob/living/proc/escapeOOC, login = TRUE)
	. += type_verb(/mob/living/proc/lick, login = TRUE)
	. += type_verb(/mob/living/proc/smell, login = TRUE)
	. += type_verb(/mob/living/proc/switch_scaling, login = TRUE)
	. += type_verb(/mob/living/proc/center_offset, login = TRUE)
	. += type_verb(/mob/living/proc/mute_entry, login = TRUE)
	. += type_verb(/mob/living/proc/liquidbelly_visuals, login = TRUE)
	. += type_verb(/mob/living/proc/fix_vore_effects, login = TRUE)
	. += type_verb(/mob/living/proc/vore_transfer_reagents, login = TRUE) // If mob doesnt have bellies it cant use this verb for anything
	. += type_verb(/mob/living/proc/vore_check_reagents, login = TRUE) // If mob doesnt have bellies it cant use this verb for anything
	. += type_verb(/mob/proc/nsay_vore, login = TRUE)
	. += type_verb(/mob/proc/nme_vore, login = TRUE)
	. += type_verb(/mob/proc/nsay_vore_ch, login = TRUE)
	. += type_verb(/mob/proc/nme_vore_ch, login = TRUE)
	. += type_verb(/mob/proc/enter_soulcatcher, login = TRUE)

/mob/living/Login()
	..()
	on_client_changed("login")
	//Mind updates
	mind_initialize()	//updates the mind (or creates and initializes one if one doesn't exist)
	mind.active = 1		//indicates that the mind is currently synced with a client
	//If they're SSD, remove it so they can wake back up.
	GLOB.antag_service.update_antag_icons(mind)
	client.screen |= GLOB.global_hud.darksight
	client.images |= dsoverlay

	if(ai_brain && !ai_brain.autopilot)
		ai_brain.go_sleep()
		to_chat(src,span_notice("Mob AI disabled while you are controlling the mob."))

	add_character_setup_button()

	// Vore stuff

	if(!no_vore)
		om_grant(src, GRANT_VERB, /mob/living/proc/vorebelly_printout, src)
		if(!vorePanel)
			add_vore_panel_button()


	if(!length(voice_sounds_list))
		if(client.prefs.read_preference(/datum/preference/text/human/voice_sound))
			var/prefsound = client.prefs.read_preference(/datum/preference/text/human/voice_sound)
			voice_sounds_list = get_talk_sound(prefsound)
		else
			voice_sounds_list = DEFAULT_TALK_SOUNDS
	resize(size_multiplier, animate = FALSE, uncapped = has_large_resize_bounds(), ignore_prefs = TRUE, aura_animation = FALSE)
	init_vore(TRUE)

	return .
