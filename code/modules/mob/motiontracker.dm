/mob/proc/has_motiontracking() // USE THIS
	return is_motion_tracking

// Subscribing and unsubscribingto the motion tracker subsystem
/mob/proc/motiontracker_subscribe()
	if(!is_motion_tracking)
		is_motion_tracking = TRUE
		wants_to_see_motion_echos = TRUE
		om_hook(GLOB.motiontracker_service, /datum/om/event/movable_motiontracker, src, PROC_REF(handle_motion_tracking))
		om_grant(src, GRANT_VERB, /mob/proc/toggle_motion_echo_vis, src)

/mob/proc/motiontracker_unsubscribe(destroying = FALSE)
	if(is_motion_tracking)
		is_motion_tracking = FALSE
		om_unhook(GLOB.motiontracker_service, /datum/om/event/movable_motiontracker, src)
		om_revoke(src, GRANT_VERB, /mob/proc/toggle_motion_echo_vis, src)

/mob/living/carbon/human/motiontracker_unsubscribe(destroying = FALSE)
	// Block unsub if our species has vibration senses
	if(!destroying && species?.has_vibration_sense)
		return
	. = ..()

// For /datum/om/event/movable_motiontracker
/mob/proc/handle_motion_tracking(datum/source, datum/om/event/movable_motiontracker/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	var/RW = event.handle
	var/turf/T = event.echo_turf_location
	if(!client || !wants_to_see_motion_echos || stat || is_deaf())
		return
	var/atom/echo_source = om_resolve(RW)
	if(!echo_source || get_dist(src,echo_source) > GLOB.motiontracker_service.max_range || src.z != echo_source.z)
		return
	// Blind characters see all pings around them. Otherwise remove the closest, or any we can see. Pings behind walls or in the dark are always visible
	if(!is_blind() && (get_dist(src,echo_source) < GLOB.motiontracker_service.min_range || (T.get_lumcount() >= 0.20 && can_see(src, T, 7)) ))
		return
	var/echos = 1
	if(prob(30))
		echos = rand(1,3)
	GLOB.motiontracker_service.queue_echo(get_turf(src),T,echos,client ? om_handle(client) : null)

/mob/proc/toggle_motion_echo_vis()
	set name = "Toggle Vibration Senses"
	set desc = "Toggle the visibility of pings revealed by vibration senses or motion trackers."
	set category = "Abilities.General"

	wants_to_see_motion_echos = !wants_to_see_motion_echos
	to_chat(src,"You will [wants_to_see_motion_echos ? "now" : "no longer"] see echos")
