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

CAPABILITIES(/obj/machinery/computer/rcon)
	owns_one(nameof(rcon), starts = /datum/tgui_module/rcon)
	op("open_ui", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(TYPE_PROC_REF(/atom, op_open_ui)))

// Proc: ui_interact()
// Description: Uses dark magic (TGUI) to render this machine's UI
/obj/machinery/computer/rcon/ui_redirect(mob/user)
	return rcon

/obj/machinery/computer/rcon/draw(datum/look/look)
	..()
	look.overlay("ai-fixer-empty", when = operable())
