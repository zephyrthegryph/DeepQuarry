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
OM_FIELD(/obj/machinery/transportpod, in_transit, FALSE, CHANGE_MACHINE_SETTINGS)
DECLARE_PERIODIC_WHILE(/obj/machinery/transportpod, MACHINE_PIPELINE, "in_transit")

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3).
/datum/om/relation/slot/occupant/transportpod
	holder = /obj/machinery/transportpod
	slot_id = OCCUPANT_SLOT_TRANSPORTPOD
	name = "transport pod"

/// The occupant (cap_occupant(), library/occupant.dm): anyone gets in by walking into it (Bumped()), dragging a person
/// onto it or the Menu's "Climb in"; "Eject" (or moving inside) lets them out. Entering asks for launch confirmation.
/obj/machinery/transportpod/capabilities()
	. = ..()
	. += cap_occupant(OCCUPANT_SLOT_TRANSPORTPOD, types = /mob/living/carbon/human, on_enter = PROC_REF(occupant_entered), self_name = "Enter Pod", eject_name = "Eject Pod")

/obj/machinery/transportpod/draw(datum/look/look)
	..()
	look.state(occupant_of(src) ? "borg_pod_closed" : "borg_pod_opened")

/// Launches once an occupant confirms (in_transit, the declaration above).
/obj/machinery/transportpod/machine_step()
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
	src.forceMove(L)
	play_sfx(src, SFX_EFFECTS_EXPLOSION, volume = 0)
	after(src, 2, PROC_REF(arrive_unload))

/obj/machinery/transportpod/proc/arrive_unload()
	occupant_eject(src)
	after(src, 2, TYPE_PROC_REF(/datum, om_qdel_self))

/obj/machinery/transportpod/relaymove(mob/user as mob)
	if(user.stat)
		return
	occupant_eject(src, user)

/obj/machinery/transportpod/Bumped(mob/living/O)
	if(!istype(O) || O.incapacitated()) //aint no sleepy people getting in here
		return
	occupant_enter(src, O, O)

/// cap_occupant()'s on_enter: whoever got in (by any path) is asked to confirm the launch.
/obj/machinery/transportpod/proc/occupant_entered(mob/living/O)
	open_request(src, /datum/prompt/yes_no, PROC_REF(launch_answered), answerer = O, title = "Transport Pod", question = "Are you sure you're ready to launch?", ask_flags = ASK_INSIDE, timeout = 0)

/obj/machinery/transportpod/proc/launch_answered(datum/act/request/A)
	if(A.answer && A.answer.answer_value)
		set_in_transit(TRUE)
		playsound(src, HYPERSPACE_WARMUP)
	else
		occupant_eject(src)
	return 1

/obj/machinery/transportpod/proc/build()
	for(var/x = limit_x-2, x <= limit_x, x++)
		for(var/y = limit_y-2, y <= limit_y, y++)
			var/current_cell = locate(x, y, 1)
			var/turf/T = get_turf(current_cell)
			if(!current_cell)
				continue
			T.ChangeTurf(/turf/unsimulated/floor/shuttle_ceiling)
