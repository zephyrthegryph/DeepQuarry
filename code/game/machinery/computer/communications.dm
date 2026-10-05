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

MSG_DEF(communications/scrambled, "You scramble the communication routing circuits!", "")

// The command console hosts the communications window (its module); an emag scrambles its routing, which opens the line to the Syndicate
// until someone restores the backup routing from the window.
CAPABILITIES(/obj/machinery/computer/communications)
	owns_one(nameof(communications), /datum/tgui_module/communications, starts = /datum/tgui_module/communications)
	emag(say = MSG(communications/scrambled))
	op("use", hand(), remote(), then(PROC_REF(open_module_window)))

/// The hand's use, or a silicon's: the communications window opens.
/obj/machinery/computer/communications/proc/open_module_window(datum/act/op/A)
	communications.tgui_interact(A.actor)
	return OP_OK

