/**********************Input and output plates**************************/

/obj/machinery/mineral/input
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x2"
	name = "Input area"
	density = FALSE
	anchored = TRUE

/obj/machinery/mineral/input/Initialize(mapload)
	. = ..()
	icon_state = "blank"

/obj/machinery/mineral/output
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	name = "Output area"
	density = FALSE
	anchored = TRUE

/obj/machinery/mineral/output/Initialize(mapload)
	. = ..()
	icon_state = "blank"

// Ore machines work only while their input plate has something on it (roadmap S5): each watches
// its input turf and wakes when an item or an ore box arrives; with nothing left to do it sleeps.

/// Wakes this ore machine on whichever lane it runs (fast mode or the machine pipeline).
/obj/machinery/mineral/proc/wake_mining()
	if(speed_process)
		// ALLOW(sys_periodic_toggle): lane dispatch for an input-arrival wake: speed_process picks which lane runs the step, the reason to start is the arrival event, not a state change
		om_task_periodic(src, PERIODIC_FAST)
	else
		// ALLOW(sys_periodic_toggle): same lane dispatch (slow lane) for the input-arrival wake
		MACHINE_WAKE(src)

/// Starts watching `plate`'s turf for arrivals.
/obj/machinery/mineral/proc/watch_input(obj/machinery/mineral/plate)
	if(plate?.loc)
		observe(plate.loc, /datum/notice/atom_entered, src, then(PROC_REF(on_input_entered)))

/obj/machinery/mineral/proc/unwatch_input(obj/machinery/mineral/plate)
	if(plate?.loc)
		unobserve(plate.loc, /datum/notice/atom_entered, src)

/obj/machinery/mineral/proc/on_input_entered(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/atom_entered/event = A
	var/atom/movable/arrived = event.arrived
	if(isitem(arrived) || istype(arrived, /obj/structure/ore_box))
		wake_mining()
