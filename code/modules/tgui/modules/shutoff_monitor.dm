/datum/tgui_module/shutoff_monitor
	name = "Shutoff Valve Monitoring"

CAPABILITIES(/datum/tgui_module/shutoff_monitor)
	interface("ShutoffMonitor")
	op("toggle_enable", ui_act("toggle_enable", arg("valve", schema_ref(/obj/machinery/atmospherics/valve/shutoff))), then(PROC_REF(ui_act_toggle_enable)))
	op("toggle_open", ui_act("toggle_open", arg("valve", schema_ref(/obj/machinery/atmospherics/valve/shutoff))), then(PROC_REF(ui_act_toggle_open)))

/datum/tgui_module/shutoff_monitor/proc/ui_act_toggle_enable(datum/act/op/A, valve)
	var/obj/machinery/atmospherics/valve/shutoff/S = valve
	if(!istype(S))
		return FALSE
	S.close_on_leaks = !S.close_on_leaks
	return TRUE

/datum/tgui_module/shutoff_monitor/proc/ui_act_toggle_open(datum/act/op/A, valve)
	var/obj/machinery/atmospherics/valve/shutoff/S = valve
	if(!istype(S))
		return FALSE
	if(S.open)
		S.close()
	else
		S.open()
	return TRUE

/datum/tgui_module/shutoff_monitor/ui_data(datum/act/eval/A)
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
