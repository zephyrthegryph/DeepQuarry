/obj/machinery/transportpod
	name = "Ballistic Transportation Pod"
	desc = "A fast transit ballistic pod used to get from one place to the next. Batteries not included!"
	icon = 'icons/obj/structures.dmi'
	icon_state = "borg_pod_opened"

	density = TRUE //thicc
	anchored = TRUE
	use_power = USE_POWER_OFF

	var/in_transit = 0
	var/mob/occupant = null

	var/xc = list(137, 209, 163, 110, 95, 60, 129, 201) // List of x values on the map to go to.
	var/yc = list(134, 99, 169, 120, 96, 122, 189, 219) // List of y values on the map to go to.

	var/limit_x = 3
	var/limit_y = 3

/obj/machinery/transportpod/process()
	if(occupant)
		if(in_transit)
			var/locNum = rand(1, 8) //pick a random location
			var/turf/L = locate(xc[locNum], yc[locNum], 1) // Pairs the X and Y to get an actual location.
			limit_x = xc[locNum]+1
			limit_y = yc[locNum]+1
			build()
			sleep(20) //Give explosion time so the pod itself doesn't go boom
			src.forceMove(L)
			playsound(src, pick('sound/effects/Explosion1.ogg', 'sound/effects/Explosion2.ogg', 'sound/effects/Explosion3.ogg', 'sound/effects/Explosion4.ogg'))
			in_transit = 0
			sleep(2)
			go_out()
			sleep(2)
			qdel(src)

/obj/machinery/transportpod/relaymove(mob/user as mob)
	if(user.stat)
		return
	go_out()
	return

/obj/machinery/transportpod/update_icon()
	..()
	if(occupant)
		icon_state = "borg_pod_closed"
	else
		icon_state = "borg_pod_opened"

/obj/machinery/transportpod/Bumped(mob/living/O)
	go_in(O)

/obj/machinery/transportpod/proc/go_in(mob/living/carbon/human/O)
	if(occupant)
		return

	if(O.incapacitated()) //aint no sleepy people getting in here
		return

	add_fingerprint(O)
	O.forceMove(src)
	occupant = O
	update_icon()
	if(tgui_alert(O, "Are you sure you're ready to launch?", "Transport Pod", list("Yes", "No")) == "Yes")
		in_transit = 1
		playsound(src, HYPERSPACE_WARMUP)
	else
		go_out()
	return 1

/obj/machinery/transportpod/proc/go_out()
	if(!occupant)
		return
	occupant.forceMove(src.loc)
	occupant = null
	update_icon()

/obj/machinery/transportpod/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_verb/transportpod_eject,
		/datum/interaction/machine_verb/transportpod_enter,
	)
	..()

/datum/interaction/machine_verb/transportpod_eject
	id = "transportpod_eject"
	name = "Eject Pod"
	category = INTERACTION_CAT_EJECT
	effect = /obj/machinery/transportpod/proc/interaction_eject

/obj/machinery/transportpod/proc/interaction_eject(mob/user, obj/item/held, datum/interaction/interaction)
	go_out()
	add_fingerprint(user)
	return TRUE

/datum/interaction/machine_verb/transportpod_enter
	id = "transportpod_enter"
	name = "Enter Pod"
	effect = /obj/machinery/transportpod/proc/interaction_enter

/obj/machinery/transportpod/proc/interaction_enter(mob/user, obj/item/held, datum/interaction/interaction)
	go_in(user)
	return TRUE

/obj/machinery/transportpod/proc/build()
	for(var/x = limit_x-2, x <= limit_x, x++)
		for(var/y = limit_y-2, y <= limit_y, y++)
			var/current_cell = locate(x, y, 1)
			var/turf/T = get_turf(current_cell)
			if(!current_cell)
				continue
			T.ChangeTurf(/turf/unsimulated/floor/shuttle_ceiling)
