/obj/machinery/computer/mecha
	name = "Exosuit Control"
	desc = "Used to track exosuits, as well as view their logs and activate EMP beacons."
	icon_keyboard = "rd_key"
	icon_screen = "mecha"
	req_access = list(ACCESS_ROBOTICS)
	circuit = VARIANT(/obj/item/circuitboard/mecha_control)
	var/list/located
	var/screen = 0
	var/list/stored_data

/// The window data: the beacons that sit in an exosuit and the log being read.
/obj/machinery/computer/mecha/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["stored_data"] = stored_data || list()
	var/list/beacons = list()
	for(var/obj/item/mecha_parts/mecha_tracking/TR in listed_beacons())
		var/list/tr_data = TR.tgui_data(A.actor)
		if(tr_data)
			beacons.Add(list(tr_data))
	data["beacons"] = beacons
	return data

/// The beacons the window lists: every tracking beacon that sits in an exosuit.
/obj/machinery/computer/mecha/proc/listed_beacons()
	// A beacon in an exosuit sits in its contents: the exosuits are a registry, so the console no longer walks every object in the world
	// (about 3 ms a build).
	var/list/listed = list()
	for(var/obj/mecha/M as anything in REGISTRY_MEMBERS(REGISTRY_MECHAS))
		for(var/obj/item/mecha_parts/mecha_tracking/TR as anything in contents_of(M, /obj/item/mecha_parts/mecha_tracking))
			listed += TR
	return listed

// The console's window: a beacon's message is asked in the op (asks()), its handler sends the answer.
CAPABILITIES(/obj/machinery/computer/mecha)
	configure(light_glow(color = "#a97faa"))
	interface("MechaControlConsole")
	ui_shape(beacons = list_of(row(ref = num(), name = schema_text(), health = num(), maxHealth = num(), cell = bool(), cellCharge = num(), cellMaxCharge = num(), airtank = num(), pilot = nullable(schema_text()), location = schema_text(), active = nullable(schema_text()), cargoUsed = num(), cargoMax = num())), stored_data = list_of(row(time = schema_text(), year = int(), message = schema_text())))
	without("ui_open")
	op("send_message", ui_act("send_message", arg("mt", schema_text(32))), needs(req(PROC_REF(beacon_named), silent = TRUE)),
		asks(/datum/prompt/text/mecha_tracker_message, step = "message"), then(PROC_REF(ui_act_send_message)))
	op("shock", ui_act("shock", arg("mt", schema_text(32))), then(PROC_REF(ui_act_shock)))
	op("get_log", ui_act("get_log", arg("mt", schema_text(32))), then(PROC_REF(ui_act_get_log)))
	op("clear_log", ui_act(), then(PROC_REF(ui_act_clear_log)))

/// A beacon button names a beacon.
/obj/machinery/computer/mecha/proc/beacon_named(datum/act/op/A)
	return beacon_of(A.args["mt"]) ? null : MSG(req_failed)

/// The beacon a handle names: one the window lists.
/obj/machinery/computer/mecha/proc/beacon_of(handle)
	return ui_member(handle, listed_beacons(), /obj/item/mecha_parts/mecha_tracking)

/obj/machinery/computer/mecha/proc/ui_act_send_message(datum/act/op/A, mt)
	var/obj/item/mecha_parts/mecha_tracking/tracker = beacon_of(mt)
	if(!tracker)
		return TRUE
	var/message = A.step_value("message")
	var/obj/mecha/M = tracker.in_mecha()
	if(message && M)
		M.occupant_message(message)
	return TRUE

/obj/machinery/computer/mecha/proc/ui_act_shock(datum/act/op/A, mt)
	var/obj/item/mecha_parts/mecha_tracking/tracker = beacon_of(mt)
	if(tracker)
		tracker.shock()
	return TRUE

/obj/machinery/computer/mecha/proc/ui_act_get_log(datum/act/op/A, mt)
	var/obj/item/mecha_parts/mecha_tracking/tracker = beacon_of(mt)
	if(tracker)
		set_stored_data(tracker.get_mecha_log())
	return TRUE

/obj/machinery/computer/mecha/proc/ui_act_clear_log(datum/act/op/A)
	set_stored_data(null)
	return OP_OK

/datum/prompt/text/mecha_tracker_message
	title = "Transmit message"
	question = "Input message"
	default = ""
	timeout = 0

/obj/item/mecha_parts/mecha_tracking
	name = "Exosuit tracking beacon"
	desc = "Device used to transmit exosuit data."
	icon = 'icons/obj/device.dmi'
	icon_state = "motion2"

/// /obj/item/mecha_parts/mecha_tracking's window data.
/obj/item/mecha_parts/mecha_tracking/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(!in_mecha())
		return FALSE

	var/obj/mecha/M = loc
	data["ref"] = handle_of(src)
	data["name"] = M.name
	data["health"] = M.get_integrity()
	data["maxHealth"] = M.max_integrity
	data["cell"] = !!M.cell
	data["cellCharge"] = M.cell ? M.cell.charge : 0
	data["cellMaxCharge"] = M.cell ? M.cell.maxcharge : 0
	data["airtank"] = M.return_pressure()
	data["pilot"] = M.slot_item_real(MECHA_SLOT_PILOT)?.name
	data["location"] = "[get_area(M)]"
	data["active"] = M.selected?.name
	data["cargoUsed"] = 0
	data["cargoMax"] = 0
	if(istype(M, /obj/mecha/working/ripley))
		var/obj/mecha/working/ripley/RM = M
		data["cargoUsed"] = length(RM.cargo)
		data["cargoMax"] = RM.cargo_capacity

	return data

CAPABILITIES(/obj/item/mecha_parts/mecha_tracking)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(tracking_emp))))

/// An EMP destroys the beacon outright.
/obj/item/mecha_parts/mecha_tracking/proc/tracking_emp(datum/act/hit/emp/A)
	destroyed(src)
	return OP_OK

/obj/item/mecha_parts/mecha_tracking/proc/in_mecha()
	if(istype(loc, /obj/mecha))
		return loc
	return 0

/obj/item/mecha_parts/mecha_tracking/proc/shock()
	var/obj/mecha/M = in_mecha()
	if(M)
		M.emp_act(EMP_HARMLESS)
	spent(src)

/obj/item/mecha_parts/mecha_tracking/proc/get_mecha_log()
	if(!in_mecha())
		return list()
	var/obj/mecha/M = loc
	return M.get_log_tgui()

/obj/item/storage/box/mechabeacons
	name = "Exosuit Tracking Beacons"
	starts_with = list(/obj/item/mecha_parts/mecha_tracking = 7)
