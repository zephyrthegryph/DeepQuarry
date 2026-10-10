/mob/proc/has_motiontracking() // USE THIS
	return is_motion_tracking

// Subscribing and unsubscribingto the motion tracker subsystem
/mob/proc/motiontracker_subscribe()
	if(!is_motion_tracking)
		is_motion_tracking = TRUE
		wants_to_see_motion_echos = TRUE
		global.observe(SSmotiontracker, /datum/notice/movable_motiontracker, src, then(PROC_REF(handle_motion_tracking)))
		grant(src, granted_verb(/mob/proc/toggle_motion_echo_vis), src)

/mob/proc/motiontracker_unsubscribe(destroying = FALSE)
	if(is_motion_tracking)
		is_motion_tracking = FALSE
		unobserve(SSmotiontracker, /datum/notice/movable_motiontracker, src)
		revoke(src, granted_verb(/mob/proc/toggle_motion_echo_vis), src)

/mob/living/carbon/human/motiontracker_unsubscribe(destroying = FALSE)
	// Block unsub if our species has vibration senses
	if(!destroying && species?.has_vibration_sense)
		return
	. = ..()

// For /datum/definition_event/movable_motiontracker
/mob/proc/handle_motion_tracking(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	var/datum/notice/movable_motiontracker/event = A
	// The event carries the moving atom itself (emitted synchronously, never stored).
	var/atom/echo_source = event.source_
	var/turf/T = event.echo_turf_location
	if(!client || !wants_to_see_motion_echos || stat || is_deaf())
		return
	if(!isatom(echo_source) || get_dist(src,echo_source) > SSmotiontracker.max_range || src.z != echo_source.z)
		return
	// Blind characters see all pings around them. Otherwise remove the closest, or any we can see. Pings behind walls or in the dark are always visible
	if(!is_blind() && (get_dist(src,echo_source) < SSmotiontracker.min_range || (T.get_lumcount() >= 0.20 && can_see(src, T, 7)) ))
		return
	var/echos = 1
	if(prob(30))
		echos = rand(1,3)
	SSmotiontracker.queue_echo(get_turf(src),T,echos,client)

/mob/proc/toggle_motion_echo_vis()
	set name = "Toggle Vibration Senses"
	set desc = "Toggle the visibility of pings revealed by vibration senses or motion trackers."
	set category = VERB_CAT_ABILITIES_GENERAL

	wants_to_see_motion_echos = !wants_to_see_motion_echos
	to_chat(src,"You will [wants_to_see_motion_echos ? "now" : "no longer"] see echos")
