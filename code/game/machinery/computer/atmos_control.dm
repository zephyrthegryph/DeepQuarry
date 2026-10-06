/obj/item/circuitboard/atmoscontrol
	name = "\improper Central Atmospherics Computer Circuitboard"
	build_path = /obj/machinery/computer/atmoscontrol

/obj/machinery/computer/atmoscontrol
	name = "\improper Central Atmospherics Computer"
	desc = "Control the station's atmospheric systems from afar! Certified atmospherics technicians only."
	icon_keyboard = "generic_key"
	icon_screen = "comm_logs"
	light_color = "#00b000"
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/atmoscontrol
	req_access = list(ACCESS_CE)
	var/list/monitored_alarm_ids = null
	var/datum/tgui_module/atmos_control/atmos_control

MSG_DEF(atmoscontrol/emagged, "You cause the screen to flash as you gain full control.", "%U% does something to %T%, causing the screen to flash!")

/// The console is its controller's window (ui_redirect()): a hand or a silicon's link opens it; an emag gives anyone full control of every alarm.
CAPABILITIES(/obj/machinery/computer/atmoscontrol)
	owns_one(nameof(atmos_control), /datum/tgui_module/atmos_control)
	op("use", inputs(hand(), remote()), label("Use"), wait(0), needs(req(PROC_REF(console_works), because = MSG(machine/inoperable))), then(PROC_REF(open_console)))
	emag(then(PROC_REF(emag_screen)), say = MSG(atmoscontrol/emagged), powered = FALSE)
	op("atmoscontrol_robot_use", remote(), priority(OP_PRIORITY_NORMAL + 1), when(req_actor_kind(/mob/living/silicon/robot)), label("Use"), then(PROC_REF(atmoscontrol_robot_use)))

/obj/machinery/computer/atmoscontrol/laptop //[TO DO] Change name to PCU and update mapdata to include replacement computers
	name = "\improper Atmospherics PCU"
	desc = "A personal computer unit. It seems to have only the Atmosphereics Control program installed."
	icon_screen = "pcu_atmo"
	icon_state = "pcu_engi"
	icon_keyboard = "pcu_key"
	density = FALSE
	light_color = "#00cc00"
	density = 0

/obj/machinery/computer/atmoscontrol/proc/console_works(datum/act/A)
	return operable()

/obj/machinery/computer/atmoscontrol/proc/open_console(datum/act/op/A)
	add_fingerprint(A.actor)
	tgui_interact(A.actor)
	return OP_OK

/// The emag gives the console's controller full control (made now when nobody opened the console yet).
/obj/machinery/computer/atmoscontrol/proc/emag_screen(datum/act/op/A)
	var/datum/tgui_module/atmos_control/controller = ui_redirect(A.actor)
	controller.emagged = TRUE
	return OP_OK

/obj/machinery/computer/atmoscontrol/ui_redirect(mob/user)
	if(!atmos_control)
		rel_set(src, nameof(atmos_control), new /datum/tgui_module/atmos_control(src, req_access, req_one_access, monitored_alarm_ids))
	return atmos_control


// A cyborg with access interfaces remotely as the AI does (FALSE: the robot adapter's default); without it, only by hand from next to it.

/obj/machinery/computer/atmoscontrol/proc/atmoscontrol_robot_use(datum/act/op/A)
	var/mob/user = A.actor
	if(allowed(user))
		return OP_DECLINE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE
