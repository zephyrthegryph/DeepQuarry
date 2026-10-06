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

/// An empty hand (or a silicon's interface, through attack_hand) opens the console; cap_access() makes the op need a
/// credential for its req_access (the held card, a worn ID, a silicon's own access), so a refused click says why.
/obj/machinery/computer/drone_control/capabilities()
	. = ..()
	. += cap_op("Open console", TYPE_PROC_REF(/atom, interaction_open_ui_fingerprint), using = EMPTY_HAND, key = "open_console", entry = INTERACTION_ENTRY_HAND)
	. += cap_access(ops = "open_console")

/// An open window closes when its user loses the credential (the same providers as the op).
/obj/machinery/computer/drone_control/tgui_status(mob/user)
	if(!access_allowed(src, user, user?.get_active_hand()))
		return STATUS_CLOSE
	return ..()

CAPABILITIES(/obj/machinery/computer/drone_control)
	interface("DroneConsole")
	without("ui_open")
	op("set_dcall_area", ui_act("set_dcall_area", arg("area")), then(PROC_REF(ui_act_set_dcall_area)))
	op("ping", ui_act("ping"), then(PROC_REF(ui_act_ping)))
	op("resync", ui_act("resync", arg("ref", schema_ref(/mob/living/silicon/robot/drone))), then(PROC_REF(ui_act_resync)))
	op("shutdown", ui_act("shutdown", arg("ref", schema_ref(/mob/living/silicon/robot/drone))), then(PROC_REF(ui_act_shutdown)))
	op("search_fab", ui_act("search_fab"), then(PROC_REF(ui_act_search_fab)))
	op("toggle_fab", ui_act("toggle_fab"), then(PROC_REF(ui_act_toggle_fab)))

/obj/machinery/computer/drone_control/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["fabricator"] = dronefab
	var/list/merged_1 = ui_data_obj_machinery_computer_drone_control(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/computer/drone_control's window data.
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

/obj/machinery/computer/drone_control/proc/ui_act_set_dcall_area(datum/act/op/A, area)
	var/mob/user = A.actor
	var/t_area = area
	if(!t_area || !(t_area in GLOB.tagger_locations))
		return

	drone_call_area = t_area
	to_chat(user, span_notice("You set the area selector to [drone_call_area]."))

/obj/machinery/computer/drone_control/proc/ui_act_ping(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You issue a maintenance request for all active drones, highlighting [drone_call_area]."))
	for(var/mob/living/silicon/robot/drone/D in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(D.stat == 0)
			to_chat(D, "-- Maintenance drone presence requested in: [drone_call_area].")

/obj/machinery/computer/drone_control/proc/ui_act_resync(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/drone/D = ref

	if(istype(D) && D.stat != 2)
		to_chat(user, span_danger("You issue a law synchronization directive for the drone."))
		D.law_resync()

/obj/machinery/computer/drone_control/proc/ui_act_shutdown(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/drone/D = ref

	if(istype(D) && D.stat != 2)
		to_chat(user, span_danger("You issue a kill command for the unfortunate drone."))
		message_admins("[key_name_admin(user)] issued kill order for drone [key_name_admin(D)] from control console.")
		log_game("[key_name(user)] issued kill order for [key_name(src)] from control console.")
		D.shut_down()

/obj/machinery/computer/drone_control/proc/ui_act_search_fab(datum/act/op/A)
	var/mob/user = A.actor
	if(dronefab)
		return

	for(var/obj/machinery/drone_fabricator/fab in oview(3,src))
		if(fab.has_stat(NOPOWER))
			continue

		rel_set(src, nameof(/obj/machinery/computer/drone_control::dronefab), fab)
		to_chat(user, span_notice("Drone fabricator located."))
		return

	to_chat(user, span_danger("Unable to locate drone fabricator."))

/obj/machinery/computer/drone_control/proc/ui_act_toggle_fab(datum/act/op/A)
	var/mob/user = A.actor
	if(!dronefab)
		return

	if(get_dist(src,dronefab) > 3)
		rel_clear(src, nameof(/obj/machinery/computer/drone_control::dronefab))
		to_chat(user, span_danger("Unable to locate drone fabricator."))
		return

	dronefab.produce_drones = !dronefab.produce_drones
	to_chat(user, span_notice("You [dronefab.produce_drones ? "enable" : "disable"] drone production in the nearby fabricator."))

