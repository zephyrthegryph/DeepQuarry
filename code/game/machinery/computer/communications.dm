//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

// The communications computer
/obj/machinery/computer/communications
	name = "command and communications console"
	desc = "Used to command and control the station. Can relay long-range communications."
	icon_keyboard = "tech_key"
	icon_screen = "comm"
	light_color = "#0099ff"
	req_access = list(ACCESS_HEADS)
	circuit = /obj/item/circuitboard/communications

	var/datum/tgui_module/communications/communications

/obj/machinery/computer/communications/Initialize(mapload)
	. = ..()
	communications = new(src)

/obj/machinery/computer/communications/emag_act(remaining_charges, mob/user)
	if(!emagged)
		emagged = TRUE
		communications.emagged = TRUE
		to_chat(user, "You scramble the communication routing circuits!")
		return TRUE

/obj/machinery/computer/communications/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/comms_open_ui,
	)
	..()

/// Old attack_hand: `if(..()) return; communications.tgui_interact(user)`.
/datum/interaction/machine_hand/comms_open_ui
	id = "comms_open_ui"
	name = "Use"
	effect = /obj/machinery/computer/communications/proc/interaction_open_ui

/obj/machinery/computer/communications/proc/interaction_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	communications.tgui_interact(user)
	return TRUE
