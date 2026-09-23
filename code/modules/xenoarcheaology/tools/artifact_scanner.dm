/obj/machinery/artifact_scanpad
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "Anomaly Scanner Pad"
	desc = "Place things here for scanning."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "tele0"
	anchored = TRUE
	density = FALSE
	circuit = /obj/item/circuitboard/artifact_scanpad

/obj/machinery/artifact_scanpad/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/part_replacement,
	)
	..()

/obj/machinery/artifact_scanpad/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_icon()
