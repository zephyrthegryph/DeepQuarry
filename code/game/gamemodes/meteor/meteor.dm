#define METEOR_DELAY 6000

/datum/game_mode/meteor
	name = "Meteor"
	round_description = "The space station has been stuck in a major meteor shower."
	extended_round_description = "The station is on an unavoidable collision course with an asteroid field. The station will be continuously slammed with meteors, venting hallways, rooms, and ultimately destroying a majority of the basic life functions of the entire structure. Coordinate with your fellow crew members to survive the inevitable destruction of the station and get back home in one piece!"
	config_tag = "meteor"
	required_players = 0
	votable = 0
	deny_respawn = 0

/// The waves have begun (METEOR_DELAY into the round); they then repeat every GLOB.meteor_wave_delay.
/datum/game_mode/meteor/var/meteor_waves = FALSE
TRACKED_BRIDGED(/datum/game_mode/meteor, meteor_waves, CHANGE_DATUM_A)
CAPABILITIES(/datum/game_mode/meteor)
	every(PROC_REF(meteor_wave_delay), then(PROC_REF(meteor_wave)), when = nameof(meteor_waves))

/datum/game_mode/meteor/post_setup()
	. = ..()
	after(src, max(METEOR_DELAY - world.time, 0), PROC_REF(start_meteor_waves))

/// after() callback: the first wave, then the declared repeat carries on.
/datum/game_mode/meteor/proc/start_meteor_waves()
	spawn_meteors(6, GLOB.meteors_normal)
	set_meteor_waves(TRUE)

/// every() interval: read each time the wave re-arms.
/datum/game_mode/meteor/proc/meteor_wave_delay(datum/act/A)
	return GLOB.meteor_wave_delay

/// The mode's periodic work is the waves alone (no latespawn), on their own timer.
/datum/game_mode/meteor/mode_step(datum/act/timer/A)
	return

/// every(): one wave of meteors every GLOB.meteor_wave_delay while the waves run.
/datum/game_mode/meteor/proc/meteor_wave(datum/act/timer/A)
	spawn_meteors(6, GLOB.meteors_normal)

/datum/game_mode/meteor/declare_completion()
	var/text
	var/survivors = 0
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(player.stat != DEAD)
			var/turf/location = get_turf(player.loc)
			if(!location)	continue
			switch(location.loc.type)
				if( /area/shuttle/escape/centcom )
					text += "<br>"
					text += span_bold(span_normal("[player.real_name] escaped on the emergency shuttle"))
				if( /area/shuttle/escape_pod1/centcom, /area/shuttle/escape_pod2/centcom, /area/shuttle/escape_pod3/centcom, /area/shuttle/escape_pod5/centcom )
					text += "<br>"
					text += span_normal("[player.real_name] escaped in a life pod.")
				else
					text += "<br>"
					text += span_small("[player.real_name] survived but is stranded without any hope of rescue.")
			survivors++

	if(survivors)
		to_chat(world, span_world("The following survived the meteor storm") + ":[text]")
	else
		to_chat(world, span_boldannounce("Nobody survived the meteor storm!"))

	feedback_set_details("round_end_result","end - evacuation")
	feedback_set("round_end_result",survivors)

	return ..()

#undef METEOR_DELAY
