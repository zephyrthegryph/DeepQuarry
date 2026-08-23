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
	Beacon = new /obj/item/radio/beacon
	Beacon.invisibility = INVISIBILITY_MAXIMUM
	Beacon.loc = T
	RegisterSignals(Beacon, list(COMSIG_MOVABLE_MOVED, COMSIG_QDELETING), PROC_REF(beacon_changed))

	hide(!T.is_plating())

/obj/machinery/bluespace_beacon/Destroy()
	if(Beacon)
		UnregisterSignal(Beacon, list(COMSIG_MOVABLE_MOVED, COMSIG_QDELETING))
		qdel(Beacon)
	. = ..()

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

/obj/machinery/bluespace_beacon/process()
	if(!Beacon)
		var/turf/T = src.loc
		Beacon = new /obj/item/radio/beacon
		Beacon.invisibility = INVISIBILITY_MAXIMUM
		Beacon.loc = T
		RegisterSignals(Beacon, list(COMSIG_MOVABLE_MOVED, COMSIG_QDELETING), PROC_REF(beacon_changed))
	if(Beacon)
		if(Beacon.loc != src.loc)
			Beacon.loc = src.loc

	update_icon()
	return PROCESS_KILL

/obj/machinery/bluespace_beacon/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	START_MACHINE_PROCESSING(src)

/obj/machinery/bluespace_beacon/proc/beacon_changed(datum/source)
	SIGNAL_HANDLER
	if(source == Beacon && QDELETED(source))
		Beacon = null
	START_MACHINE_PROCESSING(src)
