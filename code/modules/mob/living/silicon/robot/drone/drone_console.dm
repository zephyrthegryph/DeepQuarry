/obj/machinery/computer/drone_control
	name = "Maintenance Drone Control"
	desc = "Used to monitor the station's drone population and the assembler that services them."
	icon_keyboard = "power_key"
	icon_screen = "generic"
	req_access = list(ACCESS_ENGINE_EQUIP)
	circuit = /obj/item/circuitboard/drone_control

	//Used when pinging drones.
	var/drone_call_area = "Engineering"
	//Used to enable or disable drone fabrication.
	var/obj/machinery/drone_fabricator/dronefab

/obj/machinery/computer/drone_control/tgui_status(mob/user)
	if(!allowed(user))
		return STATUS_CLOSE
	return ..()

/obj/machinery/computer/drone_control/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

DECLARE_UI(/obj/machinery/computer/drone_control, "DroneConsole")

UI_DATA_REPLACE(/obj/machinery/computer/drone_control, "fabricator=dronefab", "merge:ui_data_obj_machinery_computer_drone_control{drones:list,fabPower:num,areas:list,selected_area:text}")

/// The computed part of /obj/machinery/computer/drone_control's window data (declared on its UI_DATA row).
/obj/machinery/computer/drone_control/proc/ui_data_obj_machinery_computer_drone_control(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/drones = list()
	for(var/mob/living/silicon/robot/drone/D in REGISTRY_MEMBERS(REGISTRY_MOBS))
		// multiz lol
		if(!(D.z in using_map.get_map_levels(z, TRUE, 0)))
			continue
		// multiz lol
		if(D.foreign_droid)
			continue

		drones.Add(list(list(
			"name" = D.real_name,
			"active" = D.stat != 2,
			"charge" = D.cell.charge,
			"maxCharge" = D.cell.maxcharge,
			"loc" = "[get_area(D)]",
			"ref" = "\ref[D]",
		)))
	data["drones"] = drones

	data["fabPower"] = dronefab?.produce_drones

	var/list/areas = list()
	for(var/area in GLOB.tagger_locations)
		areas += area
	data["areas"] = areas
	data["selected_area"] = "[drone_call_area]"

	return data

UI_ACT(/obj/machinery/computer/drone_control, "set_dcall_area", ui_act_set_dcall_area, UI_ARG_VALUE("area"))
UI_ACT_PROC(/obj/machinery/computer/drone_control, ui_act_set_dcall_area)
	var/t_area = params["area"]
	if(!t_area || !(t_area in GLOB.tagger_locations))
		return

	drone_call_area = t_area
	to_chat(ui.user, span_notice("You set the area selector to [drone_call_area]."))

UI_ACT(/obj/machinery/computer/drone_control, "ping", ui_act_ping)
UI_ACT_PROC(/obj/machinery/computer/drone_control, ui_act_ping)
	to_chat(ui.user, span_notice("You issue a maintenance request for all active drones, highlighting [drone_call_area]."))
	for(var/mob/living/silicon/robot/drone/D in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(D.stat == 0)
			to_chat(D, "-- Maintenance drone presence requested in: [drone_call_area].")

UI_ACT(/obj/machinery/computer/drone_control, "resync", ui_act_resync, UI_ARG_REF("ref", null, /mob/living/silicon/robot/drone))
UI_ACT_PROC(/obj/machinery/computer/drone_control, ui_act_resync)
	var/mob/living/silicon/robot/drone/D = params["ref"]

	if(istype(D) && D.stat != 2)
		to_chat(ui.user, span_danger("You issue a law synchronization directive for the drone."))
		D.law_resync()

UI_ACT(/obj/machinery/computer/drone_control, "shutdown", ui_act_shutdown, UI_ARG_REF("ref", null, /mob/living/silicon/robot/drone))
UI_ACT_PROC(/obj/machinery/computer/drone_control, ui_act_shutdown)
	var/mob/living/silicon/robot/drone/D = params["ref"]

	if(istype(D) && D.stat != 2)
		to_chat(ui.user, span_danger("You issue a kill command for the unfortunate drone."))
		message_admins("[key_name_admin(ui.user)] issued kill order for drone [key_name_admin(D)] from control console.")
		log_game("[key_name(ui.user)] issued kill order for [key_name(src)] from control console.")
		D.shut_down()

UI_ACT(/obj/machinery/computer/drone_control, "search_fab", ui_act_search_fab)
UI_ACT_PROC(/obj/machinery/computer/drone_control, ui_act_search_fab)
	if(dronefab)
		return

	for(var/obj/machinery/drone_fabricator/fab in oview(3,src))
		if(fab.has_stat(NOPOWER))
			continue

		rel_set(src, "dronefab", fab)
		to_chat(ui.user, span_notice("Drone fabricator located."))
		return

	to_chat(ui.user, span_danger("Unable to locate drone fabricator."))

UI_ACT(/obj/machinery/computer/drone_control, "toggle_fab", ui_act_toggle_fab)
UI_ACT_PROC(/obj/machinery/computer/drone_control, ui_act_toggle_fab)
	if(!dronefab)
		return

	if(get_dist(src,dronefab) > 3)
		rel_clear(src, "dronefab")
		to_chat(ui.user, span_danger("Unable to locate drone fabricator."))
		return

	dronefab.produce_drones = !dronefab.produce_drones
	to_chat(ui.user, span_notice("You [dronefab.produce_drones ? "enable" : "disable"] drone production in the nearby fabricator."))

