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

/obj/machinery/computer/mecha/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

DECLARE_UI(/obj/machinery/computer/mecha, "MechaControlConsole")

UI_DATA(/obj/machinery/computer/mecha, "stored_data:list", "merge:ui_data_obj_machinery_computer_mecha{beacons:list}")

/// The computed part of /obj/machinery/computer/mecha's window data (declared on its UI_DATA row).
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

UI_ACT(/obj/machinery/computer/mecha, "send_message", ui_act_send_message, UI_ARG_REF("mt", null, /obj/item/mecha_parts/mecha_tracking))
UI_ACT_PROC(/obj/machinery/computer/mecha, ui_act_send_message)
	var/obj/item/mecha_parts/mecha_tracking/MT = params["mt"]
	if(istype(MT))
		open_request(src, /datum/prompt/text/mecha_tracker_message, PROC_REF(mecha_message_entered), answerer = ui.user, subject = MT)
	return TRUE

UI_ACT(/obj/machinery/computer/mecha, "shock", ui_act_shock, UI_ARG_REF("mt", null, /obj/item/mecha_parts/mecha_tracking))
UI_ACT_PROC(/obj/machinery/computer/mecha, ui_act_shock)
	var/obj/item/mecha_parts/mecha_tracking/MT = params["mt"]
	if(istype(MT))
		MT.shock()
	return TRUE

UI_ACT(/obj/machinery/computer/mecha, "get_log", ui_act_get_log, UI_ARG_REF("mt", null, /obj/item/mecha_parts/mecha_tracking))
UI_ACT_PROC(/obj/machinery/computer/mecha, ui_act_get_log)
	var/obj/item/mecha_parts/mecha_tracking/MT = params["mt"]
	if(istype(MT))
		stored_data = MT.get_mecha_log()
	return TRUE

CAPABILITIES(/obj/machinery/computer/mecha)
	op("clear_log", ui_act(), then(PROC_REF(ui_act_clear_log)))

/obj/machinery/computer/mecha/proc/ui_act_clear_log(datum/act/op/A)
	stored_data = null
	return OP_OK

/datum/prompt/text/mecha_tracker_message
	title = "Transmit message"
	question = "Input message"
	default = ""
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/mecha_tracker_message/recheck_extra()
	if(QDELETED(owner) || QDELETED(answerer) || QDELETED(subject))
		return "gone"
	if(!isnull(value) && GLOB.tgui_default_state.can_use_topic(owner, answerer) < STATUS_INTERACTIVE)
		return "can't use it"
	return null

/obj/machinery/computer/mecha/proc/mecha_message_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/obj/item/mecha_parts/mecha_tracking/tracker = A.request.subject
	var/obj/mecha/M = tracker.in_mecha()
	if(A.answer.value && M)
		M.occupant_message(A.answer.value)

/obj/item/mecha_parts/mecha_tracking
	name = "Exosuit tracking beacon"
	desc = "Device used to transmit exosuit data."
	icon = 'icons/obj/device.dmi'
	icon_state = "motion2"

/// The computed part of /obj/item/mecha_parts/mecha_tracking's window data (declared on its UI_DATA row).
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

DAMAGE_REACTION(/obj/item/mecha_parts/mecha_tracking, DAMAGE_EMP, TYPE_PROC_REF(/atom, damage_reaction_qdel))

/obj/item/mecha_parts/mecha_tracking/proc/in_mecha()
	if(istype(loc, /obj/mecha))
		return loc
	return 0

/obj/item/mecha_parts/mecha_tracking/proc/shock()
	var/obj/mecha/M = in_mecha()
	if(M)
		M.emp_act(EMP_HARMLESS)
	qdel(src)

/obj/item/mecha_parts/mecha_tracking/proc/get_mecha_log()
	if(!in_mecha())
		return list()
	var/obj/mecha/M = loc
	return M.get_log_tgui()


/obj/item/storage/box/mechabeacons
	name = "Exosuit Tracking Beacons"
	starts_with = list(/obj/item/mecha_parts/mecha_tracking = 7)
