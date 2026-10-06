/// Simple, base cinematic for all animations based around a nuke detonating.
/datum/cinematic/nuke
	/// If set, this is the summary screen that pops up after the nuke is done.
	var/after_nuke_summary_state
	intro_time = 3.5 SECONDS

/datum/cinematic/nuke/play_cinematic()
	flick("intro_nuke", screen)
	// The intro runs its course, then the blast (after(), no sleep: S10b).
	after(src, intro_time, PROC_REF(play_nuke_blast))

/// The second half of the nuke cinematic, after the intro animation.
/datum/cinematic/nuke/proc/play_nuke_blast()
	play_nuke_effect()
	if(special_callback)
		special_callback.Invoke()
	if(after_nuke_summary_state)
		screen.icon_state = after_nuke_summary_state

/// Specific effects for each type of cinematics goes here.
/datum/cinematic/nuke/proc/play_nuke_effect()
	return

/// The syndicate nuclear bomb was activated, and destroyed the station!
/datum/cinematic/nuke/ops_victory
	after_nuke_summary_state = "summary_nukewin"

/datum/cinematic/nuke/ops_victory/play_nuke_effect()
	flick("station_explode_fade_red", screen)
	play_cinematic_sound(sound('sound/effects/explosionfar.ogg'))

/// The syndicate nuclear bomb was activated, but just barely missed the station!
/datum/cinematic/nuke/ops_miss
	after_nuke_summary_state = "summary_nukefail"

/datum/cinematic/nuke/ops_miss/play_nuke_effect()
	flick("station_intact_fade_red", screen)
	play_cinematic_sound(sound('sound/effects/explosionfar.ogg'))

/// The self destruct, or another station-destroying entity like a blob, destroyed the station!
/datum/cinematic/nuke/self_destruct
	after_nuke_summary_state = "summary_selfdes"

/datum/cinematic/nuke/self_destruct/play_nuke_effect()
	flick("station_explode_fade_red", screen)
	play_cinematic_sound(sound('sound/effects/explosionfar.ogg'))

/// The self destruct was activated, yet somehow avoided destroying the station!
/datum/cinematic/nuke/self_destruct_miss
	after_nuke_summary_state = "station_intact"

/datum/cinematic/nuke/self_destruct_miss/play_nuke_effect()
	play_cinematic_sound(sound('sound/effects/explosionfar.ogg'))
	special_callback?.Invoke()

/// The syndicate nuclear bomb was activated, but just missed the station by a whole z-level!
/datum/cinematic/nuke/far_explosion
	cleanup_time = 0 SECONDS
	intro_time = 0

/datum/cinematic/nuke/far_explosion/play_cinematic()
	// This one has no intro sequence.
	// It's actually just a global sound, which makes you wonder why it's a cinematic.
	play_cinematic_sound(sound('sound/effects/explosionfar.ogg'))
	special_callback?.Invoke()

