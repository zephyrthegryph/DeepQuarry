// The ballistic transportation pod: one person climbs in, confirms, and the pod launches them to a random point of the station, blowing a hole on
// arrival. ONE CAPABILITIES list says what it is: an occupant pod (occupant_pod(): the drag, the menu's "Move Inside" and "Eject", the occupant
// moving out), the launch question asked of whoever gets in, and the launch itself while the occupant's answer stands. Walking into it climbs in
// (the bump action's notice).

/obj/machinery/transportpod
	name = "Ballistic Transportation Pod"
	desc = "A fast transit ballistic pod used to get from one place to the next. Batteries not included!"
	icon = 'icons/obj/structures.dmi'
	icon_state = "borg_pod_opened"

	density = TRUE //thicc
	anchored = TRUE
	use_power = USE_POWER_OFF

	var/xc = list(137, 209, 163, 110, 95, 60, 129, 201) // List of x values on the map to go to.
	var/yc = list(134, 99, 169, 120, 96, 122, 189, 219) // List of y values on the map to go to.

	var/limit_x = 3
	var/limit_y = 3
	/// TRUE from the occupant's confirmation until the pod launches.
	var/in_transit = FALSE

TRACKED(/obj/machinery/transportpod, in_transit)

CAPABILITIES(/obj/machinery/transportpod)
	occupant_pod(OCCUPANT_SLOT_TRANSPORTPOD)
	on_notice(/datum/notice/pod_entered, then(PROC_REF(ask_to_launch)))
	on_notice(/datum/notice/bumped, then(PROC_REF(walked_into)))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(launch)), when = nameof(in_transit))

/obj/machinery/transportpod/draw(datum/look/look)
	..()
	look.state(occupant_of(src) ? "borg_pod_closed" : "borg_pod_opened")

/// Whoever got in (by any path) is asked to confirm the launch.
/obj/machinery/transportpod/proc/ask_to_launch(datum/act/A)
	var/datum/notice/pod_entered/N = A
	open_request(src, /datum/prompt/yes_no, PROC_REF(launch_answered), answerer = N.occupant, title = "Transport Pod", question = "Are you sure you're ready to launch?", ask_flags = ASK_INSIDE, timeout = 0)

/obj/machinery/transportpod/proc/launch_answered(datum/act/request/A)
	if(A.answer && A.answer.value)
		set_in_transit(TRUE)
		playsound(src, HYPERSPACE_WARMUP)
	else
		occupant_eject(src)
	return 1

/// The occupant confirmed: the pod picks a destination, clears its landing site and flies.
/obj/machinery/transportpod/proc/launch(datum/act/timer/A)
	set_in_transit(FALSE)
	if(!occupant_of(src)) // they got out before launch
		return
	var/locNum = rand(1, 8) //pick a random location
	var/turf/L = locate(xc[locNum], yc[locNum], 1) // Pairs the X and Y to get an actual location.
	limit_x = xc[locNum]+1
	limit_y = yc[locNum]+1
	build()
	after(src, 2 SECONDS, PROC_REF(arrive), with = list(L)) //Give explosion time so the pod itself doesn't go boom

/obj/machinery/transportpod/proc/arrive(turf/L)
	if(L)
		src.forceMove(L)
	play_sfx(src, SFX_EFFECTS_EXPLOSION, volume = 0)
	after(src, 0.2 SECONDS, PROC_REF(arrive_unload))

/obj/machinery/transportpod/proc/arrive_unload()
	occupant_eject(src)
	after(src, 0.2 SECONDS, TYPE_PROC_REF(/datum, om_qdel_self))

/// Someone walked into the pod: they climb in (aint no sleepy people getting in here).
/obj/machinery/transportpod/proc/walked_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/mob/living/O = N.bumper
	if(!istype(O) || O.incapacitated())
		return
	occupant_enter(src, O, O)

/obj/machinery/transportpod/proc/build()
	for(var/x = limit_x-2, x <= limit_x, x++)
		for(var/y = limit_y-2, y <= limit_y, y++)
			var/current_cell = locate(x, y, 1)
			var/turf/T = get_turf(current_cell)
			if(!current_cell)
				continue
			T.ChangeTurf(/turf/unsimulated/floor/shuttle_ceiling)
