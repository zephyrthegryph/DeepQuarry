/datum/tgui_module/shutoff_monitor
	name = "Shutoff Valve Monitoring"
	tgui_id = "ShutoffMonitor"

UI_ACT(/datum/tgui_module/shutoff_monitor, "toggle_enable", ui_act_toggle_enable, UI_ARG_REF("valve", null, /obj/machinery/atmospherics/valve/shutoff))
UI_ACT_PROC(/datum/tgui_module/shutoff_monitor, ui_act_toggle_enable)
	var/obj/machinery/atmospherics/valve/shutoff/S = params["valve"]
	if(!istype(S))
		return FALSE
	S.close_on_leaks = !S.close_on_leaks
	return TRUE

UI_ACT(/datum/tgui_module/shutoff_monitor, "toggle_open", ui_act_toggle_open, UI_ARG_REF("valve", null, /obj/machinery/atmospherics/valve/shutoff))
UI_ACT_PROC(/datum/tgui_module/shutoff_monitor, ui_act_toggle_open)
	var/obj/machinery/atmospherics/valve/shutoff/S = params["valve"]
	if(!istype(S))
		return FALSE
	if(S.open)
		S.close()
	else
		S.open()
	return TRUE

UI_DATA_REPLACE(/datum/tgui_module/shutoff_monitor, "merge:ui_data_datum_tgui_module_shutoff_monitor{valves:list}")

/// The computed part of /datum/tgui_module/shutoff_monitor's window data (declared on its UI_DATA row).
/datum/tgui_module/shutoff_monitor/proc/ui_data_datum_tgui_module_shutoff_monitor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/list/valves = list()

	for(var/obj/machinery/atmospherics/valve/shutoff/S in REGISTRY_MEMBERS(REGISTRY_SHUTOFF_VALVES))
		valves.Add(list(list(
			"name" = S.name,
			"enabled" = S.close_on_leaks,
			"open" = S.open,
			"x" = S.x,
			"y" = S.y,
			"z" = S.z,
			"ref" = "\ref[S]"
		)))

	data["valves"] = valves
	return data

/datum/tgui_module/shutoff_monitor/ntos
	ntos = TRUE
