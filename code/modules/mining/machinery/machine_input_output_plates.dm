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
		PERIODIC_START(src, PERIODIC_FAST)
	else
		MACHINE_WAKE(src)

/// Starts watching `plate`'s turf for arrivals.
/obj/machinery/mineral/proc/watch_input(obj/machinery/mineral/plate)
	if(plate?.loc)
		RegisterSignal(plate.loc, COMSIG_ATOM_ENTERED, PROC_REF(on_input_entered), override = TRUE)

/obj/machinery/mineral/proc/unwatch_input(obj/machinery/mineral/plate)
	if(plate?.loc)
		UnregisterSignal(plate.loc, COMSIG_ATOM_ENTERED)

/obj/machinery/mineral/proc/on_input_entered(datum/source, atom/movable/arrived)
	SIGNAL_HANDLER
	if(isitem(arrived) || istype(arrived, /obj/structure/ore_box))
		wake_mining()
