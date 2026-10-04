
/datum/tgui_module/supermatter_monitor
	name = "Supermatter monitor"
	tgui_id = "SupermatterMonitor"
	var/list/supermatters
	var/tmp/obj/machinery/power/supermatter/active	// Currently selected supermatter crystal.

/datum/tgui_module/supermatter_monitor/New()
	..()
	refresh()

// Refreshes list of active supermatter crystals
/datum/tgui_module/supermatter_monitor/proc/refresh()
	rel_clear(src, nameof(supermatters))
	var/z = get_z(tgui_host())
	if(!z)
		return
	var/valid_z_levels = using_map.get_map_levels(z)
	for(var/obj/machinery/power/supermatter/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		// Delaminating, not within coverage, not on a tile.
		if(S.grav_pulling || S.exploded || !(S.z in valid_z_levels) || !istype(S.loc, /turf/))
			continue
		rel_add(src, nameof(supermatters), S)

	if(!(active() in supermatters))
		rel_clear(src, nameof(active))

/datum/tgui_module/supermatter_monitor/proc/get_status()
	. = SUPERMATTER_INACTIVE
	for(var/obj/machinery/power/supermatter/S in supermatters)
		. = max(., S.get_status())

UI_DATA(/datum/tgui_module/supermatter_monitor, "merge:ui_data_datum_tgui_module_supermatter_monitor{active:num,SM_area:unknown,SM_integrity:unknown,SM_power:num,SM_ambienttemp:unknown,SM_ambientpressure:unknown,SM_EPR:unknown,SM_gas_O2:num,SM_gas_CO2:num,SM_gas_N2:num,SM_gas_PH:num,SM_gas_CH4:num,SM_gas_N2O:num,supermatters:list}")

/// The computed part of /datum/tgui_module/supermatter_monitor's window data (declared on its UI_DATA row).
/datum/tgui_module/supermatter_monitor/proc/ui_data_datum_tgui_module_supermatter_monitor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	if(istype(active(), /obj/machinery/power/supermatter))
		var/turf/T = get_turf(active())
		if(!T)
			rel_clear(src, nameof(active))
			return
		var/datum/gas_mixture/air = T.return_air()
		if(!istype(air))
			rel_clear(src, nameof(active))
			return

		data["active"] = 1
		data["SM_area"] = get_area(active())
		data["SM_integrity"] = active().get_integrity()
		data["SM_power"] = active().power
		data["SM_ambienttemp"] = air.return_temperature()
		data["SM_ambientpressure"] = air.return_pressure()
		data["SM_EPR"] = active().get_epr()
		//data["SM_EPR"] = active.get_epr()
		if(air.total_moles())
			data["SM_gas_O2"] = round(100*LINDA_GAS_AMT(air, GAS_O2)/air.total_moles(),0.01)
			data["SM_gas_CO2"] = round(100*LINDA_GAS_AMT(air, GAS_CO2)/air.total_moles(),0.01)
			data["SM_gas_N2"] = round(100*LINDA_GAS_AMT(air, GAS_N2)/air.total_moles(),0.01)
			data["SM_gas_PH"] = round(100*LINDA_GAS_AMT(air, GAS_PHORON)/air.total_moles(),0.01)
			data["SM_gas_CH4"] = round(100*LINDA_GAS_AMT(air, GAS_CH4)/air.total_moles(),0.01)
			data["SM_gas_N2O"] = round(100*LINDA_GAS_AMT(air, GAS_N2O)/air.total_moles(),0.01) // "sleeping_agent" string is not a LINDA gas id; GAS_N2O = "n2o" is the real id
		else
			data["SM_gas_O2"] = 0
			data["SM_gas_CO2"] = 0
			data["SM_gas_N2"] = 0
			data["SM_gas_PH"] = 0
			data["SM_gas_CH4"] = 0
			data["SM_gas_N2O"] = 0
	else
		var/list/SMS = list()
		for(var/obj/machinery/power/supermatter/S in supermatters)
			var/area/A = get_area(S)
			if(!A)
				continue

			SMS.Add(list(list(
			"area_name" = A.name,
			"integrity" = S.get_integrity(),
			"uid" = S.uid
			)))

		data["active"] = 0
		data["supermatters"] = SMS

	return data

CAPABILITIES(/datum/tgui_module/supermatter_monitor)
	op("clear", ui_act(), then(PROC_REF(native_ui_act_clear)))
	op("refresh", ui_act(), then(PROC_REF(native_ui_act_refresh)))

/datum/tgui_module/supermatter_monitor/proc/native_ui_act_clear(datum/act/op/A)
	rel_clear(src, nameof(/area/looking_glass::active))
	return OP_OK

/datum/tgui_module/supermatter_monitor/proc/native_ui_act_refresh(datum/act/op/A)
	refresh()
	return OP_OK

UI_ACT(/datum/tgui_module/supermatter_monitor, "set", ui_act_set, UI_ARG_NUM("set"))
UI_ACT_PROC(/datum/tgui_module/supermatter_monitor, ui_act_set)
	var/newuid = params["set"]
	for(var/obj/machinery/power/supermatter/S in supermatters)
		if(S.uid == newuid)
			rel_set(src, nameof(/area/looking_glass::active), S)
	. = TRUE

/datum/tgui_module/supermatter_monitor/ntos
	ntos = TRUE

/// Currently selected supermatter crystal. (a relation view: null once that is deleted).
/datum/tgui_module/supermatter_monitor/proc/active() as /obj/machinery/power/supermatter
	return active
