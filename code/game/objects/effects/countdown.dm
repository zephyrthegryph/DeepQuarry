/obj/effect/countdown
	name = "countdown"
	desc = "We're leaving together\n\
		But still it's farewell\n\
		And maybe we'll come back\n\
		To Earth, who can tell?"

	invisibility = INVISIBILITY_OBSERVER
	anchored = TRUE
	plane = PLANE_GHOSTS
	color = "#ff0000"
	var/text_size = 3 // Larger values clip when the displayed text is larger than 2 digits
	var/displayed_text
	var/atom/attached_to

/// Ticks its display every fast tick while started.
OM_FIELD(/obj/effect/countdown, started, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/effect/countdown, PERIODIC_FAST, "started")

/obj/effect/countdown/Initialize(mapload)
	. = ..()
	attach(loc)

/obj/effect/countdown/examine(mob/user)
	. = ..()
	. += "This countdown is displaying: [displayed_text]."

/obj/effect/countdown/proc/attach(atom/A)
	rel_set(src, nameof(attached_to), A)
	var/turf/loc_turf = get_turf(A)
	if(!loc_turf)
		om_hook(attached_to, /datum/om/event/moved, src, PROC_REF(retry_attach))
	else
		forceMove(loc_turf)

/obj/effect/countdown/proc/retry_attach(datum/source, datum/om/event/moved/event)
	EVENT_HANDLER

	var/turf/loc_turf = get_turf(attached_to)
	if(!loc_turf)
		return
	forceMove(loc_turf)
	om_unhook(attached_to, /datum/om/event/moved, src)

/obj/effect/countdown/proc/start()
	set_started(TRUE)

/obj/effect/countdown/proc/stop()
	if(started)
		maptext = null
		set_started(FALSE)

/obj/effect/countdown/proc/get_value()
	// Get the value from our atom
	return

/obj/effect/countdown/periodic_step()
	if(!attached_to || QDELETED(attached_to))
		qdel(src)
		return
	forceMove(get_turf(attached_to))
	var/new_val = get_value()
	if(new_val == displayed_text)
		return
	displayed_text = new_val

	if(displayed_text)
		maptext = MAPTEXT("[displayed_text]")
	else
		maptext = null

/obj/effect/countdown/singularity_pull(atom/singularity, current_size)
	return

/obj/effect/countdown/singularity_act()
	return

/obj/effect/countdown/anomaly
	name = "anomaly countdown"

/obj/effect/countdown/anomaly/get_value()
	var/obj/effect/anomaly/A = attached_to
	if(!istype(A))
		return
	else if(A.immortal)
		stop()
	else
		var/time_left = max(0, (A.death_time - world.time)/10)
		return round(time_left)
