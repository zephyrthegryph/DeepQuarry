/obj/machinery/artifact_scanpad
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "Anomaly Scanner Pad"
	desc = "Place things here for scanning."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "tele0"
	anchored = TRUE
	density = FALSE
	circuit = /obj/item/circuitboard/artifact_scanpad

CAPABILITIES(/obj/machinery/artifact_scanpad)
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with and redraws for them
/obj/machinery/artifact_scanpad/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_icon()
