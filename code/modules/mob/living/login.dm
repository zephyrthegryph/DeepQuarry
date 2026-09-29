// DeepQuarry preferences + loadout rewrite (commit fd3e36a673). Bay preference_setup framework deleted; /datum/gear loadout catalog relocated from code/modules/client/preference_setup/loadout/ to code/datums/gear/.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

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
	om_grant(src, GRANT_VERB, /mob/living/proc/escapeOOC, src)
	om_grant(src, GRANT_VERB, /mob/living/proc/lick, src)
	om_grant(src, GRANT_VERB, /mob/living/proc/smell, src)
	om_grant(src, GRANT_VERB, /mob/living/proc/switch_scaling, src)
	om_grant(src, GRANT_VERB, /mob/living/proc/center_offset, src)
	om_grant(src, GRANT_VERB, /mob/living/proc/mute_entry, src)
	om_grant(src, GRANT_VERB, /mob/living/proc/liquidbelly_visuals, src)
	om_grant(src, GRANT_VERB, /mob/living/proc/fix_vore_effects, src)

	if(!no_vore)
		om_grant(src, GRANT_VERB, /mob/living/proc/vorebelly_printout, src)
		if(!vorePanel)
			add_vore_panel_button()

	om_grant(src, GRANT_VERB, /mob/living/proc/vore_transfer_reagents, src) // If mob doesnt have bellies it cant use this verb for anything
	om_grant(src, GRANT_VERB, /mob/living/proc/vore_check_reagents, src) // If mob doesnt have bellies it cant use this verb for anything
	om_grant(src, GRANT_VERB, /mob/proc/nsay_vore, src)
	om_grant(src, GRANT_VERB, /mob/proc/nme_vore, src)
	om_grant(src, GRANT_VERB, /mob/proc/nsay_vore_ch, src)
	om_grant(src, GRANT_VERB, /mob/proc/nme_vore_ch, src)
	om_grant(src, GRANT_VERB, /mob/proc/enter_soulcatcher, src)

	if(!length(voice_sounds_list))
		if(client.prefs.read_preference(/datum/preference/text/human/voice_sound))
			var/prefsound = client.prefs.read_preference(/datum/preference/text/human/voice_sound)
			voice_sounds_list = get_talk_sound(prefsound)
		else
			voice_sounds_list = DEFAULT_TALK_SOUNDS
	resize(size_multiplier, animate = FALSE, uncapped = has_large_resize_bounds(), ignore_prefs = TRUE, aura_animation = FALSE)
	init_vore(TRUE)
	refresh_hud()

	return .
