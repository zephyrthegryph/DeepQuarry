/obj/machinery/computer/mecha
	name = "Exosuit Control"
	desc = "Used to track exosuits, as well as view their logs and activate EMP beacons."
	icon_keyboard = "rd_key"
	icon_screen = "mecha"
	light_color = "#a97faa"
	req_access = list(ACCESS_ROBOTICS)
	circuit = /obj/item/circuitboard/mecha_control
	var/list/located
	var/screen = 0
	var/list/stored_data

/// The window data.
/obj/machinery/computer/mecha/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["stored_data"] = stored_data
	var/list/computed = ui_data_obj_machinery_computer_mecha(A.actor, null, null)
	for(var/key in computed)
		data[key] = computed[key]
	return data

/// The computed part of the console's window data (ui_data())
/obj/machinery/computer/mecha/proc/ui_data_obj_machinery_computer_mecha(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/beacons = list()
	for(var/obj/item/mecha_parts/mecha_tracking/TR in world)
		var/list/tr_data = TR.tgui_data(user)
		if(tr_data)
			beacons.Add(list(tr_data))
	data["beacons"] = beacons

	LAZYINITLIST(stored_data)

	return data

// The console's window: a beacon's message is asked in the op (asks()), its handler sends the answer.
CAPABILITIES(/obj/machinery/computer/mecha)
	interface("MechaControlConsole")
	without("ui_open")
	op("send_message", ui_act("send_message", arg("mt", schema_ref(/obj/item/mecha_parts/mecha_tracking))), needs(req(PROC_REF(beacon_named), silent = TRUE)),
		asks(/datum/prompt/text/mecha_tracker_message, step = "message"), then(PROC_REF(ui_act_send_message)))
	op("shock", ui_act("shock", arg("mt", schema_ref(/obj/item/mecha_parts/mecha_tracking))), then(PROC_REF(ui_act_shock)))
	op("get_log", ui_act("get_log", arg("mt", schema_ref(/obj/item/mecha_parts/mecha_tracking))), then(PROC_REF(ui_act_get_log)))
	op("clear_log", ui_act(), then(PROC_REF(ui_act_clear_log)))

/// A beacon button names a beacon.
/obj/machinery/computer/mecha/proc/beacon_named(datum/act/op/A)
	return (!isnull(A.args["mt"])) ? null : MSG(req_failed)

/obj/machinery/computer/mecha/proc/ui_act_send_message(datum/act/op/A, obj/item/mecha_parts/mecha_tracking/mt)
	if(!istype(mt))
		return TRUE
	var/message = A.step_value("message")
	var/obj/mecha/M = mt.in_mecha()
	if(message && M)
		M.occupant_message(message)
	return TRUE

/obj/machinery/computer/mecha/proc/ui_act_shock(datum/act/op/A, obj/item/mecha_parts/mecha_tracking/mt)
	if(istype(mt))
		mt.shock()
	return TRUE

/obj/machinery/computer/mecha/proc/ui_act_get_log(datum/act/op/A, obj/item/mecha_parts/mecha_tracking/mt)
	if(istype(mt))
		stored_data = mt.get_mecha_log()
	return TRUE

/obj/machinery/computer/mecha/proc/ui_act_clear_log(datum/act/op/A)
	stored_data = null
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
	data["ref"] = REF(src)
	data["charge"] = M.get_charge()
	data["name"] = M.name
	data["health"] = M.get_integrity()
	data["maxHealth"] = M.max_integrity
	data["cell"] = M.cell
	if(M.cell)
		data["cellCharge"] = M.cell.charge
		data["cellMaxCharge"] = M.cell.maxcharge
	data["airtank"] = M.return_pressure()
	data["pilot"] = M?.slot_item_real(MECHA_SLOT_PILOT)
	data["location"] = get_area(M)
	data["active"] = M.selected
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
