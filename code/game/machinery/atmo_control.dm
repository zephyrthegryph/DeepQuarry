// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

#define SENSOR_PRESSURE		(1<<0)
#define SENSOR_TEMPERATURE	(1<<1)
#define SENSOR_O2			(1<<2)
#define SENSOR_PHORON		(1<<3)
#define SENSOR_N2			(1<<4)
#define SENSOR_CO2			(1<<5)
#define SENSOR_N2O			(1<<6)
#define SENSOR_CH4			(1<<7)

/obj/machinery/air_sensor
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "gsensor1"
	name = "Gas Sensor"
	desc = "Senses atmospheric conditions."

	anchored = TRUE
	var/state = 0

	var/id_tag
	var/frequency = PUMPS_FREQ

	var/on = 1
	var/output = 3
	//Flags:
	// 1 for pressure
	// 2 for temperature
	// Output >= 4 includes gas composition
	// 4 for oxygen concentration
	// 8 for phoron concentration
	// 16 for nitrogen concentration
	// 32 for carbon dioxide concentration

	var/datum/radio_frequency/radio_connection

/obj/machinery/air_sensor/update_icon()
	icon_state = "gsensor[on]"

/// What the sensor reports from `air_sample`, at the resolution it broadcasts.
/obj/machinery/air_sensor/proc/sensor_readings(datum/gas_mixture/air_sample)
	var/list/readings = list()
	if(!air_sample)
		return readings
	if(output&1)
		readings["pressure"] = num2text(round(air_sample.return_pressure(),0.1),)
	if(output&2)
		readings["temperature"] = round(air_sample.return_temperature(),0.1)
	if(output>4)
		var/total_moles = air_sample.total_moles()
		if(total_moles > 0)
			if(output&4)
				readings[GAS_O2] = round(100*LINDA_GAS_AMT(air_sample, GAS_O2)/total_moles,0.1)
			if(output&8)
				readings[GAS_PHORON] = round(100*LINDA_GAS_AMT(air_sample, GAS_PHORON)/total_moles,0.1)
			if(output&16)
				readings[GAS_N2] = round(100*LINDA_GAS_AMT(air_sample, GAS_N2)/total_moles,0.1)
			if(output&32)
				readings[GAS_CO2] = round(100*LINDA_GAS_AMT(air_sample, GAS_CO2)/total_moles,0.1)
			if(output&64)
				readings[GAS_CH4] = round(100*LINDA_GAS_AMT(air_sample, GAS_CH4)/total_moles,0.1)
		else
			readings[GAS_O2] = 0
			readings[GAS_PHORON] = 0
			readings[GAS_N2] = 0
			readings[GAS_CO2] = 0
			readings[GAS_CH4] = 0
	return readings

/// The broadcast, flattened: the sensor's gas watch wakes it only when this changes.
/obj/machinery/air_sensor/proc/current_reading_signature()
	return list2params(sensor_readings(return_air()))

/obj/machinery/air_sensor/machine_step()
	if(on && radio_connection)
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO //radio signal
		signal.data["tag"] = id_tag
		signal.data["timestamp"] = world.time
		var/list/readings = sensor_readings(return_air())
		for(var/key in readings)
			signal.data[key] = readings[key]
		signal.data["sigtype"]="status"
		radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
	register_gas_dependencies()
	return PROCESS_KILL

/obj/machinery/air_sensor/proc/dependency_mask()
	var/mask = 0
	if(output & SENSOR_PRESSURE)
		mask |= GAS_DEPENDENCY_PRESSURE
	if(output & SENSOR_TEMPERATURE)
		mask |= GAS_DEPENDENCY_TEMPERATURE
	if(output & (SENSOR_O2|SENSOR_PHORON|SENSOR_N2|SENSOR_CO2|SENSOR_N2O|SENSOR_CH4))
		mask |= GAS_DEPENDENCY_COMPOSITION
	return mask

/obj/machinery/air_sensor/proc/register_gas_dependencies()
	var/datum/gas_mixture/environment = return_air()
	// Wakes only when the rounded readings it broadcasts would change, not on every revision.
	om_watch_arm_value(src, "gas", environment?.arena_id(), dependency_mask(), CALLBACK(src, PROC_REF(current_reading_signature)), wake_callback = CALLBACK(src, PROC_REF(wake_from_gas)))

/obj/machinery/air_sensor/proc/unregister_gas_dependencies()
	om_watch_disarm(src, "gas")

/obj/machinery/air_sensor/proc/wake_from_gas()
	unregister_gas_dependencies()
	MACHINE_WAKE(src)

/obj/machinery/air_sensor/proc/invalidate_gas_dependencies()
	om_watch_invalidate(src)

/obj/machinery/air_sensor/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	invalidate_gas_dependencies()

/obj/machinery/air_sensor/proc/set_frequency(new_frequency)
	invalidate_gas_dependencies()
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = SSradio.add_object(src, frequency, RADIO_ATMOSIA)

/obj/machinery/air_sensor/Initialize(mapload)
	. = ..()
	if(frequency)
		set_frequency(frequency)

/obj/machinery/air_sensor/Destroy()
	if(SSradio)
		SSradio.remove_object(src,frequency)
	. = ..()

/obj/machinery/air_sensor/wrench_act(mob/user, obj/item/W)
	playsound(src, W.usesound, 50, 1)
	user.visible_message("[user] unfastens \the [src].", span_notice("You have unfastened \the [src]."), "You hear ratcheting.")
	var/obj/item/pipe_gsensor/gsensor = new /obj/item/pipe_gsensor(loc)
	gsensor.id_tag = id_tag
	gsensor.output = output
	qdel(src)
	playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
	return ITEM_INTERACT_SUCCESS

#define ONOFF_TOGGLE(flag) "\[[(output & flag) ? "YES" : "NO"]]"
/obj/machinery/air_sensor/multitool_act(mob/user, obj/item/tool)
	var/list/options = list(
		"Pressure: [ONOFF_TOGGLE(SENSOR_PRESSURE)]" 		= SENSOR_PRESSURE,
		"Temperature: [ONOFF_TOGGLE(SENSOR_TEMPERATURE)]" 	= SENSOR_TEMPERATURE,
		"[GASNAME_O2]: [ONOFF_TOGGLE(SENSOR_O2)]" 			= SENSOR_O2,
		"[GASNAME_PHORON]: [ONOFF_TOGGLE(SENSOR_PHORON)]" 	= SENSOR_PHORON,
		"[GASNAME_N2]: [ONOFF_TOGGLE(SENSOR_N2)]" 			= SENSOR_N2,
		"[GASNAME_CO2]: [ONOFF_TOGGLE(SENSOR_CO2)]" 		= SENSOR_CO2,
		"[GASNAME_N2O]: [ONOFF_TOGGLE(SENSOR_N2O)]" 		= SENSOR_N2O,
		"[GASNAME_CH4]: [ONOFF_TOGGLE(SENSOR_CH4)]" 		= SENSOR_CH4,
		"-SAVE TO BUFFER-" = "multitool"
	)

	om_prompt(src, user, list("kind" = "list", "message" = "[src] has an ID of \"[id_tag]\" and a frequency of [frequency]. What would you like to change?", "title" = "Options!", "choices" = options, "requires" = list(CHECK(/datum/om/check/can_see, 5)), "data" = list("options" = options, "tool" = tool)), PROC_REF(sensor_option_chosen))
	return TRUE

/obj/machinery/air_sensor/proc/sensor_option_chosen(mob/user, answer, datum/om/prompt/ask)
	var/list/options = ask.get("options")
	if(answer in options)
		invalidate_gas_dependencies()
		switch(options[answer])
			if(SENSOR_PRESSURE)
				output ^= SENSOR_PRESSURE
			if(SENSOR_TEMPERATURE)
				output ^= SENSOR_TEMPERATURE
			if(SENSOR_O2)
				output ^= SENSOR_O2
			if(SENSOR_PHORON)
				output ^= SENSOR_PHORON
			if(SENSOR_N2)
				output ^= SENSOR_N2
			if(SENSOR_CO2)
				output ^= SENSOR_CO2
			if(SENSOR_N2O)
				output ^= SENSOR_N2O
			if(SENSOR_CH4)
				output ^= SENSOR_CH4
			if("frequency")
				ask_frequency(user, frequency)
			if("multitool")
				om_prompt_chain(ask, list("kind" = "text", "message" = "Please insert an ID tag for [src], example 'burn_chamber'.", "title" = "Set ID Tag", "default" = id_tag, "max_length" = MAX_NAME_LEN, "requires" = PROMPT_ADJACENT), PROC_REF(sensor_tag_entered))

/obj/machinery/air_sensor/proc/sensor_tag_entered(mob/user, new_tag, datum/om/prompt/ask)
	if(!new_tag)
		return
	id_tag = new_tag
	var/obj/item/multitool/M = ask.get("tool")
	if(istype(M) && M.loc == user)
		M.connectable = src
		to_chat(user, span_notice("You save [src] into [M]'s buffer."))
#undef ONOFF_TOGGLE

/obj/machinery/computer/general_air_control

	icon_keyboard = "atmos_key"
	icon_screen = "tank"
	name = "Computer"
	desc = "Control atmospheric systems, remotely."
	var/frequency = PUMPS_FREQ
	var/list/sensors
	var/list/sensor_information
	var/datum/radio_frequency/radio_connection
	circuit = /obj/item/circuitboard/air_management

/obj/machinery/computer/general_air_control/Destroy()
	if(SSradio)
		SSradio.remove_object(src, frequency)
	. = ..()

/obj/machinery/computer/general_air_control/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

/obj/machinery/computer/general_air_control/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/computer/general_air_control/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]
	if(!id_tag || !LAZYFIND(sensors, id_tag)) return

	LAZYSET(sensor_information, id_tag, signal.data)

/obj/machinery/computer/general_air_control/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "GeneralAtmoControl", name)
		ui.open()

/obj/machinery/computer/general_air_control/tgui_data(mob/user)
	var/list/data = list()
	var/sensors_ui[0]
	if(length(sensors))
		for(var/id_tag in sensors)
			var/long_name = LAZYACCESS(sensors, id_tag)
			var/list/sensor_data = LAZYACCESS(sensor_information, id_tag)
			sensors_ui[++sensors_ui.len] = list("long_name" = long_name, "sensor_data" = sensor_data)
	else
		sensors_ui = null

	data["sensors"] = sensors_ui

	return data

/obj/machinery/computer/general_air_control/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = SSradio.add_object(src, frequency, RADIO_ATMOSIA)

/obj/machinery/computer/general_air_control/multitool_act(mob/user, obj/item/W)
	var/list/options = list("Sensors", "Frequency", "Cancel")
	om_prompt(src, user, list("kind" = "list", "message" = "[src] has a frequency of [frequency]. What would you like to change?", "title" = "Options!", "choices" = options, "requires" = PROMPT_ADJACENT, "data" = list("tool" = W)), PROC_REF(control_option_chosen))
	return TRUE

/// The multitool menu: Inlet, Outlet, Sensors or Frequency.
/obj/machinery/computer/general_air_control/proc/control_option_chosen(mob/user, answer, datum/om/prompt/ask)
	var/obj/item/multitool/tool = ask.get("tool")
	switch(answer)
		if("Inlet")
			configure_inlet(user, tool)
		if("Outlet")
			configure_outlet(user, tool)
		if("Sensors")
			configure_sensors(user, tool)
		if("Frequency")
			ask_frequency(user, frequency)

/obj/machinery/computer/general_air_control/proc/configure_inlet(mob/living/user, obj/item/multitool/tool)
	return

/obj/machinery/computer/general_air_control/proc/configure_outlet(mob/living/user, obj/item/multitool/tool)
	return

/obj/machinery/computer/general_air_control/proc/configure_sensors(mob/living/user, obj/item/multitool/tool)
	to_chat(user, "CONFIGURE SENSOR FUNC")
	om_prompt(src, user, list("kind" = "list", "message" = "Would you like to add or remove a sensor/meter?", "title" = "Configuration", "choices" = list("Add", "Remove","Cancel"), "requires" = PROMPT_ADJACENT, "data" = list("tool" = tool)), PROC_REF(sensor_config_chosen))

/obj/machinery/computer/general_air_control/proc/sensor_config_chosen(mob/living/user, choice, datum/om/prompt/ask)
	var/obj/item/multitool/tool = ask.get("tool")
	switch(choice)
		if("Add")
			// Device must be a meter or gas sensor.
			var/obj/machinery/device = tool.connectable
			if(!device || !(istype(device, /obj/machinery/meter)) && !(istype(device, /obj/machinery/air_sensor)))
				to_chat(user, span_warning("Error: No device in multitool buffer, or incompatible device is not a sensor or meter."))
				return
			ask.put("device", device)
			om_prompt_chain(ask, list("kind" = "text", "message" = "Enter a name for the Sensor/Meter.", "title" = "Name"), PROC_REF(sensor_named))
		if("Remove")
			// Creates an associative mapping of Names to Tags, from Tags to Names.
			var/list/sensor_names = list()
			for(var/tag in sensors)
				sensor_names[LAZYACCESS(sensors, tag)] = tag
			ask.put("names", sensor_names)
			om_prompt_chain(ask, list("kind" = "list", "message" = "Select a sensor/meter to remove", "title" = "Sensor/Meter Removal", "choices" = sensor_names), PROC_REF(sensor_removal_chosen))

/obj/machinery/computer/general_air_control/proc/sensor_named(mob/living/user, device_name, datum/om/prompt/ask)
	var/obj/machinery/device = ask.get("device")
	if(!device_name)
		to_chat(user, span_warning("Error: No name was given for [device]."))
		return
	if(istype(device, /obj/machinery/air_sensor))
		var/obj/machinery/air_sensor/AS = device
		LAZYSET(sensors, AS.id_tag, device_name)
	else
		var/obj/machinery/meter/M = device
		LAZYSET(sensors, M.id, device_name)
	to_chat(user, span_notice("You have added the [device] to the [src] under the name [device_name]!"))

/obj/machinery/computer/general_air_control/proc/sensor_removal_chosen(mob/living/user, to_remove, datum/om/prompt/ask)
	ask.put("remove", to_remove)
	om_prompt_chain(ask, list("message" = "Are you sure you want to remove the sensor/meter '[to_remove]'?", "title" = "Warning", "choices" = list("Yes", "No")), PROC_REF(sensor_removal_confirmed))

/obj/machinery/computer/general_air_control/proc/sensor_removal_confirmed(mob/living/user, confirm, datum/om/prompt/ask)
	if(confirm != "Yes")
		return
	var/list/sensor_names = ask.get("names")
	var/to_remove = ask.get("remove")
	LAZYREMOVE(sensors, sensor_names[to_remove])
	to_chat(user, span_notice("Successfully removed sensor/meter with name [to_remove]"))

/obj/machinery/computer/general_air_control/Initialize(mapload)
	. = ..()
	if(frequency)
		set_frequency(frequency)

/obj/machinery/computer/general_air_control/large_tank_control
	icon = 'icons/obj/computer.dmi'
	frequency = PUBLIC_LOW_FREQ
	name = "Large Tank Computer"
	desc = "Controls various devices for managing a gas tank."
	var/input_tag
	var/output_tag
	var/list/input_info
	var/list/output_info
	var/input_flow_setting = 200
	var/pressure_setting = ONE_ATMOSPHERE * 45
	circuit = /obj/item/circuitboard/air_management/tank_control

/obj/machinery/computer/general_air_control/large_tank_control/tgui_data(mob/user)
	var/list/data = ..()

	data["tanks"] = 1

	if(input_info)
		data["input_info"] = list("power" = input_info["power"], "volume_rate" = round(input_info["volume_rate"], 0.1))
	else
		data["input_info"] = null

	if(output_info)
		data["output_info"] = list("power" = output_info["power"], "output_pressure" = output_info["internal"])
	else
		data["output_info"] = null

	data["input_flow_setting"] = round(input_flow_setting, 0.1)
	data["pressure_setting"] = pressure_setting
	data["max_pressure"] = 50*ONE_ATMOSPHERE
	data["max_flowrate"] = ATMOS_DEFAULT_VOLUME_PUMP + 500

	return data

/obj/machinery/computer/general_air_control/large_tank_control/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]

	if(input_tag == id_tag)
		input_info = signal.data
	else if(output_tag == id_tag)
		output_info = signal.data
	else
		..(signal)

/obj/machinery/computer/general_air_control/large_tank_control/tgui_act(action, params)
	if(..())
		return TRUE

	switch(action)
		if("adj_pressure")
			var/new_pressure = text2num(params["adj_pressure"])
			pressure_setting = between(0, new_pressure, 50*ONE_ATMOSPHERE)
			return TRUE

		if("adj_input_flow_rate")
			var/new_flow = text2num(params["adj_input_flow_rate"])
			input_flow_setting = between(0, new_flow, ATMOS_DEFAULT_VOLUME_PUMP + 500) //default flow rate limit for air injectors
			return TRUE

	if(!radio_connection)
		return FALSE
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.source = src
	switch(action)
		if("in_refresh_status")
			input_info = null
			signal.data = list ("tag" = input_tag, "status" = 1)
			. = TRUE

		if("in_toggle_injector")
			input_info = null
			signal.data = list ("tag" = input_tag, "power_toggle" = 1)
			. = TRUE

		if("in_set_flowrate")
			input_info = null
			signal.data = list ("tag" = input_tag, "set_volume_rate" = "[input_flow_setting]")
			. = TRUE

		if("out_refresh_status")
			output_info = null
			signal.data = list ("tag" = output_tag, "status" = 1)
			. = TRUE

		if("out_toggle_power")
			output_info = null
			signal.data = list ("tag" = output_tag, "power_toggle" = 1)
			. = TRUE

		if("out_set_pressure")
			output_info = null
			signal.data = list ("tag" = output_tag, "set_internal_pressure" = "[pressure_setting]")
			. = TRUE

	signal.data["sigtype"]="command"
	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

/obj/machinery/computer/general_air_control/large_tank_control/multitool_act(mob/user, obj/item/W)
	. = ITEM_INTERACT_SUCCESS
	var/list/options =  list("Inlet", "Outlet", "Sensors", "Frequency", "Cancel")
	om_prompt(src, user, list("kind" = "list", "message" = "[src] has a frequency of [frequency]. What would you like to change?", "title" = "Configuration", "choices" = options, "requires" = PROMPT_ADJACENT, "data" = list("tool" = W)), PROC_REF(control_option_chosen))
	return TRUE

/obj/machinery/computer/general_air_control/large_tank_control/configure_outlet(mob/living/user, obj/item/multitool/tool)
	om_prompt(src, user, list("message" = "Would you like to set an outlet or clear it?", "title" = "Configuration", "choices" = list("Set", "Clear", "Cancel"), "requires" = PROMPT_ADJACENT, "data" = list("tool" = tool)), PROC_REF(outlet_choice_made))

/obj/machinery/computer/general_air_control/large_tank_control/proc/outlet_choice_made(mob/living/user, choice, datum/om/prompt/ask)
	var/obj/item/multitool/tool = ask.get("tool")
	switch(choice)
		if ("Set")
			to_chat(user, span_notice("The buffer is [tool.connectable]"))
			if (!istype(tool.connectable, /obj/machinery/atmospherics/unary/vent_pump))
				to_chat(user, span_notice("Error: Buffer is either empty, or object in buffer is invalid. Device should be a Unary Vent."))
				return

			var/obj/machinery/atmospherics/unary/vent_pump/pump = tool.connectable
			output_tag = pump.id_tag
			pump.external_pressure_bound = 0
			pump.external_pressure_bound_default = 0
			to_chat(user, span_notice("You have set the outlet!"))
			return

		if ("Clear")
			output_tag = null
			to_chat(user, span_notice("You have cleared the outlet!"))
			return

/obj/machinery/computer/general_air_control/large_tank_control/configure_inlet(mob/living/user, obj/item/multitool/tool)
	om_prompt(src, user, list("message" = "Would you like to set an inlet or clear it?", "title" = "Configuration", "choices" = list("Set", "Clear", "Cancel"), "requires" = PROMPT_ADJACENT, "data" = list("tool" = tool)), PROC_REF(inlet_choice_made))

/obj/machinery/computer/general_air_control/large_tank_control/proc/inlet_choice_made(mob/living/user, choice, datum/om/prompt/ask)
	var/obj/item/multitool/tool = ask.get("tool")
	switch(choice)
		if ("Set")
			if (!istype(tool.connectable, /obj/machinery/atmospherics/unary/outlet_injector))
				to_chat(user, span_notice("Error: Buffer is either empty, or object in buffer is invalid. Device should be Injector"))
				return

			var/obj/machinery/atmospherics/unary/outlet_injector/injector = tool.connectable
			input_tag = injector.id
			to_chat(user, span_notice("You have set the inlet"))
			return

		if ("Clear")
			input_tag = null
			to_chat(user, span_notice("You have cleared the inlet!"))
			return

/obj/machinery/computer/general_air_control/supermatter_core
	icon = 'icons/obj/computer.dmi'
	frequency = ENGINE_FREQ
	var/input_tag
	var/output_tag
	var/list/input_info
	var/list/output_info
	var/input_flow_setting = 700
	var/pressure_setting = 100
	circuit = /obj/item/circuitboard/air_management/supermatter_core

/obj/machinery/computer/general_air_control/supermatter_core/tgui_data(mob/user)
	var/list/data = ..()
	data["core"] = 1

	if(input_info)
		data["input_info"] = list("power" = input_info["power"], "volume_rate" = round(input_info["volume_rate"], 0.1))
	else
		data["input_info"] = null

	if(output_info)
		// Yes, TECHNICALLY this is not output pressure, it's a pressure LIMIT. HOWEVER. The fact that the UI uses "output_pressure"
		// in EXACTLY THE SAME WAY as "pressure_limit" means this should just pass it as the other fucking data argument because holy shit what the
		// fuck
		data["output_info"] = list("power" = output_info["power"], "output_pressure" = output_info["external"])
	else
		data["output_info"] = null

	data["input_flow_setting"] = round(input_flow_setting, 0.1)
	data["pressure_setting"] = pressure_setting
	data["max_pressure"] = 10*ONE_ATMOSPHERE
	data["max_flowrate"] = ATMOS_DEFAULT_VOLUME_PUMP + 500

	return data

/obj/machinery/computer/general_air_control/supermatter_core/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]

	if(input_tag == id_tag)
		input_info = signal.data
	else if(output_tag == id_tag)
		output_info = signal.data
	else
		..(signal)

/obj/machinery/computer/general_air_control/supermatter_core/tgui_act(action, params)
	if(..())
		return TRUE

	switch(action)
		if("adj_pressure")
			var/new_pressure = text2num(params["adj_pressure"])
			pressure_setting = between(0, new_pressure, 10*ONE_ATMOSPHERE)
			return TRUE

		if("adj_input_flow_rate")
			var/new_flow = text2num(params["adj_input_flow_rate"])
			input_flow_setting = between(0, new_flow, ATMOS_DEFAULT_VOLUME_PUMP + 500) //default flow rate limit for air injectors
			return TRUE

	if(!radio_connection)
		return FALSE
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.source = src
	switch(action)
		if("in_refresh_status")
			input_info = null
			signal.data = list ("tag" = input_tag, "status" = 1)
			. = TRUE

		if("in_toggle_injector")
			input_info = null
			signal.data = list ("tag" = input_tag, "power_toggle" = 1)
			. = TRUE

		if("in_set_flowrate")
			input_info = null
			signal.data = list ("tag" = input_tag, "set_volume_rate" = "[input_flow_setting]")
			. = TRUE

		if("out_refresh_status")
			output_info = null
			signal.data = list ("tag" = output_tag, "status" = 1)
			. = TRUE

		if("out_toggle_power")
			output_info = null
			signal.data = list ("tag" = output_tag, "power_toggle" = 1)
			. = TRUE

		if("out_set_pressure")
			output_info = null
			signal.data = list ("tag" = output_tag, "set_external_pressure" = "[pressure_setting]", "checks" = 1)
			. = TRUE

	signal.data["sigtype"]="command"
	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

/obj/machinery/computer/general_air_control/supermatter_core/multitool_act(mob/user, obj/item/W)
	. = ITEM_INTERACT_SUCCESS
	var/list/options =  list("Inlet", "Outlet", "Sensors", "Frequency")
	om_prompt(src, user, list("kind" = "list", "message" = "[src] has a frequency of [frequency]. What would you like to change?", "title" = "Configuration", "choices" = options, "requires" = PROMPT_ADJACENT, "data" = list("tool" = W)), PROC_REF(control_option_chosen))
	return TRUE

/obj/machinery/computer/general_air_control/supermatter_core/configure_outlet(mob/living/user, obj/item/multitool/tool)
	om_prompt(src, user, list("message" = "Would you like to set an outlet or clear it?", "title" = "Configuration", "choices" = list("Set", "Clear", "Cancel"), "requires" = PROMPT_ADJACENT, "data" = list("tool" = tool)), PROC_REF(outlet_choice_made))

/obj/machinery/computer/general_air_control/supermatter_core/proc/outlet_choice_made(mob/living/user, choice, datum/om/prompt/ask)
	var/obj/item/multitool/tool = ask.get("tool")
	switch(choice)
		if ("Set")
			if (!istype(tool.connectable, /obj/machinery/atmospherics/unary/vent_pump))
				to_chat(user, span_warning("Error: Buffer is either empty, or object in buffer is invalid. Device should be Air Vent"))
				return

			var/obj/machinery/atmospherics/unary/vent_pump/pump = tool.connectable
			output_tag = pump.id_tag
			pump.external_pressure_bound = 0
			pump.external_pressure_bound_default = 0
			to_chat(user, span_notice("You have set the outlet!"))
			return

		if ("Clear")
			output_tag = null
			to_chat(user, span_notice("You have cleared the outlet!"))
			return

/obj/machinery/computer/general_air_control/supermatter_core/configure_inlet(mob/living/user, obj/item/multitool/tool)
	om_prompt(src, user, list("message" = "Would you like to set an inlet or clear it?", "title" = "Configuration", "choices" = list("Set", "Clear", "Cancel"), "requires" = PROMPT_ADJACENT, "data" = list("tool" = tool)), PROC_REF(inlet_choice_made))

/obj/machinery/computer/general_air_control/supermatter_core/proc/inlet_choice_made(mob/living/user, choice, datum/om/prompt/ask)
	var/obj/item/multitool/tool = ask.get("tool")
	switch(choice)
		if ("Set")
			to_chat(user, span_notice("The buffer is [tool.connectable]"))
			if (!istype(tool.connectable, /obj/machinery/atmospherics/unary/outlet_injector))
				to_chat(user, span_warning("Error: Buffer is either empty, or object in buffer is invalid. Device should be Injector"))
				return

			var/obj/machinery/atmospherics/unary/outlet_injector/injector = tool.connectable
			input_tag = injector.id
			to_chat(user, span_notice("You have set the inlet!"))
			return

		if ("Clear")
			input_tag = null
			to_chat(user, span_notice("You have cleared the inlet!"))
			return

/obj/machinery/computer/general_air_control/fuel_injection
	icon = 'icons/obj/computer.dmi'
	icon_screen = "alert:0"
	var/device_tag
	var/list/device_info
	var/automation = 0
	var/cutoff_temperature = 2000
	var/on_temperature = 1200
	circuit = /obj/item/circuitboard/air_management/injector_control

/// Machine pipeline (machine_pipeline.dm, step/fuel_injection): a timed stage while automation is
/// on -- each frame re-reads the latest sensor broadcasts and commands the injectors -- and parked
/// otherwise; toggling automation wakes it.
/obj/machinery/computer/general_air_control/fuel_injection/machine_step()
	if(!automation || !radio_connection)
		return PROCESS_KILL
	if(automation)

		var/injecting = 0
		for(var/id_tag in sensor_information)
			var/list/data = LAZYACCESS(sensor_information, id_tag)
			if(data["temperature"])
				if(data["temperature"] >= cutoff_temperature)
					injecting = 0
					break
				if(data["temperature"] <= on_temperature)
					injecting = 1

		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO //radio signal
		signal.source = src

		signal.data = list(
			"tag" = device_tag,
			"power" = injecting,
			"sigtype"="command"
		)

		radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

/obj/machinery/computer/general_air_control/fuel_injection/tgui_data(mob/user)
	var/list/data = ..()
	data["fuel"] = 1
	data["automation"] = automation

	if(device_info)
		data["device_info"] = list("power" = device_info["power"], "volume_rate" = device_info["volume_rate"])
	else
		data["device_info"] = null

	return data

/obj/machinery/computer/general_air_control/fuel_injection/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]

	if(device_tag == id_tag)
		device_info = signal.data
	else
		..(signal)

/obj/machinery/computer/general_air_control/fuel_injection/tgui_act(action, params)
	if(..())
		return TRUE

	switch(action)
		if("refresh_status")
			device_info = null
			if(!radio_connection)
				return FALSE

			var/datum/signal/signal = new
			signal.transmission_method = TRANSMISSION_RADIO //radio signal
			signal.source = src
			signal.data = list(
				"tag" = device_tag,
				"status" = 1,
				"sigtype"="command"
			)
			radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
			. = TRUE

		if("toggle_automation")
			automation = !automation
			MACHINE_WAKE(src)
			. = TRUE

		if("toggle_injector")
			device_info = null
			if(!radio_connection)
				return FALSE

			var/datum/signal/signal = new
			signal.transmission_method = TRANSMISSION_RADIO //radio signal
			signal.source = src
			signal.data = list(
				"tag" = device_tag,
				"power_toggle" = 1,
				"sigtype"="command"
			)

			radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
			. = TRUE

		if("injection")
			if(!radio_connection)
				return FALSE

			var/datum/signal/signal = new
			signal.transmission_method = TRANSMISSION_RADIO //radio signal
			signal.source = src
			signal.data = list(
				"tag" = device_tag,
				"inject" = 1,
				"sigtype"="command"
			)

			radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
			. = TRUE

#undef SENSOR_PRESSURE
#undef SENSOR_TEMPERATURE
#undef SENSOR_O2
#undef SENSOR_PHORON
#undef SENSOR_N2
#undef SENSOR_CO2
#undef SENSOR_N2O
#undef SENSOR_CH4

/obj/machinery/computer/general_air_control/fuel_injection/step_has_work()
	return automation && radio_connection

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/air_sensor/arm_wakes()
	..()
	register_gas_dependencies()
