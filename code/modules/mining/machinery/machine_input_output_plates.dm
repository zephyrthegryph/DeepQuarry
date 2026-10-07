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

/// Starts this ore machine's work (started_work()).
/obj/machinery/mineral/proc/wake_mining()
	work_start(src)

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
