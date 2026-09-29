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

/datum/tgui_module/shutoff_monitor/tgui_data(mob/user)
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
