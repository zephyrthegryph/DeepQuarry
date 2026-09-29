// Special Operations Shuttle console — structured TGUI.

/obj/machinery/computer/specops_shuttle/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/specops_shuttle_open_ui,
	)
	..()

/datum/interaction/machine_hand/specops_shuttle_open_ui
	id = "specops_shuttle_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_ACTOR, /obj/machinery/computer/specops_shuttle/proc/lets_in, "access denied"))
	effect = /obj/machinery/computer/specops_shuttle/proc/interaction_open_ui_impl

/obj/machinery/computer/specops_shuttle/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/computer/specops_shuttle/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

DECLARE_UI_STATE(/obj/machinery/computer/specops_shuttle, GLOB.tgui_default_state)

DECLARE_UI(/obj/machinery/computer/specops_shuttle, "SpecopsShuttle", UI_TITLE("Special Operations Shuttle"))

UI_DATA_REPLACE(/obj/machinery/computer/specops_shuttle, "merge:ui_data_obj_machinery_computer_specops_shuttle{status_message:text,state:text,timeleft:unknown,destination:text}")

/// The computed part of /obj/machinery/computer/specops_shuttle's window data (declared on its UI_DATA row).
/obj/machinery/computer/specops_shuttle/proc/ui_data_obj_machinery_computer_specops_shuttle(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	if(temp)
		data["status_message"] = temp
		return data
	if(GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom)
		data["state"] = "moving"
		data["timeleft"] = GLOB.specops_shuttle_timeleft
		data["destination"] = station_name()
	else if(GLOB.specops_shuttle_at_station)
		data["state"] = "at_station"
	else
		data["state"] = "at_dock"
		data["destination"] = station_name()
	return data

UI_ACT(/obj/machinery/computer/specops_shuttle, "send_to_dock", ui_act_send_to_dock)
UI_ACT_PROC(/obj/machinery/computer/specops_shuttle, ui_act_send_to_dock)
	specops_send_to_dock(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/specops_shuttle, "send_to_station", ui_act_send_to_station)
UI_ACT_PROC(/obj/machinery/computer/specops_shuttle, ui_act_send_to_station)
	specops_send_to_station(ui.user)
	SStgui.update_uis(src)
	return TRUE
