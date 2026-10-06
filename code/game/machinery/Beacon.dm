/obj/machinery/bluespace_beacon
	icon = 'icons/obj/objects.dmi'
	icon_state = "floor_beaconf"
	name = "Bluespace Gigabeacon"
	desc = "A device that draws power from bluespace and creates a permanent tracking beacon."
	level = 1		// underfloor
	layer = UNDER_JUNK_LAYER
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 0
	var/obj/item/radio/beacon/Beacon

CAPABILITIES(/obj/machinery/bluespace_beacon)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	owns_one(nameof(Beacon), /obj/item/radio/beacon)

/obj/machinery/bluespace_beacon/Initialize(mapload)
	. = ..()
	var/turf/T = src.loc
	rel_set(src, nameof(Beacon), new /obj/item/radio/beacon)
	Beacon.invisibility = INVISIBILITY_MAXIMUM
	Beacon.forceMove(T)
	observe(Beacon, /datum/notice/moved, src, then(PROC_REF(beacon_changed)))
	observe(Beacon, /datum/notice/qdeleting, src, then(PROC_REF(beacon_changed)))

	hide(!T.is_plating())


// update the invisibility and icon
/obj/machinery/bluespace_beacon/hide(intact)
	invisibility = intact ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE
	changed(src)

/// The look (the draw sweep: from its template).
/obj/machinery/bluespace_beacon/draw(datum/look/look)
	..()
	look.state("floor_beacon[invisibility ? "f" : ""]")

/obj/machinery/bluespace_beacon/proc/work_step(datum/act/timer/A)
	if(!Beacon)
		var/turf/T = src.loc
		rel_set(src, nameof(Beacon), new /obj/item/radio/beacon)
		Beacon.invisibility = INVISIBILITY_MAXIMUM
		Beacon.forceMove(T)
		observe(Beacon, /datum/notice/moved, src, then(PROC_REF(beacon_changed)))
		observe(Beacon, /datum/notice/qdeleting, src, then(PROC_REF(beacon_changed)))
	if(Beacon)
		if(Beacon.loc != src.loc)
			Beacon.forceMove(src.loc)

	return PROCESS_KILL

/obj/machinery/bluespace_beacon/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	work_start(src)

/obj/machinery/bluespace_beacon/proc/beacon_changed(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	if(source == Beacon && QDELETED(source))
		own_take(src, nameof(Beacon))
	work_start(src)

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/bluespace_beacon/step_start_condition()
	return TRUE // places its beacon
