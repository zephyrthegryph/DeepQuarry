/obj/machinery/gizmo
	var/hum = 0

OM_FIELD(/obj/machinery/gizmo, on, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/machinery/gizmo, MACHINE_PIPELINE, "on")

/obj/item/other
	var/n = 0

OM_FIELD(/obj/item/other, going, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/other, PERIODIC_SLOW, "going")

/obj/item/other/periodic_step()
	n++
	return PROCESS_KILL
