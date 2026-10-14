
/obj/machinery/vent/appearance_overlays()
	var/list/parts = list()
	parts += "on"
	icon_state = "vent"
	if(welded)
		playsound(src, 'sound/weld.ogg', 50)
	last_state = "on"
	return parts

/obj/machinery/quiet/appearance_overlays()
	var/list/parts = list()
	parts += "idle"
	return parts

DECLARE_APPEARANCE_PROC(/obj/machinery/custom, TYPE_PROC_REF(/obj/machinery/custom, custom_look), list())

/obj/machinery/custom/proc/custom_look()
	icon_state = "custom"
	on = TRUE
	return list()
