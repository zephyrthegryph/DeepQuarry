#define METEOR_DELAY 6000

/datum/game_mode/meteor
	name = "Meteor"
	round_description = "The space station has been stuck in a major meteor shower."
	extended_round_description = "The station is on an unavoidable collision course with an asteroid field. The station will be continuously slammed with meteors, venting hallways, rooms, and ultimately destroying a majority of the basic life functions of the entire structure. Coordinate with your fellow crew members to survive the inevitable destruction of the station and get back home in one piece!"
	config_tag = "meteor"
	required_players = 0
	votable = 0
	deny_respawn = 0
	/// REACT_AT token for the next meteor wave; null when none is armed.
	var/tmp/wave_timer

/datum/game_mode/meteor/New()
	..()
	wave_timer = REACT_REARM(src, wave_timer, METEOR_DELAY)

/datum/game_mode/meteor/process()
	// Meteor waves are driven by wave_timer/on_react(); nothing left to poll here.
	return

/datum/game_mode/meteor/on_react(reason, source, source_kind)
	. = ..()
	if(!(reason & REACT_REASON_TIMER) || source != wave_timer)
		return
	wave_timer = null
	wave_timer = REACT_REARM(src, wave_timer, world.time + GLOB.meteor_wave_delay)
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(spawn_meteors), 6, GLOB.meteors_normal)

/datum/game_mode/meteor/declare_completion()
	var/text
	var/survivors = 0
	for(var/mob/living/player in GLOB.player_list)
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
