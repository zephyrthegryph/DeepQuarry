// RCON REMOTE CONTROL CONSOLE
//
// Last Change 1.1.2015 by Atlantis
//
// Allows remote operation of electrical systems on station (SMESs and Breaker Boxes)

/obj/machinery/computer/rcon
	name = "\improper RCON console"
	desc = "Console used to remotely control electrical machinery on the station."
	icon_keyboard = "power_key"
	icon_screen = "ai-fixer"
	light_color = "#a97faa"
	circuit = /obj/item/circuitboard/rcon_console
	req_one_access = list(ACCESS_ENGINE)
	var/current_tag = null
	var/datum/tgui_module/rcon/rcon

DECLARE_DEFAULT_CHILD(/obj/machinery/computer/rcon, "rcon", /datum/tgui_module/rcon)


/obj/machinery/computer/rcon/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

// Proc: ui_interact()
// Description: Uses dark magic (TGUI) to render this machine's UI
/obj/machinery/computer/rcon/tgui_interact(mob/user, datum/tgui/ui)
	rcon.tgui_interact(user, ui)

/obj/machinery/computer/rcon/update_icon()
	..()
	if(operable())
		add_overlay("ai-fixer-empty")
	else
		cut_overlay("ai-fixer-empty")
