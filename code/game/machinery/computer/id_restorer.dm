/obj/machinery/computer/id_restorer
	name = "ID restoration terminal"
	desc = "A terminal for restoration of damaged IDs. Mostly used for aftermath of unfortunate falls into vats of acid."
	icon_state = "restorer"
	icon_keyboard = null
	light_color = "#11cc00"
	layer = ABOVE_WINDOW_LAYER
	icon_keyboard = null
	icon = 'icons/obj/machines/id_restorer_vr.dmi'
	density = FALSE
	clicksound = null
	circuit = /obj/item/circuitboard/id_restorer
	flags = WALL_ITEM

	var/icon_success = "restorer_success"
	var/icon_fail = "restorer_fail"

	var/obj/item/card/id/inserted

//Frame
/datum/frame/frame_types/id_restorer
	name = "ID Restoration Terminal"
	frame_class = FRAME_CLASS_DISPLAY
	frame_size = 2
	frame_style = FRAME_STYLE_WALL
	x_offset = 30
	y_offset = 30
	icon_override = 'icons/obj/machines/id_restorer_vr.dmi'

/datum/frame/frame_types/id_restorer/get_icon_state(state)
	return "restorer_b[state]"
