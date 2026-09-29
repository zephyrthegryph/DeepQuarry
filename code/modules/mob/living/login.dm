// DeepQuarry preferences + loadout rewrite (commit fd3e36a673). Bay preference_setup framework deleted; /datum/gear loadout catalog relocated from code/modules/client/preference_setup/loadout/ to code/datums/gear/.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/escapeOOC)
DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/lick)
DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/smell)
DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/switch_scaling)
DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/center_offset)
DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/mute_entry)
DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/liquidbelly_visuals)
DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/fix_vore_effects)
DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/vore_transfer_reagents) // If mob doesnt have bellies it cant use this verb for anything
DECLARE_LOGIN_VERB(/mob/living, /mob/living/proc/vore_check_reagents) // If mob doesnt have bellies it cant use this verb for anything
DECLARE_LOGIN_VERB(/mob/living, /mob/proc/nsay_vore)
DECLARE_LOGIN_VERB(/mob/living, /mob/proc/nme_vore)
DECLARE_LOGIN_VERB(/mob/living, /mob/proc/nsay_vore_ch)
DECLARE_LOGIN_VERB(/mob/living, /mob/proc/nme_vore_ch)
DECLARE_LOGIN_VERB(/mob/living, /mob/proc/enter_soulcatcher)

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
	refresh_hud()

	return .
