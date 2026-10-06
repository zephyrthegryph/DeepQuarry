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

CAPABILITIES(/obj/machinery/computer/specops_shuttle)
	interface("SpecopsShuttle", title = "Special Operations Shuttle", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	op("send_to_dock", ui_act("send_to_dock"), then(PROC_REF(ui_act_send_to_dock)))
	op("send_to_station", ui_act("send_to_station"), then(PROC_REF(ui_act_send_to_station)))

/// /obj/machinery/computer/specops_shuttle's window data.
/obj/machinery/computer/specops_shuttle/ui_data(datum/act/eval/A)
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

/obj/machinery/computer/specops_shuttle/proc/ui_act_send_to_dock(datum/act/op/A)
	var/mob/user = A.actor
	specops_send_to_dock(user)
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/computer/specops_shuttle/proc/ui_act_send_to_station(datum/act/op/A)
	var/mob/user = A.actor
	specops_send_to_station(user)
	SStgui.update_uis(src)
	return TRUE
