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

/obj/machinery/computer/atmoscontrol/laptop //[TO DO] Change name to PCU and update mapdata to include replacement computers
	name = "\improper Atmospherics PCU"
	desc = "A personal computer unit. It seems to have only the Atmosphereics Control program installed."
	icon_screen = "pcu_atmo"
	icon_state = "pcu_engi"
	icon_keyboard = "pcu_key"
	density = FALSE
	light_color = "#00cc00"
	density = 0

/obj/machinery/computer/atmoscontrol
	silicon_use = SILICON_USE_UI

/obj/machinery/computer/atmoscontrol/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

DECLARE_EMAG(/obj/machinery/computer/atmoscontrol, PROC_REF(on_emag), null, null)
/obj/machinery/computer/atmoscontrol/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	act_message(user, src, MSG_SELF(span_warning("You cause the screen to flash as you gain full control.")), \
		MSG_OTHERS(span_warning("%U% does something %T%, causing the screen to flash!")), \
		MSG_BLIND("You hear an electronic warble."))
	atmos_control.emagged = 1
	return 1

/obj/machinery/computer/atmoscontrol/tgui_interact(mob/user)
	if(!atmos_control)
		own_set(src, "atmos_control", new /datum/tgui_module/atmos_control(src, req_access, req_one_access, monitored_alarm_ids))
	atmos_control.tgui_interact(user)

