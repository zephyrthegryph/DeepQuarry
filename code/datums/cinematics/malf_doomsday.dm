/// A malfunctioning AI has activated the doomsday device and wiped the station!
/datum/cinematic/malf
	intro_time = 7.6 SECONDS

/datum/cinematic/malf/play_cinematic()
	flick("intro_malf", screen)
	// The intro runs its course, then the blast (after(), no sleep: S10b).
	after(src, intro_time, PROC_REF(play_malf_blast))

/// The second half of the doomsday cinematic, after the intro animation.
/datum/cinematic/malf/proc/play_malf_blast()
	flick("station_explode_fade_red", screen)
	play_cinematic_sound(sound('sound/effects/explosionfar.ogg'))
	special_callback?.Invoke()
	screen.icon_state = "summary_malf"
