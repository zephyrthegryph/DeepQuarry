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

/obj/machinery/bluespace_beacon/Initialize(mapload)
	. = ..()
	var/turf/T = src.loc
	own_set(src, "Beacon", new /obj/item/radio/beacon)
	Beacon.invisibility = INVISIBILITY_MAXIMUM
	Beacon.forceMove(T)
	om_hook(Beacon, list(/datum/om/event/moved, /datum/om/event/qdeleting), src, PROC_REF(beacon_changed))

	hide(!T.is_plating())


// update the invisibility and icon
/obj/machinery/bluespace_beacon/hide(intact)
	invisibility = intact ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE
	update_icon()

// update the icon_state
/obj/machinery/bluespace_beacon/update_icon()
	var/state="floor_beacon"

	if(invisibility)
		icon_state = "[state]f"
	else
		icon_state = "[state]"

/obj/machinery/bluespace_beacon/machine_step()
	if(!Beacon)
		var/turf/T = src.loc
		own_set(src, "Beacon", new /obj/item/radio/beacon)
		Beacon.invisibility = INVISIBILITY_MAXIMUM
		Beacon.forceMove(T)
		om_hook(Beacon, list(/datum/om/event/moved, /datum/om/event/qdeleting), src, PROC_REF(beacon_changed))
	if(Beacon)
		if(Beacon.loc != src.loc)
			Beacon.forceMove(src.loc)

	update_icon()
	return PROCESS_KILL

/obj/machinery/bluespace_beacon/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	MACHINE_WAKE(src)

/obj/machinery/bluespace_beacon/proc/beacon_changed(datum/source, datum/om/event/event)
	EVENT_HANDLER
	if(source == Beacon && QDELETED(source))
		own_take(src, "Beacon")
	MACHINE_WAKE(src)

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/bluespace_beacon/step_start_condition()
	return TRUE // places its beacon
